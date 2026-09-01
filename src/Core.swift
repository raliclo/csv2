// =====================================================================
//  Core.swift — bytes, errors, the RFC 4180 parser, and the writer
//  Core.swift — 位元組、錯誤、RFC 4180 解析器與寫出器
//
//  Everything here works on bytes, never on String. The plan's reason:
//  UTF-8 is self-synchronising, so a byte-level parser handles emoji and
//  any multi-byte sequence for free, while decoding to String first is
//  both slower and more likely to be wrong -- and it silently replaces
//  non-UTF-8 input with U+FFFD, which is data loss reported as success.
//  此處一律以位元組處理，絕不轉成 String。計畫給的理由：UTF-8 是自同步的，
//  因此位元組層級的解析器天生就正確處理 emoji 與任何多位元組序列；先解碼成
//  String 不但較慢也更容易出錯——而且它會把非 UTF-8 輸入靜默換成 U+FFFD，
//  那是「以成功回報的資料損毀」。
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - Errors / 錯誤
// ---------------------------------------------------------------------

/// Every failure path ends here. The tool never repairs malformed input and
/// never continues past a problem it cannot describe.
/// 所有失敗路徑都到這裡。本工具不修復格式錯誤的輸入，也不會越過一個它無法
/// 描述的問題繼續執行。
struct CSV2Error: Error, CustomStringConvertible {
    let message: String
    let messageZh: String
    init(_ en: String, _ zh: String) { message = en; messageZh = zh }
    var description: String { "\(message) / \(messageZh)" }
}

func fault(_ en: String, _ zh: String) -> CSV2Error { CSV2Error(en, zh) }

// ---------------------------------------------------------------------
// MARK: - Byte constants / 位元組常數
// ---------------------------------------------------------------------

let BYTE_COMMA: UInt8 = 0x2C
let BYTE_DQUOTE: UInt8 = 0x22
let BYTE_LF: UInt8 = 0x0A
let BYTE_CR: UInt8 = 0x0D
let BYTE_BACKSLASH: UInt8 = 0x5C
/// Only ever used to RECOGNISE a line someone meant as a comment, never to
/// skip one. CSV has no comment syntax and `#id` is a legal column name, so
/// treating this byte as anything but data would mean guessing which lines
/// are data -- the guess this tool exists to refuse. It appears solely inside
/// two refusal messages, to say WHY the count did not match. KP.
/// 這個位元組只被用來「認出」一行別人打算當註解的東西，從不用來跳過它。CSV 沒有註解語法，
/// 而 `#id` 是合法的欄名，因此把這個位元組當成資料以外的任何東西，就等於去猜哪些行是資料
/// ——那正是這個工具存在所要拒絕的猜測。它只出現在兩則拒絕訊息裡，用來說出「為什麼欄數對不上」。KP。
let BYTE_HASH: UInt8 = 0x23
let BYTE_SPACE: UInt8 = 0x20
let BYTE_TAB: UInt8 = 0x09
let BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

// ---------------------------------------------------------------------
// MARK: - Echoing a value in an error message / 錯誤訊息中回顯欄位值
// ---------------------------------------------------------------------

/// Truncate on a grapheme cluster boundary, never mid-sequence. A family
/// emoji is 25 bytes, 7 code points and ONE cluster; cutting it by bytes
/// yields half a family and an invalid UTF-8 stream. A tool that produces
/// mojibake while reporting an error sends you looking the wrong way.
/// 一律在 grapheme cluster 邊界截斷。家庭 emoji 是 25 位元組、7 個碼位、
/// 一個 cluster；按位元組切會得到半個家庭與不合法的 UTF-8。一個在報告錯誤時
/// 自己產生亂碼的工具，會讓人去查錯的方向。
/// `limit: nil` means no truncation at all. The log passes nil, because an
/// audit trail that silently drops the middle of a value is not one -- the
/// README promised the old and new values "in full" while this cut them at 40
/// characters, and `status_notes`, the column whose corruption is the reason
/// this project exists, runs to 878 bytes in the real fixture. Round 38.
/// `limit: nil` 表示完全不截斷。log 傳的就是 nil，因為一份會安靜地把值的中段丟掉的稽核
/// 軌跡不算稽核軌跡——README 承諾新舊值「完整記錄」，而這裡在第 40 個字元把它們切斷，
/// 而 `status_notes`（這個專案存在的理由就是那一欄被改壞）在真實素材裡長達 878 bytes。
/// 第 38 回合。
func echoValue(_ bytes: [UInt8], limit: Int? = 40) -> String {
    guard let s = String(bytes: bytes, encoding: .utf8) else {
        // Not UTF-8. Render as hex so the message stays printable rather
        // than emitting raw bytes into someone's terminal.
        // 非 UTF-8，改以十六進位呈現，避免把原始位元組吐進終端機。
        let head = limit.map { Array(bytes.prefix($0)) } ?? bytes
        let hex = head.map { String(format: "%02x", $0) }.joined(separator: " ")
        let cut = limit.map { bytes.count > $0 } ?? false
        return "<non-UTF-8: \(hex)\(cut ? " …" : "")>"
    }
    guard let limit, s.count > limit else { return s }
    // Swift's Character IS a grapheme cluster, so prefix() cuts on a
    // cluster boundary by construction.
    // Swift 的 Character 就是 grapheme cluster，因此 prefix() 天生切在
    // cluster 邊界上。
    return String(s.prefix(limit)) + "…[+\(s.count - limit) more chars]"
}

/// Above this, a logged value gets a WARN naming its size -- and is still
/// written in full. The threshold is not a cap: it is the point at which
/// someone should know their audit trail just grew by a megabyte, which is a
/// different thing from deciding for them what to keep.
/// 超過這個大小，被記錄的值會附帶一行 WARN 說明它的大小——而且**仍然完整寫出**。
/// 這個門檻不是上限：它是「有人該知道自己的稽核軌跡剛剛長了一 MB」的那個點，
/// 而那與「替他決定該留下什麼」是兩回事。
let LOG_VALUE_WARN_BYTES = 1 << 20

// ---------------------------------------------------------------------
// MARK: - Format / 格式
// ---------------------------------------------------------------------

/// The format is a DECLARED fact taken from the file extension, never a
/// guess made from the content. No heuristic can reliably tell "the second
/// row is a Chinese title" from "the second row is the first record", and
/// guessing wrong eats a record as a header without reporting anything.
/// 格式是由副檔名宣告的事實，絕不從內容猜測。沒有任何啟發式能可靠分辨
/// 「第二列是中文標題」與「第二列是第一筆資料」，而猜錯會把一筆資料當成
/// 標頭吃掉且不報錯。
public enum Format: String, Sendable {
    case csv
    case csv2
    /// A file with no suffix: one column, no header rows, and the line's bytes
    /// are the value. Phase 8b.
    ///
    /// It is NOT a one-column `.csv2` in its escaping, and that difference is
    /// the whole of what had to be decided. Measured 2026-08-26: with the
    /// documented `--headers 1`, the first line of such a file is EATEN as a
    /// header; a comma in a path turns a `find` dump into a two-column table
    /// that then fails on the first line without one; and if the escaping were
    /// `.csv2`'s, a line holding a literal `\n` would change meaning on the
    /// way in. So: zero header rows, no comma splitting, no quote processing,
    /// nothing unescaped.
    ///
    /// 一個沒有副檔名的檔案：一欄、沒有標頭列，而那一行的位元組就是值。第 8b 階段。
    /// 它在**跳脫**上不是「一欄的 .csv2」，而那個差別正是必須被定案的全部。2026-08-26 量測：
    /// 用有記載的 `--headers 1`，這種檔案的第一行會被當成標頭吃掉；路徑裡的一個逗號會把一份
    /// `find` 輸出變成兩欄的表，接著在第一個沒有逗號的行上失敗；而如果跳脫用 `.csv2` 那一套，
    /// 一行含字面 `\n` 的內容在讀進來的路上就會改變意思。因此：零列標頭、逗號不切分、不處理引號、
    /// 什麼都不解跳脫。
    case lines

    public var headerRows: Int {
        switch self {
        case .csv2:  return 2
        case .csv:   return 1
        case .lines: return 0
        }
    }

    /// ONE suffix test, case-insensitive, used for reading and for writing.
    ///
    /// It was case-sensitive here and case-insensitive in `declaresFormat`
    /// for one day, and that day produced a message that is false: `-o
    /// x.CSV2` was refused with "x.CSV2 declares a format with a header"
    /// while `-i x.CSV2` was refused for declaring NOTHING. Worse, the
    /// never-convert guard reads THIS function, so `-r -t -i one_header.csv
    /// -o conv.CSV2` was accepted at rc=0 -- and on a case-insensitive
    /// filesystem `conv.CSV2` and `conv.csv2` are one inode, so reading it
    /// back ate a record as header row 0b and the meta line reported the
    /// smaller count with confidence.
    ///
    /// The old rule was "the check is case-sensitive, so a file named .CSV
    /// needs --headers too". Nothing in "declared, never detected" requires
    /// that: matching `.CSV` case-insensitively is still reading the name the
    /// caller gave, not guessing from content. And on the two platforms where
    /// `S.CSV` and `s.csv` are the same file, treating them as different
    /// formats is not a rule anyone can act on.
    ///
    /// 一個副檔名判斷，大小寫不敏感，讀取與寫入共用。
    ///
    /// 它曾經在這裡是大小寫敏感、在 `declaresFormat` 是不敏感，而那一天產生了一則假的訊息：
    /// `-o x.CSV2` 被以「x.CSV2 宣告了一個帶標頭的格式」拒絕，而 `-i x.CSV2` 被以「它什麼都
    /// 沒有宣告」拒絕。更糟的是，「絕不轉換格式」那道守衛讀的就是這個函式，於是
    /// `-r -t -i 單列標頭.csv -o conv.CSV2` 以 rc=0 被接受——而在大小寫不敏感的檔案系統上，
    /// `conv.CSV2` 與 `conv.csv2` 是同一個 inode，於是讀回去時一筆紀錄被當成標頭列 0b 吃掉，
    /// 而 meta 那一行很有把握地回報了那個比較小的數字。
    ///
    /// 舊規則是「這個檢查區分大小寫，因此名為 .CSV 的檔案也需要 --headers」。而「由宣告決定、
    /// 絕不偵測」這件事並不要求那樣：以大小寫不敏感的方式匹配 `.CSV`，讀的仍然是呼叫端給的
    /// 那個名字，不是從內容去猜。而在「`S.CSV` 與 `s.csv` 是同一個檔案」的那兩個平台上，
    /// 把它們當成兩種格式，不是任何人能夠據以行動的規則。
    /// Public because the alternative is a caller writing its own copy of
    /// "the suffix declares the format" -- and that copy drifts away from this
    /// one with nothing to report it. This rule changed on 2026-08-26 (a
    /// suffix that is neither .csv nor .csv2 became a one-column list) and any
    /// copy taken before that is now wrong while still compiling.
    /// 公開它，因為另一條路是呼叫端自己抄一份「副檔名宣告格式」的規則——而那份複製品會與這一份
    /// 反向漂移，卻沒有任何東西會回報。這條規則在 2026-08-26 改過（既不是 .csv 也不是 .csv2 的
    /// 副檔名成為「一欄的行清單」），任何在那之前抄走的複製品，現在都是錯的，而且照樣編得過。
    public static func from(path: String) -> Format? {
        let lower = path.lowercased()
        if lower.hasSuffix(".csv2") { return .csv2 }
        if lower.hasSuffix(".csv") { return .csv }
        return nil
    }

    /// True when the extension makes a promise about the content, so writing
    /// data rows without a header there would make the file lie about itself.
    ///
    /// The same case-insensitive test as `from(path:)`, asked as a yes/no.
    /// The two were briefly different -- see the note there -- and one day of
    /// that was enough to produce both a false message and a silent record
    /// loss.
    ///
    /// With the case-sensitive test here, `-o sel.csv2` was refused for
    /// writing a headerless selection and `-o SEL.CSV2` was accepted -- same
    /// directory, same filesystem, same file on macOS and Windows -- and the
    /// result read back as two data records eaten as header rows, at rc=0.
    /// The other half of the walk-around was `-o sel_nosuffix` followed by a
    /// rename, which is what a Makefile writing `$@.tmp` does by default; that
    /// one this cannot catch, and the README says so.
    ///
    /// 大小寫「不敏感」，而且刻意與 `from(path:)` 不是同一個判斷。「讀取」問的是「呼叫端
    /// 宣告了什麼」，而 csv2 不猜，因此 `-i S.CSV` 仍然需要 `--headers`。「寫入」問的是
    /// 「下一個讀者會認為這個檔案是什麼」，而下一個讀者可能是試算表，也可能是一個在
    /// 大小寫不敏感的檔案系統上的 csv2——在那裡 `SEL.CSV2` 與 `sel.csv2` 是同一個名字、
    /// 同一個檔案。
    ///
    /// 這裡原本是大小寫敏感的判斷，於是 `-o sel.csv2` 因為「寫入不帶標頭的選取」而被拒絕，
    /// 而 `-o SEL.CSV2` 被接受——同一個目錄、同一個檔案系統，在 macOS 與 Windows 上還是同一個
    /// 檔案——而寫出來的結果讀回去時，兩筆資料被當成標頭列吃掉，rc=0。這個繞道的另一半是
    /// 「先寫成 sel_nosuffix 再改名」，那正是一個寫 `$@.tmp` 的 Makefile 預設會做的事；
    /// 那一半這裡攔不到，而 README 說了。
    static func declaresFormat(path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".csv") || lower.hasSuffix(".csv2")
    }
}

// ---------------------------------------------------------------------
// MARK: - Field and Record / 欄位與紀錄
// ---------------------------------------------------------------------

/// `raw` is the field exactly as it appeared in the input, quotes included.
/// Keeping it is what makes byte-identical round-trip possible: a field that
/// was quoted without needing to be stays quoted, so `csv2 -r` does not
/// rewrite a file it was only asked to read.
/// `raw` 是該欄位在輸入中的原樣（含引號）。保留它才可能做到逐位元相同的
/// round-trip：本來就被加了引號、實際上不需要引號的欄位會維持原樣，於是
/// `csv2 -r` 不會改寫一個它只是被要求讀取的檔案。
public struct Field: Sendable {
    public var raw: [UInt8]?
    public var value: [UInt8]

    public init(value: [UInt8], raw: [UInt8]? = nil) {
        self.value = value
        self.raw = raw
    }

    /// Any edit drops `raw`: the stored bytes no longer describe the value.
    /// 任何修改都會丟掉 `raw`：原樣的位元組已不再描述這個值。
    public mutating func set(_ v: [UInt8]) { value = v; raw = nil }
}

public struct Record: Sendable {
    public var fields: [Field]
    /// Byte offset of the record's first byte. / 該筆第一個位元組的偏移量。
    public var offset: Int = 0
    /// Physical line the record starts on, 1-based. / 該筆起始的物理行號，1-based。
    public var line: Int = 1
    /// 1-based data record number; 0 for header rows. / 1-based 資料紀錄號，標頭為 0。
    public var number: Int = 0
    /// Which header row this is, when it is one: 0 for the English row, 1 for
    /// the Traditional Chinese row. nil for data. The report needs to tell them
    /// apart -- printing `0` for both made two identical lines that no reader
    /// could use, which is what `0a` / `0b` in the plan is for.
    /// 這是第幾列標頭（若它是標頭）：0 為英文列、1 為繁體中文列；資料為 nil。
    /// 報告必須能分辨兩者——兩列都印 `0` 會產生兩行完全相同、讀者無從使用的輸出，
    /// 而那正是計畫中 `0a` / `0b` 要解決的。
    public var headerRow: Int? = nil

    var count: Int { fields.count }
}

// ---------------------------------------------------------------------
// MARK: - csv2 backslash escaping / csv2 的反斜線跳脫
// ---------------------------------------------------------------------

/// `.csv2` holds one record per line, so a cell may not contain a raw
/// newline. Escaping is the same convention PostgreSQL's `COPY ... TEXT`
/// and IANA's text/tab-separated-values use; it is not an invention.
/// `.csv2` 一筆一行，因此儲存格內不得含原始換行。跳脫方式與 PostgreSQL 的
/// `COPY ... TEXT` 及 IANA 的 text/tab-separated-values 相同，並非發明。
enum CSV2Escape {
    static func escape(_ v: [UInt8]) -> [UInt8] {
        // The common case is a cell with none of these; check first so the
        // usual path allocates nothing.
        // 多數儲存格一個都不含，先檢查，讓常見路徑不做任何配置。
        var needs = false
        for b in v where b == BYTE_BACKSLASH || b == BYTE_LF || b == BYTE_CR {
            needs = true
            break
        }
        if !needs { return v }
        var out = [UInt8]()
        out.reserveCapacity(v.count + 8)
        for b in v {
            switch b {
            case BYTE_BACKSLASH: out.append(BYTE_BACKSLASH); out.append(0x5C)
            case BYTE_LF: out.append(BYTE_BACKSLASH); out.append(0x6E) // \n
            case BYTE_CR: out.append(BYTE_BACKSLASH); out.append(0x72) // \r
            default: out.append(b)
            }
        }
        return out
    }

    /// An undefined escape (`\q`) is an ERROR, not "keep it as written".
    /// Keeping it would let two different byte sequences read back as the
    /// same value, which destroys losslessness.
    /// 未定義的跳脫序列（`\q`）是錯誤，不是「原樣保留」。原樣保留會讓兩個
    /// 不同的位元組序列讀回同一個值，破壞無損性。
    static func unescape(_ v: [UInt8], at: String, atZh: String, field: Int) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(v.count)
        var i = 0
        while i < v.count {
            let b = v[i]
            if b != BYTE_BACKSLASH { out.append(b); i += 1; continue }
            guard i + 1 < v.count else {
                throw fault(
                    "\(at), field \(field): trailing lone backslash; write it as \\\\",
                    "\(atZh)第 \(field) 欄：結尾有孤立的反斜線，應寫成 \\\\")
            }
            let n = v[i + 1]
            switch n {
            case 0x6E: out.append(BYTE_LF)
            case 0x72: out.append(BYTE_CR)
            case 0x5C: out.append(BYTE_BACKSLASH)
            default:
                let seq = String(bytes: [BYTE_BACKSLASH, n], encoding: .utf8) ?? "\\?"
                throw fault(
                    "\(at), field \(field): undefined escape sequence \(seq); .csv2 defines only \\n, \\r and \\\\",
                    "\(atZh)第 \(field) 欄：未定義的跳脫序列 \(seq)；.csv2 只定義 \\n、\\r 與 \\\\")
            }
            i += 2
        }
        return out
    }
}

// ---------------------------------------------------------------------
// MARK: - Encoding a field for output / 欄位的輸出編碼
// ---------------------------------------------------------------------

extension Record {
    /// The one a WRITER needs. `Field` had a public init and this did not, so
    /// a caller outside the module could take a Record apart and could not
    /// build one -- and `FieldEncoder.encodeRecord` takes a Record. Reported
    /// by the SoftPCB session, which needed exactly this to turn strings into
    /// a logged row. The other fields keep their defaults on purpose: offset,
    /// line and number describe where a record CAME FROM, and a record being
    /// written has not come from anywhere.
    /// 這是**寫入端**需要的那一個。`Field` 有一個 public init 而這裡沒有，於是 module 外面的呼叫端
    /// 拆得開一個 Record、卻建不出一個——而 `FieldEncoder.encodeRecord` 收的正是 Record。由
    /// SoftPCB session 回報，它需要的正是這個，用來把字串變成一列要寫進日誌的紀錄。其餘欄位刻意
    /// 保留預設值：offset、line、number 描述的是一筆紀錄「從哪裡來」，而一筆正要被寫出去的紀錄
    /// 哪裡都還沒來過。
    public init(fields: [Field]) { self.fields = fields }
    // In an extension, not in the body: writing ANY init inside a struct
    // suppresses the memberwise one, and `RecordParser` builds every record it
    // emits with `Record(fields:offset:line:)`. The build named it at once --
    // "extra arguments at positions #2, #3" -- which is the kind of failure
    // worth having, because the alternative is an init that silently loses two
    // fields.
    // 放在 extension 裡，不放在本體：在一個 struct 內寫**任何** init 都會抑制 memberwise init，
    // 而 `RecordParser` 送出的每一筆紀錄，正是用 `Record(fields:offset:line:)` 建的。建置立刻
    // 指名了它——「extra arguments at positions #2, #3」——那是值得擁有的那種失敗，因為另一個
    // 結局是一個「安靜地少掉兩個欄位」的 init。
}

public enum FieldEncoder {
    /// `preserveRaw` is only safe when the output format equals the input
    /// format. Writing `.csv` bytes into a `.csv2` file would carry a raw
    /// embedded newline across, breaking the one-record-per-line invariant.
    /// `preserveRaw` 只有在輸出格式與輸入格式相同時才安全。把 `.csv` 的原樣
    /// 位元組寫進 `.csv2`，會把原始的內嵌換行帶過去，破壞一筆一行的不變式。
    public static func encode(_ f: Field, format: Format, preserveRaw: Bool) -> [UInt8] {
        if preserveRaw, let raw = f.raw { return raw }
        // `.lines` writes the value's bytes and nothing else -- no quoting, no
        // escaping. Quoting here would break the round trip it exists for: a
        // path containing a comma would come back with quotes that nobody put
        // in it. A value holding a newline cannot be written at all, and that
        // is refused where the record is assembled rather than silently
        // mangled here.
        // `.lines` 只寫出那個值的位元組，別無其他——不加引號、不做跳脫。在這裡加引號會弄壞它存在
        // 所要達成的那趟往返：一個含逗號的路徑會帶著「沒有人放進去的引號」回來。一個含換行的值
        // 根本寫不出去，而那件事是在「組裝紀錄」的地方被拒絕的，不是在這裡被安靜地弄壞。
        if format == .lines { return f.value }
        let v = format == .csv2 ? CSV2Escape.escape(f.value) : f.value

        var needsQuote = false
        for b in v where b == BYTE_COMMA || b == BYTE_DQUOTE || b == BYTE_LF || b == BYTE_CR {
            needsQuote = true
            break
        }
        // Leading or trailing whitespace is quoted as well, though RFC 4180
        // does not require it. It is data, and it is the kind of data that
        // disappears silently: spreadsheets and several parsers strip it from
        // an unquoted field. csv2 writing `"   "` back as `   ` produced a
        // file whose value survives ITS OWN reader and not necessarily the
        // next one's -- and it changed the bytes of a cell that had been
        // updated with the value it already held, which shows up as a diff
        // that says nothing happened twice.
        // 前後的空白也會加引號，雖然 RFC 4180 並不要求。那是資料，而且是那種會安靜消失的
        // 資料：試算表與好幾種解析器會把未加引號欄位前後的空白去掉。csv2 把 `"   "` 寫回成
        // `   `，產生的檔案，其值撐得過「它自己的」讀取器，卻不一定撐得過下一個——而且它
        // 改動了一個「以它原本就有的值去更新」的儲存格的位元組，那在 diff 上會是一句
        // 「什麼也沒發生」說了兩次。
        if !needsQuote, let first = v.first, let last = v.last,
           first == BYTE_SPACE || first == BYTE_TAB || last == BYTE_SPACE || last == BYTE_TAB {
            needsQuote = true
        }
        if !needsQuote { return v }

        var out = [UInt8]()
        out.reserveCapacity(v.count + 4)
        out.append(BYTE_DQUOTE)
        for b in v {
            if b == BYTE_DQUOTE { out.append(BYTE_DQUOTE) }
            out.append(b)
        }
        out.append(BYTE_DQUOTE)
        return out
    }

    public static func encodeRecord(_ r: Record, format: Format, preserveRaw: Bool) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(64 * max(1, r.fields.count))
        for (i, f) in r.fields.enumerated() {
            if i > 0 { out.append(BYTE_COMMA) }
            out.append(contentsOf: encode(f, format: format, preserveRaw: preserveRaw))
        }
        // The record separator is ALWAYS LF, on every platform, with no
        // detection of the host OS. Without this the cross-platform
        // byte-identical acceptance condition cannot hold at all.
        // 紀錄分隔符永遠是 LF，在任何平台上皆然，不偵測作業系統。否則
        // 「跨平台逐位元相同」這條驗收條件根本不可能成立。
        out.append(BYTE_LF)
        return out
    }
}

// ---------------------------------------------------------------------
// MARK: - The parser / 解析器
// ---------------------------------------------------------------------

/// Refuse a UTF-16 file by its byte-order mark. Two bytes is the whole test:
/// FF FE and FE FF cannot begin a UTF-8 file, so seeing one is not a guess.
/// Called as soon as two bytes are known rather than after three, because a
/// file that IS two bytes would otherwise never reach it.
/// 以位元組順序記號拒絕一個 UTF-16 檔案。整個判斷就是那兩個位元組：FF FE 與 FE FF 不可能
/// 出現在 UTF-8 檔案的開頭，因此看到它不是在猜。一知道兩個位元組就呼叫，而不是等到三個，
/// 因為「整個檔案就是兩個位元組」的情況否則永遠到不了這裡。
func refuseUTF16BOM(_ head: [UInt8]) throws {
    guard head.count >= 2 else { return }
    let b0 = head[0], b1 = head[1]
    // Gzip, for the same reason and by the same test. `1F 8B` cannot begin a
    // UTF-8 CSV any more than `FF FE` can, and a compressed file named
    // `.csv` was read at rc=0 as one record of binary -- `-contains` found
    // nothing in it and said so, which is the answer this tool exists not to
    // give. The guard existed one byte-pattern to the left.
    // gzip，理由與判斷方式與上面相同。`1F 8B` 與 `FF FE` 一樣，都不可能是一個 UTF-8 CSV 的
    // 開頭；而一個叫做 `.csv` 的壓縮檔會以 rc=0 被讀成「一筆二進位紀錄」——`-contains` 在
    // 裡面什麼也沒找到，並且這樣回報，而那正是這個工具存在所要避免的答案。那道守衛，
    // 就差在左邊一個位元組樣式。
    if b0 == 0x1F && b1 == 0x8B {
        throw fault(
            "this file begins with a gzip magic number (1f 8b); csv2 reads bytes and does not decompress. Expand it first with: gunzip -c file.csv.gz > file.csv -- the new name has to keep a .csv or .csv2 suffix, because the suffix is what declares the format",
            "本檔案以 gzip 的魔術數字（1f 8b）開頭；csv2 讀的是位元組，不做解壓縮。請先解開：gunzip -c file.csv.gz > file.csv——新檔名必須保留 .csv 或 .csv2 副檔名，因為宣告格式的正是副檔名")
    }
    guard (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) else { return }
    let which = b0 == 0xFF ? "UTF-16LE" : "UTF-16BE"
    throw fault(
        "this file begins with a \(which) byte-order mark; csv2 reads bytes and does not convert encodings, so it would parse as records that mean nothing. Convert it first with: iconv -f \(which) -t UTF-8 file > converted.csv -- the new name has to keep a .csv or .csv2 suffix, because the suffix is what declares the format",
        "本檔案以 \(which) 的位元組順序記號開頭；csv2 讀的是位元組、不做編碼轉換，因此它會被解析成一堆沒有意義的紀錄。請先轉換：iconv -f \(which) -t UTF-8 file > converted.csv——新檔名必須保留 .csv 或 .csv2 副檔名，因為宣告格式的正是副檔名")
}


/// Push-based so that `-si` can stream: bytes go in a chunk at a time and
/// records come out as they complete. Nothing here ever holds the whole
/// input, because the tool has to work on files larger than the 2-4 GiB the
/// guest has.
/// 採推送式，讓 `-si` 能串流：位元組逐塊進來，紀錄完成一筆吐一筆。此處
/// 不持有整份輸入，因為本工具必須能處理比 guest 那 2–4 GiB 更大的檔案。
/// **A header row is a Record too.** The parser hands out every record it
/// meets, headers included, because it does not know which of them you meant
/// to treat as titles -- `Format.headerRows` says how many to skip, and the
/// CLI's `-r` skips them for you. Somebody moving from the CLI to this type
/// gets one more record than they expect and finds out when the column names
/// do not line up. Reported by the first caller to make that move, on its
/// first attempt; the cost of not writing it here is that everyone after makes
/// it too.
///
/// **標頭列也是一筆 Record。** 這個解析器會把它遇到的每一筆都交出去，標頭也不例外，因為它不知道
/// 你打算把其中哪幾筆當成標題——要跳過幾列請問 `Format.headerRows`，而 CLI 的 `-r` 會替你跳過。
/// 一個從 CLI 換到這個型別的人，會比預期多拿到一筆，而發現的方式是欄名對不上。這是第一個做出那個
/// 轉換的呼叫端在它第一次嘗試時回報的；不把這件事寫在這裡的代價，是它之後的每一個人都會再犯一次。
///
/// **`Field` is a name a UI will already have.** Qualify it as `CSV2Core.Field`
/// rather than importing it bare -- the first consumer of this module collided
/// with its own `struct Field: View` on day one. That collision is also the
/// concrete reason to import this as a module instead of compiling the sources
/// into your own target, where the two names cannot both exist.
/// **`Field` 是任何 UI 都已經會有的名字。** 請用 `CSV2Core.Field` 限定，不要裸著 import
/// ——這個 module 的第一個消費端在第一天就與自己的 `struct Field: View` 撞名了。那次撞名同時也是
/// 「把它當成 module 匯入、而不是把原始碼編進你自己的 target」的具體理由：在同一個 target 裡，
/// 那兩個名字不可能並存。
public final class RecordParser {
    private enum State {
        case fieldStart
        case unquoted
        case quoted
        case quotedQuote
        case afterQuoted
    }

    let format: Format

    private var state: State = .fieldStart
    private var fields: [Field] = []
    private var rawBuf: [UInt8] = []
    private var valBuf: [UInt8] = []
    private var fieldHasBackslash = false
    private var pendingCR = false
    private var recordDirty = false

    private var offset = 0
    private var line = 1
    private var recOffset = 0
    private var recLine = 1

    private var bomPending: [UInt8] = []
    private var bomDone = false

    /// Set when the field currently being parsed contained a raw newline
    /// inside quotes. `.csv2` rejects that; `.csv` allows it.
    /// 目前解析中的欄位在引號內含原始換行時設立。`.csv2` 拒絕，`.csv` 允許。
    private var quotedNewlineInField = false

    /// True when this parser is reading ONE CHUNK of a file rather than the
    /// whole of it. Only the parallel workers set it, and it changes exactly
    /// one thing: what "the input ended" is allowed to mean.
    /// 當這個解析器讀的是一個檔案的「一塊」而不是全部時為真。只有平行工作者會設定它，
    /// 而它只改變一件事：「輸入結束了」這句話可以指什麼。
    var chunked = false
    private(set) var sawLF = false
    private(set) var sawCRAsData = false
    /// Counted, not just flagged. The CR-line-ending check used to ask "was
    /// there NO LF at all", which a CR-separated file with a single trailing
    /// LF answers with "there was one" -- so the detector, message and all,
    /// stayed silent and the file read as ZERO records at rc=0. One byte
    /// decided whether the user got a first-rate diagnosis or nothing.
    /// 用數的，不只是用旗標。原本的 CR 行尾檢查問的是「有沒有『完全沒有』LF」，而一個
    /// 「以 CR 分隔、結尾多一個 LF」的檔案會回答「有一個」——於是那個偵測器連同它寫得很好的
    /// 訊息一起沉默，而該檔案以 rc=0 讀成「零筆紀錄」。一個位元組決定了使用者拿到的是
    /// 一流的診斷，還是什麼都沒有。
    private var lfCount = 0
    private var crAsDataCount = 0
    private(set) var sawCRLF = false
    /// Whether the LAST record terminator seen was CRLF. `sawCRLF` answers
    /// "did this file ever use one"; the append path needs "what does this
    /// file end its records with", and on a file whose final record is
    /// unterminated those two questions have different answers.
    /// 「最後一個看到的紀錄終止符」是不是 CRLF。`sawCRLF` 回答的是「這個檔案有沒有用過
    /// CRLF」；而追加路徑要問的是「這個檔案的紀錄是以什麼結尾的」——在一個「最後一筆沒有
    /// 終止符」的檔案上，那兩個問題的答案不同。
    private(set) var lastTerminatorWasCRLF = false
    private(set) var strippedBOM = false
    private(set) var recordsEmitted = 0

    /// Return false from the sink to stop parsing. `-mid a,b` uses this to
    /// avoid reading a single byte past record b -- the property that makes
    /// it the cheapest range operation on a huge file.
    /// sink 回傳 false 即停止解析。`-mid a,b` 靠這一點做到不多讀 b 之後的
    /// 任何一個位元組——那正是它在巨大檔案上最便宜的原因。
    private let sink: (Record) throws -> Bool
    private(set) var stopped = false
    private let truncatePartial: Bool

    /// `firstRecordNumber`, `firstOffset` and `firstLine` let parsing resume
    /// at an index grid point while producing exactly the numbers a full scan
    /// would have produced. Output with and without an index has to be
    /// byte-identical, and the record numbers are part of the output.
    /// `firstRecordNumber`、`firstOffset` 與 `firstLine` 讓解析能從索引格點恢復，
    /// 同時產生與完整掃描完全相同的編號。有無索引的輸出必須逐位元相同，而紀錄號
    /// 就是輸出的一部分。
    /// `sink` is LAST so every call site can use trailing-closure syntax while
    /// the rest keep their defaults. Swift matches a trailing closure to the
    /// final parameter, so putting anything after it forces every caller to
    /// spell out `sink:`.
    /// `sink` 放在最後，讓每個呼叫端都能使用 trailing closure，其餘參數維持預設值。
    /// Swift 會把 trailing closure 對應到最後一個參數，因此在它之後再放任何參數，
    /// 都會迫使每個呼叫端把 `sink:` 寫出來。
    public init(format: Format,
         firstRecordNumber: Int = 1, firstOffset: Int = 0, firstLine: Int = 1,
         truncatePartial: Bool = false,
         sink: @escaping (Record) throws -> Bool) {
        self.format = format
        self.sink = sink
        self.truncatePartial = truncatePartial
        self.recordsEmitted = firstRecordNumber - 1
        self.offset = firstOffset
        self.recOffset = firstOffset
        self.line = firstLine
        self.recLine = firstLine
        // A resumed stream starts at a record boundary, so there is no BOM to
        // look for -- and looking would eat three data bytes.
        // 從紀錄邊界恢復的串流沒有 BOM 可找——而去找它會吃掉三個資料位元組。
        if firstOffset > 0 { self.bomDone = true }
    }

    /// The address a cell-level error prints, in the same shape record-level
    /// errors have always used: the DATA record number AND the physical line.
    ///
    /// It printed `recordsEmitted + 1`, which counts the header rows too. On a
    /// `.csv2` the offset was therefore exactly two, so a fault in data record
    /// 2 was reported as `record 4` -- and `-get 4:2` answered "no such
    /// record; the file has 2 records". The number in an error message is an
    /// address somebody types back into `-get` or `-update`; one that does not
    /// resolve is worse than none, because it sends them to a different cell
    /// or to a refusal that looks like the file is wrong. Round 38, defect CC.
    ///
    /// Header rows get `0a` / `0b`, the names the locating report already uses
    /// for them, rather than a record number they do not have.
    ///
    /// 儲存格層級錯誤所印的位址，形狀與紀錄層級錯誤一直以來的寫法相同：資料紀錄號**與**
    /// 物理行號。
    /// 原本印的是 `recordsEmitted + 1`，那個計數含標頭列。因此在 `.csv2` 上偏移恰好是二，
    /// 資料第 2 筆的錯誤會被回報成 `record 4`——而 `-get 4:2` 回答「沒有這一筆；本檔案有
    /// 2 筆」。錯誤訊息裡的號碼是**會被人打回 `-get` 或 `-update` 的位址**；一個解不出來的
    /// 位址比沒有更糟，因為它會把人送到另一格，或送到一個「看起來像檔案有問題」的拒絕。
    /// 第 38 回合，缺陷 CC。
    /// 標頭列給的是 `0a` / `0b`——定位報告本來就這樣稱呼它們——而不是一個它們並不擁有的紀錄號。
    private var faultAt: String {
        let n = recordsEmitted + 1
        if n <= format.headerRows { return "header row 0\(n == 1 ? "a" : "b") (line \(recLine))" }
        return "record \(n - format.headerRows) (line \(recLine))"
    }

    private var faultAtZh: String {
        let n = recordsEmitted + 1
        if n <= format.headerRows { return "標頭第 0\(n == 1 ? "a" : "b") 列（第 \(recLine) 行）" }
        return "第 \(n - format.headerRows) 筆（第 \(recLine) 行）"
    }

    public func feed(_ chunk: [UInt8]) throws {
        var bytes = chunk
        if !bomDone {
            bomPending.append(contentsOf: bytes)
            // The UTF-16 test needs two bytes and the UTF-8 BOM needs three,
            // so waiting for three skipped it entirely on a file that IS two
            // bytes -- and a file consisting of nothing but FF FE is what an
            // editor writes when you save an empty document as UTF-16. It was
            // accepted at rc=0 as a one-column CSV whose column name is those
            // two bytes, which are not valid UTF-8, while a zero-byte file --
            // semantically the same empty file -- is refused for not declaring
            // its shape. Two rules disagreeing at adjacent sizes.
            // 判斷 UTF-16 只要兩個位元組，判斷 UTF-8 BOM 要三個，而「等到三個」讓前者在
            // 「整個檔案就是兩個位元組」時完全沒有機會執行——而一個「只有 FF FE」的檔案，
            // 正是編輯器把一份空文件存成 UTF-16 時寫出來的東西。它會以 rc=0 被接受，成為一個
            // 「欄名是那兩個非法 UTF-8 位元組」的單欄 CSV；而一個零位元組的檔案——語意上同樣是
            // 空的——則因為「沒有宣告自己的形狀」而被拒絕。兩條規則在相鄰的大小上互相矛盾。
            if bomPending.count >= 2 { try refuseUTF16BOM(bomPending) }
            if bomPending.count < BOM.count {
                return // wait for more; a 1-byte file cannot carry a BOM anyway
            }
            // A UTF-16 BOM cannot begin a UTF-8 file -- FF FE and FE FF are
            // not valid UTF-8 -- so seeing one is not ambiguous. Left alone,
            // csv2 reads the file byte-transparently, which is correct for a
            // tool that promises bytes round-trip and useless to the person
            // holding it: every second byte is NUL, the column names carry
            // them, and the whole thing parses at rc=0 into records that mean
            // nothing.
            //
            // Refused rather than converted, for the same reason the CR check
            // above refuses: guessing an encoding is how a tool ends up
            // silently producing something plausible and wrong. `iconv` knows
            // how to do this and csv2 does not need to.
            //
            // UTF-16 的 BOM 不可能出現在 UTF-8 檔案的開頭——FF FE 與 FE FF 都不是合法的
            // UTF-8——因此看到它並不含糊。放著不管的話，csv2 會以「位元組透明」的方式讀它，
            // 那對一個承諾「位元組原樣往返」的工具是正確的，而對拿著這個檔案的人毫無用處：
            // 每隔一個位元組就是 NUL、欄名裡帶著它們，而整份東西會在 rc=0 下解析成一堆
            // 沒有意義的紀錄。
            //
            // 選擇拒絕而非轉換，理由與上面那個 CR 檢查相同：猜測編碼，正是一個工具最後
            // 「靜默產生出看似合理而錯誤的東西」的方式。`iconv` 知道怎麼做，csv2 不需要會。
            if Array(bomPending.prefix(3)) == BOM {
                // A UTF-8 BOM marks "this came from Windows"; Excel exports
                // one. Left in place it becomes part of the first column
                // NAME, so addressing by name fails while the printout looks
                // completely normal.
                // UTF-8 BOM 是「這個檔案來自 Windows」的標記，Excel 匯出就帶著它。
                // 不剝除的話它會變成第一個欄名的一部分，於是以欄名定址全部失敗，
                // 而印出來看起來完全正常。
                bomPending.removeFirst(3)
                strippedBOM = true
                offset = 3
                recOffset = 3
            }
            bytes = bomPending
            bomPending = []
            bomDone = true
        }
        for b in bytes {
            try consume(b)
            if stopped { return }
        }
    }

    private func consume(_ b: UInt8) throws {
        if pendingCR {
            pendingCR = false
            if b == BYTE_LF {
                // The CR belonged to the separator. Deciding this per record
                // rather than per file is what makes a mixed-line-ending file
                // parse correctly -- and mixed really happens, when someone
                // edits part of a file on Windows or two sources get cat'd.
                // 該 CR 屬於分隔符。逐筆判斷而非整檔判斷，正是混合行尾的檔案
                // 能被正確解析的原因——而混合是真的會發生的。
                sawLF = true
                lfCount += 1
                sawCRLF = true
                lastTerminatorWasCRLF = true
                offset += 1
                line += 1
                try endRecord()
                return
            }
            // A lone CR is data. Treating it as a separator would corrupt any
            // value that legitimately contains one.
            // 孤立的 CR 是資料。把它當分隔符會破壞任何合法含有它的值。
            sawCRAsData = true
            crAsDataCount += 1
            try refuseCRInHeader()
            try appendDataByte(BYTE_CR)
        }

        switch state {
        case .fieldStart, .unquoted:
            // In `.lines` a comma and a quote are DATA. The line is the
            // value, so the only byte with a meaning is the terminator.
            // Phase 8b: a `find` dump whose paths contain commas is the case
            // that decided this, and quoting had to go with it -- half of the
            // rule would have left `"a,b"` parsing as one field with its
            // quotes eaten, which is a value nobody wrote.
            // 在 `.lines` 裡，逗號與引號都是**資料**。那一行就是那個值，因此唯一有意義的位元組
            // 是終止符。第 8b 階段：決定這件事的，是一份「路徑裡含逗號」的 `find` 輸出，而引號
            // 必須跟著一起走——只做一半的規則，會讓 `"a,b"` 解析成一個「引號被吃掉」的欄位，
            // 而那是沒有人寫過的值。
            if b == BYTE_DQUOTE && state == .fieldStart && format != .lines {
                state = .quoted
                rawBuf.append(b)
                recordDirty = true
            } else if b == BYTE_COMMA && format != .lines {
                try endField()
            } else if b == BYTE_LF {
                sawLF = true
                lfCount += 1
                lastTerminatorWasCRLF = false
                line += 1
                offset += 1
                try endRecord()
                return
            } else if b == BYTE_CR {
                pendingCR = true
                recordDirty = true
            } else {
                state = .unquoted
                try appendDataByte(b)
            }

        case .quoted:
            if b == BYTE_DQUOTE {
                state = .quotedQuote
                rawBuf.append(b)
            } else {
                if b == BYTE_LF { line += 1; quotedNewlineInField = true }
                if b == BYTE_CR { quotedNewlineInField = true }
                if format == .csv2 && b == BYTE_BACKSLASH { fieldHasBackslash = true }
                rawBuf.append(b)
                valBuf.append(b)
            }

        case .quotedQuote:
            if b == BYTE_DQUOTE {
                // `""` inside a quoted field is one literal quote.
                // 引號欄位內的 `""` 代表一個字面引號。
                rawBuf.append(b)
                valBuf.append(BYTE_DQUOTE)
                state = .quoted
            } else {
                state = .afterQuoted
                offset += 1
                try consumeAfterQuoted(b)
                return
            }

        case .afterQuoted:
            offset += 1
            try consumeAfterQuoted(b)
            return
        }
        offset += 1
    }

    private func consumeAfterQuoted(_ b: UInt8) throws {
        if b == BYTE_COMMA {
            try endField()
        } else if b == BYTE_LF {
            sawLF = true
            lastTerminatorWasCRLF = false
            line += 1
            try endRecord()
        } else if b == BYTE_CR {
            pendingCR = true
        } else {
            // RFC 4180 does not allow this and neither do we. Appending the
            // stray bytes would silently produce a value nobody wrote.
            // RFC 4180 不允許，我們也不允許。把多餘的位元組接上去，會靜默
            // 產生一個沒有人寫過的值。
            throw fault(
                "\(faultAt), field \(fields.count + 1): unexpected byte after a closing quote (0x\(String(format: "%02x", b))); a quoted field must be followed by a comma or a line ending",
                "\(faultAtZh)第 \(fields.count + 1) 欄：關閉引號之後出現非預期的位元組（0x\(String(format: "%02x", b))）；引號欄位之後只能接逗號或行尾")
        }
    }

    private func appendDataByte(_ b: UInt8) throws {
        if format == .csv2 && b == BYTE_BACKSLASH { fieldHasBackslash = true }
        rawBuf.append(b)
        valBuf.append(b)
        recordDirty = true
    }

    private func endField() throws {
        if format == .csv2 && quotedNewlineInField {
            throw fault(
                "\(faultAt), field \(fields.count + 1): a raw newline inside a cell; .csv2 keeps one record per line, so newlines must be written as \\n",
                "\(faultAtZh)第 \(fields.count + 1) 欄：儲存格內有原始換行；.csv2 保證一筆一行，換行必須寫成 \\n")
        }
        var value = valBuf
        if format == .csv2 && fieldHasBackslash {
            value = try CSV2Escape.unescape(
                value, at: faultAt, atZh: faultAtZh, field: fields.count + 1)
        }
        fields.append(Field(value: value, raw: rawBuf))
        rawBuf = []
        valBuf = []
        state = .fieldStart
        quotedNewlineInField = false
        fieldHasBackslash = false
        recordDirty = true
    }

    /// A Markdown separator row -- `|---|---|---|`, or its `:--:` alignment
    /// forms -- appearing as a record with exactly ONE field.
    ///
    /// `-md` output redirected into a `.csv` path is a valid one-column CSV
    /// whenever the data happens to contain no commas, and csv2 read it back at
    /// rc=0 with the separator row handed over as data record 1. That is the
    /// failure this project's opening promise rules out: not a refusal, not a
    /// crash, but a silently half-correct read of a file it had produced itself.
    /// With commas in the data the field counts disagree and it already failed
    /// loudly; without them nothing was left to notice.
    ///
    /// One field is required as well as the shape. A real one-column CSV whose
    /// first value is exactly a row of dashes and pipes is conceivable and
    /// essentially never written; a MULTI-column file containing such a value
    /// is left alone entirely, because there the file plainly is CSV.
    ///
    /// 一列 Markdown 分隔列——`|---|---|---|`，或其 `:--:` 對齊形式——以「恰好一欄」的
    /// 紀錄形式出現。
    /// 把 `-md` 的輸出重導到 `.csv` 路徑，只要資料剛好不含逗號，那就是一份合法的單欄 CSV；
    /// 而 csv2 會在 rc=0 下把它讀回來，並把分隔列當成第 1 筆資料交出去。那正是本專案開宗明義
    /// 排除掉的那種失敗：不是拒絕、不是崩潰，而是對一個它自己產生的檔案，做出一次靜默的、
    /// 半正確的讀取。資料含逗號時欄數不符，它本來就會大聲失敗；不含逗號時，就沒有東西還會
    /// 察覺了。
    /// 除了形狀之外還要求「恰好一欄」。一份真實的單欄 CSV，其首個值剛好是一整列破折號與豎線
    /// ——可以想像，但幾乎不會有人這樣寫；而「多欄」檔案中含有這種值時完全不受影響，因為在
    /// 那裡，那個檔案顯然就是 CSV。
    private func looksLikeMarkdownSeparator(_ f: [UInt8]) -> Bool {
        guard f.count >= 5, f.first == 0x7C, f.last == 0x7C else { return false }
        var dashes = 0
        for b in f {
            switch b {
            case 0x2D: dashes += 1            // -
            case 0x7C, 0x3A, 0x20: break      // | : space
            default: return false
            }
        }
        return dashes >= 3
    }

    private func endRecord() throws {
        try endField()
        var r = Record(fields: fields, offset: recOffset, line: recLine)
        recordsEmitted += 1
        r.number = recordsEmitted
        // `format != .lines` is the whole of this fix, and it is where the
        // guard should always have been scoped. A file with no .csv/.csv2
        // suffix IS one column by definition, so `r.count == 1` is true of
        // every record in it -- which turned a check aimed at "a file that
        // CLAIMS to be CSV yet looks like Markdown" into an unconditional one
        // there.
        //
        // In `.lines` nothing is claimed, so nothing is ambiguous: `#`, JSON,
        // XML and a Markdown table's own DATA rows all pass through as bytes,
        // and only the separator was singled out. Same table, one row refused
        // and the rows above and below it fine. It also protected against
        // nothing: reading `-md` output as `.lines` gives one field per line,
        // which is exactly what `.lines` means.
        //
        // The cost was a real one -- no text file containing a Markdown table
        // could be edited line by line, which is the case a user hit. KU.
        // `format != .lines` 就是這次修正的全部，而這道守衛本來就該有這個範圍。一個沒有
        // .csv／.csv2 副檔名的檔案，依定義**就是**一欄，因此 `r.count == 1` 對它裡面每一筆都成立
        // ——那讓一道原本瞄準「一個**自稱**是 CSV、卻長得像 Markdown 的檔案」的檢查，在那裡變成
        // 無條件的。
        //
        // 在 `.lines` 裡什麼都沒有被宣稱，因此沒有任何歧義：`#`、JSON、XML，以及一張 Markdown 表
        // 自己的**資料列**，全都以位元組原樣通過，只有分隔列被挑了出來。同一張表，一列被拒，
        // 而它上下的每一列都沒事。它保護的也是一個不存在的危險：用 `.lines` 讀 `-md` 的輸出會
        // 得到「每行一個欄位」，而那正是 `.lines` 的意思。
        //
        // 代價是真實的——任何含 Markdown 表的文字檔都無法逐行編輯，而那正是一位使用者撞到的
        // 情況。KU。
        if format != .lines && r.count == 1 && looksLikeMarkdownSeparator(r.fields[0].value) {
            throw fault(
                "record \(r.number) (line \(r.line)) is a Markdown separator row in a file with one column, so this is -md output rather than CSV. Name it with a .md suffix and csv2 reads it as a table -- until 2026-08-26 this sentence ended \"-md is one-way and csv2 cannot read it back\", which stopped being true when it learned to",
                "第 \(r.number) 筆（第 \(r.line) 行）是一列 Markdown 分隔列，且此檔只有一欄，因此這是 -md 的輸出而不是 CSV。把它命名為 .md 副檔名，csv2 就會把它當成一張表來讀——在 2026-08-26 之前，這句話的結尾是「-md 是單向的，csv2 讀不回來」，而在它學會讀回來的那一刻，那句話就不再為真")
        }
        fields = []
        recordDirty = false
        recOffset = offset
        recLine = line
        if try !sink(r) { stopped = true }
    }

    /// A bare carriage return inside the FIRST record -- the header row, in
    /// every format csv2 reads -- is the signature of a CR-terminated file,
    /// and it is exact where counting was approximate.
    ///
    /// The test used to be `bare CRs > line feeds`, described in both READMEs
    /// as "this file uses CR line endings". Those are different statements and
    /// they came apart in both directions:
    ///
    ///   a,b<LF>1,x<CR><CR><CR>y<LF>       3 CRs, 2 LFs -> refused, and the
    ///                                     file is LF-terminated. The message
    ///                                     asserted something false about it,
    ///                                     and `tr '\r' '\n'`, which the
    ///                                     message prescribes, turned that one
    ///                                     record into a file csv2 will not
    ///                                     read.
    ///   col<CR>"L<LF>L<LF>L<LF>L"<CR>zz<CR>
    ///                                     3 CRs, 3 LFs -> accepted at rc=0 as
    ///                                     three records under a column named
    ///                                     `col<CR>"L`, quoted field shredded,
    ///                                     nothing on stderr. A genuine
    ///                                     CR-terminated file, silently
    ///                                     misparsed -- the failure the count
    ///                                     was written to prevent.
    ///
    /// A CR-terminated file has no LF to end its first line, so everything it
    /// contains lands in the first record -- which is why the header row is
    /// where the evidence always is, whatever the rest of the file holds. A
    /// bare CR in a RECORD stays data and still round-trips; a CR that is part
    /// of a column NAME has to be quoted, which costs one pair of quotes and
    /// makes the intent explicit.
    ///
    /// 第一筆紀錄——在 csv2 讀得懂的每一種格式裡，那就是標頭列——中的一個裸 CR，是「以 CR
    /// 結尾的檔案」的簽名，而它在「數數」只能近似的地方是精確的。
    ///
    /// 原本的判斷是「裸 CR 比換行多」，而兩份 README 都把它描述成「本檔案使用 CR 行尾」。
    /// 那是兩句不同的話，而它們往兩個方向都裂開過：一個 LF 結尾、欄位裡有三個 CR 的檔案被
    /// 拒絕，訊息對它說了一件假的事，而訊息指定的 `tr` 修法會把那一筆變成讀不回來的檔案；
    /// 一個真正以 CR 結尾、CR 與 LF 一樣多的檔案則以 rc=0 被接受，成為三筆假紀錄、欄名是
    /// `col<CR>"L`、引號欄位被撕開，stderr 上一個字也沒有。
    ///
    /// 以 CR 結尾的檔案沒有 LF 去結束它的第一行，因此它的全部內容都落在第一筆紀錄裡——那正是
    /// 「證據永遠在標頭列」的原因。紀錄裡的裸 CR 仍然是資料、仍然能原樣往返；而屬於「欄名」
    /// 的 CR 必須加引號，那只花一對引號，並且讓意圖變成明說的。
    private func refuseCRInHeader() throws {
        guard recordsEmitted == 0 else { return }
        throw fault(
            "the header row contains a bare carriage return, which is what a file with CR line endings (the pre-OS X Mac convention) looks like to a CSV reader; convert it first with: tr '\\r' '\\n' < file > converted.csv -- the new name has to keep a .csv or .csv2 suffix, because the suffix is what declares the format. If the CR really belongs to a column NAME, quote that field and it is read as data",
            "標頭列中含有一個裸 CR，而那正是「以 CR 作為行尾的檔案」（OS X 之前的 Mac 慣例）在一個 CSV 讀取器眼中的樣子；請先轉換：tr '\\r' '\\n' < file > converted.csv——新檔名必須保留 .csv 或 .csv2 副檔名，因為宣告格式的正是副檔名。若那個 CR 確實屬於某個「欄名」，請把該欄位加上引號，它就會被當成資料讀入")
    }

    /// Call once at end of input. Emits a trailing record if the file did not
    /// end with a newline, and reports the CR-only case.
    /// 輸入結束時呼叫一次。若檔案未以換行結尾則吐出最後一筆，並回報 CR-only。
    /// True only while `finish()` is draining what was left over, so the CR
    /// test above can tell "a CR in the middle" from "the file ended on one".
    /// 只有在 `finish()` 正在清空殘留內容時為真，好讓上面那個 CR 判斷分得出
    /// 「中間的一個 CR」與「檔案就結束在一個 CR 上」。
    private var atEOF = false

    public func finish() throws {
        if stopped { return }
        atEOF = true
        if !bomDone && !bomPending.isEmpty {
            let pending = bomPending
            bomPending = []
            bomDone = true
            for b in pending {
                try consume(b)
                if stopped { return }
            }
        }
        if pendingCR {
            pendingCR = false
            sawCRAsData = true
            crAsDataCount += 1
            try refuseCRInHeader()
            try appendDataByte(BYTE_CR)
            // The file ENDS on a bare CR, which is what a CR-terminated body
            // looks like from here -- and the header test above cannot see it,
            // because this file's header ended with a proper LF. `(echo a;
            // cat old_mac_body) > f.csv` is how you get one, and it read as a
            // SINGLE record at rc=0 with `records:1` on the meta line: every
            // count in that file wrong by the number of lines in it, and the
            // documented presence test reporting the wrong number confidently.
            //
            // Exact rather than approximate, again: a file whose last byte is
            // a bare CR is refused, and one that ends with a newline is not,
            // whatever its records contain. `1,x<CR><CR><CR>y<LF>` -- the
            // false positive the counting version of this guard produced --
            // still reads as one record with three CRs in its second field.
            //
            // 檔案「結束」在一個裸 CR 上，而那正是一個以 CR 結尾的內文從這裡看過去的樣子
            // ——上面那個標頭檢查看不到它，因為這個檔案的標頭是以正常的 LF 結束的。
            // `(echo a; cat old_mac_body) > f.csv` 就會產生一個這樣的檔案，而它會以 rc=0
            // 被讀成「一筆」紀錄、meta 上寫著 `records:1`：那個檔案裡的每一個計數都錯了，
            // 錯的倍數就是它的行數，而文件指定的那個「有沒有」的檢查，會很有把握地回報一個
            // 錯的數字。
            //
            // 一樣是「精確」而不是「近似」：最後一個位元組是裸 CR 的檔案會被拒絕，而以換行
            // 結尾的檔案不會，不論它的紀錄裡裝了什麼。`1,x<CR><CR><CR>y<LF>`——當初那個「用數的」
            // 版本造成的誤判——仍然會被讀成一筆紀錄，第二欄裡有三個 CR。
            if atEOF {
                throw fault(
                    "this file's last byte is a bare carriage return, which is what a body with CR line endings looks like: everything after the header lands in one record. Convert it first with: tr '\\r' '\\n' < file > converted.csv -- the new name has to keep a .csv or .csv2 suffix. If that CR really is the last byte of the last value, end the file with a newline",
                    "本檔案的最後一個位元組是一個裸 CR，而那正是「以 CR 作為行尾的內文」的樣子：標頭之後的一切都會落進同一筆紀錄。請先轉換：tr '\\r' '\\n' < file > converted.csv——新檔名必須保留 .csv 或 .csv2 副檔名。若那個 CR 確實是最後一個值的最後一個位元組，請讓檔案以換行結尾")
            }
        }
        // A CR-only file (pre-OS X Mac) contains no LF at all, so the whole
        // thing parses as ONE record with millions of fields and then hits
        // the field-count check -- whose message talks about field counts and
        // sends the user somewhere entirely unrelated. Diagnosing it costs
        // nothing; not diagnosing it costs an afternoon.
        // CR-only 檔案（OS X 之前的 Mac 慣例）完全沒有 LF，於是整份被解析成
        // 一筆有數百萬欄的紀錄，接著撞上欄數檢查——而那個訊息在講欄數，會把
        // 使用者引去一個完全無關的方向。診斷成本幾乎為零，少了它代價是一個下午。
        // The CR test lives in refuseCRInHeader now, and fires the moment the
        // byte arrives rather than at end of input.
        // CR 的判斷現在在 refuseCRInHeader 裡，而且是在那個位元組抵達的當下就觸發，
        // 不再等到輸入結束。
        let pending = recordDirty || !fields.isEmpty || !rawBuf.isEmpty || !valBuf.isEmpty
        guard pending else { return }

        // The input ran out mid-record. Two ways that is genuinely incomplete,
        // and one way it is not:
        //
        //   * still inside a quoted field -- the closing quote never arrived.
        //     Incomplete in ANY format. csv2 used to close the quote itself and
        //     emit the record at rc=0, which is this project's own definition of
        //     the worst kind of bug: a plausible record nobody wrote.
        //   * `.csv2` with no trailing newline -- that format guarantees one
        //     record per line, LF-terminated, so a missing final LF is the
        //     signature of a torn write.
        //   * `.csv` with no trailing newline is NOT incomplete. Plenty of tools
        //     emit a final line without one, and treating that as damage would
        //     reject perfectly good files.
        //
        // 輸入在一筆紀錄中途結束。有兩種情況是真的不完整，一種不是：
        //   * 還在引號欄位內——收尾的引號從未出現。這在「任何」格式下都不完整。
        //     csv2 原本會自己把引號收掉並以 rc=0 吐出那筆紀錄，而那正是本專案自己
        //     定義的最糟一類缺陷：一筆看似合理、卻沒有人寫過的紀錄。
        //   * `.csv2` 沒有結尾換行——該格式保證一筆一行且以 LF 結尾，缺少結尾 LF
        //     就是撕裂寫入的信號。
        //   * `.csv` 沒有結尾換行「不是」不完整。很多工具產生的最後一行本來就沒有，
        //     把它當成損壞會拒絕掉完全正常的檔案。
        // `.quoted` only. `.quotedQuote` means a quote was just seen INSIDE a
        // quoted field and the parser does not yet know whether it closes the
        // field or is the first half of an escaped `""`. At end of input that
        // question is answered: it closed the field, and the record is
        // complete. Treating it as unterminated rejected every well-formed row
        // ending in a quoted value -- caught by T46a, where -append of
        // `zz,last,"note, appended"` started failing.
        // 只有 `.quoted`。`.quotedQuote` 表示剛在引號欄位「內」看到一個引號，解析器
        // 還不知道它是收尾、還是跳脫 `""` 的前半。到了輸入結束，那個問題就有答案了：
        // 它收尾了，紀錄是完整的。把它當成未閉合，會拒絕每一列「以引號值結尾」的
        // 合法資料——由 T46a 抓到，那裡 `zz,last,"note, appended"` 的追加開始失敗。
        let insideQuote = (state == .quoted)
        let incomplete = insideQuote || format == .csv2

        if incomplete {
            if truncatePartial {
                // Dropping a record the user may believe was written is never
                // done on csv2's own initiative -- only when asked for by name.
                // 丟棄一筆使用者可能以為已寫入的紀錄，絕不由 csv2 自行決定，
                // 只有在被指名要求時才做。
                // WARN, and with the size, because "a record" is not what
                // this always drops. When the quote opens early, everything
                // after it is ONE unterminated record from the parser's view
                // -- and that one record can hold the whole rest of the file.
                // Measured: a ten-record file whose quote opens in record 1
                // came back with zero records, at rc=0, with nothing on
                // stderr. The flag was asked for by name, so this is not an
                // error; it is a surprise large enough that the WARN
                // machinery, which already fires for a -mid window that
                // selected nothing, should fire here too.
                //
                // Bytes rather than records: from inside the parser the
                // discarded text IS one record, and counting the records a
                // reader would have seen in it would mean parsing text that
                // has just been declared unparseable.
                //
                // 用 WARN，而且帶著大小——因為它丟掉的不總是「一筆」。當引號很早就打開，
                // 從解析器的角度，其後的一切都是「一筆」未終止的紀錄——而那一筆可以裝著
                // 整個檔案的其餘部分。實測：一個 10 筆的檔案，引號在第 1 筆打開，回傳 0 筆、
                // rc=0、stderr 空無一物。這個旗標是被指名要求的，所以它不是錯誤；但它是一個
                // 大到應該讓 WARN 機制出聲的意外——而那套機制早已為「什麼都沒選到的 -mid
                // 視窗」而觸發。
                //
                // 用位元組而不是筆數：從解析器內部看，被丟掉的文字「就是一筆」，而去數
                // 「讀者本來會在裡面看到幾筆」，等於去解析一段剛剛被宣告為解析不了的文字。
                // From where the record began to where the input ran out.
                //
                // It used to be `rawBuf.count + valBuf.count`, which counts the
                // same text twice: rawBuf holds the bytes as they arrived
                // (opening quote included) and valBuf the decoded value, so a
                // tail of B bytes was reported as 2B+1. On a 38-byte file it
                // said 55 -- more bytes than the file has -- and on a
                // three-byte tail it said 1, under-reporting. The other half of
                // the same sentence, "beginning at byte N", was right every
                // time, which is what made the wrong half credible.
                //
                // Nothing in the tool could check it: there is no --json field,
                // no -log entry and no -debug line for this number. The WARN is
                // its only report, and both READMEs promise it.
                //
                // 從「這一筆開始的地方」到「輸入用完的地方」。
                //
                // 原本是 `rawBuf.count + valBuf.count`，而那把同一段文字數了兩次：rawBuf 裝的是
                // 「抵達時的位元組」（含開引號），valBuf 裝的是解碼後的值，於是 B 個位元組的
                // 尾巴被回報成 2B+1。在一個 38 位元組的檔案上它說 55——比整個檔案還多——而在一個
                // 三位元組的尾巴上它說 1，少報。同一句話的另一半「beginning at byte N」每次都對，
                // 而那正是讓錯的那一半顯得可信的原因。
                //
                // 工具裡沒有任何東西能檢查它：這個數字沒有 --json 欄位、沒有 -log 條目、
                // 也沒有 -debug 行。那則 WARN 是它唯一的報告，而兩份 README 都承諾了它。
                let dropped = max(0, offset - recOffset)
                Logger.shared.warn(
                    "--truncate-partial discarded \(dropped) bytes: an unterminated record beginning at byte \(recOffset). If the quote opened early, that is everything after it")
                fields = []
                rawBuf = []
                valBuf = []
                recordDirty = false
                return
            }
            if insideQuote {
                // A parallel worker calls finish() at the end of its CHUNK, not
                // at the end of the file, and this message was written for the
                // latter. On a chunk boundary that lands inside a quoted field
                // it said three wrong things at once: that the input ended
                // (the worker's view ended), which record was at fault (it
                // counts from the start of the chunk), and that
                // --truncate-partial would help (it would discard a complete
                // record). The same file gave the correct diagnosis at a
                // larger chunk size -- the parser contradicting itself about
                // what a file contains, decided by an environment variable.
                //
                // A chunk ending mid-quote means one thing: the file does not
                // have one record per line, which is the premise the parallel
                // path was given by the format or by an index. So say that,
                // and let the caller do what this tool does everywhere else
                // with a premise that turned out false -- discard it and scan.
                //
                // 平行工作者是在自己那「一塊」的結尾呼叫 finish()，不是在檔案結尾，而這則
                // 訊息是為後者寫的。當區塊邊界落在引號欄位中間，它一次說錯三件事：輸入結束了
                // （結束的是工作者的視野）、是哪一筆出問題（它是從區塊開頭數的）、以及
                // --truncate-partial 會有幫助（它會丟掉一筆完整的紀錄）。同一個檔案在較大的
                // chunk 下得到的是正確診斷——解析器對一個檔案的內容與自己矛盾，而決定權在一個
                // 環境變數手上。
                //
                // 區塊在引號中間結束只代表一件事：這個檔案不是一筆一行，而那正是格式或索引
                // 交給平行路徑的前提。所以就說那件事，讓呼叫端做這個工具在其他每一處對
                // 「前提被推翻」所做的事——丟掉它，改用掃描。
                if chunked {
                    throw fault(
                        "a chunk boundary fell inside a quoted field, so this file does not have one record per line -- which is what the parallel path was told it had",
                        "有一個區塊邊界落在引號欄位中間，因此這個檔案並不是一筆一行——而「一筆一行」正是平行路徑被告知的前提")
                }
                // The DATA record number, as faultAt has computed it since
                // round 38's CC. This message kept using the raw
                // `recordsEmitted + 1`, which counts the header rows, so on a
                // `.csv2` it named record 6 of a four-record file -- an
                // address that resolves to nothing when typed back into -get.
                // The correction existed a few lines above and this one call
                // site did not use it.
                // 資料紀錄號，與 faultAt 自第 38 回合的 CC 起所計算的一致。這則訊息一直沿用
                // 原始的 `recordsEmitted + 1`，那個計數含標頭列，於是在 `.csv2` 上它會把一個
                // 4 筆檔案的問題指名為第 6 筆——一個打回 `-get` 會解不出來的位址。那個修正
                // 就在上面幾行，而這一個呼叫點沒有用它。
                let n = max(1, recordsEmitted + 1 - format.headerRows)
                throw fault(
                    "record \(n): the input ends inside a quoted field -- the closing quote is missing. The record is incomplete; pass --truncate-partial to discard it.",
                    "第 \(n) 筆：輸入在引號欄位內就結束了——缺少收尾的引號。該紀錄不完整；要丟棄它請給 --truncate-partial。")
            }
            // `.csv2` without a trailing newline is reported by checkTornAppend
            // before parsing begins, so reaching here means the caller chose to
            // continue; emit it rather than inventing a second error.
            // `.csv2` 缺少結尾換行，在解析開始前就由 checkTornAppend 回報過了，
            // 因此走到這裡表示呼叫端選擇繼續；照常吐出，不要再造一個錯誤。
        }
        try endRecord()
    }
}

// ---------------------------------------------------------------------
// MARK: - Input / 輸入
// ---------------------------------------------------------------------

/// Reads in fixed-size chunks. Never "read the whole file": the memory has
/// to be bounded by the chunk size, not by the input size.
/// 以固定大小分塊讀取。絕不「整檔讀入」：記憶體上界必須由區塊大小決定，
/// 而非由輸入大小決定。
public final class ByteSource {
    private let handle: FileHandle
    private let closeOnDeinit: Bool
    let chunkSize: Int
    public private(set) var bytesRead = 0

    public init(path: String, chunkSize: Int = 1 << 16, startAt: UInt64 = 0) throws {
        // A FIFO is opened with a plain blocking open(2), not through
        // FileHandle. Foundation's opener does not wait for a writer, so
        // `csv2 -r -i fifo.csv` started before the writer arrived read EOF
        // immediately and reported `expected 1 header row(s), found 0` -- the
        // message for a file with nothing in it -- for a stream that was about
        // to deliver three lines. Every other Unix tool blocks there, and the
        // block is what removes the race: the reader waits, the writer opens,
        // the bytes arrive.
        //
        // Only for the non-regular case, so the ordinary path keeps the
        // FileHandle it has always had, seeking included.
        // FIFO 用一個單純的、會阻塞的 open(2) 開啟，不走 FileHandle。Foundation 的開檔不會
        // 等待寫入端，於是「在寫入端出現之前就啟動」的 `csv2 -r -i fifo.csv` 立刻讀到 EOF，
        // 並回報 `expected 1 header row(s), found 0`——那是「檔案裡什麼都沒有」的訊息——而那條
        // 串流其實正要送來三行。其他每一個 Unix 工具都會在那裡阻塞，而正是那個阻塞消除了
        // 這個競態：讀取端等待，寫入端開啟，位元組抵達。
        //
        // 只針對「非一般檔案」，因此原本那條路徑仍然用它一直以來的 FileHandle，seek 也照舊。
        if Platform.fileKind(path: path) == .fifo {
            let fd = Platform.openBlockingForRead(path: path)
            guard fd >= 0 else {
                throw fault("cannot open input file: \(path)", "無法開啟輸入檔：\(path)")
            }
            handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            closeOnDeinit = true
            self.chunkSize = chunkSize
            return
        }
        guard let h = FileHandle(forReadingAtPath: path) else {
            throw fault("cannot open input file: \(path)", "無法開啟輸入檔：\(path)")
        }
        // Seeking here is the whole point of the index: fetching record 10,000
        // becomes "read 8 bytes of index, seek, read one record" and the file
        // is never read at all. On the guest's QEMU disk a 100 MB file is
        // hundreds of milliseconds to a second, so what the index saves is
        // I/O, not CPU.
        // 在此 seek 正是索引的全部意義：取第 10,000 筆變成「讀 8 bytes 索引、
        // seek、讀一筆」，整個檔案根本不必讀進來。在 guest 的 QEMU 磁碟上，
        // 一個 100 MB 的檔案是數百 ms 到 1 秒，所以索引省下的是 I/O 而非 CPU。
        if startAt > 0 { h.seek(toFileOffset: startAt) }
        handle = h
        closeOnDeinit = true
        self.chunkSize = chunkSize
    }

    public init(stdin chunkSize: Int = 1 << 16) {
        handle = FileHandle.standardInput
        closeOnDeinit = false
        self.chunkSize = chunkSize
    }

    /// Bytes that are already in hand. One caller: a `.md` input, which is
    /// translated into canonical `.csv2` before the parser ever sees it, so
    /// that reading a Markdown table reuses every rule the .csv2 reader
    /// already enforces instead of growing a second parser that would drift
    /// from it.
    ///
    /// This one input is NOT streamed, and that is a deliberate trade with a
    /// bound on it: a Markdown table is a document somebody pasted, and the
    /// alternative is a second implementation of record parsing whose
    /// disagreements with the first would be found by users. The size limit
    /// lives beside the translation, in the shape `--pretty` already uses.
    ///
    /// 已經在手上的位元組。只有一個呼叫端：`.md` 輸入，它在解析器看到它之前就被翻譯成標準的
    /// `.csv2`，如此「讀一張 Markdown 表」就會沿用 .csv2 讀取器已經在執行的每一條規則，而不是
    /// 長出第二個會與它漂移的解析器。
    /// 這一個輸入**不是**串流的，那是一次刻意的取捨，而且有上界：一張 Markdown 表是某個人貼上來
    /// 的文件，而另一條路是「紀錄解析」的第二份實作——它與第一份的分歧會由使用者來發現。那個大小
    /// 上限就放在翻譯旁邊，形狀與 `--pretty` 已經在用的相同。
    public init(bytes: [UInt8], chunkSize: Int = 1 << 16) {
        handle = FileHandle.standardInput
        closeOnDeinit = false
        self.chunkSize = chunkSize
        self.memory = bytes
    }

    private var memory: [UInt8]? = nil
    private var memoryOffset = 0

    /// The pool is the point, not the read. Without it, every `Data` this
    /// returns survives on Darwin until the process exits, so peak RSS grows
    /// with the number of bytes read and `-si` buffers the whole stream --
    /// the opposite of what `-so`/`-si` promise. See Platform.drainingPool.
    /// 重點是那個 pool，不是那次讀取。沒有它，這裡回傳的每一個 `Data` 在 Darwin 上都會
    /// 活到行程結束，於是 peak RSS 隨「讀了多少位元組」成長、`-si` 等於整條串流都緩衝
    /// 了起來——與 `-si`／`-so` 的承諾正好相反。見 Platform.drainingPool。
    public func next() -> [UInt8]? {
        if let m = memory {
            guard memoryOffset < m.count else { return nil }
            let end = min(memoryOffset + chunkSize, m.count)
            let out = Array(m[memoryOffset ..< end])
            memoryOffset = end
            bytesRead += out.count
            return out
        }
        return Platform.drainingPool {
            let d = handle.readData(ofLength: chunkSize)
            if d.isEmpty { return nil }
            bytesRead += d.count
            return [UInt8](d)
        }
    }

    public func close() {
        if closeOnDeinit { try? handle.close() }
    }
}

// ---------------------------------------------------------------------
// MARK: - Output / 輸出
// ---------------------------------------------------------------------

/// Buffered, with a FIXED buffer that flushes as it fills. `-so` promises
/// not to buffer the whole output before writing, and a growable buffer
/// would quietly break that promise on a large file.
/// 具緩衝，但緩衝區是固定大小、滿了就寫出。`-so` 承諾不在寫出前緩衝整份
/// 輸出，而一個會長大的緩衝區會在大檔案上安靜地破壞那個承諾。
public final class ByteSink {
    private var buf: [UInt8] = []
    private let limit: Int
    /// Set for the stdout and stderr sinks: the two that can meet a reader
    /// who left. A file sink has no such fd and no such failure.
    /// 只有 stdout 與 stderr 這兩個 sink 會設定它——它們是會遇到「讀端離開」的那兩個。
    /// 檔案 sink 沒有這個描述子，也沒有那種失敗。
    private let pipeSafeFD: Int32?
    /// The descriptor every sink writes through -- the only thing it writes
    /// through. There was a FileHandle here as well until DV and EE removed
    /// every use of it: Windows will not hand out a descriptor from one, and
    /// FileHandle.write answers a failed write with an exception nobody
    /// catches. A field nothing reads is a claim that something does.
    /// 每個 sink 實際寫出所用的描述子——也是它唯一用來寫出的東西。這裡原本還有一個
    /// FileHandle，直到 DV 與 EE 把它的每一處使用都拿掉：Windows 不會從它交出描述子，
    /// 而 FileHandle.write 對「寫入失敗」的回答是一個沒有人接的例外。一個沒有人讀的欄位，
    /// 本身就是一句「有人在讀它」的宣稱。
    private let writeFD: Int32?
    private let tmpPath: String?
    private let finalPath: String?
    private var closed = false
    private(set) var bytesWritten = 0

    /// stdout / 標準輸出
    init(stdout limit: Int = 1 << 16) {
        pipeSafeFD = 1
        writeFD = 1
        self.limit = limit
        tmpPath = nil
        finalPath = nil
        buf.reserveCapacity(limit)
    }

    /// In-memory, for a parallel worker to build its fragment. It never
    /// flushes, so the fragment is bounded by what that one chunk produced --
    /// which is why only the locating report runs in parallel.
    /// 記憶體內，供平行工作者組出自己的片段。它不會 flush，因此片段的大小由那一個
    /// 區塊的產出決定——這正是只有定位報告走平行的原因。
    init(memory: Void) {
        pipeSafeFD = nil
        writeFD = nil
        self.limit = Int.max
        tmpPath = nil
        finalPath = nil
    }

    func takeBytes() -> [UInt8] {
        let b = buf
        buf.removeAll(keepingCapacity: false)
        return b
    }

    /// stderr / 標準錯誤
    init(stderr limit: Int = 1 << 13) {
        // stderr is fd 2, and a diagnostic stream can meet a broken pipe just
        // as stdout can -- `csv2 -debug … 2>&1 | head` is an ordinary thing to
        // type.
        // stderr 是 fd 2，而診斷串流與 stdout 一樣會遇到管線斷掉——
        // `csv2 -debug … 2>&1 | head` 是很平常的寫法。
        pipeSafeFD = 2
        writeFD = 2
        self.limit = limit
        tmpPath = nil
        finalPath = nil
        buf.reserveCapacity(limit)
    }

    /// Writes to a temp file beside the target and renames on close. rename
    /// is atomic within a filesystem, so a failure part-way through leaves
    /// the original intact -- this project already has two records of a CSV
    /// being written wrong and restored from git.
    /// 寫入目標檔旁的暫存檔，關閉時 rename。rename 在同一檔案系統內是原子的，
    /// 因此中途失敗時原檔完好——本專案已有兩次 CSV 被寫壞、靠 git 還原的紀錄。
    init(atomicPath path: String, limit: Int = 1 << 16) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        let dirPart = dir.isEmpty ? "." : dir
        let tmp = "\(dirPart)/.\(base).csv2tmp.\(Platform.processID())"
        guard let fd = Platform.openForWrite(path: tmp) else {
            let e = Platform.errorText(errno)
            throw fault("cannot create temporary file beside \(path): \(e)",
                        "無法在 \(path) 旁建立暫存檔：\(e)")
        }
        pipeSafeFD = nil
        writeFD = fd
        Platform.rememberTemp(tmp)
        self.limit = limit
        tmpPath = tmp
        finalPath = path
        buf.reserveCapacity(limit)
    }

    func write(_ bytes: [UInt8]) {
        buf.append(contentsOf: bytes)
        if buf.count >= limit { flush() }
    }

    func write(_ s: String) { write([UInt8](s.utf8)) }

    func flush() {
        if buf.isEmpty { return }
        // Every sink writes the same way. The file branch used to call
        // handle.write, on the reasoning that a file cannot meet a broken pipe
        // -- true, and beside the point: it can meet a full disk, and
        // FileHandle.write answers that with an exception nobody catches. A
        // -o edit onto a full volume aborted with exit 134, no diagnostic at
        // all, and its temp file left behind.
        // 每個 sink 都以同一種方式寫出。檔案那一支原本呼叫 handle.write，理由是「檔案
        // 不可能遇到管線斷掉」——那是對的，而且不是重點：它會遇到磁碟寫滿，而 FileHandle.write
        // 對此的回答是一個沒有人接的例外。一次寫到滿磁碟的 -o 編輯以 134 中止、一個字的
        // 診斷也沒有，並留下它的暫存檔。
        // 這裡原本還有一段更早的註解，說「stdout 不走 handle.write，而檔案 sink 仍然走」。
        // 那段話在改動之後就不再成立，卻與新的說明並排放著——兩段文字互相矛盾，而讀者沒有
        // 辦法知道哪一段是現在的。那正是本專案一再犯的第二種形狀：**新增文字，卻沒有作廢
        // 它所推翻的那一段。** 一併刪掉了。
        // An older comment sat here saying stdout does not go through
        // handle.write "while a file sink keeps it". That stopped being true
        // with this change and was left beside the new explanation, so two
        // paragraphs contradicted each other with nothing to say which was
        // current -- this project's second recurring shape: adding text
        // without invalidating what it makes false. Removed.
        if let fd = writeFD {
            let failure = Platform.writeAll(fd: fd, buf)
            if failure != 0 { writeFailed(failure) }
        }
        bytesWritten += buf.count
        buf.removeAll(keepingCapacity: true)
    }

    /// A write that could not be completed. Reported here and not thrown,
    /// because `flush()` is called from `write()`, which is called from every
    /// formatter in the program: making it throwing would put a `try` on every
    /// line of output for a condition that ends the run either way.
    ///
    /// The two-line bilingual shape and the exit status are the same ones
    /// main.swift produces for any other refusal, deliberately -- a caller
    /// reading stderr must not have to know that this one came from further
    /// down. The temp file goes first, so a failed run leaves nothing beside
    /// the target.
    /// 一次無法完成的寫入。在此回報而不是擲出，因為 `flush()` 是由 `write()` 呼叫的，而
    /// `write()` 被程式裡每一個格式化器呼叫：把它改成 throwing，等於為了一個「無論如何都
    /// 會結束這次執行」的狀況，在每一行輸出上加一個 `try`。
    /// 兩行雙語的形狀與結束狀態，與 main.swift 對其他任何拒絕所產生的完全相同，這是刻意的
    /// ——讀 stderr 的呼叫端，不該需要知道這一次是從更底層來的。暫存檔先刪，好讓一次失敗的
    /// 執行不會在目標旁邊留下任何東西。
    private func writeFailed(_ code: Int32) -> Never {
        let e = Platform.errorText(code)
        // Named in each language rather than once in English: "無法寫入 standard
        // output" is the kind of half-translated line that tells a reader the
        // Chinese half was an afterthought.
        // 兩種語言各自命名，而不是共用一份英文：「無法寫入 standard output」正是那種
        // 半翻譯的句子，它會告訴讀者中文那一半是事後補的。
        let whatEn = tmpPath != nil ? (finalPath ?? "the output file")
                                    : (pipeSafeFD == 2 ? "standard error" : "standard output")
        let whatZh = tmpPath != nil ? (finalPath ?? "輸出檔")
                                    : (pipeSafeFD == 2 ? "標準錯誤" : "標準輸出")
        if let tmp = tmpPath {
            if let fd = writeFD { Platform.closeFD(fd) }
            try? FileManager.default.removeItem(atPath: tmp)
            Platform.forgetTemp()
        }
        let en = "cannot write to \(whatEn): \(e)"
        let zh = "無法寫入 \(whatZh)：\(e)"
        Platform.writeAll(fd: 2, [UInt8]("csv2: \(lineEscape(en))\ncsv2：\(lineEscape(zh))\n".utf8))
        Logger.shared.close()
        exit(1)
    }

    func close() throws {
        if closed { return }
        closed = true
        flush()
        if let tmp = tmpPath, let final = finalPath {
            // Data to disk BEFORE the rename, or the rename can land while the
            // contents have not -- leaving a correctly named, empty file where
            // the old one used to be. rename alone protects concurrent readers;
            // it does not protect against a crash.
            // 先讓資料落地，再 rename；否則 rename 可能已經生效而內容還沒有——
            // 於是舊檔的位置上留下一個名字正確、內容是空的檔案。單靠 rename 保護的
            // 是並行讀者，不是當機。
            if !Platform.syncFD(writeFD ?? -1) {
                // A failed flush is not a reason to lose the write: report it
                // and continue, because the alternative is discarding data the
                // caller successfully produced.
                // flush 失敗不是丟掉這次寫入的理由：回報並繼續，因為另一個選擇是
                // 丟棄呼叫端已經成功產生的資料。
                Logger.shared.warn("could not flush \(tmp) to disk before renaming; the write is atomic for readers but may not survive a crash")
            }
            if let fd = writeFD { Platform.closeFD(fd) }
            // POSIX rename(2), not FileManager.replaceItemAt. rename is the
            // primitive the design actually calls for -- atomic within a
            // filesystem, so a reader either sees the whole old file or the
            // whole new one -- and it behaves identically on both platforms.
            // replaceItemAt is a Foundation abstraction that does more than
            // that (backup items, attribute preservation) and is a SEPARATE
            // implementation in swift-corelibs-foundation: on Linux it left
            // the destination unchanged, so --in-place silently did nothing
            // while exiting zero. Caught by T28b running in the guest, not by
            // anything on macOS.
            // 使用 POSIX rename(2)，而非 FileManager.replaceItemAt。rename 正是
            // 這份設計要的原語——在同一檔案系統內是原子的，讀者要嘛看到完整的舊
            // 檔、要嘛看到完整的新檔——而且兩個平台行為一致。replaceItemAt 是
            // Foundation 的抽象，做的事更多（備份項目、屬性保留），且在
            // swift-corelibs-foundation 中是另一份實作：在 Linux 上它讓目的檔
            // 維持不變，於是 --in-place 什麼也沒做卻以 0 結束。這是由 T28b 在
            // guest 內執行時抓到的，macOS 上沒有任何東西會發現。
            // The mode of the file being replaced, carried onto the temp file
            // BEFORE the rename. A temp file is created fresh with the umask's
            // mode, so without this an edit silently rewrote 0600 as 0644 --
            // an operation whose whole job is to change one cell, quietly
            // changing who can read the file.
            // 被取代的那個檔案的模式，在 rename「之前」套到暫存檔上。暫存檔是新建的，帶的是
            // umask 的模式，因此少了這一步，一次編輯會把 0600 靜默改寫成 0644——一個「工作
            // 就只是改一格」的操作，悄悄地改變了誰讀得到這個檔案。
            Platform.copyMode(from: final, to: tmp)
            Platform.forgetTemp()
            if !Platform.replaceFile(tmp, final) {
                let e = Platform.lastErrorText()
                try? FileManager.default.removeItem(atPath: tmp)
                throw fault("cannot rename \(tmp) onto \(final): \(e)",
                            "無法將 \(tmp) rename 為 \(final)：\(e)")
            }
        }
    }

    /// Abandon the temp file. Used on every error path so a failed run never
    /// leaves a half-written file where the target should be.
    /// 放棄暫存檔。所有錯誤路徑都會呼叫，讓失敗的執行不會在目標位置留下一個
    /// 寫到一半的檔案。
    func abort() {
        closed = true
        if let tmp = tmpPath {
            if let fd = writeFD { Platform.closeFD(fd) }
            try? FileManager.default.removeItem(atPath: tmp)
            Platform.forgetTemp()
        }
    }
}

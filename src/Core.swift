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
enum Format: String {
    case csv
    case csv2

    var headerRows: Int { self == .csv2 ? 2 : 1 }

    static func from(path: String) -> Format? {
        if path.hasSuffix(".csv2") { return .csv2 }
        if path.hasSuffix(".csv") { return .csv }
        return nil
    }

    /// True when the extension makes a promise about the content, so writing
    /// data rows without a header there would make the file lie about itself.
    /// 副檔名對內容做出承諾時為真；在那裡寫入不帶標頭的資料列，會讓檔案對
    /// 自己的格式說謊。
    static func declaresFormat(path: String) -> Bool {
        path.hasSuffix(".csv") || path.hasSuffix(".csv2")
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
struct Field {
    var raw: [UInt8]?
    var value: [UInt8]

    init(value: [UInt8], raw: [UInt8]? = nil) {
        self.value = value
        self.raw = raw
    }

    /// Any edit drops `raw`: the stored bytes no longer describe the value.
    /// 任何修改都會丟掉 `raw`：原樣的位元組已不再描述這個值。
    mutating func set(_ v: [UInt8]) { value = v; raw = nil }
}

struct Record {
    var fields: [Field]
    /// Byte offset of the record's first byte. / 該筆第一個位元組的偏移量。
    var offset: Int = 0
    /// Physical line the record starts on, 1-based. / 該筆起始的物理行號，1-based。
    var line: Int = 1
    /// 1-based data record number; 0 for header rows. / 1-based 資料紀錄號，標頭為 0。
    var number: Int = 0
    /// Which header row this is, when it is one: 0 for the English row, 1 for
    /// the Traditional Chinese row. nil for data. The report needs to tell them
    /// apart -- printing `0` for both made two identical lines that no reader
    /// could use, which is what `0a` / `0b` in the plan is for.
    /// 這是第幾列標頭（若它是標頭）：0 為英文列、1 為繁體中文列；資料為 nil。
    /// 報告必須能分辨兩者——兩列都印 `0` 會產生兩行完全相同、讀者無從使用的輸出，
    /// 而那正是計畫中 `0a` / `0b` 要解決的。
    var headerRow: Int? = nil

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
        var hasBackslash = false
        for b in v where b == BYTE_BACKSLASH { hasBackslash = true; break }
        if !hasBackslash { return v }

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

enum FieldEncoder {
    /// `preserveRaw` is only safe when the output format equals the input
    /// format. Writing `.csv` bytes into a `.csv2` file would carry a raw
    /// embedded newline across, breaking the one-record-per-line invariant.
    /// `preserveRaw` 只有在輸出格式與輸入格式相同時才安全。把 `.csv` 的原樣
    /// 位元組寫進 `.csv2`，會把原始的內嵌換行帶過去，破壞一筆一行的不變式。
    static func encode(_ f: Field, format: Format, preserveRaw: Bool) -> [UInt8] {
        if preserveRaw, let raw = f.raw { return raw }
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

    static func encodeRecord(_ r: Record, format: Format, preserveRaw: Bool) -> [UInt8] {
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

/// Push-based so that `-si` can stream: bytes go in a chunk at a time and
/// records come out as they complete. Nothing here ever holds the whole
/// input, because the tool has to work on files larger than the 2-4 GiB the
/// guest has.
/// 採推送式，讓 `-si` 能串流：位元組逐塊進來，紀錄完成一筆吐一筆。此處
/// 不持有整份輸入，因為本工具必須能處理比 guest 那 2–4 GiB 更大的檔案。
final class RecordParser {
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
    init(format: Format,
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

    func feed(_ chunk: [UInt8]) throws {
        var bytes = chunk
        if !bomDone {
            bomPending.append(contentsOf: bytes)
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
            if bomPending.count >= 2 {
                let b0 = bomPending[0], b1 = bomPending[1]
                if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
                    let which = b0 == 0xFF ? "UTF-16LE" : "UTF-16BE"
                    throw fault(
                        "this file begins with a \(which) byte-order mark; csv2 reads bytes and does not convert encodings, so it would parse as records that mean nothing. Convert it first with: iconv -f \(which) -t UTF-8 file > file.utf8",
                        "本檔案以 \(which) 的位元組順序記號開頭；csv2 讀的是位元組、不做編碼轉換，因此它會被解析成一堆沒有意義的紀錄。請先轉換：iconv -f \(which) -t UTF-8 file > file.utf8")
                }
            }
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
            try appendDataByte(BYTE_CR)
        }

        switch state {
        case .fieldStart, .unquoted:
            if b == BYTE_DQUOTE && state == .fieldStart {
                state = .quoted
                rawBuf.append(b)
                recordDirty = true
            } else if b == BYTE_COMMA {
                try endField()
            } else if b == BYTE_LF {
                sawLF = true
                lfCount += 1
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
        if format == .csv2 {
            value = try CSV2Escape.unescape(
                value, at: faultAt, atZh: faultAtZh, field: fields.count + 1)
        }
        fields.append(Field(value: value, raw: rawBuf))
        rawBuf = []
        valBuf = []
        state = .fieldStart
        quotedNewlineInField = false
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
        if r.count == 1 && looksLikeMarkdownSeparator(r.fields[0].value) {
            throw fault(
                "record \(r.number) (line \(r.line)) is a Markdown separator row in a file with one column, so this is -md output rather than CSV; -md is one-way and csv2 cannot read it back",
                "第 \(r.number) 筆（第 \(r.line) 行）是一列 Markdown 分隔列，且此檔只有一欄，因此這是 -md 的輸出而不是 CSV；-md 是單向的，csv2 讀不回來")
        }
        fields = []
        recordDirty = false
        recOffset = offset
        recLine = line
        if try !sink(r) { stopped = true }
    }

    /// Call once at end of input. Emits a trailing record if the file did not
    /// end with a newline, and reports the CR-only case.
    /// 輸入結束時呼叫一次。若檔案未以換行結尾則吐出最後一筆，並回報 CR-only。
    func finish() throws {
        if stopped { return }
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
            try appendDataByte(BYTE_CR)
        }
        // A CR-only file (pre-OS X Mac) contains no LF at all, so the whole
        // thing parses as ONE record with millions of fields and then hits
        // the field-count check -- whose message talks about field counts and
        // sends the user somewhere entirely unrelated. Diagnosing it costs
        // nothing; not diagnosing it costs an afternoon.
        // CR-only 檔案（OS X 之前的 Mac 慣例）完全沒有 LF，於是整份被解析成
        // 一筆有數百萬欄的紀錄，接著撞上欄數檢查——而那個訊息在講欄數，會把
        // 使用者引去一個完全無關的方向。診斷成本幾乎為零，少了它代價是一個下午。
        // Bare CRs outnumbering LFs is what a CR-separated file looks like,
        // with or without a stray LF at the end. A legitimate CSV can contain
        // a bare CR inside a quoted field, so the test is strictly greater:
        // one such CR in a one-record file must not trip it.
        // 「裸 CR 的數量多於 LF」正是一個以 CR 分隔的檔案的樣子，不論結尾有沒有多一個 LF。
        // 合法的 CSV 也可能在引號欄位裡含有裸 CR，因此這裡用「嚴格大於」：一筆紀錄裡的
        // 一個裸 CR 不能觸發它。
        if crAsDataCount > lfCount {
            throw fault(
                "this file uses CR line endings (the pre-OS X Mac convention), which CSV does not support; convert it first with: tr '\\r' '\\n' < file > file.lf",
                "本檔案使用 CR 行尾（OS X 之前的 Mac 慣例），非 CSV 所支援；請先轉換：tr '\\r' '\\n' < file > file.lf")
        }
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
                let dropped = rawBuf.count + valBuf.count
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
final class ByteSource {
    private let handle: FileHandle
    private let closeOnDeinit: Bool
    let chunkSize: Int
    private(set) var bytesRead = 0

    init(path: String, chunkSize: Int = 1 << 16, startAt: UInt64 = 0) throws {
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

    init(stdin chunkSize: Int = 1 << 16) {
        handle = FileHandle.standardInput
        closeOnDeinit = false
        self.chunkSize = chunkSize
    }

    /// The pool is the point, not the read. Without it, every `Data` this
    /// returns survives on Darwin until the process exits, so peak RSS grows
    /// with the number of bytes read and `-si` buffers the whole stream --
    /// the opposite of what `-so`/`-si` promise. See Platform.drainingPool.
    /// 重點是那個 pool，不是那次讀取。沒有它，這裡回傳的每一個 `Data` 在 Darwin 上都會
    /// 活到行程結束，於是 peak RSS 隨「讀了多少位元組」成長、`-si` 等於整條串流都緩衝
    /// 了起來——與 `-si`／`-so` 的承諾正好相反。見 Platform.drainingPool。
    func next() -> [UInt8]? {
        return Platform.drainingPool {
            let d = handle.readData(ofLength: chunkSize)
            if d.isEmpty { return nil }
            bytesRead += d.count
            return [UInt8](d)
        }
    }

    func close() {
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
final class ByteSink {
    private var buf: [UInt8] = []
    private let limit: Int
    private let handle: FileHandle
    /// Set only for the stdout sink. A file sink writes through `handle` --
    /// it cannot meet a broken pipe, and on Windows a FileHandle for a file
    /// cannot yield a descriptor at all.
    /// 只有 stdout 那個 sink 會設定它。檔案 sink 走 `handle` 寫出——它不可能遇到管線斷掉，
    /// 而在 Windows 上，指向檔案的 FileHandle 根本取不到描述子。
    private let pipeSafeFD: Int32?
    /// The descriptor every sink writes through. Kept beside the FileHandle
    /// because Windows will not hand one out from a FileHandle, and because a
    /// write has to be able to report WHY it failed -- which is what
    /// FileHandle.write cannot do without throwing an exception nobody catches.
    /// 每個 sink 實際寫出所用的描述子。與 FileHandle 並存，因為 Windows 不會從 FileHandle
    /// 交出描述子，也因為一次寫入必須說得出「為什麼失敗」——那正是 FileHandle.write 做不到
    /// 的事，它只會擲出一個沒有人接的例外。
    private let writeFD: Int32?
    private let tmpPath: String?
    private let finalPath: String?
    private var closed = false
    private(set) var bytesWritten = 0

    /// stdout / 標準輸出
    init(stdout limit: Int = 1 << 16) {
        handle = FileHandle.standardOutput
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
        handle = FileHandle.nullDevice
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
        handle = FileHandle.standardError
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
        // nullDevice, because this sink does not use a FileHandle at all --
        // see Platform.openForWrite for what happened when it did.
        // 用 nullDevice，因為這個 sink 根本不使用 FileHandle——它曾經使用過，後果見
        // Platform.openForWrite 的說明。
        handle = FileHandle.nullDevice
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
        // stdout does NOT go through handle.write: on Linux and Windows that
        // turns a broken pipe into a fatal error and a Swift backtrace. A file
        // sink keeps handle.write, which cannot meet one. See
        // Platform.writeAll.
        // stdout 不走 handle.write：在 Linux 與 Windows 上，它會把「管線斷掉」變成一個
        // 致命錯誤與一段 Swift backtrace。檔案 sink 仍走 handle.write，它不可能遇到那件事。
        // 見 Platform.writeAll。
        // Every sink writes the same way now. The file branch used to call
        // handle.write, on the reasoning that a file cannot meet a broken pipe
        // -- true, and beside the point: it can meet a full disk, and
        // FileHandle.write answers that with an exception nobody catches. A
        // -o edit onto a full volume aborted with exit 134, no diagnostic at
        // all, and its temp file left behind.
        // 現在每個 sink 都以同一種方式寫出。檔案那一支原本呼叫 handle.write，理由是「檔案
        // 不可能遇到管線斷掉」——那是對的，而且不是重點：它會遇到磁碟寫滿，而 FileHandle.write
        // 對此的回答是一個沒有人接的例外。一次寫到滿磁碟的 -o 編輯以 134 中止、一個字的
        // 診斷也沒有，並留下它的暫存檔。
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

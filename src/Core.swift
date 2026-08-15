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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
func echoValue(_ bytes: [UInt8], limit: Int = 40) -> String {
    guard let s = String(bytes: bytes, encoding: .utf8) else {
        // Not UTF-8. Render as hex so the message stays printable rather
        // than emitting raw bytes into someone's terminal.
        // 非 UTF-8，改以十六進位呈現，避免把原始位元組吐進終端機。
        let head = Array(bytes.prefix(limit))
        let hex = head.map { String(format: "%02x", $0) }.joined(separator: " ")
        return "<non-UTF-8: \(hex)\(bytes.count > limit ? " …" : "")>"
    }
    if s.count <= limit { return s }
    // Swift's Character IS a grapheme cluster, so prefix() cuts on a
    // cluster boundary by construction.
    // Swift 的 Character 就是 grapheme cluster，因此 prefix() 天生切在
    // cluster 邊界上。
    return String(s.prefix(limit)) + "…[+\(s.count - limit) more chars]"
}

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
    static func unescape(_ v: [UInt8], record: String, field: Int) throws -> [UInt8] {
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
                    "record \(record), field \(field): trailing lone backslash; write it as \\\\",
                    "第 \(record) 筆第 \(field) 欄：結尾有孤立的反斜線，應寫成 \\\\")
            }
            let n = v[i + 1]
            switch n {
            case 0x6E: out.append(BYTE_LF)
            case 0x72: out.append(BYTE_CR)
            case 0x5C: out.append(BYTE_BACKSLASH)
            default:
                let seq = String(bytes: [BYTE_BACKSLASH, n], encoding: .utf8) ?? "\\?"
                throw fault(
                    "record \(record), field \(field): undefined escape sequence \(seq); .csv2 defines only \\n, \\r and \\\\",
                    "第 \(record) 筆第 \(field) 欄：未定義的跳脫序列 \(seq)；.csv2 只定義 \\n、\\r 與 \\\\")
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

    private(set) var sawLF = false
    private(set) var sawCRAsData = false
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

    /// `firstRecordNumber`, `firstOffset` and `firstLine` let parsing resume
    /// at an index grid point while producing exactly the numbers a full scan
    /// would have produced. Output with and without an index has to be
    /// byte-identical, and the record numbers are part of the output.
    /// `firstRecordNumber`、`firstOffset` 與 `firstLine` 讓解析能從索引格點恢復，
    /// 同時產生與完整掃描完全相同的編號。有無索引的輸出必須逐位元相同，而紀錄號
    /// 就是輸出的一部分。
    init(format: Format, sink: @escaping (Record) throws -> Bool,
         firstRecordNumber: Int = 1, firstOffset: Int = 0, firstLine: Int = 1) {
        self.format = format
        self.sink = sink
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

    func feed(_ chunk: [UInt8]) throws {
        var bytes = chunk
        if !bomDone {
            bomPending.append(contentsOf: bytes)
            if bomPending.count < BOM.count {
                return // wait for more; a 1-byte file cannot carry a BOM anyway
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
                "record \(recordsEmitted + 1), field \(fields.count + 1): unexpected byte after a closing quote (0x\(String(format: "%02x", b))); a quoted field must be followed by a comma or a line ending",
                "第 \(recordsEmitted + 1) 筆第 \(fields.count + 1) 欄：關閉引號之後出現非預期的位元組（0x\(String(format: "%02x", b))）；引號欄位之後只能接逗號或行尾")
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
                "record \(recordsEmitted + 1), field \(fields.count + 1): a raw newline inside a cell; .csv2 keeps one record per line, so newlines must be written as \\n",
                "第 \(recordsEmitted + 1) 筆第 \(fields.count + 1) 欄：儲存格內有原始換行；.csv2 保證一筆一行，換行必須寫成 \\n")
        }
        var value = valBuf
        if format == .csv2 {
            value = try CSV2Escape.unescape(
                value,
                record: recordsEmitted < format.headerRows ? "header" : "\(recordsEmitted + 1)",
                field: fields.count + 1)
        }
        fields.append(Field(value: value, raw: rawBuf))
        rawBuf = []
        valBuf = []
        state = .fieldStart
        quotedNewlineInField = false
        recordDirty = true
    }

    private func endRecord() throws {
        try endField()
        var r = Record(fields: fields, offset: recOffset, line: recLine)
        recordsEmitted += 1
        r.number = recordsEmitted
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
        if !sawLF && sawCRAsData {
            throw fault(
                "this file uses CR line endings (the pre-OS X Mac convention), which CSV does not support; convert it first with: tr '\\r' '\\n' < file > file.lf",
                "本檔案使用 CR 行尾（OS X 之前的 Mac 慣例），非 CSV 所支援；請先轉換：tr '\\r' '\\n' < file > file.lf")
        }
        if recordDirty || !fields.isEmpty || !rawBuf.isEmpty || !valBuf.isEmpty {
            try endRecord()
        }
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

    func next() -> [UInt8]? {
        let d = handle.readData(ofLength: chunkSize)
        if d.isEmpty { return nil }
        bytesRead += d.count
        return [UInt8](d)
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
    private let tmpPath: String?
    private let finalPath: String?
    private var closed = false
    private(set) var bytesWritten = 0

    /// stdout / 標準輸出
    init(stdout limit: Int = 1 << 16) {
        handle = FileHandle.standardOutput
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
        let tmp = "\(dirPart)/.\(base).csv2tmp.\(getpid())"
        FileManager.default.createFile(atPath: tmp, contents: nil)
        guard let h = FileHandle(forWritingAtPath: tmp) else {
            throw fault("cannot create temporary file beside \(path)", "無法在 \(path) 旁建立暫存檔")
        }
        handle = h
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
        handle.write(Data(buf))
        bytesWritten += buf.count
        buf.removeAll(keepingCapacity: true)
    }

    func close() throws {
        if closed { return }
        closed = true
        flush()
        if let tmp = tmpPath, let final = finalPath {
            try? handle.close()
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
            if rename(tmp, final) != 0 {
                let e = String(cString: strerror(errno))
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
            try? handle.close()
            try? FileManager.default.removeItem(atPath: tmp)
        }
    }
}

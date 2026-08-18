// =====================================================================
//  Ops.swift — the operations: select, search, edit, append, transform
//  Ops.swift — 各項操作：選取、搜尋、編輯、追加、轉換
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - Byte search / 位元組搜尋
// ---------------------------------------------------------------------

/// Comparison happens on the DECODED value, not the raw bytes. Searching for
/// `b,c` in `a,"b,c",d` must hit field 2; matching raw bytes would "find" it
/// across a quote, at a position that maps to no single cell.
/// 比對的是解碼後的值，不是原始位元組。在 `a,"b,c",d` 中搜尋 `b,c` 必須命中
/// 欄位 2；比對原始位元組會「找到」它，但那個位置跨越了引號，無法對應到任何
/// 單一儲存格。
func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    if needle.isEmpty { return true }
    if needle.count > haystack.count { return false }
    let first = needle[0]
    let last = haystack.count - needle.count
    var i = 0
    while i <= last {
        if haystack[i] == first {
            var j = 1
            while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
            if j == needle.count { return true }
        }
        i += 1
    }
    return false
}

/// Normalisation NEVER touches what is stored -- that would change bytes and
/// break the byte-identical round-trip, which is the first and most valuable
/// test. It applies to comparison only, and only when asked for, because
/// `--normalize` separates "what you can find" from "what is actually in the
/// file" and that gap has to be something the user asked for.
/// 正規化絕不動已儲存的內容——那會改動位元組，破壞逐位元相同的 round-trip，
/// 也就是第一個、也最有價值的測試。它只作用於比對，且只在被要求時，因為
/// `--normalize` 會讓「找得到」與「檔案裡實際是什麼」分離，那個差異必須是
/// 使用者明確要求的。
func normalizedBytes(_ v: [UInt8]) -> [UInt8] {
    guard let s = String(bytes: v, encoding: .utf8) else { return v }
    return [UInt8](s.precomposedStringWithCanonicalMapping.utf8)
}

// ---------------------------------------------------------------------
// MARK: - Emitters / 輸出器
// ---------------------------------------------------------------------

struct EmitContext {
    var format: Format
    var headers: [Record]
    var withHeader: Bool
    var rownum: Bool
    var zh: Bool
    var physical: Bool
    var a1: Bool
    var jsonASCII: Bool
    var enOnly: Bool
    var preserveRaw: Bool
    /// True when -A/-B/-C is in force. Those flags imply --filter, and a
    /// filtered stream of records normally needs no marking because every
    /// record in it matched. With context it does: the emitted records are a
    /// mixture, and without a mark the only trace that a match happened at all
    /// is the trailing `matched` count -- a bare number with nothing to attach
    /// it to.
    /// -A/-B/-C 生效時為 true。那些旗標隱含 --filter，而經過篩選的紀錄串流通常不需要
    /// 標記，因為裡面每一筆都是命中。有了上下文就需要了：送出的紀錄是混在一起的，
    /// 而少了標記，「曾經有命中」這件事唯一的痕跡就是末行的 matched 計數——一個沒有東西
    /// 可以掛上去的裸數字。
    var contextActive: Bool = false
}

protocol RecordEmitter: AnyObject {
    func begin(_ ctx: EmitContext) throws
    /// `matches` lists the 0-based field indices that matched, for the
    /// locating report. Empty means "this is a context or plain record".
    /// `matches` 是命中的 0-based 欄位索引，供定位報告使用；空的表示這是
    /// 上下文或一般紀錄。
    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws
    func gap(_ ctx: EmitContext) throws
    func end(_ ctx: EmitContext, records: Int, matched: Int) throws
}

func columnLabel(_ ctx: EmitContext, _ index: Int) -> String {
    guard let h = ctx.headers.first else { return "\(index + 1)" }
    let row = ctx.zh && ctx.headers.count > 1 ? ctx.headers[1] : h
    guard index < row.count else { return "\(index + 1)" }
    return baseName(headerName(row.fields[index]))
}

/// A1 notation is offered but never the default: CSV need not have a header
/// and its column count need not be constant, so making A1 primary would
/// make it a lie on exactly those files.
/// 提供 A1 記法但絕不作為預設：CSV 未必有標頭、欄數未必一致，把 A1 當主要
/// 格式會在那些檔案上變成謊言。
func a1Column(_ index: Int) -> String {
    var n = index
    var s = ""
    repeat {
        s = String(UnicodeScalar(UInt8(65 + n % 26))) + s
        n = n / 26 - 1
    } while n >= 0
    return s
}

func rownumHeaderFields(_ ctx: EmitContext, row: Int) -> Field {
    // A column added to the output must be named in BOTH header rows.
    // Without this the header would have one field fewer than the data --
    // which is the very "field count mismatch" the tool refuses to accept,
    // manufactured by the tool itself.
    // 輸出新增的欄位在兩列標頭都要有名字。少了這一步，標頭的欄數就會比資料
    // 少一——正是這支工具自己要擋的「欄數不符」，而且是它自己製造出來的。
    Field(value: [UInt8]((row == 1 ? "列號" : "rownum").utf8))
}

final class CSVEmitter: RecordEmitter {
    private let sink: ByteSink
    init(sink: ByteSink) { self.sink = sink }

    func begin(_ ctx: EmitContext) throws {
        guard ctx.withHeader else { return }
        for (i, h) in ctx.headers.enumerated() {
            var r = h
            if ctx.rownum { r.fields.insert(rownumHeaderFields(ctx, row: i), at: 0) }
            sink.write(FieldEncoder.encodeRecord(r, format: ctx.format,
                                                 preserveRaw: ctx.preserveRaw && !ctx.rownum))
        }
    }

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        var rec = r
        if ctx.rownum {
            rec.fields.insert(Field(value: [UInt8]("\(r.number)".utf8)), at: 0)
        }
        sink.write(FieldEncoder.encodeRecord(rec, format: ctx.format,
                                             preserveRaw: ctx.preserveRaw && !ctx.rownum))
    }

    /// grep prints `--` between non-adjacent blocks and so do we. It is
    /// documented as a separator rather than data, because a downstream
    /// script that treats it as a record gets one bogus row per block.
    /// grep 在不相鄰的區塊之間印 `--`，此處照做。它在說明中被標示為分隔線而
    /// 非資料，否則下游腳本每個區塊會多讀到一筆假的紀錄。
    func gap(_ ctx: EmitContext) throws { sink.write("--\n") }

    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {}
}

/// The report is TAB-separated, one line per matching cell, and a value is
/// arbitrary CSV content -- so a cell containing a TAB or a newline would break
/// the very format the report promises. It did: three matching cells produced
/// four lines, `cut -f1` returned a fragment of prose where an address belongs,
/// and csv2 exited 0. That is this project's signature failure -- a plausible
/// but wrong result reported as success -- happening in the tool's own
/// recommended script interface, on quoted prose, which is the column type that
/// caused the incident csv2 was built after.
/// 報告以 TAB 分隔、每個命中的儲存格一行，而「值」是任意的 CSV 內容——因此含有 TAB
/// 或換行的儲存格會破壞報告自己承諾的格式。它確實破壞了：三個命中的儲存格產生四行、
/// `cut -f1` 在該是位址的地方回傳一段散文，而 csv2 以 0 結束。那正是本專案的招牌
/// 失敗——看似合理但錯誤的結果以成功回報——而且發生在工具自己推薦的腳本介面上，
/// 就在「帶引號的散文」這個當初引發事故的欄位型別上。
///
/// Escaped with the SAME backslash convention `.csv2` already uses, plus `\t`
/// because TAB is this format's own delimiter. Reusing the convention rather
/// than inventing one means a reader who knows the file format already knows
/// how to read the report.
/// 以 `.csv2` 既有的反斜線慣例跳脫，另加 `\t`——因為 TAB 是這個格式自己的分隔符。
/// 沿用既有慣例而非發明新的，讓看得懂檔案格式的人不必再學一套就能讀報告。
func reportEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "\\": out += "\\\\"
        case "\t": out += "\\t"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        default: out.append(ch)
        }
    }
    return out
}

/// `-get r:c` prints ONE cell's value and nothing else -- no quoting, no
/// delimiter, no header, no address. The value as it was stored, decoded.
///
/// Not CSV, deliberately. A one-cell CSV row would need quoting whenever the
/// value contained a comma, and the caller would then have to decode it: the
/// exact detour that made reading a known address require --json plus a
/// selection plus an external parser. What a caller wants from an address is
/// the value.
///
/// A trailing newline, so `$(csv2 -get ...)` behaves like every other command
/// substitution -- the shell strips it. A value containing newlines comes back
/// containing them; nothing is escaped, because escaping would be a format, and
/// this is deliberately not one. If you need a value whose own newlines matter,
/// --json is the shape that can carry it unambiguously.
///
/// `-get r:c` 只印出「一格」的值，別的什麼都不印——沒有引號、沒有分隔符、沒有標頭、
/// 沒有位址。就是儲存時的值，解碼後。
/// 刻意不是 CSV。只有一格的 CSV 列，在值含逗號時仍需加引號，於是呼叫端還得再解碼一次
/// ——那正是「讀取一個已知位址」原本得繞道 --json 加選取加外部解析器的那條彎路。
/// 呼叫端要的是「值」。
/// 結尾帶一個換行，讓 `$(csv2 -get ...)` 的行為與其他命令替換一致（shell 會去掉它）。
/// 值本身含換行時就照樣帶著換行回來，不做任何跳脫——跳脫就是一種格式，而這裡刻意不是。
/// 若你需要一個「自身換行有意義」的值，--json 才是能明確承載它的形狀。
final class CellEmitter: RecordEmitter {
    private let sink: ByteSink
    private let column: String
    private var wrote = false
    init(sink: ByteSink, column: String) { self.sink = sink; self.column = column }

    func begin(_ ctx: EmitContext) throws {}

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        guard let header = ctx.headers.first else {
            throw fault("-get needs a header to resolve the column against",
                        "-get 需要標頭才能解析欄位")
        }
        let c = try resolveColumn(column, header: header)
        guard c < r.count else {
            throw fault("record \(r.number) has \(r.count) fields; there is no field \(c + 1)",
                        "第 \(r.number) 筆有 \(r.count) 欄；沒有第 \(c + 1) 欄")
        }
        sink.write(r.fields[c].value)
        sink.write("\n")
        wrote = true
    }

    func gap(_ ctx: EmitContext) throws {}

    /// Out of range is an error, not an empty line. An empty line is what an
    /// EXISTING empty cell looks like, and a caller cannot tell the two apart
    /// -- so the one that means "your address was wrong" has to be the one that
    /// exits non-zero.
    /// 越界是錯誤，不是一個空行。空行正是「一個確實存在的空儲存格」的樣子，呼叫端分不出
    /// 兩者——因此「你的位址是錯的」那一個，必須是以非零結束的那一個。
    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {
        if !wrote {
            throw fault("-get: no such record; the file has \(records) records",
                        "-get：沒有這一筆；本檔案有 \(records) 筆紀錄")
        }
    }
}

final class ReportEmitter: RecordEmitter {
    private let sink: ByteSink
    private let needle: [UInt8]
    init(sink: ByteSink, needle: [UInt8]) { self.sink = sink; self.needle = needle }

    func begin(_ ctx: EmitContext) throws {}

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        // One line per matching CELL, because the unit is a cell. Two matching
        // columns in one record are two different locations and print twice;
        // two occurrences inside one cell are one location and print once.
        // 每個命中的儲存格印一行，因為單位是儲存格。同一筆有兩欄命中就印兩行，
        // 那是兩個不同的位置；同一儲存格內出現兩次是同一個位置，只印一次。
        for idx in matches {
            // `0a` / `0b` for the two header rows, as the plan specifies. The
            // header does not take a data record number, so "record N" always
            // means the Nth record of DATA.
            // 兩列標頭分別是 `0a` / `0b`，如計畫所定。標頭不佔用資料的編號，
            // 因此「第 N 筆」永遠指第 N 筆資料。
            let label: String
            if let hr = r.headerRow {
                label = ctx.headers.count > 1 ? "0\(hr == 0 ? "a" : "b")" : "0"
            } else {
                label = "\(r.number)"
            }
            var addr = "\(label):\(idx + 1)"
            if ctx.physical { addr += "@L\(r.line)" }
            // The A1 row is the PHYSICAL line, because that is what a
            // spreadsheet calls a row. Using the record number made csv2 print
            // [A1] for a cell that any spreadsheet would call A3, and [E0] for a
            // header -- and A1 notation has no row 0.
            // A1 的列號取「物理行號」，因為試算表所稱的列就是那個。用紀錄號會讓
            // csv2 對一個任何試算表都會叫作 A3 的儲存格印出 [A1]，並對標頭印出
            // [E0]——而 A1 記法沒有第 0 列。
            if ctx.a1 { addr += " [\(a1Column(idx))\(r.line)]" }
            // Both fields are escaped: a header name can contain a TAB just as
            // a value can, and one bad name would shift every column.
            // 兩個欄位都要跳脫：欄名與值一樣可能含 TAB，而一個壞掉的欄名會讓
            // 每一欄都位移。
            let name = reportEscape(columnLabel(ctx, idx))
            let value = reportEscape(echoValue(r.fields[idx].value, limit: 200))
            sink.write("\(addr)\t\(name)\t\(value)\n")
        }
    }

    func gap(_ ctx: EmitContext) throws {}
    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {}
}

final class JSONEmitter: RecordEmitter {
    private let sink: ByteSink
    private let reportMode: Bool
    init(sink: ByteSink, reportMode: Bool) { self.sink = sink; self.reportMode = reportMode }

    func begin(_ ctx: EmitContext) throws {
        // JSON Lines, not one big array, so it streams -- consistent with
        // `-so` promising not to buffer the whole output.
        // 採 JSON Lines 而非一個大陣列，如此才能串流——與 `-so` 承諾不緩衝整份
        // 輸出一致。
        let fields = ctx.headers.first?.count ?? 0
        // Which columns are protected, and how. The CSV header carries the
        // marker (`license:hash`, `license:hmac:<fp>`, `license:enc:…`) but the
        // JSON keys are the clean names, so without this a JSON consumer cannot
        // tell a masked column from a plain one -- and the whole point of this
        // meta line is that a caller can assert what it is reading instead of
        // accepting a wrong guess.
        // 哪些欄位受保護、以哪一種方式。CSV 標頭帶著標記（`license:hash`、
        // `license:hmac:<fp>`、`license:enc:…`），但 JSON 的鍵是乾淨的欄名，
        // 因此少了這一項，JSON 的消費端分不出被遮蔽的欄位與一般欄位——而這行
        // metadata 的全部意義，就是讓呼叫端能斷言自己讀到的是什麼，而不是接受
        // 一個猜錯的解析。
        var protected: [String] = []
        for f in ctx.headers.first?.fields ?? [] {
            let n = headerName(f)
            if EncMarker.parse(n) != nil {
                protected.append("\(JSONOut.string([UInt8](baseName(n).utf8), asciiOnly: ctx.jsonASCII)):\"enc\"")
            } else if n.hasSuffix(":hash") {
                protected.append("\(JSONOut.string([UInt8](baseName(n).utf8), asciiOnly: ctx.jsonASCII)):\"hash\"")
            } else if n.range(of: ":hmac:", options: .backwards) != nil {
                protected.append("\(JSONOut.string([UInt8](baseName(n).utf8), asciiOnly: ctx.jsonASCII)):\"hmac\"")
            }
        }
        let prot = protected.isEmpty ? "" : ",\"protected\":{" + protected.joined(separator: ",") + "}"
        sink.write("{\"meta\":{\"format\":\"\(ctx.format.rawValue)\",\"headers\":\(ctx.headers.count),\"fields\":\(fields)\(prot)}}\n")
    }

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        if reportMode {
            for idx in matches {
                var parts = ["\"record\":\(r.number)", "\"field\":\(idx + 1)"]
                if let h = ctx.headers.first, idx < h.count {
                    parts.append("\"header_en\":\(JSONOut.string(h.fields[idx].value, asciiOnly: ctx.jsonASCII))")
                }
                if ctx.headers.count > 1, idx < ctx.headers[1].count {
                    parts.append("\"header_zh\":\(JSONOut.string(ctx.headers[1].fields[idx].value, asciiOnly: ctx.jsonASCII))")
                }
                parts.append("\"value\":\(JSONOut.string(r.fields[idx].value, asciiOnly: ctx.jsonASCII))")
                parts.append("\"line\":\(r.line)")
                sink.write("{" + parts.joined(separator: ",") + "}\n")
            }
            return
        }
        var parts = ["\"record\":\(r.number)", "\"line\":\(r.line)"]
        // Only when context is on. Without it every emitted record matched, so
        // the key would be constant true on every line -- noise that a consumer
        // has to read and can never learn anything from, and a change to output
        // that is already documented and tested.
        // 只在有上下文時加。沒有上下文時，送出的每一筆都是命中，這個鍵會在每一行都是
        // 固定的 true——那是消費端必須讀、卻永遠學不到東西的雜訊，也會更動一份已經被
        // 記載且被測試的輸出。
        if ctx.contextActive {
            parts.append("\"match\":\(matches.isEmpty ? "false" : "true")")
        }
        var cells: [String] = []
        for (i, f) in r.fields.enumerated() {
            let key = ctx.headers.first.map { i < $0.count ? baseName(headerName($0.fields[i])) : "\(i + 1)" } ?? "\(i + 1)"
            cells.append("\(JSONOut.string([UInt8](key.utf8), asciiOnly: ctx.jsonASCII)):\(JSONOut.string(f.value, asciiOnly: ctx.jsonASCII))")
        }
        parts.append("\"fields\":{" + cells.joined(separator: ",") + "}")
        sink.write("{" + parts.joined(separator: ",") + "}\n")
    }

    func gap(_ ctx: EmitContext) throws {}

    /// The record count cannot be in the FIRST meta line without reading the
    /// whole input before writing anything, which is the streaming guarantee
    /// the plan makes a hard requirement. So the count comes last, in a
    /// second meta line, rather than the guarantee being quietly dropped.
    /// 紀錄總數無法放進第一行 metadata，除非先讀完整份輸入才開始輸出——而那正是
    /// 計畫列為硬需求的串流保證。因此總數放在最後一行的第二個 metadata 中，
    /// 而不是安靜地放棄那個保證。
    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {
        sink.write("{\"meta\":{\"records\":\(records),\"matched\":\(matched)}}\n")
    }
}

final class MarkdownEmitter: RecordEmitter {
    private let sink: ByteSink
    private var wroteHeader = false
    private let pretty: Bool
    /// Only used by --pretty. Column widths cannot be known until every row
    /// has been seen, so aligning means holding the table. That is the trade
    /// the flag makes, and it is why it is not the default.
    /// 只有 --pretty 會用到。欄寬要看過每一列才知道，因此對齊就等於必須持有整張
    /// 表。這就是這個旗標所做的取捨，也是它不作為預設的原因。
    private var buffered: [[String]] = []
    private var bufferedBytes = 0
    private var headerCells: [String] = []

    init(sink: ByteSink, pretty: Bool = false) {
        self.sink = sink
        self.pretty = pretty
    }

    private func prettyLimit() -> Int {
        if let v = ProcessInfo.processInfo.environment["CSV2_PRETTY_MAX_BYTES"], let n = Int(v) {
            return n
        }
        return 16 * 1024 * 1024
    }

    func begin(_ ctx: EmitContext) throws {
        var names: [String] = []
        if ctx.rownum { names.append("rownum<br>列號") }
        for i in 0..<(ctx.headers.first?.count ?? 0) {
            // A Markdown table has ONE header row and .csv2 has two. Merging
            // them into one cell with <br> matches how this project's docs
            // already present both languages side by side.
            // Markdown 表格只有一列標頭而 .csv2 有兩列。以 <br> 併入同一個
            // 儲存格，與本專案文件雙語並列的既有習慣一致。
            let en = MarkdownOut.cell(ctx.headers[0].fields[i].value)
            if ctx.headers.count > 1 && i < ctx.headers[1].count {
                let zh = MarkdownOut.cell(ctx.headers[1].fields[i].value)
                // --zh Chinese only, --en English only, neither merges both.
                // `--en` used to be indistinguishable from giving no flag at
                // all, which made it look implemented when it was not.
                // --zh 只取中文、--en 只取英文，都不給則兩者合併。`--en` 原本與
                // 「完全不給旗標」逐位元相同，讓它看起來已實作，其實沒有。
                names.append(ctx.zh ? zh : (ctx.enOnly ? en : "\(en)<br>\(zh)"))
            } else {
                names.append(en)
            }
        }
        wroteHeader = true
        if pretty {
            headerCells = names
            return
        }
        sink.write("|" + names.joined(separator: "|") + "|\n")
        sink.write("|" + names.map { _ in "---" }.joined(separator: "|") + "|\n")
    }

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        var cells: [String] = []
        if ctx.rownum { cells.append("\(r.number)") }
        cells.append(contentsOf: r.fields.map { MarkdownOut.cell($0.value) })
        if pretty {
            for c in cells { bufferedBytes += c.utf8.count }
            // Refuse above the limit rather than try and get killed. --pretty
            // has already given up streaming, so on a large file the failure
            // mode is the OOM killer, not slowness -- and a process that is
            // killed leaves no message at all.
            // 超過上限時拒絕，而不是硬做然後被殺掉。--pretty 已經放棄串流，因此
            // 在大檔案上的失敗模式是被 OOM killer 終結而非變慢——而被殺掉的行程
            // 不會留下任何訊息。
            if bufferedBytes > prettyLimit() {
                throw fault(
                    "-md --pretty has to hold the whole table to align it, and this one is over \(prettyLimit()) bytes; drop --pretty (the unaligned form renders identically) or raise CSV2_PRETTY_MAX_BYTES",
                    "-md --pretty 必須持有整張表才能對齊，而這一張超過 \(prettyLimit()) 位元組；請拿掉 --pretty（未對齊的形式呈現結果完全相同），或調高 CSV2_PRETTY_MAX_BYTES")
            }
            buffered.append(cells)
            return
        }
        sink.write("|" + cells.joined(separator: "|") + "|\n")
    }

    func gap(_ ctx: EmitContext) throws {}

    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {
        guard pretty else { return }
        let n = max(headerCells.count, buffered.map { $0.count }.max() ?? 0)
        var widths = [Int](repeating: 0, count: n)
        for (i, c) in headerCells.enumerated() { widths[i] = max(widths[i], DisplayWidth.of(c)) }
        for row in buffered {
            for (i, c) in row.enumerated() where i < n {
                widths[i] = max(widths[i], DisplayWidth.of(c))
            }
        }
        func line(_ cells: [String]) -> String {
            var out = "|"
            for i in 0..<n {
                let c = i < cells.count ? cells[i] : ""
                out += " " + DisplayWidth.pad(c, to: widths[i]) + " |"
            }
            return out + "\n"
        }
        sink.write(line(headerCells))
        var sep = "|"
        for i in 0..<n { sep += String(repeating: "-", count: widths[i] + 2) + "|" }
        sink.write(sep + "\n")
        for row in buffered { sink.write(line(row)) }
    }
}

// ---------------------------------------------------------------------
// MARK: - Column transforms / 欄位轉換
// ---------------------------------------------------------------------

enum CellTransform {
    case none
    case encrypt(columns: [Int], key: [UInt8], fingerprint: String, salt: [UInt8], names: [String])
    case decrypt(columns: [Int], key: [UInt8], names: [String])
    /// `key` nil means plain SHA-256: deterministic, so equal values still
    /// compare equal, and dictionary-attackable for exactly that reason. With a
    /// key it is HMAC-SHA256: still deterministic, but an attacker without the
    /// key cannot build the dictionary.
    /// `key` 為 nil 時是純 SHA-256：確定性的，因此相等的值仍然相等——也正因為
    /// 確定性，它可被字典攻擊。給了金鑰則是 HMAC-SHA256：同樣是確定性的，但沒有
    /// 金鑰的攻擊者建不出那份字典。
    case hash(columns: [Int], key: [UInt8]?, fingerprint: String?)

    /// The columns this transform touches, whichever it is. Used to refuse a
    /// transform aimed at a column `-delete -col` is removing -- a check that
    /// would otherwise have to repeat the case list and would fall out of date
    /// the first time a fourth transform is added.
    /// 不論是哪一種轉換，它所觸及的欄位。用於拒絕「針對正被 -delete -col 移除之欄位」
    /// 的轉換——否則那個檢查得把 case 列表再抄一次，而在加入第四種轉換的當下就會過時。
    var columns: [Int] {
        switch self {
        case .none: return []
        case .encrypt(let c, _, _, _, _): return c
        case .decrypt(let c, _, _): return c
        case .hash(let c, _, _): return c
        }
    }

    var flagName: String {
        switch self {
        case .none: return ""
        case .encrypt: return "-encrypt"
        case .decrypt: return "-decrypt"
        case .hash: return "-hash"
        }
    }
}

/// Ciphertext must become text, since CSV is a text format. base64's alphabet
/// (A-Za-z0-9+/=) contains no comma, quote or newline, so it needs no further
/// escaping. The cell grows: nonce 12 + tag 16, then 4/3 for base64.
/// 密文必須編碼成文字，因為 CSV 是文字格式。base64 的字元集（A-Za-z0-9+/=）
/// 不含逗號、引號或換行，因此不需額外跳脫。儲存格會變長：nonce 12 + 標籤 16，
/// 再乘上 base64 的 4/3。
func applyTransform(_ t: CellTransform, to record: inout Record, header: Record) throws {
    switch t {
    case .none:
        return

    case .encrypt(let cols, let key, _, _, let names):
        for (n, c) in cols.enumerated() {
            guard c < record.count else { continue }
            // A fresh nonce every time. Reusing one destroys ChaCha20-Poly1305
            // entirely, so this is not optional -- and it is why the same
            // plaintext gives different ciphertext on every run.
            // 每次都用新的 nonce。重用會徹底摧毀 ChaCha20-Poly1305，因此這不是
            // 選項——也正因如此，同樣的明文每次會產生不同的密文。
            let nonce = cryptoRandomBytes(12)
            let aad = [UInt8](names[n].utf8)
            let sealed = ChaChaPoly.seal(plaintext: record.fields[c].value,
                                         key: key, nonce: nonce, aad: aad)
            var blob = nonce
            blob.append(contentsOf: sealed.ciphertext)
            blob.append(contentsOf: sealed.tag)
            record.fields[c].set([UInt8](B64.encode(blob).utf8))
        }

    case .decrypt(let cols, let key, let names):
        for (n, c) in cols.enumerated() {
            guard c < record.count else { continue }
            let text = String(bytes: record.fields[c].value, encoding: .utf8) ?? ""
            guard let blob = B64.decode(text), blob.count >= 28 else {
                throw fault(
                    "record \(record.number), column \(names[n]): not a valid encrypted cell",
                    "第 \(record.number) 筆，欄位 \(names[n])：不是合法的加密儲存格")
            }
            let nonce = Array(blob[0..<12])
            let tag = Array(blob[(blob.count - 16)...])
            let ct = Array(blob[12..<(blob.count - 16)])
            guard let plain = ChaChaPoly.open(ciphertext: ct, tag: tag, key: key,
                                              nonce: nonce, aad: [UInt8](names[n].utf8)) else {
                // The AEAD tag is what SHA-256 could never give: a tampered
                // cell FAILS instead of quietly decrypting to something wrong.
                // AEAD 的認證標籤帶來 SHA-256 給不了的性質：被竄改的儲存格會
                // 失敗，而不是安靜地還原出錯誤的內容。
                throw fault(
                    "record \(record.number), column \(names[n]): authentication failed; the cell was modified after it was encrypted",
                    "第 \(record.number) 筆，欄位 \(names[n])：認證失敗；該儲存格在加密之後被修改過")
            }
            record.fields[c].set(plain)
        }

    case .hash(let cols, let key, _):
        for c in cols where c < record.count {
            // SHA-256 hashes the STORED bytes, not a normalised form. The same
            // "looks identical" string therefore hashes differently in an NFD
            // file and an NFC file -- documented, because otherwise a
            // cross-platform hash comparison shows a false mismatch for a
            // reason nobody can see.
            // SHA-256 雜湊的是已儲存的位元組，不是正規化後的形式。因此同一個
            // 「看起來一樣」的字串在 NFD 與 NFC 檔案上會得到不同的雜湊——這要
            // 寫進說明，否則跨平台比對雜湊會得到假的不相符，而原因完全看不出來。
            // Unkeyed SHA-256 masks a value only as well as its value space is
            // large. `license`, `status`, `category` -- the columns people
            // reach for masking on -- have a handful of possible values, so a
            // dictionary recovers them in seconds. A blind review of this tool
            // recovered 3 of 21 licences from the hashed file alone. With a key
            // the same determinism survives and the dictionary does not.
            // 無金鑰的 SHA-256，其遮蔽效果只取決於值空間有多大。`license`、
            // `status`、`category`——正是人們會拿來遮蔽的那些欄位——可能的值只有
            // 少數幾個，一份字典幾秒鐘就能還原。一次盲測僅憑雜湊後的檔案就還原了
            // 21 個 license 中的 3 個。給了金鑰，確定性仍在，而字典不再管用。
            let digest = key.map { HMACSHA256.authenticate(record.fields[c].value, key: $0) }
                ?? SHA256.hash(record.fields[c].value)
            record.fields[c].set([UInt8](digest.map { String(format: "%02x", $0) }.joined().utf8))
        }
    }
}

func markHeaders(_ headers: inout [Record], transform: CellTransform) {
    switch transform {
    case .encrypt(let cols, _, let fp, let salt, let names):
        for c in cols {
            for i in headers.indices where c < headers[i].count {
                let m = EncMarker(base: names[cols.firstIndex(of: c)!], fingerprint: fp, salt: salt)
                let name = i == 0 ? m.encoded
                    : EncMarker(base: baseName(headerName(headers[i].fields[c])),
                                fingerprint: fp, salt: salt).encoded
                headers[i].fields[c].set([UInt8](name.utf8))
            }
        }
    case .decrypt(let cols, _, _):
        for c in cols {
            for i in headers.indices where c < headers[i].count {
                headers[i].fields[c].set([UInt8](baseName(headerName(headers[i].fields[c])).utf8))
            }
        }
    case .hash(let cols, _, let fp):
        for c in cols {
            for i in headers.indices where c < headers[i].count {
                // The file records WHICH kind was used, and for the keyed form
                // the key's fingerprint too. Without that, a reader cannot tell
                // a dictionary-attackable column from a protected one.
                // 檔案記錄用的是哪一種，keyed 形式還記下金鑰指紋。少了它，讀者
                // 分不出「可被字典攻擊的欄位」與「受保護的欄位」。
                let suffix = fp.map { ":hmac:\($0)" } ?? ":hash"
                let n = baseName(headerName(headers[i].fields[c])) + suffix
                headers[i].fields[c].set([UInt8](n.utf8))
            }
        }
    case .none:
        return
    }
}

func buildTransform(_ o: Options, headers: [Record]) throws -> CellTransform {
    guard let header = headers.first else { return .none }
    let given = [o.encryptCols, o.decryptCols, o.hashCols].compactMap { $0 }
    if given.count > 1 {
        throw fault("-encrypt, -decrypt and -hash are mutually exclusive",
                    "-encrypt、-decrypt 與 -hash 互斥")
    }
    if let spec = o.hashCols {
        let cols = try resolveColumnList(spec, header: header)
        for c in cols where hashMarkerBase(headerName(header.fields[c])) != nil {
            throw fault("column \(baseName(headerName(header.fields[c]))) is already hashed",
                        "欄位 \(baseName(headerName(header.fields[c]))) 已經是雜湊過的")
        }
        Logger.shared.redactedColumns = Set(cols.map { baseName(headerName(header.fields[$0])) })
        // A key turns SHA-256 into HMAC-SHA256. Both are deterministic, so
        // either way equal values still compare equal -- the difference is
        // whether someone without the key can build a dictionary of hashes and
        // read the column back.
        // 給了金鑰就從 SHA-256 變成 HMAC-SHA256。兩者都是確定性的，因此不論哪一種，
        // 相等的值仍然相等——差別在於「沒有金鑰的人能不能建出一份雜湊字典把該欄
        // 讀回來」。
        if o.keyfile != nil || o.assumeYes {
            let material = try KeySource.loadKeyMaterial(path: o.keyfile, assumeYes: o.assumeYes)
            let key = KeySource.derive(material: material.bytes, salt: [UInt8]("csv2-hash".utf8))
            let fp = KeySource.fingerprint(key)
            Logger.shared.info("hashing columns with a key from \(material.path) (fingerprint \(fp))")
            return .hash(columns: cols, key: key, fingerprint: fp)
        }
        return .hash(columns: cols, key: nil, fingerprint: nil)
    }
    if let spec = o.encryptCols {
        let cols = try resolveColumnList(spec, header: header)
        for c in cols where EncMarker.parse(headerName(header.fields[c])) != nil {
            // Refused rather than layered. A second layer would need a second
            // decrypt to undo, and nothing in the file would say how many.
            // 直接拒絕而非疊加一層。疊加需要再解一次才能還原，而檔案裡沒有任何
            // 東西會說明疊了幾層。
            throw fault("column \(baseName(headerName(header.fields[c]))) is already encrypted",
                        "欄位 \(baseName(headerName(header.fields[c]))) 已經加密過")
        }
        let material = try KeySource.loadKeyMaterial(path: o.keyfile, assumeYes: o.assumeYes)
        let salt = cryptoRandomBytes(16)
        let key = KeySource.derive(material: material.bytes, salt: salt)
        let fp = KeySource.fingerprint(key)
        let names = cols.map { baseName(headerName(header.fields[$0])) }
        Logger.shared.redactedColumns = Set(names)
        Logger.shared.info("encrypting columns \(names.joined(separator: ",")) with key \(material.path) (fingerprint \(fp))")
        return .encrypt(columns: cols, key: key, fingerprint: fp, salt: salt, names: names)
    }
    if let spec = o.decryptCols {
        let cols = try resolveColumnList(spec, header: header)
        guard !cols.isEmpty else {
            throw fault("no encrypted columns found", "找不到任何已加密的欄位")
        }
        var markers: [EncMarker] = []
        for c in cols {
            guard let m = EncMarker.parse(headerName(header.fields[c])) else {
                throw fault("column \(baseName(headerName(header.fields[c]))) is not marked as encrypted",
                            "欄位 \(baseName(headerName(header.fields[c]))) 未被標記為已加密")
            }
            markers.append(m)
        }
        let material = try KeySource.loadKeyMaterial(path: o.keyfile, assumeYes: o.assumeYes)
        let key = KeySource.derive(material: material.bytes, salt: markers[0].salt)
        let fp = KeySource.fingerprint(key)
        if fp != markers[0].fingerprint {
            // Without the fingerprint this shows up as a Poly1305 failure,
            // which reads like file corruption and sends the user to look at
            // the file rather than at the key.
            // 沒有指紋時，這件事會表現為 Poly1305 認證失敗——那看起來像檔案損毀，
            // 會讓使用者去查檔案而不是去查金鑰。
            throw fault(
                "this file was encrypted with key fingerprint \(markers[0].fingerprint), the current key is \(fp); the key may have been regenerated by mssh-keygen",
                "本檔案以指紋 \(markers[0].fingerprint) 的金鑰加密，目前的金鑰指紋為 \(fp)；金鑰可能已被 mssh-keygen 重新產生")
        }
        let names = cols.map { baseName(headerName(header.fields[$0])) }
        Logger.shared.redactedColumns = Set(names)
        return .decrypt(columns: cols, key: key, names: names)
    }
    return .none
}

// ---------------------------------------------------------------------
// MARK: - Row literals / 一整列 CSV 文字
// ---------------------------------------------------------------------

/// `-insert` and `-append` take ONE line of CSV-encoded text, parsed by the
/// same parser as the file. Not `-append v1 v2 v3`: that would make the user
/// express "this value contains a comma" through shell quoting rules, and
/// shell quoting is not CSV quoting -- that mismatch is the class of error
/// this tool exists to remove.
/// `-insert` 與 `-append` 的參數是一列 CSV 編碼過的文字，由與檔案相同的解析器
/// 處理。不採 `-append v1 v2 v3`：那等於要求使用者用 shell 的引號規則表達
/// 「值裡面有逗號」，而 shell 與 CSV 的引號規則不同——那正是這支工具要消滅的
/// 那類轉換錯誤。
func parseRowLiteral(_ text: String, format: Format, expected: Int, what: String) throws -> Record {
    var out: Record?
    let parser = RecordParser(format: format) { r in
        if out == nil { out = r }
        return true
    }
    try parser.feed([UInt8](text.utf8))
    try parser.finish()
    guard var r = out else {
        throw fault("\(what): empty row", "\(what)：空的一列")
    }
    if parser.recordsEmitted > 1 {
        throw fault("\(what): the value spans more than one record",
                    "\(what)：這個值跨越了不只一筆紀錄")
    }
    try checkFieldCount(r, expected: expected, what: what)
    r.number = 0
    return r
}

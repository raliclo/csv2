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

struct EmitContext: Sendable {
    var format: Format
    var headers: [Record]
    var withHeader: Bool
    var rownum: Bool
    var zh: Bool
    var physical: Bool
    /// Added to a record's parsed line to give the DOCUMENT's line, and 0 for
    /// every input that is not a Markdown table. Both places a line reaches a
    /// caller -- `--json`'s `line` and `--physical`'s `@L` -- add it, because
    /// a number that is right in one of them and wrong in the other is worse
    /// than one that is wrong in both: the two would disagree and neither would
    /// say which was which. LM.
    /// 加到紀錄「解析出來的行號」上，就得到**文件**的行號；對每一個不是 Markdown 表的輸入是 0。
    /// 行號抵達呼叫端的**兩個**出口——`--json` 的 `line` 與 `--physical` 的 `@L`——都要加它，因為
    /// 「一個對、一個錯」比「兩個都錯」更糟：那樣兩者會互相矛盾，而沒有任何一方說得出哪個才對。LM。
    var mdLineOffset: Int = 0
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
                                                 preserveRaw: ctx.preserveRaw))
        }
    }

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        var rec = r
        if ctx.rownum {
            rec.fields.insert(Field(value: [UInt8]("\(r.number)".utf8)), at: 0)
        }
        // preserveRaw is per FIELD -- a field with no raw bytes falls back to
        // its value -- so adding a rownum column does not stop the other
        // columns being written as they arrived. Turning it off wholesale would
        // make `-r -rownum` quote differently from `-r` on the same file.
        // preserveRaw 是「逐欄位」的——沒有原樣位元組的欄位會退回它的值——因此多一個 rownum
        // 欄，不會讓其他欄位失去「照原樣寫出」。整體關掉它，`-r -rownum` 與 `-r` 對同一個檔案
        // 就會給出不同的引號。
        sink.write(FieldEncoder.encodeRecord(rec, format: ctx.format,
                                             preserveRaw: ctx.preserveRaw))
    }

    /// grep prints `--` between non-adjacent blocks and so does csv2. It is
    /// documented as a separator rather than data, because a downstream
    /// script that treats it as a record gets one bogus row per block.
    /// grep 在不相鄰的區塊之間印 `--`，此處照做。它在說明中被標示為分隔線而
    /// 非資料，否則下游腳本每個區塊會多讀到一筆假的紀錄。
    func gap(_ ctx: EmitContext) throws { sink.write("--\n") }

    func end(_ ctx: EmitContext, records: Int, matched: Int) throws {}
}

// reportEscape and lineEscape are defined in Support.swift; this is why they
// differ.
// 以下說明定義在 Support.swift 的 reportEscape 與 lineEscape 為何不同。
//
// reportEscape: the locating report is TAB-separated, one line per matching
// cell, and a value is arbitrary CSV content, so a raw TAB or newline in a
// cell breaks the format: more lines than hits, and `cut -f1` returning prose
// where an address belongs, at rc=0. It uses the backslash convention `.csv2`
// already uses, plus `\t` because TAB is the report's own delimiter, so a
// reader who knows the file format can already read the report.
// reportEscape：定位報告以 TAB 分隔、每個命中的儲存格一行，而值是任意的 CSV 內容，因此儲存格
// 裡原樣的 TAB 或換行會破壞格式：行數比命中多，`cut -f1` 在該是位址的地方回傳一段散文，rc=0。
// 它沿用 `.csv2` 既有的反斜線慣例，另加 `\t`——因為 TAB 是報告自己的分隔符——讓看得懂檔案格式
// 的人不必再學一套就能讀報告。
//
// lineEscape: the whole-message escape, deliberately narrower. It escapes
// what would end a line (newline, CR), TAB, and every other C0 control
// character and DEL as `\xNN`, so no entry can be forged by opening a second
// line and no future message has to remember to. It does NOT touch the
// backslash: one choke point cannot tell an author's prose from an
// interpolated value, and escaping prose breaks the messages that teach
// escaping (`\q` would print as `\\q`, and a reader following it writes the
// wrong value at rc=0). The value sites -- `redact`, the logged invocation,
// and a message quoting input back -- escape fully. Control characters ARE
// escaped because csv2's own prose contains none: every one in a message came
// from data, and raw they are live terminal control on stderr
// (`<ESC>[2K` erases the line it is printed on).
// lineEscape：整則訊息的跳脫，刻意比 reportEscape 窄。它跳脫會結束一行的東西（換行、歸位字元）、
// TAB，以及其餘每一個 C0 控制字元與 DEL（寫成 `\xNN`），讓任何一筆都無法靠開出第二行來偽造，
// 日後的訊息也不必記得要做。它**不**動反斜線：單一關卡分不出作者寫的散文與插進去的值，而跳脫
// 散文會弄壞那些「教你怎麼跳脫」的訊息（`\q` 會印成 `\\q`，照著寫的人會在 rc=0 下寫進錯的值）。
// 「值」的那些地方——`redact`、記入 log 的呼叫、把輸入引述回來的訊息——做完整跳脫。控制字元
// **要**跳脫，因為 csv2 自己的散文裡一個都沒有：訊息裡的每一個都來自資料，原樣送上 stderr 就是
// 活的終端機控制序列（`<ESC>[2K` 會擦掉它被印出的那一行）。

/// `-get r:c` prints ONE cell's value and nothing else -- no quoting, no
/// delimiter, no header, no address. The value as it was stored, decoded.
///
/// Not CSV, deliberately. A one-cell CSV row would need quoting whenever the
/// value contained a comma, and the caller would then have to decode it with
/// --json plus a selection plus an external parser. What a caller wants from
/// an address is the value.
///
/// A trailing newline, so `$(csv2 -get ...)` behaves like every other command
/// substitution -- the shell strips it. A value containing newlines comes back
/// containing them; nothing is escaped, because escaping would be a format, and
/// this is deliberately not one. If you need a value whose own newlines matter,
/// --json is the shape that can carry it unambiguously.
///
/// `-get r:c` 只印出「一格」的值，別的什麼都不印——沒有引號、沒有分隔符、沒有標頭、
/// 沒有位址。就是儲存時的值，解碼後。
/// 刻意不是 CSV。只有一格的 CSV 列，在值含逗號時仍需加引號，於是呼叫端還得用 --json 加選取
/// 加外部解析器再解碼一次。呼叫端要的是「值」。
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
        // A NUMBER needs no header, so a file with no header row (a
        // suffix-less file, say) can still be addressed as `1:1`. Only a NAME
        // needs one. Phase 8b.
        // 「數字」不需要標頭，因此沒有標頭列的檔案（例如沒有副檔名的檔案）仍然可以用 `1:1`
        // 定址。只有「名稱」需要標頭。第 8b 階段。
        let c: Int
        if let header = ctx.headers.first {
            c = try resolveColumn(column, header: header)
        } else if let n = Int(column), n >= 1 {
            c = n - 1
        } else {
            throw fault("-get \(column): this file has no header row, so a column can only be addressed by NUMBER here",
                        "-get \(column)：這個檔案沒有標頭列，因此在這裡只能以「編號」定址欄位")
        }
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
            if ctx.physical { addr += "@L\(r.line + ctx.mdLineOffset)" }
            // The A1 row is the record number plus the header rows above it,
            // which is the row a spreadsheet puts the record on.
            //
            // Not the PHYSICAL line. The two are equal with one record per
            // line, but a record spanning lines still occupies ONE spreadsheet
            // row, because the quoted newline stays inside the cell -- and that
            // case is the only one where `--a1` offers anything `--physical`
            // does not. Not the record number alone either: A1 has no row 0,
            // and the header rows sit above the data.
            //
            // A1 的列號取「紀錄號 + 其上方的標頭列數」，那才是試算表放這筆紀錄的那一列。
            //
            // 不是「物理行號」。一筆一行時兩者相等，但跨行的紀錄在試算表裡仍然只佔「一列」，因為
            // 引號內的換行留在儲存格內——而那正是 `--a1` 唯一比 `--physical` 多給出東西的情況。
            // 也不是單用紀錄號：A1 記法沒有第 0 列，而標頭列在資料上方。
            if ctx.a1 {
                let a1Row = r.headerRow.map { $0 + 1 } ?? (r.number + ctx.headers.count)
                addr += " [\(a1Column(idx))\(a1Row)]"
            }
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
    /// Set from the context on every emit, so `carry` can escape the way the
    /// caller asked without taking the context as a parameter through a
    /// throwing helper.
    /// 每次 emit 都由 context 設定，讓 `carry` 能以呼叫端要求的方式跳脫，而不必把 context
    /// 一路傳進一個會擲出錯誤的輔助函式。
    private var jsonASCIIFlag = false
    init(sink: ByteSink, reportMode: Bool) { self.sink = sink; self.reportMode = reportMode }

    func begin(_ ctx: EmitContext) throws {
        // A record object keys `fields` by column name, and a JSON object
        // cannot hold two values under one key. Emitting both anyway produces a
        // duplicate key: syntactically permitted by RFC 8259, which leaves the
        // interpretation unspecified, and collapsed by every parser anybody
        // actually uses -- Python's json and JavaScript's JSON.parse both keep
        // the last and discard the first. The reader's parser destroys one
        // value before the reader ever sees it, unrecoverably.
        //
        // Refused, the same way an ambiguous address is refused, and pointing
        // at the shapes that can carry it. The report shape is unaffected: it
        // emits record, field, header_en and value per hit, so two columns with
        // one name are two lines, not one lost key.
        //
        // 一筆紀錄的物件以「欄名」作為 `fields` 的鍵，而一個 JSON 物件無法在同一個鍵下
        // 放兩個值。照樣輸出的結果是重複鍵：RFC 8259 在語法上允許（它把「如何解讀」列為
        // 未定義），而實際上每一個有人在用的解析器都會把它收合——Python 的 json 與
        // JavaScript 的 JSON.parse 都留下最後一個、丟掉第一個。讀者的解析器會在讀者看到之前
        // 就毀掉其中一個值，而且無法取回。
        // 因此拒絕，方式與拒絕一個有歧義的位址相同，並指出承載得了它的那些形狀。報告形狀
        // 不受影響：它每個命中輸出 record、field、header_en 與 value，因此兩個同名欄位是
        // 兩行，而不是一個被丟掉的鍵。
        if !reportMode, let header = ctx.headers.first {
            var seen = Set<String>()
            for f in header.fields {
                let n = baseName(headerName(f))
                if !seen.insert(n).inserted {
                    throw fault(
                        "--json keys each record by column name, and \"\(n)\" names more than one column, so one value would be lost when the line is parsed; read it without --json, or use -contains --json which reports each hit separately",
                        "--json 以欄名作為每一筆的鍵，而「\(n)」指向不只一個欄位，於是該行被解析時會遺失一個值；請不加 --json 讀取，或改用 -contains --json——它會分別回報每一個命中")
                }
            }
        }
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
        // The second header row, on the one format that has one.
        //
        // A record object keys `fields` by the FIRST header row, so without
        // this the second row of a `.csv2` has no way out through --json.
        // `--json` carries both names: a consumer that wants one can pick, and
        // one that wants the other cannot invent it. Round 77, JN.
        //
        // It goes on the meta line rather than into every record: the names do
        // not vary by record, and repeating them 450,000 times to carry three
        // strings would be the kind of output this tool refuses elsewhere. An
        // ARRAY, not an object, because the second row is positional -- it can
        // legitimately repeat a name, which is exactly what an object cannot
        // hold, and refusing a file for that would be a new refusal invented to
        // serve a serialisation choice.
        //
        // `.csv` gets no `header_zh`: it has one header row.
        //
        // 第二列標頭，寫在唯一有第二列的那個格式上。
        // 一筆紀錄的物件是以「第一列標頭」為鍵的，因此少了這一項，`.csv2` 的第二列就沒有任何
        // 出口經由 --json 出來。`--json` 帶著兩個名字：只想要其中一個的消費端可以自己挑，而想要
        // 另一個的沒辦法自己發明。第 77 回合，JN。
        // 它放在 meta 行而不是每一筆裡：那些名字不隨紀錄變化，為了三個字串重複 45 萬次，正是
        // 這個工具在別處會拒絕的那種輸出。用「陣列」而不是物件，因為第二列是按位置的——它可以
        // 合法地重複同一個名字，而那恰好是物件裝不下的；為了一個序列化的選擇去發明一條新的拒絕，
        // 不成立。
        // `.csv` 沒有 `header_zh`：它只有一列標頭。
        //
        // The ENGLISH header, positionally, for every format. The keys of
        // `fields` carry the names but not the ORDER: a JSON object's keys
        // have no defined order, so a consumer that decodes a record into a
        // dictionary loses it (and draws columns alphabetically). With
        // `header_zh` positional and this one missing, a consumer could get
        // the Chinese order and not the English. LI.
        //
        // **英文標頭，依位置**，每種格式都有。`fields` 的鍵帶著名字，卻不帶**順序**：JSON 物件的
        // 鍵沒有定義順序，因此把紀錄解成字典的消費者會失去它（於是依字母序畫出欄位）。若
        // `header_zh` 是位置性的而這一項不在，消費者就拿得到中文順序、拿不到英文順序。LI。
        var en = ""
        if let first = ctx.headers.first {
            let names = first.fields.map {
                JSONOut.string($0.value, asciiOnly: ctx.jsonASCII)
            }
            en = ",\"header\":[" + names.joined(separator: ",") + "]"
        }
        var zh = ""
        if ctx.headers.count > 1 {
            let names = ctx.headers[1].fields.map {
                JSONOut.string($0.value, asciiOnly: ctx.jsonASCII)
            }
            zh = ",\"header_zh\":[" + names.joined(separator: ",") + "]"
        }
        sink.write("{\"meta\":{\"format\":\"\(ctx.format.rawValue)\",\"headers\":\(ctx.headers.count),\"fields\":\(fields)\(en)\(zh)\(prot)}}\n")
    }

    /// Refused rather than substituted. JSON is text, so a byte sequence that
    /// is not valid UTF-8 cannot be carried: Swift's decoder puts U+FFFD in
    /// its place and the line stays valid JSON, which is data loss that looks
    /// exactly like success. `-get` hands back the bytes and the locating
    /// report says `<non-UTF-8: 63 61 66 e9>`.
    /// 拒絕，而不是替換。JSON 是文字，因此一段不是合法 UTF-8 的位元組載不進去：Swift 的
    /// 解碼器會放一個 U+FFFD 進去，而那一行仍然是合法的 JSON——那是一種「看起來與成功完全
    /// 相同」的資料遺失。`-get` 交還的是位元組，定位報告會寫 `<non-UTF-8: 63 61 66 e9>`。
    private func carry(_ bytes: [UInt8], record: Int, field: Int) throws -> String {
        guard JSONOut.canCarry(bytes) else {
            throw fault(
                "record \(record), field \(field) is not valid UTF-8, and JSON is text: --json would put U+FFFD where those bytes are and the line would still look right. -get returns the bytes, and the locating report names them in hex",
                "第 \(record) 筆第 \(field) 欄不是合法的 UTF-8，而 JSON 是文字：--json 會在那些位元組的位置放上 U+FFFD，而那一行看起來仍然沒問題。要位元組請用 -get，定位報告則會以十六進位指出它們")
        }
        return JSONOut.string(bytes, asciiOnly: jsonASCIIFlag)
    }

    func emit(_ r: Record, matches: [Int], ctx: EmitContext) throws {
        jsonASCIIFlag = ctx.jsonASCII
        if reportMode {
            for idx in matches {
                var parts = ["\"record\":\(r.number)", "\"field\":\(idx + 1)"]
                // Which header row, when the hit IS in a header row: the same
                // `0a` / `0b` the locating report uses, because `"record":0`
                // alone cannot tell the English title row from the Chinese one.
                // 命中「就在標頭列裡」時，是哪一列：與定位報告相同的 `0a` / `0b`，因為光是
                // `"record":0` 分不出英文標題列與中文標題列。
                if let hr = r.headerRow {
                    let label = (ctx.headers.count > 1) ? (hr == 0 ? "0a" : "0b") : "0"
                    parts.append("\"header_row\":\"\(label)\"")
                }
                if let h = ctx.headers.first, idx < h.count {
                    parts.append("\"header_en\":\(JSONOut.string(h.fields[idx].value, asciiOnly: ctx.jsonASCII))")
                }
                if ctx.headers.count > 1, idx < ctx.headers[1].count {
                    parts.append("\"header_zh\":\(JSONOut.string(ctx.headers[1].fields[idx].value, asciiOnly: ctx.jsonASCII))")
                }
                parts.append("\"value\":\(try carry(r.fields[idx].value, record: r.number, field: idx + 1))")
                parts.append("\"line\":\(r.line + ctx.mdLineOffset)")
                sink.write("{" + parts.joined(separator: ",") + "}\n")
            }
            return
        }
        var parts = ["\"record\":\(r.number)", "\"line\":\(r.line + ctx.mdLineOffset)"]
        // Only when context is on. Without it every emitted record matched, so
        // the key would be constant true on every line -- noise that a consumer
        // has to read and can never learn anything from.
        // 只在有上下文時加。沒有上下文時，送出的每一筆都是命中，這個鍵會在每一行都是
        // 固定的 true——那是消費端必須讀、卻永遠學不到東西的雜訊。
        if ctx.contextActive {
            parts.append("\"match\":\(matches.isEmpty ? "false" : "true")")
        }
        var cells: [String] = []
        for (i, f) in r.fields.enumerated() {
            let key = ctx.headers.first.map { i < $0.count ? baseName(headerName($0.fields[i])) : "\(i + 1)" } ?? "\(i + 1)"
            cells.append("\(JSONOut.string([UInt8](key.utf8), asciiOnly: ctx.jsonASCII)):\(try carry(f.value, record: r.number, field: i + 1))")
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
    /// `preserve` needs the lines the input table arrived on. Absent when the
    /// input was not Markdown, and absent is exactly when `preserve` renders
    /// as `compact` -- there is no layout to keep, which is what "preserve"
    /// means with nothing to preserve.
    /// `preserve` 需要輸入表送達時的那些原始行。輸入不是 Markdown 時它不存在，而「不存在」正是
    /// `preserve` 以 `compact` 算繪的時候——沒有排版可以保留，那就是「保留」在無物可保留時的意思。
    private var layout: MarkdownLayout?

    init(sink: ByteSink, pretty: Bool = false, layout: MarkdownLayout? = nil) {
        self.sink = sink
        self.pretty = pretty
        self.layout = layout
    }

    private func prettyLimit() -> Int {
        if let v = ProcessInfo.processInfo.environment["CSV2_PRETTY_MAX_BYTES"], let n = Int(v) {
            return n
        }
        return 16 * 1024 * 1024
    }

    func begin(_ ctx: EmitContext) throws {
        var names: [String] = []
        // The generated column follows the same rule as every other one: `--zh`
        // gives the Chinese name, `--en` the English, neither joins both -- and
        // a ONE-header `.csv` never joins, since its other cells are plain.
        // 這個「生成的」欄位遵守與其他每一欄相同的規則：`--zh` 給中文、`--en` 給英文，都不給
        // 才合併——而「只有一列標頭」的 `.csv` 永遠不合併，因為它其他的格都是純文字。
        if ctx.rownum {
            names.append(ctx.zh ? "列號"
                       : ctx.enOnly || (ctx.headers.count < 2) ? "rownum"
                       : "rownum<br>列號")
        }
        // A file with no header row has no table shape. Keyed on the header
        // itself, not on `-t`: with `-t` given and no header, the output would
        // be `||` and `||`, a document csv2 refuses to read, at rc=0. Round 78,
        // JX.
        // 一個沒有標頭列的檔案沒有「表」的形狀。這裡判斷的是標頭本身，而不是 `-t`：給了 `-t`
        // 卻沒有標頭時，輸出會是 `||` 與 `||`——一份 csv2 自己拒讀的文件，而且 rc=0。第 78 回合，JX。
        guard let hdr = ctx.headers.first, hdr.count > 0 else {
            throw fault(
                "-md needs a header row to name the columns, and this file has none. A file with no suffix is one column of lines; give it a destination with a .csv or .csv2 suffix first, or pass --headers 1 to read it as CSV",
                "-md 需要一列標頭來為欄位命名，而這個檔案沒有。沒有副檔名的檔案是一欄的行清單；請先給它一個 .csv 或 .csv2 副檔名的目的地，或以 --headers 1 把它當成 CSV 讀")
        }
        for i in 0..<hdr.count {
            // A Markdown table has ONE header row and .csv2 has two. Merging
            // them into one cell with <br> matches how this project's docs
            // already present both languages side by side.
            // Markdown 表格只有一列標頭而 .csv2 有兩列。以 <br> 併入同一個
            // 儲存格，與本專案文件雙語並列的既有習慣一致。
            let en = MarkdownOut.cell(ctx.headers[0].fields[i].value)
            if ctx.headers.count > 1 && i < ctx.headers[1].count {
                let zh = MarkdownOut.cell(ctx.headers[1].fields[i].value)
                // --zh Chinese only, --en English only, neither merges both.
                // --zh 只取中文、--en 只取英文，都不給則兩者合併。
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
        // The header and the separator come from the source when they are
        // unchanged. The separator especially: --pretty widens `|---|` to
        // `|------|`, so even a run that edits nothing rewrites it, and that
        // line carries no data at all -- it is pure formatting, and rewriting
        // it is pure diff noise.
        // 標頭與分隔列在沒有改變時取自來源。分隔列尤其如此：--pretty 會把 `|---|` 加寬成
        // `|------|`，因此即使一次什麼都沒編輯的執行也會重寫它，而那一行根本不承載任何資料
        // ——它純粹是格式，重寫它純粹是 diff 雜訊。
        if let lay = layout, let orig = lay.header[names] {
            sink.write(orig + "\n")
            sink.write((lay.separator.isEmpty
                        ? "|" + names.map { _ in "---" }.joined(separator: "|") + "|"
                        : lay.separator) + "\n")
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
                    "-md --pretty has to hold the whole table to align it, and this one is over \(prettyLimit()) bytes; drop --pretty (a Markdown renderer produces the same table from it -- a terminal does not, it will be ragged) or raise CSV2_PRETTY_MAX_BYTES",
                    "-md --pretty 必須持有整張表才能對齊，而這一張超過 \(prettyLimit()) 位元組；請拿掉 --pretty（Markdown 算出來是同一張表——終端機裡則不是，它會參差不齊），或調高 CSV2_PRETTY_MAX_BYTES")
            }
            buffered.append(cells)
            return
        }
        // A row whose values are unchanged goes back as the line it came in
        // on. A row that WAS edited is rendered compact -- its line no longer
        // describes it, and padding it to the old width would be inventing
        // formatting for a value that was never there.
        // 值沒有改變的列，會以它送進來時的那一行寫回去。被編輯過的列則以 compact 算繪——它原本
        // 那一行已經描述不了它了，而把它補齊到舊的寬度，等於替一個從來不存在的值發明格式。
        if var lay = layout, var originals = lay.rows[cells], !originals.isEmpty {
            let orig = originals.removeFirst()
            lay.rows[cells] = originals
            layout = lay
            sink.write(orig + "\n")
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
        // Report the widths under -debug. Display width is the whole point of
        // --pretty, and without this a reader checking the alignment has to
        // reimplement the measurement -- and when the reimplementation is
        // wrong, the tool is what looks wrong. Round 40.
        //
        // 在 -debug 下把欄寬報出來。顯示寬度是 --pretty 的全部意義；少了這一行，想檢查對齊的
        // 讀者只能自己重新實作量測——而當出錯的是那個重新實作時，看起來錯的會是這支工具。第 40 回合。
        Logger.shared.debug("pretty: column display widths \(widths) (columns, not bytes or characters)")

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
                //
                // What it cannot give is WHICH thing was wrong: a wrong key, an
                // altered cell, and an altered header (a stored fingerprint
                // rewritten to match a wrong key defeats the O(1) pre-check)
                // fail identically, so all three are named. The record number
                // is where the failure was DETECTED, said plainly, because
                // elsewhere `record N` promises to be where the fault is.
                //
                // AEAD 的認證標籤帶來 SHA-256 給不了的性質：被竄改的儲存格會失敗，而不是
                // 安靜地還原出錯誤的內容。
                //
                // 它給不了的是「錯的是哪一個」：金鑰不對、儲存格被改、標頭被改（把存起來的指紋
                // 改寫成錯金鑰導出的值，就能繞過 O(1) 預檢）三者失敗的樣子一模一樣，因此三個都寫出來。
                // 紀錄編號是「偵測到失敗的位置」，這一點要明講，因為在別處 `record N` 承諾的是出問題的地方。
                throw fault(
                    "authentication failed at record \(record.number), column \(names[n]) -- that is where it was DETECTED, not necessarily where the fault is. Any of three produce this and the tag cannot tell them apart: the key is not the one this column was encrypted with, the cell was altered after encryption, or the column's header was altered. Check the header first if you have a key you believe in",
                    "認證失敗，位置在第 \(record.number) 筆、欄位 \(names[n])——那是「偵測到」的地方，未必是出問題的地方。有三種情況會產生一模一樣的結果，而認證標籤分辨不出來：金鑰不是當初加密這一欄所用的那一把、儲存格在加密後被改動、或該欄的標頭被改動。若你確信手上的金鑰是對的，請先檢查標頭")
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
            // dictionary recovers them in seconds. With a key the same
            // determinism survives and the dictionary does not.
            // 無金鑰的 SHA-256，其遮蔽效果只取決於值空間有多大。`license`、
            // `status`、`category`——正是人們會拿來遮蔽的那些欄位——可能的值只有
            // 少數幾個，一份字典幾秒鐘就能還原。給了金鑰，確定性仍在，而字典不再管用。
            let digest = key.map { HMACSHA256.authenticate(record.fields[c].value, key: $0) }
                ?? SHA256.hash(record.fields[c].value)
            record.fields[c].set([UInt8](digest.map { String(format: "%02x", $0) }.joined().utf8))
        }
    }
}

/// Any column the FILE says is protected joins the redaction set, whatever this
/// run is doing.
///
/// Taking the set only from the columns being transformed right now is not
/// enough: `-update 1:secret NEW` on a file whose header reads
/// `secret:hmac:d6c8da42` would write NEW to the log in the clear.
///
/// The header is the file's own statement about which columns hold secrets. It
/// outlives any single invocation, and it is the only thing that can be right
/// about a file the caller did not create.
///
/// 任何「檔案自己說它受保護」的欄位都會進入遮蔽集合，不論這次執行在做什麼。
/// 只依「本次要轉換的欄位」填入這個集合是不夠的：對標頭寫著 `secret:hmac:d6c8da42` 的檔案
/// 執行 `-update 1:secret NEW`，會把 NEW 明文寫進 log。
/// 標頭是檔案自己對「哪些欄位存放秘密」的陳述。它比任何單次呼叫都活得久，而且它是唯一
/// 可能對「一個不是呼叫者建立的檔案」說得準的東西。
/// One predicate for "the file's own header says this column holds a
/// transformed value". Two things depend on it and they must not drift: what
/// the log redacts, and what an edit is refused on. If they differ, a value
/// the log declines to print can be written into a column it destroys.
/// 「檔案自己的標頭說這一欄存放的是轉換過的值」——只有一個謂詞。有兩件事依賴它，而它們
/// 不能各走各的：log 要遮蔽什麼，以及編輯要在什麼上面被拒絕。兩者若不同，一個 log 拒絕
/// 印出來的值，就可能被寫進一個它會摧毀的欄位。
func headerDeclaresProtected(_ name: String) -> Bool {
    EncMarker.parse(name) != nil
        || name.hasSuffix(":hash")
        || name.range(of: ":hmac:", options: .backwards) != nil
}

/// The columns this file declares transformed, as (index, visible name), plus
/// whether any of them is encrypted rather than hashed. The two consequences
/// are different and the messages below have to say the one that applies.
/// 本檔案宣告為已轉換的欄位，以 (索引, 可見欄名) 表示，另附「其中是否有加密而非雜湊的」。
/// 兩者的後果不同，而下面的訊息必須說出適用的那一個。
func protectedColumns(_ header: Record) -> (columns: [(Int, String)], anyEncrypted: Bool) {
    var cols: [(Int, String)] = []
    var enc = false
    for (i, f) in header.fields.enumerated() {
        let n = headerName(f)
        guard headerDeclaresProtected(n) else { continue }
        if EncMarker.parse(n) != nil { enc = true }
        cols.append((i, baseName(n)))
    }
    return (cols, enc)
}

/// Writing a raw value into a cell of a column the file declares transformed.
/// Shared so `-update` and `-delete -cell` cannot say different things about
/// the same situation.
/// 把原始值寫進「檔案宣告為已轉換」的欄位中的一格。共用，好讓 `-update` 與
/// `-delete -cell` 不會對同一個情況說出不同的話。
func rawCellWriteRefusal(targets: [String], anyEncrypted: Bool) -> CSV2Error {
    let why = anyEncrypted
        ? "a raw value written there cannot be decrypted, and it takes the whole column with it: -decrypt stops at that cell, so records this edit never touched can no longer be read either"
        : "a raw value written there would sit in a hashed column looking like a hash, and nothing can detect it -- a hash cannot be checked against the value it replaced"
    let whyZh = anyEncrypted
        ? "寫進去的原始值解不開，而且會連整欄一起帶走：-decrypt 會停在那一格，於是這次編輯從未碰過的紀錄也一起讀不回來"
        : "寫進去的原始值會待在一個雜湊欄位裡、看起來就像一個雜湊，而沒有任何東西能發現它——雜湊無法拿來與它所取代的值比對"
    let fix = anyEncrypted
        ? "Decrypt to a file first, edit that, then encrypt it again."
        : "Hashing is one way, so this file cannot be edited back: change the source the hash was made from and hash it again."
    let fixZh = anyEncrypted
        ? "請先解密成一個檔案、改那一份，再重新加密。"
        : "雜湊是單向的，因此這個檔案改不回去：請修改當初拿來雜湊的來源，再雜湊一次。"
    return fault(
        "\(targets.sorted().joined(separator: ", ")) targets a column this file declares transformed; \(why). \(fix)",
        "\(targets.sorted().joined(separator: "、")) 指向一個「本檔案宣告為已轉換」的欄位；\(whyZh)。\(fixZh)")
}

/// Writing a whole raw ROW into such a file. Separate from the cell case
/// because the caller did not aim at the protected column -- the row simply
/// has a field for it, and there is no value they could have supplied that
/// would be right, since the transform needs the key the header only
/// fingerprints. Defect W.
/// 把一整列原始資料寫進這樣的檔案。與「單格」分開，因為呼叫者並不是瞄準那個受保護欄位——
/// 那一列只是剛好有它的一欄，而且**沒有任何他們給得出的值會是對的**，因為那個轉換需要金鑰，
/// 而標頭裡只有金鑰的指紋。缺陷 W。
func rawRowWriteRefusal(verbs: [String], columns: [String], anyEncrypted: Bool) -> CSV2Error {
    let what = anyEncrypted ? "encrypted" : "hashed"
    let whatZh = anyEncrypted ? "加密" : "雜湊"
    let tail = anyEncrypted
        ? "and the whole column stops being decryptable, not just the new record"
        : "and it would sit there looking like a hash, with nothing able to detect it"
    let tailZh = anyEncrypted
        ? "而且失去解密能力的是整欄，不只是新加的那一筆"
        : "而且它會待在那裡、看起來就像一個雜湊，沒有任何東西能發現"
    return fault(
        "\(verbs.sorted().joined(separator: ", ")) writes a whole record into a file whose column \(columns.joined(separator: ", ")) is \(what); the new record's value for it would be stored raw, \(tail). Build the record in an untransformed copy and transform that.",
        "\(verbs.sorted().joined(separator: "、")) 要把一整筆寫進一個「\(columns.joined(separator: "、")) 欄已\(whatZh)」的檔案；新紀錄在該欄的值會以原始形式存入，\(tailZh)。請在未轉換的複本上建立該筆，再對那一份做轉換。")
}

func redactColumnsDeclaredByHeader(_ header: Record) {
    for f in header.fields where headerDeclaresProtected(headerName(f)) {
        Logger.shared.redactedColumns.insert(baseName(headerName(f)))
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
        // Each guard checks BOTH markers, not only its own. `-hash` on an
        // `:enc:` column is the worst thing this tool could do: it hashes the
        // CIPHERTEXT one way and overwrites the `:enc:` marker, salt and all,
        // at rc=0, and the correct key afterwards gets `no encrypted columns
        // found`. The README promises that re-masking an already-marked column
        // is refused rather than layered, in both directions.
        //
        // 每個守衛都檢查**兩種**標記，不只自己那一種。對 `:enc:` 欄位下 `-hash` 是這個工具做得出來
        // 最糟的一件事：它把「密文」單向雜湊掉，並連同 salt 覆寫 `:enc:` 標記，rc=0，事後拿正確的
        // 金鑰去解只得到 `no encrypted columns found`。README 承諾對已標記的欄位再次遮蔽會被拒絕
        // 而不是疊加，兩個方向都是。
        for c in cols {
            let name = headerName(header.fields[c])
            if EncMarker.parse(name) != nil {
                throw fault(
                    "column \(baseName(name)) is encrypted; -hash would hash the CIPHERTEXT one way and overwrite the :enc: marker together with its salt, and no key would recover the plaintext afterwards. Decrypt it first if you meant to mask it instead",
                    "欄位 \(baseName(name)) 已加密；-hash 會把「密文」單向雜湊掉，並連同 salt 一起覆寫 :enc: 標記，之後沒有任何金鑰救得回明文。若你的本意是改為遮蔽，請先解密")
            }
            if hashMarkerBase(name) != nil {
                throw fault("column \(baseName(name)) is already hashed",
                            "欄位 \(baseName(name)) 已經是雜湊過的")
            }
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
            let material = try KeySource.loadKeyMaterial(path: o.keyfile, assumeYes: o.assumeYes,
                                                         forCreating: true)
            let key = KeySource.derive(material: material.bytes, salt: [UInt8]("csv2-hash".utf8))
            let fp = KeySource.fingerprint(key)
            Logger.shared.info("hashing columns \(cols.map { baseName(headerName(header.fields[$0])) }.joined(separator: ",")) with a key from \(material.path) (fingerprint \(fp))")
            return .hash(columns: cols, key: key, fingerprint: fp)
        }
        // Logged like -encrypt and the keyed hash: the unkeyed hash is
        // irreversible AND dictionary-attackable, so the audit trail must name
        // the columns and say no key was used.
        // 與 -encrypt 及有金鑰的雜湊一樣要記下來：無金鑰的雜湊不可逆、又可用字典攻破，
        // 因此稽核軌跡必須列出欄位，並說明沒有用金鑰。
        Logger.shared.info("hashing columns \(cols.map { baseName(headerName(header.fields[$0])) }.joined(separator: ",")) with NO key (unsalted SHA-256)")
        return .hash(columns: cols, key: nil, fingerprint: nil)
    }
    if let spec = o.encryptCols {
        let cols = try resolveColumnList(spec, header: header)
        for c in cols {
            let name = headerName(header.fields[c])
            // Refused rather than layered. A second layer would need a second
            // decrypt to undo, and nothing in the file would say how many.
            // 直接拒絕而非疊加一層。疊加需要再解一次才能還原，而檔案裡沒有任何
            // 東西會說明疊了幾層。
            if EncMarker.parse(name) != nil {
                throw fault("column \(baseName(name)) is already encrypted",
                            "欄位 \(baseName(name)) 已經加密過")
            }
            // The other direction destroys nothing and produces a file that
            // lies about itself: the header becomes `:enc:`, so `-decrypt`
            // hands back hex digests under a clean column name with nothing
            // marking them as digests. A hash is not a plaintext and a file
            // must not claim it is.
            // 反方向不會銷毀任何東西，但會產生一個「對自己說謊」的檔案：標頭變成 `:enc:`，
            // 於是 `-decrypt` 會交還一堆十六進位摘要，掛在乾淨的欄名底下，而沒有任何東西
            // 標記它們是摘要。雜湊不是明文，而一個檔案不該宣稱它是。
            if hashMarkerBase(name) != nil {
                throw fault(
                    "column \(baseName(name)) is hashed; encrypting it would mark the file as holding ciphertext there, and -decrypt would then hand back hex digests under a clean column name with nothing saying they are digests",
                    "欄位 \(baseName(name)) 是雜湊過的；對它加密會讓檔案標記成「那裡放的是密文」，而 -decrypt 之後會交還一堆十六進位摘要、掛在乾淨的欄名底下，沒有任何東西說明它們是摘要")
            }
        }
        let material = try KeySource.loadKeyMaterial(path: o.keyfile, assumeYes: o.assumeYes,
                                                     forCreating: true)
        let salt = cryptoRandomBytes(16)
        let key = KeySource.derive(material: material.bytes, salt: salt)
        let fp = KeySource.fingerprint(key)
        let names = cols.map { baseName(headerName(header.fields[$0])) }
        Logger.shared.redactedColumns = Set(names)
        Logger.shared.info("encrypting columns \(names.joined(separator: ",")) with key \(material.path) (fingerprint \(fp))")
        return .encrypt(columns: cols, key: key, fingerprint: fp, salt: salt, names: names)
    }
    if let spec = o.decryptCols {
        let cols = try resolveColumnList(spec, header: header, allMeansMarked: true)
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
                "this file was encrypted with key fingerprint \(markers[0].fingerprint), and the key you gave derives \(fp) against this file's stored salt; either the key differs, or this header's salt has been altered. A regenerated key -- mssh-keygen -- is the usual cause",
                "本檔案以指紋 \(markers[0].fingerprint) 的金鑰加密，而你給的金鑰對這個檔案存下的 salt 推導出 \(fp)；可能是金鑰不同，也可能是這個標頭的 salt 被改動過。最常見的原因是金鑰被 mssh-keygen 重新產生")
        }
        let names = cols.map { baseName(headerName(header.fields[$0])) }
        Logger.shared.redactedColumns = Set(names)
        // Logged like -encrypt and -hash: decrypting takes data out, and "who
        // opened this column, with which key" is the line somebody comes
        // looking for. The README's log table promises the fingerprint for
        // -decrypt too. Round 40, defect UU.
        // 與 -encrypt、-hash 一樣要記錄：解密是把資料拿出來，而「誰用哪一把金鑰把這一欄打開了」
        // 正是日後有人會來找的那一行。README 的 log 表也為 -decrypt 承諾了指紋。第 40 回合，缺陷 UU。
        Logger.shared.info("decrypting columns \(names.joined(separator: ",")) with key \(material.path) (fingerprint \(fp))")
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
    parser.isRowLiteral = true
    try parser.feed([UInt8](text.utf8))
    try parser.finish()
    guard var r = out else {
        // In `.lines` a line with nothing on it IS a record: one empty field.
        // The parser emits nothing for empty input, but that is a parser
        // detail, not a rule: csv2 reads such a line back (`para one\n\npara
        // two\n` round-trips whole) and `-update 1:1 ''` makes one, so
        // -insert/-append must accept it too, or the blank lines between a
        // prose document's paragraphs cannot be edited. KX (see also KC, KU).
        // 在 `.lines` 裡，一行什麼都沒有**就是**一筆紀錄：一個空欄位。解析器對空輸入不吐出任何
        // 東西，但那是解析器的細節，不是規則：csv2 讀得回這樣的一行（`para one\n\npara two\n` 完整
        // 往返），`-update 1:1 ''` 也做得出一個，因此 -insert／-append 也必須接受它，否則散文文件
        // 裡分隔段落的空行就無法編輯。KX（另見 KC、KU）。
        if format == .lines {
            var blank = Record(fields: [Field(value: [])], offset: 0, line: 0)
            blank.number = 0
            return blank
        }
        throw fault("\(what): empty row", "\(what)：空的一列")
    }
    if parser.recordsEmitted > 1 {
        throw fault("\(what): the value spans more than one record",
                    "\(what)：這個值跨越了不只一筆紀錄")
    }
    try checkFieldCount(r, expected: expected, what: what)
    // A supplied row has no RAW to preserve. It was typed on a command line,
    // not read out of a file, so the bytes it arrived as carry no provenance
    // worth keeping -- and keeping them would stop csv2's own quoting rule
    // from applying to it. The edit path writes with preserveRaw, so
    // `-append 'r2, leading'` would write ` leading` unquoted while
    // `-update 1:2 ' leading'` quotes it; the README states the quoting rule
    // as covering "a value you supply".
    //
    // 一列「被交進來的」紀錄沒有 RAW 可以保留。它是在命令列上打出來的，不是從檔案裡讀出來的，
    // 因此它抵達時的那些位元組沒有值得保留的來歷——而保留它們會讓 csv2 自己的加引號規則對它失效。
    // 編輯路徑是以 preserveRaw 寫出的，於是 `-append 'r2, leading'` 會寫出沒有引號的 ` leading`，
    // 而 `-update 1:2 ' leading'` 會加引號；README 把加引號規則寫成涵蓋「你交進來的值」。
    for i in r.fields.indices { r.fields[i].raw = nil }
    r.number = 0
    return r
}

/// Splits `-add-column`'s NAME into one title per header row.
///
/// It is parsed as a CSV record, not split on commas, because a column name
/// may contain a comma and this tool refuses to lose one anywhere else.
/// `'note,備註'` is two titles; `'"a,b",備註'` is a column literally called
/// `a,b` and its Chinese title.
///
/// 把 `-add-column` 的 NAME 切成「每一列標頭一個標題」。
/// 它是以一筆 CSV 紀錄來解析的，不是用逗號切開，因為一個欄位名稱可能含有逗號，而這個工具在其他
/// 任何地方都不會弄丟它。`'note,備註'` 是兩個標題；`'"a,b",備註'` 是一個「名字就叫 a,b」的欄位
/// 加上它的中文標題。
func splitHeaderName(_ s: String) throws -> [String] {
    var records: [[String]] = []
    let parser = RecordParser(format: .csv) { r in
        records.append(r.fields.map { String(decoding: $0.value, as: UTF8.self) })
        return true
    }
    do {
        try parser.feed(Array(s.utf8) + [BYTE_LF])
        if !parser.stopped { try parser.finish() }
    } catch let e as CSV2Error {
        throw fault("-add-column NAME is not one valid CSV record: \(e.message)",
                    "-add-column 的 NAME 不是一筆合法的 CSV 紀錄：\(e.messageZh)")
    }
    guard records.count == 1 else {
        throw fault("-add-column NAME must be one CSV record, not \(records.count)",
                    "-add-column 的 NAME 必須是一筆 CSV 紀錄，不是 \(records.count) 筆")
    }
    return records[0]
}

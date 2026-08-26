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
        // columns being written as they arrived. Turning it off wholesale made
        // `-r -rownum` quote differently from `-r` on the same file: `"   "`
        // came out as `   `, one flag away, with no reason a reader could see.
        // preserveRaw 是「逐欄位」的——沒有原樣位元組的欄位會退回它的值——因此多一個 rownum
        // 欄，不會讓其他欄位失去「照原樣寫出」。整體關掉它的結果是 `-r -rownum` 與 `-r` 對
        // 同一個檔案給出不同的引號：`"   "` 變成 `   `，只差一個旗標，而讀者看不出任何理由。
        sink.write(FieldEncoder.encodeRecord(rec, format: ctx.format,
                                             preserveRaw: ctx.preserveRaw))
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
/// Escapes what would end a line -- a newline or a carriage return -- and
/// every other C0 control character and DEL, as `\xNN`.
///
/// This is the whole-message escape, and it is deliberately narrower than
/// `reportEscape`. One choke point protects line integrity -- an entry can
/// never be forged by opening a second line, and no future message has to
/// remember -- but a choke point cannot tell an author's PROSE from an
/// interpolated VALUE, and those two need opposite treatment.
///
/// Escaping everything there was tried, on 2026-08-20, and it broke the
/// messages that teach escaping:
///
///     README:  undefined escape sequence \q; .csv2 defines only \n, \r and \\
///     printed: undefined escape sequence \\q; .csv2 defines only \\n, \\r and \\\\
///
/// A reader who followed the message wrote a literal backslash-n into a
/// `.csv2` cell and got rc=0 with the wrong value. Backslashes in prose are
/// the author's; backslashes in a value are data. So the value sites escape
/// fully -- `redact`, the logged invocation, and a message quoting input back
/// -- and the BACKSLASH is still not touched here.
///
/// The CONTROL CHARACTERS are, and that half of "escape everything" was thrown
/// out with the half that was wrong. csv2's own prose contains no ESC, no BEL,
/// no TAB: every control character in a message arrived from data. Leaving
/// them raw put live terminal control on stderr from an input the caller may
/// not have chosen -- `no column named "<ESC>[2K…"` erases the line it is
/// printed on, which is the hazard this file already argues for escaping the
/// locating report, one screen away. The line count held throughout; the rule
/// did not.
///
/// 那個「全部都跳脫」的決定,被丟掉的不只是錯的那一半。csv2 自己的散文裡沒有 ESC、沒有 BEL、
/// 沒有 TAB:訊息裡的每一個控制字元都來自資料。放它們原樣通過,等於把「活的」終端機控制序列
/// 送上 stderr,而那個輸入未必是呼叫端挑的——`no column named "<ESC>[2K…"` 會擦掉它正被印出的
/// 那一行,而這正是本檔案在一個螢幕之外、為「定位報告要跳脫」所給的同一個理由。行數的承諾
/// 一直守著,規則沒有。
/// 只跳脫「會結束一行」的東西：換行與歸位字元。
///
/// 這是「整則訊息」的跳脫，而它刻意比 `reportEscape` 窄。單一的關卡守住「一筆一行」——
/// 一筆紀錄永遠無法靠開出第二行來偽造，而日後的訊息也不必記得任何事——但一個關卡分不出
/// 「作者寫的散文」與「插進去的值」，而那兩者需要的處理正好相反。
///
/// 「全部都跳脫」試過了，是 2026-08-20，而它弄壞了那些「教你怎麼跳脫」的訊息：照著訊息寫的
/// 人會把一個字面的反斜線 n 寫進 `.csv2` 儲存格，rc=0，而值是錯的。散文裡的反斜線屬於作者；
/// 值裡面的反斜線是資料。因此「值」的那些地方做完整跳脫——`redact` 與記入 log 的呼叫——
/// 而這裡只處理那兩個會破壞格式的字元。
func lineEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    // Unicode SCALARS, not Characters. A Swift `Character` is a grapheme
    // cluster and CRLF is ONE of them, so a `case "\n"` / `case "\r"` switch
    // over Characters matches neither half of a `\r\n` pair and lets it
    // through intact. A bare LF was escaped correctly; `\r\n` walked straight
    // out, opening a second line in the log whose entire content -- timestamp
    // included -- came from the input, reachable from a plain `-contains` with
    // no write access to anything.
    //
    // The README warns about this exact property of the language for
    // `--pretty`: "grapheme clusters with emoji presentation applied, NOT a
    // per-code-point lookup". Same fact, few hundred lines away, and the
    // escaper walked into it.
    //
    // 用 Unicode「純量」，不是 Character。Swift 的 `Character` 是 grapheme cluster，而 CRLF
    // 就是其中「一個」，因此以 Character 去 switch 的 `case "\n"` / `case "\r"` 對一個
    // `\r\n` 兩半都不匹配，讓它原樣通過。單獨的 LF 被正確跳脫；`\r\n` 直接走了出去，在
    // log 裡開出第二行，而那一行的全部內容——連同時間戳——都來自輸入，且只需要一次普通的
    // `-contains`，完全不需要對任何東西有寫入權限。
    //
    // README 就在 `--pretty` 那一節警告過這個語言性質：「grapheme cluster 加上 emoji
    // presentation，不是逐 code point 查表」。同一件事，相隔幾百行，而跳脫器撞了上去。
    for u in s.unicodeScalars {
        switch u {
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out
}

func reportEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    // Scalars, for the reason spelled out on lineEscape above: CRLF is a
    // single Character and a Character switch lets it through. Here that broke
    // "one line per matching cell" -- one hit printed two lines, so `cut -f1`
    // returned a fragment of prose where an address belongs. That is the
    // failure this function was written to prevent, in the interface this tool
    // recommends for scripts.
    // 用純量，理由與上面 lineEscape 的註解相同：CRLF 是單一個 Character，而以 Character
    // 去 switch 會讓它通過。在這裡，那打破的是「每個命中的儲存格一行」——一個命中印出了
    // 兩行，於是 `cut -f1` 在該是位址的地方回傳一段散文碎片。那正是這個函式當初被寫出來
    // 所要防止的失敗，而且發生在這個工具推薦給腳本使用的那個介面上。
    for u in s.unicodeScalars {
        switch u {
        case "\\": out += "\\\\"
        case "\t": out += "\\t"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        default:
            // Every other C0 control, and DEL, as \\xNN. The report is written to a
            // terminal, and ESC is not text there: a value can start a colour
            // sequence, move the cursor, or erase the line it is being printed on --
            // including the address printed before it. A round put an ESC-[-3-1-m in
            // a cell and the report handed it to the terminal unchanged.
            // The three that already have names keep their short forms. This does not
            // make the third column reversible -- the README says it is a display form
            // and not for feeding back -- it makes it one that cannot rewrite what the
            // other columns said.
            // 其餘每一個 C0 控制字元與 DEL，一律寫成 \\xNN。這份報告是印到終端機上的，而 ESC
            // 在那裡不是文字：一個值可以起一段顏色序列、移動游標，或抹掉它正被印出的那一行
            // ——連同印在它前面的那個位址。已經有名字的那三個保留短形式。這不會讓第三欄變得
            // 可逆，它讓那個形式無法改寫其他欄位說過的話。
            if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
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
        // A NUMBER needs no header. This refused every `-get r:c` on a file
        // with no header row -- including `1:1` on a suffix-less file, where
        // the column can only ever be 1. The message was written when every
        // file had a header and a name was the interesting case; it stayed
        // true of names and became false of numbers the moment zero-header
        // files existed. Phase 8b.
        // 一個「數字」不需要標頭。這裡原本會拒絕「對沒有標頭列的檔案」下的每一次 `-get r:c`
        // ——包括對一個沒有副檔名的檔案下 `1:1`，而那種檔案的欄位號永遠只可能是 1。這則訊息是在
        // 「每個檔案都有標頭」的年代寫的，那時「名稱」才是有意思的情況；它對名稱一直為真，而在
        // 「零標頭列的檔案」存在的那一刻，它對數字就成了假的。第 8b 階段。
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
            if ctx.physical { addr += "@L\(r.line)" }
            // The A1 row is the record number plus the header rows above it,
            // which is the row a spreadsheet puts the record on.
            //
            // This used to be the PHYSICAL line, defended by an argument that
            // was half right: the record number ALONE would print [A1] for a
            // cell any spreadsheet calls A3, and [E0] for a header, and A1
            // notation has no row 0. Both true -- but the answer to that is to
            // add the header rows, not to switch to the line. With one record
            // per line the two are equal, so every example in the README and
            // every fixture in this repo agreed with both readings and could
            // not tell them apart.
            //
            // They differ exactly once: a record spanning lines still occupies
            // ONE spreadsheet row, because the quoted newline stays inside the
            // cell. Record 3 of a one-header `.csv` whose earlier records span
            // six lines is row 4; the physical line is 10. csv2 printed [B10],
            // at rc=0, with nothing marking it. And that case is the only one
            // where `--a1` offers anything `--physical` does not -- everywhere
            // else it was `--physical` in another notation.
            //
            // A1 的列號取「紀錄號 + 其上方的標頭列數」，那才是試算表放這筆紀錄的那一列。
            //
            // 原本取的是「物理行號」，並附有一段對了一半的論證：光用紀錄號，確實會讓一個
            // 任何試算表都叫作 A3 的儲存格印成 [A1]、讓標頭印成 [E0]，而 A1 記法沒有第 0 列。
            // 兩者都對——但對它們的解法是「加上標頭列數」，不是「改用行號」。一筆一行時兩者
            // 相等，於是 README 的每一個範例與本 repo 的每一份 fixture 都同時符合兩種讀法，
            // 分辨不出差別。
            //
            // 它們只在一種情況下不同：跨行的紀錄在試算表裡仍然只佔「一列」，因為引號內的換行
            // 留在儲存格內。一個一列標頭的 `.csv`，若前面幾筆各佔六行，第 3 筆是第 4 列，而
            // 物理行號是 10。csv2 印的是 [B10]，rc=0，沒有任何標記。而那個情況正是 `--a1`
            // 唯一比 `--physical` 多給出一點東西的場合——在其他每一處，它只是換一種寫法的
            // `--physical`。
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
        // the last and discard the first. csv2's own bytes contain both values;
        // the reader's parser destroys one before the reader ever sees it.
        //
        // That is worse than the duplicate-name bug fixed alongside it. There,
        // an address picked a column silently. Here a value is DESTROYED
        // silently, and it is unrecoverable from the parsed object by any
        // means, so "fields is keyed by column name, which is the way to pull
        // one column out without counting" is not merely ambiguous for such a
        // file -- it is false.
        //
        // Refused, the same way an ambiguous address is refused, and pointing
        // at the shapes that can carry it. The report shape is unaffected: it
        // emits record, field, header_en and value per hit, so two columns with
        // one name are two lines, not one lost key.
        //
        // 一筆紀錄的物件以「欄名」作為 `fields` 的鍵，而一個 JSON 物件無法在同一個鍵下
        // 放兩個值。照樣輸出的結果是重複鍵：RFC 8259 在語法上允許（它把「如何解讀」列為
        // 未定義），而實際上每一個有人在用的解析器都會把它收合——Python 的 json 與
        // JavaScript 的 JSON.parse 都留下最後一個、丟掉第一個。csv2 自己的位元組裡兩個值
        // 都在；是讀者的解析器在讀者看到之前就毀掉了其中一個。
        // 那比與它一同修正的「同名欄位」缺陷更糟。那裡是一個位址靜默地挑了一欄；這裡是一個值
        // 被靜默地「毀掉」，而且從解析後的物件裡再也無法以任何方式取回。因此「fields 以欄名
        // 為鍵，那是不必數欄位就能取出某一欄的方法」對這種檔案而言不只是有歧義——它是假的。
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
        // A record object keys `fields` by the FIRST header row, so on a
        // `.csv2` the second row had no way out through --json at all: not per
        // record, not on this line, and `--zh` changed nothing and said nothing
        // (rc=0, silently). The document promised otherwise -- "`--json` always
        // carries both names, because a consumer that wanted one of them can
        // pick, and one that wanted the other cannot invent it" -- and that was
        // true only of the locating report, which emits header_en and header_zh
        // per hit. Round 77, JN.
        //
        // It goes on the meta line rather than into every record: the names do
        // not vary by record, and repeating them 450,000 times to carry three
        // strings would be the kind of output this tool refuses elsewhere. An
        // ARRAY, not an object, because the second row is positional -- it can
        // legitimately repeat a name, which is exactly what an object cannot
        // hold, and refusing a file for that would be a new refusal invented to
        // serve a serialisation choice.
        //
        // `.csv` is untouched: it has one header row, and the `fields` keys are
        // already it.
        //
        // 第二列標頭，寫在唯一有第二列的那個格式上。
        // 一筆紀錄的物件是以「第一列標頭」為鍵的，因此在 `.csv2` 上，第二列根本沒有任何出口
        // 經由 --json 出來：不在每一筆裡、不在這一行上，而 `--zh` 什麼也沒改變、什麼也沒說
        // （rc=0，安靜）。文件承諾的是另一回事——「`--json` 一律帶著兩個名字，因為只想要其中
        // 一個的消費端可以自己挑，而想要另一個的那個沒辦法自己發明」——而那只對定位報告為真，
        // 它每個命中都輸出 header_en 與 header_zh。第 77 回合，JN。
        // 它放在 meta 行而不是每一筆裡：那些名字不隨紀錄變化，為了三個字串重複 45 萬次，正是
        // 這個工具在別處會拒絕的那種輸出。用「陣列」而不是物件，因為第二列是按位置的——它可以
        // 合法地重複同一個名字，而那恰好是物件裝不下的；為了一個序列化的選擇去發明一條新的拒絕，
        // 不成立。
        // `.csv` 不受影響：它只有一列標頭，而 `fields` 的鍵已經就是它。
        var zh = ""
        if ctx.headers.count > 1 {
            let names = ctx.headers[1].fields.map {
                JSONOut.string($0.value, asciiOnly: ctx.jsonASCII)
            }
            zh = ",\"header_zh\":[" + names.joined(separator: ",") + "]"
        }
        sink.write("{\"meta\":{\"format\":\"\(ctx.format.rawValue)\",\"headers\":\(ctx.headers.count),\"fields\":\(fields)\(zh)\(prot)}}\n")
    }

    /// Refused rather than substituted. JSON is text, so a byte sequence that
    /// is not valid UTF-8 cannot be carried: Swift's decoder puts U+FFFD in
    /// its place and the line stays valid JSON, which is data loss that looks
    /// exactly like success -- in the shape this README recommends when the
    /// value is the thing that matters. `-get` hands back the bytes and the
    /// locating report says `<non-UTF-8: 63 61 66 e9>`; only --json was
    /// quietly lying.
    /// 拒絕，而不是替換。JSON 是文字，因此一段不是合法 UTF-8 的位元組載不進去：Swift 的
    /// 解碼器會放一個 U+FFFD 進去，而那一行仍然是合法的 JSON——那是一種「看起來與成功完全
    /// 相同」的資料遺失，而且發生在「值本身才是重點」時 README 推薦的那個形狀上。`-get`
    /// 交還的是位元組、定位報告會寫 `<non-UTF-8: 63 61 66 e9>`；只有 --json 在安靜地說謊。
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
                // Which header row, when the hit IS in a header row. The
                // locating report says `0a` and `0b`, and the whole stated
                // reason for those two labels is that a hit in the English
                // title row and one in the Chinese title row are
                // distinguishable -- while `--json`, the shape meant for
                // programs, gave `"record":0` for both and left only the
                // physical line to tell them apart.
                // 命中「就在標頭列裡」時，是哪一列。定位報告寫的是 `0a` 與 `0b`，而那兩個
                // 標籤存在的全部理由，就是「英文標題列的命中」與「中文標題列的命中」分得出來
                // ——而 `--json`（給程式看的那個形狀）對兩者都給 `"record":0`，只留下實體行號
                // 可以分辨。
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
        // The generated column follows the same rule as every other one: `--zh`
        // gives the Chinese name, `--en` the English, neither joins both. It
        // was hard-coded to the joined form, so `--en` and `--zh` -- documented
        // as giving "one clean row instead" -- could not clean the one cell
        // csv2 itself had invented, and a ONE-header `.csv` got a `<br>` cell
        // beside plain ones, in a table whose join is explained by the data
        // having two header rows.
        // 這個「生成的」欄位遵守與其他每一欄相同的規則：`--zh` 給中文、`--en` 給英文，都不給
        // 才合併。它原本被寫死成合併的樣子，於是 `--en` 與 `--zh`——文件說它們「會給你乾淨的
        // 一列」——唯獨清不掉 csv2 自己發明的那一格；而一份「只有一列標頭」的 `.csv`，會在一張
        // 「以『資料有兩列標頭』來解釋合併」的表格裡，得到一個與其他純文字格並排的 `<br>` 格。
        if ctx.rownum {
            names.append(ctx.zh ? "列號"
                       : ctx.enOnly || (ctx.headers.count < 2) ? "rownum"
                       : "rownum<br>列號")
        }
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
                    "-md --pretty has to hold the whole table to align it, and this one is over \(prettyLimit()) bytes; drop --pretty (a Markdown renderer produces the same table from it -- a terminal does not, it will be ragged) or raise CSV2_PRETTY_MAX_BYTES",
                    "-md --pretty 必須持有整張表才能對齊，而這一張超過 \(prettyLimit()) 位元組；請拿掉 --pretty（Markdown 算出來是同一張表——終端機裡則不是，它會參差不齊），或調高 CSV2_PRETTY_MAX_BYTES")
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
        // Report the widths. This is the one number csv2 computes that it had no
        // way of telling anyone -- -debug already gives read_bytes, file_bytes,
        // peak_rss_bytes, fields and records, and the README names DISPLAY
        // WIDTH as the fourth number and the whole point of --pretty, while
        // offering no way to observe it.
        //
        // Round 40's reader had to build the instrument himself to check the
        // alignment, got it wrong twice, and nearly filed two defect reports
        // against correct code. A tool that claims a property and hands you no
        // way to measure it turns verification into "reimplement it and
        // compare" -- and when the reimplementation is the thing that is wrong,
        // the tool is what looks wrong.
        //
        // 把欄寬報出來。這是 csv2 會算、卻沒有辦法告訴任何人的那一個數字——-debug 早就給了
        // read_bytes、file_bytes、peak_rss_bytes、fields 與 records，而 README 指名
        // 「顯示寬度」是第四個數字、也是 --pretty 的全部意義，卻不提供任何觀察它的方法。
        // 第 40 回合的讀者為了檢查對齊，只好自己造量測工具，造錯了兩次，差點對正確的程式碼
        // 提出兩份缺陷報告。一個宣稱了某個性質、卻不給你量它的工具，會把「驗證」變成
        // 「重新實作一次再比對」——而當出錯的是那個重新實作時，看起來錯的會是這支工具。
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
                // What it cannot give is WHICH thing was wrong. This message
                // used to say "the cell was modified after it was encrypted",
                // and a blind-test subject got it by editing the HEADER --
                // rewriting the stored fingerprint to the one their wrong key
                // derives, which defeats the O(1) pre-check and leaves the tag
                // to do the work. The real cause there was a wrong key, and
                // the message named a cell that nobody had touched.
                //
                // Three causes produce this identically and the tag cannot
                // separate them, so all three are named. The record number is
                // where the failure was DETECTED, which is worth saying
                // plainly, because this project's error-location table
                // promises that `record N` is where the fault is -- and for
                // this one message that promise cannot be kept.
                //
                // AEAD 的認證標籤帶來 SHA-256 給不了的性質：被竄改的儲存格會失敗，而不是
                // 安靜地還原出錯誤的內容。
                //
                // 它給不了的是「錯的是哪一個」。這則訊息原本寫「該儲存格在加密之後被修改過」，
                // 而一位盲測受測者是靠改「標頭」得到它的——把存起來的指紋改寫成他那把錯金鑰
                // 會導出的值，於是 O(1) 預檢被繞過，剩下標籤去做事。那裡真正的成因是「金鑰
                // 不對」，而訊息指名了一個沒有人碰過的儲存格。
                //
                // 有三種成因會產生一模一樣的結果，而標籤分不出它們，因此三個都寫出來。
                // 紀錄編號是「偵測到失敗的位置」，這一點值得明講，因為本專案那張「錯誤位置」
                // 的表承諾 `record N` 就是出問題的地方——而這一則訊息守不住那個承諾。
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

/// Any column the FILE says is protected joins the redaction set, whatever this
/// run is doing.
///
/// Before 2026-08-18 the set was populated only by buildTransform, from the
/// columns being transformed right now. So `-hash secret` redacted `secret` in
/// its own log, and `-update 1:secret NEW` on the resulting file -- a header
/// reading `secret:hmac:d6c8da42`, the file declaring in writing that the
/// column is sensitive -- wrote NEW to the log in the clear. The run that put
/// the value in was protected; the run that changed it was not.
///
/// The header is the file's own statement about which columns hold secrets. It
/// outlives any single invocation, and it is the only thing that can be right
/// about a file the caller did not create.
///
/// 任何「檔案自己說它受保護」的欄位都會進入遮蔽集合，不論這次執行在做什麼。
/// 2026-08-18 之前，這個集合只由 buildTransform 依「本次要轉換的欄位」填入。於是
/// `-hash secret` 會在它自己的 log 裡遮蔽 secret，而對其產物執行 `-update 1:secret NEW`
/// ——那個檔案的標頭寫著 `secret:hmac:d6c8da42`，是這個檔案白紙黑字宣告該欄位敏感——卻會把
/// NEW 明文寫進 log。放進那個值的那次執行受保護，改動它的那次執行不受保護。
/// 標頭是檔案自己對「哪些欄位存放秘密」的陳述。它比任何單次呼叫都活得久，而且它是唯一
/// 可能對「一個不是呼叫者建立的檔案」說得準的東西。
/// One predicate for "the file's own header says this column holds a
/// transformed value". Two things depend on it and they must not drift: what
/// the log redacts, and what an edit is refused on. They were separate before
/// 2026-08-19, and the gap between them was a defect -- redaction covered the
/// column while editing did not, so a value the log declined to print was
/// written into a column it destroyed.
/// 「檔案自己的標頭說這一欄存放的是轉換過的值」——只有一個謂詞。有兩件事依賴它，而它們
/// 不能各走各的：log 要遮蔽什麼，以及編輯要在什麼上面被拒絕。2026-08-19 之前這兩者是
/// 分開的，而它們之間的落差就是一個缺陷——遮蔽涵蓋了那一欄而編輯沒有，於是一個 log 拒絕
/// 印出來的值，被寫進了一個它會摧毀的欄位。
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
/// fingerprints. Found by extending defect W: the first fix covered -update
/// and -delete -cell, and -append walked straight past it into the same
/// destruction at rc=0.
/// 把一整列原始資料寫進這樣的檔案。與「單格」分開，因為呼叫者並不是瞄準那個受保護欄位——
/// 那一列只是剛好有它的一欄，而且**沒有任何他們給得出的值會是對的**，因為那個轉換需要金鑰，
/// 而標頭裡只有金鑰的指紋。這是延伸缺陷 W 時發現的：第一版的修正只涵蓋 -update 與
/// -delete -cell，而 -append 直接繞過它、以 rc=0 造成同樣的破壞。
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
        // Each of these guards used to look for ITS OWN marker only: -hash
        // refused an already-hashed column, -encrypt refused an
        // already-encrypted one, and neither looked at the other's.
        //
        // `-hash` on an `:enc:` column was therefore accepted, and it is the
        // worst thing this tool can do. It hashes the CIPHERTEXT one way and
        // overwrites the `:enc:` marker -- taking the salt with it -- at rc=0,
        // printing nothing, with an audit entry saying it hashed a column. The
        // correct key afterwards gets `no encrypted columns found`. One
        // well-formed command, and the data is gone.
        //
        // The README already promised this was refused: "re-masking an
        // already-marked column is refused rather than layered". The promise
        // was kept for one direction out of two.
        //
        // 這兩個守衛原本各自「只看自己那一種標記」：-hash 拒絕已雜湊的欄位、-encrypt 拒絕
        // 已加密的欄位，而兩者都不看對方的。
        //
        // 於是對 `:enc:` 欄位下 `-hash` 是被接受的——而那是這個工具做得出來最糟的一件事。
        // 它把「密文」單向雜湊掉，並覆寫 `:enc:` 標記、連同 salt 一起帶走，rc=0、不印任何
        // 東西，而稽核紀錄說它雜湊了一個欄位。事後拿正確的金鑰去解，得到的是
        // `no encrypted columns found`。一個格式完全正確的指令，資料就沒了。
        //
        // README 早就承諾過它會被拒絕：「對一個已經標記過的欄位再次遮蔽會被拒絕，而不是
        // 疊加。」那個承諾，兩個方向裡守住了一個。
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
        // The unkeyed path said nothing at all. -encrypt names its columns and
        // so does the keyed hash; the one that is irreversible AND
        // dictionary-attackable logged neither the columns nor the fact that
        // no key was used. The audit trail was weakest where the operation is
        // hardest to undo.
        // 無金鑰那條路先前什麼也不說。-encrypt 會列出它的欄位，有金鑰的雜湊也會；而那個
        // 「不可逆、又可用字典攻破」的組合，既沒有記下欄位，也沒有記下「沒有用金鑰」。
        // 稽核軌跡最弱的地方，正是那個最難還原的操作。
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
        // -encrypt and -hash both log which key they used; -decrypt did not, so
        // the audit trail recorded every locking and no unlocking. In an audit
        // that is the wrong way round: encrypting puts data away, decrypting
        // takes it out, and "who opened this column, with which key" is the
        // line somebody comes looking for. The README's log table promised the
        // fingerprint without excepting -decrypt. Round 40, defect UU.
        // -encrypt 與 -hash 都會記錄自己用了哪一把金鑰，-decrypt 不會——於是稽核軌跡記下了
        // 每一次上鎖、沒有記下任何一次開鎖。就稽核而言那是反的：加密是把資料收起來，解密是
        // 把它拿出來，而「誰用哪一把金鑰把這一欄打開了」正是日後有人會來找的那一行。
        // README 的 log 表承諾了指紋，並未為 -decrypt 開例外。第 40 回合，缺陷 UU。
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
    // A supplied row has no RAW to preserve. It was typed on a command line,
    // not read out of a file, so the bytes it arrived as carry no provenance
    // worth keeping -- and keeping them is what stopped csv2's own quoting
    // rule from applying to it.
    //
    // `-append 'r2, leading'` wrote ` leading` UNQUOTED, while
    // `-update 1:2 ' leading'` quoted the identical value, because the edit
    // path writes with preserveRaw and an inserted row went out through it
    // with its literal bytes attached. csv2 reads its own output back
    // correctly either way; the spreadsheets and "several parsers" the
    // quoting rule exists for do not, and the README states that rule as
    // covering "a value you supply".
    //
    // 一列「被交進來的」紀錄沒有 RAW 可以保留。它是在命令列上打出來的，不是從檔案裡讀出來的，
    // 因此它抵達時的那些位元組沒有值得保留的來歷——而「保留它們」正是讓 csv2 自己的加引號規則
    // 對它失效的原因。
    //
    // `-append 'r2, leading'` 寫出的 ` leading` 沒有引號，而 `-update 1:2 ' leading'` 對同一個
    // 值加了引號：編輯路徑是以 preserveRaw 寫出的，而一列被插入的紀錄帶著它的字面位元組走了
    // 那條路。兩種寫法 csv2 自己都讀得回來；而那條加引號規則所為之存在的試算表與「好幾種
    // 解析器」不行，何況 README 把那條規則寫成涵蓋「你交進來的值」。
    for i in r.fields.indices { r.fields[i].raw = nil }
    r.number = 0
    return r
}

import Foundation

// ---------------------------------------------------------------------
// MARK: - Reading a Markdown table back / 把一張 Markdown 表讀回來
//
// `-md` could render a table and nothing could read one. Phase 8a.
//
// The strategy is translation, not a second parser: a `.md` becomes canonical
// `.csv2` bytes and the existing reader takes it from there. Every rule that
// reader enforces -- field counts, the header-row check, escaping, the
// refusals -- then applies to a Markdown table for free, and cannot drift
// away from the CSV path because there is only one path.
//
// `-md` 算繪得出一張表，而沒有任何東西讀得回一張表。第 8a 階段。
// 做法是「翻譯」而不是第二個解析器：一個 `.md` 會變成標準的 `.csv2` 位元組，之後交給既有的
// 讀取器。那個讀取器執行的每一條規則——欄數、標頭列檢查、跳脫、那些拒絕——就免費地適用於一張
// Markdown 表，而且不可能與 CSV 那條路徑漂移，因為只有一條路徑。
// ---------------------------------------------------------------------

enum MarkdownIn {
    /// Overridable for the same reason CSV2_INDEX_MIN_BYTES is: so the limit
    /// can be TESTED without a 16 MiB fixture.
    /// 可覆寫的理由與 CSV2_INDEX_MIN_BYTES 相同：讓那個上限可以被測試，而不需要一個 16 MiB
    /// 的 fixture。
    static func maxBytes() -> Int {
        if let v = ProcessInfo.processInfo.environment["CSV2_MD_MAX_BYTES"], let n = Int(v) {
            return n
        }
        return 16 * 1024 * 1024
    }

    /// One cell, with the escapes `MarkdownOut.cell` writes undone.
    ///
    /// The order mirrors the writer's exactly and in reverse, which is the
    /// only way the pair can be checked by reading them side by side. An
    /// UNESCAPED `<br>` is a newline; `\<br>` is the literal text; and a
    /// backslash that escapes something is consumed, so `\\` is one backslash.
    ///
    /// 一個儲存格，把 `MarkdownOut.cell` 寫下的跳脫解開。
    /// 順序與寫出去那一側完全相反且一一對應，那是「把兩者並排讀就能檢查」的唯一辦法。
    /// **未跳脫**的 `<br>` 是一個換行；`\<br>` 是那段字面文字；而一個「跳脫了某個東西」的反斜線
    /// 會被吃掉，因此 `\\` 是一個反斜線。
    static func unescape(_ cell: String) throws -> [UInt8] {
        var out: [UInt8] = []
        let s = Array(cell.unicodeScalars)
        var i = 0
        while i < s.count {
            if s[i] == "\\" , i + 1 < s.count {
                let n = s[i + 1]
                switch n {
                case "\\": out.append(0x5C); i += 2
                case "|":  out.append(0x7C); i += 2
                case "t":  out.append(0x09); i += 2
                case "<":
                    // `\<br>` -- a literal `<br>` that must not become a newline.
                    // `\<br>` —— 一段字面的 `<br>`，它不能變成換行。
                    if i + 4 < s.count, s[i+2] == "b", s[i+3] == "r", s[i+4] == ">" {
                        out.append(contentsOf: Array("<br>".utf8)); i += 5
                    } else {
                        out.append(0x5C); i += 1
                    }
                case "x":
                    guard i + 3 < s.count,
                          let b = UInt8(String(String.UnicodeScalarView(s[(i+2)...(i+3)])), radix: 16) else {
                        throw fault(
                            "a Markdown cell contains \\x that is not followed by two hex digits; csv2 wrote \\xNN for the bytes it escaped and will not guess what this one was",
                            "一個 Markdown 儲存格裡的 \\x 後面沒有接兩位十六進位數字；csv2 為它跳脫的位元組寫的是 \\xNN，而它不會去猜這一個原本是什麼")
                    }
                    out.append(b); i += 4
                default:
                    // An escape this writer never produces. Refused rather
                    // than passed through: a backslash that means nothing here
                    // means the file was not written by -md, and guessing is
                    // how a wrong value gets stored looking right.
                    // 一個這個寫出端從不產生的跳脫。拒絕，而不是原樣通過：一個在這裡沒有意義的
                    // 反斜線，表示這個檔案不是 -md 寫的，而用猜的正是「一個錯的值被存進去、看起來
                    // 卻沒問題」的由來。
                    throw fault(
                        "a Markdown cell contains the escape \\\(String(n)), which -md never writes; csv2 will not guess what it meant",
                        "一個 Markdown 儲存格含有跳脫 \\\(String(n))，而 -md 從不寫出它；csv2 不會去猜它的意思")
                }
                continue
            }
            // An unescaped `<br>` is the newline -md wrote.
            // 未跳脫的 `<br>`，就是 -md 寫下的那個換行。
            if s[i] == "<", i + 3 < s.count, s[i+1] == "b", s[i+2] == "r", s[i+3] == ">" {
                out.append(0x0A); i += 4
                continue
            }
            out.append(contentsOf: Array(String(s[i]).utf8))
            i += 1
        }
        return out
    }

    /// Splits one table row on unescaped `|`, dropping the delimiters at each
    /// end. `\|` is data and does not split.
    /// 以「未跳脫的 `|`」切開一列，並丟掉兩端的分隔符。`\|` 是資料，不會造成切分。
    static func cells(of line: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var esc = false
        for ch in line {
            if esc { cur.append("\\"); cur.append(ch); esc = false; continue }
            if ch == "\\" { esc = true; continue }
            if ch == "|" { parts.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        if esc { cur.append("\\") }
        parts.append(cur)
        // A row is `|a|b|`, so the split yields an empty piece at each end.
        // 一列是 `|a|b|`，因此切開後兩端各會多出一個空片段。
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Is this the `|---|:--:|` row? That row is what makes a block of lines a
    /// TABLE rather than prose, and csv2's own reader already names it when it
    /// meets one, so the thing that used to make reading fail is the thing
    /// that now says what the file is.
    /// 這是不是 `|---|:--:|` 那一列？正是那一列讓一疊文字成為一張**表**而不是散文，而 csv2 自己的
    /// 讀取器遇到它時本來就會指名它——於是「讓讀取失敗的那個東西」，成了「說出這個檔案是什麼」的
    /// 那個東西。
    static func isSeparator(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        for c in cells {
            let t = c.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return false }
            var body = t
            if body.hasPrefix(":") { body.removeFirst() }
            if body.hasSuffix(":") { body.removeLast() }
            guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return false }
        }
        return true
    }
}

extension MarkdownIn {
    /// A whole `.md` file translated into canonical `.csv2` bytes, plus how
    /// many header rows it turned out to have.
    ///
    /// The header count is RECOVERED, not asked for. `-md` joins a `.csv2`'s
    /// two header rows with an unescaped `<br>`, so a header cell that splits
    /// in two says the file came from a two-header format and one that does
    /// not says it came from a `.csv`. Every header cell must agree: a file
    /// where one column splits and another does not is ambiguous, and this
    /// tool refuses ambiguity by naming it rather than picking.
    ///
    /// 一整個 `.md` 檔翻譯成標準的 `.csv2` 位元組，外加「它結果有幾列標頭」。
    /// 那個標頭數是**還原**出來的，不是要來的。`-md` 用一個未跳脫的 `<br>` 把 `.csv2` 的兩列標頭
    /// 接起來，因此一個「切得開兩半」的標頭儲存格說出這個檔案來自兩列標頭的格式，而切不開的那個
    /// 說它來自 `.csv`。每一個標頭儲存格都必須一致：一個「這一欄切得開、那一欄切不開」的檔案是有
    /// 歧義的，而這個工具面對歧義的做法是指名它，不是替它挑一個。
    static func translate(path: String, table wanted: Int?) throws -> (bytes: [UInt8], headerRows: Int) {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw fault("cannot open input file: \(path)", "無法開啟輸入檔：\(path)")
        }
        let limit = maxBytes()
        guard data.count <= limit else {
            throw fault(
                "\(path) is \(data.count) bytes, over the \(limit) a Markdown table is read whole at; csv2 translates a .md in memory rather than growing a second record parser, so this one is bounded. Raise CSV2_MD_MAX_BYTES, or convert it once with a .csv2 destination and work on that",
                "\(path) 有 \(data.count) 個位元組，超過「整份讀入」的上限 \(limit)；csv2 是在記憶體裡翻譯 .md，而不是長出第二個紀錄解析器，因此這一項有上界。請調高 CSV2_MD_MAX_BYTES，或先轉換成一個 .csv2 目的地再對它工作")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw fault(
                "\(path) is not valid UTF-8; csv2 reads bytes and a Markdown table is text, so there is nothing here it could split into cells",
                "\(path) 不是合法的 UTF-8；csv2 讀的是位元組，而 Markdown 表是文字，因此這裡沒有東西可以被切成儲存格")
        }

        // Every line, with its number, so a refusal can name where.
        // 每一行連同它的行號，讓一句拒絕說得出「在哪裡」。
        var lines: [(no: Int, text: String)] = []
        var n = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            n += 1
            var l = String(raw)
            if l.hasSuffix("\r") { l.removeLast() }
            lines.append((n, l))
        }

        // Find every table: a header line, a |---| separator under it, and the
        // rows that follow until something stops being a row.
        //
        // Finding them ALL and then deciding is the point. The first version of
        // this read from the top and stopped at the first thing that was not a
        // row -- so a file holding two tables was read as one, and the second
        // table's header and separator went in as DATA. `---,---` became a
        // record and the run exited 0. That is the exact "looks like it
        // succeeded" failure this tool exists to refuse, and it was introduced
        // by the same commit that added the feature.
        //
        // 先把「每一張表」都找出來、再決定，這才是重點。
        // 這段的第一個版本是從頭讀、遇到第一個「不是一列」的東西就停——於是一個含有兩張表的檔案
        // 被讀成一張，而第二張表的標頭與分隔列**當成資料**進去了。`---,---` 變成了一筆紀錄，而
        // 那次執行以 0 結束。那正是這個工具存在所要拒絕的「看起來成功」，而它是被「加入這個功能」
        // 的同一個 commit 帶進來的。
        struct Table { var headerAt: Int; var header: [String]; var rows: [(Int, [String])] }
        var tables: [Table] = []
        var i = 0
        while i < lines.count {
            let l = lines[i].text.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { i += 1; continue }
            guard l.hasPrefix("|") else {
                if wanted == nil {
                    // Prose, and no table was asked for by number. A .md that
                    // is a document with a table in it is a different request
                    // from a .md that IS a table, and --md-table is how the
                    // first one is spelled.
                    // 散文，而且沒有人用編號指定要哪一張表。「一份裡面有表的文件」與「本身就是一張
                    // 表的 .md」是兩種不同的請求，而 --md-table 正是前者的寫法。
                    throw fault(
                        "\(path) line \(lines[i].no) is not a table row: without --md-table, csv2 reads a .md that IS a table, not a document with a table in it. Pass --md-table N to take the Nth table out of a document",
                        "\(path) 第 \(lines[i].no) 行不是一列表格：不給 --md-table 時，csv2 讀的是「本身就是一張表」的 .md，不是「裡面有一張表的文件」。要從一份文件裡取出第 N 張表，請給 --md-table N")
                }
                i += 1; continue
            }
            let header = MarkdownIn.cells(of: lines[i].text)
            guard i + 1 < lines.count, MarkdownIn.isSeparator(MarkdownIn.cells(of: lines[i+1].text)) else {
                if wanted == nil {
                    throw fault(
                        "\(path) line \(lines[i].no + 1): a Markdown table's second line is the separator (|---|---|), and this is not one. Without it these lines are prose that happens to contain pipes",
                        "\(path) 第 \(lines[i].no + 1) 行：一張 Markdown 表的第二行是分隔列（|---|---|），而這一行不是。少了它，這些行只是「剛好含有直線符號」的散文")
                }
                i += 1; continue
            }
            var t = Table(headerAt: lines[i].no, header: header, rows: [])
            i += 2
            while i < lines.count {
                let r = lines[i].text.trimmingCharacters(in: .whitespaces)
                if r.isEmpty || !r.hasPrefix("|") { break }
                let cs = MarkdownIn.cells(of: lines[i].text)
                // A separator here means the line above it was another
                // table's header, not a record of this one.
                // 出現在這裡的分隔列，表示它上面那一行是「另一張表的標頭」，不是這一張的紀錄。
                if MarkdownIn.isSeparator(cs) {
                    if let last = t.rows.last { t.rows.removeLast(); i = lines.firstIndex(where: { $0.no == last.0 })! }
                    break
                }
                t.rows.append((lines[i].no, cs))
                i += 1
            }
            tables.append(t)
        }

        guard !tables.isEmpty else {
            throw fault(
                "\(path) has no Markdown table in it: a table is a header row, a |---| separator, and its records",
                "\(path) 裡面沒有 Markdown 表：一張表是一列標頭、一列 |---| 分隔，以及它的紀錄")
        }
        let chosen: Table
        if let w = wanted {
            guard w >= 1, w <= tables.count else {
                throw fault(
                    "--md-table \(w): \(path) has \(tables.count) table(s)",
                    "--md-table \(w)：\(path) 裡有 \(tables.count) 張表")
            }
            chosen = tables[w - 1]
        } else {
            guard tables.count == 1 else {
                throw fault(
                    "\(path) has \(tables.count) tables, the second starting at line \(tables[1].headerAt); csv2 will not pick one for you. Pass --md-table N",
                    "\(path) 裡有 \(tables.count) 張表，第二張從第 \(tables[1].headerAt) 行開始；csv2 不會替你挑一張。請給 --md-table N")
            }
            chosen = tables[0]
        }

        let headerRows = try headerRowCount(of: chosen.header, path: path)
        // The bytes are handed to the reader as the format the recovered header
        // count implies, so the ESCAPING the translation writes has to be that
        // same format's. Writing .csv2 escapes and then being parsed as .csv
        // left a value's newline as a literal `\n` in the data -- silent
        // corruption, found while fixing the CR rendering rather than by the
        // round that found the CR. One header row is .csv; two is .csv2.
        // 那些位元組是以「還原出來的標頭列數所隱含的格式」交給讀取器的，因此翻譯時寫出的**跳脫**
        // 也必須是同一個格式的。寫 .csv2 的跳脫、卻被當成 .csv 解析，會讓一個值裡的換行以字面
        // `\n` 留在資料裡——靜默的損壞，而它是在修 CR 的算繪時撞到的，不是找到 CR 那個回合抓到的。
        // 一列標頭是 .csv，兩列是 .csv2。
        let wire: Format = headerRows == 2 ? .csv2 : .csv
        var out: [UInt8] = []
        try appendRow(chosen.header, headerRows: headerRows, format: wire, into: &out)
        for r in chosen.rows { try appendRow(r.1, headerRows: 1, format: wire, into: &out) }
        return (out, headerRows)
    }

    /// How many header rows the table had, recovered from the header cells.
    /// 這張表原本有幾列標頭，從標頭儲存格還原出來。
    private static func headerRowCount(of cells: [String], path: String) throws -> Int {
        let splits = cells.map { c -> Int in
            var n = 1, esc = false
            let a = Array(c.unicodeScalars); var i = 0
            while i < a.count {
                if esc { esc = false; i += 1; continue }
                if a[i] == "\\" { esc = true; i += 1; continue }
                if a[i] == "<", i + 3 < a.count, a[i+1] == "b", a[i+2] == "r", a[i+3] == ">" {
                    n += 1; i += 4; continue
                }
                i += 1
            }
            return n
        }
        guard let first = splits.first, splits.allSatisfy({ $0 == first }) else {
            throw fault(
                "\(path): the header row joins two titles with <br> in some columns and not others, so how many header rows this table has cannot be decided without guessing. Make every column agree",
                "\(path)：標頭那一列在某些欄位用 <br> 接了兩個標題、某些沒有，因此「這張表有幾列標頭」無法在不猜的情況下決定。請讓每一欄一致")
        }
        guard first <= 2 else {
            throw fault(
                "\(path): a header cell splits into \(first) titles on <br>, and csv2 knows two formats -- one header row and two. Nothing writes three",
                "\(path)：一個標頭儲存格以 <br> 切成了 \(first) 個標題，而 csv2 只認得兩種格式——一列標頭與兩列。沒有東西會寫出三列")
        }
        return first
    }

    /// One Markdown row becomes one or two `.csv2` lines -- two when this is
    /// the header of a table that was rendered from a `.csv2`, because those
    /// two titles were one cell here and are two rows there.
    /// 一列 Markdown 會變成一或兩行 `.csv2`——兩行，是當這一列是「從 `.csv2` 算繪出來的表」的標頭
    /// 時，因為那兩個標題在這裡是一個儲存格，在那裡是兩列。
    private static func appendRow(_ cells: [String], headerRows: Int, format: Format, into out: inout [UInt8]) throws {
        var columns: [[[UInt8]]] = Array(repeating: [], count: headerRows)
        for c in cells {
            let decoded = try MarkdownIn.unescape(c)
            if headerRows == 1 {
                columns[0].append(decoded)
            } else {
                // The unescaped <br> became a newline in `decoded`; that is
                // the join, and it splits back into the two rows it came from.
                // 未跳脫的 <br> 在 `decoded` 裡變成了一個換行；那就是那個「接起來」的動作，
                // 而它會切回它原本來自的那兩列。
                let parts = decoded.split(separator: 0x0A, maxSplits: 1,
                                          omittingEmptySubsequences: false).map { Array($0) }
                columns[0].append(parts.count > 0 ? parts[0] : [])
                columns[1].append(parts.count > 1 ? parts[1] : [])
            }
        }
        for row in columns {
            var line: [UInt8] = []
            for (i, f) in row.enumerated() {
                if i > 0 { line.append(0x2C) }
                line.append(contentsOf: FieldEncoder.encode(Field(value: f), format: format, preserveRaw: false))
            }
            line.append(0x0A)
            out.append(contentsOf: line)
        }
    }
}

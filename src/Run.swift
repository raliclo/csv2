// =====================================================================
//  Run.swift — the three drivers: select, edit, and the append fast path
//  Run.swift — 三個驅動路徑：選取、編輯，以及追加快路徑
// =====================================================================

import Foundation

func resolveSearchColumn(_ token: String, headers: [Record], path: String) throws -> Int {
    if let header = headers.first { return try resolveColumn(token, header: header) }
    guard let number = Int(token), number == 1 else {
        throw fault("\(path): a file with no header row has one searchable column; use --search-column 1",
                    "\(path)：沒有標頭列的檔案只有一個可搜尋欄位；請使用 --search-column 1")
    }
    return 0
}

// ---------------------------------------------------------------------
// MARK: - Shared setup / 共用的前置
// ---------------------------------------------------------------------

func makeSink(_ o: Options) throws -> ByteSink {
    if let path = o.output { return try ByteSink(atomicPath: path) }
    return ByteSink(stdout: 1 << 16)
}

func makeInPlaceBackup(_ path: String) throws {
    let backup = path + ".bak"
    guard !FileManager.default.fileExists(atPath: backup) else {
        throw fault("backup path already exists: \(backup); refusing to overwrite it",
                    "備份路徑已存在：\(backup)；拒絕覆寫")
    }
    do {
        // A backup must freeze the bytes, not duplicate a symlink that keeps
        // following the target this run is about to edit. `--in-place` deliberately
        // follows the input link; copying the link itself would make INPUT.bak
        // point at the edited file and keep no old content. KN, T229.
        // 備份必須凍結位元組，不是複製一個會繼續跟著「即將被編輯之目標」的 symlink。
        // `--in-place` 刻意跟隨輸入連結；把連結本身複製成 INPUT.bak，它會同樣指向編輯後的檔案，
        // 舊內容一點也不會留下。KN、T229。
        try FileManager.default.copyItem(atPath: resolved(path), toPath: backup)
    } catch {
        throw fault("cannot create backup \(backup): \(error.localizedDescription)",
                    "無法建立備份 \(backup)：\(error.localizedDescription)")
    }
}

func runMarkdownEdit(_ o: Options) throws {
    guard let input = o.input else {
        throw fault("Markdown editing needs -i FILE", "Markdown 編輯需要 -i FILE")
    }

    // Dry run leaves BEFORE anything below can write, and it is a separate
    // branch rather than a flag threaded through the rest.
    //
    // The rest of this function needs `csv.dryRun = false` on the inner edit,
    // because that inner run produces the temp file the renderer reads -- a
    // dry inner run would leave nothing to render. Once it is cleared, nothing
    // below consults `o.dryRun`, so without this exit both writes below run:
    // `--dry-run -md --in-place` would change the input, exit 0, and print
    // nothing at all. LK.
    //
    // Delegating to runEdit with dryRun kept also makes the report the one the
    // README promises, `old -> new` per changed cell, instead of a second
    // Markdown-shaped report that would have to be written and then kept true.
    //
    // dry run 在底下任何東西能寫入「之前」就離開，而且是一條獨立的分支，不是一個穿過其餘程式碼
    // 的旗標。
    //
    // 這個函式的其餘部分需要內層編輯的 `csv.dryRun = false`，因為那次內層執行正是「產生暫存檔
    // 供算繪器讀取」的那一步——乾跑的內層會讓後面沒有東西可以算繪。它一旦被清掉，底下就沒有任何
    // 地方再看 `o.dryRun`，少了這個出口，底下兩處都會寫入：`--dry-run -md --in-place` 會改掉
    // 輸入檔、rc=0，而且什麼都不印。LK。
    //
    // 委派給仍保留 dryRun 的 runEdit，也讓報告就是 README 承諾的那一份（每個變更儲存格一行
    // `old -> new`），而不是另外寫一份 Markdown 形狀的報告、再想辦法讓它保持為真。
    if o.dryRun {
        var report = o
        report.markdown = false
        report.output = nil
        report.inPlace = false
        report.backup = false
        try runEdit(report)
        return
    }

    let probe = try openInput(o)
    let extensionName = probe.headerRows == 2 ? "csv2" : "csv"
    probe.source.close()
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("csv2-edit-\(UUID().uuidString).\(extensionName)").path
    defer { try? FileManager.default.removeItem(atPath: temp) }

    var csv = o
    csv.markdown = false
    csv.output = temp
    csv.inPlace = false
    csv.dryRun = false
    csv.backup = false
    try runEdit(csv)

    var rendered = o
    rendered.edits = []
    rendered.input = temp
    let renderedPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("csv2-render-\(UUID().uuidString).md").path
    defer { try? FileManager.default.removeItem(atPath: renderedPath) }
    rendered.output = renderedPath
    rendered.inPlace = false
    rendered.markdown = true
    try runSelect(rendered)

    let original = try String(contentsOfFile: input, encoding: .utf8)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let replacement = try String(contentsOfFile: renderedPath, encoding: .utf8)
    let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var newLines = replacement.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while newLines.last == "" { newLines.removeLast() }
    if o.mdStyle == .preserve, newLines.count >= 2 {
        let layout = try MarkdownIn.translate(path: input, table: o.mdTable).layout
        let headerKey = MarkdownIn.cells(of: newLines[0])
        if let original = layout.header[headerKey] { newLines[0] = original }
        newLines[1] = layout.separator
        // Keep row OCCURRENCES aligned with the batch row operations. Value
        // lookup alone cannot tell which equal row survived a deletion, or
        // whether an update merely changed one row into another row's value.
        // A nil entry is a newly inserted/appended row and has no old layout.
        // 依批次列操作對齊每一次「列的出現」。只查值分不出刪除後是哪一筆相同列活下來，
        // 也分不出某次 update 是否剛好把一列改成另一列的值。nil 表示新插入／追加的列，
        // 本來就沒有舊排版可保留。
        var inserts: [Int: Int] = [:]
        var deletes: [(Int, Int)] = []
        var appendCount = 0
        for edit in o.edits {
            switch edit {
            case .insert(let at, _): inserts[at, default: 0] += 1
            case .append: appendCount += 1
            case .deleteRange(let from, let to): deletes.append((from, to))
            default: break
            }
        }
        var identities: [(cells: [String], line: String)?] = []
        for (offset, originalRow) in layout.orderedRows.enumerated() {
            let record = offset + 1
            identities.append(contentsOf: repeatElement(nil, count: inserts[record] ?? 0))
            if !deletes.contains(where: { record >= $0.0 && record <= $0.1 }) {
                identities.append(originalRow)
            }
        }
        identities.append(contentsOf: repeatElement(nil, count: appendCount))
        let outputRows = max(0, newLines.count - 2)
        guard identities.count == outputRows else {
            throw fault("Markdown preserve lost row identity: expected \(identities.count) output row(s), rendered \(outputRows)",
                        "Markdown preserve 遺失列身分：預期 \(identities.count) 筆輸出列，實際算繪 \(outputRows) 筆")
        }
        for offset in 0..<outputRows {
            if let identity = identities[offset],
               MarkdownIn.cells(of: newLines[offset + 2]) == identity.cells {
                newLines[offset + 2] = identity.line
            }
        }
    }
    if !o.inPlace {
        guard let output = o.output else {
            throw fault("Markdown editing needs -o FILE or --in-place",
                        "Markdown 編輯需要 -o FILE 或 --in-place")
        }
        let sink = try ByteSink(atomicPath: output)
        sink.write(newLines.joined(separator: "\n") + "\n")
        try sink.close()
        return
    }
    let wanted = o.mdTable ?? 1
    var starts: [Int] = []
    var ends: [Int] = []
    var i = 0
    while i + 1 < oldLines.count {
        if oldLines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") &&
           MarkdownIn.isSeparator(MarkdownIn.cells(of: oldLines[i + 1])) {
            starts.append(i)
            // The reader's own rule, not a second copy of it. RG.
            // 用讀取器自己的那條規則，不是它的第二份。RG。
            let end = MarkdownIn.tableEnd(oldLines, header: i)
            ends.append(end)
            i = end
        } else { i += 1 }
    }
    guard wanted >= 1, wanted <= starts.count else {
        throw fault("--md-table \(wanted): could not locate that table for in-place replacement",
                    "--md-table \(wanted)：找不到要就地替換的那張表")
    }
    let start = starts[wanted - 1], end = ends[wanted - 1]
    // Joined back exactly as it was split: only the table's lines change.
    // Trimming trailing empty lines and adding one "\n" would add a newline to
    // a document without one and drop trailing blank lines -- bytes outside
    // the table. The split keeps a final newline as a last "" element, which
    // this join turns back into that newline. RK.
    // 怎麼拆開就怎麼接回去：只有那張表的行會變。若先丟掉結尾空行再補一個 "\n"，沒有結尾換行的
    // 文件會多一個、以空行結尾的文件會失去它們——都是表格以外的位元組。拆開時，結尾的換行會留成
    // 最後一個 "" 元素，而這裡的接合會把它還原成那個換行。RK。
    let combined = Array(oldLines[..<start]) + newLines + Array(oldLines[end...])
    if o.backup { try makeInPlaceBackup(input) }
    let sink = try ByteSink(atomicPath: o.output ?? resolved(input))
    sink.write(Array(combined.joined(separator: "\n").utf8))
    try sink.close()
}

/// A selection without `-t` produces DATA ROWS, not a valid file of that
/// format. Writing them to a `.csv2` path means the next read eats the first
/// two records as headers -- the exact error this tool exists to prevent.
/// 沒有 `-t` 的選取輸出是資料列，不是該格式的合法檔案。把它們寫進 `.csv2`
/// 路徑，下次讀取時前兩筆資料會被當成標頭吃掉——正是這支工具存在的理由所在的
/// 那個錯誤。
func checkOutputPromise(_ o: Options, emitsRecords: Bool) throws {
    guard let path = o.output, Format.declaresFormat(path: path) else { return }
    if o.markdown {
        // Refused because these bytes are not what the suffix declares, not
        // because csv2 cannot read Markdown back -- it can, so the message
        // names the .md destination that works. Round 78.
        // 拒絕的理由是這些位元組不是那個副檔名所宣告的東西，而不是 csv2 讀不回 Markdown——它讀得
        // 回來，所以訊息會指名一個行得通的 .md 目的地。第 78 回合。
        throw fault("-md writes Markdown but \(path) declares a CSV format; give it a .md destination, which csv2 can read back",
                    "-md 產生 Markdown，但 \(path) 的副檔名宣告的是 CSV 格式；請給它一個 .md 目的地，那個 csv2 讀得回來")
    }
    if o.json {
        throw fault("--json writes JSON Lines but \(path) declares a CSV format",
                    "--json 產生 JSON Lines，但 \(path) 的副檔名宣告的是 CSV 格式")
    }
    if !emitsRecords {
        throw fault("the locating report is not CSV, but \(path) declares a CSV format; use --filter to write records",
                    "定位報告不是 CSV，但 \(path) 的副檔名宣告的是 CSV 格式；要輸出紀錄請用 --filter")
    }
    if !o.withHeader {
        throw fault("\(path) declares a format with a header, so writing data rows there needs -t; without it the next read would take the first record(s) as the header",
                    "\(path) 的副檔名宣告了帶標頭的格式，因此在此寫入資料列必須給 -t；否則下次讀取會把最前面的紀錄當成標頭")
    }
}

func validateHeaders(_ headers: [Record], want: Int, path: String) throws {
    guard headers.count == want else {
        throw fault("\(path): expected \(want) header row(s), found \(headers.count)",
                    "\(path)：預期 \(want) 列標頭，實際只有 \(headers.count) 列")
    }
    // Both header rows must have the same field count, and the data must
    // match it. Never pad to fit: padding hides a shifted column.
    // 兩列標頭必須有相同的欄數，且與資料相同。絕不補空湊合：補空會掩蓋錯位的欄。
    // Checked BEFORE the field-count comparison, because a leading `# ...`
    // line becomes the header and the mismatch is then reported against rows
    // that are all correct. This is the most common shape of KP: the comment
    // is the FIRST line, so it is the header that is wrong, and every message
    // downstream describes a symptom two steps from the cause.
    // 這一項排在欄數比較**之前**，因為一行開頭的 `# ...` 會變成標頭，於是那個不符會被回報在
    // 一堆本身完全正確的列上。這是 KP 最常見的形狀：註解是**第一行**，因此錯的是標頭，
    // 而它下游的每一則訊息描述的都是離原因兩步之遙的症狀。
    if let first = headers.first, first.count == 1,
       first.fields.first?.value.first == BYTE_HASH {
        throw fault(
            "\(path): the header row starts with '#'. csv2 has no comment syntax: in CSV a '#' is data, and a column named '#id' is legal, so skipping such a line would mean guessing which lines are data. To read it as lines -- one field each, bytes verbatim -- pipe it in: csv2 -si --headers 0 < FILE. That touches nothing on disk. Reading it under a name with no .csv/.csv2 suffix does the same, and removing the line makes it a CSV. Note that --headers 0 with a .csv/.csv2 suffix means a HEADERLESS CSV, not lines: the suffix has already declared comma separation",
            "\(path)：標頭列以 '#' 開頭。csv2 沒有註解語法：在 CSV 裡 '#' 是資料，而一個叫 '#id' 的欄位是合法的，因此跳過這樣的一行就等於去猜哪些行是資料。要把它當成一行行來讀（每行一個欄位、位元組原樣），用管線送進來：csv2 -si --headers 0 < FILE，那不會動到磁碟上的任何東西。以「沒有 .csv／.csv2 副檔名」的名字讀取效果相同；移除那一行則會讓它成為一份 CSV。注意：在有 .csv／.csv2 副檔名時，--headers 0 的意思是「沒有標頭列的 CSV」而不是逐行——副檔名已經宣告了逗號分隔")
    }
    if headers.count > 1 && headers[0].count != headers[1].count {
        throw fault(
            "\(path): header row 0a has \(headers[0].count) fields, row 0b has \(headers[1].count); a .csv2 header must have the same field count on both rows",
            "\(path)：標頭 0a 有 \(headers[0].count) 欄，0b 有 \(headers[1].count) 欄；.csv2 的兩列標頭欄數必須相同")
    }
    for (row, header) in headers.enumerated() {
        let rowName = headers.count == 1 ? "0" : (row == 0 ? "0a" : "0b")
        for (column, field) in header.fields.enumerated() {
            let name = headerName(field)
            guard name.contains(":") else { continue }
            let isProtectedMarker = (EncMarker.parse(name).map { !$0.base.contains(":") } ?? false)
                || (name.hasSuffix(":hash") && !name.dropLast(5).contains(":"))
                || (name.range(of: ":hmac:", options: .backwards).map {
                    !name[..<$0.lowerBound].contains(":") && name[$0.upperBound...].isEmpty == false
                } ?? false)
            guard isProtectedMarker else {
                throw fault(
                    "\(path): column \(column + 1) in header row \(rowName) is named \"\(name)\"; column names cannot contain ':'",
                    "\(path)：標頭 \(rowName) 的第 \(column + 1) 欄名稱為「\(name)」；欄名不可包含「:」")
            }
        }
    }
    try checkProtectionAgreement(headers, path: path)
}

/// The two header rows must say the SAME thing about protection.
///
/// Every guard in this tool asks "does the file's own header declare this
/// column transformed", and every one of them reads row 0a. A `.csv2` whose
/// 0b carries `:enc:` and whose 0a does not would walk past all of them:
/// `-update` would write plaintext into an encrypted column, `--json` would
/// report nothing protected, and `-hash` would hash the ciphertext and
/// overwrite the `:enc:` marker and its salt.
///
/// Reading BOTH rows and taking the union would fix the misses and leave the
/// file itself incoherent. Refusing is the answer the rest of this program
/// gives to "two sources disagree": a file whose header rows contradict each
/// other about a column is not a file csv2 can act on, and no verb should
/// have to decide which row wins.
///
/// The marker is compared, not the name. The two rows are meant to differ --
/// that is what the second row is FOR -- so only the `:enc:<fp>:<salt>`,
/// `:hmac:<fp>` and `:hash` parts are matched.
///
/// 兩列標頭對「保護」必須說同一件事。
///
/// 這個工具裡的每一道守衛都在問「這個檔案自己的標頭有沒有宣告這一欄已被轉換」，而它們讀的都是
/// 第 0a 列。一個「0b 帶著 `:enc:`、0a 沒有」的 `.csv2` 會從它們全部旁邊走過去：`-update` 會把
/// 明文寫進加密欄、`--json` 會說什麼都沒被保護，而 `-hash` 會把密文雜湊掉，並覆寫 `:enc:` 標記
/// 與它的 salt。
///
/// 「兩列都讀、取聯集」會修好那些漏接，卻留下一個自相矛盾的檔案。而「兩個來源互相矛盾」時，
/// 這支程式其餘部分給的答案是「拒絕」：一個兩列標頭對某一欄互相矛盾的檔案，不是 csv2 能夠
/// 作用的檔案，而任何一個動詞都不該去決定哪一列說了算。
///
/// 比對的是「標記」，不是「名字」。那兩列本來就該不同——那正是第二列存在的目的——因此只比對
/// `:enc:<fp>:<salt>`、`:hmac:<fp>` 與 `:hash` 那幾部分。
func checkProtectionAgreement(_ headers: [Record], path: String) throws {
    guard headers.count > 1 else { return }
    func marker(_ f: Field) -> String {
        let n = headerName(f)
        if let m = EncMarker.parse(n) { return ":enc:\(m.fingerprint):\(B64.encode(m.salt))" }
        if let r = n.range(of: ":hmac:", options: .backwards) { return String(n[r.lowerBound...]) }
        if n.hasSuffix(":hash") { return ":hash" }
        return ""
    }
    for i in 0..<headers[0].count where i < headers[1].count {
        let a = marker(headers[0].fields[i])
        let b = marker(headers[1].fields[i])
        guard a != b else { continue }
        let sa = a.isEmpty ? "nothing" : a
        let sb = b.isEmpty ? "nothing" : b
        throw fault(
            "\(path): the two header rows disagree about column \(i + 1): row 0a says \(sa), row 0b says \(sb). Every check for a protected column reads the header, and a file whose rows contradict each other has no answer to give -- restore the marker on both rows, or remove it from both",
            "\(path)：兩列標頭對第 \(i + 1) 欄的說法不一致：0a 說 \(sa)，0b 說 \(sb)。每一項「這一欄是否受保護」的檢查讀的都是標頭，而一個兩列互相矛盾的檔案給不出答案——請讓兩列都帶著那個標記，或兩列都不帶")
    }
}

// ---------------------------------------------------------------------
// MARK: - Select / read / search  —— 選取、讀取、搜尋
// ---------------------------------------------------------------------

/// Reads ONLY the header rows. Used when an index seek jumps straight into the
/// data: the column names still have to come from the front of the file.
/// 只讀取標頭列。索引 seek 直接跳進資料區時使用：欄名仍然必須來自檔案開頭。
func readHeaderRows(path: String, format: Format, want: Int) throws -> [Record] {
    var headers: [Record] = []
    let src = try ByteSource(path: path, chunkSize: 1 << 16)
    defer { src.close() }
    let parser = RecordParser(format: format) { r in
        headers.append(r)
        return headers.count < want
    }
    while headers.count < want, let c = src.next() { try parser.feed(c) }
    if headers.count < want { try parser.finish() }
    try validateHeaders(headers, want: want, path: path)
    return headers
}

/// Does a record actually BEGIN at this byte?
///
/// A grid point whose offset has drifted by one lands on the previous record's
/// terminator, and the parser then reads an empty line and refuses it -- with
/// a message about a blank line, naming a record number and a line number both
/// derived from the wrong index -- on a file with no blank line, which
/// `--no-index` reads fine. JB.
///
/// The README's contract for the index: it is an OPTIMISATION and never a
/// PRECONDITION. A seek that cannot be trusted must cost a scan, not an answer.
///
/// The test is the cheapest one that is a real test: parse a single record
/// from that byte and require it to have as many fields as the header. It can
/// still be fooled -- an offset landing mid-record at a plausible boundary
/// parses fine -- but it can only ever REJECT the index, so being fooled costs
/// a scan and never an answer. That asymmetry is why field count is checked
/// here rather than the cheaper "is the previous byte a newline", which the
/// drifted-by-one case would also fail: this catches that AND more.
///
/// 一筆紀錄是不是真的從這個位元組開始？
/// 一個偏移量漂了一個位元組的格點，會落在前一筆的終止符上，於是解析器讀到一個空行並拒絕它
/// ——訊息講的是「空白行」，而它指名的紀錄號與行號，兩個都是從那份錯的索引推導出來的；
/// 那個檔案裡其實沒有空白行，加上 `--no-index` 就讀得到。JB。
/// README 對索引的契約：它是**最佳化**，永遠不是**必要條件**。一個不能信任的 seek，代價應該
/// 是一次掃描，而不是一個答案。
/// 檢查方式取的是「還算得上是檢查」裡最便宜的那個：從那個位元組解析出一筆紀錄，要求它的欄位
/// 數與標頭相同。它仍然可能被騙——一個落在紀錄中間、看起來像邊界的偏移量會解析得很順利——但
/// 它只可能「拒絕」索引，因此被騙的代價是一次掃描，永遠不是一個錯答案。正是這個不對稱，讓
/// 這裡檢查欄位數而不是更便宜的「前一個位元組是不是換行」：那個漂一位的情況兩者都抓得到，
/// 而這個還能多抓一些。
func recordBeginsAt(path: String, offset: UInt64, format: Format,
                    expectedFields: Int, truncatePartial: Bool) -> Bool {
    guard expectedFields > 0 else { return true }
    guard let src = try? ByteSource(path: path, chunkSize: 1 << 16, startAt: offset) else {
        return true
    }
    defer { src.close() }
    var fields: Int? = nil
    let parser = RecordParser(format: format, truncatePartial: truncatePartial) { r in
        fields = r.count
        return false
    }
    // One chunk is enough to hold a record on any file this seek is worth
    // doing on; if the record is longer than 64 KiB the parser simply has not
    // finished and `fields` stays nil, which is treated as "cannot tell" --
    // and "cannot tell" must not reject a working index.
    // 一個 chunk 足以裝下「值得對它做這個 seek 的檔案」上的一筆紀錄；若一筆長過 64 KiB，
    // 解析器只是還沒讀完，`fields` 維持 nil，那被當成「判斷不出來」——而「判斷不出來」不該
    // 去否決一份能用的索引。
    if let c = src.next() { try? parser.feed(c) }
    guard let n = fields else { return true }
    return n == expectedFields
}

/// Decides whether this call can seek instead of scan. The index only helps
/// RANDOM access: `-r` and `-contains` read the whole file no matter what, so
/// they neither use nor create one -- building an index for them is pure waste.
/// 決定這次呼叫能不能用 seek 取代掃描。索引只對隨機存取有幫助：`-r` 與
/// `-contains` 無論如何都要讀完整個檔案，因此既不使用也不建立索引——為它們建
/// 索引是純粹的浪費。
struct IndexPlan {
    var resumeOffset: UInt64?
    var resumeRecord: Int = 1
    var resumeLine: Int = 1
    var lower: Int?
    var upper: Int?
    var builder: IndexBuilder?
}

func planIndex(_ o: Options, plan: InputPlan, lower: Int, upper: Int) -> IndexPlan {
    var out = IndexPlan()
    guard !o.noIndex, let path = o.input, o.contains == nil else { return out }
    let wantsRandomAccess = (o.mid != nil) || (o.tail != nil)
    guard wantsRandomAccess else { return out }

    if let idx = CSVIndex.load(dataPath: path) {
        // No `no_embedded_newlines` requirement here: since index v4 each grid
        // point carries its physical line, so a resume knows the line number
        // `--physical` prints, and the output stays byte-identical with and
        // without an index. Requiring the property would make one quoted
        // newline cost a full scan of the file. The parallel path still uses
        // it, where it means something else.
        // 這裡不要求 `no_embedded_newlines`：自索引 v4 起每個格點都帶著自己的實體行號，恢復解析
        // 知道 `--physical` 要印的行號，有無索引的輸出仍逐位元相同。要求那個性質，會讓一個引號內
        // 的換行就付上整個檔案的掃描。平行路徑仍然用它，而它在那裡的意思是另一回事。
        guard idx.records > 0 else { return out }
        var startRecord = lower
        if let n = o.tail {
            let total = Int(idx.records)
            startRecord = max(1, total - n + 1)
            out.lower = startRecord
            out.upper = total
        }
        guard let gp = idx.gridPoint(forRecord: startRecord) else { return out }
        out.resumeOffset = gp.offset
        out.resumeRecord = gp.recordNumber
        out.resumeLine = Int(gp.line)
        Logger.shared.debug("index hit: record \(startRecord) via grid point \(gp.recordNumber) at byte \(gp.offset)")
        return out
    }

    // No index. Build one only when the scan is happening anyway. `-tail`
    // without an index must read the whole file to find the end, so noting the
    // offsets on the way costs nothing. `-mid` stops early by design, so
    // building there would turn a cheap operation into a full scan.
    // 沒有索引。只在「掃描本來就要發生」時建立。`-tail` 沒有索引時必須讀完整個
    // 檔案才能找到結尾，順手記下偏移量不花額外成本。`-mid` 的設計是提前停止，
    // 在那裡建索引會把一個便宜的操作變成一次全掃描。
    guard o.tail != nil else { return out }
    guard let st = FileStamp.of(path: path), st.size >= UInt64(indexMinBytes()) else { return out }
    out.builder = IndexBuilder(isCSV2: plan.format == .csv2)
    return out
}

/// Builds the sidecar on demand. Without this an index only ever appears as a
/// SIDE EFFECT -- a write builds one, and `-tail` builds one because it has to
/// read the whole file anyway -- so somebody who only ever runs `-mid` on a
/// large file never gets one at all. `-mid` stops early by design and building
/// there would cancel that out, which is correct per operation but leaves the
/// user no way to ask for one.
/// 依需求建立 sidecar。少了它，索引只會以「副作用」的方式出現——寫入時建一個、
/// `-tail` 因為本來就要讀完整個檔案而建一個——於是只用 `-mid` 讀大檔的人根本不會
/// 得到索引。`-mid` 的設計就是提前停止，在那裡建索引會抵銷掉它：就單一操作而言正確，
/// 但使用者因此無從要求。
///
/// The rule this must not break: the index stays an OPTIMISATION and never a
/// precondition. So this changes no output, and a directory it cannot write to
/// is a warning, not a failure.
/// 不可破壞的規則：索引維持是最佳化，永遠不是必要條件。因此本操作不改變任何輸出，
/// 目錄不可寫時只警告、不失敗。
func runBuildIndex(_ o: Options) throws {
    guard let path = o.input else {
        throw fault("--build-index needs -i FILE", "--build-index 需要 -i FILE")
    }
    let plan = try openInput(o)
    defer { plan.source.close() }
    try checkTornAppend(path: path, format: plan.format, truncatePartial: o.truncatePartial)

    var headers: [Record] = []
    var expectedFields = 0
    var pendingError: Error?
    let builder = IndexBuilder(isCSV2: plan.format == .csv2)

    let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
        do {
            if headers.count < plan.headerRows {
                headers.append(rec)
                if headers.count == plan.headerRows {
                    try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath)
                    expectedFields = headers[0].count
                    builder.headerEnded(at: UInt64(rec.offset + 1))
                }
                return true
            }
            var r = rec
            r.number = rec.number - plan.headerRows
            // With no header rows the first RECORD sets the width. `.lines`
            // has none by definition, and a headed file has already set this
            // from its header, so this is inert there.
            // 沒有標頭列時，由第一筆**紀錄**決定寬度。`.lines` 依定義沒有標頭，而有標頭的檔案
            // 早就從它的標頭設過這個值，因此這一行在那裡是惰性的。
            if expectedFields == 0 { expectedFields = r.count }
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))",
                                headerRows: plan.headerRows)
            // A record that itself spans lines means a record number is no
            // longer a line number, and the index stores bytes rather than
            // lines -- so the seek path must refuse to use this index. Recorded
            // here so the flag in the header is right.
            //
            // Ask the record itself, not `rec.line != r.line`: `r` is `rec`
            // with only `number` changed, so that comparison is never true, and
            // a wrong flag makes the parallel path count lines as records.
            // 自身跨行的紀錄會讓紀錄號不再等於行號，而索引存的是位元組而非行號
            // ——因此 seek 路徑必須拒絕使用這份索引。在此記錄，讓檔頭的旗標正確。
            //
            // 要問紀錄本身，不是 `rec.line != r.line`：`r` 是只改了 `number` 的 `rec`，那個比較
            // 永遠不為真；而旗標錯了，平行路徑就會把行當成紀錄來數。
            builder.add(record: r.number, at: UInt64(r.offset), line: UInt64(r.line),
                        spansLines: recordSpansLines(r, format: plan.format))
            return true
        } catch {
            pendingError = error
            return false
        }
    }

    while !parser.stopped, let chunk = plan.source.next() { try parser.feed(chunk) }
    if !parser.stopped { try parser.finish() }
    if let e = pendingError { throw e }
    guard headers.count == plan.headerRows else {
        throw fault("\(path): expected \(plan.headerRows) header row(s), found \(headers.count)",
                    "\(path)：預期 \(plan.headerRows) 列標頭，實際只有 \(headers.count) 列")
    }
    guard let idx = builder.finish(dataPath: path) else {
        throw fault("cannot stat \(path)", "無法取得 \(path) 的狀態")
    }
    Metrics.report(bytesRead: plan.source.bytesRead, fileSize: Int(idx.stamp.size))
    let sink = ByteSink(stdout: 1 << 13)
    if idx.save(dataPath: path) {
        sink.write("index built: \(idx.records) records, stride \(idx.stride), \(idx.offsets.count) grid points\n")
    } else {
        // Not a failure: the index is an optimisation, so being unable to write
        // one leaves everything else exactly as it was.
        // 不算失敗：索引是最佳化，寫不出來也不影響其餘一切。
        sink.write("index not written (directory not writable); nothing else changed\n")
    }
    try sink.close()
}

/// O(n), and the only thing here that is a proof rather than a heuristic.
/// Offered because the O(1) validation deliberately is not one.
/// O(n)，也是此處唯一構成證明而非啟發式的東西。之所以提供它，正因為 O(1) 的
/// 驗證刻意不是證明。
/// `-count`: how many DATA records the file has, on one line.
///
/// A scrolling front end needs the total before it draws anything: `List` and
/// `LazyVStack` size their scroll range from it, and a model that discovers
/// the total while scrolling makes the scrollbar move under the user's hand.
///
/// Rejected: a `total` field in `--json`'s meta line. That number is only known when an index exists, so the field
/// would come and go -- and a field that is sometimes there recreates the
/// ambiguity this tool exists to remove, because a caller that does not find
/// it cannot tell "this file is empty" from "this run had no index". A verb
/// always answers; it is only sometimes slower.
///
/// `-count`：這個檔案有幾筆**資料**紀錄，一行。
///
/// 一個會捲動的前端在畫任何東西之前就需要總數：`List` 與 `LazyVStack` 用它決定捲動範圍，
/// 而一個「邊捲邊發現總數」的模型會讓捲軸在使用者手下移動。
///
/// 被否決的：在 `--json` 的 meta 行加一個 `total` 欄位。那個數字只有在索引
/// 存在時才知道，因此那個欄位會**時有時無**——而一個有時候出現的欄位，重新製造了這個工具存在
/// 所要消滅的那種歧義：讀不到它的呼叫端，分不出「這個檔案是空的」與「這次執行沒有索引」。
/// 一個動詞一定會回答，只是有時候比較慢。
func runCount(_ o: Options) throws {
    guard let path = o.input else {
        throw fault("-count needs -i FILE", "-count 需要 -i FILE")
    }

    // O(1) when a usable index is beside the file. `CSVIndex.load` is the same
    // gate every other reader goes through, so a stale or unusable sidecar is
    // discarded here exactly as it is there -- and the scan below then gives
    // the same answer, which is what T80 asserts.
    // 檔案旁有一份可用索引時是 O(1)。`CSVIndex.load` 就是其他每一個讀取者走的同一道關口，
    // 因此一份過期或不可用的 sidecar 在這裡被捨棄的方式與那裡完全相同——而底下的掃描接著會給出
    // 同一個答案，那正是 T80 斷言的東西。
    if !o.noIndex, let idx = CSVIndex.load(dataPath: path) {
        // Say so. README calls -debug the only window onto whether an index was
        // used, and `-count`'s whole claim is O(1)-via-index, so it must print
        // `index hit` too. The miss side is already covered: a stale sidecar
        // reports itself through CSVIndex.load. OZ.
        // 把它說出來。README 說 -debug 是「索引有沒有被用到」的唯一窗口，而 `-count` 的全部賣點
        // 就是有索引時 O(1)，所以它也必須印出 `index hit`。沒用到的那一半已經有了：過期的 sidecar
        // 會透過 CSVIndex.load 自己回報。OZ。
        Logger.shared.debug("index hit: \(idx.records) records from the sidecar; the file was not read")
        Platform.writeStdout("\(idx.records)\n")
        return
    }

    // O(n): read it. No sidecar is written on the way.
    //
    // `planIndex` writes a sidecar only when the run wants random access
    // (`-mid` or `-tail`), and `-count` wants neither. Writing one anyway would
    // give a question-answering verb a side effect on disk that no rule asks
    // for; `--build-index` exists to ask for it explicitly.
    //
    // O(n)：讀過去。過程中不寫 sidecar。
    //
    // `planIndex` 只在這次執行**需要隨機存取**（`-mid` 或 `-tail`）時才寫 sidecar，而 `-count`
    // 兩者都不要。照樣寫一份，等於給一個「回答問題」的動詞一個沒有規則要求的磁碟副作用；要的話，
    // `--build-index` 就是用來明說的。
    let plan = try openInput(o)
    defer { plan.source.close() }
    try checkTornAppend(path: path, format: plan.format, truncatePartial: o.truncatePartial)

    var headers: [Record] = []
    var n = 0
    var pendingError: Error?
    let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
        if headers.count < plan.headerRows {
            headers.append(rec)
            if headers.count == plan.headerRows {
                do { try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath) }
                catch { pendingError = error; return false }
            }
            return true
        }
        n = rec.number - plan.headerRows
        return true
    }
    while let c = plan.source.next() { try parser.feed(c) }
    try parser.finish()
    if let e = pendingError { throw e }

    // A file with only a header row answers 0, not an error. The count of an
    // empty file is a fact; asking for a record IN it is what is an error.
    // 只有標頭列的檔案回答 0，不是錯誤。一個空檔案的筆數是一件事實；向它「要一筆紀錄」才是錯誤。
    Platform.writeStdout("\(n)\n")
}

/// Validate what a pasted address CLAIMED, before the verb acts on it.
///
/// `--physical` and `--a1` print a location beside every address, and that
/// address may be pasted back. The decoration is a CLAIM about the file as it
/// was when the address was printed, and if the file has changed since,
/// acting on that address is exactly the edit the caller does not want. An
/// address that validates itself is worth more than one that merely remembers.
///
/// 在動詞對一個貼回來的位址動作**之前**，先驗證它宣稱了什麼。
///
/// `--physical` 與 `--a1` 會在每個位址旁印出一段位置，而那個位址可以被貼回來。那段裝飾是一個
/// **關於「位址被印出來的當下那個檔案」的宣稱**，若檔案之後變了，
/// 照那個位址動手正是呼叫者最不想要的那一次編輯。**一個會自我驗證的位址，比一個只是記得的
/// 位址有價值。**
///
/// One place, before the dispatch, so every verb that takes a cell address is
/// covered by the same check: `-get`, `-update`, `-delete -cell` and
/// `--search-cell`. Putting it inside the emitters would have covered the read
/// path and left the edit path to grow its own copy.
/// 放在分派**之前**的單一位置，讓每一個接受儲存格位址的動詞都被同一道檢查涵蓋：`-get`、
/// `-update`、`-delete -cell` 與 `--search-cell`。放進 emitter 裡的話，只會涵蓋讀取路徑，而編輯
/// 路徑會長出它自己的一份。
func validateLocationClaim(_ o: Options) throws {
    guard let lc = o.locationClaim else { return }
    // EVERY claim, not the first. `--physical --a1` prints both decorations on
    // one address, and checking one of two would be a guard that passes on the
    // half it did not look at.
    // **每一個**宣稱，不是第一個。`--physical --a1` 會在同一個位址上印出兩段裝飾，而只檢查其中
    // 一個，等於一道「在它沒看的那一半上放行」的守衛。
    for claim in lc.claims {
        try validateOneClaim(o, lc: lc, claim: claim)
    }
}

private func validateOneClaim(_ o: Options,
                              lc: (record: Int, column: String, claims: [LocationClaim], flag: String),
                              claim: LocationClaim) throws {

    // A numeric column in the address can be compared with `[A2]`'s letter. A
    // NAMED column cannot, without resolving it against the headers, and the
    // printed form is always numeric -- `--a1` prints `1:1 [A2]` -- so a named
    // column with a letter claim is hand-written. The row half still applies.
    // 位址裡的數字欄可以與 `[A2]` 的字母比對。**具名**的欄不行，除非拿標頭去解析它；而印出來
    // 的形式一定是數字（`--a1` 印的是 `1:1 [A2]`），所以「具名欄 + 字母宣稱」是手寫的。列的
    // 那一半仍然適用。
    func checkColumn(_ resolvedZeroBased: Int?) throws {
        guard let want = claim.column, let got = resolvedZeroBased else { return }
        if want != got {
            throw fault(
                "\(lc.flag): the address names column \(got + 1) and \(claim.text) says column \(a1Column(want)); they cannot both be right",
                "\(lc.flag)：位址指的是第 \(got + 1) 欄，而 \(claim.text) 說的是第 \(a1Column(want)) 欄；兩者不可能同時正確")
        }
    }

    switch claim.kind {
    case .spreadsheetRow:
        // Arithmetic, not a scan: the spreadsheet row is the record number
        // plus the header rows, and both are known without reading a record.
        // That is also why this half works on stdin.
        // 這是算術，不是掃描：試算表列號等於紀錄號加上標頭列數，而兩者都不必讀任何一筆紀錄
        // 就知道。那也是為什麼這一半在 stdin 上仍然成立。
        let plan = try openInput(o)
        defer { plan.source.close() }
        let want = lc.record + plan.headerRows
        if claim.row != want {
            throw fault(
                "\(lc.flag): \(claim.text) says record \(lc.record) is spreadsheet row \(claim.row), but in this file it is row \(want); the file is not the one that address was printed from",
                "\(lc.flag)：\(claim.text) 說第 \(lc.record) 筆在試算表的第 \(claim.row) 列，而在這個檔案裡它是第 \(want) 列；這不是那個位址被印出來時的那個檔案")
        }
        try checkColumn(Int(lc.column).map { $0 - 1 })

    case .physicalLine:
        // A scan, and deliberately NOT through the index. `planIndex` seeks to
        // a byte offset, and every newline skipped over on the way was never
        // counted -- so the line number after a seek is not the file's. The
        // index records record boundaries, not layout, and a path that cannot
        // count lines cannot validate a claim about layout. The cost falls only
        // on a decorated address.
        // 一次掃描，而且**刻意不走索引**。`planIndex` 會 seek 到一個位元組位移，而途中被跳過的
        // 每一個換行都沒有被數——所以 seek 之後的行號不是這個檔案的行號。索引記的是紀錄邊界，
        // 不是排版；一條數不了行的路徑驗證不了關於排版的宣稱。這個成本
        // 只落在「帶裝飾的那一次呼叫」上。
        guard o.input != nil else {
            throw fault(
                "\(lc.flag): \(claim.text) is a claim about physical lines, which cannot be checked on stdin because it cannot be read twice",
                "\(lc.flag)：\(claim.text) 是一個關於實體行號的宣稱，而 stdin 無法被讀第二次，因此檢查不了")
        }
        let plan = try openInput(o)
        defer { plan.source.close() }
        var headers: [Record] = []
        var found: Int?
        var lastRecord = 0
        let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
            if headers.count < plan.headerRows { headers.append(rec); return true }
            let n = rec.number - plan.headerRows
            lastRecord = n
            if n == lc.record { found = rec.line; return false }
            return true
        }
        while found == nil, let c = plan.source.next() { try parser.feed(c) }
        if found == nil { try? parser.finish() }
        guard let line = found else {
            // Not this check's job to complain that the record is absent: the
            // verb itself says that, and better. Say nothing and let it.
            // 「那一筆不存在」不是這道檢查該抱怨的事：動詞自己會說，而且說得更好。這裡閉嘴，
            // 讓它去說。
            _ = lastRecord
            return
        }
        if line != claim.row {
            throw fault(
                "\(lc.flag): \(claim.text) says record \(lc.record) starts on physical line \(claim.row), but in this file it starts on line \(line); the file has changed since that address was printed",
                "\(lc.flag)：\(claim.text) 說第 \(lc.record) 筆從實體第 \(claim.row) 行開始，而在這個檔案裡它從第 \(line) 行開始；這個檔案在那個位址被印出來之後變過了")
        }
        try checkColumn(Int(lc.column).map { $0 - 1 })
    }
}

func runVerifyIndex(_ o: Options) throws {
    guard let path = o.input else {
        throw fault("--verify-index needs -i FILE", "--verify-index 需要 -i FILE")
    }
    let plan = try openInput(o)
    defer { plan.source.close() }
    guard let idx = CSVIndex.load(dataPath: path) else {
        // Separate "absent" from "present and unusable", as everywhere else in
        // this tool: --verify-index's whole job is to report on a sidecar, so
        // "no usable index" must not be said while one sits right there.
        // 與這個工具的其他地方一樣，把「不存在」與「存在但不能用」分開：--verify-index 的整份
        // 工作就是回報 sidecar，不該在 sidecar 就躺在那裡時說「沒有可用的索引」。
        let sidecar = CSVIndex.path(for: path)
        if FileManager.default.fileExists(atPath: sidecar) {
            let why = CSVIndex.lastDiscardReason ?? ("reason not recorded", "沒有記錄到理由")
            throw fault(
                "index \(sidecar) exists but cannot be used: \(why.en). It was not compared against the data; --build-index replaces it",
                "索引 \(sidecar) 存在但無法使用：\(why.zh)。它並未與資料比對過；--build-index 可以重建它")
        }
        throw fault("no index beside \(path); --build-index creates one",
                    "\(path) 旁沒有索引；--build-index 可以建立一個")
    }
    var headers: [Record] = []
    var n = 0
    var mismatches: [String] = []
    var spanningRecord: Int? = nil
    let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
        if headers.count < plan.headerRows { headers.append(rec); return true }
        n = rec.number - plan.headerRows
        if (n - 1) % idx.stride == 0 {
            let g = (n - 1) / idx.stride
            if g < idx.offsets.count && idx.offsets[g] != UInt64(rec.offset) {
                mismatches.append("record \(n): index says byte \(idx.offsets[g]), actual \(rec.offset)")
            }
            // The line at each grid point is checked because the index STORES
            // one (v4); a proof that skips a stored claim lets a wrong line
            // pass as "index OK". Same class as T79: a sidecar asserting
            // something nothing re-derived. A wrong line is quieter than a
            // wrong offset, because it surfaces only in `--json`, `--physical`
            // and an `@L` address.
            // 每個格點的行號會被檢查，因為索引「存了」一個（v4）；跳過一項已存宣稱的證明，會讓錯的
            // 行號以「index OK」通過。與 T79 同類：一份 sidecar 宣稱了一件沒有任何東西重新推導過的
            // 事。錯的行號比錯的偏移量更安靜，因為它只在 `--json`、`--physical` 與 `@L` 位址上露臉。
            if g < idx.lines.count && idx.lines[g] != UInt64(rec.line) {
                mismatches.append("record \(n): index says line \(idx.lines[g]), actual \(rec.line)")
            }
        }
        if spanningRecord == nil, recordSpansLines(rec, format: plan.format) { spanningRecord = n }
        return true
    }
    while let c = plan.source.next() { try parser.feed(c) }
    try parser.finish()
    if Int(idx.records) != n {
        mismatches.append("record count: index says \(idx.records), actual \(n)")
    }
    // Offsets and count alone survive the failure that matters: put a newline
    // inside a quoted field and every record still starts where the index
    // says, and there are still as many. What changes is the header's
    // no_embedded_newlines claim -- the one the parallel path consumes to
    // decide that a line is a record -- so it is re-derived here.
    //
    // Only the dangerous direction is a mismatch. An index that says a file
    // spans lines when it does not is merely pessimistic: it gives up a fast
    // path and returns the same answer. Failing on that would send people to
    // rebuild a sidecar that was never going to hurt them.
    //
    // 只看偏移量與筆數，在「真正要命的那個失敗」下會照樣通過：在引號欄位裡放一個換行，每一筆
    // 仍然從索引所說的那個位元組開始，筆數也仍然一樣。變的是檔頭的 no_embedded_newlines 宣稱
    // ——平行路徑正是用它來斷定「一行就是一筆」——因此在這裡重新推導它。
    //
    // 只有危險的那個方向算不符。索引說檔案跨行而其實沒有，只是悲觀：它放棄一條快路徑，
    // 答案不變。為那種情況失敗，等於叫人去重建一份本來就不會害到他的 sidecar。
    if idx.noEmbeddedNewlines, let bad = spanningRecord {
        mismatches.append("no_embedded_newlines: index says the file has none, "
                        + "but record \(bad) spans lines")
    }
    Metrics.report(bytesRead: plan.source.bytesRead,
                   fileSize: Int(FileStamp.of(path: path)?.size ?? 0))
    let sink = ByteSink(stdout: 1 << 13)
    if mismatches.isEmpty {
        sink.write("index OK: \(n) records, stride \(idx.stride), \(idx.offsets.count) grid points\n")
        try sink.close()
        return
    }
    for m in mismatches { sink.write("index MISMATCH: \(m)\n") }
    try sink.close()
    throw fault("index beside \(path) does not describe the file",
                "\(path) 旁的索引與檔案不符")
}

func runSelect(_ o: Options) throws {
    // Say which path was taken, always -- including when it is the ordinary
    // one. Reporting only the interesting case makes silence ambiguous, and
    // "parallel produced identical output" is indistinguishable from "parallel
    // never ran" precisely when the output is identical.
    // 一律說出走的是哪一條路——包括走的是普通那一條時。只回報「有趣的那一種」會讓沉默變得
    // 有歧義；而「平行產生了相同的輸出」與「平行根本沒跑」，恰恰在輸出相同時無法區分。
    // `?? .lines`, not `?? .csv`. `Format.from(path:)` answers only for the two
    // DECLARING suffixes and returns nil for everything else -- and everything
    // else is read line by line. A `.csv` default tells the parallel path that
    // a `.txt` is a CSV, and a suffix-less file with an index then reaches a
    // splitter built for CSV records and dies on SIGTRAP; the format guard in
    // parallelDeclineReason cannot catch a format that is already wrong. OF.
    //
    // The two `checkTornAppend` calls take the same default. They return at
    // once unless the format is `.csv2`, so `.csv` would not hurt them, but
    // the default is kept the same everywhere: `.csv` is a false statement
    // about what a suffix-less file is.
    //
    // `?? .lines`，不是 `?? .csv`。`Format.from(path:)` 只為那兩個**會宣告的**副檔名作答，其餘一律
    // 回傳 nil——而那個「其餘」是逐行讀的。預設成 `.csv` 等於告訴平行路徑「一個 .txt 是 CSV」，
    // 一個有索引、無宣告副檔名的檔案就會抵達「為 CSV 紀錄而建的切分器」，並以 SIGTRAP 死去；
    // parallelDeclineReason 裡的格式守衛攔不住一個早已錯了的格式。OF。
    //
    // 底下兩個 `checkTornAppend` 用同一個預設。它們在格式不是 `.csv2` 時立刻返回，所以 `.csv`
    // 傷不到它們，但預設在每一處都保持一致：`.csv` 是一句關於「無宣告副檔名的檔案是什麼」的假話。
    if let p = o.input, let why = parallelDeclineReason(o, format: Format.from(path: p) ?? .lines) {
        Logger.shared.debug("single-threaded: \(why)")
    } else if o.input == nil {
        Logger.shared.debug("single-threaded: stdin")
    }
    if let p = o.input, canRunParallelSearch(o, format: Format.from(path: p) ?? .lines) {
        try checkTornAppend(path: p, format: Format.from(path: p) ?? .lines,
                            truncatePartial: o.truncatePartial)
        do {
            try runParallelSearch(o)
            return
        } catch let e as CSV2Error where e.message.hasPrefix("a chunk boundary fell inside") {
            // The premise was false: the format or the index said one record
            // per line and a chunk boundary landed inside a quoted field. This
            // tool's answer to a premise that turns out false is the same
            // everywhere -- discard it and scan -- so the run continues below,
            // single-threaded, and produces whatever the real diagnosis is.
            //
            // Falling back rather than reporting is what makes the two paths
            // agree. Reporting from here would give the same file a
            // raw-newline error at one chunk size and an unclosed-quote error
            // at another, with a wrong record number.
            //
            // 前提是假的：格式或索引說「一筆一行」，而某個區塊邊界落在了引號欄位中間。
            // 這個工具對「前提被推翻」的回答在每一處都相同——丟掉它、改用掃描——因此這次
            // 執行會往下繼續，以單執行緒進行，並產生真正的診斷。
            //
            // 選擇「退回」而不是「回報」，正是讓兩條路徑說法一致的原因。從這裡回報的話，同一個
            // 檔案會在某個 chunk 大小下得到「裸換行」的錯誤、在另一個大小下得到「引號未關閉」的
            // 錯誤，紀錄號也是錯的。
            Logger.shared.debug(
                "single-threaded: a chunk boundary fell inside a quoted field, so the one-record-per-line premise was false; re-reading without it")
        }
    }
    if let p = o.input {
        try checkTornAppend(path: p, format: Format.from(path: p) ?? .lines,
                            truncatePartial: o.truncatePartial)
    }

    let searching = o.contains != nil
    let reportMode = searching && !o.filter && !o.markdown
    let emitsRecords = !reportMode
    try checkOutputPromise(o, emitsRecords: emitsRecords)

    let maxBuffer = Int(ProcessInfo.processInfo.environment["CSV2_MAX_BUFFER_RECORDS"] ?? "") ?? 1_000_000
    if let n = o.tail, n > maxBuffer {
        // `-tail N` and `-B N` size is chosen by the user, and the guest has
        // 2-4 GiB. Doing as told and then dying is not an option; refusing is.
        // `-tail N` 與 `-B N` 的記憶體由使用者控制，而 guest 只有 2–4 GiB。
        // 照做然後死掉不是選項，拒絕才是。
        throw fault("-tail \(n) exceeds the buffered-record limit (\(maxBuffer)); raise CSV2_MAX_BUFFER_RECORDS if you really mean it",
                    "-tail \(n) 超過可緩衝的紀錄上限（\(maxBuffer)）；若確實需要請調高 CSV2_MAX_BUFFER_RECORDS")
    }
    if o.before > maxBuffer {
        // The variable name belongs in EVERY message that reports this limit:
        // the README says the message "names the request, the limit and the
        // variable" for both flags. And the flag quoted is the one the
        // operator typed: `-C 6` sets `before` too, and must not be reported
        // as `-B 6`.
        // 變數名稱屬於「每一則回報這個上限的訊息」：README 說訊息會「指出請求、上限與變數名稱」，
        // 而那一句同時涵蓋兩個旗標。引用的旗標則是使用者實際打的那個：`-C 6` 同樣會設定
        // `before`，不該被回報成 `-B 6`。
        throw fault("\(o.beforeFlag) \(o.before) exceeds the buffered-record limit (\(maxBuffer)); raise CSV2_MAX_BUFFER_RECORDS if you really mean it",
                    "\(o.beforeFlag) \(o.before) 超過可緩衝的紀錄上限（\(maxBuffer)）；若確實需要請調高 CSV2_MAX_BUFFER_RECORDS")
    }

    var lower = 1
    var upper = Int.max
    if let (a, b) = o.mid { lower = a; upper = b ?? Int.max }
    // -get is -mid r,r with a different emitter: same seek, same stop, same
    // index use. A separate implementation would have its own off-by-one to
    // get wrong.
    // -get 就是「-mid r,r 換一個輸出器」：同樣的 seek、同樣的停止點、同樣使用索引。
    // 另外實作一份，只會讓它多出一個屬於自己的差一錯誤。
    if let (r, _) = o.getCell { lower = r; upper = r }
    if let n = o.head { upper = min(upper, n) }

    // ONE open. `planIndex` only reads the plan's format and header count, and
    // opening a second source to hand it is free on a regular file and fatal
    // on a FIFO: the first open drains the pipe, the second waits for a writer
    // that has already gone, and a three-line stream is reported as an empty
    // file.
    // 只開一次。`planIndex` 用到的只是這份 plan 的格式與標頭列數，而「為了交給它而多開一個
    // 來源」在一般檔案上是免費的、在 FIFO 上是致命的：第一次開啟把管線抽乾，第二次則在等一個
    // 早已離開的寫入端，一條有三行的串流會被回報成空檔案。
    var plan = try openInput(o)
    var ip = planIndex(o, plan: plan, lower: lower, upper: upper)
    // Kept so the index can be given up AFTER the plan has already rewritten
    // them. `-tail N` becomes a record range using the index's own record
    // count, and dropping the index without putting these back would leave the
    // run selecting a window computed from the thing it just stopped trusting.
    // 留著，是為了「計畫已經改寫過它們之後」還能放棄索引。`-tail N` 會用索引自己的紀錄總數
    // 變成一個紀錄範圍，而放棄索引時若不把這些放回去，這次執行就會照著「一個由它剛剛決定
    // 不再信任的東西算出來的視窗」去選取。
    let preIndexLower = lower, preIndexUpper = upper
    var tailN = o.tail
    if ip.resumeOffset != nil, let l = ip.lower, let u = ip.upper {
        // The index turned `-tail N` into a range, so the ring buffer is no
        // longer needed: this is the seek the plan describes.
        // 索引把 `-tail N` 變成了一個範圍，於是不再需要環狀緩衝：這就是計畫
        // 所描述的那個 seek。
        lower = l
        upper = u
        tailN = nil
    }

    var headers: [Record] = []
    if let off = ip.resumeOffset, let path = o.input {
        headers = try readHeaderRows(path: path, format: plan.format, want: plan.headerRows)
        if recordBeginsAt(path: path, offset: off, format: plan.format,
                          expectedFields: headers.first?.count ?? 0,
                          truncatePartial: o.truncatePartial) {
            plan.source.close()
            plan.source = try ByteSource(path: path, chunkSize: 1 << 16, startAt: off)
        } else {
            // Nothing has been emitted yet, so giving up here costs a scan and
            // nothing else. Later would be a different matter, which is why
            // the check is here.
            // 此時還沒有輸出過任何東西，因此在這裡放棄，代價就只是一次掃描。晚一點放棄就是
            // 另一回事了——這正是這個檢查放在這裡的原因。
            Logger.shared.log(.info, "index for \(path) points at byte \(off), which is not the start of a record; ignoring it and scanning")
            ip = IndexPlan()
            headers = []
            lower = preIndexLower
            upper = preIndexUpper
            tailN = o.tail
        }
    }
    defer { plan.source.close() }

    var pendingError: Error?
    // Before the sink, because the sink is what replaces the file.
    //
    // This is the write path `-encrypt --in-place` runs through. Without the
    // backup here, `--backup` would be accepted, exit 0, overwrite the
    // plaintext and leave no `.bak` -- on the one path where losing the
    // original cannot be undone. LU.
    //
    // 放在 sink 之前，因為 sink 正是「取代那個檔案」的東西。
    //
    // `-encrypt --in-place` 走的就是這條寫入路徑。這裡少了備份，`--backup` 會被接受、以 0 結束、
    // 覆寫明文，而旁邊沒有 `.bak`——**偏偏在那條「原檔一旦失去就無法復原」的路上**。LU。
    var backupToUndo: String?
    if o.backup, o.inPlace, let path = o.input {
        try makeInPlaceBackup(path)
        backupToUndo = path + ".bak"
    }
    let sink = try makeSink(o)
    var aborted = true
    // The backup goes with the sink.
    //
    // It is written BEFORE the edit, which it has to be -- it exists to hold
    // the bytes the edit is about to replace. But a failed edit leaves the
    // input byte-identical, so the `.bak` then holds a copy of a file nothing
    // touched, and `makeInPlaceBackup` refuses to overwrite an existing one:
    // left behind, ONE failure would block every future `--backup` edit on
    // that path.
    //
    // This is the same shape as T28d, which asserts that a failed in-place edit
    // leaves no temp file beside the input. A stale `.bak` is that debris under
    // a different name. OB.
    //
    // 備份與 sink 同進退。
    //
    // 它寫在編輯**之前**，那是必然的——它存在的理由就是保存「那次編輯即將取代的位元組」。但一次
    // 失敗的編輯會讓輸入逐位元不變，於是那個 `.bak` 保存的是一份「沒有任何東西動過的檔案」的複本；
    // 而 `makeInPlaceBackup` 拒絕覆寫既有的備份：留著它，**一次失敗就會封死那個路徑上未來的
    // 每一次 `--backup` 編輯**。
    //
    // 這與 T28d 是同一個形狀——那個案例斷言「一次失敗的就地編輯不會在輸入旁邊留下暫存檔」。
    // 一個過期的 `.bak` 就是那份殘骸換了個名字。OB。
    defer {
        if aborted {
            sink.abort()
            if let b = backupToUndo { try? FileManager.default.removeItem(atPath: b) }
        }
    }

    let needle: [UInt8] = o.contains.map {
        o.normalize ? normalizedBytes([UInt8]($0.utf8)) : [UInt8]($0.utf8)
    } ?? []

    var emitter: RecordEmitter
    if let (_, col) = o.getCell {
        emitter = CellEmitter(sink: sink, column: col)
    } else if o.json {
        emitter = JSONEmitter(sink: sink, reportMode: reportMode)
    } else if o.markdown {
        emitter = MarkdownEmitter(sink: sink, pretty: o.pretty,
                                  layout: o.mdStyle == .preserve ? plan.mdLayout : nil)
    } else if reportMode {
        emitter = ReportEmitter(sink: sink, needle: needle)
    } else {
        emitter = CSVEmitter(sink: sink)
    }

    var ctx: EmitContext?
    var transform: CellTransform = .none
    var expectedFields = 0
    var ring: [Record] = []
    var afterRemaining = 0
    var lastEmitted = 0
    var seen = 0
    var matchedCount = 0
    // An actual ring buffer, not an Array with `removeFirst()`: that shifts
    // every remaining element, so `-tail N` would cost O(records x N) and run
    // slower than reading the whole file, while every answer stayed correct.
    // Only timing shows the difference. Round 85.
    //
    // 一個真正的環狀緩衝，而不是帶 `removeFirst()` 的 Array：那會搬移其餘每一個元素，讓
    // `-tail N` 的成本變成 O(紀錄數 × N)，比讀完整個檔案還慢，而每一個答案仍然是對的。
    // 只有計時看得出差別。第 85 回合。
    var tailRing: [Record] = []
    var tailHead = 0
    var tailFilled = 0
    let builder = ip.builder
    var scopedColumn: Int?
    var scopedRecord: Int?
    var scopedRecordSeen = false

    func prepareSearchScope() throws {
        guard let scope = o.searchScope else { return }
        switch scope {
        case .cell(let record, let column):
            scopedRecord = record
            scopedColumn = try resolveSearchColumn(column, headers: headers,
                                                   path: plan.describedPath)
        case .row(let record):
            scopedRecord = record
        case .column(let column):
            scopedColumn = try resolveSearchColumn(column, headers: headers,
                                                   path: plan.describedPath)
        }
    }

    func matchesIn(_ r: Record) -> [Int] {
        guard searching else { return [] }
        var hits: [Int] = []
        for (i, f) in r.fields.enumerated() {
            switch o.searchScope {
            case .cell:
                guard r.headerRow == nil, scopedColumn == i else { continue }
                if let scopedRecord, r.number != scopedRecord { continue }
            case .column:
                guard scopedColumn == i else { continue }
                if r.headerRow != nil && !o.includeHeaders { continue }
            case .row:
                guard r.headerRow == nil, scopedRecord == r.number else { continue }
            case nil:
                break
            }
            let hay = o.normalize ? normalizedBytes(f.value) : f.value
            if bytesContain(hay, needle) { hits.append(i) }
        }
        return hits
    }

    /// TRACE for a record that is NOT emitted. Without it, `-debug=trace`
    /// logs only the records that came out -- the half the output already
    /// shows. The question it answers is "why is record N not in my result",
    /// and for that the interesting record is precisely the one with no line.
    ///
    /// It also keeps silence unambiguous: without it, "read and rejected" and
    /// "never reached, because the read stopped first" look identical. DD.
    ///
    /// 給「沒有被輸出」的紀錄用的 TRACE。少了它，`-debug=trace` 只會記錄有輸出的那些
    /// ——而那一半輸出本身就看得到。它該回答的問題是「為什麼第 N 筆不在我的結果裡」，
    /// 而對那個問題來說，有意思的紀錄恰恰是「沒有那一行」的那一筆。
    /// 它也讓沉默不再有歧義：少了它，「讀過但被排除」與「根本沒讀到，因為讀取先停了」看起來
    /// 完全一樣。DD。
    func traceSkip(_ r: Record, _ why: String) {
        Logger.shared.log(.trace, "select: record \(r.number) line \(r.line) not emitted: \(why)")
    }

    // Counted for the audit trail's outcome line. `-hash`, `-encrypt` and
    // `-decrypt` rewrite a file through the SELECT path, not the edit path, so
    // this path must write that line too -- the README calls it "the one to
    // look for when asking whether an edit landed", and these are the edits
    // whose result cannot be undone.
    // 為了稽核軌跡的那一行「結果」而計數。`-hash`、`-encrypt`、`-decrypt` 走「選取」路徑而不是
    // 編輯路徑來重寫檔案，所以這條路徑也必須寫那一行——README 稱它為「想知道一次編輯有沒有
    // 落地時該找的那一行」，而這些正是結果無法還原的編輯。
    var emittedCount = 0

    func emitRecord(_ r: Record, matches: [Int]) throws {
        guard let c = ctx else { return }
        // TRACE is per-record: the question it answers is "why was record N not
        // in my output", which DEBUG would drown.
        // TRACE 是逐筆的：它要回答的是「為什麼第 N 筆不在我的輸出裡」，而那個問題
        // 會被 DEBUG 的量淹沒。
        Logger.shared.log(.trace, "select: record \(r.number) line \(r.line) emitted\(matches.isEmpty ? "" : ", matched fields \(matches.map { $0 + 1 })")")
        if lastEmitted != 0 && r.number > lastEmitted + 1 && (o.before > 0 || o.after > 0) {
            try emitter.gap(c)
        }
        try emitter.emit(r, matches: matches, ctx: c)
        lastEmitted = r.number
        emittedCount += 1
    }

    func headersComplete() throws {
        try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath)
        // Zero header rows is a real shape (`.lines`), and everything below
        // reads row 0; indexing it unguarded traps with SIGTRAP and no message
        // on either stream.
        // 零列標頭是一個真實的形狀（`.lines`），而底下的一切都會去讀第 0 列；不加防護地取它，會以
        // SIGTRAP 當掉，兩條輸出流上都沒有訊息。
        // Only the header-DERIVED work is skipped when there is no header row,
        // not the emitter setup below it. An early `return` here would read the
        // file and print nothing at rc=0 -- a silent success, worse than the
        // trap, which at least stops.
        // 沒有標頭列時，只跳過「由標頭推導」的那些工作，不跳過它下面的 emitter 設定。在這裡直接
        // `return` 會讓它讀完檔案卻什麼都不印，而且 rc=0——一次無聲的成功，比 trap 更糟：trap 至少
        // 會停下來。
        if let first = headers.first {
        expectedFields = first.count
        // Before buildTransform, so a column the file already marks is redacted even
                    // when this run performs no transform at all.
                    // 放在 buildTransform 之前，好讓「檔案已標記的欄位」即使在本次完全沒有
                    // 轉換時也會被遮蔽。
                    redactColumnsDeclaredByHeader(headers[0])
                    transform = try buildTransform(o, headers: headers)
        markHeaders(&headers, transform: transform)
        }
        ctx = EmitContext(
            format: plan.format, headers: headers, withHeader: o.withHeader,
            rownum: o.rownum, zh: o.zh, physical: o.physical,
            mdLineOffset: plan.mdLineOffset, a1: o.a1,
            jsonASCII: o.jsonASCII, enOnly: o.enOnly, preserveRaw: true,
            contextActive: o.after > 0 || o.before > 0)
        try prepareSearchScope()
        try emitter.begin(ctx!)
        if searching && o.includeHeaders {
            for (i, h) in headers.enumerated() {
                let hits = matchesIn(h)
                if !hits.isEmpty {
                    var hh = h
                    hh.number = 0
                    hh.headerRow = i
                    // Header hits are reported as 0a / 0b: the header does not
                    // take a data record number, so "record N" always means the
                    // Nth record of DATA.
                    // 標頭命中回報為 0a / 0b：標頭不佔用資料的編號，因此「第 N 筆」
                    // 永遠指第 N 筆資料。
                    Logger.shared.debug("match in header row 0\(i == 0 ? "a" : "b")")
                    try emitter.emit(hh, matches: hits, ctx: ctx!)
                }
            }
        }
    }

    let resuming = ip.resumeOffset != nil
    // ... or when there are no header rows to complete. With headerRows == 0
    // the callback below never enters its header branch, so headersComplete --
    // which also builds the emit context -- would never run, and the run
    // would read the whole file and emit nothing at rc=0. Same fix as the
    // resume path, shared rather than duplicated.
    // ……或是在「根本沒有標頭列可以完成」的時候。headerRows == 0 時，底下那個 callback 永遠不會
    // 進入它的標頭分支，於是 headersComplete——它同時也是建立 emit context 的地方——永遠不會被呼叫，
    // 而那次執行會讀完整個檔案、什麼都不輸出，rc=0。與恢復解析路徑共用同一個解法，而不是另寫一份。
    if resuming || plan.headerRows == 0 { try headersComplete() }

    let firstRecord = resuming ? ip.resumeRecord + plan.headerRows : 1
    // Taken from the grid point, not derived from the record number: deriving
    // it assumes one record per line, which a file with an embedded newline
    // breaks.
    // 取自那個格點，而不是由紀錄號推導：推導的前提是「一筆一行」，而含內嵌換行的檔案會打破它。
    let firstLine = resuming ? ip.resumeLine : 1

    let parser = RecordParser(format: plan.format,
                              firstRecordNumber: firstRecord,
                              firstOffset: Int(ip.resumeOffset ?? 0),
                              firstLine: firstLine,
                              truncatePartial: o.truncatePartial) { rec in
        do {
            if !resuming && headers.count < plan.headerRows {
                var h = rec
                h.number = 0
                headers.append(h)
                if headers.count == plan.headerRows {
                    try headersComplete()
                    builder?.headerEnded(at: UInt64(rec.offset + 1))
                }
                return true
            }

            var r = rec
            r.number = rec.number - plan.headerRows
            seen = r.number
            if scopedRecord == r.number { scopedRecordSeen = true }
            // With no header rows the first RECORD sets the width. `.lines`
            // has none by definition, and a headed file has already set this
            // from its header, so this is inert there.
            // 沒有標頭列時，由第一筆**紀錄**決定寬度。`.lines` 依定義沒有標頭，而有標頭的檔案
            // 早就從它的標頭設過這個值，因此這一行在那裡是惰性的。
            if expectedFields == 0 { expectedFields = r.count }
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))",
                                headerRows: plan.headerRows)
            // Not `false`. This is the index -tail builds as a side effect, and
            // a sidecar that lies about this property is worse than none --
            // the next -contains on the file acts on it.
            // 不是 `false`。這是 -tail 順手建出來的那份索引，而一份在這個性質上說謊的
            // sidecar 比沒有更糟——檔案上的下一次 -contains 會照著它做。
            builder?.add(record: r.number, at: UInt64(r.offset), line: UInt64(r.line),
                         spansLines: recordSpansLines(r, format: plan.format))
            if let h0 = headers.first { try applyTransform(transform, to: &r, header: h0) }

            if r.number < lower {
                if o.before > 0 {
                    ring.append(r)
                    if ring.count > o.before { ring.removeFirst() }
                    traceSkip(r, "before the requested range; held as -B context")
                } else {
                    traceSkip(r, "before the requested range")
                }
                return true
            }
            if r.number > upper {
                traceSkip(r, "past the requested range")
                // A builder means the whole file is being scanned to produce
                // the index, so stopping early would leave it incomplete.
                // 有 builder 表示正在為了產生索引而掃描全檔，提前停止會讓它不完整。
                if builder != nil { return true }
                return afterRemaining > 0 || tailN != nil ? true : false
            }

            if let n = tailN {
                // Write at the head and advance it, growing only until the ring
                // is full. `tailFilled` is separate from `tailRing.count`
                // because the two differ while the ring is still filling, and
                // the drain below needs the first of those two numbers.
                // 寫在 head 的位置再前進，只在環還沒滿之前成長。`tailFilled` 與 `tailRing.count`
                // 是兩個不同的數字——在環還在填滿的期間兩者不同——而底下的取出需要的是前者。
                if tailRing.count < n {
                    tailRing.append(r)
                } else {
                    tailRing[tailHead] = r
                }
                tailHead = (tailHead + 1) % n
                if tailFilled < n { tailFilled += 1 }
                traceSkip(r, "held in the -tail buffer; whether it is emitted is not known until EOF")
                return true
            }

            if searching {
                let hits = matchesIn(r)
                if !hits.isEmpty {
                    matchedCount += 1
                    if o.before > 0 {
                        for b in ring where b.number > lastEmitted {
                            try emitRecord(b, matches: [])
                        }
                        ring.removeAll(keepingCapacity: true)
                    }
                    try emitRecord(r, matches: hits)
                    afterRemaining = o.after
                } else if afterRemaining > 0 {
                    try emitRecord(r, matches: [])
                    afterRemaining -= 1
                } else if o.before > 0 {
                    ring.append(r)
                    if ring.count > o.before { ring.removeFirst() }
                    traceSkip(r, "no field matched; held as -B context")
                } else {
                    traceSkip(r, "no field matched")
                }
            } else {
                try emitRecord(r, matches: [])
            }
            // Returning false here stops the read. `-mid a,b` never touches a
            // byte past record b, which is what makes it the cheapest range
            // operation on a huge file.
            // 在此回傳 false 即停止讀取。`-mid a,b` 因此不會碰到 b 之後的任何
            // 一個位元組，那正是它在巨大檔案上最便宜的原因。
            if r.number >= upper && afterRemaining == 0 && tailN == nil && builder == nil {
                // Say that the read stops here. Otherwise every record after
                // this one is missing from the trace for a reason the trace
                // cannot express -- indistinguishable from having been read
                // and rejected.
                // 說出「讀取到此為止」。否則之後每一筆都會因為一個「trace 表達不出來的理由」
                // 而缺席，與「讀過但被排除」無法區分。
                Logger.shared.log(.trace, "select: stopping after record \(r.number); nothing past it is read")
                return false
            }
            return true
        } catch {
            pendingError = error
            return false
        }
    }

    while !parser.stopped, let chunk = plan.source.next() {
        try parser.feed(chunk)
    }
    if !parser.stopped { try parser.finish() }
    if let e = pendingError { throw e }

    if headers.count < plan.headerRows {
        throw fault("\(plan.describedPath): expected \(plan.headerRows) header row(s), found \(headers.count)",
                    "\(plan.describedPath)：預期 \(plan.headerRows) 列標頭，實際只有 \(headers.count) 列")
    }
    // A start past the end is an ERROR, not a warning. For a scrolling UI this
    // is the call made at wrap-around, and empty output is indistinguishable
    // from "these rows are genuinely empty" -- SwiftUI renders blank cells that
    // look exactly like data. `-get` past the end is an error for the same
    // reason (T70f). This includes a file with a header and no records, where
    // every window is past the end. `b` past the end still runs to EOF without
    // failing (T14c): a window that STARTS inside the file has an unambiguous
    // answer -- what is there.
    //
    // BEFORE emitter.end, which writes the closing meta line. After it,
    // `--json` would emit a complete, valid document announcing zero records
    // while exiting 1, and a consumer reading only stdout would conclude "the
    // range is empty" when it is invalid; the closing line is the sentinel
    // that marks a run cut short. NI.
    //
    // The opening meta line, and with `-t` the header row, may already have
    // gone out: the total is not knowable until the file has been read. That
    // is the price of streaming; buffering the header until a data record
    // appears would change what `-t` means for every empty selection.
    //
    // 起點越過檔尾是**錯誤**，不是警告。對一個會捲動的 UI，這正是繞回時發生的那一次呼叫，而
    // 空輸出與「這幾列真的是空的」無法區分——SwiftUI 會算繪出一片空白儲存格，看起來完全像資料。
    // `-get` 越界是錯誤，理由相同（T70f）。這也涵蓋「有標頭、沒有紀錄」的檔案，在那裡每一個
    // 視窗都在結尾之後。`b` 越界仍然輸出到檔尾、不失敗（T14c）：一個「起點在檔案內」的視窗有一個
    // 明確的答案——現有的這些。
    //
    // 放在 emitter.end **之前**，而 emitter.end 會寫出結尾那行 meta。放在它之後，`--json` 會在以 1
    // 結束的同時輸出一份宣告「零筆」、完整而合法的文件，只讀 stdout 的消費端會得出「這個範圍是
    // 空的」，而事實是它無效；那行結尾正是標示「執行被中途切斷」的記號。NI。
    //
    // 開頭那行 meta，以及帶 `-t` 時的標頭列，可能已經送出去了：總筆數要讀完檔案才知道。那是串流的
    // 代價；把標頭緩衝到「有資料紀錄出現」為止，會改變 `-t` 對每一種空選取的意義。
    if let (a, _) = o.mid, a > seen {
        if seen == 0 {
            throw fault(
                "-mid \(a): this file has no data records at all, so no window can start there",
                "-mid \(a)：這個檔案完全沒有資料紀錄，因此沒有任何視窗能從那裡開始")
        }
        throw fault(
            "-mid \(a) starts after the last record: this file has \(seen)",
            "-mid \(a) 的起點在最後一筆之後：這個檔案有 \(seen) 筆")
    }

    if let scopedRecord, !scopedRecordSeen {
        throw fault("search scope requested record \(scopedRecord), but the file has only \(seen) records",
                    "搜尋範圍要求第 \(scopedRecord) 筆，但本檔案只有 \(seen) 筆紀錄")
    }
    if let c = ctx {
        // Oldest first. While the ring was still filling, `tailHead` has wrapped
        // to 0 exactly when it became full, so starting at `tailHead` is right
        // in both cases -- but only because the modulo above uses `n` and the
        // array never grows past it.
        // 由舊到新。在環還在填滿的期間，`tailHead` 恰好在它填滿的那一刻繞回 0，因此從 `tailHead`
        // 開始在兩種情況下都正確——而那只在「上面的取模用的是 `n`、且陣列永遠不會長過它」時成立。
        if tailFilled > 0 {
            for k in 0..<tailFilled {
                try emitRecord(tailRing[(tailHead + k) % tailFilled], matches: matchesIn(tailRing[(tailHead + k) % tailFilled]))
            }
        }
        try emitter.end(c, records: seen, matched: matchedCount)
    }
    // Close the INPUT before the rename, not at function exit.
    //
    // POSIX lets you rename over a file somebody still has open; Windows does
    // not -- MoveFileExW returns error 5, ACCESS_DENIED. `defer { plan.source
    // .close() }` runs when the function returns, which is AFTER sink.close()
    // has renamed, so on Windows every `--in-place` edit and every `-o` write
    // would fail there. On macOS and Linux the ordering does not matter, so
    // only a Windows run shows it.
    //
    // The defer stays: this is belt and braces, and ByteSource.close is safe to
    // call twice.
    //
    // 在 rename「之前」關閉輸入，而不是等到函式結束。
    // POSIX 允許你 rename 覆蓋一個「還有人開著」的檔案，Windows 不允許——MoveFileExW 回傳
    // error 5（ACCESS_DENIED）。`defer { plan.source.close() }` 在函式回傳時才執行，而那是在
    // sink.close() 完成 rename「之後」，因此在 Windows 上，每一次 `--in-place` 編輯與每一次 `-o`
    // 寫入都會在那裡失敗。在 macOS 與 Linux 上這個順序無關緊要，所以只有在 Windows 上跑才看得到。
    // defer 保留：這是雙保險，而 ByteSource.close 可以安全地被呼叫兩次。
    plan.source.close()
    try sink.close()
    aborted = false

    // Only when a FILE was written. `-so` and the bare stdout path have no
    // rename to report, and saying "atomic rename OK" about a stream would be
    // a line that is false in the one word that matters.
    // 只有在「有寫出檔案」時才寫。`-so` 與直接寫 stdout 的那條路徑沒有 rename 可回報，
    // 而對一條串流說「atomic rename OK」，會是一行「錯在最要緊的那個字上」的紀錄。
    if o.output != nil {
        Logger.shared.info("wrote \(emittedCount) records, \(headers.first?.count ?? 0) fields, atomic rename OK")
    }

    // The index is written only after everything else has succeeded, and it is
    // never allowed to turn a completed operation into a failed one.
    // 索引只在其餘一切都成功之後才寫，且絕不允許它把一個已完成的操作變成失敗。
    if let b = builder, let path = o.input, let idx = b.finish(dataPath: path) {
        idx.save(dataPath: path)
    }

    Logger.shared.debug("format=\(plan.format.rawValue) fields=\(expectedFields) records=\(seen)")
    Metrics.report(bytesRead: plan.source.bytesRead,
                   fileSize: o.input.flatMap { Int(FileStamp.of(path: $0)?.size ?? 0) } ?? 0)
    if parser.sawCRLF {
        // Recorded at INFO in the log, NOT printed to stderr: reading a CRLF
        // file and writing LF changes every line of the git diff, and that
        // surprises people -- but the rule about staying silent on the normal
        // path does not get an exception for it.
        // 以 INFO 記入 log，不印到 stderr：讀 CRLF 寫 LF 會讓整份 git diff 變動，
        // 那會讓人意外——但「正常路徑上不出聲」那條規則不因此破例。
        Logger.shared.info("input contained CRLF line endings; normalised to LF")
    }
}

// ---------------------------------------------------------------------
// MARK: - Edit / 編輯
// ---------------------------------------------------------------------

func runEdit(_ o: Options) throws {
    var plan = try openInput(o)
    defer { plan.source.close() }
    if let p = o.input {
        try checkTornAppend(path: p, format: plan.format, truncatePartial: o.truncatePartial)
    }

    // A suffix-less file is `.lines`: ONE column, zero header rows, bytes
    // verbatim -- so a comma there is DATA. A column added to it would be a
    // second field only until it is read back, when the comma is data again
    // and the record is one field containing a comma: csv2 would write, at
    // rc=0, a file csv2 misreads (the same class as JV). The suffix declares
    // the format, and this file's suffix cannot declare two columns. KC,
    // T214q.
    // 沒有副檔名的檔案是 `.lines`：**一欄**、零列標頭、位元組原樣——因此那裡的逗號是**資料**。
    // 對它新增的一欄只在被讀回來之前是第二個欄位；讀回來時那個逗號又是資料，那一筆就成了「一個
    // 含逗號的欄位」：csv2 會在 rc=0 之下寫出一個 csv2 自己會誤讀的檔案（與 JV 同類）。副檔名宣告
    // 格式，而這個檔案的副檔名宣告不出兩欄。KC、T214q。
    if plan.format == .lines, o.edits.contains(where: { if case .addColumn = $0 { return true }; return false }) {
        throw fault(
            "-add-column on a file with no suffix: that is one column, zero header rows, bytes verbatim, so a comma in it is DATA. A second column would be read back as part of the first. Write it to a file named .csv or .csv2 instead",
            "-add-column 用在沒有副檔名的檔案上：那是一欄、零列標頭、位元組原樣，因此裡面的逗號是**資料**。第二欄讀回來時會變成第一欄的一部分。請改寫到一個名為 .csv 或 .csv2 的檔案")
    }

    var inserts: [Int: [String]] = [:]
    var appends: [String] = []
    var deletes: [(Int, Int)] = []
    var updates: [Int: [(String, [UInt8])]] = [:]
    var blanks: [Int: [String]] = [:]
    var dropTokens: [String] = []

    // Applied to the headers and to every data record, at a 1-based position
    // that counts against the file AS IT ARRIVED -- the same batch rule the
    // four other edit verbs obey, so that `-add-column 2 x -delete -col 2`
    // names the arriving column 2 in both halves rather than one before and
    // one after.
    // 套用在標頭與每一筆資料紀錄上，位置是 1-based，且對「檔案送達時的樣子」計數——那是其他四個
    // 編輯動詞遵守的同一條批次規則，如此 `-add-column 2 x -delete -col 2` 的兩半指的都是「送達時的
    // 第 2 欄」，而不是一個在改動前、一個在改動後。
    var addCols: [(at: Int, name: String, titles: [String], value: String)] = []
    for e in o.edits {
        switch e {
        case .insert(let at, let row): inserts[at, default: []].append(row)
        case .append(let row): appends.append(row)
        case .deleteRange(let a, let b): deletes.append((a, b))
        case .update(let r, let c, let v): updates[r, default: []].append((c, [UInt8](v.utf8)))
        case .deleteCell(let r, let c): blanks[r, default: []].append(c)
        case .deleteColumn(let c): dropTokens.append(c)
        case .addColumn(let at, let name, let value):
            let titles = try splitHeaderName(name)
            guard let english = titles.first, !english.isEmpty else {
                throw fault("-add-column \(at): the English title is required and cannot be empty",
                            "-add-column \(at)：英文標題是必填，且不可為空")
            }
            guard titles.count <= plan.headerRows else {
                throw fault(
                    "-add-column \(at) NAME has \(titles.count) titles, but this input has \(plan.headerRows) header row(s); no title may be silently ignored",
                    "-add-column \(at) 的 NAME 有 \(titles.count) 個標題，但輸入只有 \(plan.headerRows) 列標頭；任何標題都不可被靜默忽略")
            }
            addCols.append((at, name, titles, value))
        case .updateWhere: break
        }
    }

    if o.valueFile != nil || o.valueStdin {
        let bytes: [UInt8]
        if let path = o.valueFile {
            // Name the path: a script driving `-update` over many value files
            // needs to know WHICH one failed, as every comparable message here
            // names its subject. NX.
            //
            // Name the reason too. `Data(contentsOf:)` fails alike for a
            // missing file and a non-regular one, while an empty REGULAR file
            // is accepted -- so "cannot read" would misdescribe `/dev/null`. A
            // directory or a device is not unreadable; its bytes simply cannot
            // be a cell's value.
            //
            // 指名路徑：一支對許多值檔案跑 `-update` 的腳本，需要知道是**哪一個**失敗了，而這裡其他
            // 每一則同類訊息都會指名它的主體。NX。
            //
            // 理由也一併指名。`Data(contentsOf:)` 對「不存在的檔案」與「不是一般檔案的東西」都會失敗，
            // 而空的**一般**檔案是被接受的——因此「無法讀取」會誤述 `/dev/null`。目錄或裝置不是「讀不到」，
            // 而是它們的位元組不能成為一個儲存格的值。
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                let why: (String, String)
                if !exists {
                    why = ("there is no such file", "沒有這個檔案")
                } else if isDir.boolValue {
                    why = ("that is a directory", "那是一個目錄")
                } else {
                    why = ("it is not a regular file, so it has no bytes to read as a value",
                           "它不是一般檔案，因此沒有可以當成值讀取的位元組")
                }
                throw fault("--value-file \(path): \(why.0)",
                            "--value-file \(path)：\(why.1)")
            }
            bytes = [UInt8](data)
        } else {
            bytes = [UInt8](FileHandle.standardInput.readDataToEndOfFile())
        }
        guard case .update(let record, let column, _) = o.edits[0] else {
            throw fault("--value-file/--value-stdin requires -update",
                        "--value-file／--value-stdin 需要搭配 -update")
        }
        updates[record] = [(column, bytes)]
    }

    let anchored = o.edits.compactMap { edit -> (String, String)? in
        if case .updateWhere(let old, let value) = edit { return (old, value) }
        return nil
    }
    if !anchored.isEmpty {
        guard o.input != nil, !o.useStdin else {
            throw fault(
                "-update-where needs -i FILE because it must scan the complete input before writing; it cannot be used with -si",
                "-update-where 需要搭配 -i FILE，因為它必須在寫出前掃描完整輸入；不可與 -si 併用")
        }

        // Content-anchored edits must know whether each OLD value is unique
        // before a destination or stdout receives any bytes. A second pass is
        // deliberate: refusing after partial output would not be recoverable.
        // 依內容定位的編輯必須在任何目的地或 stdout 收到位元組之前，先知道每個 OLD 是否唯一。
        // 第二次掃描是刻意的：寫出部分內容後才拒絕，結果無法復原。
        // Re-open through openInput, NOT through ByteSource(path:) directly.
        //
        // `ByteSource(path:)` hands back the file's raw bytes; openInput hands
        // back the RECORD STREAM, and for a `.md` input those differ, because
        // openInput is where MarkdownIn.translate turns the table into records.
        // Raw bytes would deliver `| pkg | version |` as one comma-free field
        // and `|---|---|` as the next, tripping the guard against feeding `-md`
        // output back in as CSV on a correctly named `.md` file. LL.
        //
        // 用 openInput 重新開啟，**不要**直接用 `ByteSource(path:)`。
        //
        // `ByteSource(path:)` 交回的是檔案的原始位元組，openInput 交回的是**紀錄流**，而對 `.md`
        // 輸入而言兩者不同——因為 openInput 正是 MarkdownIn.translate 把表格轉成紀錄的地方。
        // 讀原始位元組，會讓 `| pkg | version |` 以「一個不含逗號的欄位」抵達、`|---|---|` 成為下一個，
        // 於是那道「防止有人把 `-md` 的輸出當 CSV 餵回來」的守衛，會對一個副檔名正確為 `.md` 的檔案
        // 開火。LL。
        plan.source.close()
        let scanPlan = try openInput(o)
        let scan = scanPlan.source
        var scanHeaders: [Record] = []
        var scanExpected = 0
        var scanError: Error?
        var found: [[(record: Int, column: Int)]] = Array(repeating: [], count: anchored.count)
        let parser = RecordParser(format: scanPlan.format) { rec in
            do {
                if scanHeaders.count < plan.headerRows {
                    var h = rec
                    h.number = 0
                    scanHeaders.append(h)
                    if scanHeaders.count == plan.headerRows {
                        try validateHeaders(scanHeaders, want: plan.headerRows, path: plan.describedPath)
                        scanExpected = scanHeaders[0].count
                    }
                } else {
                    var data = rec
                    data.number = rec.number - plan.headerRows
                    if scanExpected == 0 { scanExpected = data.count }
                    try checkFieldCount(data, expected: scanExpected,
                                        what: "record \(data.number) (line \(data.line))")
                    for (i, target) in anchored.enumerated() {
                        let old = Array(target.0.utf8)
                        for (column, field) in data.fields.enumerated()
                                where field.value == old {
                            found[i].append((data.number, column + 1))
                        }
                    }
                }
            } catch {
                scanError = error
                return false
            }
            return true
        }
        while !parser.stopped, let chunk = scan.next() { try parser.feed(chunk) }
        if !parser.stopped { try parser.finish() }
        if let scanError { throw scanError }
        if scanHeaders.count < plan.headerRows {
            try validateHeaders(scanHeaders, want: plan.headerRows, path: plan.describedPath)
        }

        var occupied = Set<String>()
        for (i, hits) in found.enumerated() {
            guard hits.count == 1 else {
                let old = echoValue(Array(anchored[i].0.utf8))
                if hits.isEmpty {
                    throw fault(
                        "-update-where \"\(old)\": no data cell equals OLD in full",
                        "-update-where「\(old)」：沒有任何資料儲存格的完整內容等於 OLD")
                }
                let addresses = hits.map { "\($0.record):\($0.column)" }.joined(separator: ", ")
                throw fault(
                    "-update-where \"\(old)\": more than one data cell matches (\(addresses)); refusing an ambiguous update",
                    "-update-where「\(old)」：有多個資料儲存格符合（\(addresses)）；拒絕這個有歧義的更新")
            }
            let hit = hits[0]
            let key = "\(hit.record):\(hit.column)"
            guard occupied.insert(key).inserted else {
                throw fault(
                    "-update-where edits overlap at \(key); refusing to choose which value should survive",
                    "-update-where 編輯在 \(key) 重疊；拒絕猜測哪一個值應該留下")
            }
            updates[hit.record, default: []].append((String(hit.column), [UInt8](anchored[i].1.utf8)))
        }
        scan.close()
        // Same reason as the scan's own open: this rewind feeds the MAIN pass,
        // which needs the record stream too.
        // 與掃描自己的開啟同一個理由：這次倒帶餵的是**主要**那一趟，它同樣需要紀錄流。
        plan.source = try openInput(o).source
    }

    // Two edits aimed at the SAME cell: the first cannot survive the second,
    // so applying both would overwrite the first at rc=0 and still report it
    // as done.
    //
    // Two `-insert`s at one N are different and stay legal: they produce two
    // records, in the order written, and both survive. That is documented.
    // Two updates produce one value, and one of them was never going to be it.
    //
    // 兩個瞄準「同一個儲存格」的編輯：第一個不可能在第二個之下存活，兩個都套用的話，第一個會在
    // rc=0 之下被覆蓋，卻仍被回報為已完成。
    //
    // 同一個 N 上的兩次 `-insert` 是另一回事，仍然合法：它們產生兩筆紀錄、依書寫順序，兩筆
    // 都留下來。那是記錄在案的。兩次更新只會產生一個值，而其中一個從一開始就不會是它。
    for (rn, ups) in updates where ups.count > 1 {
        var seen = Set<String>()
        for (c, _) in ups where !seen.insert(c).inserted {
            throw fault(
                "-update \(rn):\(c) is given more than once; the earlier one would have no effect and would still be reported as done",
                "-update \(rn):\(c) 被給了不只一次；較早的那一個不會有任何效果，卻仍會被回報為已完成")
        }
    }

    // The same clash, one axis over. `-delete -col X` combined with an edit
    // aimed at column X is refused because "the edit would have no effect and
    // would still be reported as done"; `-delete a,b` combined with an edit
    // aimed at a RECORD inside a..b is the same thing:
    //
    //     csv2 -delete 1,1 -update 1:2 GHOST -i g.csv --in-place
    //     without this refusal: rc=0, GHOST nowhere, nothing said
    //
    // Addresses are input-relative, which is what makes this decidable here:
    // `-delete 1,1` and `-update 1:2` are talking about the same record by
    // definition, without needing to know what the file contains.
    //
    // 同一個衝突，換一個軸。`-delete -col X` 與「瞄準欄位 X 的編輯」併用會被拒絕，因為「該編輯
    // 不會有任何效果，卻仍會被回報為已完成」；`-delete a,b` 與「瞄準 a..b 之中某一筆的編輯」併用
    // 是同一件事：少了這道拒絕，會 rc=0、GHOST 不在任何地方，也沒有任何訊息。
    //
    // 位址是相對於輸入的，這正是此處判斷得出來的原因：`-delete 1,1` 與 `-update 1:2` 依定義
    // 就是在說同一筆紀錄，不需要知道檔案裡有什麼。
    if !deletes.isEmpty {
        func deleted(_ r: Int) -> (Int, Int)? {
            for (a, b) in deletes where r >= a && r <= b { return (a, b) }
            return nil
        }
        var clash: [String] = []
        for (rn, ups) in updates {
            if let (a, b) = deleted(rn) {
                for (c, _) in ups { clash.append("-update \(rn):\(c) with -delete \(a),\(b)") }
            }
        }
        for (rn, cols) in blanks {
            if let (a, b) = deleted(rn) {
                for c in cols { clash.append("-delete -cell \(rn):\(c) with -delete \(a),\(b)") }
            }
        }
        if !clash.isEmpty {
            throw fault(
                "\(clash.sorted().joined(separator: ", ")): the edit targets a record that -delete is removing in the same run, so it would have no effect and would still be reported as done",
                "\(clash.sorted().joined(separator: "、"))：該編輯瞄準的紀錄正被同一次執行的 -delete 移除，因此它不會有任何效果，卻仍會被回報為已完成")
        }
    }

    var backupToUndo: String?
    if o.backup, let path = o.input {
        try makeInPlaceBackup(path)
        backupToUndo = path + ".bak"
    }
    let sink = o.dryRun ? ByteSink(stdout: 1 << 16) : try makeSink(o)
    var aborted = true
    // The backup goes with the sink.
    //
    // It is written BEFORE the edit, which it has to be -- it exists to hold
    // the bytes the edit is about to replace. But a failed edit leaves the
    // input byte-identical, so the `.bak` then holds a copy of a file nothing
    // touched, and `makeInPlaceBackup` refuses to overwrite an existing one:
    // left behind, ONE failure would block every future `--backup` edit on
    // that path.
    //
    // This is the same shape as T28d, which asserts that a failed in-place edit
    // leaves no temp file beside the input. A stale `.bak` is that debris under
    // a different name. OB.
    //
    // 備份與 sink 同進退。
    //
    // 它寫在編輯**之前**，那是必然的——它存在的理由就是保存「那次編輯即將取代的位元組」。但一次
    // 失敗的編輯會讓輸入逐位元不變，於是那個 `.bak` 保存的是一份「沒有任何東西動過的檔案」的複本；
    // 而 `makeInPlaceBackup` 拒絕覆寫既有的備份：留著它，**一次失敗就會封死那個路徑上未來的
    // 每一次 `--backup` 編輯**。
    //
    // 這與 T28d 是同一個形狀——那個案例斷言「一次失敗的就地編輯不會在輸入旁邊留下暫存檔」。
    // 一個過期的 `.bak` 就是那份殘骸換了個名字。OB。
    defer {
        if aborted {
            sink.abort()
            if let b = backupToUndo { try? FileManager.default.removeItem(atPath: b) }
        }
    }

    var headers: [Record] = []
    // The header as it ARRIVED, kept for resolving column addresses.
    //
    // `headers` is rewritten in place by `-delete -col` and `-add-column`
    // before any record is processed, while each record keeps its input shape
    // until the very end -- deliberately, "so that every index above still
    // refers to the input" (see the bottom of the record path). An address
    // resolved against the REWRITTEN header and applied to an UNREWRITTEN
    // record silently writes to a neighbouring column: `-delete -col a
    // -update 1:d` on `a,b,c,d,e` would put the new value in `c`, exit 0. The
    // record side holds the invariant, so the header side adapts to it. MS.
    //
    // 標頭**抵達時**的樣子，留著用來解析欄位位址。
    //
    // `headers` 會在任何紀錄被處理之前，就被 `-delete -col` 與 `-add-column` 就地改寫，而每一筆
    // 紀錄保持它輸入時的形狀直到最後——那是刻意的，「讓上面每一個索引都仍指向輸入」（見紀錄路徑
    // 底部）。拿**改寫過的**標頭解析位址、再套到一筆**還沒改寫的**紀錄上，會靜默地寫進隔壁那一欄：
    // `a,b,c,d,e` 上的 `-delete -col a -update 1:d` 會把新值放進 `c`，rc=0。不變量由紀錄那一側
    // 維持，因此由標頭這一側去配合它。MS。
    var addressHeader: Record?
    var expectedFields = 0
    var transform: CellTransform = .none
    var total = 0
    var pendingError: Error?
    var touched = Set<Int>()
    // Resolved once, against the INPUT header, and then applied to every
    // record. Re-resolving per record would let a name refer to different
    // columns in the same run once earlier columns had been removed.
    // 對「輸入」的標頭解析一次，之後套用到每一筆。若逐筆重新解析，同一次執行中
    // 一個名稱會在先前欄位被移除後指向不同的欄。
    var drop = Set<Int>()
    // Insert before dropping, and both against the ARRIVING file.
    //
    // The two must not see each other's work: `-add-column 2 x -delete -col 2`
    // has to mean "the arriving column 2, in both", the same way
    // `-insert 3 -delete 2` counts both against the arriving records. Applying
    // the add first and then a drop computed on the NEW positions would delete
    // whatever the add had just pushed sideways -- one line of code apart, and
    // silent.
    //
    // 先插入、後刪除，而兩者都是對「送達時的檔案」計數。
    // 這兩件事不能看見彼此的成果：`-add-column 2 x -delete -col 2` 必須表示「送達時的第 2 欄，
    // 兩者皆是」，就像 `-insert 3 -delete 2` 兩者都對送達時的紀錄計數一樣。先套用新增、再用
    // 「**新的**位置」算出來的刪除，會刪掉那次新增剛剛推到旁邊的東西——兩者相差一行程式碼，而且是
    // 靜默的。
    func addColumns(_ r: inout Record, headerRow: Int?) throws {
        guard !addCols.isEmpty else { return }
        // The width BEFORE any of these went in. Both the bounds check and
        // the position are answered against the file as it arrived -- "All
        // indexes refer to the INPUT and are applied in one pass", the rule
        // `-insert` follows -- so a second -add-column in one run does not
        // count against a file the first one already widened. KB.
        // 這是「這些欄位都還沒進去之前」的寬度。越界檢查與插入位置都以「檔案送達時的樣子」來回答
        // ——「所有索引都指向輸入，並在一遍之內套用」，那是 `-insert` 遵守的規則——因此同一次執行裡
        // 第二個 -add-column 不會算在前一個已經加寬過的檔案上。KB。
        let arrived = r.fields.count
        for (k, a) in addCols.enumerated() {
            // No clamping: `-add-column 9` on a two-column file must not land
            // at the end and exit 0, leaving the caller believing the 9 meant
            // something. One past the last column is the append; anything
            // beyond it is a number that does not describe this file.
            // 不夾取：兩欄檔案上的 `-add-column 9` 不可以落在最後並以 0 結束，讓呼叫端以為那個 9
            // 有意義。「最後一欄再加一」是附加；再往後就是一個描述不了這個檔案的數字。
            guard a.at <= arrived + 1 else {
                throw fault(
                    "-add-column \(a.at): this file has \(arrived) columns, so the highest position is \(arrived + 1), which appends",
                    "-add-column \(a.at)：這個檔案有 \(arrived) 欄，因此最大的位置是 \(arrived + 1)，那會附加在最後")
            }
            // Shift by the ones already placed at or before this position, so
            // that a.at keeps meaning what it meant on the command line.
            // 依「已經放在這個位置或更前面的那幾個」平移，好讓 a.at 維持它在命令列上的意思。
            let idx = a.at - 1 + addCols[..<k].filter { $0.at <= a.at }.count
            let text: String
            if let hr = headerRow {
                // The name carries both titles the way the header row does:
                // one CSV record, so `note,備註` is two fields and a name that
                // itself contains a comma can be quoted like anything else.
                // 那個名字以「標頭列的方式」承載兩個標題：一筆 CSV 紀錄，因此 `note,備註` 是兩個
                // 欄位，而一個「名字本身含逗號」的欄位可以像其他任何東西一樣加引號。
                text = hr < a.titles.count ? a.titles[hr] : ""
            } else {
                text = a.value
            }
            r.fields.insert(Field(value: Array(text.utf8)), at: idx)
        }
    }

    /// Removing several columns at once, by rebuilding rather than removing in
    /// place: `remove(at:)` twice would make the second index refer to the row
    /// as it stands after the first removal -- the same off-by-one as
    /// `-delete 3 -delete 4`, described in the record path below.
    /// 一次移除多欄時採「重建」而非就地刪除：連續兩次 `remove(at:)` 會讓第二個索引
    /// 指向第一次移除後的那一列——與下面紀錄路徑中 `-delete 3 -delete 4` 所描述的是同一個偏移。
    func dropColumns(_ r: inout Record) {
        guard !drop.isEmpty else { return }
        var kept: [Field] = []
        kept.reserveCapacity(r.fields.count - drop.count)
        for (i, f) in r.fields.enumerated() where !drop.contains(i) { kept.append(f) }
        r.fields = kept
    }

    // The write path already knows where every record starts -- it is about to
    // write it. Noting the offsets costs no extra scan, which is why building
    // the index here is nearly free while building one for a read would not be.
    // 寫入端本來就知道每一筆從哪裡開始——它正要寫下去。順手記下偏移量不需要額外
    // 掃描，這正是「在此建索引幾乎免費、而為讀取建索引則不然」的原因。
    var outOffset = 0
    var outRecords = 0
    /// The physical line the NEXT record written will start on. The index
    /// stores a line per grid point now, and the output's lines are not the
    /// input's: a record is re-serialised on the way out, and a value holding
    /// newlines makes the two diverge from the first such record onwards.
    /// Counted from what is actually written.
    /// 「下一筆要寫出的紀錄」會落在第幾實體行。索引現在每個格點存一個行號，而輸出的行號
    /// 不是輸入的行號：紀錄在寫出時會重新序列化，而一個含換行的值會讓兩者從第一筆這樣的
    /// 紀錄起就分家。因此由「實際寫出去的東西」去數。
    var outLine = 1
    var builder: IndexBuilder? = nil
    if !o.noIndex, let outPath = o.output, Format.declaresFormat(path: outPath),
       let inPath = o.input, let st = FileStamp.of(path: inPath),
       st.size >= UInt64(indexMinBytes()) {
        builder = IndexBuilder(isCSV2: plan.format == .csv2)
    }

    var dryRunChanges: [String] = []
    // RN. In `.lines` a value is written raw, so an LF in it ends the record
    // and starts another, and a CR at its end joins the LF after it into a
    // CRLF that reads back as the line ending. -insert and -append refuse such
    // a value; -update (and -update-where, --value-file, --value-stdin, which
    // all arrive here) must too, before anything is written.
    // RN。`.lines` 的值是原樣寫出的，所以值裡的 LF 會結束這一筆並開始另一筆；值結尾的 CR 會和
    // 後面的 LF 合成 CRLF，讀回來就成了行尾。-insert 與 -append 都拒絕這種值；-update（以及
    // -update-where、--value-file、--value-stdin，它們都走到這裡）也必須在寫出任何東西之前拒絕。
    if plan.format == .lines {
        for (record, ups) in updates.sorted(by: { $0.key < $1.key }) {
            for (column, value) in ups {
                if value.contains(BYTE_LF) {
                    throw fault("-update \(record):\(column): the value spans more than one record",
                                "-update \(record):\(column)：這個值跨越了不只一筆紀錄")
                }
                if value.last == BYTE_CR {
                    throw fault("-update \(record):\(column): in a lines file a value cannot end with a carriage return; it would read back as part of the line ending",
                                "-update \(record):\(column)：在 lines 檔裡，值不能以歸位字元結尾；讀回時它會成為行尾的一部分")
                }
            }
        }
    }
    // Each record's closing LF is held back until the next record goes out, so
    // that the LAST one can end the way the input's last one did; otherwise a
    // file with no final newline gains one from any edit. CRLF is a different case -- one line ending
    // replaced by another -- and still becomes LF. The offset and line counts
    // include the held byte, which is right for every record after it and
    // does not matter after the last. RK.
    // 每一筆紀錄結尾的 LF 先扣著，等下一筆寫出時才補，好讓**最後一筆**以輸入最後一筆的方式結束。
    // 否則一個沒有結尾換行的檔案，任何一次編輯都會讓它多出一個。CRLF 是另一回事——
    // 一個行尾換成另一個——它照舊變成 LF。偏移量與行數都把扣著的那個位元組算進去：對它之後的每一筆
    // 都是對的，在最後一筆之後則無關緊要。RK。
    var heldLF = false
    // RL. A record that encodes to nothing but its LF -- one empty field in a
    // one-column file -- exists only through that newline, so for it the held
    // LF is the record itself and is written even when the input had no final
    // newline. Without this, 'a\nx' edited to an empty last record would come
    // out as 'a\n': one record fewer, rc 0. Writing `""` instead was rejected: it
    // rewrites a field encoding nobody asked to change.
    // RL。一筆編碼後只剩 LF 的紀錄——單欄檔案裡的一個空欄位——只靠那個換行而存在，所以對它來說扣著的
    // LF 就是紀錄本身，即使輸入沒有結尾換行也照寫。少了這一條，'a\nx' 把最後一筆改成空值後會寫出
    // 'a\n'：少一筆，rc 0。否決了改寫成 `""`：那會改動一個沒人要求改的欄位編碼。
    var heldRecordIsEmpty = false
    // RP. The LF is withheld only when the record written last IS the input's
    // final record -- the one that ended without a newline. When that record
    // is deleted, the record now written last is one that had its LF in the
    // input, and it keeps it. Inserted and appended records are not input
    // records, so they never take the input's missing newline.
    // RP。只有在最後寫出的那一筆「就是」輸入的最後一筆（那筆沒有結尾換行的）時，才扣下 LF。那一筆
    // 被刪掉時，現在最後寫出的是一筆在輸入裡本來就有 LF 的紀錄，它保留它的 LF。插入與追加的紀錄
    // 不是輸入的紀錄，所以永遠不會沿用輸入缺少的換行。
    var inputRecordsSeen = 0
    var heldSeenAt = -1
    // Every byte that leaves this function is counted here -- offset AND
    // line. Header rows go out through this function too, so counting lines
    // only in emitData would put record 1 of a `.csv2` on line 1 in the index
    // instead of line 3.
    // 每一個離開這個函式的位元組都在這裡被計入——偏移量「與」行號。標頭列也走這個函式，若只在
    // emitData 裡數行，索引會說 `.csv2` 的第 1 筆在第 1 行，而它其實在第 3 行。
    func emit(_ r: Record, fromInput: Bool = true) {
        if o.dryRun { return }
        let bytes = FieldEncoder.encodeRecord(r, format: plan.format, preserveRaw: true)
        if heldLF { sink.write([BYTE_LF]) }
        heldLF = bytes.last == BYTE_LF
        heldSeenAt = fromInput ? inputRecordsSeen : -1
        heldRecordIsEmpty = heldLF && bytes.count == 1
        sink.write(heldLF ? Array(bytes.dropLast()) : bytes)
        outOffset += bytes.count
        outLine += bytes.filter { $0 == BYTE_LF }.count
    }

    func emitData(_ r: Record, fromInput: Bool = true) {
        outRecords += 1
        // A record that itself contains a newline makes the record number stop
        // matching the line number, and the index cannot then be used to seek
        // (it stores bytes, not lines). Recorded here so the flag in the index
        // header is right.
        // 自身含換行的紀錄會讓紀錄號不再等於行號，屆時索引就不能用來 seek
        // （它存的是位元組而非行號）。在此記錄，讓索引檔頭的旗標是正確的。
        // Answered by the same function as the other two call sites, so the
        // three cannot disagree.
        // 與另外兩個呼叫點由同一個函式回答，因此三者不可能說法不一。
        builder?.add(record: outRecords, at: UInt64(outOffset), line: UInt64(outLine),
                     spansLines: recordSpansLines(r, format: plan.format))
        emit(r, fromInput: fromInput)
    }

    let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
        inputRecordsSeen += 1
        do {
            if headers.count < plan.headerRows {
                var h = rec
                h.number = 0
                headers.append(h)
                if headers.count == plan.headerRows {
                    try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath)
                    expectedFields = headers[0].count
                    // Before buildTransform, so a column the file already marks is redacted even
                    // when this run performs no transform at all.
                    // 放在 buildTransform 之前，好讓「檔案已標記的欄位」即使在本次完全沒有
                    // 轉換時也會被遮蔽。
                    redactColumnsDeclaredByHeader(headers[0])
                    // Refuse before a byte is written, and against the INPUT
                    // header rather than the marked one -- `-encrypt secret`
                    // together with `-update 1:secret NEW` is coherent (the new
                    // value is what gets encrypted) and stays allowed, because
                    // the input's header carries no marker yet.
                    //
                    // What is refused is writing a raw value into a column the
                    // FILE already declares transformed. For `:enc:` that is
                    // not merely wrong, it is unrecoverable and it is not
                    // confined to the record edited: -decrypt stops at the
                    // damaged cell, so every later record -- ciphertext intact,
                    // never touched -- can no longer be read either. And the
                    // log would say `<redacted> -> <redacted>`, because
                    // redaction follows the file's declaration, so the only
                    // record of what happened would conceal it. W.
                    //
                    // 在寫出任何一個位元組之前拒絕，而且是對「輸入的」標頭而非加上標記後的
                    // 標頭——`-encrypt secret` 與 `-update 1:secret NEW` 併用是說得通的
                    // （被加密的就是那個新值），因此仍然允許，因為輸入的標頭還沒有標記。
                    // 被拒絕的是「把原始值寫進一個檔案已經宣告為轉換過的欄位」。對 `:enc:`
                    // 而言那不只是錯，而是不可回復、且不限於被編輯的那一筆：-decrypt 會停在
                    // 損壞的那一格，於是之後每一筆——密文完好、從未被碰過——也一起讀不回來。
                    // 而 log 會寫 `<redacted> -> <redacted>`，因為遮蔽依據的是檔案的宣告，
                    // 於是唯一那份「發生了什麼」的紀錄會把它掩蓋掉。W。
                    let prot = protectedColumns(headers[0])
                    if !prot.columns.isEmpty {
                        var cellTargets: [String] = []
                        let protIdx = Set(prot.columns.map { $0.0 })
                        for (rn, ups) in updates {
                            for (c, _) in ups where protIdx.contains(try resolveColumn(c, header: headers[0])) {
                                cellTargets.append("-update \(rn):\(c)")
                            }
                        }
                        for (rn, cols) in blanks {
                            for c in cols where protIdx.contains(try resolveColumn(c, header: headers[0])) {
                                cellTargets.append("-delete -cell \(rn):\(c)")
                            }
                        }
                        if !cellTargets.isEmpty {
                            throw rawCellWriteRefusal(targets: cellTargets, anyEncrypted: prot.anyEncrypted)
                        }
                        // A whole row cannot be written into such a file at all:
                        // every field of it is raw, including the one belonging
                        // to the transformed column, and no value the caller
                        // could supply would be right -- the transform needs the
                        // key, and the header carries only its fingerprint.
                        // 一整列根本無法寫進這樣的檔案：它的每一欄都是原始值，包括屬於那個
                        // 已轉換欄位的那一欄，而呼叫者給得出的值沒有一個會是對的——那個轉換
                        // 需要金鑰，而標頭裡只有它的指紋。
                        var rowVerbs: [String] = []
                        for rn in inserts.keys.sorted() { rowVerbs.append("-insert \(rn)") }
                        if !appends.isEmpty { rowVerbs.append("-append") }
                        if !rowVerbs.isEmpty {
                            throw rawRowWriteRefusal(verbs: rowVerbs,
                                                     columns: prot.columns.map { $0.1 },
                                                     anyEncrypted: prot.anyEncrypted)
                        }
                    }
                    transform = try buildTransform(o, headers: headers)
                    markHeaders(&headers, transform: transform)
                    if !dropTokens.isEmpty {
                        for token in dropTokens {
                            drop.insert(try resolveColumn(token, header: headers[0]))
                        }
                        // A file with no columns is not a CSV file, and an
                        // empty output would be produced with rc=0 -- the
                        // shape of failure this project exists to refuse.
                        // 沒有任何欄位的檔案不是 CSV 檔，而那會產生一個 rc=0 的空
                        // 輸出——正是本專案存在的目的所要拒絕的那種失敗形狀。
                        if drop.count == expectedFields {
                            throw fault(
                                "-delete -col would remove all \(expectedFields) columns; a file with no columns is not a CSV file",
                                "-delete -col 會移除全部 \(expectedFields) 欄；沒有任何欄位的檔案不是 CSV 檔")
                        }
                        // The columns, by name, once for the run: the README
                        // promises this entry, and a run that removes a whole
                        // column must leave an audit trail naming it. Round 59.
                        //
                        // Values are NOT recorded: they are the entire column,
                        // and one entry per record would make the log larger
                        // than the file it describes. The README says that too.
                        // 那些欄位的名字，整次執行記一則：README 承諾了這則紀錄，而一次移除整個欄位
                        // 的執行，留下的稽核軌跡必須指名那些欄位。第 59 回合。
                        // 不記各筆的值：那些值就是整個欄位，一筆一則會讓 log 比它描述的檔案還大。
                        // README 也是這樣寫的。
                        let goneNames = drop.sorted().map {
                            Logger.shared.nameForLog(baseName(headerName(headers[0].fields[$0])))
                        }.joined(separator: ", ")
                        Logger.shared.info("delete column \(goneNames) from every record and both header rows")
                        // An edit aimed at a column that is being removed does
                        // nothing, and reports that it did. Refusing is the
                        // whole point: the alternative is a log line saying the
                        // cell was updated and an output where it is gone.
                        // 針對一個正被移除的欄位所做的編輯不會有任何效果，卻會回報它做了。
                        // 拒絕正是重點所在：另一個選擇是一行說「該格已更新」的日誌，
                        // 以及一份那一格根本不存在的輸出。
                        var clash: [String] = []
                        for (rn, ups) in updates {
                            for (c, _) in ups where drop.contains(try resolveColumn(c, header: headers[0])) {
                                clash.append("-update \(rn):\(c)")
                            }
                        }
                        for (rn, cols) in blanks {
                            for c in cols where drop.contains(try resolveColumn(c, header: headers[0])) {
                                clash.append("-delete -cell \(rn):\(c)")
                            }
                        }
                        for c in transform.columns where drop.contains(c) {
                            clash.append("\(transform.flagName) \(baseName(headerName(headers[0].fields[c])))")
                        }
                        if !clash.isEmpty {
                            throw fault(
                                "\(clash.sorted().joined(separator: ", ")) targets a column that -delete -col is removing; the edit would have no effect and would still be reported as done",
                                "\(clash.sorted().joined(separator: "、")) 指向一個正被 -delete -col 移除的欄位；該編輯不會有任何效果，卻仍會被回報為已完成")
                        }
                        if addressHeader == nil { addressHeader = headers.first }
                        for i in headers.indices { dropColumns(&headers[i]) }
                    }
                    // An edit rewrites the whole file, so the header always
                    // goes out. `-t` is about selections, which produce a
                    // fragment; this produces a file.
                    // 編輯會重寫整個檔案，因此標頭一定寫出。`-t` 是給選取用的
                    // ——那產生的是片段，而這裡產生的是一個完整檔案。
                    // Outside the `-delete -col` block above, because a
                    // run may add a column without deleting one -- inside it,
                    // the header would keep its arriving width while every
                    // data record grew, and csv2's own reader would reject the
                    // file on the next read.
                    // 放在上面 `-delete -col` 區塊之外，因為一次執行可以只加不刪——放在裡面的話，
                    // 標頭會維持送達時的寬度而每一筆資料都變寬，寫回去的檔案在下一次讀取時
                    // 會被 csv2 自己的讀取器拒絕。
                    // A warning, not a refusal: the file is still correct
                    // csv2 with an empty Chinese title, and the person adding
                    // the column may not be the person who can translate it.
                    // Filling it with the English title would be inventing a
                    // translation, and a wrong one is harder to find later
                    // than an empty cell.
                    // 這是警告而非拒絕：中文標題留空的檔案仍然是正確的 csv2，而「加這一欄的人」
                    // 未必就是「能翻譯它的人」。拿英文標題去填等於發明一個翻譯，而一個錯的翻譯
                    // 日後比一個空格更難被發現。
                    if plan.headerRows >= 2 {
                        for a in addCols where a.titles.count < 2 {
                            Platform.writeStderr(
                                "csv2: -add-column \(a.at) \(a.name): no Chinese title given, row 2 left empty; supply both as 'english,中文'\n"
                                + "csv2：-add-column \(a.at) \(a.name)：未提供中文標題，第 2 列留空；請以 'english,中文' 一併給出\n")
                        }
                    }
                    if addressHeader == nil { addressHeader = headers.first }
                    for i in headers.indices { try addColumns(&headers[i], headerRow: i) }
                    for h in headers { emit(h) }
                    builder?.headerEnded(at: UInt64(outOffset))
                }
                return true
            }

            var r = rec
            r.number = rec.number - plan.headerRows
            total = r.number

            // Every index refers to the INPUT and they are applied in one
            // pass. Applying them one at a time would make `-delete 3
            // -delete 4` delete input record 3 and then whatever slid into
            // position 4 -- not what anybody writing that line meant.
            // 所有索引都指向輸入，且一次套用。逐一套用會讓
            // `-delete 3 -delete 4` 刪掉輸入的第 3 筆，再刪掉遞補到第 4 位的
            // 那一筆——那不是寫下這行的人想的。
            // The width has to be known BEFORE an insert at position 1 is
            // checked against it. With no header row it is set by the first
            // record -- and an insert at 1 is handled while that very record
            // is in hand, so it must be set here, before the inserts, or
            // position 1 alone is refused with a message naming a header the
            // file does not have. Round 78, JX.
            // 那個寬度必須在「位置 1 的插入被拿去和它比較」**之前**就已知。沒有標頭列時，它由
            // 第一筆紀錄決定——而位置 1 的插入，正是在那一筆還在手上時被處理的，所以必須在插入之前
            // 於此設定，否則只有位置 1 會被拒絕，而訊息還會指名一個這個檔案沒有的標頭。第 78 回合，JX。
            if expectedFields == 0 { expectedFields = r.count }
            if let rows = inserts[r.number] {
                touched.insert(r.number)
                for row in rows {
                    let ins = try parseRowLiteral(row, format: plan.format,
                                                  expected: expectedFields,
                                                  what: "-insert \(r.number)")
                    // emitData, not emit: an inserted row is a record of the
                    // OUTPUT and has to be counted like one. Through emit it
                    // would move the offset and nothing else, so the index
                    // built by the same run would count N records in a file of
                    // N+1, and every grid point after the insertion would name
                    // another record's byte -- `-mid` returning the wrong
                    // records quickly, at rc=0, which this design calls far
                    // worse than no index.
                    // 用 emitData 而不是 emit：被插入的一列是「輸出」的一筆紀錄，就該被當成
                    // 一筆來計。走 emit 的話它只推進偏移量、其餘什麼也不做，於是同一次執行建出
                    // 的索引會在 N+1 筆的檔案裡數出 N 筆，插入點之後的每一個格點指的都是另一筆
                    // 紀錄的位元組——`-mid` 會很快地以 rc=0 回傳錯的紀錄，本設計稱之為比沒有索引
                    // 糟得多。
                    emitData(ins, fromInput: false)
                }
            }
            if deletes.contains(where: { r.number >= $0.0 && r.number <= $0.1 }) {
                touched.insert(r.number)
                // With its contents: a deleted record is the largest thing
                // this tool destroys, and a bare number is not an audit trail.
                // Redacted per column, so a protected column does not arrive
                // in the log in the clear, and escaped like every other line,
                // so one record is one entry.
                // 連同它的內容：被刪掉的紀錄是這個工具銷毀得最大的東西，只記一個編號算不上稽核
                // 軌跡。逐欄套用遮蔽規則，好讓受保護的欄位不會以明文進到 log；
                // 也與其他每一行一樣做跳脫，因此一筆紀錄就是一則紀錄。
                let contents = r.fields.enumerated().map { (i, f) -> String in
                    // A file with no header row reaches these too. Row 0 is
                    // read only to NAME the column in the audit line, which is
                    // worth having and not worth a SIGTRAP when there is no
                    // row 0. Without a header the number is the name.
                    // 沒有標頭列的檔案也會走到這裡。讀第 0 列只是為了在稽核那一行裡「說出欄位的名字」，
                    // 那件事值得有，但不值得在沒有第 0 列時以 SIGTRAP 當掉。沒有標頭時，編號就是名字。
                    let n = (headers.first.map { i < $0.count ? baseName(headerName($0.fields[i])) : "\(i + 1)" }) ?? "\(i + 1)"
                    return "\(Logger.shared.nameForLog(n))=\(Logger.shared.redact(column: n, value: f.value))"
                }.joined(separator: ", ")
                Logger.shared.info("delete record \(r.number): \(contents)")
                return true
            }
            // With no header rows the first RECORD sets the width. `.lines`
            // has none by definition, and a headed file has already set this
            // from its header, so this is inert there.
            // 沒有標頭列時，由第一筆**紀錄**決定寬度。`.lines` 依定義沒有標頭，而有標頭的檔案
            // 早就從它的標頭設過這個值，因此這一行在那裡是惰性的。
            if expectedFields == 0 { expectedFields = r.count }
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))",
                                headerRows: plan.headerRows)

            if let ups = updates[r.number] {
                touched.insert(r.number)
                for (colToken, value) in ups {
                    let c: Int
                    let name: String
                    if let h0 = addressHeader ?? headers.first {
                        c = try resolveColumn(colToken, header: h0)
                        name = baseName(headerName(h0.fields[c]))
                    } else if let numeric = Int(colToken), numeric >= 1 {
                        c = numeric - 1
                        name = colToken
                    } else {
                        throw fault("\(colToken): this file has no header row, so a column can only be addressed by NUMBER here",
                                    "\(colToken)：這個檔案沒有標頭列，因此在這裡只能以「編號」定址欄位")
                    }
                    let old = r.fields[c].value
                    r.fields[c].set(value)
                    if o.dryRun {
                        dryRunChanges.append("update \(r.number):\(name): \(Logger.shared.redact(column: name, value: old)) -> \(Logger.shared.redact(column: name, value: r.fields[c].value))")
                    }
                    // The log records the value in full, so say so when "in
                    // full" is a megabyte. This is a WARN and not a cap: an
                    // audit trail must not drop data, and the honest
                    // consequence is an unbounded line -- which the person
                    // running the edit should hear about rather than discover
                    // in a disk graph.
                    // log 會完整記錄那個值，因此當「完整」等於一 MB 時，要說出來。這是
                    // WARN 而不是上限：稽核軌跡不得丟資料，而那個決定誠實的後果就是無界的
                    // 行長度——執行這次編輯的人應該當場聽到，而不是事後在磁碟用量圖上發現。
                    for v in [old, r.fields[c].value] where Logger.shared.logValueIsLarge(column: name, value: v) {
                        Logger.shared.warn("record \(r.number) column \(name): a value of \(v.count) bytes is being written to the log in full; the log is not truncated")
                    }
                    Logger.shared.info("update \(r.number):\(name): \(Logger.shared.redact(column: name, value: old)) -> \(Logger.shared.redact(column: name, value: r.fields[c].value))")
                }
            }
            if let cols = blanks[r.number] {
                touched.insert(r.number)
                for colToken in cols {
                    let c: Int
                    let name: String
                    if let h0 = addressHeader ?? headers.first {
                        c = try resolveColumn(colToken, header: h0)
                        name = baseName(headerName(h0.fields[c]))
                    } else if let numeric = Int(colToken), numeric >= 1 {
                        c = numeric - 1
                        name = colToken
                    } else {
                        throw fault("\(colToken): this file has no header row, so a column can only be addressed by NUMBER here",
                                    "\(colToken)：這個檔案沒有標頭列，因此在這裡只能以「編號」定址欄位")
                    }
                    // Blanking, never removing. Actually dropping the field
                    // would leave that record one column short and shift every
                    // later field left, so status_notes appears under license
                    // -- silently.
                    // 只清空，絕不移除。真的把欄位拿掉會讓該列少一欄、後面所有
                    // 欄位往前位移，於是 status_notes 出現在 license 底下——
                    // 而且是靜默的。
                    // The value goes into the log BEFORE it is discarded.
                    // `-update` records old -> new, and the README promises
                    // "old and new values in an ordinary column -- in full,
                    // never truncated"; blanking a cell destroys exactly such
                    // a value, so it is logged the same way.
                    // 值在被丟棄「之前」進入 log。`-update` 記錄 old -> new，而 README 承諾
                    // 「一般欄位的新舊值——完整、絕不截斷」；清空一個儲存格銷毀的正是那樣一個值，
                    // 因此以同樣的方式記錄。
                    let gone = r.fields[c].value
                    r.fields[c].set([])
                    // `-> ""`, not a bare `->`. The grammar the log promises is
                    // old and new each wrapped in quotes, including for the
                    // one verb whose new value is always empty. A parser
                    // reading `-> ` cannot tell an empty value from a
                    // truncated line.
                    // 用 `-> ""`，不是光禿禿的 `->`。log 承諾的文法是「新舊值各自加引號」，那個
                    // 「新值永遠是空的」動詞也不例外。一個讀到 `-> ` 的解析器，分不出「空的值」
                    // 與「被截斷的一行」。
                    Logger.shared.info("blank \(r.number):\(name): \(Logger.shared.redact(column: name, value: gone)) -> \"\"")
                }
            }
            if let h0 = headers.first { try applyTransform(transform, to: &r, header: h0) }
            // Last, so that every index above still refers to the input. The
            // field-count check, the column names in the log, and the
            // transform all read the original shape; only what is written out
            // is narrower.
            // 放在最後，讓上面每一個索引都仍指向輸入。欄位數檢查、日誌裡的欄位名稱、
            // 以及轉換全都依原本的形狀讀取；只有真正寫出去的東西變窄。
            dropColumns(&r)
            try addColumns(&r, headerRow: nil)
            emitData(r)
            return true
        } catch {
            pendingError = error
            return false
        }
    }

    // One read loop for the whole stream. The header rows are just the first
    // `headerRows` records the parser produces, handled in the sink above.
    // 整份串流只有一個讀取迴圈。標頭列就是解析器吐出的前 `headerRows` 筆，
    // 由上面的 sink 處理。
    while !parser.stopped, let chunk = plan.source.next() {
        try parser.feed(chunk)
    }
    if !parser.stopped { try parser.finish() }
    if let e = pendingError { throw e }

    if headers.count < plan.headerRows {
        throw fault("\(plan.describedPath): expected \(plan.headerRows) header row(s), found \(headers.count)",
                    "\(plan.describedPath)：預期 \(plan.headerRows) 列標頭，實際只有 \(headers.count) 列")
    }

    for row in appends {
        let rec = try parseRowLiteral(row, format: plan.format, expected: expectedFields,
                                      what: "-append")
        emitData(rec, fromInput: false)
        total += 1
        Logger.shared.info("append record \(total)")
    }

    // Out of range is an ERROR, never "grow the file to fit". `-update 99:3`
    // on a 20-record file must fail rather than invent 79 empty records.
    // Because the output is a temp file that is only renamed on success,
    // failing here leaves the original untouched.
    // 越界是錯誤，絕不是「自動長大」。在 20 筆的檔案上 `-update 99:3` 必須失敗，
    // 而不是補出 79 筆空紀錄。由於輸出是成功才 rename 的暫存檔，此處失敗時
    // 原檔完好。
    var bad: [String] = []
    for k in inserts.keys where k > total { bad.append("-insert \(k)") }
    for (a, b) in deletes where a > total || (b != Int.max && b > total) {
        bad.append(b == Int.max ? "-delete \(a)," : "-delete \(a),\(b)")
    }
    for k in updates.keys where k > total { bad.append("-update \(k):…") }
    for k in blanks.keys where k > total { bad.append("-delete -cell \(k):…") }
    if !bad.isEmpty {
        // -insert past the end has a right answer, so the message names it:
        // someone holding this refusal has no reason to go looking for the
        // README sentence about -append. Only for -insert: -update and -delete
        // past the end have no equivalent, and offering one would be advice to
        // do something else.
        // 「-insert 越過結尾」是有正解的，所以訊息會說出來：拿著這則拒絕的人，沒有理由會去翻到
        // README 裡關於 -append 的那一句。只對 -insert 加，因為 -update 與 -delete 越界沒有對應的
        // 正解，硬給一個等於是叫人去做別的事。
        let hint = bad.contains { $0.hasPrefix("-insert") }
            ? ". To add a record at the end, use -append" : ""
        let hintZh = bad.contains { $0.hasPrefix("-insert") }
            ? "。要在最後加一筆，請用 -append" : ""
        throw fault(
            "\(bad.joined(separator: ", ")) is out of range; the file has \(total) records and csv2 does not create empty ones to fill the gap\(hint)",
            "\(bad.joined(separator: "、")) 超出範圍；本檔案有 \(total) 筆紀錄，csv2 不會補出空紀錄來填補\(hintZh)")
    }

    // Close the INPUT before the rename, not at function exit.
    //
    // POSIX lets you rename over a file somebody still has open; Windows does
    // not -- MoveFileExW returns error 5, ACCESS_DENIED. `defer { plan.source
    // .close() }` runs when the function returns, which is AFTER sink.close()
    // has renamed, so on Windows every `--in-place` edit and every `-o` write
    // would fail there. On macOS and Linux the ordering does not matter, so
    // only a Windows run shows it.
    //
    // The defer stays: this is belt and braces, and ByteSource.close is safe to
    // call twice.
    //
    // 在 rename「之前」關閉輸入，而不是等到函式結束。
    // POSIX 允許你 rename 覆蓋一個「還有人開著」的檔案，Windows 不允許——MoveFileExW 回傳
    // error 5（ACCESS_DENIED）。`defer { plan.source.close() }` 在函式回傳時才執行，而那是在
    // sink.close() 完成 rename「之後」，因此在 Windows 上，每一次 `--in-place` 編輯與每一次 `-o`
    // 寫入都會在那裡失敗。在 macOS 與 Linux 上這個順序無關緊要，所以只有在 Windows 上跑才看得到。
    // defer 保留：這是雙保險，而 ByteSource.close 可以安全地被呼叫兩次。
    // The held LF goes out unless the input's last record had none (RK).
    // -append is the exception: the records it adds are new, written by csv2,
    // and end the way every record csv2 writes does -- the same answer the fast
    // path gives, which T202b pins for a file whose last record was cut off.
    // 扣著的 LF 會寫出，除非輸入的最後一筆本來就沒有（RK）。-append 是例外：它加上的紀錄是新的、
    // 由 csv2 寫出，因此和 csv2 寫出的每一筆一樣帶著行尾——與快速路徑給的答案相同，而 T202b 對
    // 「最後一筆被切斷」的檔案釘住了那個答案。
    let heldIsUnterminatedInput = parser.endedWithoutNewline && heldSeenAt == inputRecordsSeen
    if heldLF && (!heldIsUnterminatedInput || heldRecordIsEmpty) { sink.write([BYTE_LF]) }
    plan.source.close()
    try sink.close()
    aborted = false

    if o.dryRun {
        // Not `print()`: on Windows that goes through the CRT's text-mode
        // stdout and turns the LF into CRLF, while every data path here emits
        // LF. Same program, same stream, two line endings. KT.
        // 不用 `print()`：在 Windows 上它走的是 CRT 的文字模式 stdout，會把那個 LF 換成 CRLF，
        // 而這裡每一條資料路徑輸出的都是 LF。同一支程式、同一條流、兩種行尾。KT。
        for change in dryRunChanges { Platform.writeStdout(change + "\n") }
    }

    // After the data file is renamed into place, never before. Interrupted
    // between the two, the index is absent or fails validation, and both fall
    // back to scanning. The other order gives an index describing content that
    // does not exist.
    // 在資料檔 rename 就位「之後」才寫，絕不在之前。若在兩者之間被打斷，索引
    // 要嘛不存在、要嘛驗證不過，兩種都會退回掃描。反過來的順序會得到一個描述著
    // 不存在內容的索引。
    if let b = builder, let outPath = o.output, let idx = b.finish(dataPath: outPath) {
        idx.save(dataPath: outPath)
    }
    // The counts describe what was WRITTEN, not what was read. `total` and
    // `expectedFields` are the input's shape: after `-delete 1,2 -delete -col
    // 7` they would say "22 records, 7 fields" for a file holding 20 and 6, in
    // the one audit line that summarises the result.
    //
    // `outRecords` is incremented in emitData, so it counts records that
    // reached the sink; `headers[0]` has already had its dropped columns
    // removed by the time this runs, so its width is the output's.
    //
    // 這兩個數字描述的是「寫出了什麼」，不是「讀進了什麼」。`total` 與 `expectedFields` 是「輸入」
    // 的形狀：在 `-delete 1,2 -delete -col 7` 之後，它們會說「22 筆、7 欄」，而檔案裡是 20 筆、6 欄
    // ——錯在稽核軌跡裡「總結結果」的那一行。
    //
    // `outRecords` 在 emitData 裡遞增，因此它數的是「真的到達輸出端」的紀錄；而執行到這裡時，
    // `headers[0]` 已經移除過被刪掉的欄位，所以它的寬度就是輸出的寬度。
    if o.dryRun {
        Logger.shared.info("dry run: \(dryRunChanges.count) change(s), wrote nothing")
    } else {
        Logger.shared.info("wrote \(outRecords) records, \(headers.first?.count ?? expectedFields) fields, atomic rename OK")
    }
    // A metrics: line on every path, edits included: --in-place edits are the
    // runs whose cost a caller most wants to see.
    // 每一條路徑都有一行 metrics，編輯也不例外：--in-place 編輯正是呼叫端最想看到成本的執行。
    Metrics.report(bytesRead: plan.source.bytesRead,
                   fileSize: o.input.flatMap { Int(FileStamp.of(path: $0)?.size ?? 0) } ?? 0)
}

// ---------------------------------------------------------------------
// MARK: - The -append fast path / -append 快路徑
// ---------------------------------------------------------------------

/// Every other edit rewrites the whole file, and rewriting is what makes them
/// atomic. Appending is the one operation where the data itself can be written
/// incrementally, so it is the one that gets an O(1) path: adding a record to
/// a 1 GiB file takes milliseconds instead of a full rewrite. A build log that
/// gains a row on every build is exactly this shape.
/// 其餘的編輯都要重寫全檔，而重寫正是它們原子性的來源。追加是唯一「資料本身
/// 也能增量寫入」的操作，因此只有它值得一條 O(1) 路徑：對 1 GiB 的檔案加一筆
/// 只要毫秒級，而不是重寫全檔。每次建置都追加一列的建置紀錄，正是這個形狀。
func canUseAppendFastPath(_ o: Options) -> Bool {
    guard o.edits.count >= 1, o.input != nil else { return false }
    // DECLINE a .md. openInput() carries the rule that a `.md` with
    // `--headers 0` is prose read line by line, and that a `.md` table is
    // TRANSLATED before any parser sees it. This path resolves the format
    // itself, so without this a comma in prose would make `-append` refuse a
    // file `-insert` accepts with the same flag. QJ.
    //
    // 對 `.md` **退讓**。openInput() 帶著這條規則：一個 `.md` 加上 `--headers 0` 是「散文、逐行
    // 讀」，而一張 `.md` 表格在任何解析器看到它之前會先被**翻譯**。這條路徑自己解析格式，少了這一
    // 行，一個散文裡的逗號會讓 `-append` 拒絕一個 `-insert` 在同一個旗標下接受的檔案。QJ。
    //
    // Declining rather than copying the rule here: a third implementation of
    // one rule is how the two drift apart, and byte-wise appending cannot
    // serve a format that is translated before it is parsed. The ordinary
    // edit path handles both correctly.
    // 這裡選擇**退讓**而不是把那條規則抄過來：同一條規則的第三份實作，正是讓它們分歧的原因，
    // 而「逐位元組追加」也服務不了一個「被解析之前先被翻譯」的格式。正常的編輯路徑兩者都處理
    // 得正確。
    if let p = o.input, p.lowercased().hasSuffix(".md") { return false }
    guard o.encryptCols == nil, o.decryptCols == nil, o.hashCols == nil else { return false }
    // What decides this is whether the run is an in-place append, and o.inPlace
    // answers that directly. Do not compare the two PATHS (the DP mistake):
    // `--in-place` sets o.output to the symlink-resolved path, and
    // resolvingSymlinksInPath() also normalises -- a relative path becomes
    // absolute, and on macOS /private/tmp becomes /tmp -- so a relative
    // `-append -i data.csv --in-place` would silently rewrite the whole file.
    // T43d alone cannot catch that, because it passes a canonical absolute
    // path. `-o` naming the input is refused in main.swift, so nothing else
    // can reach this path by accident.
    // 決定這件事的是「這是不是一次就地追加」，而 o.inPlace 直接回答了。不要比較兩個「路徑」
    // （DP 那個錯）：`--in-place` 會把 o.output 設成解析過 symlink 的路徑，而
    // resolvingSymlinksInPath() 同時也會正規化——相對路徑變絕對，macOS 上 /private/tmp
    // 變 /tmp——於是相對路徑的 `-append -i data.csv --in-place` 會靜默重寫整個檔案。光靠 T43d
    // 抓不到，因為它傳的是正規形式的絕對路徑。`-o` 指向輸入在 main.swift 已被拒絕，因此沒有別的
    // 東西會意外走到這裡。
    guard o.inPlace else { return false }
    for e in o.edits {
        if case .append = e { continue }
        return false
    }
    return true
}

func runAppendFast(_ o: Options) throws {
    let path = o.input!
    // Resolved the way the READ path resolves it, and for the same reason it
    // does: `--headers N` says how many header ROWS there are. It does not say
    // what separates fields -- only a suffix does that, which is why
    // `--headers 0` on a `.csv` is a headerless CSV and not lines.
    //
    // Do not derive the format from --headers, as in
    //
    //     Format.from(path:) ?? o.headersOverride.map { $0 == 2 ? .csv2 : .csv } ?? .lines
    //
    // `0` is a value, so the map fires and `.lines` becomes unreachable
    // whenever --headers is given: `beta, gamma, delta` would parse as three
    // fields against a one-field header the flag said does not exist, and
    // appending in place would refuse a file that reads correctly. QS.
    //
    // 用**讀取路徑那一份**的解析，理由也和它相同：`--headers N` 說的是「有幾列標頭」，它不說
    // 「欄位靠什麼分開」——那是副檔名的事，也正是「`--headers 0` 配 `.csv` 是無標頭 CSV 而不是
    // lines」的理由。
    //
    // 不要從 --headers 推導格式（如上面那個形狀）：`0` 是一個值，那個 map 會觸發，只要給了
    // `--headers`，`.lines` 就永遠到不了。`beta, gamma, delta` 會被解析成三欄、去和一個「該旗標說
    // 不存在」的一欄標頭比對，於是一個讀得正確的檔案，就地追加時會被拒絕。QS。
    //
    // The chain ends in `.lines`, so it is never nil and needs no "declares no
    // format" guard; a refusal that cannot fire reads, to a maintainer, like
    // a case that has been considered.
    // 這一串以 `.lines` 結尾，永遠不會是 nil，因此不需要「declares no format」的守衛；一道不可能
    // 觸發的拒絕，對維護的人而言，讀起來像是「這個情況已經被考慮過了」。
    let fmt = Format.from(path: path) ?? .lines
    let headerRows = o.headersOverride ?? fmt.headerRows

    guard FileManager.default.fileExists(atPath: path) else {
        // Silently creating a header-less file would produce a file that lies
        // about its own format, the same reason -head refuses to.
        // 無聲地建立一個沒有標頭的檔案，會產生一個對自己格式說謊的檔案——
        // 與 -head 拒絕的理由相同。
        throw fault("\(path) does not exist; -append will not create a file with no header row",
                    "\(path) 不存在；-append 不會建立一個沒有標頭列的檔案")
    }

    // Read only the front of the file to learn the field count. O(1) in file
    // size, so the fast path stays fast.
    // 只讀檔案開頭以取得欄數，成本與檔案大小無關，快路徑因此仍然快。
    var headers: [Record] = []
    let head = try ByteSource(path: path, chunkSize: 1 << 16)
    let headParser = RecordParser(format: fmt) { r in
        headers.append(r)
        return headers.count < headerRows
    }
    while headers.count < headerRows, let c = head.next() { try headParser.feed(c) }
    if headers.count < headerRows { try? headParser.finish() }
    head.close()
    try validateHeaders(headers, want: headerRows, path: path)
    // With no header row there is nothing to take a width from: one column, by
    // definition. Reaching for row 0 here and on the line below would trap on
    // a file that has no header.
    // 沒有標頭列時，沒有東西可以拿來取寬度：依定義就是一欄。在這裡、以及下面那一行伸手去拿第 0
    // 列，遇到沒有標頭的檔案就會 trap。
    let expected = headers.first?.count ?? 1

    // The fast path never reaches runEdit, so the refusal has to be repeated
    // here rather than relied on, with the same function. `-append
    // --in-place` is the path most likely to be used on a big protected file,
    // and without this it would write plaintext into an encrypted column at
    // rc=0. Cheap here: the header is already read.
    // 快路徑不會走到 runEdit，因此這條拒絕必須在此重複一次、用同一個函式，而不是指望它。
    // `-append --in-place` 是最可能被用在大型受保護檔案上的那條路徑，少了這裡，它會以 rc=0 把明文
    // 寫進加密欄。在這裡做很便宜：標頭本來就已經讀進來了。
    let protFast: (columns: [(Int, String)], anyEncrypted: Bool) =
        headers.first.map { protectedColumns($0) } ?? (columns: [], anyEncrypted: false)
    if !protFast.columns.isEmpty {
        throw rawRowWriteRefusal(verbs: ["-append"],
                                 columns: protFast.columns.map { $0.1 },
                                 anyEncrypted: protFast.anyEncrypted)
    }

    // Load the index BEFORE writing. Validation compares against the file as
    // it is now, so an index loaded after the append would always look stale
    // and could never be updated -- the sidecar would silently die on the
    // first append and every later read would go back to scanning.
    // 在寫入「之前」載入索引。驗證比對的是當下的檔案，因此追加之後才載入的索引
    // 永遠看起來是過期的，也就永遠無法更新——sidecar 會在第一次追加時靜默失效，
    // 之後每次讀取都退回掃描。
    let existingIndex = o.noIndex ? nil : CSVIndex.load(dataPath: path)

    guard let h = FileHandle(forUpdatingAtPath: path) else {
        throw fault("cannot open \(path) for appending", "無法開啟 \(path) 以追加")
    }
    defer { try? h.close() }
    let size = h.seekToEndOfFile()

    // Validated on EVERY fast-path append, not only when the file lacks a
    // trailing newline. A missing final newline is not the only sign of a
    // half-written last record: a record ending inside an unclosed quote
    // contains newlines like any other prose, so the file ends with `\n` and
    // is still open:
    //
    //     id,name,note
    //     r1,n1,"ok"
    //     r2,n2,"unclosed<LF>          <- ends with a newline, record is open
    //
    // `-o` refuses this. Unchecked, `--in-place` -- the only destination the
    // fast path serves -- would write at rc=0 a file csv2 cannot read back,
    // and the unclosed quote would swallow the appended record, so the
    // documented repair, --truncate-partial, would discard the very record
    // just written.
    //
    // The cost is a scan the fast path was built to avoid. It is paid because
    // the alternative is a write reported as successful that produces a file
    // this tool refuses to read -- the exact failure csv2 exists to prevent,
    // and the one the README claims is checked "for -o and for --in-place
    // alike".
    //
    // 每一次走快路徑的追加都會驗證，不只在「檔案沒有結尾換行」時才驗。缺少結尾換行不是「最後
    // 一筆只寫了一半」的唯一跡象：一筆停在未關閉引號裡的紀錄，和任何散文一樣會含有換行，因此
    // 檔案以 `\n` 結尾，而那一筆仍然是開著的。
    //
    // `-o` 會拒絕它。不檢查的話，`--in-place`——快路徑唯一服務的目的地——會以 rc=0 寫出一個
    // csv2 自己讀不回來的檔案，而未關閉的引號會把被追加的紀錄吞進去，於是文件指定的修復手段
    // --truncate-partial 丟掉的，正是剛剛寫入的那一筆。
    //
    // 代價是一次「快路徑當初就是為了避免它」的掃描。之所以付這個代價，是因為另一個選項是
    // 「一次被回報為成功的寫入，產生一個這個工具自己拒絕讀取的檔案」——那正是 csv2 存在所要
    // 防止的失敗，也正是 README 宣稱「`-o` 與 `--in-place` 一視同仁地檢查」的那一項。
    //
    // Because that scan happens, the fast path is in the same position as
    // every other write path: it has just read the whole file. So it builds
    // an index like the others do, instead of being the one exception.
    //
    // 正因為那次掃描會發生，快路徑就和其他每一條寫入路徑處於同一個位置：它剛剛讀完整個
    // 檔案。因此它像其他路徑一樣建索引，而不是那個唯一的例外。
    let wantsIndex = existingIndex == nil && !o.noIndex && size >= UInt64(indexMinBytes())
    let builder = wantsIndex ? IndexBuilder(isCSV2: fmt == .csv2) : nil
    var fileLineFeeds = 0
    var scanSawCRLFLast = false
    if size > 0 {
        do {
            fileLineFeeds = try withUnsafeMutablePointer(to: &scanSawCRLFLast) { p in
                try validateBeforeAppend(path: path, format: fmt, headerRows: headerRows,
                                         truncatePartial: false, builder: builder,
                                         lastTerminatorWasCRLF: p)
            }
        } catch let e as CSV2Error {
            guard o.truncatePartial else { throw e }
            throw fault(
                "\(e.message) --truncate-partial cannot be honoured by -append: appending adds bytes and cannot remove the incomplete record, so the file would keep it and gain a complete record after it. Write a clean copy first (csv2 -r -t --truncate-partial -i \(path) -o CLEAN), then append to that.",
                "\(e.messageZh) -append 無法接受 --truncate-partial：追加只會加上位元組、無法移除那筆不完整的紀錄，因此檔案會同時保留它、並在其後多出一筆完整的。請先寫出一份乾淨的複本（csv2 -r -t --truncate-partial -i \(path) -o CLEAN），再對那一份追加。")
        }
    }

    // Does this file end its records with CRLF? Appending an LF record to a
    // CRLF file leaves one file written two ways -- csv2 reads it back (record
    // endings are decided per record) and plenty of other tools do not. The
    // fast path writes bytes rather than rewriting the file, so "output is
    // always LF" cannot apply here without changing every other line too;
    // matching what is already there is the only answer that leaves the file
    // internally consistent.
    // 這個檔案的紀錄是以 CRLF 結尾的嗎？把一筆 LF 紀錄追加到一個 CRLF 檔案上，會留下一個
    // 「用兩種方式寫成」的檔案——csv2 讀得回來（紀錄結尾是逐筆判斷的），而很多別的工具不行。
    // 快路徑寫的是位元組、不是重寫整個檔案，因此「輸出一律用 LF」在這裡無法適用，除非把其他
    // 每一行也一起改掉；配合檔案「已經是的樣子」，是唯一能讓它保持自身一致的答案。
    // Is the file's last record terminated at all? Asked once, used twice:
    // here, and below where the missing LF is supplied.
    // 這個檔案的最後一筆有沒有終止符？只問一次，用兩次：在這裡，以及下面「補上那個缺掉的 LF」
    // 的地方。
    var lastByteIsLF = false
    if size > 0 {
        h.seek(toFileOffset: size - 1)
        lastByteIsLF = [UInt8](h.readData(ofLength: 1)).first == BYTE_LF
    }
    var endsWithCRLF = false
    if size >= 2 {
        h.seek(toFileOffset: size - 2)
        let tail = [UInt8](h.readData(ofLength: 2))
        endsWithCRLF = tail == [BYTE_CR, BYTE_LF]
    }
    // The last two bytes answer this only when the file's last record is
    // TERMINATED. On a CRLF file whose tail is not -- an exporter cut off, a
    // torn write, anything that ends mid-record -- they are the last two bytes
    // of a value, so the probe would say LF and the append would write LF into
    // a file where every other record ends CRLF. The scan above has already
    // read the whole file and knows what its last terminator was; use that
    // when the tail has none.
    // 只有在「檔案最後一筆有終止符」時，那兩個位元組才回答得了這個問題。一個 CRLF 檔案的尾巴
    // 若沒有終止符——匯出程式被切斷、寫入撕裂、任何停在紀錄中間的情況——那兩個位元組就是某個
    // 「值」的最後兩個位元組，探測會說「LF」，追加就會把 LF 寫進一個「其他每一筆都以 CRLF 結尾」
    // 的檔案。上面那次掃描已經讀過整個檔案，知道它最後一個終止符是什麼；尾巴沒有終止符時就用它。
    if !endsWithCRLF, !lastByteIsLF, scanSawCRLFLast {
        endsWithCRLF = true
    }
    // The encoder always terminates a record with LF, and it is the same
    // encoder every write path uses -- so the ending is adjusted here, on the
    // final byte only. A record may hold LFs of its own inside quotes and
    // those are data.
    // 編碼器一律以 LF 結束一筆紀錄，而那是每一條寫入路徑共用的同一個編碼器——因此在這裡調整
    // 行尾，而且只動最後一個位元組。一筆紀錄的引號內可能有它自己的 LF，那些是資料。
    func terminated(_ bytes: [UInt8]) -> [UInt8] {
        guard endsWithCRLF, bytes.last == BYTE_LF else { return bytes }
        return bytes.dropLast() + [BYTE_CR, BYTE_LF]
    }

    var prefix: [UInt8] = []
    if size > 0 {
        if !lastByteIsLF {
            if fmt == .csv2 {
                // .csv2 guarantees an LF-terminated line per record, so a
                // missing final LF is evidence of a torn write, not just an
                // untidy file. checkTornAppend has already reported it unless
                // --truncate-partial was given.
                // .csv2 保證每筆一行且以 LF 結尾，因此缺少結尾 LF 是撕裂寫入的
                // 證據，而不只是檔案不整齊。除非給了 --truncate-partial，
                // checkTornAppend 已經報過錯了。
                try checkTornAppend(path: path, format: fmt, truncatePartial: o.truncatePartial)
            }
            // Reached for every format. Logged so the supplied newline is
            // visible rather than a mystery in the output.
            // 每一種格式都會走到。記錄下來，讓那個「補上一個換行」的決定是看得見的。
            Logger.shared.debug("append: \(path) does not end with a newline, so a line feed is written before the new record")
            // .csv makes no such promise -- plenty of tools emit a file with
            // no trailing newline. Add one, or the new record gets glued onto
            // the tail of the last one and two records become one.
            // .csv 沒有這個承諾——很多工具產生的檔案就是沒有結尾換行。必須補上
            // 一個，否則新紀錄會被接到最後一筆的尾巴上，兩筆變成一筆。
            // And the terminator supplied here follows the file too: adding a
            // bare LF to a CRLF file leaves the record before the appended one
            // ending differently from every other record in it.
            // 而在這裡補上的那個終止符同樣跟著檔案走：對一個 CRLF 檔案補上一個裸 LF，
            // 會讓「被追加那一筆的前一筆」的結尾與檔案裡其他每一筆都不同。
            prefix = endsWithCRLF ? [BYTE_CR, BYTE_LF] : [BYTE_LF]
        }
    }

    var payload = prefix
    for e in o.edits {
        guard case .append(let row) = e else { continue }
        // Validate BEFORE writing. Unlike the rewrite path, where a failure
        // just discards a temp file, here what is written cannot be taken back.
        // 寫入之前先驗證。與重寫路徑不同——那裡失敗只是丟掉暫存檔，這裡寫下去
        // 就收不回來了。
        let rec = try parseRowLiteral(row, format: fmt, expected: expected, what: "-append")
        // Same encoder as every other write path, so the fast path cannot
        // drift away from the escaping rules.
        // 與其他寫入路徑用同一個編碼器，快路徑因此不會偏離跳脫規則。
        payload.append(contentsOf: terminated(FieldEncoder.encodeRecord(rec, format: fmt, preserveRaw: false)))
    }

    // Where each appended record will start, needed before the write so the
    // index can be updated afterwards without a scan.
    // 每一筆追加紀錄的起始位置，必須在寫入前算好，索引才能在事後無須掃描地更新。
    var appendOffsets: [UInt64] = []
    do {
        var at = size + UInt64(prefix.count)
        for e in o.edits {
            guard case .append(let row) = e else { continue }
            appendOffsets.append(at)
            let rec = try parseRowLiteral(row, format: fmt, expected: expected, what: "-append")
            at += UInt64(terminated(FieldEncoder.encodeRecord(rec, format: fmt, preserveRaw: false)).count)
        }
    }

    // `--backup` matters most on this path: an append changes the original
    // inode directly and has no temp+rename to fall back on, and this O(1)
    // path deliberately bypasses runEdit, where the other backups are made.
    // Validate and encode everything first; then copy the exact pre-append
    // bytes immediately before the first write. KG, T224.
    // `--backup` 最需要保護的正是這條路：追加直接改原 inode，沒有 temp+rename 可以退回，而這條
    // O(1) 路徑刻意繞過建立其他備份的 runEdit。先完成全部驗證與編碼，再於第一次寫入正前方複製
    // 「追加前」的精確位元組。KG、T224。
    try h.close()
    if o.backup { try makeInPlaceBackup(path) }

    // ONE write() through a descriptor opened O_APPEND. POSIX makes the offset
    // update and the write atomic there, so two concurrent appends cannot land
    // on the same offset.
    //
    // Not `seek(toFileOffset: size)` then `write` -- seek-to-computed-end, the
    // construction the log file avoids for the same reason. Two appends racing
    // on one file would both write at the same offset, and the shorter write
    // would land on top of the longer one:
    //
    //   * the tail of the overwritten row survives as a record NOBODY WROTE --
    //     `A,BBBB` from a row that was `AAAA,BBBB` -- and the file reads back
    //     clean at rc=0 with a fabricated record in it;
    //   * or the leftover byte is a bare newline, and csv2's own blank-line
    //     rule then refuses the file it has just written, with both writers
    //     at rc=0 and both logging success.
    //
    // The README's worst case for concurrent writers is "one edit is lost";
    // that construction can lose both, invent a record, or destroy a file.
    //
    // 一次 write()，走的是以 O_APPEND 開啟的描述子。POSIX 保證那裡的偏移量更新與寫入是
    // 原子的，因此兩個並行的追加不可能落在同一個偏移量上。
    //
    // 不要用 `seek(toFileOffset: size)` 再 `write`——「先算出檔尾再寫到那裡」，正是 log 檔為了
    // 同一個理由而避開的構造。兩個追加在同一個檔案上競賽時，兩者會寫在同一個偏移量上，較短的
    // 那次寫入蓋在較長的那次上面：被蓋掉那一列的尾巴，會以「沒有任何人寫過的一筆紀錄」活下來，
    // 而檔案以 rc=0 乾乾淨淨地讀得回來；或者剩下的是一個裸換行，而 csv2 自己的空白行規則
    // 會拒絕它剛剛寫出來的那個檔案——兩個寫入者都以 rc=0 結束，都記下了成功。
    //
    // README 對並行寫入者的最壞情況是「有一次編輯會遺失」；那個構造則可能兩次編輯都遺失、
    // 憑空造出一筆紀錄，或毀掉一個檔案。
    guard let afd = Platform.openAppendFD(path: path) else {
        throw fault("cannot open \(path) for appending", "無法開啟 \(path) 以追加")
    }
    let werr = Platform.writeAll(fd: afd, payload)
    Platform.closeFD(afd)
    if werr != 0 {
        throw fault("cannot write to \(path): \(Platform.errorText(werr))",
                    "無法寫入 \(path)：\(Platform.errorText(werr))")
    }
    Logger.shared.info("append fast path: wrote \(payload.count) bytes to \(path) (file was \(size) bytes)")

    // Did another process append during this one? O_APPEND keeps both writes
    // whole, so the DATA is fine either way -- but the offsets computed above
    // are then wrong for the index, and an index that is wrong about where
    // records start is worse than no index at all. The size is the evidence,
    // and it is one stat.
    // 在這次追加的同時，有別的行程也追加了嗎？O_APPEND 讓兩次寫入各自完整，因此「資料」無論如何
    // 都是好的——但上面算出來的那些偏移量對索引就不對了，而一份「說錯紀錄從哪裡開始」的索引，
    // 比沒有索引更糟。檔案大小就是證據，而那只要一次 stat。
    // The append path reads the whole file to validate it (see above), so the
    // bytes it read are the file as it was before this write.
    // 追加路徑會把整個檔案讀過一遍來驗證它（見上文），因此它讀到的位元組數，就是「這次寫入
    // 之前」的那個檔案。
    Metrics.report(bytesRead: Int(size), fileSize: Int(size))

    var raced = false
    if let now = Platform.fileIdentity(path: path), now.size != size + UInt64(payload.count) {
        raced = true
        Logger.shared.warn("another process appended to \(path) during this append; both records are whole, but the index beside it was left alone because the offsets this run computed are no longer where its records start")
    }

    // Data first, then the index. Interrupted between them the index is stale,
    // which validation catches and turns into a scan -- a safe downgrade.
    // 先寫資料，再更新索引。中間被打斷的話索引是過期的，會被驗證擋下並退回掃描
    // ——安全的降級。
    // The physical line the first appended record starts on, from the file's
    // own bytes rather than from the index.
    //
    // Not `Int(idx.lastLine) + prefix.count`: `lastLine` is documented in
    // Index.swift as the line the LAST record STARTS on, so the sum is short
    // by however many lines that record itself occupies -- at least one, more
    // when it carries newlines inside quotes -- and a wrong line would reach
    // the sidecar.
    //
    // The line feeds are counted by the scan above, so this is exact: a file
    // ending in LF has that many complete lines and the next record starts on
    // the one after; a file not ending in LF gets the prefix LF that completes
    // its last line, which `prefix.count` adds.
    //
    // 被追加的第一筆紀錄從哪一個實體行開始，由檔案自己的位元組決定，而不是由索引決定。
    //
    // 不是 `Int(idx.lastLine) + prefix.count`：`lastLine` 在 Index.swift 裡的定義是「最後一筆
    // 『開始』的那一行」，因此這個和會少掉那一筆自己佔掉的行數——至少一行，引號內含換行時更多
    // ——錯的行號就會進到 sidecar。
    //
    // 換行數由上面那次掃描順手數好，因此這是精確值：以 LF 結尾的檔案有那麼多完整的行，
    // 下一筆從再下一行開始；不以 LF 結尾的檔案會得到那個補上的 LF 來把最後一行補完，
    // 而那正是 `prefix.count` 加進去的。
    let firstAppendedLine = fileLineFeeds + 1 + prefix.count

    /// Walks the payload once, handing back each appended record's number,
    /// offset, starting line and how many lines it occupies. Both the
    /// extend-an-index and the build-an-index branch need exactly this, and
    /// having it twice is how the two would drift apart.
    /// 走過 payload 一次，交出每一筆被追加紀錄的編號、偏移量、起始行，以及它佔掉幾行。
    /// 「延續索引」與「建立索引」兩條分支要的正好是同一份資料，寫兩次就是它們日後分岔的方式。
    func appendedRecords(startingAt firstNumber: Int) -> [(n: Int, off: UInt64, line: Int, lines: Int)] {
        var out: [(n: Int, off: UInt64, line: Int, lines: Int)] = []
        var line = firstAppendedLine
        var n = firstNumber
        var cursor = prefix.count
        for off in appendOffsets {
            let start = cursor
            var end = start
            var seen = 0
            while end < payload.count {
                if payload[end] == BYTE_LF { seen += 1 }
                end += 1
                if seen == 1 && end > start { break }
            }
            let lines = payload[start..<end].filter { $0 == BYTE_LF }.count
            out.append((n: n, off: off, line: line, lines: max(lines, 1)))
            line += lines
            n += 1
            cursor = end
        }
        return out
    }

    if raced {
        // Nothing here can be trusted to describe the file that now exists.
        // 這裡沒有任何東西可以被信任來描述「現在存在的那個檔案」。
    } else if let b = builder {
        for r in appendedRecords(startingAt: b.recordCount + 1) {
            b.add(record: r.n, at: r.off, line: UInt64(r.line), spansLines: r.lines > 1)
        }
        // finish() stamps the file, so it has to run AFTER the write -- an
        // index stamped before the append describes a file that no longer
        // exists and is discarded on the next read, which is safe and useless.
        // finish() 會為檔案蓋戳記，因此必須在寫入「之後」執行——在追加之前蓋的戳記描述的是
        // 一個已經不存在的檔案，下次讀取時會被丟棄：安全，但毫無用處。
        if let idx = b.finish(dataPath: path) {
            if idx.save(dataPath: path) {
                Logger.shared.info(
                    "append fast path: built the index beside \(path) from the scan it had to do anyway: \(idx.records) records, \(idx.offsets.count) grid points")
            }
        }
    } else if let idx = existingIndex {
        // A record that spans lines makes `no_embedded_newlines` false, and
        // this path updates the count, the offsets and the freshness stamp, so
        // it must update that claim too.
        //
        // Otherwise this is T79's defect by another door: an index asserting
        // a property of the file that nothing re-derived. The O(1) check
        // passes -- the stamp is current, because this path just refreshed it
        // -- `-contains` takes the parallel path, and every record after the
        // first chunk boundary past the appended one is numbered one too high,
        // at rc=0; the README's find-then-edit recipe then writes into the
        // wrong row. This in-place fast path is the only one that edits an
        // index rather than rebuilding it, so it is the only one exposed.
        //
        // Counting line feeds is enough: every appended record ends with
        // exactly one, so more of them than records means at least one record
        // carries a newline inside a quoted field.
        //
        // 一筆跨行的紀錄會讓 `no_embedded_newlines` 變成假的，而這條路徑會更新筆數、偏移量與
        // 新鮮度戳記，因此也必須更新那個宣稱。
        //
        // 否則就是 T79 的缺陷從另一扇門回來：一份索引宣稱了一個「沒有任何東西重新推導過」的檔案
        // 性質。O(1) 檢查會通過——戳記是最新的，因為這條路徑剛剛才更新過它——`-contains` 走上平行
        // 路徑，而「被追加那一筆之後的第一個區塊邊界」以後的每一筆編號都大了一，rc=0；照著 README
        // 那套「先找再改」的寫法做，值會被寫進錯的那一列。就地的快路徑是唯一一條「編輯」索引而不是
        // 重建它的路徑，所以只有它會碰上這件事。
        //
        // 數換行就夠了：每一筆被追加的紀錄都恰好以一個換行結尾，因此換行比筆數多，就代表
        // 至少有一筆在引號欄位裡帶著換行。
        let lfInPayload = payload.filter { $0 == BYTE_LF }.count - prefix.count
        if lfInPayload > appendOffsets.count {
            idx.noEmbeddedNewlines = false
            Logger.shared.info(
                "append: a record spans lines, so the index beside \(path) no longer claims one record per line")
        }
        // Each appended record's starting line, from the bytes actually
        // written. The index carries a line per grid point since v4, and the
        // append path is the one place that extends an index instead of
        // rebuilding it -- so it is the one place that can put a wrong line in
        // one, the same class as the record count in T79.
        // 每一筆被追加紀錄的起始行號，由「實際寫出去的位元組」算出。自 v4 起索引每個格點都帶
        // 一個行號，而追加是唯一一條「延續索引」而非「重建索引」的路徑——因此它也是唯一一個
        // 能把錯的行號放進索引的地方，與 T79 的筆數問題同類。
        for r in appendedRecords(startingAt: Int(idx.records) + 1) {
            idx.noteAppend(record: r.n, at: r.off, line: UInt64(r.line))
        }
        idx.save(dataPath: path)
    }
}

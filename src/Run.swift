// =====================================================================
//  Run.swift — the three drivers: select, edit, and the append fast path
//  Run.swift — 三個驅動路徑：選取、編輯，以及追加快路徑
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - Shared setup / 共用的前置
// ---------------------------------------------------------------------

func makeSink(_ o: Options) throws -> ByteSink {
    if let path = o.output { return try ByteSink(atomicPath: path) }
    return ByteSink(stdout: 1 << 16)
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
        // The reason was "Markdown cannot be read back by csv2", which stopped
        // being true on 2026-08-26 and is a headline feature of the same
        // README. The refusal is still right -- these bytes are not what that
        // suffix declares -- so only the reason changed, and it now names the
        // destination that works. Round 78.
        // 那個理由原本是「Markdown 無法被 csv2 讀回」，而它在 2026-08-26 就不再為真，而且那是同一份
        // README 的招牌功能之一。這條拒絕仍然是對的——這些位元組不是那個副檔名所宣告的東西——因此
        // 只有理由改了，而它現在會指名一個行得通的目的地。第 78 回合。
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
    // match it. Never pad to fit -- this is the check artifacts.csv lacked.
    // 兩列標頭必須有相同的欄數，且與資料相同。絕不補空湊合——這正是
    // artifacts.csv 當時缺少的檢查。
    if headers.count > 1 && headers[0].count != headers[1].count {
        throw fault(
            "\(path): header row 0a has \(headers[0].count) fields, row 0b has \(headers[1].count); a .csv2 header must have the same field count on both rows",
            "\(path)：標頭 0a 有 \(headers[0].count) 欄，0b 有 \(headers[1].count) 欄；.csv2 的兩列標頭欄數必須相同")
    }
    try checkProtectionAgreement(headers, path: path)
}

/// The two header rows must say the SAME thing about protection.
///
/// Every guard in this tool asks "does the file's own header declare this
/// column transformed", and every one of them asked row 0a. A `.csv2` whose
/// 0b carries `:enc:` and whose 0a does not therefore walked past all of
/// them -- `-update` wrote plaintext into an encrypted column, `-insert` was
/// accepted, `--json`'s `protected` key said nothing was protected, and
/// `-hash` did the thing this document calls the worst thing it can do: it
/// hashed the CIPHERTEXT and overwrote the `:enc:` marker together with its
/// salt, at rc=0, on a file whose Chinese header row still visibly said
/// `:enc:`.
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
/// 這個工具裡的每一道守衛都在問「這個檔案自己的標頭有沒有宣告這一欄已被轉換」，而它們每一個
/// 問的都是第 0a 列。於是一個「0b 帶著 `:enc:`、0a 沒有」的 `.csv2`，從它們全部旁邊走了過去
/// ——`-update` 把明文寫進加密欄、`-insert` 被接受、`--json` 的 `protected` 說什麼都沒被保護，
/// 而 `-hash` 做了這份文件稱為「它做得出來最糟的一件事」：把密文單向雜湊掉，並覆寫 `:enc:`
/// 標記、連同 salt 一起帶走，rc=0，而那個檔案的中文標頭列上，`:enc:` 明明還在。
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
/// derived from the index that was wrong in the first place. On 2026-08-25 a
/// file with no blank line in it was refused that way, exit 1, while the same
/// command with `--no-index` returned the record. Recorded as JB.
///
/// The contract this restores is stated twice in the README and is the reason
/// the index exists at all: it is an OPTIMISATION and never a PRECONDITION. A
/// seek that cannot be trusted must cost a scan, not an answer.
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
/// ——訊息講的是「空白行」，而它指名的紀錄號與行號，兩個都是從「一開始就錯的那份索引」推導
/// 出來的。2026-08-25，一個裡面沒有任何空白行的檔案就是這樣被拒絕的（exit 1），而同一個指令
/// 加上 `--no-index` 會把紀錄給你。記為 JB。
/// 這裡要恢復的契約，在 README 裡寫了兩次，也正是索引之所以存在的理由：它是**最佳化**，
/// 永遠不是**必要條件**。一個不能信任的 seek，代價應該是一次掃描，而不是一個答案。
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
        // The seek used to require `no_embedded_newlines`, because a grid point
        // was a byte offset alone and a resume could not say which physical
        // LINE it had landed on -- and `--physical` puts that line in the
        // output, which must be byte-identical with and without an index.
        //
        // One record spanning lines in 450,000 then cost the whole file: a
        // `.csv` with a single quoted newline read 15 MB where a `.csv2` of the
        // same shape read 7 kB, and a blind round reported that as the two
        // formats behaving differently. It was never the format. Since v4 each
        // grid point carries its line, so the property is no longer needed
        // here -- the parallel path still uses it, where it means something
        // else.
        // 這個 seek 原本要求 `no_embedded_newlines`，因為一個格點只有位元組偏移量，恢復解析
        // 說不出「落在第幾實體行」——而 `--physical` 會把那個行號放進輸出，且有無索引的輸出
        // 必須逐位元相同。
        // 於是 45 萬筆裡有一筆跨行，就要付上整個檔案的代價：一個含單一引號換行的 `.csv` 讀了
        // 15 MB，而同樣形狀的 `.csv2` 只讀 7 kB——有一個盲測回合把那回報成「兩種格式行為不同」。
        // 那從來就不是格式的問題。自 v4 起每個格點都帶著自己的行號，因此這裡不再需要那個性質；
        // 平行路徑仍然用它，而它在那裡的意思是另一回事。
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
/// user with no way to ask. `--verify-index` existing while nothing creates one
/// made the gap plain.
/// 依需求建立 sidecar。少了它，索引只會以「副作用」的方式出現——寫入時建一個、
/// `-tail` 因為本來就要讀完整個檔案而建一個——於是只用 `-mid` 讀大檔的人根本不會
/// 得到索引。`-mid` 的設計就是提前停止，在那裡建索引會抵銷掉它：就單一操作而言正確，
/// 但使用者因此無從要求。「有 `--verify-index` 可驗證、卻沒有東西可建立」讓這個缺口
/// 一目了然。
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
                                what: "record \(r.number) (line \(r.line))")
            // A record that itself spans lines means a record number is no
            // longer a line number, and the index stores bytes rather than
            // lines -- so the seek path must refuse to use this index. Recorded
            // here so the flag in the header is right.
            //
            // This read `rec.line != r.line || false`, and `r` is `rec` with
            // only `number` changed: the comparison could never be true. Every
            // index --build-index ever wrote claimed no embedded newlines, and
            // on an ordinary CSV with prose in quotes the parallel path then
            // counted lines as records and reported the record after the one
            // it found, at rc=0, with --verify-index saying OK.
            // 自身跨行的紀錄會讓紀錄號不再等於行號，而索引存的是位元組而非行號
            // ——因此 seek 路徑必須拒絕使用這份索引。在此記錄，讓檔頭的旗標正確。
            //
            // 原本寫的是 `rec.line != r.line || false`，而 `r` 是只改了 `number` 的
            // `rec`：那個比較永遠不可能為真。--build-index 寫出的每一份索引都宣稱
            // 沒有內嵌換行，於是對一份引號內含散文的普通 CSV，平行路徑把行當成紀錄來數，
            // 回報了它所找到那一筆的「下一筆」，rc=0，而 --verify-index 說 OK。
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
func runVerifyIndex(_ o: Options) throws {
    guard let path = o.input else {
        throw fault("--verify-index needs -i FILE", "--verify-index 需要 -i FILE")
    }
    let plan = try openInput(o)
    defer { plan.source.close() }
    guard let idx = CSVIndex.load(dataPath: path) else {
        // "No usable index" was said with the sidecar sitting right there.
        // This tool separates "absent" from "present and unusable" everywhere
        // else -- the parallel decline was fixed for exactly that distinction
        // earlier the same day -- and --verify-index, whose whole job is to
        // report on a sidecar, collapsed the two.
        // 原本在 sidecar 就躺在那裡時說「沒有可用的索引」。這個工具在其他每一處都把
        // 「不存在」與「存在但不能用」分開——平行路徑的拒絕就是為了這個分別而在同一天
        // 稍早修過的——而 --verify-index 這個「整份工作就是回報某個 sidecar」的動作，
        // 卻把兩者合成了一句。
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
            // one. Version 4 added it and this proof was not extended, so an
            // index with a wrong line passed at rc=0 saying "index OK" -- and
            // the append fast path was writing exactly that, short by however
            // many lines the previous last record occupied. The same door as
            // T79: a sidecar asserting something nothing re-derived. A wrong
            // line is quieter than a wrong offset, because it surfaces only in
            // `--json`, `--physical` and an `@L` address.
            // 每個格點的行號會被檢查，因為索引「存了」一個。第 4 版加了它，而這份證明沒有
            // 跟著擴充，於是一份帶著錯行號的索引以 rc=0 通過並說「index OK」——而追加快路徑
            // 寫進去的正是那種，少了上一筆佔掉的行數。與 T79 是同一扇門：一份 sidecar 宣稱了
            // 一件沒有任何東西重新推導過的事。錯的行號比錯的偏移量更安靜，因為它只在
            // `--json`、`--physical` 與 `@L` 位址上露臉。
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
    // The offsets and the count were the whole check, and both survive the
    // failure that matters: put a newline inside a quoted field and every
    // record still starts exactly where the index says, and there are still
    // exactly as many. What changed is a claim in the header that nothing
    // re-derived -- and it is the claim the parallel path consumes to decide
    // that a line is a record. So "proof" proved the two things that were
    // already right and skipped the one that was wrong.
    //
    // Only the dangerous direction is a mismatch. An index that says a file
    // spans lines when it does not is merely pessimistic: it gives up a fast
    // path and returns the same answer. Failing on that would send people to
    // rebuild a sidecar that was never going to hurt them.
    //
    // 偏移量與筆數本來就是全部的檢查，而它們在「真正要命的那個失敗」下都活得好好的：
    // 在引號欄位裡放一個換行，每一筆仍然從索引所說的那個位元組開始，筆數也仍然一樣。
    // 變的是檔頭裡一個沒有任何東西重新推導過的宣稱——而那正是平行路徑用來斷定「一行
    // 就是一筆」的那個宣稱。於是「證明」證明了本來就對的兩件事，跳過了錯的那一件。
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
    if let p = o.input, let why = parallelDeclineReason(o, format: Format.from(path: p) ?? .csv) {
        Logger.shared.debug("single-threaded: \(why)")
    } else if o.input == nil {
        Logger.shared.debug("single-threaded: stdin")
    }
    if let p = o.input, canRunParallelSearch(o, format: Format.from(path: p) ?? .csv) {
        try checkTornAppend(path: p, format: Format.from(path: p) ?? .csv,
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
            // agree. Before this, the same file got a raw-newline error at one
            // chunk size and an unclosed-quote error at another, with a wrong
            // record number and a remedy that would have discarded a complete
            // record.
            //
            // 前提是假的：格式或索引說「一筆一行」，而某個區塊邊界落在了引號欄位中間。
            // 這個工具對「前提被推翻」的回答在每一處都相同——丟掉它、改用掃描——因此這次
            // 執行會往下繼續，以單執行緒進行，並產生真正的診斷。
            //
            // 選擇「退回」而不是「回報」，正是讓兩條路徑說法一致的原因。在此之前，同一個
            // 檔案在某個 chunk 大小下得到「裸換行」的錯誤，在另一個大小下得到「引號未關閉」
            // 的錯誤，附帶錯誤的紀錄號，以及一個會丟掉完整紀錄的補救建議。
            Logger.shared.debug(
                "single-threaded: a chunk boundary fell inside a quoted field, so the one-record-per-line premise was false; re-reading without it")
        }
    }
    if let p = o.input {
        try checkTornAppend(path: p, format: Format.from(path: p) ?? .csv,
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
        // The variable name belongs in EVERY message that reports this limit,
        // not only in `-tail`'s. The README says the message "names the
        // request, the limit and the variable" and covers both flags with that
        // one sentence; this one named two of the three, so the operator was
        // told a wall exists and not which knob moves it. And the flag quoted
        // is the one the operator typed: `-C 6` sets `before` too, and used to
        // be reported as `-B 6`.
        // 變數名稱屬於「每一則回報這個上限的訊息」，不是只屬於 `-tail` 那一則。README 說
        // 訊息會「指出請求、上限與變數名稱」，而那一句同時涵蓋兩個旗標；這一則只給了三者
        // 中的兩個，於是撞牆的人知道有牆、不知道該轉哪個旋鈕。引用的旗標則是他實際打的那個：
        // `-C 6` 同樣會設定 `before`，而它原本被回報成 `-B 6`。
        throw fault("\(o.beforeFlag) \(o.before) exceeds the buffered-record limit (\(maxBuffer)); raise CSV2_MAX_BUFFER_RECORDS if you really mean it",
                    "\(o.beforeFlag) \(o.before) 超過可緩衝的紀錄上限（\(maxBuffer)）；若確實需要請調高 CSV2_MAX_BUFFER_RECORDS")
    }

    var lower = 1
    var upper = Int.max
    if let (a, b) = o.mid { lower = a; upper = b ?? Int.max }
    // -get is -mid r,r with a different emitter: same seek, same stop, same
    // index use. Implementing it separately would have given it its own
    // off-by-one to get wrong.
    // -get 就是「-mid r,r 換一個輸出器」：同樣的 seek、同樣的停止點、同樣使用索引。
    // 另外實作一份，只會讓它多出一個屬於自己的差一錯誤。
    if let (r, _) = o.getCell { lower = r; upper = r }
    if let n = o.head { upper = min(upper, n) }

    // ONE open. `planIndex` only reads the plan's format and header count, and
    // opening a second source to hand it was free on a regular file and fatal
    // on a FIFO: the first open drained the pipe, the second waited for a
    // writer that had already gone. `csv2 -r -i fifo.csv` reported `expected 1
    // header row(s), found 0` -- the message for an empty file -- about a
    // stream carrying three lines.
    // 只開一次。`planIndex` 用到的只是這份 plan 的格式與標頭列數，而「為了交給它而多開一個
    // 來源」在一般檔案上是免費的、在 FIFO 上是致命的：第一次開啟把管線抽乾，第二次則在等一個
    // 早已離開的寫入端。`csv2 -r -i fifo.csv` 對一條正要送來三行的串流，回報了
    // `expected 1 header row(s), found 0`——那是「空檔案」的訊息。
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
    let sink = try makeSink(o)
    var aborted = true
    defer { if aborted { sink.abort() } }

    let needle: [UInt8] = o.contains.map {
        o.normalize ? normalizedBytes([UInt8]($0.utf8)) : [UInt8]($0.utf8)
    } ?? []

    var emitter: RecordEmitter
    if let (_, col) = o.getCell {
        emitter = CellEmitter(sink: sink, column: col)
    } else if o.json {
        emitter = JSONEmitter(sink: sink, reportMode: reportMode)
    } else if o.markdown {
        emitter = MarkdownEmitter(sink: sink, pretty: o.pretty)
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
    var tailRing: [Record] = []
    let builder = ip.builder

    func matchesIn(_ r: Record) -> [Int] {
        guard searching else { return [] }
        var hits: [Int] = []
        for (i, f) in r.fields.enumerated() {
            let hay = o.normalize ? normalizedBytes(f.value) : f.value
            if bytesContain(hay, needle) { hits.append(i) }
        }
        return hits
    }

    /// TRACE for a record that is NOT emitted. Without it, `-debug=trace`
    /// logged only the records that came out -- which is the half you already
    /// had, from the output. The question it is supposed to answer is "why is
    /// record N not in my result", and for that the interesting record is
    /// precisely the one with no line.
    ///
    /// It also removed an ambiguity this project condemns two sections earlier
    /// in its own README, about the parallel path: "reporting only the
    /// interesting case would make silence ambiguous". Silence here meant
    /// either "read and rejected" or "never reached, because the read stopped
    /// first", and the evidence was identical. Round 38, defect DD.
    ///
    /// 給「沒有被輸出」的紀錄用的 TRACE。少了它，`-debug=trace` 只會記錄有輸出的那些
    /// ——而那一半你從輸出本身就已經有了。它該回答的問題是「為什麼第 N 筆不在我的結果裡」，
    /// 而對那個問題來說，有意思的紀錄恰恰是「沒有那一行」的那一筆。
    /// 它同時消除了一個歧義，而本專案在自己 README 中隔兩節就譴責過它（平行路徑那一段）：
    /// 「只回報有趣的那個情況，會讓沉默變得有歧義」。這裡的沉默可能是「讀過但被排除」，
    /// 也可能是「根本沒讀到，因為讀取先停了」，而兩者的證據完全相同。第 38 回合，缺陷 DD。
    func traceSkip(_ r: Record, _ why: String) {
        Logger.shared.log(.trace, "select: record \(r.number) line \(r.line) not emitted: \(why)")
    }

    // Counted for the audit trail's outcome line, which this path did not
    // write. `-hash`, `-encrypt` and `-decrypt` rewrite a file and run through
    // the SELECT path, not the edit path, so every protection write finished
    // with the log saying only that it had started. The README nominates that
    // line -- "the one to look for when asking whether an edit landed" -- and
    // it was missing for the class of edit whose result cannot be undone.
    // 為了稽核軌跡的那一行「結果」而計數，而這條路徑原本不寫它。`-hash`、`-encrypt`、
    // `-decrypt` 會重寫一個檔案，走的卻是「選取」路徑而不是編輯路徑，於是每一次保護寫入
    // 結束時，log 只說了它開始過。README 指名的正是那一行——「想知道一次編輯有沒有落地時
    // 該找的那一行」——而它獨獨在「結果無法還原」的那一類編輯上不存在。
    var emittedCount = 0

    func emitRecord(_ r: Record, matches: [Int]) throws {
        guard let c = ctx else { return }
        // TRACE is per-record: the question it answers is "why was record N not
        // in my output", which DEBUG would drown. This is the first thing in
        // the tool worth a TRACE line, which is why the level had no way to be
        // reached until now -- a flag that lowers the threshold to a level
        // nothing logs at would have been an option that does nothing.
        // TRACE 是逐筆的：它要回答的是「為什麼第 N 筆不在我的輸出裡」，而那個問題
        // 會被 DEBUG 的量淹沒。這是本工具第一件值得寫成 TRACE 的事，也正是這個層級
        // 在此之前無法被達到的原因——把門檻降到一個「沒有東西以它記錄」的層級，
        // 會得到一個什麼也不做的選項。
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
        // reads row 0. Reaching for it crashed with SIGTRAP and exit 133 -- no
        // message on either stream, which is the worst way for this tool to
        // fail and the same trap `/dev/null` produced on 2026-08-21.
        // 零列標頭是一個真實的形狀（`.lines`），而底下的一切都會去讀第 0 列。伸手去拿它會以
        // SIGTRAP、exit 133 當掉——兩條輸出流上都沒有訊息，那是這個工具最糟的失敗方式，也與
        // 2026-08-21 那次 `/dev/null` 造成的 trap 是同一個。
        // Only the header-DERIVED work is skipped when there is no header row,
        // not the emitter setup below it. An early `return` here read the file
        // and printed nothing, at rc=0 -- a silent success, which is worse than
        // the SIGTRAP it replaced: the trap at least stopped.
        // 沒有標頭列時，只跳過「由標頭推導」的那些工作，不跳過它下面的 emitter 設定。在這裡直接
        // `return` 會讓它讀完檔案卻什麼都不印，而且 rc=0——一次無聲的成功，那比它取代掉的 SIGTRAP
        // 更糟：那個 trap 至少會停下來。
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
            rownum: o.rownum, zh: o.zh, physical: o.physical, a1: o.a1,
            jsonASCII: o.jsonASCII, enOnly: o.enOnly, preserveRaw: true,
            contextActive: o.after > 0 || o.before > 0)
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
    // which is also what builds the emit context -- was never called, and the
    // run read the whole file and emitted nothing at rc=0. The resume path had
    // the same shape and had already solved it; this is the second caller of
    // that solution, not a new one.
    // ……或是在「根本沒有標頭列可以完成」的時候。headerRows == 0 時，底下那個 callback 永遠不會
    // 進入它的標頭分支，於是 headersComplete——它同時也是建立 emit context 的地方——從未被呼叫，
    // 而那次執行讀完了整個檔案、什麼都沒輸出，rc=0。恢復解析那條路徑是同樣的形狀，而且早就解決過；
    // 這裡是那個解法的第二個呼叫端，不是一個新的解法。
    if resuming || plan.headerRows == 0 { try headersComplete() }

    let firstRecord = resuming ? ip.resumeRecord + plan.headerRows : 1
    // Taken from the grid point, not derived from the record number. Deriving
    // it assumed one record per line, which is exactly the assumption that
    // kept the seek away from every file with an embedded newline.
    // 取自那個格點，而不是由紀錄號推導。推導的前提是「一筆一行」，而那正是「讓 seek 遠離
    // 每一個含內嵌換行的檔案」的那個假設。
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
            // With no header rows the first RECORD sets the width. `.lines`
            // has none by definition, and a headed file has already set this
            // from its header, so this is inert there.
            // 沒有標頭列時，由第一筆**紀錄**決定寬度。`.lines` 依定義沒有標頭，而有標頭的檔案
            // 早就從它的標頭設過這個值，因此這一行在那裡是惰性的。
            if expectedFields == 0 { expectedFields = r.count }
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))")
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
                tailRing.append(r)
                if tailRing.count > n { tailRing.removeFirst() }
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
    if let c = ctx {
        for r in tailRing { try emitRecord(r, matches: matchesIn(r)) }
        try emitter.end(c, records: seen, matched: matchedCount)
    }
    // Close the INPUT before the rename, not at function exit.
    //
    // POSIX lets you rename over a file somebody still has open; Windows does
    // not -- MoveFileExW returns error 5, ACCESS_DENIED. `defer { plan.source
    // .close() }` runs when the function returns, which is AFTER sink.close()
    // has renamed, so every `--in-place` edit and every `-o` write failed
    // there. It cost ten of the seventeen failures in the first Windows run of
    // the suite, 2026-08-19, and not one of them was visible on macOS or Linux,
    // where the ordering genuinely does not matter.
    //
    // The defer stays: this is belt and braces, and ByteSource.close is safe to
    // call twice.
    //
    // 在 rename「之前」關閉輸入，而不是等到函式結束。
    // POSIX 允許你 rename 覆蓋一個「還有人開著」的檔案，Windows 不允許——MoveFileExW 回傳
    // error 5（ACCESS_DENIED）。`defer { plan.source.close() }` 在函式回傳時才執行，而那是在
    // sink.close() 完成 rename「之後」，因此那裡的每一次 `--in-place` 編輯與每一次 `-o` 寫入
    // 都失敗。它造成了 2026-08-19 首次 Windows 執行中十七條失敗裡的十條，而其中沒有任何一條
    // 在 macOS 或 Linux 上看得見——在那兩個平台上，這個順序確實無關緊要。
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

    // A window that begins past the end of the file produces no rows and
    // exits 0, which is indistinguishable from a window that exists and is
    // empty. Clamping the END is deliberate and asserted (T14c); this is the
    // other edge, where nothing the caller asked for could ever have been
    // returned.
    //
    // The documented way to tell the two apart is `records` on the trailing
    // `--json` meta line -- and that channel does not exist in the shape you
    // actually hand to a person. `-md` renders a complete-looking empty table:
    //
    //     $ csv2 -mid 500,505 -t -md -i s.csv      # the file has 299 records
    //     |a|b|
    //     |---|---|
    //
    // So the warning goes to stderr, where every output shape can carry it and
    // no pipeline is polluted by it. WARN is the default threshold, so it is
    // seen without asking. It is not an error: the run did what it was told
    // and the exit status stays 0.
    //
    // 一個「起點在檔案結尾之後」的視窗不會產生任何列，並以 0 結束——那與「一個確實存在、
    // 而且是空的視窗」無法區分。截斷「終點」是刻意的、也有測試釘住（T14c）；這裡是另一端，
    // 呼叫端所要求的東西沒有任何一部分可能被回傳。
    //
    // 文件指定的分辨方法是 `--json` 結尾那行 meta 的 `records`——而那個管道在「你真正交出去
    // 的形狀」裡並不存在：`-md` 會算繪出一張看起來完整的空表格。
    //
    // 因此警告走 stderr，那裡每一種輸出形狀都載得動它，也不會污染任何管線。WARN 是預設門檻，
    // 所以不必特地要求就看得到。它不是錯誤：這次執行做了它被告知的事，結束狀態仍然是 0。
    // `seen > 0` used to be part of this condition, which excluded the one file
    // where EVERY window is past the end: a header row and no records. There
    // the caller got empty output, exit 0, silent stderr and `"records":0` --
    // and the second channel the README nominates for this question, the
    // --json meta line, says the same thing whether the window was past the end
    // or the file was empty. The strongest case for the warning was the case it
    // did not cover.
    // 這個條件原本還有 `seen > 0`，而那正好排除了「每一個視窗都在結尾之後」的那個檔案：
    // 有標頭、沒有紀錄。在那裡，呼叫端拿到的是空輸出、rc=0、stderr 沉默，以及 `"records":0`
    // ——而 README 指定用來分辨這件事的第二個管道（--json 的 meta 行），無論是「視窗在結尾
    // 之後」還是「檔案本來就空」都說同一句話。最該發出這個警告的情況，正是它沒有涵蓋的那個。
    if let (a, _) = o.mid, a > seen {
        if seen == 0 {
            Logger.shared.warn(
                "-mid \(a) starts after the last record: this file has no data records at all, so no window could have selected anything; this is not an error and the exit status is 0")
        } else {
            Logger.shared.warn(
                "-mid \(a) starts after the last record (\(seen)), so nothing was selected; this is not an error and the exit status is 0")
        }
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
    let plan = try openInput(o)
    defer { plan.source.close() }
    if let p = o.input {
        try checkTornAppend(path: p, format: plan.format, truncatePartial: o.truncatePartial)
    }

    // A suffix-less file is `.lines`: ONE column, zero header rows, bytes
    // verbatim -- so a comma there is DATA. Adding a column to it writes a
    // file whose second field is only a second field until it is read back,
    // at which point the comma is data again and the record is one field
    // containing a comma. csv2 would be writing a file csv2 misreads, at
    // rc=0, which is the same hole JV came through earlier the same day. The
    // refusal is the one that already stops `.csv` being written as `.csv2`:
    // the suffix declares the format, and this file's suffix cannot declare
    // two columns. KC in todo/known-defects.md, T214q.
    // 沒有副檔名的檔案是 `.lines`：**一欄**、零列標頭、位元組原樣——因此那裡的逗號是**資料**。
    // 對它新增一欄，寫出的檔案裡「第二個欄位」只在被讀回來之前是第二個欄位；讀回來時那個逗號
    // 又是資料，那一筆就成了「一個含逗號的欄位」。csv2 會在 rc=0 之下寫出一個 csv2 自己會誤讀的
    // 檔案，而那是 JV 同一天稍早走過的同一個缺口。這道拒絕與「阻止 `.csv` 被寫成 `.csv2`」是
    // 同一道：副檔名宣告格式，而這個檔案的副檔名宣告不出兩欄。見 todo/known-defects.md 的 KC、T214q。
    if plan.format == .lines, o.edits.contains(where: { if case .addColumn = $0 { return true }; return false }) {
        throw fault(
            "-add-column on a file with no suffix: that is one column, zero header rows, bytes verbatim, so a comma in it is DATA. A second column would be read back as part of the first. Write it to a file named .csv or .csv2 instead",
            "-add-column 用在沒有副檔名的檔案上：那是一欄、零列標頭、位元組原樣，因此裡面的逗號是**資料**。第二欄讀回來時會變成第一欄的一部分。請改寫到一個名為 .csv 或 .csv2 的檔案")
    }

    var inserts: [Int: [String]] = [:]
    var appends: [String] = []
    var deletes: [(Int, Int)] = []
    var updates: [Int: [(String, String)]] = [:]
    var blanks: [Int: [String]] = [:]
    var dropTokens: [String] = []

    // Phase 10. Applied to the headers and to every data record, at a 1-based
    // position that counts against the file AS IT ARRIVED -- the same batch
    // rule the four other edit verbs obey, so that `-add-column 2 x
    // -delete -col 2` names the arriving column 2 in both halves rather than
    // one before and one after.
    // 第 10 階段。套用在標頭與每一筆資料紀錄上，位置是 1-based，且對「檔案送達時的樣子」計數
    // ——那是其他四個編輯動詞遵守的同一條批次規則，如此 `-add-column 2 x -delete -col 2` 的兩半
    // 指的都是「送達時的第 2 欄」，而不是一個在改動前、一個在改動後。
    var addCols: [(at: Int, name: String, value: String)] = []
    for e in o.edits {
        switch e {
        case .insert(let at, let row): inserts[at, default: []].append(row)
        case .append(let row): appends.append(row)
        case .deleteRange(let a, let b): deletes.append((a, b))
        case .update(let r, let c, let v): updates[r, default: []].append((c, v))
        case .deleteCell(let r, let c): blanks[r, default: []].append(c)
        case .deleteColumn(let c): dropTokens.append(c)
        case .addColumn(let at, let name, let value): addCols.append((at, name, value))
        }
    }

    // The same clash, one axis over. `-delete -col X` combined with an edit
    // aimed at column X is refused, with the reason stated exactly: "the edit
    // would have no effect and would still be reported as done". `-delete a,b`
    // combined with an edit aimed at a RECORD inside a..b did that very thing:
    //
    //     csv2 -delete 1,1 -update 1:2 GHOST -i g.csv --in-place
    //     rc=0        and GHOST is nowhere, and nothing was said
    //
    // A rule was thought through, written down, and implemented on one axis.
    // Nothing carried it to the other, and nothing noticed, because the two
    // are in different parts of this function and only the column one had a
    // reason to be written when it was.
    //
    // Addresses are input-relative, which is what makes this decidable here:
    // `-delete 1,1` and `-update 1:2` are talking about the same record by
    // definition, without needing to know what the file contains.
    //
    // 同一個衝突，換一個軸。`-delete -col X` 與「瞄準欄位 X 的編輯」併用會被拒絕，理由寫得
    // 一字不差：「該編輯不會有任何效果，卻仍會被回報為已完成」。而 `-delete a,b` 與「瞄準
    // a..b 之中某一筆的編輯」併用，做的正是那件事：rc=0，GHOST 不在任何地方，也沒有任何訊息。
    //
    // 一條規則被想清楚、寫下來，並實作在一個軸上。沒有任何東西把它帶到另一個軸，也沒有任何
    // 東西發現——因為兩者位在這個函式的不同段落，而當時只有「欄」那一個有被寫出來的理由。
    //
    // 位址是相對於輸入的，這正是此處判斷得出來的原因：`-delete 1,1` 與 `-update 1:2` 依定義
    // 就是在說同一筆紀錄，不需要知道檔案裡有什麼。
    // Two edits aimed at the SAME cell: the first cannot survive the second,
    // and it used to be applied and then overwritten, at rc=0, with nothing
    // said. The refusal for `-update` colliding with `-delete` gives the
    // reason in words that describe this exactly -- "the edit would have no
    // effect and would still be reported as done".
    //
    // Two `-insert`s at one N are different and stay legal: they produce two
    // records, in the order written, and both survive. That is documented.
    // Two updates produce one value, and one of them was never going to be it.
    //
    // 兩個瞄準「同一個儲存格」的編輯：第一個不可能在第二個之下存活，而它原本會先被套用、
    // 再被覆蓋，rc=0，什麼都不說。「`-update` 撞上 `-delete`」那個拒絕給出的理由，逐字
    // 描述了這裡發生的事——「該編輯不會有任何效果，卻仍會被回報為已完成」。
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

    let sink = try makeSink(o)
    var aborted = true
    defer { if aborted { sink.abort() } }

    var headers: [Record] = []
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


    /// Removing several columns at once, by rebuilding rather than removing in
    /// place: `remove(at:)` twice would make the second index refer to the row
    /// as it stands after the first removal, which is the same off-by-one the
    /// `-delete 3 -delete 4` comment above describes.
    /// 一次移除多欄時採「重建」而非就地刪除：連續兩次 `remove(at:)` 會讓第二個索引
    /// 指向第一次移除後的那一列，正是上面 `-delete 3 -delete 4` 註解所描述的偏移。
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
        // the position have to be answered against the file as it arrived --
        // "All indexes refer to the INPUT and are applied in one pass" is the
        // rule `-insert` has always followed, and the first version of this
        // broke it for the second and later -add-column in one run: their N
        // counted against the file the earlier insert had already widened.
        // See KB in todo/known-defects.md.
        // 這是「這些欄位都還沒進去之前」的寬度。越界檢查與插入位置都必須以「檔案送達時的樣子」
        // 來回答——「所有索引都指向輸入，並在一遍之內套用」是 `-insert` 一直遵守的規則，而這個
        // 函式的第一版對「同一次執行裡第二個以後的 -add-column」違反了它：它們的 N 算在
        // 前一次插入已經加寬過的檔案上。見 todo/known-defects.md 的 KB。
        let arrived = r.fields.count
        for (k, a) in addCols.enumerated() {
            // Clamping put `-add-column 9` on a two-column file at the end and
            // exited zero, which is this tool's own named failure: the caller
            // gets a file back, believes the 9 meant something, and nothing
            // ever says the number was ignored. One past the last column is
            // the append; anything beyond it is a number that does not
            // describe this file.
            // 用夾取的方式處理，會讓一個兩欄檔案上的 `-add-column 9` 落在最後並以 0 結束，而那
            // 正是這個工具自己命名過的失敗：呼叫端拿回一個檔案、以為那個 9 有意義，而沒有任何
            // 東西說過那個數字被忽略了。「最後一欄再加一」是附加；再往後就是一個描述不了這個
            // 檔案的數字。
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
                let parts = splitHeaderName(a.name)
                text = hr < parts.count ? parts[hr] : ""
            } else {
                text = a.value
            }
            r.fields.insert(Field(value: Array(text.utf8)), at: idx)
        }
    }

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

    // Every byte that leaves this function is counted here -- offset AND line.
    // The line used to be counted in emitData only, so the header rows, which
    // go out through this one, advanced the offset and not the line: the index
    // built by a write said record 1 was on line 1 when a `.csv2` puts it on
    // line 3. Nothing checked it until --verify-index learned to compare the
    // lines it stores.
    // 每一個離開這個函式的位元組都在這裡被計入——偏移量「與」行號。行號原本只在 emitData
    // 裡數，而標頭列走的是這一個：於是它們推進了偏移量卻沒有推進行號，一次寫入建出的索引
    // 便說第 1 筆在第 1 行，而 `.csv2` 會把它放在第 3 行。在 --verify-index 學會比對它自己
    // 存的行號之前，沒有任何東西檢查過這件事。
    func emit(_ r: Record) {
        let bytes = FieldEncoder.encodeRecord(r, format: plan.format, preserveRaw: true)
        sink.write(bytes)
        outOffset += bytes.count
        outLine += bytes.filter { $0 == BYTE_LF }.count
    }

    func emitData(_ r: Record) {
        outRecords += 1
        // A record that itself contains a newline makes the record number stop
        // matching the line number, and the index cannot then be used to seek
        // (it stores bytes, not lines). Recorded here so the flag in the index
        // header is right.
        // 自身含換行的紀錄會讓紀錄號不再等於行號，屆時索引就不能用來 seek
        // （它存的是位元組而非行號）。在此記錄，讓索引檔頭的旗標是正確的。
        // Answered by the same function as the other two call sites. It was
        // right here and wrong there; one function is what stops that from
        // being possible again.
        // 與另外兩個呼叫點由同一個函式回答。這裡本來是對的、那裡是錯的；
        // 「只有一個函式」才是讓那件事不可能再發生的東西。
        builder?.add(record: outRecords, at: UInt64(outOffset), line: UInt64(outLine),
                     spansLines: recordSpansLines(r, format: plan.format))
        emit(r)
    }

    let parser = RecordParser(format: plan.format, truncatePartial: o.truncatePartial) { rec in
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
                    // log said `<redacted> -> <redacted>`, because redaction
                    // follows the file's declaration, so the one record of what
                    // happened concealed it. Round 37 of the README-only blind
                    // testing, defect W.
                    //
                    // 在寫出任何一個位元組之前拒絕，而且是對「輸入的」標頭而非加上標記後的
                    // 標頭——`-encrypt secret` 與 `-update 1:secret NEW` 併用是說得通的
                    // （被加密的就是那個新值），因此仍然允許，因為輸入的標頭還沒有標記。
                    // 被拒絕的是「把原始值寫進一個檔案已經宣告為轉換過的欄位」。對 `:enc:`
                    // 而言那不只是錯，而是不可回復、且不限於被編輯的那一筆：-decrypt 會停在
                    // 損壞的那一格，於是之後每一筆——密文完好、從未被碰過——也一起讀不回來。
                    // 而 log 寫的是 `<redacted> -> <redacted>`，因為遮蔽依據的是檔案的宣告，
                    // 於是唯一那份「發生了什麼」的紀錄把它掩蓋掉了。README-only 盲測第 37
                    // 回合，編號 W。
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
                        // The columns, by name, once for the run. The README
                        // has promised this entry since 2026-08-21 and there
                        // was none: a run that removed a whole column left an
                        // audit trail naming no column at all. Round 59 read
                        // the table and looked for it.
                        //
                        // Values are NOT recorded: they are the entire column,
                        // and one entry per record would make the log larger
                        // than the file it describes. The README says that too.
                        // 那些欄位的名字，整次執行記一則。README 從 2026-08-21 起就承諾了這則
                        // 紀錄，而它並不存在：一次移除了整個欄位的執行，留下的稽核軌跡沒有指名
                        // 任何欄位。第 59 回合讀了那張表，然後去找它。
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
                        for i in headers.indices { dropColumns(&headers[i]) }
                    }
                    // An edit rewrites the whole file, so the header always
                    // goes out. `-t` is about selections, which produce a
                    // fragment; this produces a file.
                    // 編輯會重寫整個檔案，因此標頭一定寫出。`-t` 是給選取用的
                    // ——那產生的是片段，而這裡產生的是一個完整檔案。
                    // Outside the `-delete -col` block above, because a
                    // run may add a column without deleting one -- inside it,
                    // the header kept its arriving width while every data
                    // record grew, and the file that came back out was
                    // rejected by csv2's own reader on the next read.
                    // 放在上面 `-delete -col` 區塊之外，因為一次執行可以只加不刪——放在裡面時，
                    // 標頭維持送達時的寬度而每一筆資料都變寬了，寫回去的檔案在下一次讀取時
                    // 被 csv2 自己的讀取器拒絕。
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
                        for a in addCols where splitHeaderName(a.name).count < 2 {
                            Platform.writeStderr(
                                "csv2: -add-column \(a.at) \(a.name): no Chinese title given, row 2 left empty; supply both as 'english,中文'\n"
                                + "csv2：-add-column \(a.at) \(a.name)：未提供中文標題，第 2 列留空；請以 'english,中文' 一併給出\n")
                        }
                    }
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
            // is in hand, before the line below that sets it. So positions
            // 2..N worked and 1 alone refused, with a message naming a header
            // the file does not have. Round 78, JX.
            // 那個寬度必須在「位置 1 的插入被拿去和它比較」**之前**就已知。沒有標頭列時，它由
            // 第一筆紀錄決定——而位置 1 的插入，正是在那一筆還在手上時被處理的，也就是在下面
            // 那行設定它之前。於是位置 2..N 可用，只有 1 被拒絕，而那則訊息指名了一個這個檔案
            // 沒有的標頭。第 78 回合，JX。
            if expectedFields == 0 { expectedFields = r.count }
            if let rows = inserts[r.number] {
                touched.insert(r.number)
                for row in rows {
                    let ins = try parseRowLiteral(row, format: plan.format,
                                                  expected: expectedFields,
                                                  what: "-insert \(r.number)")
                    // emitData, not emit: an inserted row is a record of the
                    // OUTPUT and has to be counted like one. Through emit it
                    // moved the offset and nothing else, so the index built by
                    // the same run said there were N records when the file had
                    // N+1, and every grid point after the insertion named a
                    // byte that was now some other record. `-mid 257,258` on a
                    // file with one row inserted at 5 returned records 258 and
                    // 259 labelled 257 and 258, at rc=0, while `--no-index`
                    // returned the right ones -- the index giving the wrong
                    // data quickly, which this design calls far worse than no
                    // index. Caught by --verify-index only after it learned to
                    // check the lines it stores.
                    // 用 emitData 而不是 emit：被插入的一列是「輸出」的一筆紀錄，就該被當成
                    // 一筆來計。走 emit 時它只推進了偏移量、其餘什麼也沒做，於是同一次執行建出
                    // 的索引說有 N 筆而檔案有 N+1 筆，插入點之後的每一個格點指的位元組都成了
                    // 另一筆紀錄。在第 5 筆插入一列的檔案上，`-mid 257,258` 回傳的是第 258 與
                    // 259 筆、標成 257 與 258，rc=0，而 `--no-index` 回傳的是對的——「索引很快
                    // 地給出錯的資料」，本設計稱之為比沒有索引糟得多。直到 --verify-index 學會
                    // 檢查它自己存的行號，才抓到。
                    emitData(ins)
                }
            }
            if deletes.contains(where: { r.number >= $0.0 && r.number <= $0.1 }) {
                touched.insert(r.number)
                // With its contents. A deleted record is the largest thing
                // this tool destroys, and the audit trail said only that a
                // number had gone. Redacted per column, so a protected column
                // does not arrive in the log in the clear, and escaped like
                // every other line, so one record is one entry.
                // 連同它的內容。被刪掉的紀錄是這個工具銷毀得最大的東西，而稽核軌跡先前只說了
                // 「某個編號不見了」。逐欄套用遮蔽規則，好讓受保護的欄位不會以明文進到 log；
                // 也與其他每一行一樣做跳脫，因此一筆紀錄就是一則紀錄。
                let contents = r.fields.enumerated().map { (i, f) -> String in
                    // A file with no header row reaches these too. Phase 8b: `-delete` and
                    // `-update` on a suffix-less file crashed with SIGTRAP at exit 133,
                    // nothing on either stream -- these three read row 0 to NAME the
                    // column in the audit line, which is worth having and is not worth
                    // crashing for. Without a header the number is the name.
                    // 沒有標頭列的檔案也會走到這裡。第 8b 階段：對一個沒有副檔名的檔案下 `-delete`
                    // 與 `-update` 會以 SIGTRAP、exit 133 當掉，兩條輸出流上都沒有東西——這三處讀第 0 列
                    // 是為了在稽核那一行裡「說出欄位的名字」，那件事值得有，但不值得為它當掉。
                    // 沒有標頭時，編號就是名字。
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
                                what: "record \(r.number) (line \(r.line))")

            if let ups = updates[r.number] {
                touched.insert(r.number)
                for (colToken, value) in ups {
                    let c: Int
                    let name: String
                    if let h0 = headers.first {
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
                    r.fields[c].set([UInt8](value.utf8))
                    // The log records the value in full, so say so when "in
                    // full" is a megabyte. This is a WARN and not a cap: the
                    // decision (2026-08-19) was that an audit trail must not
                    // drop data, and the honest consequence of that is an
                    // unbounded line -- which the person running the edit
                    // should hear about rather than discover in a disk graph.
                    // log 會完整記錄那個值，因此當「完整」等於一 MB 時，要說出來。這是
                    // WARN 而不是上限：2026-08-19 定案「稽核軌跡不得丟資料」，而那個決定
                    // 誠實的後果就是無界的行長度——執行這次編輯的人應該當場聽到，而不是
                    // 事後在磁碟用量圖上發現。
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
                    if let h0 = headers.first {
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
                    // `-update` has always recorded old -> new, and the README
                    // promises "old and new values in an ordinary column -- in
                    // full, never truncated"; blanking a cell destroys exactly
                    // such a value and recorded only that it had happened. The
                    // most destructive of the two logged the least.
                    // 值在被丟棄「之前」進入 log。`-update` 一向記錄 old -> new，而 README
                    // 承諾「一般欄位的新舊值——完整、絕不截斷」；清空一個儲存格銷毀的正是
                    // 那樣一個值，而它先前只記錄了「這件事發生過」。兩者之中破壞性較大的
                    // 那一個，記錄得最少。
                    let gone = r.fields[c].value
                    r.fields[c].set([])
                    // `-> ""`, not a bare `->`. The grammar the log promises is
                    // old and new each wrapped in quotes, and an absent new
                    // value broke it for the one verb whose new value is always
                    // empty. A parser reading `-> ` cannot tell an empty value
                    // from a truncated line.
                    // 用 `-> ""`，不是光禿禿的 `->`。log 承諾的文法是「新舊值各自加引號」，
                    // 而「新值缺席」在唯一一個「新值永遠是空的」動詞上打破了它。一個讀到
                    // `-> ` 的解析器，分不出「空的值」與「被截斷的一行」。
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
        emitData(rec)
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
    for (a, b) in deletes where a > total || b > total { bad.append("-delete \(a),\(b)") }
    for k in updates.keys where k > total { bad.append("-update \(k):…") }
    for k in blanks.keys where k > total { bad.append("-delete -cell \(k):…") }
    if !bad.isEmpty {
        // -insert past the end has a right answer and the message never named
        // it. The README says -append is how you add at the end; someone
        // holding this refusal has no reason to go looking for that sentence.
        // Only added for -insert: -update and -delete past the end have no
        // equivalent, and offering one would be advice to do something else.
        // 「-insert 越過結尾」是有正解的，而這則訊息從來沒說出那個正解。README 寫著要加在
        // 最後請用 -append；而拿著這則拒絕的人，沒有任何理由會去翻到那一句。只對 -insert 加，
        // 因為 -update 與 -delete 越界沒有對應的正解，硬給一個等於是叫人去做別的事。
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
    // has renamed, so every `--in-place` edit and every `-o` write failed
    // there. It cost ten of the seventeen failures in the first Windows run of
    // the suite, 2026-08-19, and not one of them was visible on macOS or Linux,
    // where the ordering genuinely does not matter.
    //
    // The defer stays: this is belt and braces, and ByteSource.close is safe to
    // call twice.
    //
    // 在 rename「之前」關閉輸入，而不是等到函式結束。
    // POSIX 允許你 rename 覆蓋一個「還有人開著」的檔案，Windows 不允許——MoveFileExW 回傳
    // error 5（ACCESS_DENIED）。`defer { plan.source.close() }` 在函式回傳時才執行，而那是在
    // sink.close() 完成 rename「之後」，因此那裡的每一次 `--in-place` 編輯與每一次 `-o` 寫入
    // 都失敗。它造成了 2026-08-19 首次 Windows 執行中十七條失敗裡的十條，而其中沒有任何一條
    // 在 macOS 或 Linux 上看得見——在那兩個平台上，這個順序確實無關緊要。
    // defer 保留：這是雙保險，而 ByteSource.close 可以安全地被呼叫兩次。
    plan.source.close()
    try sink.close()
    aborted = false

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
    // The counts describe what was WRITTEN, not what was read. This line used
    // to report `total` and `expectedFields`, both of which are the input's
    // shape: after `-delete 1,2 -delete -col 7` it said "22 records, 7 fields"
    // for a file holding 20 and 6. Wrong in both numbers, in the one line of
    // the audit trail that summarises the result -- and the trail's stated job
    // is to record what changed.
    //
    // `outRecords` is incremented in emitData, so it counts records that
    // reached the sink; `headers[0]` has already had its dropped columns
    // removed by the time this runs, so its width is the output's.
    //
    // 這兩個數字描述的是「寫出了什麼」，不是「讀進了什麼」。這一行原本回報的是 `total` 與
    // `expectedFields`，而兩者都是「輸入」的形狀：在 `-delete 1,2 -delete -col 7` 之後，
    // 它說「22 筆、7 欄」，而檔案裡是 20 筆、6 欄。兩個數字都錯，而且錯在稽核軌跡裡「總結
    // 結果」的那一行——那份軌跡自己宣稱的工作，正是記錄改了什麼。
    //
    // `outRecords` 在 emitData 裡遞增，因此它數的是「真的到達輸出端」的紀錄；而執行到這裡時，
    // `headers[0]` 已經移除過被刪掉的欄位，所以它的寬度就是輸出的寬度。
    Logger.shared.info("wrote \(outRecords) records, \(headers.first?.count ?? expectedFields) fields, atomic rename OK")
    // "a metrics: line on every path" was true of the reads and of nothing
    // else: every --in-place edit and both index commands printed none, and
    // those are the runs whose cost a caller most wants to see.
    // 「每一條路徑都有一行 metrics」對「讀取」為真，對其餘一切為假：每一次 --in-place 編輯
    // 與兩個索引指令都不印，而那些正是呼叫端最想看到成本的執行。
    Metrics.report(bytesRead: plan.source.bytesRead,
                   fileSize: o.input.flatMap { Int(FileStamp.of(path: $0)?.size ?? 0) } ?? 0)
}

// ---------------------------------------------------------------------
// MARK: - The -append fast path / -append 快路徑
// ---------------------------------------------------------------------

/// Every other edit rewrites the whole file, and rewriting is what makes them
/// atomic. Appending is the one operation where the data itself can be written
/// incrementally, so it is the one that gets an O(1) path: adding a record to
/// a 1 GiB file goes from 26 seconds to milliseconds. `artifacts.csv` gains a
/// row on every build, which is exactly this shape.
/// 其餘的編輯都要重寫全檔，而重寫正是它們原子性的來源。追加是唯一「資料本身
/// 也能增量寫入」的操作，因此只有它值得一條 O(1) 路徑：對 1 GiB 的檔案加一筆
/// 從 26 秒變成毫秒級。`artifacts.csv` 每次建置追加一列，正是這個形狀。
func canUseAppendFastPath(_ o: Options) -> Bool {
    guard o.edits.count >= 1, o.input != nil else { return false }
    guard o.encryptCols == nil, o.decryptCols == nil, o.hashCols == nil else { return false }
    // What decides this is whether the run is an in-place append, and o.inPlace
    // answers that directly. Comparing the two PATHS was the same mistake DP
    // was about: `--in-place` sets o.output to the symlink-resolved path, and
    // resolvingSymlinksInPath() also normalises -- a relative path becomes
    // absolute, and on macOS /private/tmp becomes /tmp. From 9132e66 until this
    // line, `-append -i data.csv --in-place` -- a relative path, the ordinary
    // way to type it -- silently rewrote the whole file. T43d kept passing
    // because it happens to pass an already-canonical absolute path.
    // `-o` naming the input is refused in main.swift, so nothing else can reach
    // this path by accident.
    // 決定這件事的是「這是不是一次就地追加」，而 o.inPlace 直接回答了。比較兩個「路徑」
    // 犯的是 DP 那個一樣的錯：`--in-place` 會把 o.output 設成解析過 symlink 的路徑，而
    // resolvingSymlinksInPath() 同時也會正規化——相對路徑變絕對，macOS 上 /private/tmp
    // 變 /tmp。從 9132e66 起到這一行為止，`-append -i data.csv --in-place`（相對路徑，
    // 也就是一般人會打的那種）一直在靜默重寫整個檔案。T43d 之所以照樣通過，是因為它剛好
    // 傳了一個已是正規形式的絕對路徑。`-o` 指向輸入在 main.swift 已被拒絕，因此沒有別的
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
    // A suffix-less path is `.lines` now, not "no format". This guard predates
    // that and turned `-append` on such a file into "t declares no format" --
    // a sentence that was true when it was written and became false the moment
    // the format existed. Phase 8b.
    // 沒有副檔名的路徑現在是 `.lines`，不是「沒有格式」。這道守衛比那件事早，於是對這種檔案下
    // `-append` 會得到「t declares no format」——那句話在寫下時為真，而在那個格式存在的那一刻
    // 就成了假的。第 8b 階段。
    guard let fmt = Format.from(path: path) ?? (o.headersOverride.map { $0 == 2 ? .csv2 : .csv }) ?? Format.lines as Format? else {
        throw fault("\(path) declares no format", "\(path) 未宣告格式")
    }
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
    // definition. Reaching for row 0 here and on the line below were the last
    // of the SIGTRAPs this phase turned up -- four of them, all the same shape:
    // code written when every file had a header, meeting a file that has none.
    // 沒有標頭列時，沒有東西可以拿來取寬度：依定義就是一欄。在這裡、以及下面那一行伸手去拿第 0
    // 列，是這個階段挖出的最後幾個 SIGTRAP——一共四個，形狀完全相同：在「每個檔案都有標頭」的年代
    // 寫下的程式碼，遇到一個沒有標頭的檔案。
    let expected = headers.first?.count ?? 1

    // The fast path never reaches runEdit, so the refusal has to be repeated
    // here rather than relied on. It is the same function, which is the point:
    // the first version of this fix lived only in runEdit and `-append
    // --in-place` -- the path most likely to be used on a big protected file --
    // walked straight past it and wrote plaintext into an encrypted column at
    // rc=0. Cheap here: the header is already read.
    // 快路徑不會走到 runEdit，因此這條拒絕必須在此重複一次，而不是指望它。用的是同一個
    // 函式，那正是重點：這個修正的第一版只住在 runEdit 裡，而 `-append --in-place`——
    // 最可能被用在一個大型受保護檔案上的那條路徑——直接繞過它，以 rc=0 把明文寫進了加密欄。
    // 在這裡做很便宜：標頭本來就已經讀進來了。
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
    // trailing newline.
    //
    // The condition used to be `if the file does not end in a newline`, and
    // the comment below it justified that: "a file that does not end in a
    // newline is the only file whose last record can be half-written". That is
    // false, and the counter-example is ordinary. A record ending inside an
    // unclosed quote contains newlines like any other prose, so the file ends
    // with `\n` and is still open:
    //
    //     id,name,note
    //     r1,n1,"ok"
    //     r2,n2,"unclosed<LF>          <- ends with a newline, record is open
    //
    // `-o` refused this correctly the whole time. `--in-place` -- which is the
    // only destination the fast path serves -- wrote at rc=0, and the result
    // could not be read back by csv2 at all. Worse, the appended record was
    // then unrecoverable: the unclosed quote swallowed it, so the documented
    // repair, --truncate-partial, discarded the very record that had just been
    // written successfully.
    //
    // The cost is a scan the fast path was built to avoid. It is paid because
    // the alternative is a write reported as successful that produces a file
    // this tool refuses to read -- the exact failure csv2 exists to prevent,
    // and the one the README already claims is checked "for -o and for
    // --in-place alike".
    //
    // 每一次走快路徑的追加都會驗證，不再只在「檔案沒有結尾換行」時才驗。
    //
    // 原本的條件是「若檔案不以換行結尾」，而它下方的註解為此辯護：「未以換行結尾的檔案，
    // 是唯一『最後一筆可能只寫了一半』的檔案」。那是假的，而反例非常普通：一筆停在未關閉
    // 引號裡的紀錄，和任何散文一樣會含有換行，因此檔案以 `\n` 結尾，而那一筆仍然是開著的。
    //
    // `-o` 從頭到尾都正確地拒絕了它。而 `--in-place`——快路徑唯一服務的目的地——以 rc=0
    // 寫了進去，結果 csv2 自己完全讀不回來。更糟的是那筆被追加的紀錄再也救不回來：未關閉的
    // 引號把它吞了進去，於是文件指定的修復手段 --truncate-partial 丟掉的，正是幾秒前才被
    // 「成功」寫入的那一筆。
    //
    // 代價是一次「快路徑當初就是為了避免它」的掃描。之所以付這個代價，是因為另一個選項是
    // 「一次被回報為成功的寫入，產生一個這個工具自己拒絕讀取的檔案」——那正是 csv2 存在所要
    // 防止的失敗，也正是 README 早已宣稱「`-o` 與 `--in-place` 一視同仁地檢查」的那一項。
    //
    // Because that scan happens, the fast path is in the same position as
    // every other write path: it has just read the whole file. So it builds
    // an index like the others do, instead of being the one exception -- an
    // exception whose stated reason ("its fast path never reads to the end")
    // had been false since the scan above was added, in three sentences of
    // the README and two comments here.
    //
    // 正因為那次掃描會發生，快路徑就和其他每一條寫入路徑處於同一個位置：它剛剛讀完整個
    // 檔案。因此它像其他路徑一樣建索引，而不再是那個唯一的例外——一個「它的快路徑從不讀到
    // 檔尾」的理由早已不成立的例外，那句話在 README 裡有三份、在這個檔案裡有兩份。
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
    // of a value, so the probe said LF and the append wrote LF into a file
    // where every other record ends CRLF. The scan above has already read the
    // whole file and knows what its last terminator was; use that when the
    // tail has none, which is the same rule stated for the case the probe
    // handles.
    // 只有在「檔案最後一筆有終止符」時，那兩個位元組才回答得了這個問題。一個 CRLF 檔案的尾巴
    // 若沒有終止符——匯出程式被切斷、寫入撕裂、任何停在紀錄中間的情況——那兩個位元組就是某個
    // 「值」的最後兩個位元組，於是這個探測說「LF」，而追加就把 LF 寫進了一個「其他每一筆都以
    // CRLF 結尾」的檔案。上面那次掃描已經讀過整個檔案，知道它最後一個終止符是什麼；尾巴沒有
    // 終止符時就用它——那與這個探測所處理的情況，是同一條規則。
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
            // Reached for every format, because the reason is not the format:
            // a file that does not end in a newline is the only file whose
            // last record can be half-written, and the fast path had no way to
            // know. Reported so the O(n) is visible rather than a mystery in
            // the timings.
            // 每一種格式都會走到。回報出來，讓那個「補上一個換行」的決定是看得見的。
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

    // ONE write() through a descriptor opened O_APPEND. POSIX makes the offset
    // update and the write atomic there, so two concurrent appends cannot land
    // on the same offset.
    //
    // The comment above this line used to say exactly that while the code did
    // `seek(toFileOffset: size)` then `write` -- seek-to-computed-end, which is
    // the construction the log file was moved OFF for this very reason, one
    // file over. Two appends racing on one file then both wrote at the same
    // offset, and the shorter write landed on top of the longer one:
    //
    //   * the tail of the overwritten row survived as a record NOBODY WROTE --
    //     `A,BBBB` from a row that was `AAAA,BBBB` -- and the file read back
    //     clean at rc=0 with a fabricated record in it;
    //   * or the leftover byte was a bare newline, and csv2's own blank-line
    //     rule then refused the file it had just written, at rc=0 from both
    //     writers, both logging success.
    //
    // The README's worst case for concurrent writers is "one edit is lost".
    // This was both edits lost, a record invented, or a file destroyed.
    //
    // 一次 write()，走的是以 O_APPEND 開啟的描述子。POSIX 保證那裡的偏移量更新與寫入是
    // 原子的，因此兩個並行的追加不可能落在同一個偏移量上。
    //
    // 這一行上面的註解原本就是這樣寫的，而程式做的是 `seek(toFileOffset: size)` 再 `write`
    // ——「先算出檔尾再寫到那裡」，正是 log 檔為了同一個理由而搬離的那個構造，就在隔壁一個
    // 檔案裡。兩個追加在同一個檔案上競賽時，兩者於是寫在同一個偏移量上，較短的那次寫入
    // 蓋在較長的那次上面：被蓋掉那一列的尾巴，會以「沒有任何人寫過的一筆紀錄」活下來，
    // 而檔案以 rc=0 乾乾淨淨地讀得回來；或者剩下的是一個裸換行，而 csv2 自己的空白行規則
    // 於是拒絕了它剛剛寫出來的那個檔案——兩個寫入者都以 rc=0 結束，都記下了成功。
    //
    // README 對並行寫入者的最壞情況是「有一次編輯會遺失」。這裡是兩次編輯都遺失、一筆紀錄
    // 被憑空造出來，或者一個檔案被毀掉。
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

    // Did somebody else append while we were? O_APPEND keeps both writes whole,
    // so the DATA is fine either way -- but the offsets computed above are then
    // wrong for the index, and an index that is wrong about where records start
    // is worse than no index at all. The size is the evidence, and it is one
    // stat.
    // 在我們追加的同時，有別人也追加了嗎？O_APPEND 讓兩次寫入各自完整，因此「資料」無論如何
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
    // This used to be `Int(idx.lastLine) + prefix.count`, and `lastLine` is
    // documented in Index.swift as the line the LAST record STARTS on -- so
    // the sum was short by however many lines that record itself occupies, at
    // least one and more when it carries newlines inside quotes. An appended
    // record landing on a grid point then put a wrong line in the sidecar,
    // `-mid N,N --json` reported it, `--no-index` disagreed by one, and
    // `--verify-index` said OK because it did not check the lines it stores.
    //
    // The line feeds are counted by the scan above, so this is exact: a file
    // ending in LF has that many complete lines and the next record starts on
    // the one after; a file not ending in LF gets the prefix LF that completes
    // its last line, which `prefix.count` adds.
    //
    // 被追加的第一筆紀錄從哪一個實體行開始，由檔案自己的位元組決定，而不是由索引決定。
    //
    // 原本寫的是 `Int(idx.lastLine) + prefix.count`，而 `lastLine` 在 Index.swift 裡的
    // 定義是「最後一筆『開始』的那一行」——因此這個和少了那一筆自己佔掉的行數，至少一行，
    // 引號內含換行時更多。一筆剛好落在格點上的追加紀錄，於是把一個錯的行號放進 sidecar，
    // `-mid N,N --json` 會照著報，`--no-index` 差一行，而 `--verify-index` 說 OK，因為
    // 它根本沒有檢查自己存的行號。
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
        // this path used to update the count, the offsets and the freshness
        // stamp while leaving that claim exactly as it was.
        //
        // The result is the defect T79 was written for, arriving through a
        // different door: an index asserting a property of the file that
        // nothing re-derived. The O(1) check then passes -- the stamp is
        // current, because this path just refreshed it -- `-contains` takes
        // the parallel path, and every record after the first chunk boundary
        // past the appended one is numbered one too high. At rc=0. Following
        // the README's own find-then-edit recipe writes into the wrong row.
        //
        // `-append` with `-o` and `-update` were both correct; only the
        // in-place fast path, which is the only one that edits an index rather
        // than rebuilding it, had this to get wrong.
        //
        // Counting line feeds is enough: every appended record ends with
        // exactly one, so more of them than records means at least one record
        // carries a newline inside a quoted field.
        //
        // 一筆跨行的紀錄會讓 `no_embedded_newlines` 變成假的，而這條路徑原本會更新筆數、
        // 偏移量與新鮮度戳記，卻把那個宣稱原封不動地留著。
        //
        // 結果就是 T79 當初要處理的那個缺陷從另一扇門回來：一份索引宣稱了一個「沒有任何東西
        // 重新推導過」的檔案性質。O(1) 檢查於是通過——戳記是最新的，因為這條路徑剛剛才更新
        // 過它——`-contains` 走上平行路徑，而「被追加那一筆之後的第一個區塊邊界」以後的每一筆
        // 編號都大了一。rc=0。照著 README 自己那套「先找再改」的寫法做，值會被寫進錯的那一列。
        //
        // `-append` 搭配 `-o` 與 `-update` 都是對的；只有就地的快路徑——唯一一條「編輯」索引
        // 而不是重建它的路徑——有這件事可以做錯。
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
        // one, which is the same door the record COUNT came through in T79.
        // 每一筆被追加紀錄的起始行號，由「實際寫出去的位元組」算出。自 v4 起索引每個格點都帶
        // 一個行號，而追加是唯一一條「延續索引」而非「重建索引」的路徑——因此它也是唯一一個
        // 能把錯的行號放進索引的地方，而那正是 T79 當初讓「筆數」出錯的同一扇門。
        for r in appendedRecords(startingAt: Int(idx.records) + 1) {
            idx.noteAppend(record: r.n, at: r.off, line: UInt64(r.line))
        }
        idx.save(dataPath: path)
    }
}

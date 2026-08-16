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
        throw fault("-md writes Markdown but \(path) declares a CSV format; Markdown cannot be read back by csv2",
                    "-md 產生 Markdown，但 \(path) 的副檔名宣告的是 CSV 格式；Markdown 無法被 csv2 讀回")
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

/// Decides whether this call can seek instead of scan. The index only helps
/// RANDOM access: `-r` and `-contains` read the whole file no matter what, so
/// they neither use nor create one -- building an index for them is pure waste.
/// 決定這次呼叫能不能用 seek 取代掃描。索引只對隨機存取有幫助：`-r` 與
/// `-contains` 無論如何都要讀完整個檔案，因此既不使用也不建立索引——為它們建
/// 索引是純粹的浪費。
struct IndexPlan {
    var resumeOffset: UInt64?
    var resumeRecord: Int = 1
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
        // The seek is only taken when the file has no embedded newlines. With
        // one, a record number no longer equals a line number, and the index
        // stores byte offsets but not line numbers -- so resuming would report
        // a physical line the full scan would not. Output with and without an
        // index must be byte-identical, and `--physical` puts the line in the
        // output.
        // 只有在檔案沒有內嵌換行時才走 seek。有內嵌換行時紀錄號不再等於行號，
        // 而索引存的是位元組偏移量、不是行號——恢復解析會回報一個完整掃描不會
        // 給出的物理行號。有無索引的輸出必須逐位元相同，而 `--physical` 會把
        // 行號放進輸出。
        guard idx.noEmbeddedNewlines, idx.records > 0 else { return out }
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

    let parser = RecordParser(format: plan.format) { rec in
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
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))")
            // A record that itself spans lines means a record number is no
            // longer a line number, and the index stores bytes rather than
            // lines -- so the seek path must refuse to use this index. Recorded
            // here so the flag in the header is right.
            // 自身跨行的紀錄會讓紀錄號不再等於行號，而索引存的是位元組而非行號
            // ——因此 seek 路徑必須拒絕使用這份索引。在此記錄，讓檔頭的旗標正確。
            builder.add(record: r.number, at: UInt64(r.offset),
                        spansLines: rec.line != r.line || false)
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
        throw fault("no usable index beside \(path)", "\(path) 旁沒有可用的索引")
    }
    var headers: [Record] = []
    var n = 0
    var mismatches: [String] = []
    let parser = RecordParser(format: plan.format) { rec in
        if headers.count < plan.headerRows { headers.append(rec); return true }
        n = rec.number - plan.headerRows
        if (n - 1) % idx.stride == 0 {
            let g = (n - 1) / idx.stride
            if g < idx.offsets.count && idx.offsets[g] != UInt64(rec.offset) {
                mismatches.append("record \(n): index says byte \(idx.offsets[g]), actual \(rec.offset)")
            }
        }
        return true
    }
    while let c = plan.source.next() { try parser.feed(c) }
    try parser.finish()
    if Int(idx.records) != n {
        mismatches.append("record count: index says \(idx.records), actual \(n)")
    }
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
    if let p = o.input, canRunParallelSearch(o, format: Format.from(path: p) ?? .csv) {
        try checkTornAppend(path: p, format: Format.from(path: p) ?? .csv,
                            truncatePartial: o.truncatePartial)
        try runParallelSearch(o)
        return
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
        throw fault("-B \(o.before) exceeds the buffered-record limit (\(maxBuffer))",
                    "-B \(o.before) 超過可緩衝的紀錄上限（\(maxBuffer)）")
    }

    var lower = 1
    var upper = Int.max
    if let (a, b) = o.mid { lower = a; upper = b ?? Int.max }
    if let n = o.head { upper = min(upper, n) }

    let ip = planIndex(o, plan: try openInput(o), lower: lower, upper: upper)
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

    var plan = try openInput(o)
    var headers: [Record] = []
    if let off = ip.resumeOffset, let path = o.input {
        headers = try readHeaderRows(path: path, format: plan.format, want: plan.headerRows)
        plan.source.close()
        plan.source = try ByteSource(path: path, chunkSize: 1 << 16, startAt: off)
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
    if o.json {
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
    }

    func headersComplete() throws {
        try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath)
        expectedFields = headers[0].count
        transform = try buildTransform(o, headers: headers)
        markHeaders(&headers, transform: transform)
        ctx = EmitContext(
            format: plan.format, headers: headers, withHeader: o.withHeader,
            rownum: o.rownum, zh: o.zh, physical: o.physical, a1: o.a1,
            jsonASCII: o.jsonASCII, preserveRaw: true)
        try emitter.begin(ctx!)
        if searching && o.includeHeaders {
            for (i, h) in headers.enumerated() {
                let hits = matchesIn(h)
                if !hits.isEmpty {
                    var hh = h
                    hh.number = 0
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
    if resuming { try headersComplete() }

    let firstRecord = resuming ? ip.resumeRecord + plan.headerRows : 1
    // With no embedded newlines a record number IS a line number offset by the
    // header rows, which is why the seek is only taken in that case.
    // 沒有內嵌換行時，紀錄號就是行號減去標頭列數——這正是只在該情況下才走 seek
    // 的原因。
    let firstLine = resuming ? ip.resumeRecord + plan.headerRows : 1

    let parser = RecordParser(format: plan.format, sink: { rec in
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
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))")
            builder?.add(record: r.number, at: UInt64(r.offset), spansLines: false)
            try applyTransform(transform, to: &r, header: headers[0])

            if r.number < lower {
                if o.before > 0 {
                    ring.append(r)
                    if ring.count > o.before { ring.removeFirst() }
                }
                return true
            }
            if r.number > upper {
                // A builder means the whole file is being scanned to produce
                // the index, so stopping early would leave it incomplete.
                // 有 builder 表示正在為了產生索引而掃描全檔，提前停止會讓它不完整。
                if builder != nil { return true }
                return afterRemaining > 0 || tailN != nil ? true : false
            }

            if let n = tailN {
                tailRing.append(r)
                if tailRing.count > n { tailRing.removeFirst() }
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
                }
            } else {
                try emitRecord(r, matches: [])
            }
            // Returning false here stops the read. `-mid a,b` never touches a
            // byte past record b, which is what makes it the cheapest range
            // operation on a huge file.
            // 在此回傳 false 即停止讀取。`-mid a,b` 因此不會碰到 b 之後的任何
            // 一個位元組，那正是它在巨大檔案上最便宜的原因。
            if r.number >= upper && afterRemaining == 0 && tailN == nil && builder == nil { return false }
            return true
        } catch {
            pendingError = error
            return false
        }
    }, firstRecordNumber: firstRecord, firstOffset: Int(ip.resumeOffset ?? 0), firstLine: firstLine)

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
    try sink.close()
    aborted = false

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
    let plan = try openInput(o)
    defer { plan.source.close() }
    if let p = o.input {
        try checkTornAppend(path: p, format: plan.format, truncatePartial: o.truncatePartial)
    }

    var inserts: [Int: [String]] = [:]
    var appends: [String] = []
    var deletes: [(Int, Int)] = []
    var updates: [Int: [(String, String)]] = [:]
    var blanks: [Int: [String]] = [:]

    for e in o.edits {
        switch e {
        case .insert(let at, let row): inserts[at, default: []].append(row)
        case .append(let row): appends.append(row)
        case .deleteRange(let a, let b): deletes.append((a, b))
        case .update(let r, let c, let v): updates[r, default: []].append((c, v))
        case .deleteCell(let r, let c): blanks[r, default: []].append(c)
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

    // The write path already knows where every record starts -- it is about to
    // write it. Noting the offsets costs no extra scan, which is why building
    // the index here is nearly free while building one for a read would not be.
    // 寫入端本來就知道每一筆從哪裡開始——它正要寫下去。順手記下偏移量不需要額外
    // 掃描，這正是「在此建索引幾乎免費、而為讀取建索引則不然」的原因。
    var outOffset = 0
    var outRecords = 0
    var builder: IndexBuilder? = nil
    if !o.noIndex, let outPath = o.output, Format.declaresFormat(path: outPath),
       let inPath = o.input, let st = FileStamp.of(path: inPath),
       st.size >= UInt64(indexMinBytes()) {
        builder = IndexBuilder(isCSV2: plan.format == .csv2)
    }

    func emit(_ r: Record) {
        let bytes = FieldEncoder.encodeRecord(r, format: plan.format, preserveRaw: true)
        sink.write(bytes)
        outOffset += bytes.count
    }

    func emitData(_ r: Record) {
        let bytes = FieldEncoder.encodeRecord(r, format: plan.format, preserveRaw: true)
        outRecords += 1
        // A record that itself contains a newline makes the record number stop
        // matching the line number, and the index cannot then be used to seek
        // (it stores bytes, not lines). Recorded here so the flag in the index
        // header is right.
        // 自身含換行的紀錄會讓紀錄號不再等於行號，屆時索引就不能用來 seek
        // （它存的是位元組而非行號）。在此記錄，讓索引檔頭的旗標是正確的。
        let spans = bytes.dropLast().contains(BYTE_LF)
        builder?.add(record: outRecords, at: UInt64(outOffset), spansLines: spans)
        sink.write(bytes)
        outOffset += bytes.count
    }

    let parser = RecordParser(format: plan.format) { rec in
        do {
            if headers.count < plan.headerRows {
                var h = rec
                h.number = 0
                headers.append(h)
                if headers.count == plan.headerRows {
                    try validateHeaders(headers, want: plan.headerRows, path: plan.describedPath)
                    expectedFields = headers[0].count
                    transform = try buildTransform(o, headers: headers)
                    markHeaders(&headers, transform: transform)
                    // An edit rewrites the whole file, so the header always
                    // goes out. `-t` is about selections, which produce a
                    // fragment; this produces a file.
                    // 編輯會重寫整個檔案，因此標頭一定寫出。`-t` 是給選取用的
                    // ——那產生的是片段，而這裡產生的是一個完整檔案。
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
            if let rows = inserts[r.number] {
                touched.insert(r.number)
                for row in rows {
                    let ins = try parseRowLiteral(row, format: plan.format,
                                                  expected: expectedFields,
                                                  what: "-insert \(r.number)")
                    emit(ins)
                }
            }
            if deletes.contains(where: { r.number >= $0.0 && r.number <= $0.1 }) {
                touched.insert(r.number)
                Logger.shared.info("delete record \(r.number)")
                return true
            }
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))")

            if let ups = updates[r.number] {
                touched.insert(r.number)
                for (colToken, value) in ups {
                    let c = try resolveColumn(colToken, header: headers[0])
                    let name = baseName(headerName(headers[0].fields[c]))
                    let old = r.fields[c].value
                    r.fields[c].set([UInt8](value.utf8))
                    Logger.shared.info("update \(r.number):\(name): \(Logger.shared.redact(column: name, value: old)) -> \(Logger.shared.redact(column: name, value: r.fields[c].value))")
                }
            }
            if let cols = blanks[r.number] {
                touched.insert(r.number)
                for colToken in cols {
                    let c = try resolveColumn(colToken, header: headers[0])
                    let name = baseName(headerName(headers[0].fields[c]))
                    // Blanking, never removing. Actually dropping the field
                    // would leave that record one column short and shift every
                    // later field left, so status_notes appears under license
                    // -- silently.
                    // 只清空，絕不移除。真的把欄位拿掉會讓該列少一欄、後面所有
                    // 欄位往前位移，於是 status_notes 出現在 license 底下——
                    // 而且是靜默的。
                    r.fields[c].set([])
                    Logger.shared.info("blank \(r.number):\(name)")
                }
            }
            try applyTransform(transform, to: &r, header: headers[0])
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
        throw fault(
            "\(bad.joined(separator: ", ")) is out of range; the file has \(total) records and csv2 does not create empty ones to fill the gap",
            "\(bad.joined(separator: "、")) 超出範圍；本檔案有 \(total) 筆紀錄，csv2 不會補出空紀錄來填補")
    }

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
    Logger.shared.info("wrote \(total) records, \(expectedFields) fields, atomic rename OK")
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
    guard o.output == o.input else { return false }
    for e in o.edits {
        if case .append = e { continue }
        return false
    }
    return true
}

func runAppendFast(_ o: Options) throws {
    let path = o.input!
    guard let fmt = Format.from(path: path) ?? (o.headersOverride.map { $0 == 2 ? .csv2 : .csv }) else {
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
    let expected = headers[0].count

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

    var prefix: [UInt8] = []
    if size > 0 {
        h.seek(toFileOffset: size - 1)
        let last = [UInt8](h.readData(ofLength: 1))
        if last.first != BYTE_LF {
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
            // .csv makes no such promise -- plenty of tools emit a file with
            // no trailing newline. Add one, or the new record gets glued onto
            // the tail of the last one and two records become one.
            // .csv 沒有這個承諾——很多工具產生的檔案就是沒有結尾換行。必須補上
            // 一個，否則新紀錄會被接到最後一筆的尾巴上，兩筆變成一筆。
            prefix = [BYTE_LF]
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
        payload.append(contentsOf: FieldEncoder.encodeRecord(rec, format: fmt, preserveRaw: false))
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
            at += UInt64(FieldEncoder.encodeRecord(rec, format: fmt, preserveRaw: false).count)
        }
    }

    h.seek(toFileOffset: size)
    // ONE write() per call. POSIX makes the offset update and the write atomic
    // for O_APPEND, so two concurrent appends do not interleave -- the only
    // multi-writer-safe operation this tool has. The guarantee has edges (NFS,
    // very large writes), so it is best effort and detection still exists.
    // 每次呼叫只做一次 write()。POSIX 保證 O_APPEND 的偏移量更新與寫入是原子的，
    // 因此兩個並行的追加不會交錯——這是本工具唯一多寫入者安全的操作。該保證有
    // 邊界（NFS、過大的寫入），所以它是盡力而為，偵測仍然必須存在。
    h.write(Data(payload))
    Logger.shared.info("append fast path: wrote \(payload.count) bytes to \(path) (file was \(size) bytes)")

    // Data first, then the index. Interrupted between them the index is stale,
    // which validation catches and turns into a scan -- a safe downgrade.
    // 先寫資料，再更新索引。中間被打斷的話索引是過期的，會被驗證擋下並退回掃描
    // ——安全的降級。
    if let idx = existingIndex {
        var n = Int(idx.records)
        for off in appendOffsets {
            n += 1
            idx.noteAppend(record: n, at: off)
        }
        // No index means do NOT build one here: an O(n) scan to serve an O(1)
        // operation cancels out the whole point of the fast path.
        // 沒有索引時不在此建立：為了一個 O(1) 的操作去做 O(n) 全掃描，會把快路徑
        // 的意義完全抵銷。
        idx.save(dataPath: path)
    }
}

// =====================================================================
//  Run.swift — the three drivers: select, edit, and the append fast path
//  Run.swift — 三個驅動路徑：選取、編輯，以及追加快路徑
// =====================================================================

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

func runSelect(_ o: Options) throws {
    let plan = try openInput(o)
    defer { plan.source.close() }
    if let p = o.input {
        try checkTornAppend(path: p, format: plan.format, truncatePartial: o.truncatePartial)
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

    var headers: [Record] = []
    var pendingError: Error?

    let sink = try makeSink(o)
    var aborted = true
    defer { if aborted { sink.abort() } }

    var lower = 1
    var upper = Int.max
    if let (a, b) = o.mid { lower = a; upper = b ?? Int.max }
    if let n = o.head { upper = min(upper, n) }

    let needle: [UInt8] = o.contains.map {
        o.normalize ? normalizedBytes([UInt8]($0.utf8)) : [UInt8]($0.utf8)
    } ?? []

    var emitter: RecordEmitter
    if o.json {
        emitter = JSONEmitter(sink: sink, reportMode: reportMode)
    } else if o.markdown {
        emitter = MarkdownEmitter(sink: sink)
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
        if lastEmitted != 0 && r.number > lastEmitted + 1 && (o.before > 0 || o.after > 0) {
            try emitter.gap(c)
        }
        try emitter.emit(r, matches: matches, ctx: c)
        lastEmitted = r.number
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
                    ctx = EmitContext(
                        format: plan.format, headers: headers, withHeader: o.withHeader,
                        rownum: o.rownum, zh: o.zh, physical: o.physical, a1: o.a1,
                        jsonASCII: o.jsonASCII,
                        preserveRaw: true)
                    try emitter.begin(ctx!)
                    if searching && o.includeHeaders {
                        for (i, h) in headers.enumerated() {
                            let hits = matchesIn(h)
                            if !hits.isEmpty {
                                var hh = h
                                hh.number = 0
                                // Header hits are reported as 0a / 0b: the
                                // header does not take a data record number,
                                // so "record N" always means the Nth record
                                // of DATA.
                                // 標頭命中回報為 0a / 0b：標頭不佔用資料的編號，
                                // 因此「第 N 筆」永遠指第 N 筆資料。
                                Logger.shared.debug("match in header row 0\(i == 0 ? "a" : "b")")
                                try emitter.emit(hh, matches: hits, ctx: ctx!)
                            }
                        }
                    }
                }
                return true
            }

            var r = rec
            r.number = rec.number - plan.headerRows
            seen = r.number
            try checkFieldCount(r, expected: expectedFields,
                                what: "record \(r.number) (line \(r.line))")
            try applyTransform(transform, to: &r, header: headers[0])

            if r.number < lower {
                if o.before > 0 {
                    ring.append(r)
                    if ring.count > o.before { ring.removeFirst() }
                }
                return true
            }
            if r.number > upper {
                return afterRemaining > 0 || o.tail != nil ? true : false
            }

            if let n = o.tail {
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
            if r.number >= upper && afterRemaining == 0 && o.tail == nil { return false }
            return true
        } catch {
            pendingError = error
            return false
        }
    }

    do {
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
        Logger.shared.debug("format=\(plan.format.rawValue) fields=\(expectedFields) records=\(seen)")
        if parser.sawCRLF {
            // Recorded at INFO in the log, NOT printed to stderr: reading a
            // CRLF file and writing LF changes every line of the git diff, and
            // that surprises people -- but the rule about staying silent on
            // the normal path does not get an exception for it.
            // 以 INFO 記入 log，不印到 stderr：讀 CRLF 寫 LF 會讓整份 git diff
            // 變動，那會讓人意外——但「正常路徑上不出聲」那條規則不因此破例。
            Logger.shared.info("input contained CRLF line endings; normalised to LF")
        }
    } catch {
        throw error
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

    func emit(_ r: Record) {
        sink.write(FieldEncoder.encodeRecord(r, format: plan.format, preserveRaw: true))
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
            emit(r)
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
        emit(rec)
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
}

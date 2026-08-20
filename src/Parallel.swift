// =====================================================================
//  Parallel.swift — multi-core search
//  Parallel.swift — 多核搜尋
//
//  THE ACCEPTANCE CONDITION IS THE POINT: parallel and single-threaded
//  output must be BYTE-IDENTICAL. This project's failures are mostly
//  silent, and parallelising is especially good at producing results that
//  are correct most of the time.
//  驗收條件就是重點：平行與單執行緒的輸出必須逐位元相同。本專案的失敗多半是
//  靜默的，而平行化尤其擅長產生「大部分情況正確」的結果。
//
//  CSV cannot be split at an arbitrary byte offset: whether an offset sits
//  inside quotes or outside changes the meaning entirely, and knowing which
//  requires reading from the start of the file. So "multi-core" cannot mean
//  "cut the file into N pieces and parse each".
//  CSV 無法從任意位元組位移切開：一個位移落在引號內或引號外，語意完全不同，
//  而要知道自己在不在引號內，必須從檔案開頭讀過來。所以「多核」不能是
//  「把檔案切成 N 段各自解析」。
//
//  This takes the plan's recommended route, the third of the three: a cheap
//  single-threaded pass to find record boundaries, then fully parallel work
//  after it. It is enabled only where the boundaries are knowable without
//  speculation -- one record per line -- which is exactly the guarantee
//  `.csv2` makes, and which every `.csv` in this repository also happens to
//  satisfy.
//  此處採用計畫三條路線中建議的第三條：先做一次便宜的單執行緒掃描建立紀錄邊界，
//  之後完全平行。只在「邊界不需推測即可得知」時啟用——也就是一筆一行——那正是
//  `.csv2` 的保證，而本 repo 內每一份 `.csv` 恰好也滿足它。
// =====================================================================

import Foundation
import Dispatch

/// Chunks are a FIXED small size with a work queue, never "file size / P".
/// The latter would cut a 100 GiB file into eight 12.5 GiB pieces, and the
/// guest has 2-4 GiB. Memory here is workers x chunk size, which is bounded
/// by neither the file nor the core count getting larger.
/// 區塊是固定的小尺寸配工作佇列，絕不是「檔案大小 ÷ P」。後者會把 100 GiB 切成
/// 8 個 12.5 GiB 的區塊，而 guest 只有 2–4 GiB。此處的記憶體是「工作者數 × 區塊
/// 大小」，不隨檔案變大，也不隨核心數變大。
let PARALLEL_CHUNK_DEFAULT = 4 * 1024 * 1024

/// Overridable for the same reason as the thresholds: the chunk boundary is
/// where a parallel implementation goes wrong, and testing it with a 4 MiB
/// chunk needs a file big enough to have several of them. A test that only
/// ever produces ONE chunk exercises no boundary at all and would pass on an
/// implementation that had no chunking logic.
/// 可覆寫的理由與門檻相同：區塊邊界正是平行實作出錯的地方，而以 4 MiB 的區塊
/// 測試它，需要一個大到能切出好幾塊的檔案。一個永遠只產生「一個區塊」的測試
/// 完全沒有測到邊界，在一個根本沒有切塊邏輯的實作上也會通過。
var PARALLEL_CHUNK_BYTES: Int {
    if let v = ProcessInfo.processInfo.environment["CSV2_PARALLEL_CHUNK_BYTES"],
       let n = Int(v), n > 0 {
        return n
    }
    return PARALLEL_CHUNK_DEFAULT
}

func parallelMinBytes() -> Int {
    // Overridable so the logic can be tested without a 16 MiB fixture, and so
    // the single-threaded path can be forced for the comparison that IS the
    // acceptance condition. Set it above the file size to disable.
    // 可覆寫，讓這條邏輯不需要 16 MiB 的 fixture 就能測試，也讓「與單執行緒比對」
    // 這個驗收條件能強制走單執行緒路徑。設成大於檔案大小即可停用。
    if let v = ProcessInfo.processInfo.environment["CSV2_PARALLEL_MIN_BYTES"], let n = Int(v) {
        return n
    }
    return 16 * 1024 * 1024
}

/// The ceiling on what the in-flight chunks may hold, in bytes.
///
/// Only the OUTPUT fragments are governed by it. The input side is bounded
/// already: a worker reads its chunk 64 KiB at a time and never holds more.
/// The output side is not bounded by anything the file can tell you in
/// advance -- a search that matches every record produces a report as large as
/// the data -- and one batch of it is held so the fragments can be written in
/// chunk order, which is what makes the parallel output byte-identical to the
/// single-threaded output.
///
/// Measured on a 615 MB file whose every record matched: peak RSS 52 MB with
/// one chunk in flight, 63 MB with two, 102 MB with five, 160 MB with ten. It
/// is the one part of this path that concurrency really does drive, so it is
/// the one part a cap can control.
///
/// 「同時在飛的區塊」可以持有的位元組上限。
///
/// 它只管「輸出」那一側。輸入側本來就有界：一個工作者以 64 KiB 為單位讀自己的區塊，
/// 從不多持有。輸出側則沒有任何「事先從檔案看得出來」的界限——一個命中每一筆的搜尋，
/// 產生的報告會和資料一樣大——而一整批的輸出必須被持有，才能依區塊順序寫出，
/// 那正是平行輸出能與單執行緒逐位元相同的原因。
///
/// 在一個「每一筆都命中」的 615 MB 檔案上實測：同時 1 個區塊時峰值 RSS 52 MB、
/// 2 個 63 MB、5 個 102 MB、10 個 160 MB。這是這條路徑上唯一真的由並行度驅動的部分，
/// 因此也是唯一一個「設上限」管得到的部分。
func parallelMaxBytes() -> Int {
    if let v = ProcessInfo.processInfo.environment["CSV2_PARALLEL_MAX_BYTES"], let n = Int(v), n > 0 {
        return n
    }
    return 1 << 30
}

func workerCount() -> Int {
    // Fixed to the machine, with no flag: `-n` is taken by the record-number
    // column. Same choice swift_tar makes.
    // 固定取決於機器，不提供旗標：`-n` 已被列號欄位佔用。與 swift_tar 的做法相同。
    max(1, ProcessInfo.processInfo.activeProcessorCount)
}

/// Only the locating report is parallelised. Its output is one short line per
/// matching CELL, so the fragments held in memory while chunks are in flight
/// stay small. `--filter` emits whole records and could hold a copy of the
/// entire file, which would trade the memory bound for speed -- on a machine
/// that has 2-4 GiB, that is the wrong trade.
/// 只有定位報告走平行。它的輸出是每個命中儲存格一行短文字，因此區塊在處理中時
/// 保留在記憶體裡的片段很小。`--filter` 輸出的是完整紀錄，可能等於整個檔案的
/// 副本——那是拿記憶體上界去換速度，而在一台只有 2–4 GiB 的機器上，那是錯的交換。
/// Returns the reason parallelism was declined, or nil when it can run.
///
/// A REASON rather than a bare false, because "did the parallel path run?"
/// cannot be answered from outside the process otherwise. The acceptance
/// condition for parallelism is that its output is byte-identical to
/// single-threaded, and the environment knobs exist so that condition can be
/// tested on a small file -- but a test that compares two runs proves nothing
/// if both silently took the same path, and identical output is exactly what
/// that looks like. Reported through -debug so the difference is observable.
/// Found on 2026-08-18 by a reader who set the knobs, got byte-identical
/// output, and correctly refused to call it a pass.
///
/// 回傳「拒絕平行化的理由」，能夠平行時回傳 nil。
/// 是「理由」而不是單純的 false，因為否則「平行路徑到底有沒有跑」從行程外面無法回答。
/// 平行化的驗收條件是「輸出與單執行緒逐位元相同」，而那些環境變數的存在，正是為了讓這個
/// 條件能在小檔案上被測試——但若兩次執行其實都走了同一條路，比對兩者什麼也證明不了，
/// 而「輸出相同」看起來就正是那個樣子。透過 -debug 回報，使這個差別可被觀察。
/// 2026-08-18 由一位讀者發現：他設了那些旋鈕、得到逐位元相同的輸出，並且正確地拒絕
/// 把那稱為通過。
func parallelDeclineReason(_ o: Options, format: Format) -> String? {
    if o.contains == nil { return "not a search; parallelism applies to -contains only" }
    if o.filter { return "--filter" }
    if o.markdown { return "-md" }
    if o.after != 0 || o.before != 0 { return "-A/-B/-C" }
    if o.head != nil || o.tail != nil || o.mid != nil { return "-head/-tail/-mid" }
    if o.encryptCols != nil || o.decryptCols != nil || o.hashCols != nil { return "a transform" }
    if !o.edits.isEmpty { return "an edit" }
    guard let path = o.input else { return "stdin (the file must be seekable)" }
    if workerCount() <= 1 { return "one core" }
    guard let st = FileStamp.of(path: path) else { return "the file could not be stamped" }
    if st.size < UInt64(parallelMinBytes()) {
        return "file is \(st.size) bytes, under CSV2_PARALLEL_MIN_BYTES (\(parallelMinBytes()))"
    }
    // One record per line is the precondition. `.csv2` guarantees it; a `.csv`
    // is only trusted when an index that was built by scanning says so.
    // 前提是一筆一行。`.csv2` 保證了這一點；`.csv` 只有在「由掃描建立的索引這麼說」
    // 時才被信任。
    if format == .csv2 { return nil }
    // --no-index says "never read or write a sidecar", and this was the one
    // place that read one anyway. It did not print, return or write anything
    // from the index -- it only let the index decide which path ran -- which
    // is exactly why nothing caught it: the flag's effect was invisible except
    // in the record numbers. It also meant the documented escape hatch did not
    // escape. Anyone reaching for --no-index because they suspect the sidecar
    // got the sidecar's answer.
    // --no-index 的意思是「絕不讀寫 sidecar」，而這裡是唯一仍然去讀的地方。它不曾從索引
    // 取出任何東西來印、來回傳或來寫入——它只是讓索引決定走哪一條路——而那正是沒有東西
    // 抓到它的原因：那個旗標的作用除了紀錄號之外看不見。它同時也讓那條寫在文件裡的逃生口
    // 逃不掉：因為懷疑 sidecar 而伸手去拿 --no-index 的人，拿到的還是 sidecar 的答案。
    if o.noIndex { return "--no-index, and a .csv needs an index to prove one record per line" }
    // No logging HERE: this is a pure query, asked more than once per run, so
    // anything it prints prints twice. What load itself says about discarding a
    // sidecar is deduplicated inside load, once per sidecar per run, which is
    // the only place that can see both calls. The trust line lives at the
    // single point of use in runParallelSearch.
    // 此處不記錄：這是純查詢，一次執行會被問不只一次，它印的任何東西都會印兩次。而 load
    // 自己對「丟棄某個 sidecar」所說的話，在 load 內部依 sidecar 去重、每次執行只說一次
    // ——那是唯一看得到兩次呼叫的地方。那行「採信」放在 runParallelSearch 裡唯一的使用點。
    if let idx = CSVIndex.load(dataPath: path) {
        if idx.noEmbeddedNewlines { return nil }
        // Distinguished from "no index" because the remedy is not the same.
        // Telling someone to run --build-index here sends them to rebuild an
        // index that will reach the identical conclusion: the file really does
        // have a record spanning lines, and the single-threaded path is not a
        // fallback but the correct answer.
        // 與「沒有索引」分開，因為解法不同。在這裡叫人去跑 --build-index，是讓他重建一份
        // 會得到完全相同結論的索引：這個檔案確實有一筆紀錄跨行，而單執行緒不是退而求其次，
        // 它就是正確答案。
        return ".csv whose index records a record spanning lines; a record number is not a line number here"
    }
    // Three different situations used to end here with one message, and the
    // message asserted there was no index while a sidecar sat beside the data.
    // It then told the reader to --build-index, which is what they had just
    // done. A blind-test subject lost several minutes to it and said so.
    //
    // The three are separated now because the remedy differs: build one,
    // rebuild the one that is there, or nothing (the file genuinely spans
    // lines -- handled above). Naming the sidecar matters more than the
    // wording: "no index" beside a file called `x.csv.index` is the kind of
    // statement that makes someone doubt what they can see.
    //
    // 原本三種不同的情況都走到這裡、印出同一句話，而那句話宣稱「沒有索引」——當時 sidecar
    // 就躺在資料旁邊。它接著叫人去 --build-index，而那正是對方剛剛做過的事。一位盲測受測者
    // 為此損失了好幾分鐘，並且寫了下來。
    //
    // 現在三者分開，因為解法不同：建立一個、重建已經在那裡的那一個、或什麼都不必做（檔案
    // 真的跨行——在上面處理）。指名那個 sidecar 比措辭更要緊：在一個叫做 `x.csv.index` 的
    // 檔案旁邊說「沒有索引」，是那種會讓人懷疑自己眼睛的說法。
    let sidecar = CSVIndex.path(for: path)
    if FileManager.default.fileExists(atPath: sidecar) {
        // The reason goes IN the message. It used to say "run with -debug to
        // see why", which is advice for someone who is not running with
        // -debug -- and this line is only visible to someone who is. The
        // reader was told to do the thing they were already doing, while the
        // answer sat one line above at INFO.
        // 理由寫「進」訊息裡。原本寫的是「用 -debug 看原因」，那是給「沒有在用 -debug 的人」
        // 的建議——而這一行只有正在用 -debug 的人看得到。讀者被叫去做他已經在做的事，
        // 而答案就在上一行的 INFO 裡。
        let why = CSVIndex.lastDiscardReason ?? "reason not recorded"
        return ".csv whose index \(sidecar) was discarded (\(why)); --build-index replaces it"
    }
    return ".csv with no index proving one record per line; build one with --build-index"
}

func canRunParallelSearch(_ o: Options, format: Format) -> Bool {
    parallelDeclineReason(o, format: format) == nil
}

private struct ChunkSpan {
    var start: UInt64
    var end: UInt64
    var firstRecord: Int
    var records: Int
}

/// Pass one: find the record boundaries. Single-threaded and cheap -- it only
/// looks for newlines, never parses fields.
/// 第一遍：找出紀錄邊界。單執行緒且便宜——它只找換行，完全不解析欄位。
private func planChunks(path: String, from headEnd: UInt64, size: UInt64) throws -> [ChunkSpan] {
    guard let h = FileHandle(forReadingAtPath: path) else {
        throw fault("cannot open input file: \(path)", "無法開啟輸入檔：\(path)")
    }
    defer { try? h.close() }

    // Candidate cut points, then each is pushed forward to the byte after the
    // next newline so that every chunk begins on a record boundary. A boundary
    // reached this way needs no knowledge of what came before it, which is the
    // property that makes the parallel pass safe.
    // 先取候選切點，再各自往後推到下一個換行之後的位元組，使每個區塊都從紀錄
    // 邊界開始。以這種方式取得的邊界不需要知道前文，這正是讓平行那一遍安全的性質。
    var cuts: [UInt64] = [headEnd]
    var probe = headEnd + UInt64(PARALLEL_CHUNK_BYTES)
    while probe < size {
        h.seek(toFileOffset: probe)
        let window = [UInt8](h.readData(ofLength: 1 << 16))
        if window.isEmpty { break }
        if let nl = window.firstIndex(of: BYTE_LF) {
            let boundary = probe + UInt64(nl) + 1
            if boundary < size, boundary > cuts[cuts.count - 1] { cuts.append(boundary) }
            probe = boundary + UInt64(PARALLEL_CHUNK_BYTES)
        } else {
            probe += UInt64(window.count)
        }
    }
    cuts.append(size)

    var spans: [ChunkSpan] = []
    for i in 0..<(cuts.count - 1) {
        spans.append(ChunkSpan(start: cuts[i], end: cuts[i + 1], firstRecord: 0, records: 0))
    }

    // Count the records in each span, so every chunk knows the number of its
    // first record. Get this wrong and the tool reports the right cell at the
    // wrong address -- which looks entirely plausible.
    // 數出每個區間的紀錄數，讓每個區塊知道自己第一筆的編號。這裡算錯，工具會在
    // 錯誤的位址上回報正確的儲存格——而那看起來完全合理。
    var running = 1
    for i in spans.indices {
        h.seek(toFileOffset: spans[i].start)
        var remaining = Int(spans[i].end - spans[i].start)
        // The pool is the point, not the read. This loop walks the WHOLE file
        // -- it is how each chunk learns its first record number -- and on
        // Darwin every `Data` returned here survived until the process exited,
        // so peak RSS came to about one byte per byte of input. 615 MB in,
        // 608 MB resident, while the single-threaded path over the same file
        // stayed at 9.5 MB.
        //
        // The measurement that found it: forcing the batch size down to 1, so
        // that exactly one chunk is in flight at a time, changed peak RSS by
        // half a percent (637 MB against 640 MB). Nothing that scales with
        // work IN FLIGHT can behave like that, which ruled out the workers and
        // left the one loop that touches every byte outside a pool.
        //
        // Third occurrence of the same defect: ByteSource.next carries the
        // same comment, and the parallel worker's read loop needed the same
        // fix an hour earlier. See Platform.drainingPool.
        //
        // 重點是那個 pool，不是那次讀取。這個迴圈會走過「整個檔案」——每個區塊就是靠它
        // 知道自己第一筆的編號——而在 Darwin 上，這裡回傳的每一個 `Data` 都活到行程結束，
        // 於是峰值 RSS 大約是「輸入每一個位元組對應一個位元組」。讀進 615 MB，常駐 608 MB，
        // 而同一個檔案在單執行緒路徑上是 9.5 MB。
        //
        // 找到它的那次量測：把批次大小強制降到 1，也就是同時只有一個區塊在飛，峰值 RSS 只
        // 變動了百分之零點五（637 MB 對 640 MB）。任何隨「同時在飛的工作量」而變的東西都
        // 不可能是這種行為——這排除了工作者，只剩下那個「在 pool 之外走過每一個位元組」的
        // 迴圈。
        //
        // 這是同一個缺陷的第三次出現：`ByteSource.next` 帶著同一段註解，而平行工作者的讀取
        // 迴圈在一小時前才需要同樣的修正。見 Platform.drainingPool。
        var count = 0
        while remaining > 0 {
            let n = Platform.drainingPool { () -> Int in
                let want = min(remaining, 1 << 20)
                let d = h.readData(ofLength: want)
                if d.isEmpty { return 0 }
                for b in d where b == BYTE_LF { count += 1 }
                return d.count
            }
            if n == 0 { break }
            remaining -= n
        }
        spans[i].firstRecord = running
        spans[i].records = count
        running += count
    }
    return spans
}

/// Pass two: fully parallel. Chunks run in batches of `workerCount()` and each
/// batch's fragments are written in chunk order before the next batch starts,
/// so the output is identical to the single-threaded order while the memory
/// held stays workers x (chunk + fragment) rather than the whole file.
/// 第二遍：完全平行。區塊以 `workerCount()` 為一批執行，每一批的片段按區塊順序
/// 寫出後才開始下一批，因此輸出順序與單執行緒相同，而持有的記憶體是
/// 「工作者數 ×（區塊 + 片段）」而非整個檔案。
func runParallelSearch(_ o: Options) throws {
    let plan = try openInput(o)
    plan.source.close()
    let path = o.input!
    guard let st = FileStamp.of(path: path) else {
        throw fault("cannot stat \(path)", "無法取得 \(path) 的狀態")
    }

    // Every path that DECLINES the index names it and says why; the path that
    // TRUSTS it said nothing at all. The asymmetry ran the wrong way: by the
    // size+mtime stamp's own limits a trusted index can be stale, so this is
    // the only branch that can be silently wrong -- and it was the only one
    // leaving no trace. An operator reading -debug could see why a sidecar was
    // rejected but never that one had been believed, nor which file it was.
    // 每一條「拒絕」索引的路徑都會指名它並說明理由；而「採信」它的那條什麼都不說。
    // 這個不對稱正好反了：依 size+mtime 戳記自身的限制，被採信的索引可能是過期的，
    // 因此這是唯一可能靜默給出錯誤答案的分支——卻也是唯一不留痕跡的。讀 -debug 的人
    // 看得到 sidecar 為何被拒，卻看不到它被信了、信的是哪一個檔案。
    if plan.format != .csv2, let idx = CSVIndex.load(dataPath: path), idx.noEmbeddedNewlines {
        Logger.shared.debug(
            "parallel: trusting index \(CSVIndex.path(for: path)), which declares "
            + "no_embedded_newlines; if the file changed since that was built while keeping "
            + "the same size and mtime, record numbers will be wrong -- "
            + "csv2 --verify-index -i \(path) is the O(n) proof")
    }

    let headers = try readHeaderRows(path: path, format: plan.format, want: plan.headerRows)
    let expectedFields = headers[0].count

    // Where the header ends is where the data begins; the first chunk starts
    // there. Recomputed rather than taken from an index, because this path
    // must work with no index at all.
    // 標頭結束處就是資料開始處，第一個區塊從那裡開始。此處重新計算而非取自索引，
    // 因為這條路徑必須在完全沒有索引時也能運作。
    var headEnd: UInt64 = 0
    do {
        let src = try ByteSource(path: path, chunkSize: 1 << 16)
        defer { src.close() }
        var n = 0
        let p = RecordParser(format: plan.format) { r in
            n += 1
            if n == plan.headerRows { headEnd = UInt64(r.offset) + 0 }
            return n < plan.headerRows
        }
        while n < plan.headerRows, let c = src.next() { try p.feed(c) }
        // r.offset is the START of the last header row; advance past its line.
        // r.offset 是最後一列標頭的起點，往後推過它那一行。
        if let h = FileHandle(forReadingAtPath: path) {
            defer { try? h.close() }
            h.seek(toFileOffset: headEnd)
            let d = [UInt8](h.readData(ofLength: 1 << 16))
            if let nl = d.firstIndex(of: BYTE_LF) { headEnd += UInt64(nl) + 1 }
        }
    }

    let spans = try planChunks(path: path, from: headEnd, size: st.size)
    Logger.shared.debug("parallel: \(spans.count) chunks, \(workerCount()) workers, chunk \(PARALLEL_CHUNK_BYTES) bytes")

    let outSink = try makeSink(o)
    var aborted = true
    defer { if aborted { outSink.abort() } }

    let needle: [UInt8] = o.contains.map {
        o.normalize ? normalizedBytes([UInt8]($0.utf8)) : [UInt8]($0.utf8)
    } ?? []

    let ctx = EmitContext(
        format: plan.format, headers: headers, withHeader: o.withHeader,
        rownum: o.rownum, zh: o.zh, physical: o.physical, a1: o.a1,
        jsonASCII: o.jsonASCII, enOnly: o.enOnly, preserveRaw: true)

    if o.json {
        let e = JSONEmitter(sink: outSink, reportMode: true)
        try e.begin(ctx)
    }
    if o.includeHeaders {
        let e: RecordEmitter = o.json ? JSONEmitter(sink: outSink, reportMode: true)
                                      : ReportEmitter(sink: outSink, needle: needle)
        for h in headers {
            var hits: [Int] = []
            for (i, f) in h.fields.enumerated() {
                let hay = o.normalize ? normalizedBytes(f.value) : f.value
                if bytesContain(hay, needle) { hits.append(i) }
            }
            if !hits.isEmpty {
                var hh = h
                hh.number = 0
                try e.emit(hh, matches: hits, ctx: ctx)
            }
        }
    }

    // How many chunks may be in flight at once, decided per batch rather than
    // fixed, because what has to be held is the OUTPUT and no one can know its
    // size before running the search. The first batch is estimated from the
    // chunk size -- a report is rarely larger than the data it describes --
    // and every batch after it uses what the previous batch actually held.
    //
    // 一次可以有多少區塊在飛，是「每一批各自決定」而非固定的，因為必須被持有的是「輸出」，
    // 而沒有人能在搜尋跑完之前知道它有多大。第一批以區塊大小估算——報告很少大於它所描述的
    // 資料——之後每一批都用「上一批實際持有了多少」來決定。
    let cap = parallelMaxBytes()
    var perChunk = PARALLEL_CHUNK_BYTES
    var throttled = false
    var totalRecords = 0
    var matched = 0
    var firstError: Error?
    let lock = NSLock()

    var i = 0
    while i < spans.count {
        let batch = max(1, min(workerCount(), cap / max(perChunk, 1)))
        if batch < workerCount() && !throttled {
            throttled = true
            // Said once, and said with the numbers, because a run that is
            // slower than the machine could be has to be explainable. The
            // alternative -- silently using fewer workers -- is the shape of
            // defect this project keeps finding.
            // 只說一次，而且帶著數字，因為一次「比機器能力慢」的執行必須是可以被解釋的。
            // 另一種做法——安靜地少用幾個工作者——正是本專案一再找到的那種缺陷形狀。
            Logger.shared.debug(
                "parallel: holding \(batch) chunk(s) in flight instead of \(workerCount()); "
                + "the last batch held about \(perChunk) bytes per chunk and "
                + "CSV2_PARALLEL_MAX_BYTES is \(cap)")
        }
        let hi = min(i + batch, spans.count)
        var fragments = [[UInt8]](repeating: [], count: hi - i)
        var counts = [Int](repeating: 0, count: hi - i)

        DispatchQueue.concurrentPerform(iterations: hi - i) { k in
            let span = spans[i + k]
            var bytes: [UInt8] = []
            var hitCount = 0
            do {
                guard let h = FileHandle(forReadingAtPath: path) else { return }
                defer { try? h.close() }
                h.seek(toFileOffset: span.start)

                let memory = ByteSink(memory: ())
                let emitter: RecordEmitter = o.json
                    ? JSONEmitter(sink: memory, reportMode: true)
                    : ReportEmitter(sink: memory, needle: needle)

                // The record number and line are handed to the parser, so a
                // chunk reports exactly the addresses a full scan would.
                // 紀錄號與行號直接交給解析器，因此一個區塊回報的位址與完整掃描
                // 給出的完全相同。
                var localError: Error?
                let parser = RecordParser(format: plan.format,
                                          firstRecordNumber: span.firstRecord + plan.headerRows,
                                          firstOffset: Int(span.start),
                                          firstLine: span.firstRecord + plan.headerRows) { rec in
                    do {
                        var r = rec
                        r.number = rec.number - plan.headerRows
                        try checkFieldCount(r, expected: expectedFields,
                                            what: "record \(r.number) (line \(r.line))")
                        var hits: [Int] = []
                        for (n, f) in r.fields.enumerated() {
                            let hay = o.normalize ? normalizedBytes(f.value) : f.value
                            if bytesContain(hay, needle) { hits.append(n) }
                        }
                        if !hits.isEmpty {
                            hitCount += 1
                            try emitter.emit(r, matches: hits, ctx: ctx)
                        }
                        return true
                    } catch {
                        localError = error
                        return false
                    }
                }

                var remaining = Int(span.end - span.start)
                while remaining > 0 {
                    let more = try Platform.drainingPool { () -> Bool in
                        let d = h.readData(ofLength: min(remaining, 1 << 16))
                        if d.isEmpty { return false }
                        remaining -= d.count
                        try parser.feed([UInt8](d))
                        return !parser.stopped
                    }
                    if !more { break }
                }
                if !parser.stopped { try parser.finish() }
                if let e = localError { throw e }
                bytes = memory.takeBytes()
            } catch {
                lock.lock()
                if firstError == nil { firstError = error }
                lock.unlock()
                return
            }
            lock.lock()
            fragments[k] = bytes
            counts[k] = hitCount
            lock.unlock()
        }

        if let e = firstError { throw e }
        // Written in chunk order, which is what makes the output identical to
        // the single-threaded run.
        // 按區塊順序寫出，這正是輸出能與單執行緒完全相同的原因。
        // What this batch actually held, which decides the next one. Measured
        // before the fragments are written and released, because afterwards
        // there is nothing left to measure.
        // 這一批實際持有了多少，決定下一批的大小。在片段被寫出並釋放「之前」量，
        // 因為之後就沒有東西可以量了。
        perChunk = max(1, fragments.reduce(0) { $0 + $1.count } / max(hi - i, 1))

        for k in 0..<(hi - i) {
            outSink.write(fragments[k])
            matched += counts[k]
        }
        totalRecords = spans[hi - 1].firstRecord + spans[hi - 1].records - 1
        i = hi
    }

    if o.json {
        let e = JSONEmitter(sink: outSink, reportMode: true)
        try e.end(ctx, records: totalRecords, matched: matched)
    }
    try outSink.close()
    aborted = false
    Logger.shared.debug("parallel: \(totalRecords) records, \(matched) matched")
    // The metrics line belongs to every path, not to the one that happens to
    // end in runSelect. -debug is documented as "diagnostics to stderr,
    // including a metrics: line", and this path emitted none -- so
    // peak_rss_bytes was unavailable on exactly the runs where someone would
    // want it, since parallelism is what a large file gets. Round 38, EE.
    //
    // read_bytes is the file size here rather than a counter: the parallel
    // pass reads every chunk, so those are the same number, and reporting a
    // counter that could only ever equal the size would invite the reader to
    // believe it might not.
    // metrics 那一行屬於「每一條路徑」，不屬於「剛好在 runSelect 收尾的那一條」。-debug 的
    // 文件寫的是「診斷輸出到 stderr，包含一行 metrics」，而這條路徑一行都沒有——於是
    // peak_rss_bytes 恰好在「有人會想看它」的那些執行上取不到，因為大檔案拿到的正是平行。
    // 第 38 回合，EE。
    // 此處的 read_bytes 直接用檔案大小而不是計數器：平行那一遍會讀過每一個區塊，因此兩者
    // 是同一個數字；而回報一個「永遠只會等於檔案大小」的計數器，反而會讓讀者以為它可能不等於。
    Metrics.report(bytesRead: Int(st.size), fileSize: Int(st.size))
}

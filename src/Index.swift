// =====================================================================
//  Index.swift — the .csv.index / .csv2.index sidecar
//  Index.swift — .csv.index / .csv2.index sidecar
//
//  THE FIRST RULE, from which everything else follows: the index is always
//  an optimisation and never a precondition. With no index the program must
//  behave EXACTLY the same. No situation may let the index fail an
//  operation, and no situation may let it change the output -- output with
//  and without an index has to be byte-identical.
//  第一條規則，其餘皆由它推導：索引永遠是最佳化，永遠不是必要條件。沒有索引時
//  程式的行為必須完全一樣。任何情況下都不得因為索引而使操作失敗，也不得因為
//  索引而產生不同的輸出——有索引與無索引的輸出必須逐位元相同。
//
//  Therefore the default action on ANY doubt is to discard the index and
//  scan. Not repair, not report. An index that will quickly give you the
//  wrong data is far worse than no index at all.
//  因此只要有任何疑慮，預設動作就是丟棄索引並改用掃描。不修復，也不報錯。
//  一個會很快給你錯資料的索引，比沒有索引糟得多。
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - On-disk layout / 磁碟上的格式
// ---------------------------------------------------------------------
//
//   header 88 bytes
//     0  magic      8   "CSV2IDX\0"
//     8  version    u32  = 1
//    12  flags      u32  bit0 no_embedded_newlines, bit1 format is csv2
//    16  stride     u64  records between stored offsets
//    24  dataSize   u64  size of the data file when the index was written
//    32  mtimeSec   i64
//    40  mtimeNsec  i64
//    48  headEnd    u64  byte just past the last header row
//    56  records    u64  total data records
//    64  hashHead   8    first 8 bytes of SHA-256 over the first 64 bytes
//    72  hashTail   8    first 8 bytes of SHA-256 over the last 64 bytes
//    80  reserved   8
//   entries: u64 LE, one per stride grid point
//
//  Fixed width, so record N's grid entry is at `88 + 8*(N-1)/stride` -- an
//  O(1) seek. Written as one number per line of text it would have to be
//  scanned to find entry N, which is the very cost the index exists to avoid.
//  定寬，因此第 N 筆的格點位於 `88 + 8*(N-1)/stride`——O(1) 直接 seek。若寫成
//  一行一個數字的文字檔，得先掃描索引才能找到第 N 格，那就沒有意義了。
//
//  SPARSE, not one entry per record. A 1 GB file at 500 bytes a row is two
//  million records; a dense index would be 16 MB. stride 256 makes it 64 KB,
//  and the forward parse from a grid point is at most 255 records -- a few
//  tens of KB, one or two disk reads, negligible against the whole-file read
//  it replaces.
//  稀疏，不是每筆都存。1 GB、每列 500 bytes 是 200 萬筆，密集索引要 16 MB；
//  stride 256 讓它變成 64 KB，而從格點向前解析至多 255 筆——幾十 KB，一兩次
//  磁碟讀取，與它省下的整檔讀取相比可以忽略。

let INDEX_MAGIC: [UInt8] = Array("CSV2IDX\0".utf8)
/// 2 since 2026-08-18: the header gained a checksum over the index's own bytes.
/// A version 1 index has zeros where the checksum belongs and is discarded on
/// sight, which is the correct outcome -- it was written by a build that could
/// not detect corruption in itself.
/// 自 2026-08-18 起為 2：檔頭新增了一個「涵蓋索引自身位元組」的檢查碼。版本 1 的索引在
/// 該欄位處是零，會被直接丟棄，而那是正確的結果——它是由一個「無法偵測自身損毀」的版本
/// 寫出來的。
// Bumped to 3 on 2026-08-19. Version 2 sidecars were written by a build whose
// no_embedded_newlines flag was computed by two call sites that always said
// "none" -- so a v2 index on a file with a quoted newline asserts a property
// the file does not have, and the parallel path acted on it. Those files are
// still on disk and no check inside them can catch it; only the version can.
// A mismatch is already handled the right way: ignored at INFO, and the scan
// that replaces it is correct.
// 2026-08-19 推進為 3。版本 2 的 sidecar 由一個「no_embedded_newlines 旗標出自兩個
// 恆答『沒有』的呼叫點」的建置寫出——因此含引號換行的檔案旁那份 v2 索引，宣告了一個
// 該檔案並不具備的性質，而平行路徑照著它做了。那些檔案還在磁碟上，且索引內部沒有任何
// 檢查抓得到；只有版本抓得到。版本不符本來就處理得對：以 INFO 忽略，取而代之的掃描
// 是正確的。
let INDEX_VERSION: UInt32 = 3
let INDEX_HEADER_SIZE = 88
let INDEX_DEFAULT_STRIDE = 256

/// Threshold in BYTES, never in rows. Two reasons. Row counts differ by 20x
/// in cost for the same number: TARGET_PACKAGES.csv is 478 bytes a row,
/// marathon-data.csv is 23. And knowing the row count means counting the
/// rows, which is the scan the index exists to avoid; a size is one stat().
/// 門檻以位元組計，絕不以列數計。兩個理由：同樣的列數可能差 20 倍的成本
/// （TARGET_PACKAGES.csv 每列 478 bytes，marathon-data.csv 是 23）；而且要知道
/// 列數就得先數列，那正是索引想省掉的掃描，檔案大小則 stat 一次就有。
func indexMinBytes() -> Int {
    // Overridable not merely for tuning but so this logic can be TESTED:
    // otherwise verifying it needs a 16 MiB fixture.
    // 可覆寫不只是為了調校，是為了能測試——否則驗證這條邏輯需要 16 MiB 的 fixture。
    if let v = ProcessInfo.processInfo.environment["CSV2_INDEX_MIN_BYTES"], let n = Int(v) {
        return n
    }
    return 16 * 1024 * 1024
}

struct FileStamp {
    var size: UInt64
    var mtimeSec: Int64
    var mtimeNsec: Int64
    var hashHead: [UInt8]
    var hashTail: [UInt8]

    static func of(path: String) -> FileStamp? {
        guard let id = Platform.fileIdentity(path: path) else { return nil }
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let head = [UInt8](h.readData(ofLength: 64))
        var tail = head
        if id.size > 64 {
            h.seek(toFileOffset: id.size - 64)
            tail = [UInt8](h.readData(ofLength: 64))
        }
        return FileStamp(size: id.size, mtimeSec: id.mtimeSec, mtimeNsec: id.mtimeNsec,
                         hashHead: Array(SHA256.hash(head).prefix(8)),
                         hashTail: Array(SHA256.hash(tail).prefix(8)))
    }
}

// ---------------------------------------------------------------------
// MARK: - Little-endian helpers / 小端序輔助
// ---------------------------------------------------------------------

@inline(__always) func putU64(_ v: UInt64, into a: inout [UInt8]) {
    for i in 0..<8 { a.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) }
}
@inline(__always) func putU32(_ v: UInt32, into a: inout [UInt8]) {
    for i in 0..<4 { a.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
}
@inline(__always) func getU64(_ a: [UInt8], _ off: Int) -> UInt64 {
    var v: UInt64 = 0
    for i in 0..<8 { v |= UInt64(a[off + i]) << (8 * UInt64(i)) }
    return v
}
@inline(__always) func getU32(_ a: [UInt8], _ off: Int) -> UInt32 {
    var v: UInt32 = 0
    for i in 0..<4 { v |= UInt32(a[off + i]) << (8 * UInt32(i)) }
    return v
}

/// Offset of the checksum inside the header, in the 8 bytes that were reserved
/// and unused until 2026-08-18.
/// 檢查碼在檔頭中的位移，位於 2026-08-18 之前保留而未使用的那 8 個位元組。
let INDEX_SUM_OFFSET = 80

/// FNV-1a over the whole index with the checksum field itself read as zero.
///
/// This detects CORRUPTION -- a flipped bit, a short write, a partially
/// overwritten file. It is not a signature and does not pretend to be: anyone
/// who can rewrite the offsets can rewrite eight more bytes. Against that,
/// --verify-index is the answer, and it is O(n) for the reason that it has to
/// be. FNV-1a rather than something stronger because the cost falls on every
/// indexed read and the threat is a bit flip, not an adversary.
///
/// 以 FNV-1a 計算整份索引，並把檢查碼欄位本身當成零。
/// 它偵測的是「損毀」——翻轉的位元、寫入不完整、被部分覆寫的檔案。它不是簽章，也不假裝是：
/// 能改寫偏移量的人，同樣能改寫另外八個位元組。對付那種情況的答案是 --verify-index，
/// 而它之所以是 O(n)，正因為它非得是不可。選 FNV-1a 而非更強的演算法，是因為這個成本落在
/// 每一次「用到索引的讀取」上，而威脅是一個位元翻轉，不是一個對手。
func indexChecksum(_ b: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for i in 0..<b.count {
        let byte = (i >= INDEX_SUM_OFFSET && i < INDEX_SUM_OFFSET + 8) ? 0 : b[i]
        h ^= UInt64(byte)
        h = h &* 0x1000_0000_01b3
    }
    return h
}

// ---------------------------------------------------------------------
// MARK: - The index / 索引
// ---------------------------------------------------------------------

final class CSVIndex {
    var stride: Int
    var noEmbeddedNewlines: Bool
    var isCSV2: Bool
    var headEnd: UInt64
    var records: UInt64
    var stamp: FileStamp
    /// Offset of the first record of each grid point: entry g is record
    /// g*stride + 1. / 每個格點第一筆的偏移量：第 g 格是第 g*stride + 1 筆。
    var offsets: [UInt64]

    init(stride: Int, noEmbeddedNewlines: Bool, isCSV2: Bool,
         headEnd: UInt64, records: UInt64, stamp: FileStamp, offsets: [UInt64]) {
        self.stride = stride
        self.noEmbeddedNewlines = noEmbeddedNewlines
        self.isCSV2 = isCSV2
        self.headEnd = headEnd
        self.records = records
        self.stamp = stamp
        self.offsets = offsets
    }

    static func path(for dataPath: String) -> String { dataPath + ".index" }

    // -----------------------------------------------------------------
    // Loading and validation / 讀取與驗證
    // -----------------------------------------------------------------

    /// Every check is O(1), and the result is a HEURISTIC, not a proof:
    /// `rsync -t`, `cp -p` and `tar -p` all preserve mtime, so a file with the
    /// same size and mtime but different content can be constructed. The
    /// head/tail hashes catch the overwhelming majority. Anyone who needs
    /// certainty runs --verify-index, which is O(n).
    /// 所有檢查都是 O(1)，而結果是啟發式而非證明：`rsync -t`、`cp -p`、`tar -p`
    /// 都會保留 mtime，因此可以構造出「大小與 mtime 相同、內容不同」的檔案。
    /// 前後 64 bytes 的雜湊擋掉絕大多數。需要確定的人用 --verify-index，那是 O(n)。
    /// Why a sidecar was discarded is said ONCE per run, per sidecar.
    ///
    /// `load` is called twice in a run -- once as a pure eligibility query and
    /// once where the index is actually read -- so every "ignoring and
    /// scanning" line below printed twice, reading as two sidecars having been
    /// consulted. Silencing the query instead was tried first and was worse:
    /// on a search that declines the parallel path the query is the ONLY call,
    /// so the reason stopped being printed at all, and the decline message
    /// says "run with -debug to see why". A duplicate is noise; a silence is
    /// the defect this whole area keeps producing.
    ///
    /// 一個 sidecar 為什麼被丟棄，一次執行只說一次。
    ///
    /// `load` 在一次執行中被呼叫兩次——一次是純粹的資格查詢，一次是真的要讀索引的地方——
    /// 因此下面每一句「ignoring and scanning」都印了兩次，讀起來像查了兩個 sidecar。
    /// 先試過的做法是把查詢那一次靜音，而那更糟：在一個「拒絕平行路徑」的搜尋裡，查詢是
    /// 唯一的一次呼叫，於是那個理由變成完全不印——而拒絕訊息卻寫著「用 -debug 看原因」。
    /// 重複只是雜訊；沉默才是這一帶一再產生的那種缺陷。
    private static var announced = Set<String>()

    private static func announceDiscard(_ message: @autoclosure () -> String, for sidecar: String) {
        guard !announced.contains(sidecar) else { return }
        announced.insert(sidecar)
        Logger.shared.info(message())
    }

    static func load(dataPath: String) -> CSVIndex? {
        let p = path(for: dataPath)
        guard let d = FileManager.default.contents(atPath: p) else { return nil }
        // A sidecar too short to hold a header used to be the one discard that
        // said nothing at all -- indistinguishable, from the outside, from
        // having no sidecar. Every other rejection below announces itself.
        // 一個短到裝不下檔頭的 sidecar，原本是唯一一種「什麼都不說」的丟棄——從外面看，
        // 與「根本沒有 sidecar」無法區分。下面每一種拒絕都會說出自己。
        guard d.count >= INDEX_HEADER_SIZE else {
            announceDiscard(
                "index \(p): shorter than an index header (\(d.count) bytes), ignoring and scanning",
                for: p)
            return nil
        }
        let b = [UInt8](d)
        guard Array(b.prefix(8)) == INDEX_MAGIC else {
            announceDiscard("index \(p): bad magic, ignoring and scanning", for: p)
            return nil
        }
        guard getU32(b, 8) == INDEX_VERSION else {
            announceDiscard("index \(p): version mismatch, ignoring and scanning", for: p)
            return nil
        }
        let flags = getU32(b, 12)
        let stride = Int(getU64(b, 16))
        guard stride > 0 else { return nil }
        let dataSize = getU64(b, 24)
        let mtimeSec = Int64(bitPattern: getU64(b, 32))
        let mtimeNsec = Int64(bitPattern: getU64(b, 40))
        let headEnd = getU64(b, 48)
        let records = getU64(b, 56)
        let hashHead = Array(b[64..<72])
        let hashTail = Array(b[72..<80])

        // The stamp checks above all describe the DATA file. Nothing described
        // the index itself, so a flipped bit in an offset passed every one of
        // them: the stamp still matched, the entry count still matched, and the
        // wrong offset was used. On 2026-08-18 a reader corrupted a single byte
        // and `-mid 1,1` returned a fragment beginning mid-field, presented as a
        // record, at rc=0 -- while `-r` on the same file was correct, because it
        // does not consult the index. That is the case the design calls "far
        // worse than no index", produced by the one thing nothing was checking.
        //
        // 上面那些戳記檢查描述的全是「資料檔」。沒有任何東西描述索引本身，因此偏移量裡
        // 一個翻轉的位元能通過其中每一項：戳記仍然相符、項目數仍然相符，於是那個錯誤的
        // 偏移量被採用了。2026-08-18，一位讀者改動了一個位元組，`-mid 1,1` 便回傳了一段
        // 從欄位中間開始的碎片，並以「一筆紀錄」的身分呈現，rc=0——而同一個檔案的 `-r`
        // 是正確的，因為它不使用索引。那正是本設計所稱「比沒有索引糟得多」的情況，
        // 而它出自那個唯一沒有被檢查的東西。
        guard getU64(b, INDEX_SUM_OFFSET) == indexChecksum(b) else {
            announceDiscard("index \(p): checksum mismatch, ignoring and scanning", for: p)
            return nil
        }

        guard let now = FileStamp.of(path: dataPath) else { return nil }
        guard now.size == dataSize, now.mtimeSec == mtimeSec, now.mtimeNsec == mtimeNsec,
              now.hashHead == hashHead, now.hashTail == hashTail else {
            // Stale, not corrupt. Logged at INFO and then ignored -- never an
            // error, because the operation must succeed identically without it.
            // 過期而非損毀。以 INFO 記錄後忽略——絕不是錯誤，因為沒有它時操作
            // 必須以完全相同的方式成功。
            announceDiscard("index \(p) is stale, ignoring and scanning", for: p)
            return nil
        }

        let want = (Int(records) + stride - 1) / stride
        let have = (b.count - INDEX_HEADER_SIZE) / 8
        guard have >= want else {
            // Truncated. Same treatment: discard, scan. Not an error.
            // 被截斷。同樣處理：丟棄、掃描。不是錯誤。
            announceDiscard("index \(p) is truncated (\(have) of \(want) entries), ignoring and scanning", for: p)
            return nil
        }
        var offsets = [UInt64]()
        offsets.reserveCapacity(want)
        for g in 0..<want { offsets.append(getU64(b, INDEX_HEADER_SIZE + 8 * g)) }

        return CSVIndex(stride: stride,
                        noEmbeddedNewlines: (flags & 1) != 0,
                        isCSV2: (flags & 2) != 0,
                        headEnd: headEnd, records: records,
                        stamp: now, offsets: offsets)
    }

    // -----------------------------------------------------------------
    // Writing / 寫出
    // -----------------------------------------------------------------

    func encode() -> [UInt8] {
        var b = [UInt8]()
        b.reserveCapacity(INDEX_HEADER_SIZE + 8 * offsets.count)
        b.append(contentsOf: INDEX_MAGIC)
        putU32(INDEX_VERSION, into: &b)
        var flags: UInt32 = 0
        if noEmbeddedNewlines { flags |= 1 }
        if isCSV2 { flags |= 2 }
        putU32(flags, into: &b)
        putU64(UInt64(stride), into: &b)
        putU64(stamp.size, into: &b)
        putU64(UInt64(bitPattern: stamp.mtimeSec), into: &b)
        putU64(UInt64(bitPattern: stamp.mtimeNsec), into: &b)
        putU64(headEnd, into: &b)
        putU64(records, into: &b)
        b.append(contentsOf: stamp.hashHead)
        b.append(contentsOf: stamp.hashTail)
        b.append(contentsOf: [UInt8](repeating: 0, count: 8))
        for o in offsets { putU64(o, into: &b) }
        // Computed last, over everything including the offsets, and written
        // back into the reserved field. Computing it over the header alone
        // would leave the offsets -- the part that decides where a read lands
        // -- exactly as unprotected as before.
        // 最後才計算，涵蓋包含偏移量在內的全部內容，再寫回那個保留欄位。只對檔頭計算的話，
        // 偏移量——也就是決定一次讀取會落在哪裡的那一部分——會和先前一樣毫無保護。
        let sum = indexChecksum(b)
        for i in 0..<8 { b[INDEX_SUM_OFFSET + i] = UInt8((sum >> (8 * UInt64(i))) & 0xFF) }
        return b
    }

    /// Written only AFTER the data file is in place, and itself via
    /// temp+rename. Interrupted, the index is either absent or fails
    /// validation, and both fall back to scanning -- both safe. The other
    /// order gives an index describing content that does not exist.
    /// 只在資料檔就位「之後」才寫，且自己也走 temp+rename。中途被打斷的話，索引
    /// 要嘛不存在、要嘛驗證不過，兩種都會退回掃描，都是安全的。反過來的順序會
    /// 得到一個描述著不存在內容的索引。
    @discardableResult
    func save(dataPath: String) -> Bool {
        guard let fresh = FileStamp.of(path: dataPath) else { return false }
        stamp = fresh
        let p = CSVIndex.path(for: dataPath)
        let tmp = p + ".tmp.\(Platform.processID())"
        guard FileManager.default.createFile(atPath: tmp, contents: Data(encode())) else {
            // A directory we cannot write is a warning, once, and the
            // operation completes regardless.
            // 目錄不可寫時警告一次，操作照常完成。
            Logger.shared.warn("cannot write index beside \(dataPath); continuing without one")
            return false
        }
        // POSIX rename(2) via Platform.replaceFile, NOT
        // FileManager.replaceItemAt -- and not the fileExists/moveItem pair
        // either, since rename overwrites atomically and asking first only adds
        // a race. Core.swift moved off replaceItemAt when it was found to leave
        // the destination unchanged on Linux while reporting success; this file
        // kept the old call, so the fix reached the data path and not the index
        // beside it.
        //
        // The symptom was quiet and only visible on Linux: rewriting an index
        // that already existed threw, the catch below warned, and the warning
        // went to stderr on the NORMAL path -- breaking the one promise that
        // lets csv2 sit in a pipeline. The index also silently stopped being
        // updated, so the optimisation was permanently off after its first
        // write. Nothing produced wrong data, which is why it survived a whole
        // cross-platform run: a stale index is discarded in favour of a scan.
        // Caught on 2026-08-18 by T62f, which asserts that a fallback says
        // nothing on stderr.
        //
        // 使用 Platform.replaceFile（POSIX rename(2)），而非
        // FileManager.replaceItemAt；也不用 fileExists 加 moveItem 的組合——rename 本身
        // 就是原子覆寫，先問一次只是多製造一個 race。Core.swift 在發現 replaceItemAt 於
        // Linux 上「回報成功卻沒有動到目的地」之後就換掉了它，而這個檔案留著舊呼叫，
        // 於是修正只到了資料路徑，沒有到它旁邊的索引。
        //
        // 症狀很安靜，而且只在 Linux 上看得到：改寫一個已經存在的索引會丟出例外，下面的
        // catch 發出警告，而那個警告出現在「正常路徑」的 stderr 上——破壞了讓 csv2 能待在
        // 管線裡的那唯一一條承諾。索引也就此靜默地不再更新，因此第一次寫出之後，這項最佳化
        // 就永久關閉了。沒有任何東西產生錯誤的資料，這正是它能撐過一整輪跨平台測試的原因：
        // 過期的索引會被丟棄改用掃描。2026-08-18 由 T62f 抓到——那個案例斷言「退回掃描時
        // stderr 不說話」。
        if Platform.replaceFile(tmp, p) {
            Logger.shared.info("wrote index \(p): \(records) records, stride \(stride), \(offsets.count) entries")
            return true
        }
        try? FileManager.default.removeItem(atPath: tmp)
        Logger.shared.warn("cannot rename index into place beside \(dataPath): \(Platform.lastErrorText()); continuing without one")
        return false
    }

    // -----------------------------------------------------------------
    // Lookup / 查詢
    // -----------------------------------------------------------------

    /// The grid point at or before `record`, as (byte offset, record number
    /// living at that offset). Parsing resumes there and runs forward at most
    /// stride-1 records.
    /// `record` 之前（或正好）的格點，回傳（位元組偏移量、該偏移量上的紀錄號）。
    /// 從該處恢復解析，最多向前走 stride-1 筆。
    func gridPoint(forRecord record: Int) -> (offset: UInt64, recordNumber: Int)? {
        guard record >= 1, !offsets.isEmpty else { return nil }
        let g = (record - 1) / stride
        guard g < offsets.count else { return nil }
        return (offsets[g], g * stride + 1)
    }

    /// Called while writing: record `n` starts at `offset`. Only grid points
    /// are kept.
    /// 寫入時呼叫：第 n 筆從 offset 開始。只保留格點。
    func note(record n: Int, at offset: UInt64) {
        if (n - 1) % stride == 0 { offsets.append(offset) }
        records = UInt64(n)
    }

    /// O(1) update after the append fast path. If there is no index, one is
    /// NOT created: doing an O(n) scan to serve an O(1) operation cancels out
    /// the entire point of the fast path.
    /// 追加快路徑之後的 O(1) 更新。沒有索引時不建立：為了一個 O(1) 的操作去做
    /// 一次 O(n) 全掃描，會把快路徑的意義完全抵銷。
    func noteAppend(record n: Int, at offset: UInt64) {
        note(record: n, at: offset)
    }
}

// ---------------------------------------------------------------------
// MARK: - Building an index while scanning / 掃描時順手建索引
// ---------------------------------------------------------------------

/// The writer already knows where every record starts -- it just wrote it.
/// Noting the offsets costs no extra scan. A full scan is only needed when
/// taking over a CSV someone else produced, and that scan had to happen
/// anyway.
/// 寫入端本來就知道每一筆從哪個 byte 開始——它剛剛才寫下去，順手記下來不需要
/// 額外掃描。接手別人產生的 CSV 時才需要付一次完整掃描，而那次掃描本來就要做。
/// Whether a record occupies more than one physical line, which is the ONLY
/// thing `no_embedded_newlines` is allowed to mean. One function, because
/// three call sites each answered it their own way and two of them answered
/// `false` unconditionally -- so every index ever built claimed the property
/// whether the file had it or not.
///
/// A decoded value can only hold a newline if the source quoted it, so for a
/// `.csv` this is exactly the question. A `.csv2` escapes newlines and is one
/// record per line by construction, so a real LF in a value there says nothing
/// about the file's layout and must not be read as if it did.
///
/// CR counts as well as LF. A lone CR inside quotes does not split an
/// LF-terminated file into lines, so calling it "spanning" is pessimistic --
/// and pessimistic costs a fast path, while optimistic costs a wrong answer.
///
/// 一筆紀錄是否佔用超過一個物理行，而那是 `no_embedded_newlines` 唯一被允許表示的
/// 意思。寫成一個函式，因為原本三個呼叫點各自回答了這個問題，其中兩個無條件回答
/// `false`——於是每一份建出來的索引都宣稱自己有這個性質，不管檔案有沒有。
///
/// 解碼後的值裡會有換行，只可能是因為來源把它放進引號，所以對 `.csv` 而言這正好就是
/// 那個問題。`.csv2` 會跳脫換行、且依建構方式就是一筆一行，因此那裡的值中出現真正的
/// LF 完全不代表檔案的排版，不得被當成代表。
///
/// CR 與 LF 一樣算。引號內單獨的 CR 不會把一個以 LF 斷行的檔案切成兩行，所以把它算成
/// 「跨行」是悲觀的——而悲觀付出的是一條快路徑，樂觀付出的是一個錯的答案。
func recordSpansLines(_ r: Record, format: Format) -> Bool {
    if format == .csv2 { return false }
    for f in r.fields {
        if f.value.contains(BYTE_LF) || f.value.contains(BYTE_CR) { return true }
    }
    return false
}

final class IndexBuilder {
    private let stride: Int
    private let isCSV2: Bool
    private var offsets: [UInt64] = []
    private var count = 0
    private var headEnd: UInt64 = 0
    private var embeddedNewlineSeen = false

    init(stride: Int = INDEX_DEFAULT_STRIDE, isCSV2: Bool) {
        self.stride = stride
        self.isCSV2 = isCSV2
    }

    func headerEnded(at offset: UInt64) { headEnd = offset }

    func add(record n: Int, at offset: UInt64, spansLines: Bool) {
        if spansLines { embeddedNewlineSeen = true }
        if (n - 1) % stride == 0 { offsets.append(offset) }
        count = n
    }

    /// `no_embedded_newlines` is free to compute while building and is worth a
    /// lot: when true, later parallel work on a `.csv` can take the memchr
    /// fast path instead of a two-state speculative parse. It is not a rare
    /// case -- every CSV in this repository has the property.
    /// `no_embedded_newlines` 在建立時順手就知道，而它的用處很大：為真時，之後對
    /// `.csv` 的平行操作可以走 memchr 快路徑，不必做兩狀態推測解析。這不是罕見
    /// 情況——本 repo 樹內每一份 CSV 都是這樣。
    func finish(dataPath: String) -> CSVIndex? {
        guard let stamp = FileStamp.of(path: dataPath) else { return nil }
        return CSVIndex(stride: stride,
                        noEmbeddedNewlines: !embeddedNewlineSeen,
                        isCSV2: isCSV2,
                        headEnd: headEnd,
                        records: UInt64(count),
                        stamp: stamp,
                        offsets: offsets)
    }
}

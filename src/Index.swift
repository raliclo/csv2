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
let INDEX_VERSION: UInt32 = 1
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
    static func load(dataPath: String) -> CSVIndex? {
        let p = path(for: dataPath)
        guard let d = FileManager.default.contents(atPath: p), d.count >= INDEX_HEADER_SIZE else {
            return nil
        }
        let b = [UInt8](d)
        guard Array(b.prefix(8)) == INDEX_MAGIC else {
            Logger.shared.info("index \(p): bad magic, ignoring and scanning")
            return nil
        }
        guard getU32(b, 8) == INDEX_VERSION else {
            Logger.shared.info("index \(p): version mismatch, ignoring and scanning")
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

        guard let now = FileStamp.of(path: dataPath) else { return nil }
        guard now.size == dataSize, now.mtimeSec == mtimeSec, now.mtimeNsec == mtimeNsec,
              now.hashHead == hashHead, now.hashTail == hashTail else {
            // Stale, not corrupt. Logged at INFO and then ignored -- never an
            // error, because the operation must succeed identically without it.
            // 過期而非損毀。以 INFO 記錄後忽略——絕不是錯誤，因為沒有它時操作
            // 必須以完全相同的方式成功。
            Logger.shared.info("index \(p) is stale, ignoring and scanning")
            return nil
        }

        let want = (Int(records) + stride - 1) / stride
        let have = (b.count - INDEX_HEADER_SIZE) / 8
        guard have >= want else {
            // Truncated. Same treatment: discard, scan. Not an error.
            // 被截斷。同樣處理：丟棄、掃描。不是錯誤。
            Logger.shared.info("index \(p) is truncated (\(have) of \(want) entries), ignoring and scanning")
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
        do {
            if FileManager.default.fileExists(atPath: p) {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: p),
                                                          withItemAt: URL(fileURLWithPath: tmp))
            } else {
                try FileManager.default.moveItem(atPath: tmp, toPath: p)
            }
            Logger.shared.info("wrote index \(p): \(records) records, stride \(stride), \(offsets.count) entries")
            return true
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
            Logger.shared.warn("cannot rename index into place beside \(dataPath); continuing without one")
            return false
        }
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

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
//    80  checksum   8   over the whole file, written back here last
//    88  lastLine   u64  physical line the LAST record starts on
//   entries: two u64 LE per grid point -- byte offset, then the physical line
//            that record starts on
//
//  Fixed width, so record N's grid entry is at `96 + 16*((N-1)/stride)` -- an
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
// Bumped to 4 on 2026-08-21. Version 3 grid entries are a byte offset alone,
// and a seek from one could not say which physical LINE it had landed on -- so
// the seek was refused for any file with a record spanning lines, and one such
// record in 450,000 cost the whole file: `-tail 40` read 15 MB instead of 7 kB.
// A `.csv2` never has one, so the two formats behaved differently for a reason
// that was never the format. Each entry now carries the line, and the seek
// applies to both.
// 2026-08-21 推進為 4。版本 3 的格點只有一個位元組偏移量，從它 seek 過去說不出「落在第幾
// 實體行」——因此只要檔案裡有一筆跨行紀錄，seek 就整個被拒絕，而 45 萬筆裡的一筆就要付上
// 整個檔案的代價：`-tail 40` 讀了 15 MB 而不是 7 kB。`.csv2` 不可能有那種紀錄，於是兩種格式
// 表現不同——而原因從來不是格式。現在每個格點都帶著行號，兩者都 seek 得到。
let INDEX_VERSION: UInt32 = 4
let INDEX_HEADER_SIZE = 96
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
        // A stamp reads the first and last 64 bytes, and on anything that is
        // not a regular file those bytes do not come back: reading a FIFO
        // CONSUMES them. `csv2 -r -i fifo.csv` on a three-line file therefore
        // reached the parser empty and was reported as `expected 1 header
        // row(s), found 0` -- the message for a file with nothing in it --
        // while the same bytes through `-si` were read correctly.
        //
        // Returning nil here is what "there is no index for this input" is
        // already spelled as everywhere else, so a pipe simply gets the
        // no-sidecar path: no load, no save, no seek, and the read works.
        // Refusing the input instead was tried first and it took `-i <(...)`
        // with it, which had been working.
        // 一個戳記會讀頭尾各 64 個位元組，而在「不是一般檔案」的東西上，那些位元組不會回來：
        // 讀一個 FIFO 會把它們「吃掉」。於是 `csv2 -r -i fifo.csv` 對一個三行的檔案，抵達
        // 解析器時是空的，並被回報為 `expected 1 header row(s), found 0`——那是「檔案裡什麼
        // 都沒有」的訊息——而同樣的位元組走 `-si` 讀得完全正確。
        //
        // 在這裡回傳 nil，正是這棵樹在其他每一處用來表達「這個輸入沒有索引」的寫法，因此
        // 一條管線就自然走上「沒有 sidecar」那條路：不載入、不儲存、不 seek，而讀取是對的。
        // 先試過的是「拒絕這個輸入」，而那會連 `-i <(...)` 一起帶走，那原本是可用的。
        guard Platform.fileKind(path: path) == .regular else { return nil }
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

/// A 64-bit FNV-1a over the whole index with the checksum field itself read as
/// zero -- except for the multiplier, which is `0x1000_0000_01b3` and NOT the
/// FNV-1a prime `0x100000001b3`. The underscores are grouped one nibble wrong,
/// which makes it 2^44 + 0x1b3 instead of 2^40 + 0x1b3.
///
/// It is left as it is, and named accurately here instead. The multiplier is
/// odd, so the map is still a bijection modulo 2^64 and still detects the bit
/// flips and short writes this is for; correcting it would make every sidecar
/// already on disk report "checksum does not match (damaged)", which is a
/// message about corruption for files that have none. Anyone reimplementing
/// this check -- the test suite does, in Python, so that the constant is
/// pinned by something that is not this line -- needs the constant above, not
/// the name below it. Reading the name and writing the prime is exactly the
/// failure the -log escape table had: a documented reader that cannot
/// reproduce what the tool wrote.
///
/// 這是對整份索引所做的 64-bit FNV-1a、並把檢查碼欄位本身當成零——但乘數是
/// `0x1000_0000_01b3`，而**不是** FNV-1a 的質數 `0x100000001b3`：底線的分組錯了一個
/// nibble，於是它成了 2^44 + 0x1b3 而不是 2^40 + 0x1b3。
///
/// 它維持原狀，改成在這裡誠實地說出來。那個乘數是奇數，因此模 2^64 仍是雙射，仍然抓得到
/// 它要抓的位元翻轉與寫入不完整；改正它會讓每一份已經在磁碟上的 sidecar 回報「檢查碼不符
/// （已損毀）」——對一批毫無損毀的檔案說損毀。任何要重新實作這個檢查的人（測試套件就用
/// Python 做了一份，好讓這個常數被「這一行以外的東西」釘住）需要的是上面那個常數，而不是
/// 它下面那個名字。照著名字去寫那個質數，正是 `-log` 跳脫表犯過的同一個錯：一份照文件寫成
/// 的讀取器，重現不出工具實際寫下的東西。
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
    /// The physical line each of those records starts on. Same length as
    /// `offsets`, and the reason a file with an embedded newline can be seeked
    /// into at all: without it a resume could not report the line a full scan
    /// would, and `--physical` puts that line in the output.
    /// 那些紀錄各自起始的實體行號。長度與 `offsets` 相同，而它正是「含內嵌換行的檔案也能被
    /// seek」的原因：沒有它，恢復解析就報不出「完整掃描會給的那個行號」，而 `--physical`
    /// 會把那個行號放進輸出。
    var lines: [UInt64]
    /// The line the last record starts on, so an append can extend `lines`
    /// without scanning. / 最後一筆起始的行號，讓追加可以在不掃描的情況下延續 `lines`。
    var lastLine: UInt64

    init(stride: Int, noEmbeddedNewlines: Bool, isCSV2: Bool,
         headEnd: UInt64, records: UInt64, stamp: FileStamp,
         offsets: [UInt64], lines: [UInt64], lastLine: UInt64) {
        self.stride = stride
        self.noEmbeddedNewlines = noEmbeddedNewlines
        self.isCSV2 = isCSV2
        self.headEnd = headEnd
        self.records = records
        self.stamp = stamp
        self.offsets = offsets
        self.lines = lines
        self.lastLine = lastLine
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

    /// Why the last `load` discarded a sidecar, in a few words, for a caller
    /// that has to say something about it.
    ///
    /// Without this, two messages could only point elsewhere. The parallel
    /// decline said "run with -debug to see why" -- to a reader who was
    /// already running with -debug, since that is the only way to see the
    /// message at all -- and `--verify-index` said "no usable index beside X"
    /// with the sidecar sitting right there, conflating "absent" with "present
    /// and unusable". Both were written on 2026-08-20, hours apart, and both
    /// had the reason available one call away.
    ///
    /// 上一次 `load` 為什麼丟棄某個 sidecar，用幾個字說明，給「必須對此說點什麼」的呼叫端。
    ///
    /// 沒有它，兩則訊息都只能把讀者指到別處去。平行路徑的拒絕說「用 -debug 看原因」——而
    /// 那是說給一個「已經在用 -debug」的讀者聽的，因為那是唯一看得到這則訊息的方式；
    /// 而 `--verify-index` 說「旁邊沒有可用的索引」，當時 sidecar 就在那裡，把「不存在」與
    /// 「存在但不能用」合成了一句話。兩者都寫於 2026-08-20，相隔數小時，而兩者要的理由
    /// 都只差一次呼叫。
    ///
    /// Carried as a PAIR. The first version was English only, and the callers
    /// interpolate it into both halves of a two-line bilingual message -- so
    /// the Chinese line read `…無法使用：stale: the data file changed。`. The
    /// "exactly two lines, English then Chinese" contract held by count and
    /// not by language, and it held that way because the reason was written
    /// once, in one language, by someone who then used it twice.
    /// 以「一對」的形式攜帶。第一版只有英文，而呼叫端會把它插進一則雙語兩行訊息的「兩」半裡
    /// ——於是中文那一行讀起來是「…無法使用：stale: the data file changed。」。
    /// 「恰好兩行、英文在前中文在後」這個契約依行數成立、依語言不成立，而它之所以如此，
    /// 是因為那個理由被寫了一次、用了兩次。
    private(set) static var lastDiscardReason: (en: String, zh: String)?

    private static func announceDiscard(_ message: @autoclosure () -> String, for sidecar: String,
                                        reason: String, reasonZh: String) {
        lastDiscardReason = (reason, reasonZh)
        guard !announced.contains(sidecar) else { return }
        announced.insert(sidecar)
        Logger.shared.info(message())
    }

    static func load(dataPath: String) -> CSVIndex? {
        let p = path(for: dataPath)
        // Cleared per call. A reason left over from an earlier load would be
        // reported against a sidecar it has nothing to do with, which is a
        // worse failure than saying nothing.
        // 每次呼叫都清掉。留著上一次 load 的理由，會讓它被報在一個毫不相干的 sidecar 上，
        // 而那比什麼都不說更糟。
        lastDiscardReason = nil
        // A sidecar that exists and cannot be READ was the last silent discard:
        // it returned nil with no reason recorded, so --verify-index answered
        // "reason not recorded" for a condition the system had just given us in
        // one word. Absent is still silent, and correctly so -- having no
        // sidecar is the ordinary case, not an event.
        // 一份「存在但讀不到」的 sidecar，是最後一種安靜的丟棄：它回傳 nil 而沒有記下理由，
        // 於是 --verify-index 對一個「系統剛剛用一個詞告訴我們」的狀況回答「沒有記錄到理由」。
        // 「不存在」仍然是安靜的，而那是對的——沒有 sidecar 是常態，不是事件。
        guard let d = FileManager.default.contents(atPath: p) else {
            if FileManager.default.fileExists(atPath: p) {
                let e = Platform.errorText(errno)
                announceDiscard("index \(p): cannot be read (\(e)), ignoring and scanning", for: p,
                                reason: "it exists but cannot be read: \(e)",
                                reasonZh: "它存在但讀不到：\(e)")
            }
            return nil
        }
        // A sidecar too short to hold a header used to be the one discard that
        // said nothing at all -- indistinguishable, from the outside, from
        // having no sidecar. Every other rejection below announces itself.
        // 一個短到裝不下檔頭的 sidecar，原本是唯一一種「什麼都不說」的丟棄——從外面看，
        // 與「根本沒有 sidecar」無法區分。下面每一種拒絕都會說出自己。
        guard d.count >= INDEX_HEADER_SIZE else {
            announceDiscard("index \(p): shorter than an index header (\(d.count) bytes), ignoring and scanning", for: p, reason: "too short to hold a header", reasonZh: "檔案短到裝不下一個索引檔頭")
            return nil
        }
        let b = [UInt8](d)
        guard Array(b.prefix(8)) == INDEX_MAGIC else {
            announceDiscard("index \(p): bad magic, ignoring and scanning", for: p, reason: "not an index file (bad magic)", reasonZh: "不是索引檔（magic 不符）")
            return nil
        }
        guard getU32(b, 8) == INDEX_VERSION else {
            announceDiscard("index \(p): version mismatch, ignoring and scanning", for: p, reason: "written by a different INDEX_VERSION", reasonZh: "由不同的 INDEX_VERSION 寫出")
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
            announceDiscard("index \(p): checksum mismatch, ignoring and scanning", for: p, reason: "its own checksum does not match (damaged)", reasonZh: "它自己的檢查碼不符（已損毀）")
            return nil
        }

        guard let now = FileStamp.of(path: dataPath) else { return nil }
        guard now.size == dataSize, now.mtimeSec == mtimeSec, now.mtimeNsec == mtimeNsec,
              now.hashHead == hashHead, now.hashTail == hashTail else {
            // Stale, not corrupt. Logged at INFO and then ignored -- never an
            // error, because the operation must succeed identically without it.
            // 過期而非損毀。以 INFO 記錄後忽略——絕不是錯誤，因為沒有它時操作
            // 必須以完全相同的方式成功。
            // "does not describe this file", not "the data file changed". The
            // stamp says the two do not match; it cannot say which of them
            // moved. Copy another file's sidecar into place and the old wording
            // reported a change to a file that had not been touched, sending
            // the reader to look for an edit nobody made.
            // 用「不描述這個檔案」而不是「資料檔已經改變」。那個戳記說的是「兩者不相符」，
            // 它說不出是哪一邊動了。把另一個檔案的 sidecar 複製過來，舊的說法會去回報一個
            // 「根本沒被碰過的檔案發生了變更」，把讀者送去找一次沒有人做過的編輯。
            announceDiscard("index \(p) is stale, ignoring and scanning", for: p, reason: "stale: it does not describe this file -- size, timestamp or content stamp differs. Either the file changed, or this sidecar belongs to another one", reasonZh: "過期：它不描述這個檔案——大小、時間戳或內容戳記不符。可能是檔案變了，也可能這份 sidecar 屬於另一個檔案")
            return nil
        }

        let want = (Int(records) + stride - 1) / stride
        let have = (b.count - INDEX_HEADER_SIZE) / 16
        guard have >= want else {
            // Truncated. Same treatment: discard, scan. Not an error.
            // 被截斷。同樣處理：丟棄、掃描。不是錯誤。
            announceDiscard("index \(p) is truncated (\(have) of \(want) entries), ignoring and scanning", for: p, reason: "truncated: fewer grid entries than its record count needs", reasonZh: "被截斷：格點項目少於它自己的筆數所需")
            return nil
        }
        var offsets = [UInt64]()
        var lines = [UInt64]()
        offsets.reserveCapacity(want)
        lines.reserveCapacity(want)
        for g in 0..<want {
            offsets.append(getU64(b, INDEX_HEADER_SIZE + 16 * g))
            lines.append(getU64(b, INDEX_HEADER_SIZE + 16 * g + 8))
        }

        return CSVIndex(stride: stride,
                        noEmbeddedNewlines: (flags & 1) != 0,
                        isCSV2: (flags & 2) != 0,
                        headEnd: headEnd, records: records,
                        stamp: now, offsets: offsets, lines: lines,
                        lastLine: getU64(b, 88))
    }

    // -----------------------------------------------------------------
    // Writing / 寫出
    // -----------------------------------------------------------------

    func encode() -> [UInt8] {
        var b = [UInt8]()
        b.reserveCapacity(INDEX_HEADER_SIZE + 16 * offsets.count)
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
        b.append(contentsOf: [UInt8](repeating: 0, count: 8))   // checksum, filled in below
        putU64(lastLine, into: &b)
        for (g, o) in offsets.enumerated() {
            putU64(o, into: &b)
            putU64(g < lines.count ? lines[g] : 0, into: &b)
        }
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
    func gridPoint(forRecord record: Int) -> (offset: UInt64, recordNumber: Int, line: UInt64)? {
        guard record >= 1, !offsets.isEmpty, lines.count == offsets.count else { return nil }
        let g = (record - 1) / stride
        guard g < offsets.count else { return nil }
        return (offsets[g], g * stride + 1, lines[g])
    }

    /// Called while writing: record `n` starts at `offset`. Only grid points
    /// are kept.
    /// 寫入時呼叫：第 n 筆從 offset 開始。只保留格點。
    func note(record n: Int, at offset: UInt64, line: UInt64) {
        if (n - 1) % stride == 0 { offsets.append(offset); lines.append(line) }
        records = UInt64(n)
        lastLine = line
    }

    /// O(1) update after the append fast path, for an index that already
    /// exists. When there is none, one is built from the scan that path now
    /// performs anyway -- see runAppendFast. The comment that used to be here
    /// refused to build one "because an O(n) scan to serve an O(1) operation
    /// cancels out the entire point of the fast path", and by then the scan
    /// was unconditional.
    /// 追加快路徑之後、針對「已經存在」的索引所做的 O(1) 更新。不存在時，會由那條路徑
    /// 現在無論如何都會做的掃描建出一份——見 runAppendFast。原本這裡的註解以「為了一個
    /// O(1) 的操作去做一次 O(n) 全掃描，會把快路徑的意義完全抵銷」為由拒絕建立，而那時
    /// 那次掃描已經是無條件的了。
    func noteAppend(record n: Int, at offset: UInt64, line: UInt64) {
        note(record: n, at: offset, line: line)
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
    private var lines: [UInt64] = []
    private var lastLine: UInt64 = 1
    private var count = 0
    private var headEnd: UInt64 = 0
    private var embeddedNewlineSeen = false

    init(stride: Int = INDEX_DEFAULT_STRIDE, isCSV2: Bool) {
        self.stride = stride
        self.isCSV2 = isCSV2
    }

    func headerEnded(at offset: UInt64) { headEnd = offset }

    /// How many records have been added. The append fast path continues the
    /// numbering from here when it finishes a builder that was filled by the
    /// validation scan.
    /// 已經加入幾筆。追加快路徑在結束一個「由驗證掃描填好的」builder 時，從這裡接著編號。
    var recordCount: Int { count }

    func add(record n: Int, at offset: UInt64, line: UInt64, spansLines: Bool) {
        if spansLines { embeddedNewlineSeen = true }
        if (n - 1) % stride == 0 { offsets.append(offset); lines.append(line) }
        count = n
        lastLine = line
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
                        offsets: offsets, lines: lines, lastLine: lastLine)
    }
}

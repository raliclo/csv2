// =====================================================================
//  Platform.swift — the one file that knows which OS this is
//  Platform.swift — 唯一一個知道「這是哪個作業系統」的檔案
//
//  Every POSIX call csv2 makes goes through here. The alternative -- an
//  #if canImport(...) beside each call site -- is how a port rots: adding a
//  third platform then means finding every site, and missing one produces a
//  build error on that platform only, months later.
//  csv2 所有的 POSIX 呼叫都經過這裡。另一種寫法——在每個呼叫點旁邊各放一組
//  #if canImport(...)——正是移植腐化的方式：新增第三個平台就得找出每一處，
//  而漏掉一處只會在那個平台上、幾個月後才變成建置錯誤。
//
//  STATUS: the Darwin and Glibc branches are exercised by the test suite on
//  macOS and on the aarch64 Linux guest. The Windows branch is written but
//  HAS NEVER BEEN COMPILED OR RUN. It is a starting point for a port, not a
//  supported platform, and nothing in this repository should claim otherwise
//  until a Windows run reports the same counts as the other two.
//  狀態：Darwin 與 Glibc 兩個分支由測試在 macOS 與 aarch64 Linux guest 上實際
//  執行過。Windows 分支已寫出，但**從未被編譯或執行過**。它是移植的起點，不是
//  受支援的平台；在 Windows 上跑出與另外兩者相同的數字之前，本 repo 任何地方都
//  不該宣稱相反的事。
// =====================================================================

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
import WinSDK
#endif

enum Platform {

    // -----------------------------------------------------------------
    // MARK: - Autorelease drain / autorelease 排空
    // -----------------------------------------------------------------

    /// Runs `body` inside an autorelease pool where the platform has one, and
    /// plain where it does not. It exists for one call site -- the read loop
    /// -- and it is here rather than there because `autoreleasepool` DOES NOT
    /// EXIST on Linux Swift: the first version of the fix put it beside the
    /// call, passed on macOS, and failed the guest build with
    /// `cannot find 'autoreleasepool' in scope`. That is precisely the rot
    /// this file's header describes, caught by the cross-platform run instead
    /// of by review.
    ///
    /// The pool is not decoration. `FileHandle.readData` returns Foundation
    /// objects that, on Darwin, are released only when a pool drains -- with
    /// none in the loop they accumulated for the whole run and peak RSS tracked
    /// bytes read. Linux Foundation has no pools and manages `Data` by ARC, so
    /// the leak was macOS-only and the plain branch is correct rather than a
    /// stub waiting to be filled in.
    ///
    /// 在有 autorelease pool 的平台上把 `body` 包進一個 pool，沒有的平台就直接執行。
    /// 它只為一個呼叫點存在——讀取迴圈——而它放在這裡而不是那裡，是因為
    /// **`autoreleasepool` 在 Linux 的 Swift 上根本不存在**：這個修正的第一版把它寫在
    /// 呼叫點旁邊，在 macOS 上通過，而 guest 建置以
    /// `cannot find 'autoreleasepool' in scope` 失敗。那正是本檔案開頭所描述的那種腐化，
    /// 而抓到它的是跨平台的那次執行，不是審閱。
    ///
    /// 這個 pool 不是裝飾。`FileHandle.readData` 回傳的 Foundation 物件在 Darwin 上只有
    /// 在 pool 排空時才會被釋放——迴圈裡一個都沒有，於是它們累積了整趟執行，peak RSS 正比於
    /// 讀進來的位元組數。Linux 的 Foundation 沒有 pool、以 ARC 管理 `Data`，因此這個洩漏
    /// 是 macOS 專屬的，而那個「直接執行」的分支是正確答案，不是一個待填的空殼。
    static func drainingPool<T>(_ body: () -> T) -> T {
        #if canImport(Darwin)
        return autoreleasepool(invoking: body)
        #else
        return body()
        #endif
    }

    // -----------------------------------------------------------------
    // MARK: - Raw argv / 原始 argv
    // -----------------------------------------------------------------

    /// The bytes of one argument as the kernel delivered them, before Swift
    /// decoded it. `CommandLine.arguments` is `[String]`, and Swift builds
    /// those by decoding argv as UTF-8 **with replacement** -- so an invalid
    /// byte has already become U+FFFD before any csv2 code runs, and the value
    /// stored by `-update` is not the value that was typed.
    ///
    /// This exists to DETECT that, not to carry the bytes through: csv2 refuses
    /// such an argument rather than altering it. Threading raw bytes through
    /// every value path would be the other answer and a much larger change;
    /// refusing is the one this project's own rule already prescribes -- do not
    /// silently repair malformed input, report it and exit non-zero.
    ///
    /// Here rather than at the call site because reaching argv is a per-platform
    /// question, which is this file's whole reason for existing.
    ///
    /// 一個參數在「Swift 解碼之前」、由核心交過來的原始位元組。`CommandLine.arguments`
    /// 是 `[String]`，而 Swift 是以「UTF-8 解碼、無效處以替代字元補上」的方式建出它們的
    /// ——因此在任何 csv2 的程式碼執行之前，無效位元組就已經變成 U+FFFD，而 `-update`
    /// 存進去的值並不是使用者打的那個值。
    /// 它的用途是「偵測」，不是把位元組一路帶過去：csv2 會拒絕這樣的參數，而不是改動它。
    /// 把原始位元組穿過每一條值的路徑是另一個答案，而且是大得多的改動；拒絕才是本專案自己
    /// 的規則早已規定的那一個——不要靜默修復格式錯誤的輸入，指出它並以非零結束。
    /// 放在這裡而不是呼叫點旁邊，因為「怎麼拿到 argv」是一個依平台而異的問題，
    /// 而那正是這個檔案存在的全部理由。
    static func rawArgumentIsValidUTF8(at index: Int) -> Bool {
        guard index >= 0, index < Int(CommandLine.argc),
              let argv = CommandLine.unsafeArgv[index] else { return true }
        var bytes: [UInt8] = []
        var p = argv
        while p.pointee != 0 {
            bytes.append(UInt8(bitPattern: p.pointee))
            p += 1
        }
        return String(bytes: bytes, encoding: .utf8) != nil
    }

    // -----------------------------------------------------------------
    // MARK: - Atomic replace / 原子性取代
    // -----------------------------------------------------------------

    /// POSIX rename(2): atomic within a filesystem, so a reader sees either
    /// the whole old file or the whole new one. Windows `rename` REFUSES to
    /// overwrite an existing target, which is exactly what this needs to do,
    /// so the Windows branch uses MoveFileExW with MOVEFILE_REPLACE_EXISTING.
    /// Using plain rename there would fail on every write to a file that
    /// already exists -- which is every in-place edit.
    /// POSIX rename(2)：在同一檔案系統內是原子的，讀者要嘛看到完整的舊檔、
    /// 要嘛看到完整的新檔。Windows 的 `rename` **拒絕覆蓋既有目標**，而覆蓋正是
    /// 此處必須做的事，因此 Windows 分支改用帶 MOVEFILE_REPLACE_EXISTING 的
    /// MoveFileExW。在那裡直接用 rename，會在每一次「寫入既有檔案」時失敗——
    /// 也就是每一次就地編輯。
    static func replaceFile(_ from: String, _ to: String) -> Bool {
        #if canImport(ucrt)
        return from.withCString(encodedAs: UTF16.self) { f in
            to.withCString(encodedAs: UTF16.self) { t in
                MoveFileExW(f, t, DWORD(MOVEFILE_REPLACE_EXISTING))
            }
        }
        #else
        return rename(from, to) == 0
        #endif
    }

    /// The reason the last call failed, in words. Windows MoveFileExW reports
    /// through GetLastError rather than errno, so asking errno there would
    /// print a stale or meaningless message.
    /// 上一次呼叫失敗的原因，以文字表示。Windows 的 MoveFileExW 是透過
    /// GetLastError 回報而非 errno，在那裡去問 errno 會印出一個過期或無意義的訊息。
    static func lastErrorText() -> String {
        #if canImport(ucrt)
        return "Windows error \(GetLastError())"
        #else
        return String(cString: strerror(errno))
        #endif
    }

    // -----------------------------------------------------------------
    // MARK: - Durability / 落地
    // -----------------------------------------------------------------

    /// Force a file's data to the filesystem before it is renamed into place.
    ///
    /// rename(2) alone gives atomicity for CONCURRENT READERS -- a reader holds
    /// either the old inode or the new one, never a half-written file. It does
    /// NOT give durability across a crash: the rename can reach the disk while
    /// the temp file's data blocks have not, leaving a file that exists, is
    /// named correctly, and is empty or truncated.
    ///
    /// Those are two different guarantees and csv2's design conflated them. The
    /// second is the one the plan leans on when it says this project's data
    /// files are held up by "all-new or all-old", so it has to be real.
    /// 在檔案被 rename 就位之前，強制把它的資料寫到檔案系統。
    ///
    /// 單靠 rename(2) 提供的是「並行讀者」的原子性——讀者持有的要嘛是舊 inode、
    /// 要嘛是新的，絕不會是寫到一半的檔案。它「不」提供當機後的持久性：rename 可能
    /// 已經落地，而暫存檔的資料區塊還沒有，留下一個存在、名字正確、但內容是空的或
    /// 被截斷的檔案。
    ///
    /// 那是兩個不同的保證，而 csv2 的設計把它們混為一談。計畫說「這個專案的資料檔
    /// 正是靠『要嘛全新、要嘛全舊』在支撐的」時，指的是第二個——所以它必須是真的。
    ///
    /// On Darwin plain fsync() only pushes data to the drive, which may still
    /// hold it in a volatile write cache; F_FULLFSYNC is what actually flushes
    /// that cache. Using the weaker one and calling it durable is the kind of
    /// half-true claim this project exists to avoid.
    /// 在 Darwin 上，單純的 fsync() 只把資料推給磁碟，而磁碟可能仍將它留在揮發性的
    /// 寫入快取中；真正沖掉該快取的是 F_FULLFSYNC。用比較弱的那個、然後宣稱「已持久」，
    /// 正是本專案要避免的那種半真陳述。
    @discardableResult
    static func flushToDisk(_ fd: Int32) -> Bool {
        #if canImport(ucrt)
        let handle = HANDLE(bitPattern: _get_osfhandle(fd))
        guard let h = handle, h != INVALID_HANDLE_VALUE else { return false }
        return FlushFileBuffers(h)
        #elseif canImport(Darwin)
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        // Some filesystems do not implement F_FULLFSYNC and return ENOTSUP.
        // fsync is then the strongest thing available, and saying so beats
        // failing the write over it.
        // 有些檔案系統未實作 F_FULLFSYNC，會回傳 ENOTSUP。此時 fsync 就是可用的
        // 最強手段，退回它並說明，好過為此讓寫入失敗。
        return fsync(fd) == 0
        #else
        return fsync(fd) == 0
        #endif
    }

    // -----------------------------------------------------------------
    // MARK: - Process and terminal / 行程與終端機
    // -----------------------------------------------------------------

    static func processID() -> Int32 {
        #if canImport(ucrt)
        return _getpid()
        #else
        return getpid()
        #endif
    }

    /// Whether a descriptor is a terminal. csv2 uses this for one decision
    /// only, and it is a security-relevant one: a prompt that cannot be shown
    /// must never be treated as a yes.
    /// 某個描述子是不是終端機。csv2 只用它做一個決定，而那個決定與安全有關：
    /// 無法顯示的提示絕不可視為「是」。
    static func isTerminal(_ fd: Int32) -> Bool {
        #if canImport(ucrt)
        return _isatty(fd) != 0
        #else
        return isatty(fd) == 1
        #endif
    }

    static var stdinFD: Int32 {
        #if canImport(ucrt)
        return 0
        #else
        return STDIN_FILENO
        #endif
    }

    static var stderrFD: Int32 {
        #if canImport(ucrt)
        return 2
        #else
        return STDERR_FILENO
        #endif
    }

    // -----------------------------------------------------------------
    // MARK: - File identity for the index / 索引用的檔案識別
    // -----------------------------------------------------------------

    /// Size and modification time, used as an O(1) heuristic for whether an
    /// index still describes its data file.
    ///
    /// The nanosecond field is where the three platforms disagree: Darwin has
    /// st_mtimespec, Linux has st_mtim, and Windows `_stat64` has only
    /// whole-second st_mtime. Reporting 0 nanoseconds there is honest and
    /// costs only resolution -- the index is a heuristic by design, and the
    /// head/tail hashes carry the real weight.
    /// 大小與修改時間，作為「索引是否仍描述其資料檔」的 O(1) 啟發式判斷。
    ///
    /// 奈秒欄位正是三個平台分歧之處：Darwin 是 st_mtimespec、Linux 是 st_mtim，
    /// 而 Windows 的 `_stat64` 只有整秒的 st_mtime。在那裡回報 0 奈秒是誠實的，
    /// 代價僅是解析度——索引本來就是啟發式的，真正的份量在前後段的雜湊上。
    static func fileIdentity(path: String) -> (size: UInt64, mtimeSec: Int64, mtimeNsec: Int64)? {
        #if canImport(ucrt)
        var st = _stat64()
        guard _stat64(path, &st) == 0 else { return nil }
        return (UInt64(st.st_size), Int64(st.st_mtime), 0)
        #else
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        #if canImport(Darwin)
        return (UInt64(st.st_size), Int64(st.st_mtimespec.tv_sec), Int64(st.st_mtimespec.tv_nsec))
        #else
        return (UInt64(st.st_size), Int64(st.st_mtim.tv_sec), Int64(st.st_mtim.tv_nsec))
        #endif
        #endif
    }

    // -----------------------------------------------------------------
    // MARK: - Peak memory / 峰值記憶體
    // -----------------------------------------------------------------

    /// Peak resident set size in BYTES.
    ///
    /// Three different answers. Darwin's ru_maxrss is bytes; Linux's is
    /// kilobytes -- the same struct field with two units, which is the kind of
    /// difference that only shows up when the second platform runs it. Windows
    /// has no getrusage at all and reports through GetProcessMemoryInfo.
    /// 峰值常駐記憶體，單位為「位元組」。
    /// 三個平台三種答案。Darwin 的 ru_maxrss 是位元組，Linux 的是 KB——同一個
    /// 結構欄位、兩種單位，正是那種「只有第二個平台真的跑起來才會顯現」的差異。
    /// Windows 根本沒有 getrusage，改由 GetProcessMemoryInfo 回報。
    static func peakRSSBytes() -> Int {
        #if canImport(ucrt)
        var counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
        guard GetProcessMemoryInfo(GetCurrentProcess(), &counters, counters.cb) else { return 0 }
        return Int(counters.PeakWorkingSetSize)
        #else
        var usage = rusage()
        // The `who` argument's TYPE differs: Darwin declares
        // getrusage(Int32, ...), glibc declares getrusage(__rusage_who_t, ...)
        // while RUSAGE_SELF imports as __rusage_who. Passing it straight
        // through compiles on macOS and fails on Linux.
        // `who` 參數的「型別」不同：Darwin 宣告 getrusage(Int32, ...)，glibc 宣告
        // getrusage(__rusage_who_t, ...)，而 RUSAGE_SELF 被匯入為 __rusage_who。
        // 直接傳過去在 macOS 上編得過、在 Linux 上會失敗。
        #if canImport(Darwin)
        let who: Int32 = RUSAGE_SELF
        #else
        let who: Int32 = Int32(RUSAGE_SELF.rawValue)
        #endif
        guard getrusage(who, &usage) == 0 else { return 0 }
        #if canImport(Darwin)
        return Int(usage.ru_maxrss)
        #else
        return Int(usage.ru_maxrss) * 1024
        #endif
        #endif
    }

    /// Named so a caller can report honestly rather than printing 0 as though
    /// it were a measurement. On Windows the value comes from a different API
    /// and has not been verified, so the metrics line says so.
    /// 特意命名，讓呼叫端能誠實回報，而不是把 0 當成一次量測印出去。Windows 上
    /// 這個值來自另一組 API 且尚未驗證，因此 metrics 那一行會如實說明。
    static var peakRSSIsVerified: Bool {
        #if canImport(Darwin) || canImport(Glibc)
        return true
        #else
        return false
        #endif
    }

    static var name: String {
        #if canImport(Darwin)
        return "darwin"
        #elseif canImport(Glibc)
        return "linux"
        #elseif canImport(ucrt)
        return "windows"
        #else
        return "unknown"
        #endif
    }
}

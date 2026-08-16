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

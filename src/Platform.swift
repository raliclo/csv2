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
//  STATUS (2026-08-19): all three branches are exercised. Darwin on macOS,
//  Glibc on both the aarch64 Linux guest and x86_64 WSL2, and ucrt on Windows
//  (MINGW64_NT-10.0-26200, Swift 6.3.3, x86_64-unknown-windows-msvc). The
//  Windows suite passes with four skips, each one an environment limit that is
//  named where it is skipped and recorded in todo/known-defects.md.
//
//  It had never been compiled until that day, and the first attempt producedd
//  exactly two errors -- one name that Swift's WinSDK does not surface, and
//  one property that does not exist there. Everything else in this file had
//  been right for three days without anyone being able to say so.
//
//  狀態（2026-08-19）：三個分支都已被實際執行。Darwin 在 macOS 上，Glibc 在 aarch64
//  Linux guest 與 x86_64 WSL2 上，ucrt 在 Windows 上（MINGW64_NT-10.0-26200、
//  Swift 6.3.3、x86_64-unknown-windows-msvc）。Windows 的測試套件通過，有四個略過，
//  每一個都是環境的限制，在略過處指名，並記在 todo/known-defects.md。
//  在那一天之前它從未被編譯過，而第一次嘗試恰好produced 兩個錯誤——一個 Swift 的 WinSDK
//  沒有呈現的名稱，以及一個在那裡並不存在的屬性。這個檔案裡其餘每一行，在那之前三天
//  都是對的，只是沒有人能這樣說。
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
    static func drainingPool<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
        return try autoreleasepool(invoking: body)
        #else
        return try body()
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

    /// Open a file for appending, with the append happening in the KERNEL on
    /// every write rather than once at open.
    ///
    /// `FileHandle(forWritingAtPath:)` followed by `seekToEndOfFile()` is not
    /// the same thing, and the difference is invisible with one process. The
    /// seek fixes an offset at open time; a second process that appends in
    /// between leaves this one writing over what it wrote. Eight processes
    /// each logging 25 operations to one file produced 98 entries of 200, none
    /// of them malformed and every run exiting 0 -- silent loss, in the one
    /// file whose entire value is that what happened is still there later.
    ///
    /// `O_APPEND` moves the seek-and-write into a single kernel operation, so
    /// concurrent writers cannot land on the same offset.
    ///
    /// **Windows is weaker and this says so rather than pretending.** The CRT
    /// implements `_O_APPEND` by seeking before each write, which closes the
    /// window to almost nothing but does not make it atomic across processes.
    /// The honest summary is: POSIX loses nothing, Windows loses far less than
    /// it did, and neither is a reason to keep the seek-once behaviour.
    ///
    /// 以「追加」開啟檔案，而追加發生在**核心**、在每一次寫入時，不是在開檔時發生一次。
    ///
    /// `FileHandle(forWritingAtPath:)` 之後接 `seekToEndOfFile()` 不是同一件事，而這個
    /// 差別在單一行程下看不出來。那個 seek 在開檔當下固定了一個位移；若第二個行程在中間
    /// 追加，這個行程就會蓋掉對方寫的東西。八個行程各記錄 25 次操作到同一個檔案，200 筆
    /// 只留下 98 筆，沒有任何一筆是壞的，而且每一次都以 0 結束——靜默的遺失，發生在那個
    /// 「全部價值就是日後回頭查時東西還在」的檔案上。
    ///
    /// `O_APPEND` 把 seek 與 write 合成單一次核心操作，並行的寫入者因此不可能落在同一個
    /// 位移上。
    ///
    /// **Windows 較弱，而此處說明而非假裝。** CRT 對 `_O_APPEND` 的實作是「每次寫入前先
    /// seek」，那把窗口縮到極小，卻沒有讓它在跨行程之間成為不可分割的操作。誠實的說法是：
    /// POSIX 不會遺失，Windows 遺失的比原本少得多，而兩者都不構成保留「開檔時 seek 一次」
    /// 的理由。
    static func openForAppend(path: String) -> FileHandle? {
        #if canImport(ucrt)
        // FILE_APPEND_DATA without FILE_WRITE_DATA is Windows' real atomic
        // append: the OS moves to the end and writes as one operation, so two
        // processes cannot land on the same offset. Reached through
        // CreateFileW because Swift for Windows marks `_open` unavailable, and
        // handed to a CRT descriptor so the rest of this file stays one code
        // path.
        //
        // The weaker version -- open for writing and seek before every write,
        // which is what the CRT does for _O_APPEND -- was here first, and it
        // was not enough: six processes writing 120 entries to one log left
        // 110. Whole entries, none torn. That is the same silent loss as the
        // POSIX defect this replaced, just smaller.
        //
        // FILE_APPEND_DATA（且不帶 FILE_WRITE_DATA）是 Windows 上真正的不可分割追加：
        // 由作業系統移到檔尾並寫入，合為一次操作，因此兩個行程不可能落在同一個位移上。
        // 以 CreateFileW 取得，因為 Swift for Windows 把 `_open` 標為不可用；再交給一個
        // CRT 描述子，讓這個檔案其餘部分維持單一條程式路徑。
        //
        // 較弱的那個版本——以寫入開啟、每次寫入前 seek，也就是 CRT 對 _O_APPEND 的做法——
        // 原本在這裡，而它不夠：六個行程寫 120 筆到同一個 log，只剩 110 筆。整筆整筆地少，
        // 沒有一筆是壞的。那與它所取代的那個 POSIX 缺陷是同一種靜默遺失，只是小一些。
        let handle: HANDLE = path.withCString(encodedAs: UTF16.self) { wpath in
            CreateFileW(wpath,
                        DWORD(FILE_APPEND_DATA),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE),
                        nil,
                        DWORD(OPEN_ALWAYS),
                        DWORD(FILE_ATTRIBUTE_NORMAL),
                        nil)
        }
        guard handle != INVALID_HANDLE_VALUE else { return nil }
        let fd = _open_osfhandle(intptr_t(bitPattern: handle), _O_APPEND)
        guard fd >= 0 else { CloseHandle(handle); return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        #else
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        #endif
    }

    /// Write to a handle from `openForAppend`. The append property is held by
    /// the operating system on every platform now, so this is a plain write.
    ///
    /// It was not always. This used to seek to the end before each write on
    /// Windows, reproducing what the C runtime does for `_O_APPEND`, because
    /// `_open` is unavailable there and O_APPEND looked out of reach. That
    /// shrinks the window between deciding where the end is and writing there;
    /// it does not close it, and the difference was measurable: six processes
    /// writing 120 entries to one log left 110, whole entries, none torn. The
    /// function survives as one line because the call sites should not have to
    /// know which platform they are on.
    /// 寫入由 `openForAppend` 取得的 handle。「追加」這個性質現在在每個平台上都由作業系統
    /// 持有，因此這裡就是一次單純的寫入。
    ///
    /// 它並非一直如此。原本在 Windows 上會在每次寫入前 seek 到檔尾，重現 C runtime 對
    /// `_O_APPEND` 的做法——因為那裡 `_open` 不可用，O_APPEND 看起來拿不到。那會縮小「判斷
    /// 尾端在哪」與「寫到那裡」之間的窗口，但關不上它，而那個差別是量得到的：六個行程寫
    /// 120 筆到同一個 log，只剩 110 筆，整筆整筆地少，沒有一筆是壞的。這個函式仍以一行的
    /// 形式留著，因為呼叫端不該需要知道自己在哪個平台上。
    static func appendWrite(_ h: FileHandle, _ data: Data) {
        h.write(data)
    }

    /// Write every byte, and when the reader has gone, stop the way a Unix
    /// filter stops.
    ///
    /// `FileHandle.write` cannot be used for this. swift-corelibs-foundation
    /// implements it with `try!`, so `EPIPE` is not an error to handle but a
    /// fatal one: on Linux and Windows csv2 died of SIGILL, exit 132, printing
    /// a Swift backtrace to the stderr of whoever ran `| head`. Darwin's
    /// Foundation does not do that, which is why the behaviour looked correct
    /// for as long as it was only ever measured on macOS.
    ///
    /// A filter whose reader has left has nothing left to do and nothing to
    /// say. On POSIX it dies of SIGPIPE, which is exit 141 and is what the
    /// shell and every other tool in the pipeline expect. Windows has no
    /// SIGPIPE, so 141 is produced directly -- the number is a convention
    /// there rather than a signal, and using the same one keeps a script that
    /// checks for it portable.
    ///
    /// 把每一個位元組寫出去；而當讀取端已經離開時，以「一個 Unix filter 該有的方式」停下來。
    ///
    /// 這裡不能用 `FileHandle.write`。swift-corelibs-foundation 用 `try!` 實作它，於是
    /// `EPIPE` 不是一個「要處理的錯誤」而是一個「致命錯誤」：csv2 在 Linux 與 Windows 上
    /// 死於 SIGILL、結束狀態 132，並把一段 Swift backtrace 印進那個執行 `| head` 的人的
    /// stderr。Darwin 的 Foundation 不是這個實作——而那正是「這個行為看起來一直是對的」的
    /// 原因：它只在 macOS 上被量過。
    ///
    /// 一個讀取端已經離開的 filter，沒有事情要做，也沒有話要說。在 POSIX 上它死於 SIGPIPE，
    /// 也就是結束狀態 141，那是 shell 與管線中其他每一個工具所預期的。Windows 沒有 SIGPIPE，
    /// 因此直接產生 141——在那裡這個數字是一個約定而不是訊號，而沿用同一個數字，可以讓
    /// 「會去檢查它」的腳本保持可攜。
    /// Takes a DESCRIPTOR, not a FileHandle, because Swift for Windows marks
    /// `FileHandle.fileDescriptor` unavailable outright ("Cannot perform
    /// non-owning handle to fd conversion"). Only the stdout sink needs this
    /// path -- a file sink cannot meet a broken pipe -- and stdout is fd 1 in
    /// the C runtime on every platform csv2 builds for, so nothing has to be
    /// converted.
    /// 接受的是「描述子」而不是 FileHandle，因為 Swift for Windows 直接把
    /// `FileHandle.fileDescriptor` 標為不可用。只有 stdout 那個 sink 需要這條路徑——
    /// 檔案 sink 不可能遇到管線斷掉——而 stdout 在 csv2 建置的每個平台上、於 C runtime 中
    /// 都是 fd 1，因此沒有任何東西需要轉換。
    /// Windows' C runtime opens fd 1 and fd 2 in TEXT mode, where every `\n`
    /// written becomes `\r\n`. Foundation's `FileHandle.write` never met this
    /// because it writes through the Win32 handle and not the CRT descriptor;
    /// moving stdout onto `_write` walked straight into it, and 43 cases
    /// failed with output that looked identical and was not -- `got 'zzz',
    /// want 'zzz'`, differing by an invisible CR.
    ///
    /// Set once, before the first write. It restores the promise the README
    /// makes in one line: output always uses `\n`, on every platform.
    ///
    /// Windows 的 C runtime 以「文字模式」開啟 fd 1 與 fd 2，在那裡每一個寫出的 `\n` 都會
    /// 變成 `\r\n`。Foundation 的 `FileHandle.write` 從未遇到這件事，因為它寫的是 Win32
    /// handle 而不是 CRT 描述子；把 stdout 改走 `_write` 就正面撞上了它，43 個案例因此失敗，
    /// 而它們的輸出「看起來一模一樣」卻不相同——`got 'zzz', want 'zzz'`，差在一個看不見的 CR。
    ///
    /// 在第一次寫出之前設定一次。它守住 README 用一句話給出的那個承諾：輸出一律使用 `\n`，
    /// 在每一個平台上。
    private static var binaryModeSet = false

    private static func ensureBinaryMode(_ fd: Int32) {
        #if canImport(ucrt)
        if binaryModeSet { return }
        binaryModeSet = true
        _ = _setmode(1, _O_BINARY)
        _ = _setmode(2, _O_BINARY)
        #endif
    }

    /// Writes every byte, or returns the errno that stopped it. 0 means all of
    /// them went.
    ///
    /// EPIPE is the one failure that is not an error: the reader left, and a
    /// filter should die of SIGPIPE like every other one. Everything else IS an
    /// error and is handed back to the caller, who knows which file it was and
    /// can say so. Treating them alike is how a full disk came to look exactly
    /// like `| head`: ENOSPC raised SIGPIPE, csv2 exited 141 with nothing on
    /// stderr and a half-written file on disk, and 141 is the status the README
    /// tells callers to disregard.
    /// 把每一個位元組寫出去，或回傳讓它停下來的 errno。0 表示全部寫完。
    /// EPIPE 是唯一「不算錯誤」的失敗：讀端走了，而一個 filter 應該像其他每一個那樣死於
    /// SIGPIPE。其餘都**是**錯誤，交還給呼叫端——它知道那是哪一個檔案，說得出口。把兩者
    /// 一視同仁，正是「磁碟寫滿」長得跟 `| head` 一模一樣的原因：ENOSPC 引發了 SIGPIPE，
    /// csv2 以 141 結束、stderr 上一個字也沒有、磁碟上留著寫到一半的檔案，而 141 正是
    /// README 叫呼叫端不必理會的那個狀態。
    @discardableResult
    static func writeAll(fd: Int32, _ bytes: [UInt8]) -> Int32 {
        if bytes.isEmpty { return 0 }
        ensureBinaryMode(fd)
        var off = 0
        var failure: Int32 = 0
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            while off < bytes.count {
                let remaining = bytes.count - off
                #if canImport(ucrt)
                let n = Int(_write(fd, base + off, UInt32(remaining)))
                #else
                let n = write(fd, base + off, remaining)
                #endif
                if n > 0 { off += n; continue }
                #if canImport(ucrt)
                // Windows has no SIGPIPE, and csv2 emulates one deliberately:
                // `| head -1` must end in 141 here as it does everywhere else,
                // which is what T110d pins. So a departed reader has to be
                // told apart from every other write failure, and the CRT's
                // errno is not enough -- the answer is in GetLastError.
                // ERROR_BROKEN_PIPE is the reader closing its end;
                // ERROR_NO_DATA is the same thing on a named pipe.
                // Windows 沒有 SIGPIPE，而 csv2 是刻意模擬它的：`| head -1` 在這裡也必須以
                // 141 結束，一如其他每一個平台，那正是 T110d 釘住的東西。因此「讀端走了」
                // 必須與其他每一種寫入失敗分開，而 CRT 的 errno 不足以分辨——答案在
                // GetLastError 裡。ERROR_BROKEN_PIPE 是讀端關掉了它那一端；具名管線上
                // 的同一件事則是 ERROR_NO_DATA。
                let winErr = GetLastError()
                if errno == EPIPE || winErr == ERROR_BROKEN_PIPE || winErr == ERROR_NO_DATA {
                    readerHasGone()
                }
                failure = errno == 0 ? EIO : errno
                return
                #else
                if n < 0 && errno == EINTR { continue }
                if n < 0 && errno == EPIPE { readerHasGone() }
                failure = n < 0 ? errno : EIO
                return
                #endif
            }
        }
        return failure
    }

    /// Open a file for writing, truncating it. A descriptor, and nothing else.
    ///
    /// No FileHandle: wrapping a CRT descriptor in one and then calling
    /// `synchronize()` killed csv2 on Windows with no message and no exit
    /// status worth reading -- every `-o` and `--in-place` run, while `-so`
    /// and reads were fine. FileHandle on Windows carries a HANDLE of its own
    /// and a descriptor it was handed is not the same thing. The temp file is
    /// opened, written, synced and closed through the descriptor on every
    /// platform now, which is also one code path instead of two.
    /// 以寫入開啟並截斷一個檔案。回傳一個描述子，沒有別的。
    /// 不用 FileHandle：把一個 CRT 描述子包進 FileHandle、再呼叫 `synchronize()`，會讓
    /// csv2 在 Windows 上無聲死去——每一次 `-o` 與 `--in-place` 都是，而 `-so` 與讀取
    /// 都正常。Windows 上的 FileHandle 自己帶著一個 HANDLE，而「別人交給它的描述子」
    /// 不是同一個東西。暫存檔現在在每個平台上都以描述子開啟、寫入、同步與關閉，
    /// 這同時也把兩條程式路徑併成一條。
    static func openForWrite(path: String) -> Int32? {
        #if canImport(ucrt)
        let h: HANDLE = path.withCString(encodedAs: UTF16.self) { wpath in
            CreateFileW(wpath,
                        DWORD(GENERIC_WRITE),
                        DWORD(FILE_SHARE_READ),
                        nil,
                        DWORD(CREATE_ALWAYS),
                        DWORD(FILE_ATTRIBUTE_NORMAL),
                        nil)
        }
        guard h != INVALID_HANDLE_VALUE else { return nil }
        let fd = _open_osfhandle(intptr_t(bitPattern: h), _O_BINARY)
        guard fd >= 0 else { CloseHandle(h); return nil }
        return fd
        #else
        // 0600, not the umask's 0644. The temp file holds the whole contents of
        // the file being edited, and copyMode does not run until just before
        // the rename -- so a 0600 source spent the entire write world-readable
        // under a name anyone could open. Measured on a 15 MB file: the temp
        // was -rw-r--r-- for the duration and -rw------- afterwards, and the
        // README's "an edit does not change who can read it" was true only of
        // the finished file.
        //
        // Starting private and widening at the end is the right order: the
        // mode that matters during the write is the source's, and 0600 is
        // never wider than that.
        // 用 0600，不是 umask 的 0644。暫存檔裝的是「正在被編輯的那個檔案」的全部內容，而
        // copyMode 要到 rename 之前才執行——因此一個 0600 的來源，在整個寫入期間都以一個
        // 「任何人都開得了」的名字、對所有人可讀。15 MB 檔案上的實測：暫存檔在那段時間是
        // -rw-r--r--，結束後才是 -rw-------，而 README 那句「一次編輯不會改變誰讀得到它」
        // 只對「完成後的檔案」成立。
        // 先私有、最後再放寬，才是對的順序：寫入期間該生效的是來源的模式，而 0600 永遠不會
        // 比它更寬。
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return nil }
        return fd
        #endif
    }

    /// Flush a descriptor's data to the medium, not just to the OS cache.
    /// `_commit` is the CRT's fsync; F_FULLFSYNC is the only thing on Darwin
    /// that reaches the platter rather than the drive's own cache.
    ///
    /// This replaced a version taking a FileHandle, which existed because
    /// `FileHandle.fileDescriptor` is unavailable on Windows ("Cannot perform
    /// non-owning handle to fd conversion") -- so the descriptor could not be
    /// recovered from a handle and the difference had to live here rather than
    /// in Core.swift. Found on the first Windows compile, 2026-08-19. The
    /// answer now is the other direction: carry the descriptor and never make
    /// a handle, which also avoids `synchronize()` on a handle wrapping a CRT
    /// descriptor -- that combination killed every -o run on Windows silently.
    /// 把一個描述子的資料送到儲存媒體，而不只是送進作業系統的快取。
    /// `_commit` 是 CRT 的 fsync；在 Darwin 上，只有 F_FULLFSYNC 會真正抵達碟片，
    /// 而不是停在磁碟自己的快取裡。
    static func syncFD(_ fd: Int32) -> Bool {
        #if canImport(ucrt)
        return _commit(fd) == 0
        #elseif canImport(Darwin)
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        // Some filesystems do not implement F_FULLFSYNC and return ENOTSUP.
        // 有些檔案系統未實作 F_FULLFSYNC，會回傳 ENOTSUP。
        return fsync(fd) == 0
        #else
        return fsync(fd) == 0
        #endif
    }

    static func closeFD(_ fd: Int32) {
        #if canImport(ucrt)
        _ = _close(fd)
        #else
        _ = close(fd)
        #endif
    }

    /// Everything csv2 says to stderr goes through here.
    ///
    /// Not `FileHandle.standardError.write`: that answers a failed write with
    /// an exception nobody catches, so `csv2 -get 9:9 -i f.csv 2>&-` -- an
    /// ordinary thing for a script to do -- exited 134 while PRINTING THE
    /// REFUSAL, turning an exit status of 1 into one the documentation does
    /// not contain. Reporting an error is the last place that should be able
    /// to fail this way.
    ///
    /// A departed reader still ends the process with SIGPIPE, inside
    /// writeAll: `csv2 -debug 2>&1 | head -1` is a pipeline, not a fault. Any
    /// other failure means stderr cannot be written, and there is nothing
    /// further to say about it -- the caller's exit status is what carries the
    /// news.
    /// csv2 對 stderr 說的每一句話都走這裡。
    /// 不用 `FileHandle.standardError.write`：它對「寫入失敗」的回答是一個沒有人接的例外，
    /// 因此 `csv2 -get 9:9 -i f.csv 2>&-`——腳本裡很平常的寫法——會在「印出那則拒絕」的
    /// 當下以 134 結束，把一個本該是 1 的結束狀態，換成一個文件裡根本沒有的數字。
    /// 「回報一個錯誤」是最不該以這種方式失敗的地方。
    /// 讀端離開仍然會在 writeAll 裡以 SIGPIPE 結束行程：`csv2 -debug 2>&1 | head -1`
    /// 是一條管線，不是故障。其餘的失敗只表示 stderr 寫不出去，而那件事沒有別的話好說
    /// ——把消息帶出去的是呼叫端拿到的結束狀態。
    static func writeStderr(_ text: String) {
        _ = writeAll(fd: 2, [UInt8](text.utf8))
    }

    /// What kind of thing a path names, for the one question csv2 asks about
    /// it: can a temp file be renamed onto this?
    ///
    /// Here rather than at the call site because `st_mode` is UInt16 on
    /// Windows and Int32 elsewhere, and S_IFMT and friends differ in type with
    /// it -- the check compiled on macOS and Linux and would not build at all
    /// on Windows, which is the difference this file exists to absorb. Windows
    /// has no FIFOs in the POSIX sense; `.other` covers whatever it does have.
    /// 一個路徑指的是什麼東西——只為了 csv2 對它問的那一個問題：暫存檔 rename 得上去嗎？
    /// 放在這裡而不是呼叫端，因為 `st_mode` 在 Windows 上是 UInt16、其他平台是 Int32，
    /// 而 S_IFMT 之類的常數型別也跟著不同——那個檢查在 macOS 與 Linux 上編得過，在 Windows
    /// 上根本建不起來，而那正是本檔案存在要吸收的差異。Windows 沒有 POSIX 意義下的 FIFO；
    /// `.other` 涵蓋它實際會有的東西。
    enum FileKind { case regular, directory, fifo, other }

    /// The append descriptor itself, for a caller that wants `writeAll`'s error
    /// handling rather than `FileHandle.write`'s `try!`.
    ///
    /// `FileHandle.fileDescriptor` cannot be used to get here: it is marked
    /// UNAVAILABLE on Windows, and reaching for it broke the Windows build --
    /// which the node then survived by keeping its old binary and running the
    /// new tests against it, so the suite reported five failures that looked
    /// like a defect in the metrics line and were a build that never ran.
    /// 追加用的描述子本身，給「想要 writeAll 的錯誤處理、而不是 FileHandle.write 的 try!」
    /// 的呼叫端。
    ///
    /// 不能用 `FileHandle.fileDescriptor` 來取得它：那在 Windows 上被標記為「不可用」，
    /// 而伸手去拿它弄壞了 Windows 的建置——那台節點於是保留了舊的二進位檔、拿新的測試去跑它，
    /// 於是測試回報了五個「看起來像 metrics 那一行有缺陷」的失敗，而真相是一次從未跑起來的建置。
    static func openAppendFD(path: String) -> Int32? {
        #if canImport(ucrt)
        let handle: HANDLE = path.withCString(encodedAs: UTF16.self) { wpath in
            CreateFileW(wpath,
                        DWORD(FILE_APPEND_DATA),
                        DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE),
                        nil,
                        DWORD(OPEN_ALWAYS),
                        DWORD(FILE_ATTRIBUTE_NORMAL),
                        nil)
        }
        guard handle != INVALID_HANDLE_VALUE else { return nil }
        let fd = _open_osfhandle(intptr_t(bitPattern: handle), _O_APPEND)
        guard fd >= 0 else { CloseHandle(handle); return nil }
        return fd
        #else
        let fd = open(path, O_WRONLY | O_APPEND)
        return fd >= 0 ? fd : nil
        #endif
    }

    /// Device and inode: the pair that says two names are ONE file, which a
    /// path comparison cannot. `-i x -o y` where the two are hard links to the
    /// same inode passed every spelling check -- `./`, `../`, absolute,
    /// symlink -- and then broke the link at rc=0, leaving the caller with one
    /// name holding the edit and the other holding what used to be shared.
    /// Nil on Windows, where the CRT reports inode 0 for everything and the
    /// answer would be "every file is every other file".
    /// 裝置號與 inode：這一對才說得出「兩個名字是同一個檔案」，而比對路徑說不出。
    /// `-i x -o y` 在兩者是同一個 inode 的硬連結時，通過了每一種拼法的檢查——`./`、`../`、
    /// 絕對路徑、symlink——然後以 rc=0 把那個連結斷開，留給呼叫端一個「有這次編輯」的名字，
    /// 和一個「還是原本共用內容」的名字。Windows 上回傳 nil：CRT 對所有檔案都回報 inode 0，
    /// 那個答案會變成「每個檔案都是彼此」。
    static func fileNode(path: String) -> (dev: UInt64, ino: UInt64)? {
        #if canImport(ucrt)
        return nil
        #else
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        // bitPattern, not UInt64(_:). `st_dev` is a SIGNED 32-bit dev_t on
        // Darwin and a device node's is negative: /dev/null reports -1, and
        // `UInt64(-1)` is a Swift trap -- SIGTRAP, exit 133, nothing on either
        // stream. Introduced on 2026-08-21 by the hard-link fix, which turned
        // `-o /dev/null` from the documented two-line refusal into a silent
        // crash, on the very example the refusals table names. The identity is
        // only ever compared for equality, so the bit pattern is the whole of
        // what it needs to be.
        // 用 bitPattern，不用 UInt64(_:)。Darwin 上的 `st_dev` 是「有號」的 32 位元 dev_t，
        // 而一個裝置節點的值是負的：/dev/null 回報 -1，而 `UInt64(-1)` 是一個 Swift trap
        // ——SIGTRAP、exit 133、兩條輸出流上都沒有東西。這是 2026-08-21 那個「硬連結」修正
        // 帶進來的，它把 `-o /dev/null` 從一條「有記載的兩行拒絕」變成一次無聲的當機，而那
        // 正是拒絕表拿來當範例的那一個。這個身分只會被拿去比對相等，因此「位元樣式」就是
        // 它需要的全部。
        return (UInt64(bitPattern: Int64(st.st_dev)), UInt64(st.st_ino))
        #endif
    }

    /// A blocking read-only open, for the one input that needs to WAIT: a
    /// FIFO with no writer yet. Returns -1 on failure.
    /// 一個會阻塞的唯讀開檔，給那個唯一需要「等」的輸入用：一個還沒有寫入端的 FIFO。
    /// 失敗時回傳 -1。
    static func openBlockingForRead(path: String) -> Int32 {
        #if canImport(ucrt)
        return -1   // no FIFOs in a path name on Windows / Windows 的路徑名裡沒有 FIFO
        #else
        return open(path, O_RDONLY)
        #endif
    }

    static func fileKind(path: String) -> FileKind? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        // The numbers rather than the names: on Windows `S_IFMT` is ambiguous
        // -- the CRT exposes both it and `_S_IFMT` -- and Swift refuses to
        // choose. The values are the same everywhere csv2 builds (0o170000,
        // 0o100000, 0o040000, 0o010000) and have been since V7 Unix, so
        // writing them costs nothing and removes a per-platform spelling.
        // 用數字而不是名字：在 Windows 上 `S_IFMT` 是有歧義的——CRT 同時提供它與 `_S_IFMT`
        // ——而 Swift 拒絕替我們選。這些值在 csv2 建置的每一個平台上都相同（0o170000、
        // 0o100000、0o040000、0o010000），而且從 V7 Unix 以來就是這樣，因此直接寫出來
        // 沒有任何代價，還少掉一組「每個平台各自拼寫」的名字。
        let fmt = UInt32(st.st_mode) & 0o170000
        if fmt == 0o100000 { return .regular }
        if fmt == 0o040000 { return .directory }
        #if !canImport(ucrt)
        if fmt == 0o010000 { return .fifo }
        #endif
        return .other
    }

    /// Can a new file be created in this directory? The question `-o` really
    /// asks, since it writes a temp file there before renaming.
    ///
    /// `_access` on Windows, `access` elsewhere; W_OK is 2 in both. Asked here
    /// so the refusal can name the path the caller typed, rather than failing
    /// later with a path the shell produced -- `-o /dev/stdout` with stdout
    /// redirected to a file resolves to /dev/fd/1, whose DIRECTORY is /dev,
    /// and the old failure read "cannot create temporary file beside
    /// /dev/fd/1: No such file or directory": a false cause, a path never
    /// typed, and no way out.
    /// 這個目錄裡建得了新檔案嗎？那才是 `-o` 真正要問的問題——它會先在那裡寫一個暫存檔，
    /// 再 rename。
    /// Windows 用 `_access`、其他平台用 `access`，W_OK 兩邊都是 2。在這裡問，是為了讓那條
    /// 拒絕能指名「呼叫端打出來的路徑」，而不是稍後以一個 shell 產生的路徑失敗——
    /// `-o /dev/stdout` 在 stdout 被導向檔案時會解析成 /dev/fd/1，它的「目錄」是 /dev，
    /// 而舊的失敗訊息是「cannot create temporary file beside /dev/fd/1: No such file or
    /// directory」：錯的原因、沒打過的路徑、沒有出路。
    static func directoryAcceptsNewFiles(_ dir: String) -> Bool {
        let d = dir.isEmpty ? "." : dir
        guard fileKind(path: d) == .directory else { return false }
        #if canImport(ucrt)
        return _access(d, 2) == 0
        #else
        return access(d, W_OK) == 0
        #endif
    }

    /// The system's text for an errno, as a message can print it.
    /// 一個 errno 對應的系統文字，可直接印在訊息裡。
    static func errorText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }

    // -----------------------------------------------------------------
    // MARK: - Removing the temp file when the run is killed / 被殺死時清掉暫存檔
    // -----------------------------------------------------------------

    /// The path a signal handler is allowed to unlink, as a C string.
    ///
    /// Preallocated on purpose. A handler may not allocate, may not take a
    /// lock, and may not call into Swift's runtime -- so the path cannot be
    /// converted from a String at the moment the signal arrives. It is
    /// converted when the temp file is created and freed when it is gone.
    /// 一個訊號處理常式可以 unlink 的路徑，以 C 字串形式。
    /// 刻意預先配置。處理常式不可配置記憶體、不可取鎖、不可呼叫 Swift runtime——因此那個
    /// 路徑不能等訊號到達時才從 String 轉換。它在暫存檔建立時轉換，在暫存檔消失時釋放。
    private static var doomedTemp: UnsafeMutablePointer<CChar>?

    /// Remember a temp file for the duration of the write, so an interrupted
    /// run does not leave it beside the target.
    ///
    /// The README promises a failed in-place edit "leaves no temp file beside
    /// it", and that was true only of the error paths: a SIGINT, SIGTERM or
    /// SIGHUP part-way through a 32 MB edit left a hidden 4 MB file behind,
    /// invisible to `ls` and never cleaned up. SIGKILL still can, and always
    /// will -- it cannot be caught -- which is why the README now says so.
    /// 在寫入期間記住一個暫存檔，好讓一次被中斷的執行不會把它留在目標旁邊。
    /// README 承諾「失敗的就地編輯不會在旁邊留下暫存檔」，而那只在錯誤路徑上成立：一次
    /// 32 MB 編輯進行到一半收到 SIGINT／SIGTERM／SIGHUP，會留下一個 4 MB 的隱藏檔，
    /// `ls` 看不到，也沒有人會清掉。SIGKILL 仍然會、而且永遠會——它攔不下來——所以 README
    /// 現在把這件事寫出來了。
    static func rememberTemp(_ path: String) {
        forgetTemp()
        doomedTemp = strdup(path)
        #if !canImport(ucrt)
        // Every catchable signal whose default action ends the process, not
        // the three that came to mind. A round killed an edit with SIGXFSZ,
        // SIGPIPE, SIGALRM and SIGUSR1 and got a 13 MB hidden temp file each
        // time, against a README that names SIGKILL as the one that leaves
        // one. SIGXFSZ is not exotic -- an `ulimit -f` or a filesystem quota
        // produces it.
        //
        // SIGPIPE is included and does not disturb readerHasGone(): that path
        // restores SIG_DFL before re-raising, so the handler runs at most once
        // and the process still dies of the signal.
        // 每一個「可攔截、且預設動作是結束行程」的訊號，而不是當初想到的那三個。有一個回合
        // 用 SIGXFSZ、SIGPIPE、SIGALRM、SIGUSR1 各殺了一次編輯，每次都留下一個 13 MB 的
        // 隱藏暫存檔——而 README 寫的是「SIGKILL 是那個會留下暫存檔的」。SIGXFSZ 一點也不
        // 罕見：一個 `ulimit -f` 或檔案系統配額就會產生它。
        // SIGPIPE 也在其中，且不會干擾 readerHasGone()：那條路徑會先還原 SIG_DFL 再重新
        // 引發，因此處理常式最多跑一次，而行程仍然死於那個訊號。
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGXFSZ, SIGXCPU,
                    SIGALRM, SIGUSR1, SIGUSR2, SIGPIPE, SIGVTALRM, SIGPROF] {
            signal(sig, { received in
                if let p = Platform.doomedTempPointer { unlink(p) }
                signal(received, SIG_DFL)
                raise(received)
            })
        }
        #endif
    }

    /// Readable from a signal handler: a plain pointer load, no Swift runtime.
    /// 供訊號處理常式讀取：單純載入一個指標，不經過 Swift runtime。
    static var doomedTempPointer: UnsafeMutablePointer<CChar>? { doomedTemp }

    static func forgetTemp() {
        if let p = doomedTemp { free(p) }
        doomedTemp = nil
    }

    /// Exit as a filter does when its reader has gone: no message, no output
    /// file, the status the shell expects.
    /// 以「讀取端離開時 filter 該有的方式」結束：不留訊息、不留輸出檔，狀態就是 shell 預期的
    /// 那一個。
    private static func readerHasGone() -> Never {
        #if canImport(ucrt)
        ucrt._exit(141)
        #else
        // Restored to the default and re-raised rather than calling exit(141):
        // the shell distinguishes "killed by signal 13" from "exited with 141"
        // in $?-adjacent places, and a filter should look like every other one.
        // 先還原成預設處置再重新引發，而不是直接 exit(141)：shell 在某些地方會區分「被訊號
        // 13 殺死」與「以 141 結束」，而一個 filter 應該與其他每一個長得一樣。
        signal(SIGPIPE, SIG_DFL)
        raise(SIGPIPE)
        _exit(141)
        #endif
    }

    /// Copy a file's permission bits onto another file.
    ///
    /// The temp-file-and-rename that makes a write atomic for readers also
    /// makes the result a NEW file, with the umask's mode rather than the
    /// original's. A file at 0644 stayed 0644 only by coincidence; one at 0600
    /// came back world-readable, and one at 0444 was rewritten at all, because
    /// rename needs permission on the DIRECTORY and never looks at the file.
    ///
    /// Restoring the mode does not restore the read-only intent -- csv2 still
    /// rewrites a 0444 file -- but it stops an edit from quietly widening who
    /// can read it, which is the half that loses data to someone else.
    ///
    /// 把一個檔案的權限位元套到另一個檔案上。
    ///
    /// 讓寫入對讀者而言不可分割的那個「暫存檔 + rename」，同時也讓結果成為一個「新」檔案，
    /// 帶的是 umask 的模式而不是原檔的。一個 0644 的檔案維持 0644 只是碰巧；一個 0600 的
    /// 會變成全世界可讀，而一個 0444 的根本會被改寫——因為 rename 需要的是「目錄」的權限，
    /// 它從來不看那個檔案。
    ///
    /// 還原模式並不能還原「唯讀」這個意圖——csv2 仍然會改寫一個 0444 的檔案——但它能阻止
    /// 一次編輯悄悄放寬「誰讀得到它」，而那一半才是會把資料交給別人的那一半。
    static func copyMode(from source: String, to destination: String) {
        #if !canImport(ucrt)
        var st = stat()
        guard stat(source, &st) == 0 else { return }
        _ = chmod(destination, st.st_mode & 0o7777)
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
        // K32GetProcessMemoryInfo, not GetProcessMemoryInfo. The two are the
        // same call; the difference is which DLL exports it. The psapi.h name
        // lives in psapi.dll and is NOT in the set Swift's WinSDK module
        // surfaces, so it does not resolve -- `cannot find
        // 'GetProcessMemoryInfo' in scope`, which was the ONE error in the
        // whole source on the first Windows compile, 2026-08-19. The K32
        // prefixed form has been exported from kernel32 since Windows 7 and
        // does resolve. Measured on that machine: 9129984 bytes.
        // 用 K32GetProcessMemoryInfo，不是 GetProcessMemoryInfo。兩者是同一個呼叫，
        // 差別在於由哪個 DLL 匯出。psapi.h 的那個名字住在 psapi.dll，而它**不在** Swift 的
        // WinSDK 模組所呈現的那一組裡，因此解析不到——`cannot find 'GetProcessMemoryInfo'
        // in scope`，那是 2026-08-19 第一次 Windows 編譯時，整份原始碼裡唯一的錯誤。
        // 帶 K32 前綴的那個自 Windows 7 起由 kernel32 匯出，解析得到。在該機器上實測：
        // 9129984 bytes。
        guard K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, counters.cb) else { return 0 }
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

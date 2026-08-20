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
    /// Takes the FileHandle, not a descriptor, because `FileHandle
    /// .fileDescriptor` IS UNAVAILABLE ON WINDOWS -- "Cannot perform
    /// non-owning handle to fd conversion". The old signature took an Int32,
    /// which forced the one call site to reach for that property and put a
    /// platform difference in Core.swift, where this file's header says it
    /// must not live. It compiled on two platforms for months because neither
    /// of them minded; the third would not build at all. Found on the first
    /// Windows compile, 2026-08-19, as the second of the two errors.
    ///
    /// Windows uses Foundation's `synchronize()`, which calls FlushFileBuffers
    /// itself -- the same call the previous `_get_osfhandle` branch made, minus
    /// a descriptor round trip that cannot be taken there.
    ///
    /// 收的是 FileHandle 而不是 descriptor，因為 **`FileHandle.fileDescriptor` 在 Windows
    /// 上不可用**——「Cannot perform non-owning handle to fd conversion」。舊的簽章收 Int32，
    /// 於是唯一的呼叫點必須去碰那個屬性，把一個平台差異放進了 Core.swift——而本檔案開頭
    /// 說明了那種東西不該住在那裡。它在兩個平台上編了好幾個月，因為那兩個都不介意；
    /// 第三個則根本建不起來。發現於 2026-08-19 第一次 Windows 編譯，是兩個錯誤中的第二個。
    /// Windows 改用 Foundation 的 `synchronize()`，它內部呼叫的就是 FlushFileBuffers
    /// ——與先前 `_get_osfhandle` 分支所做的是同一件事，只是少了一次「在那裡根本走不通」的
    /// descriptor 往返。
    static func flushToDisk(_ handle: FileHandle) -> Bool {
        #if canImport(ucrt)
        do { try handle.synchronize(); return true } catch { return false }
        #elseif canImport(Darwin)
        let fd = handle.fileDescriptor
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        // Some filesystems do not implement F_FULLFSYNC and return ENOTSUP.
        // fsync is then the strongest thing available, and saying so beats
        // failing the write over it.
        // 有些檔案系統未實作 F_FULLFSYNC，會回傳 ENOTSUP。此時 fsync 就是可用的
        // 最強手段，退回它並說明，好過為此讓寫入失敗。
        return fsync(fd) == 0
        #else
        return fsync(handle.fileDescriptor) == 0
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

    static func writeAll(fd: Int32, _ bytes: [UInt8]) {
        if bytes.isEmpty { return }
        ensureBinaryMode(fd)
        var off = 0
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
                #if !canImport(ucrt)
                if n < 0 && errno == EINTR { continue }
                #endif
                readerHasGone()
            }
        }
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

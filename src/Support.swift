// =====================================================================
//  Support.swift — key handling, logging, JSON and Markdown emitters
//  Support.swift — 金鑰處理、記錄、JSON 與 Markdown 輸出
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - Logging / 記錄
// ---------------------------------------------------------------------

enum LogLevel: Int, Comparable {
    case trace = 0, debug, info, warn, error
    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO "
        case .warn: return "WARN "
        case .error: return "ERROR"
        }
    }
}

/// `-debug` and `-log` are deliberately two different things. `-debug` is for
/// someone chasing a problem right now: high volume, format may change, thrown
/// away when done. `-log` is for whoever later asks who changed this file:
/// low volume, stable format, kept. Writing both to one place drowns the
/// history in the debugging.
/// `-debug` 與 `-log` 刻意是兩個不同的東西。`-debug` 給「現在正在查一個問題」
/// 的人看：量大、格式可變、用完即棄。`-log` 給「日後要回頭查這個檔案被誰改成
/// 這樣」的人看：量小、格式穩定、要保存。寫進同一個地方會讓歷史被除錯輸出淹沒。
/// Read a numeric environment knob, or refuse.
///
/// A plain `if let n = Int(v)` fails three different ways: a negative value
/// can trap (exit 133, nothing on either stream), be accepted and reported
/// back as a limit of -1, or an unparseable value like `16MiB` is ignored and
/// -debug prints the default under the variable's own name, which reads as
/// confirmation.
///
/// An environment variable is input, and malformed input is not silently
/// repaired: a bad value is refused by name, quoted back, before any work
/// starts.
///
/// 讀取一個數值型的環境旋鈕，否則拒絕。
///
/// 單純的 `if let n = Int(v)` 有三種出錯方式：負數可能直接 trap（以 133 結束、兩個串流都
/// 沒有輸出），或被接受後回報成「上限 -1」；而 `16MiB` 這類無法解析的值會被忽略，`-debug`
/// 再用該變數自己的名字印出預設值，看起來就像確認。
///
/// 環境變數就是輸入，而格式錯誤的輸入不做靜默修復：壞的值會被指名拒絕、原樣引述，
/// 且在任何工作開始之前。
func envInt(_ name: String, default def: Int, min lower: Int = 1) throws -> Int {
    guard let raw = ProcessInfo.processInfo.environment[name], !raw.isEmpty else { return def }
    guard let n = Int(raw) else {
        throw fault(
            "\(name)=\(raw) is not a number; csv2 will not fall back to the default silently, because -debug would then print that default under this variable's own name and read as confirmation",
            "\(name)=\(raw) 不是數字；csv2 不會靜默退回預設值，因為那樣 -debug 會用這個變數自己的名字印出那個預設值，讀起來像是確認")
    }
    guard n >= lower else {
        throw fault(
            "\(name)=\(n) is below the minimum of \(lower)",
            "\(name)=\(n) 低於最小值 \(lower)")
    }
    return n
}

/// Every numeric knob, checked once, before any work starts.
///
/// The readers are non-throwing computed properties in four files; threading
/// `throws` through them would put the check in four places that each have to
/// remember it. One pass here refuses a bad value before a byte is read, and
/// the readers can assume the value is valid.
///
/// 每一個數值旗標，在任何工作開始之前檢查一次。
///
/// 讀取點是散在四個檔案裡、不會 throw 的計算屬性；把 `throws` 穿過它們，等於把檢查放進
/// 四個各自都得記得的地方。在這裡檢查一次，壞的值在讀進任何位元組之前就被拒絕，讀取點
/// 則可以假設值是有效的。
func validateEnvironment() throws {
    _ = try envInt("CSV2_PARALLEL_MIN_BYTES", default: 0, min: 0)
    _ = try envInt("CSV2_PARALLEL_CHUNK_BYTES", default: 1, min: 1)
    _ = try envInt("CSV2_PARALLEL_MAX_BYTES", default: 1, min: 1)
    _ = try envInt("CSV2_PRETTY_MAX_BYTES", default: 1, min: 1)
    _ = try envInt("CSV2_MAX_BUFFER_RECORDS", default: 1, min: 1)
    _ = try envInt("CSV2_INDEX_MIN_BYTES", default: 0, min: 0)
}

// lineEscape and reportEscape live here, not in Ops.swift: their callers are Core.swift, the
// Logger below, and main.swift, and keeping them here lets the parsing and encoding layer
// compile without the CLI operation layer.
// lineEscape 與 reportEscape 放在這裡而非 Ops.swift：呼叫者是 Core.swift、下方的 Logger 與
// main.swift，放在這裡也讓解析與編碼層可以不帶進 CLI 操作層而單獨編譯。

func lineEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    // Unicode SCALARS, not Characters. A Swift `Character` is a grapheme
    // cluster and CRLF is ONE of them, so a `case "\n"` / `case "\r"` switch
    // over Characters matches neither half of a `\r\n` pair and lets it
    // through intact, opening a second log line whose whole content, timestamp
    // included, comes from the input -- reachable from a plain `-contains`.
    //
    // 用 Unicode「純量」，不是 Character。Swift 的 `Character` 是 grapheme cluster，而 CRLF
    // 就是其中「一個」，因此以 Character 去 switch 的 `case "\n"` / `case "\r"` 對 `\r\n`
    // 兩半都不匹配而讓它原樣通過，在 log 裡開出第二行，整行內容連同時間戳都來自輸入——
    // 一次普通的 `-contains` 就能觸發。
    for u in s.unicodeScalars {
        switch u {
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out
}
func reportEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    // Scalars, for the reason spelled out on lineEscape above: CRLF is a
    // single Character and a Character switch lets it through. Here that would
    // break "one line per matching cell", the shape scripts depend on: one hit
    // would print two lines.
    // 用純量，理由與上面 lineEscape 的註解相同：CRLF 是單一個 Character，以 Character
    // 去 switch 會讓它通過。在這裡那會打破腳本所依賴的「每個命中的儲存格一行」——
    // 一個命中會印成兩行。
    for u in s.unicodeScalars {
        switch u {
        case "\\": out += "\\\\"
        case "\t": out += "\\t"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        default:
            // Every other C0 control, and DEL, as \\xNN. The report is written to a
            // terminal, and ESC is not text there: a value can start a colour
            // sequence, move the cursor, or erase the line it is being printed on --
            // including the address printed before it.
            // The three that already have names keep their short forms. This does not
            // make the third column reversible -- the README says it is a display form
            // and not for feeding back -- it makes it one that cannot rewrite what the
            // other columns said.
            // 其餘每一個 C0 控制字元與 DEL，一律寫成 \\xNN。這份報告是印到終端機上的，而 ESC
            // 在那裡不是文字：一個值可以起一段顏色序列、移動游標，或抹掉它正被印出的那一行
            // ——連同印在它前面的那個位址。已經有名字的那三個保留短形式。這不會讓第三欄變得
            // 可逆，它讓那個形式無法改寫其他欄位說過的話。
            if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out
}

/// The singleton is configured, used and closed by the CLI coordinator. The
/// parallel workers return values to that coordinator and never call Logger
/// themselves. `@unchecked Sendable` records that ownership boundary without
/// imposing MainActor on the parser and byte-stream library surface.
/// 這個單例由 CLI 協調執行緒設定、使用並關閉；平行工作者只把值交回協調端，不會自行
/// 呼叫 Logger。`@unchecked Sendable` 記錄這條所有權界線，同時不把 MainActor 強加到
/// parser 與位元組串流的 library 表面。
final class Logger: @unchecked Sendable {
    static let shared = Logger()

    var threshold: LogLevel = .warn
    private var logPath: String?
    private var logHandle: FileHandle?
    private var logWarned = false
    /// Column names whose values must never reach the log. / 其值絕不可進入 log 的欄名。
    var redactedColumns: Set<String> = []

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        // POSIX locale, not the user's. The guest runs a different locale
        // from the host, and a date format that follows the locale would put
        // two shapes of timestamp in the same log file.
        // 使用 POSIX locale 而非使用者的。guest 與 host 的 locale 不同，跟隨
        // locale 的日期格式會讓同一份 log 出現兩種格式。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    /// ISO 8601 WITH the UTC offset. The guest runs UTC and the host +08:00;
    /// without the offset the two sides' events cannot be put on one timeline.
    /// ISO 8601 且帶時區位移。guest 在 UTC、host 在 +08:00，沒有位移就無法把
    /// 兩邊的事件排在同一條時間線上。
    static func timestamp() -> String { formatter.string(from: Date()) }

    /// Append, never truncate: overwriting defeats the only purpose the file
    /// has, which is being read later.
    ///
    /// Opening for write and calling `seekToEndOfFile()` seeks only once, so
    /// concurrent processes overwrite each other's entries at rc=0.
    /// `Platform.openForAppend` puts the append in the kernel, where a
    /// concurrent writer cannot be raced.
    /// 一律追加，絕不覆寫：覆寫會讓這個檔案唯一的用途（日後回頭查）失效。
    /// 「以寫入開啟後 seekToEndOfFile()」只 seek 一次，多個行程並行時會互相蓋掉紀錄，
    /// 且都以 0 結束。`Platform.openForAppend` 把追加交給核心，並行的寫入者在那裡搶不到
    /// 同一個位移。
    func openLog(path: String) {
        logPath = path
        if let h = Platform.openForAppend(path: path) {
            logHandle = h
        } else {
            warnLogUnavailable()
        }
    }

    private func warnLogUnavailable() {
        guard !logWarned else { return }
        logWarned = true
        // Failing to write the log must NOT fail the operation. The reverse
        // design turns a purely observational feature into a new source of
        // failure.
        // 寫 log 失敗不得使操作失敗。反過來的設計會讓一個純粹的觀測功能
        // 變成一個新的失敗來源。
        // Same shape as every other WARN, so a script parsing the documented
        // grammar does not miss it; it accompanies an rc=0 run, so a
        // mis-parse means missing it entirely.
        //
        // It cannot go through `Logger.warn` directly: that writes to the log
        // file too, and the log file is precisely what has just failed. So the
        // line is built in the same shape and sent only to stderr.
        //
        // 與其他每一則 WARN 同形狀，照文件文法剖析的腳本才不會漏掉它；它伴隨的是 rc=0 的
        // 執行，剖析錯就等於完全錯過。
        //
        // 它不能直接走 `Logger.warn`：那會同時寫進 log 檔，而剛剛失敗的正是那個 log 檔。
        // 因此這一行以相同的形狀組出來，只送到 stderr。
        Platform.writeStderr(
            "csv2: \(Logger.timestamp()) WARN  cannot write log file \(logPath ?? "?"); continuing without one\n")
    }

    /// `message` is an @autoclosure, and the level test happens BEFORE anything
    /// is built. Building the line first and deciding afterwards makes a
    /// suppressed TRACE line cost two string constructions per record; on a
    /// 2,000,000-record stream that shows up as peak RSS growing with the
    /// record count.
    /// `message` 是 @autoclosure，而層級判斷發生在「建構任何東西之前」。若先組出整行再
    /// 判斷，一行被抑制的 TRACE 每筆仍要付兩次字串建構；在 2,000,000 筆的串流上，這會
    /// 表現為 peak RSS 隨紀錄數增長。
    func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        let belongsInFile = level >= .info || threshold <= .debug
        let wantsFile = belongsInFile && (logHandle != nil || logPath != nil)
        if !wantsFile && level < threshold { return }
        // One entry is one line, and the message is escaped to keep it that
        // way: any message interpolating input -- a column name, a path, a
        // field -- could otherwise open a second log line whose whole content,
        // timestamp included, came from that input. Escaping where the line is
        // built covers every message, including ones added later, instead of a
        // rule each call site has to remember.
        // 一筆是一行，而訊息會被跳脫以維持這一點：否則任何插入輸入的訊息——欄名、路徑、
        // 欄位——都可能在 log 中開出第二行，整行內容連同時間戳都來自那個輸入。在「建行」
        // 這一點跳脫，涵蓋現在與日後的每一則訊息，而不是一條每個呼叫點都得各自記得的規則。
        let line = "\(Logger.timestamp()) \(level.label) \(lineEscape(message()))\n"
        // The log FILE is an operation record: what was done, to what, with
        // what result. DEBUG and TRACE are for someone chasing a problem right
        // now -- high volume, thrown away when done -- and letting them into
        // the file drowns the history in the debugging, which is the exact
        // reason -debug and -log are two flags and not one. They reach the file
        // only when -debug asked for them.
        // log「檔案」是操作紀錄：做了什麼、對什麼、結果如何。DEBUG 與 TRACE 是給
        // 「現在正在查一個問題」的人看的——量大、用完即棄——讓它們進入檔案會把歷史
        // 淹沒在除錯輸出裡，而那正是 -debug 與 -log 是兩個旗標而不是一個的理由。
        // 只有在 -debug 明確要求時，它們才會進入檔案。
        if let h = logHandle, belongsInFile {
            Platform.appendWrite(h, Data(line.utf8))
        } else if logPath != nil && belongsInFile {
            warnLogUnavailable()
        }
        if level >= threshold {
            // Diagnostics go to stderr, never stdout: with `-so` the output
            // IS the CSV, and a timestamp in the middle of it is corruption.
            // 診斷訊息走 stderr，絕不走 stdout：使用 `-so` 時輸出就是 CSV，
            // 在其中插入時間戳就是損毀。
            //
            // A WARNING is a message to the person running the command, and it
            // is written the way every other one is: `csv2: <text>`, without
            // the log file's timestamp and level, so all warnings share one
            // shape whether or not -log was given. OA.
            //
            // DEBUG and TRACE keep the timestamp: they exist for someone
            // watching a run happen, where the ordering and the gaps are the
            // information.
            //
            // 一則**警告**是說給「正在下這個指令的人」聽的，因此它的寫法與其他每一則相同：
            // `csv2: <文字>`，不帶 log 檔那一行的時間戳與等級，於是不論有沒有給 -log，所有
            // 警告都是同一種形狀。OA。
            //
            // DEBUG 與 TRACE 保留時間戳：它們是給「正在看一次執行發生」的人用的，而那裡
            // 順序與間隔本身就是資訊。
            if level == .warn {
                Platform.writeStderr("csv2: \(lineEscape(message()))\n")
            } else {
                Platform.writeStderr("csv2: \(line)")
            }
        }
    }

    /// For a failure the caller has already printed. It belongs in the log file
    /// -- that is the record someone reads later -- but printing it again on
    /// stderr just duplicates it.
    /// 給「呼叫端已經印過」的失敗使用。它該進 log 檔——那是日後有人會讀的紀錄——
    /// 但再往 stderr 印一次只是重複。
    func logToFileOnly(_ level: LogLevel, _ message: String) {
        guard let h = logHandle else { return }
        Platform.appendWrite(h, Data("\(Logger.timestamp()) \(level.label) \(lineEscape(message))\n".utf8))
    }

    func debug(_ m: @autoclosure () -> String) { log(.debug, m()) }
    func info(_ m: @autoclosure () -> String) { log(.info, m()) }
    func warn(_ m: @autoclosure () -> String) { log(.warn, m()) }

    /// A value that belongs to an encrypted or hashed column never appears in
    /// the log. Otherwise `-update` on a protected column writes the plaintext
    /// into a file nobody is guarding.
    /// 屬於加密或雜湊欄位的值絕不出現在 log 中。否則對受保護欄位的 `-update`
    /// 會把明文寫進一個沒有人在保護的檔案。
    /// NOT truncated, and NOT escaped here. The escaping is load-bearing --
    /// the log is one entry per line, and an unescaped newline in a value
    /// would forge a whole entry, timestamp included, at rc=0 -- but it
    /// happens once, where the log line is built. Escaping again here would
    /// turn a newline into `\\n`, a value that no longer round-trips.
    /// Truncation never prevented the forgery, only shortened it, so there is
    /// no limit as long as the escaping stays in `log`.
    /// **不截斷**，而且此處**不跳脫**。跳脫是承重的——log 是一行一筆，值裡未跳脫的換行
    /// 會以 rc=0 偽造出一整筆紀錄，連時間戳都由值決定——但跳脫只在建構 log 行的地方做一次。
    /// 在這裡再跳脫會讓換行變成 `\\n`，值就還原不回去了。截斷從來擋不住偽造，只是把它
    /// 剪短，因此只要跳脫留在 `log` 裡，就不設長度上限。
    /// A `"` inside the value is doubled, because `"` is what delimits the
    /// value. Without that, `-update` with `INNOCENT" -> "ALSO INNOCENT`
    /// writes `update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"`
    /// -- one entry whose old and new halves no parser can separate.
    ///
    /// Doubling rather than backslashing: it is the convention `.csv2` and
    /// RFC 4180 already use, and it carries no backslash, so the whole-line
    /// escape in `log` leaves it untouched -- a `\"` would have its backslash
    /// doubled on the way out.
    ///
    /// 值裡的 `"` 會被寫成兩個，因為 `"` 正是用來界定這個值的字元。沒有這一步，
    /// 對 `INNOCENT" -> "ALSO INNOCENT` 做 `-update` 會寫出
    /// `update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"`——一筆紀錄，
    /// 而沒有任何剖析器分得出哪一半是舊值、哪一半是新值。
    ///
    /// 用「加倍」而非「反斜線」：那是 `.csv2` 與 RFC 4180 已經在用的慣例；而且它不含反斜線，
    /// `log` 裡那道整行跳脫不會碰它——若寫成 `\"`，它的反斜線會在輸出時被加倍。
    /// A column NAME as a log entry can carry it: escaped and quoted the same
    /// way a value is. `delete record 1: a,b="1"` -- a real name with a comma
    /// in it -- reads as three fields and cannot be parsed back; the file
    /// format this tool exists for allows that name, and the README explains
    /// how to address it.
    /// 一個「log 紀錄載得動」的欄位名稱：與值以同一種方式跳脫並加引號。
    /// `delete record 1: a,b="1"`——一個名字裡真的有逗號的欄位——讀起來像三個欄位，
    /// 解析不回去；而這支工具為之存在的那個檔案格式允許這種名字，README 也講了怎麼定址它。
    func nameForLog(_ name: String) -> String {
        "\"\(reportEscape(name).replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func redact(column: String, value: [UInt8]) -> String {
        if redactedColumns.contains(column) { return "<redacted>" }
        let v = reportEscape(echoValue(value, limit: nil))
            .replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(v)\""
    }

    /// Whether a value about to be logged is large enough that the person
    /// running this should be told. Returns false for a redacted column,
    /// because nothing of it reaches the log to be large.
    /// 一個即將被記錄的值是否大到「執行這件事的人應該被告知」。受保護欄位回傳 false，
    /// 因為它不會有任何內容進入 log，也就談不上大。
    func logValueIsLarge(column: String, value: [UInt8]) -> Bool {
        !redactedColumns.contains(column) && value.count > LOG_VALUE_WARN_BYTES
    }

    func close() { try? logHandle?.close() }
}

// ---------------------------------------------------------------------
// MARK: - Keys / 金鑰
// ---------------------------------------------------------------------

enum KeySource {
    /// $HOME first, NSHomeDirectory() only as a fallback. Foundation's tilde
    /// expansion goes to the password database on Darwin and ignores $HOME
    /// entirely, which makes "what happens when the key is missing" untestable
    /// -- the test would silently pick up the real key and pass by accident.
    /// 先看 $HOME，NSHomeDirectory() 只作為後援。Foundation 在 Darwin 上的
    /// 波浪號展開會查 password database、完全忽略 $HOME，那會讓「金鑰不存在時
    /// 會怎樣」無法測試——測試會靜默地取到真正的金鑰，然後意外地通過。
    static let defaultPath: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return home + "/.multissh/generated/mldsa44-ed25519.key.raw"
    }()

    /// Domain separation. The multissh key is a SIGNATURE key; using one
    /// secret for two purposes is explicitly discouraged in cryptography.
    /// Folding a fixed label into the salt makes the derived key
    /// mathematically unrelated to any signing operation with the same input.
    /// 網域分離。multissh 的金鑰是簽章金鑰；把同一份秘密用於兩種用途，是密碼學
    /// 上明確不建議的事。把固定標籤併入 salt，使推導出的金鑰與任何以相同輸入
    /// 進行的簽章運算在數學上無關。
    static let domainLabel = "csv2-column-encryption-v1"
    static let iterations = 200_000

    /// The floor on key material, in bytes, when a file's protection is being
    /// CREATED.
    ///
    /// 16 is where brute force stops being a rounding error. It is not a
    /// strength test -- a 16-byte English phrase is weak and passes -- it is a
    /// floor under the case that has no defence at all.
    /// 建立保護時，金鑰材料的位元組下限。16 是「窮舉不再是零頭」的那個點。它不是強度檢定
    /// ——一句 16 bytes 的英文短語很弱，而且會通過——它是給「完全沒有防禦的那種情況」一個底。
    static let minimumKeyBytes = 16

    /// `forCreating` decides whether a weak key is refused, and the asymmetry
    /// is the whole design.
    ///
    /// `-encrypt` and keyed `-hash` are producing a file that has to protect
    /// something afterwards; that is the moment to insist. `-decrypt` is
    /// reading a file that already exists, and applying the same floor there
    /// would make a file made with a weak key permanently unreadable --
    /// losing data for a security reason, which is the worse trade.
    ///
    /// Without a floor, a one-byte keyfile is accepted silently and the column
    /// it protects is recovered in at most 256 tries.
    ///
    /// `forCreating` 決定「弱金鑰要不要被拒絕」，而那個不對稱正是整個設計。
    ///
    /// `-encrypt` 與帶金鑰的 `-hash` 是在產生一個「日後要靠它保護某些東西」的檔案，那是
    /// 該堅持的時刻。`-decrypt` 面對的是「已經存在的檔案」，在那裡套用同一個下限，會讓一份
    /// 用弱金鑰做出來的檔案再也讀不回來——**以安全為由造成資料無法取回，那是更糟的交換。**
    ///
    /// 沒有下限時，1 byte 的金鑰檔會被靜默接受，它保護的整欄在 256 次以內就能被復原。
    static func loadKeyMaterial(path: String?, assumeYes: Bool,
                                forCreating: Bool = false) throws -> (bytes: [UInt8], path: String) {
        let p = path ?? defaultPath
        guard FileManager.default.fileExists(atPath: p) else {
            if path == nil {
                throw fault(
                    "no key at \(p); csv2 does not generate one or fall back to another file, because a fallback produces a file that decrypts with a key you did not mean to use. Create it with: release/mssh-keygen -o ~/.multissh/generated",
                    "找不到金鑰 \(p)；csv2 不會自行產生，也不會改用其他檔案——任何後援都會產生一個「能解密、但不是你以為的那把金鑰」的檔案。請執行：release/mssh-keygen -o ~/.multissh/generated")
            }
            throw fault("keyfile not found: \(p)", "找不到金鑰檔：\(p)")
        }
        // A directory, an unreadable file and an empty file each get their own
        // message. Pointing -keyfile at a DIRECTORY is an easy slip -- the key
        // lives in one -- and "empty or unreadable" would send the reader to
        // look inside something that is not a file.
        // 目錄、讀不到的檔案、空檔案各有各的訊息。把 -keyfile 指到「目錄」是很容易的失手——
        // 金鑰就住在某個目錄裡——而一句「為空或無法讀取」會把讀者送去檢查一個根本不是檔案的東西。
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
        if isDir.boolValue {
            throw fault("keyfile is a directory: \(p); name the key file inside it",
                        "金鑰檔是一個目錄：\(p)；請指名它裡面的那個金鑰檔")
        }
        guard let d = FileManager.default.contents(atPath: p) else {
            let e = Platform.errorText(errno)
            throw fault("cannot read keyfile \(p): \(e)", "無法讀取金鑰檔 \(p)：\(e)")
        }
        guard !d.isEmpty else {
            throw fault("keyfile is empty: \(p)", "金鑰檔是空的：\(p)")
        }
        let bytes = [UInt8](d)

        // A key of one byte repeated is guessed on the first attempt whatever
        // its length, so the length floor alone would accept 16 NUL bytes --
        // what a truncated or never-written key file looks like -- while
        // refusing 15 random bytes that are far stronger.
        //
        // Only the shapes that are certainly not keys are refused. csv2 does
        // not estimate entropy -- that is a judgement, and a judgement that
        // refuses a caller's real key is worse than one that accepts a poor
        // one -- but a file with one distinct byte in it is not a judgement.
        // 一把「同一個位元組重複而成」的金鑰，不論多長都會在第一次嘗試就被猜中，因此光靠長度
        // 下限會接受 16 個 NUL——被截斷或從未寫入的金鑰檔就是這個樣子——卻拒絕強得多的
        // 15 個隨機位元組。
        //
        // 只拒絕「確定不是金鑰」的形狀。csv2 不估算熵——那是一種判斷，而一個「把呼叫端真正的
        // 金鑰擋下來」的判斷，比一個「接受了一把差金鑰」的判斷更糟——但「整個檔案只有一種
        // 位元組」不是判斷。
        if forCreating, bytes.count >= minimumKeyBytes, Set(bytes).count == 1 {
            throw fault(
                "keyfile \(p) is \(bytes.count) copies of one byte, which is guessed on the first attempt however long it is; csv2 will not create protection from it. Make one with: head -c 32 /dev/urandom > key.bin",
                "金鑰檔 \(p) 是同一個位元組重複 \(bytes.count) 次，不論多長都會在第一次嘗試就被猜中；csv2 不會用它建立保護。請這樣產生一把：head -c 32 /dev/urandom > key.bin")
        }
        if forCreating && bytes.count < minimumKeyBytes {
            throw fault(
                "keyfile \(p) holds \(bytes.count) byte(s); csv2 will not create protection from fewer than \(minimumKeyBytes). A key this short is searched exhaustively in less time than this run took, and the file it produces looks encrypted. Make one with: head -c 32 /dev/urandom > key.bin. Reading a file that was already made with a short key is NOT refused -- only making a new one is",
                "金鑰檔 \(p) 只有 \(bytes.count) 個位元組；csv2 不會用少於 \(minimumKeyBytes) 個位元組的金鑰去建立保護。這麼短的金鑰，窮舉所需的時間比這次執行還短，而它產生的檔案看起來是加密過的。請這樣產生一把：head -c 32 /dev/urandom > key.bin。讀取「已經用短金鑰做出來的檔案」不會被拒絕——被拒絕的只有「產生新的」")
        }

        if path == nil {
            // Which key was used decides whether this file can ever be read
            // again, and the default is something the user did not type.
            // Taking it silently puts the single most important decision
            // off-screen.
            // 「用了哪一把金鑰」決定這個檔案日後還能不能讀，而預設值是使用者
            // 沒有打出來的東西。沉默地採用它，等於讓最重要的一項決定發生在
            // 畫面之外。
            if assumeYes {
                Logger.shared.info("using the default multissh key at \(p) (--yes)")
            } else {
                guard Platform.isTerminal(Platform.stdinFD) && Platform.isTerminal(Platform.stderrFD) else {
                    // A prompt that cannot be displayed must NEVER be treated
                    // as a yes; otherwise scripts and cron jobs silently adopt
                    // the default key, which is the exact thing the prompt is
                    // there to prevent.
                    // 無法顯示的提示絕不可視為「是」——否則腳本與排程工作會靜默
                    // 採用預設金鑰，而提示的用意正是不讓這件事靜默發生。
                    throw fault(
                        "no -keyfile given and no tty to ask on; pass -keyfile explicitly, or --yes to accept the default multissh key at \(p)",
                        "未指定 -keyfile 且沒有可詢問的 tty；請明確給 -keyfile，或以 --yes 表示已知悉將使用預設的 multissh 金鑰 \(p)")
                }
                let fp = fingerprint(derive(material: bytes, salt: [UInt8](domainLabel.utf8)))
                Platform.writeStderr("""
                warning: no -keyfile given; the multissh private key will be used / 警告：未指定 -keyfile，將使用 multissh 的私鑰
                  \(p)  (fingerprint \(fp))
                if that key is regenerated or lost, this file can never be decrypted / 若此金鑰被重新產生或遺失，本檔案將永久無法解密
                continue? [y/N] / 繼續？[y/N]
                """)
                let answer = readLine(strippingNewline: true)?.lowercased() ?? ""
                guard answer == "y" || answer == "yes" else {
                    throw fault("aborted at the key prompt", "已於金鑰確認處中止")
                }
            }
        }
        return (bytes, p)
    }

    static func derive(material: [UInt8], salt: [UInt8]) -> [UInt8] {
        // PBKDF2 has no `info` parameter, so the domain label is prefixed to
        // the salt. Same effect: a different label yields an unrelated key.
        // PBKDF2 沒有 `info` 參數，因此把網域標籤前置於 salt。效果相同：
        // 不同標籤得到互不相關的金鑰。
        var s = [UInt8](domainLabel.utf8)
        s.append(contentsOf: salt)
        return PBKDF2.derive(password: material, salt: s, iterations: iterations, length: 32)
    }

    /// The first 4 bytes of SHA-256 over the DERIVED key. A public value; it
    /// leaks nothing about the key. It cannot stop `mssh-keygen` from making a
    /// new key and stranding every previously encrypted CSV -- but it turns
    /// that from a Poly1305 authentication failure (which reads like file
    /// corruption and sends you the wrong way) into a message that says so.
    /// 取推導後金鑰 SHA-256 的前 4 bytes。這是公開值，不洩漏金鑰。它擋不住
    /// 「mssh-keygen 重新產生金鑰、於是先前加密的 CSV 全數無法解密」，但能讓
    /// 那件事從一個看起來像檔案損毀的 Poly1305 認證失敗，變成一句說清楚的話。
    static func fingerprint(_ derivedKey: [UInt8]) -> String {
        SHA256.hash(derivedKey).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

// ---------------------------------------------------------------------
// MARK: - Base64 without Foundation's Data round-trip / 精簡 base64
// ---------------------------------------------------------------------

enum B64 {
    static func encode(_ bytes: [UInt8]) -> String { Data(bytes).base64EncodedString() }
    static func decode(_ s: String) -> [UInt8]? {
        guard let d = Data(base64Encoded: s) else { return nil }
        return [UInt8](d)
    }
}

// ---------------------------------------------------------------------
// MARK: - JSON / JSON 輸出
// ---------------------------------------------------------------------

enum JSONOut {
    /// Emoji go out as raw UTF-8: that is valid JSON and shorter than the
    /// `😀` surrogate pair. Only the control characters JSON
    /// actually requires are escaped.
    /// emoji 以原始 UTF-8 寫出：那是合法的 JSON，也比 `😀` 的代理對短。
    /// 只跳脫 JSON 真正要求的控制字元。
    /// Whether these bytes can go into JSON without being changed.
    ///
    /// JSON is defined over text, so bytes that are not valid UTF-8 cannot be
    /// carried at all -- `String(decoding:as:)` substitutes U+FFFD, which is
    /// data loss that looks like success. The caller refuses instead, because
    /// `--json` is the shape this README recommends when the value matters,
    /// and the locating report already answers this case honestly with
    /// `<non-UTF-8: 63 61 66 e9>`.
    /// 這些位元組能不能原樣進到 JSON 裡。
    /// JSON 是定義在「文字」上的，因此不是合法 UTF-8 的位元組根本載不進去——
    /// `String(decoding:as:)` 會換成 U+FFFD，那是一種「看起來成功」的資料遺失。呼叫端因此
    /// 改為拒絕，因為 `--json` 正是這份 README 在「值很重要」時推薦的那個形狀，而定位報告
    /// 早就以 `<non-UTF-8: 63 61 66 e9>` 誠實地回答了這個情況。
    static func canCarry(_ bytes: [UInt8]) -> Bool {
        String(bytes: bytes, encoding: .utf8) != nil
    }

    static func string(_ bytes: [UInt8], asciiOnly: Bool) -> String {
        let s = String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else if asciiOnly && ch.value > 0x7E {
                    if ch.value > 0xFFFF {
                        let v = ch.value - 0x10000
                        out += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                    } else {
                        out += String(format: "\\u%04x", ch.value)
                    }
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }
}

// ---------------------------------------------------------------------
// MARK: - Markdown / Markdown 輸出
// ---------------------------------------------------------------------

enum MarkdownOut {
    /// A `|` inside a cell splits the table; an embedded newline splits the
    /// row. Both must be escaped. This is the SAME class of error as naive
    /// comma splitting: the output still looks like a table and the renderer
    /// does not complain, the fields have just moved to other columns.
    /// 儲存格內的 `|` 會把表格切開，內嵌換行會把一列拆成兩列，兩者都必須跳脫。
    /// 這與天真的逗號切割是同一類錯誤：輸出看起來像表格、renderer 也不會抱怨，
    /// 只是欄位跑到別欄去了。
    /// The control characters go too, as `\xNN`, for the reason the locating
    /// report already gives: `-md` is a RENDERING, read by a person, and a
    /// control character is not text on a terminal.
    ///
    /// Unescaped, a licence column holding
    /// `GPL-3.0<BS><BS><BS><BS><BS><BS><BS>MIT` renders as `MIT` on any
    /// terminal that moves the cursor for a backspace, at rc=0, while `-get`
    /// returns the real bytes. `--pretty` only happens to expose that payload
    /// through column width, which is alignment, not a defence.
    ///
    /// 控制字元也要跳脫，寫成 `\xNN`，理由與定位報告已經給過的相同：`-md` 是一種「算繪」，
    /// 給人讀的，而控制字元在終端機上不是文字。
    ///
    /// 不跳脫的話，一個存著 `GPL-3.0<BS><BS><BS><BS><BS><BS><BS>MIT` 的授權欄位，在任何
    /// 「退格會移動游標」的終端機上會算繪成 `MIT`，rc=0，而 `-get` 交還的仍是真正的位元組。
    /// `--pretty` 只是碰巧因欄寬而讓這個 payload 露餡，那是對齊的意外，不是防線。
    static func cell(_ bytes: [UInt8]) -> String {
        var s = String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "|", with: "\\|")
        // A literal `<br>` in a VALUE, escaped before the newlines become one.
        //
        // `<br>` joins the two header rows and stands for an embedded newline,
        // so a value that literally contains `<br>` must be escaped or
        // `two\nlines` and `lit<br>eral` render identically and cannot be told
        // apart when read back (phase 8a).
        //
        // The order is the whole trick: backslashes are already doubled by the
        // line above, so the backslash introduced here cannot be mistaken for
        // one that was in the data, and the newline replacements below are the
        // only thing left that produces an UNESCAPED `<br>`.
        //
        // 值裡的字面 `<br>`，在換行變成 `<br>` 之前先跳脫。
        // `<br>` 用來接起兩列標頭、也代表內嵌換行，因此值裡字面的 `<br>` 必須跳脫，否則
        // `two\nlines` 與 `lit<br>eral` 會算繪成同一個樣子，讀回來時分不出來（第 8a 階段）。
        // 順序就是全部的訣竅：上一行已經把反斜線加倍了，因此這裡引入的那個反斜線不會被誤認為
        // 資料裡本來就有的；而下面那幾行換行替換，是唯一還會產生「未跳脫的 `<br>`」的東西。
        s = s.replacingOccurrences(of: "<br>", with: "\\<br>")
        // Only LF becomes `<br>`. A CR is a control byte and goes through the
        // loop below as `\x0D`, which is what this function's own documented
        // rule says -- "a TAB as \t, everything else below 0x20 and DEL as
        // \xNN".
        //
        // Turning CR into `<br>` too would read `a\rb` back as `a\nb`, and a
        // CRLF as a single LF, breaking the byte-identical round trip. Writing
        // CR as `\x0D` makes a CRLF `\x0D<br>`, which survives. Round 78.
        //
        // 只有 LF 會變成 `<br>`。CR 是一個控制位元組，會走下面那個迴圈成為 `\x0D`——那正是這個
        // 函式自己那條有記載的規則所說的（「TAB 是 \t，其餘 0x20 以下與 DEL 是 \xNN」）。
        // 若 CR 也變成 `<br>`，`a\rb` 讀回來會是 `a\nb`、CRLF 會變成單一個 LF，打破逐位元相同的
        // 往返。把 CR 寫成 `\x0D`，CRLF 就成了 `\x0D<br>`，可以完整還原。第 78 回合。
        s = s.replacingOccurrences(of: "\n", with: "<br>")
        var out = ""
        out.reserveCapacity(s.count)
        for u in s.unicodeScalars {
            // A tab is `\t` here because it is `\t` in the locating report,
            // and two shapes of this tool spelling the same byte two ways is
            // the drift everything else in this file argues against.
            // TAB 在這裡寫成 `\t`，因為它在定位報告裡就是 `\t`；這個工具的兩種形狀
            // 把同一個位元組拼成兩種樣子，正是這個檔案其他部分一直在反對的那種漂移。
            if u == "\t" {
                out += "\\t"
            } else if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02X", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
        // A leading or trailing space, escaped, because padding is the one
        // thing a reader cannot tell from data.
        //
        // `-md` writes a value's own edge spaces straight into the cell, and
        // `--pretty` pads every cell to the column width with the same
        // character. `|  padded  |` is therefore either a value with two
        // spaces each side, or a short value in a wide column, and nothing in
        // the line says which. Stripping on the way back loses real data;
        // not stripping makes --pretty unreadable. Escaping is what lets BOTH
        // round-trip, and it costs the document nothing except on the values
        // that actually have edge spaces.
        //
        // `\x20` rather than a new spelling: this function already writes
        // `\xNN` for control bytes, and a second escape convention inside one
        // format is the drift the comment above argues against.
        //
        // 開頭或結尾的空白要跳脫，因為「補白」正是讀取端唯一分不出來的那個東西。
        // `-md` 會把一個值自己的邊緣空白直接寫進儲存格，而 `--pretty` 用同一個字元把每一格補到
        // 欄寬。於是 `|  padded  |` 要嘛是「前後各兩個空白的值」，要嘛是「一個短值落在寬欄位裡」，
        // 而那一行裡沒有任何東西說是哪一種。讀回來時把它剝掉會丟失真實資料；不剝掉則會讓
        // --pretty 讀不回來。跳脫才是讓「兩者都能 round-trip」的做法，而它對文件的代價，只出現在
        // 那些真的有邊緣空白的值上。
        // 用 `\x20` 而不是發明新寫法：這個函式本來就為控制位元組寫 `\xNN`，而在一個格式裡有第二套
        // 跳脫慣例，正是上面那則註解一直在反對的漂移。
        if out.hasPrefix(" ") { out = "\\x20" + out.dropFirst() }
        if out.hasSuffix(" ") { out = out.dropLast() + "\\x20" }
        // RV. A cell made only of `-` and `:` (with at least one `-`) is what a
        // separator cell looks like, and the reader takes a row of them as a
        // new table's separator, which turns the row above into a header. The
        // first character goes out as `\x2D` / `\x3A`, which reads back as the
        // same byte and no longer looks like a separator.
        // RV。只由 `-` 與 `:` 組成（至少一個 `-`）的儲存格，正是分隔線儲存格的樣子，而讀取端會把
        // 一整列這樣的格子當成新表的分隔線，讓上一列變成標頭。第一個字元改寫成 `\x2D`／`\x3A`，讀回
        // 來是同一個位元組，而且不再像分隔線。
        let body = out.trimmingCharacters(in: .whitespaces)
        if body.contains("-"), body.allSatisfy({ $0 == "-" || $0 == ":" }),
           let first = out.firstIndex(where: { $0 == "-" || $0 == ":" }) {
            let esc = out[first] == "-" ? "\\x2D" : "\\x3A"
            out.replaceSubrange(first...first, with: esc)
        }
        return out
    }
}

// ---------------------------------------------------------------------
// MARK: - Metrics / 量測
// ---------------------------------------------------------------------

/// Reported under `-debug` so the streaming guarantees can be ASSERTED rather
/// than asserted-by-comment. "It is written as a ring buffer" is not evidence
/// that memory stays bounded, and "it stops early" is not evidence that no
/// bytes past record b were read; without these numbers both tests could only
/// SKIP.
/// 在 `-debug` 下回報，讓串流保證可以被「斷言」而不是「以註解宣稱」。
/// 「它是以環狀緩衝寫的」不構成記憶體有上界的證據，「它會提前停止」也不構成
/// 「沒有讀取 b 之後任何位元組」的證據；沒有這些數字，兩項測試都只能 SKIP。
enum Metrics {
    /// Peak resident set size in bytes. ru_maxrss is BYTES on Darwin and
    /// KILOBYTES on Linux -- the same field with two units, which is exactly
    /// the kind of difference that only shows up when the guest runs it.
    /// 峰值常駐記憶體，單位為位元組。ru_maxrss 在 Darwin 上是 bytes、在 Linux
    /// 上是 KB——同一個欄位兩種單位，正是那種「只有在 guest 上跑才會現形」的差異。
    static func peakRSSBytes() -> Int { Platform.peakRSSBytes() }

    /// One line, at DEBUG, in a shape a test can parse without guessing.
    /// 一行，DEBUG 層級，格式讓測試不必猜就能解析。
    static func report(bytesRead: Int, fileSize: Int) {
        // The RSS figure is labelled when it comes from an unverified path, so
        // a reader is never handed a number that looks measured but is not.
        // RSS 數值在來自未經驗證的路徑時會被標示，讓讀者不會拿到一個「看起來像
        // 量測、其實不是」的數字。
        let rssNote = Platform.peakRSSIsVerified ? "" : " peak_rss_unverified_on=\(Platform.name)"
        Logger.shared.debug("metrics: read_bytes=\(bytesRead) file_bytes=\(fileSize) peak_rss_bytes=\(peakRSSBytes())\(rssNote)")
    }
}

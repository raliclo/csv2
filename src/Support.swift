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
final class Logger {
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
    /// This used to open for writing and `seekToEndOfFile()`, which is that
    /// intention expressed as a seek that happens ONCE. With one process the
    /// two are indistinguishable. With two they are not: the second writer
    /// lands on the offset the first recorded at open and overwrites it.
    /// Eight processes each logging 25 operations left 98 entries of 200 --
    /// none malformed, every run exiting 0. `Platform.openForAppend` puts the
    /// append in the kernel, where a concurrent writer cannot be raced.
    /// 一律追加，絕不覆寫：覆寫會讓這個檔案唯一的用途（日後回頭查）失效。
    /// 原本的寫法是「以寫入開啟後 seekToEndOfFile()」——也就是把上面那個意圖表達成一次
    /// 「只發生一次」的 seek。單一行程下兩者無法區分；兩個行程下就不是了：後來的寫入者會
    /// 落在前一個在開檔時記下的位移上並蓋掉它。八個行程各記錄 25 次操作，200 筆只剩 98 筆
    /// ——沒有一筆是壞的，每一次都以 0 結束。`Platform.openForAppend` 把追加交給核心，
    /// 並行的寫入者在那裡搶不到同一個位移。
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
        FileHandle.standardError.write(Data(
            "csv2: warning: cannot write log file \(logPath ?? "?"); continuing / 警告：無法寫入 log 檔，操作照常繼續\n".utf8))
    }

    /// `message` is an @autoclosure, and the level test happens BEFORE anything
    /// is built. It used to compose the timestamp and the whole line first and
    /// decide afterwards, while the caller had already paid for its own
    /// interpolation -- so a TRACE line on a run with the default WARN
    /// threshold cost two string constructions per record and produced no
    /// output at all. On a 2,000,000-record stream that was measurable as peak
    /// RSS: 123 MB, against 15.9 MB for the same bytes in 100,000 records.
    /// Discovered on 2026-08-19 while chasing the streaming memory claim; the
    /// per-RECORD shape is what identified it, since the same byte volume in
    /// fewer records did not grow.
    /// `message` 是 @autoclosure，而層級判斷發生在「建構任何東西之前」。原本的寫法是
    /// 先組出時間戳與整行、之後才判斷，而呼叫端在此之前早已付過自己那次字串插值——因此
    /// 在預設 WARN 門檻下，一行 TRACE 每筆要付兩次字串建構，而且完全不產生輸出。
    /// 在 2,000,000 筆的串流上這是量得到的：peak RSS 123 MB，而同樣的位元組量分成
    /// 100,000 筆時是 15.9 MB。2026-08-19 追查串流記憶體宣稱時發現；認出它的是那個
    /// 「隨紀錄數而非隨位元組數」的形狀。
    func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        let belongsInFile = level >= .info || threshold <= .debug
        let wantsFile = belongsInFile && (logHandle != nil || logPath != nil)
        if !wantsFile && level < threshold { return }
        // One entry is one line, and the message is escaped to keep it that
        // way. The rule was already documented and already applied to logged
        // VALUES; it was not applied here, so any message interpolating input
        // -- a column name, a path, a field -- could open a second line in the
        // log whose whole content, timestamp included, came from that input.
        // Escaping at the point the line is built covers every message that
        // exists and every one added later, which is the difference that
        // matters: the two call sites this defect reached were both cases of
        // a rule that had to be remembered separately in each place.
        // 一筆是一行，而訊息會被跳脫以維持這一點。這條規則本來就寫在文件裡，也已經套用在
        // 記入 log 的「值」上；只是沒有套到這裡，於是任何把輸入插進去的訊息——欄名、路徑、
        // 欄位——都可能在 log 中開出第二行，而那一行的全部內容連同時間戳都來自那個輸入。
        // 在「建行」這一點跳脫，涵蓋的是現在與日後的每一則訊息，而那正是關鍵差別：這個
        // 缺陷所到過的兩個呼叫點，都是「一條規則必須在每個地方各被記得一次」的例子。
        let line = "\(Logger.timestamp()) \(level.label) \(reportEscape(message()))\n"
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
            FileHandle.standardError.write(Data("csv2: \(line)".utf8))
        }
    }

    /// For a failure the caller has already printed. It belongs in the log file
    /// -- that is the record someone reads later -- but printing it again on
    /// stderr just duplicates it.
    /// 給「呼叫端已經印過」的失敗使用。它該進 log 檔——那是日後有人會讀的紀錄——
    /// 但再往 stderr 印一次只是重複。
    func logToFileOnly(_ level: LogLevel, _ message: String) {
        guard let h = logHandle else { return }
        Platform.appendWrite(h, Data("\(Logger.timestamp()) \(level.label) \(reportEscape(message))\n".utf8))
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
    /// the log is one entry per line, and writing a value with quotes and
    /// nothing else let a newline inside it open a new line whose entire
    /// content the value chose, a forged entry with an attacker-picked
    /// timestamp at rc=0 -- but it now happens once, where the log line is
    /// built, so it also covers the invocation and every message. Escaping
    /// again here produced `\\n` for a newline: a value that no longer
    /// round-trips, arrived at by two fixes each of which was right alone.
    /// The 40-character truncation never prevented the forgery, it only
    /// shortened the forged line, which is why lifting the limit had to wait
    /// for the escaping: otherwise the forgery would have gone from truncated
    /// to complete.
    /// **不截斷**，而且此處**不跳脫**。跳脫是承重的那一半——log 是一行一筆，而只把值加上
    /// 引號、別的什麼都不做，會讓值裡的一個換行開啟新的一行，那一行的全部內容由值決定，
    /// 是一筆時間戳由攻擊者挑選、以 rc=0 落進稽核軌跡的偽造紀錄——但它現在只發生一次，
    /// 在建構 log 行的地方，因此同時涵蓋了「呼叫」與每一則訊息。在這裡再跳脫一次會讓換行
    /// 變成 `\\n`：一個再也還原不回去的值，而它來自兩個各自都正確的修正。40 字元的截斷
    /// 從來擋不住那個偽造，它只是把偽造的那一行剪短——這正是「解除上限」必須等「跳脫」先做
    /// 的原因：否則偽造會從被剪斷變成完整。
    /// A `"` inside the value is doubled, because `"` is what delimits the
    /// value. Without that, `-update` with `INNOCENT" -> "ALSO INNOCENT` wrote
    /// `update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"` -- one
    /// line, one entry, correct data on disk, and no parser can recover which
    /// half is old and which is new. Whole-line forgery was already blocked;
    /// this is forgery of an entry's CONTENT, inside an otherwise legitimate
    /// entry.
    ///
    /// Doubling rather than backslashing, for two reasons. It is the
    /// convention `.csv2` and RFC 4180 already use, so a reader who knows the
    /// format needs nothing new. And it carries no backslash, so the
    /// whole-line escape in `log` leaves it untouched -- a `\"` would have had
    /// its backslash doubled on the way out, which is the two-layer escaping
    /// that made the first attempt at this wrong.
    ///
    /// 值裡的 `"` 會被寫成兩個，因為 `"` 正是用來界定這個值的字元。沒有這一步，
    /// 對 `INNOCENT" -> "ALSO INNOCENT` 做 `-update` 會寫出
    /// `update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"`——一行、一筆、
    /// 磁碟上的資料也正確，而沒有任何剖析器分得出哪一半是舊值、哪一半是新值。整行的偽造
    /// 早已擋掉；這是在一筆本身合法的紀錄「內部」偽造它的內容。
    ///
    /// 用「加倍」而非「反斜線」，有兩個理由：那是 `.csv2` 與 RFC 4180 已經在用的慣例，
    /// 看得懂這個格式的人不必再學一套；而且它不含反斜線，因此 `log` 裡那道整行跳脫完全
    /// 不會碰它——若寫成 `\"`，它的反斜線會在輸出時被加倍，那正是這件事第一次做錯時的
    /// 那種兩層跳脫。
    func redact(column: String, value: [UInt8]) -> String {
        if redactedColumns.contains(column) { return "<redacted>" }
        let v = echoValue(value, limit: nil).replacingOccurrences(of: "\"", with: "\"\"")
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
    /// What prompted it: a keyfile of ZERO bytes was refused and a keyfile of
    /// ONE byte was accepted, silently, at rc=0. The whole column came back in
    /// 98 tries. Someone had already decided a keyfile must have content; the
    /// missing decision was how much. A blind-test subject put it exactly:
    /// this tool's silence at 1 byte is indistinguishable from its silence at
    /// 32.
    ///
    /// `forCreating` 決定「弱金鑰要不要被拒絕」，而那個不對稱正是整個設計。
    ///
    /// `-encrypt` 與帶金鑰的 `-hash` 是在產生一個「日後要靠它保護某些東西」的檔案，那是
    /// 該堅持的時刻。`-decrypt` 面對的是「已經存在的檔案」，在那裡套用同一個下限，會讓一份
    /// 用弱金鑰做出來的檔案再也讀不回來——**以安全為由造成資料無法取回，那是更糟的交換。**
    ///
    /// 起因：0 bytes 的金鑰檔會被拒絕，而 1 byte 的被靜默接受，rc=0。整欄在 98 次內被復原。
    /// 有人早已決定「金鑰檔必須有內容」，缺的是「多少」。一位盲測受測者說得最準：這個工具
    /// 在 1 byte 時的沉默，與它在 32 bytes 時的沉默無法區分。
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
        guard let d = FileManager.default.contents(atPath: p), !d.isEmpty else {
            throw fault("keyfile is empty or unreadable: \(p)", "金鑰檔為空或無法讀取：\(p)")
        }
        let bytes = [UInt8](d)

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
                FileHandle.standardError.write(Data("""
                warning: no -keyfile given; the multissh private key will be used / 警告：未指定 -keyfile，將使用 multissh 的私鑰
                  \(p)  (fingerprint \(fp))
                if that key is regenerated or lost, this file can never be decrypted / 若此金鑰被重新產生或遺失，本檔案將永久無法解密
                continue? [y/N] / 繼續？[y/N]
                """.utf8))
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
    static func cell(_ bytes: [UInt8]) -> String {
        var s = String(bytes: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "|", with: "\\|")
        s = s.replacingOccurrences(of: "\r\n", with: "<br>")
        s = s.replacingOccurrences(of: "\n", with: "<br>")
        s = s.replacingOccurrences(of: "\r", with: "<br>")
        return s
    }
}

// ---------------------------------------------------------------------
// MARK: - Metrics / 量測
// ---------------------------------------------------------------------

/// Reported under `-debug` so the streaming guarantees can be ASSERTED rather
/// than asserted-by-comment. "It is written as a ring buffer" is not evidence
/// that memory stays bounded, and "it stops early" is not evidence that no
/// bytes past record b were read. Both were skipped cases until these numbers
/// existed.
/// 在 `-debug` 下回報，讓串流保證可以被「斷言」而不是「以註解宣稱」。
/// 「它是以環狀緩衝寫的」不構成記憶體有上界的證據，「它會提前停止」也不構成
/// 「沒有讀取 b 之後任何位元組」的證據。在這些數字存在之前，兩者都只能是 SKIP。
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

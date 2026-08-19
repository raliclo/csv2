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

    func openLog(path: String) {
        logPath = path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        // Append, never truncate: overwriting defeats the only purpose the
        // file has, which is being read later.
        // 一律追加，絕不覆寫：覆寫會讓這個檔案唯一的用途（日後回頭查）失效。
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
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
        let line = "\(Logger.timestamp()) \(level.label) \(message())\n"
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
            h.write(Data(line.utf8))
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
        h.write(Data("\(Logger.timestamp()) \(level.label) \(message)\n".utf8))
    }

    func debug(_ m: @autoclosure () -> String) { log(.debug, m()) }
    func info(_ m: @autoclosure () -> String) { log(.info, m()) }
    func warn(_ m: @autoclosure () -> String) { log(.warn, m()) }

    /// A value that belongs to an encrypted or hashed column never appears in
    /// the log. Otherwise `-update` on a protected column writes the plaintext
    /// into a file nobody is guarding.
    /// 屬於加密或雜湊欄位的值絕不出現在 log 中。否則對受保護欄位的 `-update`
    /// 會把明文寫進一個沒有人在保護的檔案。
    /// Escaped, and NOT truncated. The escaping is the load-bearing half: the
    /// log is one entry per line, and this wrote the value with quotes and
    /// nothing else -- so a newline inside a value opened a new line whose
    /// entire content the value chose. A forged entry with an attacker-picked
    /// timestamp landed in the audit trail at rc=0. The 40-character
    /// truncation did not prevent that, it only shortened the forged line,
    /// which is why lifting the limit had to wait for the escaping: otherwise
    /// the forgery would have gone from truncated to complete.
    /// 有跳脫，且**不截斷**。跳脫是承重的那一半：log 是一行一筆，而原本只是把值加上引號、
    /// 別的什麼都沒做——因此值裡的一個換行就會開啟新的一行，而那一行的全部內容由值決定。
    /// 一筆時間戳由攻擊者挑選的偽造紀錄，就這樣以 rc=0 落進稽核軌跡。40 字元的截斷擋不住
    /// 那件事，它只是把偽造的那一行剪短——這正是「解除上限」必須等「跳脫」先做的原因：
    /// 否則偽造會從被剪斷變成完整。
    func redact(column: String, value: [UInt8]) -> String {
        redactedColumns.contains(column)
            ? "<redacted>"
            : "\"\(reportEscape(echoValue(value, limit: nil)))\""
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

    static func loadKeyMaterial(path: String?, assumeYes: Bool) throws -> (bytes: [UInt8], path: String) {
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

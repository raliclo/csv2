// =====================================================================
//  main.swift — the command line, and the operations behind it
//  main.swift — 命令列，以及其後的各項操作
//
//  On the normal path this tool prints NOTHING. It has to work inside a
//  pipeline, and a CLI that talks on success cannot. Diagnostics go to
//  stderr under -debug; the operation record goes to the file named by -log.
//  正常路徑上本工具不輸出任何訊息。它必須能放進管線，而一個成功時還會說話的
//  CLI 做不到。診斷訊息在 -debug 下走 stderr，操作紀錄走 -log 指定的檔案。
// =====================================================================

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let CSV2_VERSION = "0.1.0"

// ---------------------------------------------------------------------
// MARK: - Options / 選項
// ---------------------------------------------------------------------

enum EditVerb {
    case insert(at: Int, row: String)
    case append(row: String)
    case deleteRange(from: Int, to: Int)
    case deleteCell(record: Int, column: String)
    case update(record: Int, column: String, value: String)
}

struct Options {
    var read = false
    var contains: String?
    var filter = false
    var includeHeaders = false
    var normalize = false

    var after = 0
    var before = 0

    var head: Int?
    var tail: Int?
    var mid: (Int, Int?)?

    var withHeader = false
    var rownum = false
    var physical = false
    var a1 = false

    var input: String?
    var output: String?
    var useStdin = false
    var useStdout = false
    var inPlace = false
    var headersOverride: Int?

    var markdown = false
    var pretty = false
    var json = false
    var jsonASCII = false
    var zh = false

    var edits: [EditVerb] = []
    var cellModifier = false
    var truncatePartial = false

    var encryptCols: String?
    var decryptCols: String?
    var hashCols: String?
    var keyfile: String?
    var assumeYes = false

    var debug = false
    var logPath: String?
    var noIndex = false
}

func usageError(_ en: String, _ zh: String) -> CSV2Error { fault(en, zh) }

// ---------------------------------------------------------------------
// MARK: - Argument parsing / 參數解析
// ---------------------------------------------------------------------

/// Both `-contains` and `--contains` are accepted. The cost is nil and it
/// stops someone typing by swift_tar's `--long` habit from hitting a wall.
/// An UNKNOWN flag is always an error: multissh has already been bitten by
/// an unknown option being swallowed as a hostname.
/// `-contains` 與 `--contains` 皆接受。成本為零，且避免使用者按 swift_tar 的
/// `--long` 習慣打字時撞牆。未知旗標一律報錯：multissh 已經被「未知選項被當成
/// 主機名稱吞掉」咬過一次。
func normalizeFlag(_ a: String) -> String {
    if a.hasPrefix("--") { return String(a.dropFirst(2)) }
    if a.hasPrefix("-") { return String(a.dropFirst(1)) }
    return a
}

func parseArgs(_ argv: [String]) throws -> Options {
    var o = Options()
    var i = 0

    func need(_ flag: String) throws -> String {
        i += 1
        guard i < argv.count else {
            throw usageError("\(flag) needs a value", "\(flag) 需要一個值")
        }
        // `-cell` is a MODIFIER, and it reads naturally between the verb and
        // its address: `-delete -cell 12:6`. Taking it as the value would make
        // the address "-cell", which then fails with a message about the
        // address rather than about what actually happened.
        // `-cell` 是修飾詞，寫在動詞與位址之間才自然：`-delete -cell 12:6`。
        // 把它當成值會使位址變成「-cell」，接著以一個在講位址的訊息失敗——
        // 而那不是實際發生的事。
        while argv[i] == "-cell" || argv[i] == "--cell" {
            o.cellModifier = true
            i += 1
            guard i < argv.count else {
                throw usageError("\(flag) needs a value after -cell", "\(flag) 在 -cell 之後仍需要一個值")
            }
        }
        return argv[i]
    }

    func intVal(_ flag: String, _ s: String) throws -> Int {
        guard let n = Int(s) else {
            throw usageError("\(flag): not a number: \(s)", "\(flag)：不是數字：\(s)")
        }
        return n
    }

    while i < argv.count {
        let arg = argv[i]
        guard arg.hasPrefix("-"), arg.count > 1 else {
            throw usageError(
                "unexpected argument \"\(arg)\"; csv2 takes flags only",
                "非預期的參數「\(arg)」；csv2 只接受旗標")
        }
        switch normalizeFlag(arg) {
        case "r": o.read = true
        case "contains": o.contains = try need(arg)
        case "filter": o.filter = true
        case "include-headers": o.includeHeaders = true
        case "normalize": o.normalize = true
        case "A": o.after = try intVal(arg, try need(arg))
        case "B": o.before = try intVal(arg, try need(arg))
        case "C":
            let n = try intVal(arg, try need(arg))
            o.after = n; o.before = n
        case "head": o.head = try intVal(arg, try need(arg))
        case "tail": o.tail = try intVal(arg, try need(arg))
        case "mid": o.mid = try parseMid(try need(arg))
        case "t": o.withHeader = true
        case "rownum": o.rownum = true
        case "physical": o.physical = true
        case "a1": o.a1 = true
        case "i": o.input = try need(arg)
        case "o": o.output = try need(arg)
        case "si": o.useStdin = true
        case "so": o.useStdout = true
        case "in-place": o.inPlace = true
        case "headers": o.headersOverride = try intVal(arg, try need(arg))
        case "md": o.markdown = true
        case "pretty": o.pretty = true
        case "json": o.json = true
        case "json-ascii": o.json = true; o.jsonASCII = true
        case "zh": o.zh = true
        case "en": o.zh = false
        case "cell": o.cellModifier = true
        case "truncate-partial": o.truncatePartial = true
        case "insert":
            let at = try intVal(arg, try need(arg))
            o.edits.append(.insert(at: at, row: try need(arg)))
        case "append":
            o.edits.append(.append(row: try need(arg)))
        case "delete":
            let spec = try need(arg)
            o.edits.append(try parseDelete(spec, cell: o.cellModifier, argvTail: argv, index: i))
        case "update":
            let addr = try need(arg)
            let val = try need(arg)
            let (r, c) = try parseCellAddress(addr, flag: arg)
            o.edits.append(.update(record: r, column: c, value: val))
        case "encrypt": o.encryptCols = try need(arg)
        case "decrypt": o.decryptCols = try need(arg)
        case "hash": o.hashCols = try need(arg)
        case "keyfile": o.keyfile = try need(arg)
        case "yes": o.assumeYes = true
        case "key":
            // Deliberately NOT implemented, and it says why rather than
            // "unknown flag": a secret on the command line is visible in `ps`
            // to every process on the machine and stays in shell history.
            // Offering it with a warning would not help -- the warning is read
            // once, after which it is just the easier one to type.
            // 刻意不實作，且說明原因而非只回「未知旗標」：命令列上的秘密在 `ps`
            // 中對本機所有行程可見，也會留在 shell 歷史裡。提供它並加警告沒有用
            // ——警告只會被讀一次，之後它就只是比較好打的那一個。
            throw usageError(
                "-key is not supported: a secret passed on the command line is visible in `ps` to every process on this machine and is kept in shell history. Use -keyfile <path>.",
                "不支援 -key：命令列上的秘密在 `ps` 中對本機每個行程都可見，也會留在 shell 歷史中。請改用 -keyfile <path>。")
        case "debug": o.debug = true
        case "log": o.logPath = try need(arg)
        case "no-index": o.noIndex = true
        case "version", "V":
            print("csv2 \(CSV2_VERSION)")
            exit(0)
        case "h", "help":
            printHelp()
            exit(0)
        default:
            throw usageError(
                "unknown flag \(arg); run csv2 --help",
                "未知旗標 \(arg)；請執行 csv2 --help")
        }
        i += 1
    }
    return o
}

func parseMid(_ s: String) throws -> (Int, Int?) {
    let parts = s.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 else {
        throw usageError("-mid takes a,b (either side may be empty)",
                         "-mid 的格式是 a,b（任一端可留空）")
    }
    let a = parts[0].isEmpty ? 1 : Int(parts[0]) ?? -1
    let b = parts[1].isEmpty ? nil : Int(parts[1])
    if parts[1].isEmpty == false && b == nil {
        throw usageError("-mid: not a number: \(parts[1])", "-mid：不是數字：\(parts[1])")
    }
    if a < 1 {
        throw usageError("-mid: a must be >= 1; records are numbered from 1",
                         "-mid：a 必須 >= 1；紀錄從 1 開始編號")
    }
    if let bb = b, bb < a {
        // Not silently swapped. Someone who wrote the range backwards has
        // probably got the logic backwards somewhere else too.
        // 不自動對調。使用者若寫反了，多半是別處的邏輯也反了。
        throw usageError("-mid \(a),\(bb): a is greater than b; csv2 does not swap them for you",
                         "-mid \(a),\(bb)：a 大於 b；csv2 不會替你對調")
    }
    return (a, b)
}

func parseDelete(_ spec: String, cell: Bool, argvTail: [String], index: Int) throws -> EditVerb {
    let looksLikeCell = spec.contains(":")
    // The `:` alone could tell these apart, but then "delete a whole record"
    // and "blank one cell" -- two very different things -- would differ by one
    // punctuation mark. What is wanted here is an error on a typo, not
    // silently doing the other thing.
    // 用 `:` 的有無自動判斷是做得到的，但那會讓「刪掉一整筆」與「清空一格」
    // 這兩件差很多的事，差別只在一個標點符號上。這裡要的是打錯字時報錯，
    // 而不是靜默地做另一件事。
    if cell && !looksLikeCell {
        throw usageError(
            "-delete -cell needs an r:c address, got \"\(spec)\"",
            "-delete -cell 需要 r:c 形式的位址，得到「\(spec)」")
    }
    if !cell && looksLikeCell {
        throw usageError(
            "\"\(spec)\" is a cell address; add -cell to blank that cell, or give a record number to delete the whole record",
            "「\(spec)」是儲存格位址；要清空該格請加 -cell，要刪除整筆請給紀錄號")
    }
    if cell {
        let (r, c) = try parseCellAddress(spec, flag: "-delete -cell")
        return .deleteCell(record: r, column: c)
    }
    let parts = spec.split(separator: ",").map(String.init)
    if parts.count == 1 {
        guard let n = Int(parts[0]), n >= 1 else {
            throw usageError("-delete: not a record number: \(spec)", "-delete：不是紀錄號：\(spec)")
        }
        return .deleteRange(from: n, to: n)
    }
    guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), a >= 1 else {
        throw usageError("-delete takes N or a,b", "-delete 的格式是 N 或 a,b")
    }
    if b < a {
        throw usageError("-delete \(a),\(b): a is greater than b", "-delete \(a),\(b)：a 大於 b")
    }
    return .deleteRange(from: a, to: b)
}

/// `r:c`, not `a,b`. In this tool `a,b` already means a RANGE (`-mid 3,7`),
/// and the same notation meaning two different things under different flags
/// is something a user gets wrong eventually -- silently, editing the wrong
/// cell. `r:c` is also exactly what `-contains` prints, so the output of one
/// command feeds straight into the next.
/// 用 `r:c` 而非 `a,b`。在這支工具裡 `a,b` 已經是「範圍」的意思（`-mid 3,7`），
/// 同一種寫法在不同旗標下代表不同概念，是使用者遲早會弄錯的東西——而且弄錯時
/// 不會報錯，只會改到別的儲存格。`r:c` 也正是 `-contains` 印出來的格式，因此
/// 一個指令的輸出可以直接接到下一個。
func parseCellAddress(_ s: String, flag: String) throws -> (Int, String) {
    let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let r = Int(parts[0]), r >= 1, !parts[1].isEmpty else {
        throw usageError("\(flag): expected r:c, got \"\(s)\"",
                         "\(flag)：需要 r:c 格式，得到「\(s)」")
    }
    return (r, parts[1])
}

// ---------------------------------------------------------------------
// MARK: - Validation / 驗證
// ---------------------------------------------------------------------

func validate(_ o: inout Options) throws {
    if o.input != nil && o.useStdin {
        throw usageError("-i and -si are mutually exclusive; giving both is an error rather than a silent choice",
                         "-i 與 -si 互斥；同時給出即為錯誤，而非默默擇一")
    }
    if o.output != nil && o.useStdout {
        throw usageError("-o and -so are mutually exclusive", "-o 與 -so 互斥")
    }
    if o.input == nil && !o.useStdin {
        throw usageError("no input: give -i FILE or -si", "沒有輸入：請給 -i FILE 或 -si")
    }
    if o.head != nil && o.tail != nil {
        // Not interpreted as "the middle" or "both ends". There is no reading
        // of both that is obviously right, so guessing one would be wrong
        // half the time and silent every time.
        // 不解釋成「中間」或「兩端」。兩者沒有一個明顯正確的讀法，猜一個會有
        // 一半的時候是錯的，而且每次都是靜默的。
        throw usageError("-head and -tail together have no single sensible meaning",
                         "-head 與 -tail 同時給出沒有一個合理的解釋")
    }
    if o.mid != nil && (o.head != nil || o.tail != nil) {
        throw usageError("-mid is mutually exclusive with -head and -tail",
                         "-mid 與 -head、-tail 互斥")
    }
    if o.markdown && o.json {
        throw usageError("-md and --json are mutually exclusive", "-md 與 --json 互斥")
    }
    if o.useStdin && o.headersOverride == nil {
        // stdin has no filename, so it has no extension, so the format cannot
        // be a declared fact. A default here would be a guess, and guessing
        // wrong eats the first record as a header without saying anything.
        // stdin 沒有檔名就沒有副檔名，格式無法成為被宣告的事實。此處的預設值
        // 就是猜測，而猜錯會把第一筆資料當成標頭吃掉，且什麼都不說。
        throw usageError("-si needs --headers 1 or --headers 2: stdin has no extension to declare the format",
                         "-si 需要 --headers 1 或 --headers 2：stdin 沒有可宣告格式的副檔名")
    }
    if let h = o.headersOverride, h != 1 && h != 2 {
        throw usageError("--headers takes 1 or 2", "--headers 只能是 1 或 2")
    }
    if o.markdown && !o.withHeader {
        // A Markdown table needs a header row and its `|---|` separator. Not
        // adding one silently: that would make the "no header by default" rule
        // grow an invisible exception, and invisible exceptions are what this
        // design keeps avoiding.
        // Markdown 表格需要標頭列與其下的分隔列。不自動補上：那會讓「預設不帶
        // 標頭」這條規則出現一個看不見的例外，而看不見的例外正是這份設計一直
        // 在避免的東西。
        throw usageError("-md needs -t: a Markdown table has no shape without a header row",
                         "-md 需要 -t：沒有標頭列就渲染不出 Markdown 表格")
    }
    if o.cellModifier {
        for e in o.edits {
            if case .insert = e {
                throw usageError(
                    "-insert -cell does not exist: inserting a cell mid-record pushes every later field one column along, so status_notes ends up under license. To add a column, every record and both header rows have to change together.",
                    "沒有 -insert -cell：在一列中間插入儲存格會把該列後面的欄位全部往後推一格，於是 status_notes 跑到 license 底下。要新增一欄，必須每一列與兩列標頭一起改。")
            }
        }
    }
    if !o.edits.isEmpty {
        if o.head != nil || o.tail != nil || o.mid != nil || o.contains != nil {
            throw usageError("editing and selection cannot be combined in one call",
                             "編輯與選取不可在同一次呼叫中混用")
        }
        if o.output == nil && !o.useStdout && !o.inPlace {
            throw usageError("an edit needs an explicit destination: -o FILE, -so, or --in-place",
                             "編輯需要明確的目的地：-o FILE、-so 或 --in-place")
        }
    }
    if o.after > 0 || o.before > 0 {
        guard o.contains != nil else {
            throw usageError("-A/-B/-C need -contains", "-A/-B/-C 需要搭配 -contains")
        }
        // Context records have no matching cell, so there is nothing for the
        // locating report to say about them. Context therefore implies the
        // record-shaped output, exactly like grep.
        // 上下文紀錄沒有命中的儲存格，定位報告對它們無話可說。因此給了上下文
        // 就走紀錄形狀的輸出，與 grep 相同。
        o.filter = true
    }
    if let inp = o.input, let out = o.output, inp == out, !o.inPlace {
        // Opening the output truncates it, and the input has not been read
        // yet. Refusing by default is the only safe behaviour.
        // 開啟輸出即截斷，而那時輸入還沒讀完。預設拒絕是唯一安全的做法。
        throw usageError("-i and -o name the same file; opening the output truncates it before the input has been read. Use --in-place, which writes a temp file and renames.",
                         "-i 與 -o 指向同一個檔案；開啟輸出會在輸入讀完前把它截斷。要就地編輯請用 --in-place，它會寫暫存檔再 rename。")
    }
    if o.inPlace {
        guard let inp = o.input else {
            throw usageError("--in-place needs -i FILE", "--in-place 需要 -i FILE")
        }
        if o.output == nil { o.output = inp }
    }
    if o.encryptCols != nil || o.decryptCols != nil || o.hashCols != nil {
        if o.head == nil && o.tail == nil && o.mid == nil && o.contains == nil {
            // -encrypt / -decrypt / -hash rewrite every record of the file, so
            // what comes out IS a file, not a selection fragment. The -t rule
            // exists to stop a fragment being written where a complete file is
            // promised; it has nothing to refuse here.
            // -encrypt / -decrypt / -hash 會改寫檔案的每一筆，因此產出的就是
            // 一個完整檔案，不是選取的片段。-t 那條規則是為了阻止「片段被寫進
            // 承諾了完整檔案的位置」，在這裡沒有東西要擋。
            o.withHeader = true
        }
    }
    if o.contains == nil && o.filter && o.edits.isEmpty {
        throw usageError("--filter needs -contains", "--filter 需要搭配 -contains")
    }
}

// ---------------------------------------------------------------------
// MARK: - Header helpers / 標頭輔助
// ---------------------------------------------------------------------

func headerName(_ f: Field) -> String {
    String(bytes: f.value, encoding: .utf8) ?? ""
}

/// `name:enc:<fingerprint>:<salt-base64>` marks an encrypted column. Keeping
/// it in the file itself means `-decrypt` needs no external metadata, a second
/// `-encrypt` on the same column can be refused rather than layered, and the
/// key fingerprint is checked BEFORE any decryption is attempted.
/// `name:enc:<指紋>:<salt-base64>` 標記已加密的欄位。資訊留在檔案本身，於是
/// `-decrypt` 不需要外部 metadata、對已加密的欄再次 `-encrypt` 可以直接拒絕
/// 而不是疊加一層，而且金鑰指紋在任何解密嘗試之前就先被檢查。
struct EncMarker {
    var base: String
    var fingerprint: String
    var salt: [UInt8]

    static func parse(_ name: String) -> EncMarker? {
        guard let range = name.range(of: ":enc:", options: .backwards) else { return nil }
        let base = String(name[name.startIndex..<range.lowerBound])
        let rest = String(name[range.upperBound...])
        let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let salt = B64.decode(parts[1]) else { return nil }
        return EncMarker(base: base, fingerprint: parts[0], salt: salt)
    }

    var encoded: String { "\(base):enc:\(fingerprint):\(B64.encode(salt))" }
}

func hashMarkerBase(_ name: String) -> String? {
    name.hasSuffix(":hash") ? String(name.dropLast(5)) : nil
}

/// The visible column name, with any marker removed. Addressing by name works
/// on the same name before and after encryption.
/// 去掉標記後的欄名。加密前後以欄名定址用的是同一個名字。
func baseName(_ name: String) -> String {
    if let m = EncMarker.parse(name) { return m.base }
    if let b = hashMarkerBase(name) { return b }
    return name
}

/// Numeric tokens are column numbers, anything else is a column name. 1-based,
/// because `cut -f`, `awk $1` and every spreadsheet are 1-based; 0-based here
/// would put people one column off when they paste the result into `cut`.
/// 純數字視為欄號，其餘視為欄名。1-based，因為 `cut -f`、`awk $1` 與所有試算表
/// 都是 1-based；0-based 會讓人把結果貼進 `cut` 時差一格。
func resolveColumn(_ token: String, header: Record) throws -> Int {
    if let n = Int(token) {
        guard n >= 1 && n <= header.count else {
            throw fault("column \(n) is out of range; the file has \(header.count) columns",
                      "第 \(n) 欄超出範圍；本檔案有 \(header.count) 欄")
        }
        return n - 1
    }
    for (i, f) in header.fields.enumerated() where baseName(headerName(f)) == token {
        return i
    }
    let names = header.fields.map { baseName(headerName($0)) }.joined(separator: ", ")
    throw fault("no column named \"\(token)\"; the columns are: \(names)",
              "沒有名為「\(token)」的欄位；本檔案的欄位是：\(names)")
}

func resolveColumnList(_ spec: String, header: Record) throws -> [Int] {
    if spec == "all" {
        return header.fields.enumerated().compactMap { (i, f) in
            EncMarker.parse(headerName(f)) != nil ? i : nil
        }
    }
    var out: [Int] = []
    for token in spec.split(separator: ",").map(String.init) {
        let idx = try resolveColumn(token, header: header)
        if !out.contains(idx) { out.append(idx) }
    }
    return out
}

// ---------------------------------------------------------------------
// MARK: - Reading a whole input through the parser / 以解析器讀取輸入
// ---------------------------------------------------------------------

struct InputPlan {
    var format: Format
    var headerRows: Int
    var source: ByteSource
    var describedPath: String
}

func openInput(_ o: Options) throws -> InputPlan {
    if o.useStdin {
        let h = o.headersOverride ?? 1
        return InputPlan(format: h == 2 ? .csv2 : .csv, headerRows: h,
                         source: ByteSource(stdin: 1 << 16), describedPath: "<stdin>")
    }
    let path = o.input!
    guard let fmt = Format.from(path: path) else {
        // The extension is what declares the format. Without one there is
        // nothing to declare it, so --headers has to.
        // 格式由副檔名宣告。沒有副檔名就沒有東西可以宣告，只能由 --headers 指定。
        guard let h = o.headersOverride else {
            throw fault("\(path) has neither a .csv nor a .csv2 extension, so the format is not declared; pass --headers 1 or --headers 2",
                      "\(path) 既非 .csv 亦非 .csv2，格式未被宣告；請給 --headers 1 或 --headers 2")
        }
        return InputPlan(format: h == 2 ? .csv2 : .csv, headerRows: h,
                         source: try ByteSource(path: path), describedPath: path)
    }
    let h = o.headersOverride ?? fmt.headerRows
    return InputPlan(format: fmt, headerRows: h,
                     source: try ByteSource(path: path), describedPath: path)
}

/// `.csv2` guarantees one record per line, LF-terminated, so a file that does
/// not end in LF is the signature of a torn append. It is reported, never
/// repaired: silently dropping a record the user believes was written is the
/// exact silent behaviour this design exists to avoid.
/// `.csv2` 保證一筆一行且以 LF 結尾，因此未以 LF 結尾就是撕裂追加的信號。
/// 只回報、不修復：安靜地丟掉一筆使用者以為已經寫入的資料，正是這份設計
/// 一直在避免的靜默行為。
func checkTornAppend(path: String, format: Format, truncatePartial: Bool) throws {
    guard format == .csv2 else { return }
    guard let h = FileHandle(forReadingAtPath: path) else { return }
    defer { try? h.close() }
    let size = h.seekToEndOfFile()
    guard size > 0 else { return }
    h.seek(toFileOffset: size - 1)
    let last = [UInt8](h.readData(ofLength: 1))
    if last.first != BYTE_LF && !truncatePartial {
        throw fault(
            "\(path) does not end with a newline; in .csv2 that means the last record is incomplete (a torn append). Pass --truncate-partial to drop it -- csv2 will not drop a record on its own.",
            "\(path) 未以換行結尾；在 .csv2 中這表示最後一筆不完整（撕裂的追加）。要丟棄它請給 --truncate-partial——csv2 不會自行丟棄任何一筆。")
    }
}

// ---------------------------------------------------------------------
// MARK: - Field count check / 欄數檢查
// ---------------------------------------------------------------------

func checkFieldCount(_ r: Record, expected: Int, what: String) throws {
    guard r.count == expected else {
        // Never pad. This is the check `artifacts.csv` was missing on the day
        // a commit string got written into the built_utc column with nothing
        // reporting anything.
        // 絕不補空。這正是 `artifacts.csv` 被寫壞那天缺少的檢查——一個 commit
        // 字串被寫進 built_utc 欄位，沒有任何東西報錯。
        throw fault(
            "\(what) has \(r.count) fields but the header has \(expected); csv2 will not pad or truncate to fit",
            "\(what) 有 \(r.count) 欄，標頭有 \(expected) 欄；csv2 不會補空或截斷來湊合")
    }
}

// ---------------------------------------------------------------------
// MARK: - Help / 說明
// ---------------------------------------------------------------------

func printHelp() {
    print("""
    csv2 \(CSV2_VERSION) — a CSV parser and editor that fails loudly
    csv2 \(CSV2_VERSION) —— 會大聲失敗的 CSV 解析器與編輯器

    READING / 讀取
      -r                 read
      -contains S        report every CELL containing S, as record:field
      --filter           with -contains, emit the matching records instead
      --include-headers  search the header rows too (reported as record 0)
      --normalize        compare in NFC; storage is never normalised
      -A N  -B N  -C N   context in RECORDS, not lines; blocks separated by --
      -head N  -tail N   first / last N RECORDS
      -mid a,b           records a through b inclusive; a, or ,b, are open ended
      -t                 include the header rows (default: data only)
      -rownum            prepend a record-number column (does not change addressing)
      --physical         also print the physical line the record starts on
      --a1               also print spreadsheet A1 notation

    INPUT / OUTPUT / 輸入輸出
      -i FILE  -o FILE   file paths; -o writes a temp file and renames
      -si  -so           stdin / stdout; neither buffers the whole file
      --headers 1|2      required with -si: stdin has no extension
      --in-place         edit -i in place, via temp file + rename

    FORMAT / 格式
      foo.csv            one header row, RFC 4180
      foo.csv2           TWO header rows (English, then Traditional Chinese),
                         one record per line, newlines escaped as \\n
      -md [--pretty]     Markdown table; needs -t. --pretty aligns and
                         therefore gives up streaming
      --json             JSON Lines; --json-ascii escapes non-ASCII
      --en  --zh         which header row to name columns by

    EDITING / 編輯
      -insert N ROW      insert as record N; ROW is ONE line of CSV text
      -append ROW        add at the end (O(1) when writing in place)
      -delete N | a,b    delete record N, or records a through b
      -delete -cell r:c  BLANK that cell; the field count never changes
      -update r:c VAL    set that cell
      --truncate-partial drop a trailing incomplete record instead of failing
      All indexes refer to the INPUT and are applied in one pass.

    PROTECTION / 保護
      -hash COLS         SHA-256, one way; still comparable for equality
      -encrypt COLS      ChaCha20-Poly1305; a fresh nonce each time, so the
                         same plaintext gives different ciphertext and the
                         column can no longer be searched
      -decrypt COLS      COLS may be `all` to take every marked column
      -keyfile PATH      default: ~/.multissh/generated/mldsa44-ed25519.key.raw
      --yes              accept the default key without a prompt
      There is no -key: a secret on the command line is visible in ps.

    DIAGNOSTICS / 診斷
      -debug             diagnostics to stderr
      -log FILE          append a timestamped operation record
      --version  --help

    NOTES / 注意
      * The record separator written is ALWAYS LF, on every platform. Bytes
        inside quotes are data and are preserved exactly, CR included.
      * Record numbers count DATA records; the header is 0 (0a / 0b).
      * Writing data rows without -t into a .csv/.csv2 path is refused.
      * 寫出的紀錄分隔符永遠是 LF；引號內的位元組是資料，原樣保留（含 CR）。
      * 紀錄號數的是資料筆數，標頭是 0（0a / 0b）。
      * 不加 -t 就把資料列寫進 .csv/.csv2 會被拒絕。
    """)
}

// ---------------------------------------------------------------------
// MARK: - The logged invocation / 記入 log 的呼叫方式
// ---------------------------------------------------------------------

/// The command line is logged so that "who changed this file into that" can
/// be answered later -- but the VALUES it carries are the data itself. A
/// `-update 12:6 <secret>` logged verbatim writes that secret into a file
/// nobody is guarding, which defeats redacting it everywhere else. So the
/// flags and addresses are kept and the values are replaced.
/// 呼叫方式記入 log，是為了日後能回答「這個檔案被誰改成這樣」——但它帶的「值」
/// 就是資料本身。把 `-update 12:6 <秘密>` 原樣記下來，等於把那個秘密寫進一個
/// 沒有人在保護的檔案，也就抵銷了其他地方的遮蔽。因此保留旗標與位址，把值換掉。
func sanitizedCommandLine(_ argv: [String]) -> String {
    var out: [String] = []
    var i = 0
    while i < argv.count {
        let a = argv[i]
        out.append(a)
        switch normalizeFlag(a) {
        case "update":
            // keep the address, drop the value / 保留位址，去掉值
            if i + 1 < argv.count { out.append(argv[i + 1]) }
            if i + 2 < argv.count { out.append("<value>") }
            i += 3
            continue
        case "insert":
            if i + 1 < argv.count { out.append(argv[i + 1]) }
            if i + 2 < argv.count { out.append("<row>") }
            i += 3
            continue
        case "append":
            if i + 1 < argv.count { out.append("<row>") }
            i += 2
            continue
        default:
            i += 1
        }
    }
    return out.joined(separator: " ")
}

// ---------------------------------------------------------------------
// MARK: - Entry point / 進入點
// ---------------------------------------------------------------------

func main() -> Int32 {
    do {
        var o = try parseArgs(Array(CommandLine.arguments.dropFirst()))
        if o.debug { Logger.shared.threshold = .debug }
        if let p = o.logPath { Logger.shared.openLog(path: p) }
        try validate(&o)

        Logger.shared.log(.info, "csv2 \(sanitizedCommandLine(Array(CommandLine.arguments.dropFirst())))")

        if !o.edits.isEmpty {
            if canUseAppendFastPath(o) {
                try runAppendFast(o)
            } else {
                try runEdit(o)
            }
        } else {
            try runSelect(o)
        }
        Logger.shared.close()
        return 0
    } catch let e as CSV2Error {
        // Exit non-zero with the record and field named. A wrong CSV is not
        // caught by the next tool; it is caught months later, if ever.
        // 以非零結束，並指出是哪一筆、哪一欄。錯的 CSV 不會被下一個工具發現，
        // 而是在數個月後才被發現——如果還有機會被發現的話。
        FileHandle.standardError.write(Data("csv2: \(e.message)\ncsv2：\(e.messageZh)\n".utf8))
        Logger.shared.log(.error, e.message)
        Logger.shared.close()
        return 1
    } catch {
        FileHandle.standardError.write(Data("csv2: \(error)\n".utf8))
        Logger.shared.close()
        return 1
    }
}

exit(main())

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

let CSV2_VERSION = "0.1.0"

// ---------------------------------------------------------------------
// MARK: - Options / 選項
// ---------------------------------------------------------------------

enum EditVerb {
    case insert(at: Int, row: String)
    case append(row: String)
    case deleteRange(from: Int, to: Int)
    case deleteCell(record: Int, column: String)
    case deleteColumn(column: String)
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
    var enOnly = false

    /// `-get r:c` -- the read that matches `-update r:c VAL`. Kept out of
    /// `edits` because it writes nothing; it is a selection of exactly one cell.
    /// `-get r:c`——與 `-update r:c VAL` 對稱的讀取。不放進 `edits`，因為它不寫入任何
    /// 東西；它是一種「恰好一格」的選取。
    var getCell: (Int, String)?

    var edits: [EditVerb] = []
    var cellModifier = false
    var colModifier = false
    var truncatePartial = false

    var encryptCols: String?
    var decryptCols: String?
    var hashCols: String?
    var keyfile: String?
    var assumeYes = false

    var debug = false
    var trace = false
    var logPath: String?
    var noIndex = false
    var verifyIndex = false
    var buildIndex = false
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
        while argv[i] == "-cell" || argv[i] == "--cell"
                || argv[i] == "-col" || argv[i] == "--col" {
            let mod = argv[i]
            if mod.hasSuffix("cell") { o.cellModifier = true } else { o.colModifier = true }
            i += 1
            guard i < argv.count else {
                throw usageError("\(flag) needs a value after \(mod)", "\(flag) 在 \(mod) 之後仍需要一個值")
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

    /// Counts are 1-based, like every index in this tool. `-head 0` and
    /// `-head -1` quietly returned nothing, which reads as "the file is empty"
    /// -- a wrong answer delivered as a successful one. They are typos, not
    /// requests.
    /// 計數是 1-based，與本工具所有索引一致。`-head 0` 與 `-head -1` 原本靜默回傳
    /// 空結果，那讀起來像「檔案是空的」——一個以成功姿態送出的錯誤答案。它們是
    /// 打錯字，不是請求。
    func positiveInt(_ flag: String, _ s: String) throws -> Int {
        let n = try intVal(flag, s)
        guard n >= 1 else {
            throw usageError("\(flag) \(n): a count must be at least 1",
                             "\(flag) \(n)：計數至少必須是 1")
        }
        return n
    }

    /// Context may legitimately be 0; negative cannot.
    /// 上下文可以是 0，但不可以是負數。
    func nonNegativeInt(_ flag: String, _ s: String) throws -> Int {
        let n = try intVal(flag, s)
        guard n >= 0 else {
            throw usageError("\(flag) \(n): context cannot be negative",
                             "\(flag) \(n)：上下文不可為負數")
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
        case "A": o.after = try nonNegativeInt(arg, try need(arg))
        case "B": o.before = try nonNegativeInt(arg, try need(arg))
        case "C":
            let n = try nonNegativeInt(arg, try need(arg))
            o.after = n; o.before = n
        case "head": o.head = try positiveInt(arg, try need(arg))
        case "tail": o.tail = try positiveInt(arg, try need(arg))
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
        case "zh": o.zh = true; o.enOnly = false
        case "en": o.enOnly = true; o.zh = false
        case "cell": o.cellModifier = true
        case "col": o.colModifier = true
        case "truncate-partial": o.truncatePartial = true
        // A modifier belongs to ONE verb and is cleared once that verb has
        // consumed it. Leaving it set made it sticky: in
        // `-delete -col b -delete 1` the second -delete inherited -col and
        // removed COLUMN 1 while the record survived -- an output that is
        // wrong in two ways at rc=0. `-cell` had the same defect and was only
        // hidden by r:c shape validation rejecting a bare record number; -col
        // accepts any column token, so nothing caught it.
        // 修飾詞屬於「一個」動詞，該動詞取用後即清除。留著不清會讓它變得黏著：
        // 在 `-delete -col b -delete 1` 中，第二個 -delete 繼承了 -col，移除了
        // 「第 1 欄」而那筆紀錄還在——一份在兩個方向上都錯、且 rc=0 的輸出。
        // `-cell` 有同樣的缺陷，只是被 r:c 的形狀檢查擋下（純紀錄號會被拒），
        // 而 -col 接受任何欄位標記，因此沒有東西攔得住。
        case "insert":
            let at = try intVal(arg, try need(arg))
            let row = try need(arg)
            if o.cellModifier {
                throw usageError(
                    "-insert -cell does not exist: inserting a cell mid-record pushes every later field one column along, so status_notes ends up under license. To add a column, every record and both header rows have to change together.",
                    "沒有 -insert -cell：在一列中間插入儲存格會把該列後面的欄位全部往後推一格，於是 status_notes 跑到 license 底下。要新增一欄，必須每一列與兩列標頭一起改。")
            }
            o.edits.append(.insert(at: at, row: row))
            o.cellModifier = false; o.colModifier = false
        case "append":
            o.edits.append(.append(row: try need(arg)))
            o.cellModifier = false; o.colModifier = false
        case "delete":
            let spec = try need(arg)
            o.edits.append(try parseDelete(spec, cell: o.cellModifier, col: o.colModifier,
                                           argvTail: argv, index: i))
            o.cellModifier = false; o.colModifier = false
        case "get":
            let addr = try need(arg)
            // 0a / 0b are well-formed ADDRESSES -- the locating report emits
            // them -- they are simply not addresses any verb can act on. Caught
            // here, before parseCellAddress, so the message is about what the
            // address means rather than about its shape.
            // 0a／0b 是格式正確的「位址」——定位報告就會產生它們——它們只是不是任何動詞
            // 能作用的位址。在 parseCellAddress 之前攔下，讓訊息談的是這個位址的意義，
            // 而不是它的形狀。
            if addr.hasPrefix("0a:") || addr.hasPrefix("0b:") || addr.hasPrefix("0:") {
                throw usageError(
                    "-get addresses data records from 1; \(addr) names a header cell, and header cells are not addressable by any verb -- -update cannot write one either",
                    "-get 從第 1 筆資料開始定址；\(addr) 指的是標頭儲存格，而標頭儲存格不是任何動詞可以定址的——-update 同樣寫不了它")
            }
            o.getCell = try parseCellAddress(addr, flag: arg)
            o.cellModifier = false; o.colModifier = false
        case "update":
            let addr = try need(arg)
            let val = try need(arg)
            let (r, c) = try parseCellAddress(addr, flag: arg)
            o.edits.append(.update(record: r, column: c, value: val))
            o.cellModifier = false; o.colModifier = false
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
        case "debug=trace", "debug=TRACE": o.debug = true; o.trace = true
        case "log": o.logPath = try need(arg)
        case "no-index": o.noIndex = true
        case "verify-index": o.verifyIndex = true
        case "build-index": o.buildIndex = true
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

func parseDelete(_ spec: String, cell: Bool, col: Bool, argvTail: [String], index: Int) throws -> EditVerb {
    // -cell and -col are opposites: one keeps the field and empties it, the
    // other removes the field from every record. Given both, there is no
    // reading that satisfies each, and picking one would make the other
    // silently ignored.
    // -cell 與 -col 是相反的：一個保留欄位並清空它，另一個把該欄位從每一筆中移除。
    // 兩個都給時不存在同時滿足的解釋，而選其中一個會讓另一個被靜默忽略。
    if cell && col {
        throw usageError(
            "-delete takes -cell or -col, not both: -cell blanks one field and keeps the column, -col removes the column from every record",
            "-delete 只能用 -cell 或 -col 其中之一：-cell 清空一格但保留該欄，-col 則把該欄從每一筆中移除")
    }
    if col {
        return .deleteColumn(column: spec)
    }
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
    if o.verifyIndex && o.input == nil {
        throw usageError("--verify-index needs -i FILE", "--verify-index 需要 -i FILE")
    }
    if o.buildIndex {
        guard o.input != nil else {
            throw usageError("--build-index needs -i FILE", "--build-index 需要 -i FILE")
        }
        if o.noIndex {
            throw usageError("--build-index and --no-index contradict each other",
                             "--build-index 與 --no-index 互相矛盾")
        }
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
    // `-delete -col` changes the SHAPE of every record, and `-insert`/`-append`
    // carry a literal row that has to match a shape. Which one -- the input's,
    // or the output's one column shorter? Both readings are defensible, so
    // whichever were chosen would quietly be wrong for half the people writing
    // the line. Two commands, one shape each.
    // `-delete -col` 會改變每一筆的「形狀」，而 `-insert`／`-append` 帶著一列必須符合
    // 某個形狀的字面值。是哪一個——輸入的，還是少一欄的輸出的？兩種讀法都說得通，
    // 因此無論選哪一個，對寫下這行的人裡有一半而言都會是靜默的錯。分成兩道指令，
    // 各自只有一個形狀。
    if o.edits.contains(where: { if case .deleteColumn = $0 { return true }; return false }) {
        for e in o.edits {
            switch e {
            case .insert, .append:
                throw usageError(
                    "-delete -col cannot be combined with -insert or -append: the literal row would have to match either the old shape or the new one, and there is no way to tell which was meant. Run them as two commands.",
                    "-delete -col 不可與 -insert／-append 併用：那一列字面值必須符合舊形狀或新形狀其中之一，而無法判斷是哪一個。請分成兩道指令執行。")
            default: break
            }
        }
    }
    if let (r, _) = o.getCell {
        // -get is a selection of one cell, so it cannot be combined with the
        // other selections or with an edit. Refusing rather than picking an
        // order: `-get 1:1 -head 3` has two readings and neither is obviously
        // the one intended.
        // -get 是「恰好一格」的選取，因此不能與其他選取或編輯併用。這裡是拒絕而非替它
        // 定一個順序：`-get 1:1 -head 3` 有兩種讀法，而沒有哪一種明顯就是使用者要的。
        if o.head != nil || o.tail != nil || o.mid != nil || o.contains != nil {
            throw usageError("-get selects one cell; it cannot be combined with -head/-tail/-mid/-contains",
                             "-get 選取的是一格；不可與 -head／-tail／-mid／-contains 併用")
        }
        if !o.edits.isEmpty {
            throw usageError("-get reads; it cannot be combined with an edit",
                             "-get 是讀取；不可與編輯併用")
        }
        // The report addresses header cells as 0a / 0b, and -get takes the same
        // r:c form as -update, which starts at record 1. Rejecting 0 with the
        // reason rather than with "expected r:c" -- the address is well-formed,
        // it just names something no edit verb can name either.
        // 定位報告以 0a／0b 定址標頭，而 -get 採用與 -update 相同的 r:c 形式，從第 1 筆
        // 開始。此處以「理由」拒絕 0 而非回以「需要 r:c」——那個位址格式正確，只是它指的
        // 東西同樣不是任何編輯動詞能指的。
        if r < 1 {
            throw usageError("-get addresses data records from 1; header cells (0a/0b in the locating report) are not addressable, the same as for -update",
                             "-get 從第 1 筆資料開始定址；標頭儲存格（定位報告中的 0a／0b）不可定址，與 -update 相同")
        }
        // -get has exactly one output shape: the value. Every flag that shapes
        // output is therefore meaningless with it, and accepting one silently
        // is worse than meaningless -- `-get 1:2 --json` is a natural thing to
        // type, because the README sends you to --json when a value's own
        // newlines matter, and it used to return the plain value at rc=0 with
        // the flag ignored. A flag the caller passed and the tool discarded is
        // this project's failure in miniature.
        // -get 只有一種輸出形狀：那個值。因此每一個「決定輸出形狀」的旗標對它都沒有意義，
        // 而「安靜地接受」比沒有意義更糟——`-get 1:2 --json` 是很自然會打出來的東西，因為
        // README 在「值本身的換行有意義」時就是叫你去用 --json；而它先前會在 rc=0 下回傳
        // 純粹的值，並把那個旗標丟掉。一個呼叫端給了、而工具丟棄了的旗標，正是本專案要
        // 消滅的失敗的縮影。
        var shaping: [String] = []
        if o.json { shaping.append("--json") }
        if o.markdown { shaping.append("-md") }
        if o.pretty { shaping.append("--pretty") }
        if o.withHeader { shaping.append("-t") }
        if o.rownum { shaping.append("-rownum") }
        if !shaping.isEmpty {
            throw usageError(
                "-get prints one value and has no other shape, so \(shaping.joined(separator: ", ")) would be ignored; for a shaped record use -mid \(r),\(r) instead",
                "-get 只印出一個值、沒有第二種形狀，因此 \(shaping.joined(separator: "、")) 會被忽略；需要帶形狀的紀錄請改用 -mid \(r),\(r)")
        }
        // A one-cell value is not a CSV file and must not be written to a path
        // whose suffix promises one.
        // 一格的值不是一個 CSV 檔，不得寫入「副檔名承諾了 CSV」的路徑。
        if let out = o.output, Format.declaresFormat(path: out) {
            throw usageError("-get writes one value, not a CSV file; do not send it to a .csv/.csv2 path",
                             "-get 寫出的是一個值而不是 CSV 檔；請不要送往 .csv／.csv2 路徑")
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
        // ALWAYS write the header, selection or not.
        //
        // For -encrypt this is not a convenience, it is the difference between
        // recoverable and destroyed. The per-file salt and the key fingerprint
        // live ONLY in the header marker (`col:enc:<fp>:<salt>`), and the salt
        // is fresh on every run -- so ciphertext emitted without its header can
        // never be decrypted by anyone, including the person who wrote it.
        // Previously `-encrypt license -head 1` produced exactly that, at rc=0,
        // with no warning.
        //
        // Forcing the header rather than refusing: for a transform there is no
        // second reading. A headerless encrypted fragment has no use to refuse
        // in favour of.
        // 不論有沒有選取，一律寫出標頭。
        //
        // 對 -encrypt 而言這不是方便，而是「還原得回來」與「毀了」的差別。每檔的
        // salt 與金鑰指紋只存在於標頭標記中（`col:enc:<指紋>:<salt>`），而 salt
        // 每次執行都重新產生——因此不帶標頭寫出的密文，任何人都無法解密，包括寫
        // 它的人自己。先前 `-encrypt license -head 1` 產生的正是那個，rc=0，
        // 而且沒有任何警告。
        //
        // 選擇「強制」而非「拒絕」：對轉換而言沒有第二種合理讀法。一個不帶標頭的
        // 加密片段，沒有任何值得為它保留的用途。
        o.withHeader = true
    }

    // --- Defect 2: --headers overrode the suffix with no cross-check.
    //
    // `--headers 1` on a .csv2 file made csv2 report
    // `{"format":"csv2","headers":1}` -- a self-contradiction, since a .csv2
    // has two header rows by definition -- and read 22 records as 23, promoting
    // the Chinese title row to data. An edit written back then deleted the
    // wrong record and produced a structurally valid file with one header row
    // missing.
    //
    // The suffix DECLARES the format; --headers exists for input that has no
    // suffix to declare it. When both speak and disagree, one of them is wrong
    // and csv2 cannot tell which -- so it refuses, the same way
    // `--build-index --no-index` is refused for contradicting itself.
    // 缺陷 2：--headers 會覆蓋副檔名，且不做交叉檢查。
    //
    // 對 .csv2 檔案給 `--headers 1`，csv2 會回報
    // `{"format":"csv2","headers":1}`——那是自相矛盾，因為 .csv2 依定義就有兩列
    // 標頭——並把 22 筆讀成 23 筆，將中文標題列升格為資料。據此寫回的編輯會刪錯
    // 紀錄，並產生一個「結構合法但少了一列標頭」的檔案。
    //
    // 副檔名「宣告」格式；--headers 的存在是為了「沒有副檔名可宣告」的輸入。當兩者
    // 都發言且互相牴觸時，其中一個是錯的而 csv2 分不出是哪一個——因此拒絕，與
    // `--build-index --no-index` 因自相矛盾而被拒是同一條規則。
    if let h = o.headersOverride, let inp = o.input, let fmt = Format.from(path: inp) {
        if h != fmt.headerRows {
            throw usageError(
                "\(inp) declares \(fmt.headerRows) header row(s) by its suffix, but --headers says \(h). The suffix declares the format; --headers is for input with no suffix to declare it. Rename the file or drop --headers.",
                "\(inp) 的副檔名宣告了 \(fmt.headerRows) 列標頭，但 --headers 說 \(h) 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請改檔名，或拿掉 --headers。")
        }
    }

    // --- Defect 3: .csv -> .csv2 silently lost a record.
    //
    // `-r -t -i a.csv -o conv.csv2` wrote ONE header row into a path whose
    // suffix promises two. Reading it back took the first data record as the
    // second header row: 21 records became 20, and busybox became a column
    // title. The existing guard only asked whether -t was given, never whether
    // the header rows being written match what the output suffix declares.
    //
    // csv2 cannot convert between them on its own: going from one header row to
    // two means inventing a row of Traditional Chinese titles, and inventing
    // data is the one thing this tool must never do.
    // 缺陷 3：.csv → .csv2 會靜默少一筆資料。
    //
    // `-r -t -i a.csv -o conv.csv2` 把「一列」標頭寫進一個副檔名承諾「兩列」的路徑。
    // 讀回時第一筆資料被當成第二列標頭：21 筆變成 20 筆，busybox 變成了欄位標題。
    // 原本的守衛只問「有沒有給 -t」，從未問「正在寫出的標頭列數是否符合輸出副檔名
    // 所宣告的」。
    //
    // csv2 無法自行轉換：從一列標頭變成兩列，意味著要「發明」一列繁體中文標題，
    // 而發明資料正是這支工具絕不能做的事。
    if let out = o.output, let outFmt = Format.from(path: out) {
        let inRows: Int
        if let inp = o.input, let inFmt = Format.from(path: inp) {
            inRows = o.headersOverride ?? inFmt.headerRows
        } else {
            inRows = o.headersOverride ?? 1
        }
        if inRows != outFmt.headerRows {
            throw usageError(
                "the input has \(inRows) header row(s) and \(out) declares \(outFmt.headerRows) by its suffix. csv2 will not convert between them: going to two rows would mean inventing a row of titles, and dropping to one would discard them. Choose an output suffix that matches, or write the header rows yourself.",
                "輸入有 \(inRows) 列標頭，而 \(out) 的副檔名宣告 \(outFmt.headerRows) 列。csv2 不會替你轉換：轉成兩列意味著要發明一列標題，轉成一列則會丟掉它們。請改用相符的輸出副檔名，或自行寫出標頭列。")
        }
    }
    if (o.physical || o.a1) && (o.contains == nil || o.filter || o.markdown || o.json) {
        // Both add a part to an ADDRESS, and the locating report is the only
        // output that prints one. Everywhere else they were accepted and did
        // nothing, which is indistinguishable from "this flag is not working".
        // 兩者都是在「位址」上附加資訊，而唯一會印出位址的輸出就是定位報告。
        // 在其他地方它們會被接受卻毫無作用，那與「這個旗標壞了」無從分辨。
        let which = [o.physical ? "--physical" : nil, o.a1 ? "--a1" : nil].compactMap { $0 }.joined(separator: " and ")
        throw usageError(
            "\(which) add to the address in the locating report, so they need -contains without --filter, -md or --json",
            "\(which) 是附加在定位報告的位址上的，因此需要搭配 -contains，且不能同時給 --filter、-md 或 --json")
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
    if name.hasSuffix(":hash") { return String(name.dropLast(5)) }
    // `:hmac:<fingerprint>` is the keyed form. Recognised here so that
    // re-hashing an already-hashed column is refused either way, and so the
    // base name still resolves for addressing.
    // `:hmac:<指紋>` 是 keyed 形式。在此一併辨識，讓「對已雜湊的欄位再雜湊一次」
    // 兩種形式都會被拒絕，也讓定址時仍能解析出原本的欄名。
    if let r = name.range(of: ":hmac:", options: .backwards) {
        return String(name[name.startIndex..<r.lowerBound])
    }
    return nil
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
    // Collect every match rather than returning the first.
    //
    // A file may legitimately carry two columns with the same name -- CSV does
    // not forbid it and spreadsheets produce it -- and `-update 1:note X` used
    // to edit whichever came first, at rc=0, with nothing said. The caller
    // asked to change `note` and got one of two, chosen by position. That is
    // the incident this project was built after, reproduced by the tool meant
    // to prevent it.
    //
    // Comparison is by Swift's String ==, which is CANONICAL EQUIVALENCE: an
    // NFC `café` and an NFD `café` are the same name here, even though they are
    // different bytes. That is right for a name -- they are the same name to
    // everyone who reads it -- but it also means two columns can collide
    // without looking identical in a hex dump, which makes refusing the
    // ambiguity matter more, not less.
    //
    // 收集「每一個」匹配，而不是回傳第一個。
    // 一個檔案可以合法地帶有兩個同名欄位——CSV 並未禁止，而試算表就會產生——而
    // `-update 1:note X` 先前會編輯位置在前的那一個，rc=0，什麼也不說。呼叫端要求修改
    // `note`，拿到的是兩者之一，由位置決定。那正是本專案因之而生的那起事故，被那支
    // 本該防止它的工具重現了一次。
    // 比較用的是 Swift 的 String ==，也就是「正規等價」：NFC 的 café 與 NFD 的 café 在此
    // 是同一個名字，儘管位元組不同。對「名字」而言那是對的——對每一個讀到它的人來說，
    // 那就是同一個名字——但這也意味著兩個欄位可以在 hex dump 裡看起來不同卻相撞，
    // 因此「拒絕這個歧義」更要緊，而不是更不要緊。
    var hits: [Int] = []
    for (i, f) in header.fields.enumerated() where baseName(headerName(f)) == token {
        hits.append(i)
    }
    if hits.count == 1 { return hits[0] }
    if hits.count > 1 {
        let where_ = hits.map { "\($0 + 1)" }.joined(separator: ", ")
        throw fault(
            "\"\(token)\" names \(hits.count) columns (\(where_)); address it by number, because picking one for you would be a guess",
            "「\(token)」指向 \(hits.count) 個欄位（第 \(where_) 欄）；請改用欄號定址，因為替你挑一個等於猜測")
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
      -delete -col N     remove column N from every record AND both header
                         rows. The one deletion that keeps alignment.
      -get r:c           print that cell's value and nothing else. The read
                         that matches -update r:c VAL
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
      --no-index         never read or write a .index sidecar
      --verify-index     O(n) full check of the sidecar; the O(1) check the
                         normal path does is deliberately a heuristic
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
        if o.debug { Logger.shared.threshold = o.trace ? .trace : .debug }
        if let p = o.logPath { Logger.shared.openLog(path: p) }
        try validate(&o)

        Logger.shared.log(.info, "csv2 \(sanitizedCommandLine(Array(CommandLine.arguments.dropFirst())))")

        if o.buildIndex {
            try runBuildIndex(o)
        } else if o.verifyIndex {
            try runVerifyIndex(o)
        } else if !o.edits.isEmpty {
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
        // Recorded in the -log FILE, not echoed to stderr again. ERROR is above
        // the default WARN threshold, so routing it through Logger printed the
        // same failure a third time, with a timestamp, even when no -log was
        // asked for. A script capturing stderr got the message twice.
        // 只記入 -log 指定的檔案，不再往 stderr 回顯一次。ERROR 高於預設的 WARN
        // 門檻，因此走 Logger 會把同一個失敗第三次印出來、還帶時間戳，即使根本
        // 沒有要求 -log。捕捉 stderr 的腳本會拿到重複的訊息。
        Logger.shared.logToFileOnly(.error, e.message)
        Logger.shared.close()
        return 1
    } catch {
        FileHandle.standardError.write(Data("csv2: \(error)\n".utf8))
        Logger.shared.close()
        return 1
    }
}

exit(main())

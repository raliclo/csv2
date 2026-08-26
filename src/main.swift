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
    /// Whether a context flag was GIVEN, regardless of its value. The output
    /// shape follows the flag, not the number -- see the parse site.
    /// 是否「給了」上下文旗標，與它的值無關。輸出形狀跟著旗標走，不跟著數字走——見解析處。
    var contextGiven = false
    /// Which flag SET `before`. The buffered-record refusal quotes it, and a
    /// message naming `-B` to someone who typed `-C` sends them looking for a
    /// flag that is not on their command line.
    /// 是哪一個旗標設定了 `before`。緩衝上限那條拒絕會引用它——對一個打了 `-C` 的人說
    /// `-B`，會讓他去找一個並不在自己指令列上的旗標。
    var beforeFlag = "-B"
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
    var mdTable: Int? = nil
    var zh = false
    var enOnly = false
    /// How many of `--en`/`--zh` were given, which the two Bools cannot say:
    /// each clears the other, so both-given looks exactly like last-given.
    /// `--en`／`--zh` 給了幾個——那是那兩個 Bool 說不出來的：它們互相清除，因此「兩個都給」
    /// 看起來與「只給了後面那個」一模一樣。
    var langFlags = 0
    var sawEn = 0
    var sawZh = 0

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

/// A path with symlinks followed and the spelling normalised.
///
/// Used for deciding WHERE to write and whether two paths are one file; never
/// for what a message says, because a caller should be told about the file they
/// named. resolvingSymlinksInPath() also normalises -- a relative path becomes
/// absolute, and on macOS /private/tmp becomes /tmp -- which is why the result
/// must not be compared against a path as typed. That comparison is what broke
/// the append fast path (DT).
/// 解析過 symlink、且拼法已正規化的路徑。
/// 只用來決定「寫到哪裡」與「兩個路徑是不是同一個檔案」，絕不用於訊息內容——訊息要指名
/// 呼叫端說出口的那個檔案。resolvingSymlinksInPath() 同時也會正規化（相對變絕對、macOS 上
/// /private/tmp 變 /tmp），因此它的結果不能拿去和「打出來的路徑」比較；append 快路徑就是
/// 那樣被弄斷的（DT）。
func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

/// Whether two paths name one file, decided by resolving both. Both are
/// normalised the same way, so a relative path and an absolute one that reach
/// the same file compare equal.
/// 兩個路徑是不是同一個檔案，以「兩邊都解析」來判定。兩者以同一種方式正規化，因此一個
/// 相對路徑與一個抵達同一個檔案的絕對路徑會相等。
/// Two names for one file. The path comparison catches every SPELLING --
/// `./x`, `../d/x`, an absolute path, a symlink -- and a hard link is not a
/// spelling: it is a second name in the directory tree for the same inode, and
/// resolving it changes nothing. So the identity is asked for as well, and it
/// is the authority where it exists.
/// 一個檔案的兩個名字。比對路徑抓得到每一種「拼法」——`./x`、`../d/x`、絕對路徑、symlink
/// ——而硬連結不是一種拼法：它是同一個 inode 在目錄樹裡的第二個名字，解析它不會改變什麼。
/// 因此也一併問「身分」，而在身分問得到的地方，以身分為準。
func sameFile(_ a: String, _ b: String) -> Bool {
    if resolved(a) == resolved(b) { return true }
    guard let na = Platform.fileNode(path: a), let nb = Platform.fileNode(path: b) else {
        return false
    }
    return na.dev == nb.dev && na.ino == nb.ino
}

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
/// Every flag this parser recognises, so a DATA argument can refuse to be one.
///
/// `csv2 -update 1:1 -t -i f.csv --in-place` wrote the two characters `-t`
/// into the cell, at rc=0. `-append --json` appended a record containing
/// `--json`. That is this tool's founding failure -- exit zero, plausible
/// garbage -- arriving through its own argument parser, and the README quotes
/// multissh being bitten by an unknown option swallowed as a hostname as the
/// reason unknown flags are always an error. The principle was there; it just
/// stopped at UNKNOWN flags.
///
/// Known flags only, not "anything starting with a dash": `-update 1:2 -5`
/// stores a negative number and must keep working. For a value that really is
/// a flag name, `--` ends flag parsing -- `-update 1:1 -- -t`.
///
/// T121b holds this list against the parser's own cases, because a list of
/// names beside a switch is exactly the kind of thing that drifts.
///
/// 這個解析器認得的每一個旗標，好讓「資料」引數能拒絕自己變成其中之一。
///
/// `csv2 -update 1:1 -t -i f.csv --in-place` 會把 `-t` 這兩個字元寫進儲存格，rc=0。
/// 那正是這個工具的招牌失敗——以 0 結束、輸出看似合理的垃圾——而它是從自己的引數解析器
/// 進來的；README 還引用了 multissh 被「未知選項被當成主機名吞掉」咬過的事，作為「未知旗標
/// 一律視為錯誤」的理由。那條原則本來就在，只是停在「未知」旗標上。
///
/// 只擋「已知旗標」，而不是「所有以減號開頭的東西」：`-update 1:2 -5` 存的是一個負數，
/// 必須繼續能用。若某個值真的就是一個旗標名，用 `--` 結束旗標解析：`-update 1:1 -- -t`。
///
/// 這份清單由 T121b 對照解析器自己的 case 檢查——一份放在 switch 旁邊的名稱清單，正是那種
/// 會漂移的東西。
let KNOWN_FLAGS: Set<String> = [
    "a1",
    "append",
    "build-index",
    "cell",
    "col",
    "contains",
    "debug",
    "decrypt",
    "delete",
    "en",
    "encrypt",
    "filter",
    "get",
    "h",
    "hash",
    "head",
    "headers",
    "help",
    "i",
    "in-place",
    "include-headers",
    "insert",
    "json",
    "json-ascii",
    "md-table",
    "key",
    "keyfile",
    "log",
    "md",
    "mid",
    "no-index",
    "normalize",
    "o",
    "physical",
    "pretty",
    "r",
    "rownum",
    "si",
    "so",
    "t",
    "tail",
    "truncate-partial",
    "update",
    "verify-index",
    // Four names the parser answers to that this list did not carry: version
    // with its single-letter alias, and the three context flags. A flag absent
    // from here is written into the file as data instead of being refused --
    // measured, an edit whose value was the version flag stored it as text at
    // rc=0, while a read flag in the same position was refused.
    //
    // T121h compares this list against the parser's cases and could not see
    // them: its pattern allowed only lowercase inside an alias, so a case line
    // carrying a capital-letter alias matched nothing at all and was skipped
    // whole. Both sides accept capitals now.
    //
    // No flag names in quotes anywhere in this comment. The extraction reads
    // every quoted token between the brackets, so a comment quoting one adds a
    // flag that does not exist -- which happened while writing this, and cost
    // two runs to see.
    // 這份清單先前沒有帶著、而解析器認得的四個名字：版本旗標與它的單字母別名，以及三個
    // 上下文旗標。一個不在這裡的旗標，會被當成資料寫進檔案而不是被拒絕——實測：一次
    // 「值就是版本旗標」的編輯，以 rc=0 把它當文字存了進去，而同一個位置的讀取旗標會被拒絕。
    // T121h 拿這份清單去對解析器的 case，卻看不見它們：它的樣式在別名處只允許小寫，因此一行
    // 帶著大寫別名的 case 完全不匹配、整行被跳過。現在兩邊都接受大寫。
    // 這段註解裡不放任何「加引號的旗標名稱」。抽取器會讀括號之間每一個帶引號的 token，
    // 因此一段引用了旗標名的註解，會憑空多出一個不存在的旗標——寫這段時就發生了，花了兩次
    // 執行才看出來。
    "version",
    "V",
    "A",
    "B",
    "C",
    "yes",
    "zh"
]

func normalizeFlag(_ a: String) -> String {
    if a.hasPrefix("--") { return String(a.dropFirst(2)) }
    if a.hasPrefix("-") { return String(a.dropFirst(1)) }
    return a
}

func parseArgs(_ argv: [String]) throws -> Options {
    var o = Options()
    var i = 0
    /// Set by `--` and consumed by the next `needData`, so a value that is a
    /// flag name can still be stored.
    /// 由 `--` 設定、由下一次 `needData` 消耗，好讓「本身就是旗標名」的值仍然存得進去。
    var dataIsLiteral = false
    /// Flags already seen, for the ones that are not repeatable.
    ///
    /// Given twice, they used to take the LAST silently. For most that is a
    /// surprise; for `-hash` it discloses data: `-hash note -hash ver` hashed
    /// `ver` and left `note` in plaintext, at rc=0, in a file whose whole
    /// purpose was that `note` be masked. The README states the edit verbs are
    /// repeatable and accumulate, which makes the unstated opposite rule for
    /// everything else actively misleading.
    ///
    /// 已經出現過的旗標，供「不可重複」的那些使用。
    ///
    /// 重複給出時，它們原本會靜默採用「最後一個」。對多數旗標那只是意外；對 `-hash` 則會
    /// 洩漏資料：`-hash note -hash ver` 雜湊了 `ver`、把 `note` 留成明文，rc=0，而那個檔案
    /// 存在的全部目的就是讓 `note` 被遮蔽。README 說「編輯動詞可重複、會累加」，這讓其餘
    /// 旗標那條沒有被寫出來的相反規則，變得會主動誤導人。
    var seenFlags: Set<String> = []
    func once(_ name: String) throws {
        guard seenFlags.insert(name).inserted else {
            throw usageError(
                "\(name) is given more than once; it is not repeatable, and taking the last one silently is how -hash note -hash ver leaves note in plaintext at rc=0. The repeatable verbs are -insert, -append, -delete and -update",
                "\(name) 被給了不只一次；它不可重複，而「靜默採用最後一個」正是 -hash note -hash ver 會在 rc=0 下把 note 留成明文的原因。可重複的動詞是 -insert、-append、-delete 與 -update")
        }
    }

    /// For an argument that carries DATA -- a value, a row literal, a search
    /// string. Those are the ones where Swift's lossy decode of argv changes
    /// what csv2 stores or compares, silently and at rc=0: `-update 1:2 $'A\xffB'`
    /// wrote `A U+FFFD B`, which is the exact substitution T8 exists to prevent,
    /// arriving through the write path instead of the read path.
    ///
    /// Only these. A PATH may legitimately hold arbitrary bytes on Linux, and
    /// refusing those would break a use that works today for a fault csv2 does
    /// not commit -- it hands paths to the filesystem, it does not store them
    /// as data. Round 38, defect II.
    ///
    /// 給「帶資料」的參數用——一個值、一列 row literal、一個搜尋字串。那些正是
    /// 「Swift 對 argv 的有損解碼」會改變 csv2 所儲存或比對的東西的地方，而且是靜默的、
    /// rc=0：`-update 1:2 $'A\xffB'` 存進去的是 `A U+FFFD B`，那正是 T8 存在所要防止的
    /// 那個替代，只是它從「寫入」路徑而不是「讀取」路徑進來。
    /// 只有這些。**路徑**在 Linux 上本來就可以是任意位元組，為一個 csv2 並未犯下的錯誤去
    /// 拒絕它們，會弄壞一個今天可以正常運作的用法——csv2 把路徑交給檔案系統，並不把它當成
    /// 資料儲存。第 38 回合，缺陷 II。
    func needData(_ flag: String) throws -> String {
        let v = try need(flag)
        if !dataIsLiteral, v.hasPrefix("-"), KNOWN_FLAGS.contains(normalizeFlag(v)) {
            throw usageError(
                // "end flag parsing" overstates what `--` does here: it marks
                // the NEXT argument as data and leaves later flags alone,
                // which is what lets -i and -o follow the value. A round read
                // the phrase, wrote it into the README as "everything after it
                // is data", and the next round proved that false in one
                // command.
                // 「結束旗標解析」把 `--` 在這裡做的事說大了：它讓「下一個」引數成為資料，
                // 而後面的旗標依然是旗標——那正是 -i、-o 可以接在值後面的原因。有一個回合
                // 讀了這個說法、把它寫成 README 裡的「其後一律視為資料」，而下一個回合用
                // 一個指令就證明那是錯的。
                // "will not write a flag into your file" was written for the
                // edit verbs and reused for every verb, so `-contains -r`
                // answered a SEARCH with a sentence about writing. The refusal
                // is right either way; what it is protecting differs, and the
                // wording now says the part that is common to both.
                // 「不會把一個旗標寫進你的檔案」是為編輯動詞寫的，卻被每一個動詞共用，
                // 於是 `-contains -r` 用一句關於「寫入」的話去回答一次「搜尋」。兩種情況下
                // 這條拒絕都是對的；不同的是它在保護什麼，而現在的措辭說的是兩者共通的那一半。
                // The prescription used to be a whole command, `\(flag) -- \(v)`,
                // and it was runnable only for the verbs that take ONE argument.
                // `-update` takes r:c and then the value, so the address had
                // already been consumed by the time this ran, and typing the
                // suggestion back gave `-update: expected r:c, got "-append"`.
                // It now shows where `--` goes rather than reconstructing a
                // command it cannot see all of. Round 74, JC.
                // 這個處方原本是一整個指令 `\(flag) -- \(v)`，而它只有在「吃一個引數」的動詞上
                // 才跑得起來。`-update` 先吃 r:c、再吃值，因此走到這裡時那個位址早就被消耗掉了，
                // 把建議照打回去會得到 `-update: expected r:c, got "-append"`。現在它指出 `--`
                // 該放在哪裡，而不是去重建一個它看不全的指令。第 74 回合，JC。
                "\(flag) \(v): \(v) is a flag, and this position takes DATA. csv2 will not treat a flag as data. If the value really is \(v), put -- immediately BEFORE it, leaving everything else where it is: ... -- \(v) ...",
                "\(flag) \(v)：\(v) 是一個旗標，而這個位置要的是「資料」。csv2 不會把一個旗標當成資料。若這個值真的就是 \(v)，請把 -- 放在它的「正前面」，其餘一切位置不變：... -- \(v) ...")
        }
        dataIsLiteral = false
        // argv[0] is the program, and `argv` here is CommandLine.arguments
        // dropping it -- so the raw index is one higher.
        // argv[0] 是程式本身，而此處的 `argv` 是去掉它之後的 CommandLine.arguments
        // ——因此原始索引要多一。
        guard Platform.rawArgumentIsValidUTF8(at: i + 1) else {
            throw usageError(
                "\(flag): the value is not valid UTF-8. csv2 will not store a replacement character in place of a byte it cannot decode -- that is the silent substitution this tool exists to refuse. Put the value in a file and edit it there, where bytes are preserved exactly.",
                "\(flag)：這個值不是合法的 UTF-8。csv2 不會用替代字元去頂替一個它解不開的位元組——那正是這支工具存在所要拒絕的那種靜默替代。請把該值放進檔案、在檔案裡編輯，那裡的位元組會被原樣保留。")
        }
        return v
    }

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
        // `--` ends flag parsing for the value that follows, which is the only
        // way to store a value that IS a flag name. Conventional, and it gives
        // the refusal above something true to point at.
        // `--` 結束「其後那個值」的旗標解析，那是「儲存一個本身就是旗標名的值」唯一的辦法。
        // 這是慣例，也讓上面那個拒絕有一個真的存在的出路可以指。
        if argv[i] == "--" {
            i += 1
            guard i < argv.count else {
                throw usageError("\(flag) needs a value after --", "\(flag) 在 -- 之後仍需要一個值")
            }
            dataIsLiteral = true
            return argv[i]
        }
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
        case "contains":
            try once("-contains")
            let needle = try needData(arg)
            // An empty search string matched every cell in the file. Refused
            // for the reason an empty column list is refused: "search for
            // nothing" and "a variable that came out empty" cannot be told
            // apart, and one of them prints the whole file as a report of
            // matches. `-r` is how you ask for every record, and the sibling
            // refusal for -hash said so first.
            // 空的搜尋字串會匹配檔案裡的每一個儲存格。拒絕它的理由與「空的欄位清單」相同：
            // 「搜尋空字串」與「某個變數算成了空字串」無法區分，而其中一種會把整個檔案當成
            // 「命中報告」印出來。要每一筆請用 `-r`，而 -hash 那條同輩的拒絕先說了這件事。
            if needle.isEmpty {
                throw usageError(
                    "-contains was given an empty string, which matches every cell. Searching for nothing cannot be told from a variable that came out empty; use -r to read every record",
                    "-contains 收到一個空字串，而它會匹配每一個儲存格。「搜尋空字串」與「某個變數算成了空字串」無法區分；要讀每一筆請用 -r")
            }
            o.contains = needle
        case "filter": o.filter = true
        case "include-headers": o.includeHeaders = true
        case "normalize": o.normalize = true
        // `contextGiven` rather than `after > 0 || before > 0`: the output SHAPE
        // must not depend on the NUMBER. `-A 0` left the locating report in
        // place while `-A 1` switched to records, so a script writing
        // `-A "$N"` got one of two incompatible formats depending on a
        // variable -- TAB-separated report against CSV, at rc=0, with nothing
        // said. That is the mistake the README opens with, reached through a
        // flag interaction.
        // 用 `contextGiven`，而不是 `after > 0 || before > 0`：輸出的「形狀」不該取決於那個
        // 「數字」。`-A 0` 會讓定位報告留著，而 `-A 1` 會切成紀錄形狀，於是一支寫
        // `-A "$N"` 的腳本，會依一個變數拿到兩種不相容的格式——TAB 分隔的報告對上 CSV，
        // rc=0，什麼也不說。那正是 README 開頭那個錯誤，只是經由一次旗標互動抵達。
        case "A": o.after = try nonNegativeInt(arg, try need(arg)); o.contextGiven = true
        case "B":
            o.before = try nonNegativeInt(arg, try need(arg))
            o.beforeFlag = "-B"; o.contextGiven = true
        case "C":
            let n = try nonNegativeInt(arg, try need(arg))
            o.after = n; o.before = n; o.beforeFlag = "-C"; o.contextGiven = true
        case "head": try once("-head"); o.head = try positiveInt(arg, try need(arg))
        case "tail": try once("-tail"); o.tail = try positiveInt(arg, try need(arg))
        case "mid": try once("-mid"); o.mid = try parseMid(try need(arg))
        case "t": o.withHeader = true
        case "rownum": o.rownum = true
        case "physical": o.physical = true
        case "a1": o.a1 = true
        case "i": try once("-i"); o.input = try need(arg)
        case "o": try once("-o"); o.output = try need(arg)
        case "si": o.useStdin = true
        case "so": o.useStdout = true
        case "in-place": o.inPlace = true
        case "headers": try once("--headers"); o.headersOverride = try intVal(arg, try need(arg))
        case "md": o.markdown = true
        case "pretty": o.pretty = true
        case "json": o.json = true
        case "json-ascii": o.json = true; o.jsonASCII = true
        case "md-table": try once("--md-table"); o.mdTable = try intVal(arg, try need(arg))
        // Each clears the other so the LAST one wins -- which is what made
        // giving both a silent, order-dependent choice. The pair is refused in
        // validate(), and it can only see that both were given if the parse
        // stops erasing the evidence: `langGiven` counts the flags, not the
        // state they leave behind.
        // 兩者互相清除，於是「後面那個贏」——而那正是「兩個都給」變成一個安靜、且與順序有關的
        // 選擇的原因。這一對在 validate() 裡被拒絕，而它要看得見「兩個都給了」，解析就不能把
        // 證據抹掉：`langGiven` 數的是旗標，不是它們留下的狀態。
        case "zh": o.zh = true; o.enOnly = false; o.langFlags += 1; o.sawZh += 1
        case "en": o.enOnly = true; o.zh = false; o.langFlags += 1; o.sawEn += 1
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
            // The upper bound of the documented `1..N` was enforced and the
            // lower was not. `-insert 0` and `-insert -1` exited 0 with the
            // file byte-for-byte unchanged, nothing on stderr, and `-log`
            // recording `wrote 2 records, 3 fields, atomic rename OK` -- an
            // audit entry corroborating a write that never included the row.
            // In a batch it dropped its own row and applied the others,
            // producing a partial result at rc=0.
            //
            // Every sibling verb already refused zero: -delete, -head, -tail,
            // -mid, -update. This one verb did not, and it is the one that
            // WRITES.
            //
            // 文件寫的 `1..N`，上界有檢查，下界沒有。`-insert 0` 與 `-insert -1` 都以 0
            // 結束，檔案逐位元未變、stderr 空無一物，而 `-log` 記著
            // `wrote 2 records, 3 fields, atomic rename OK`——一筆替「從未包含那一列的寫入」
            // 作證的稽核紀錄。在批次裡它會丟掉自己那一列、套用其餘的，產生一個部分完成的
            // 結果，rc=0。
            //
            // 每一個同輩動詞早就拒絕 0 了：-delete、-head、-tail、-mid、-update。
            // 只有這一個沒有——而它正是會「寫入」的那一個。
            guard at >= 1 else {
                throw usageError(
                    "-insert \(at): a record number must be at least 1; records are numbered from 1, and -insert puts a row BEFORE record N",
                    "-insert \(at)：紀錄編號至少要是 1；紀錄從 1 開始編號，而 -insert 是把一列放在第 N 筆「之前」")
            }
            let row = try needData(arg)
            if o.cellModifier {
                // The names were `status_notes` and `license` -- two columns
                // from this project's own fixture, printed at anyone whose
                // file has neither. It read as a report about the file that
                // was passed, and on a one-column file it named two columns
                // that do not exist. An illustration has to be visibly an
                // illustration when the message cannot see the file.
                // 原本寫的是 `status_notes` 與 `license`——本專案自己 fixture 裡的兩個欄名，
                // 卻被印給一個「兩個都沒有」的使用者看。它讀起來像是在描述「你傳進來的那個
                // 檔案」，而在一個單欄檔案上，它指名了兩個不存在的欄位。當訊息看不到那個檔案時，
                // 舉例就必須「看得出來是舉例」。
                throw usageError(
                    "-insert -cell does not exist: inserting a cell mid-record pushes every later field one column along, so the value in column 5 would end up under the name of column 6, and so on to the end of the row. To add a column, every record and both header rows have to change together.",
                    "沒有 -insert -cell：在一列中間插入儲存格，會把該列後面的欄位全部往後推一格，於是原本第 5 欄的值會跑到第 6 欄的名字底下，並一路推到該列結尾。要新增一欄，必須每一列與兩列標頭一起改。")
            }
            o.edits.append(.insert(at: at, row: row))
            o.cellModifier = false; o.colModifier = false
        case "append":
            o.edits.append(.append(row: try needData(arg)))
            o.cellModifier = false; o.colModifier = false
        case "delete":
            let spec = try need(arg)
            o.edits.append(try parseDelete(spec, cell: o.cellModifier, col: o.colModifier,
                                           argvTail: argv, index: i))
            o.cellModifier = false; o.colModifier = false
        case "get":
            try once("-get")
            let addr = try need(arg)
            // A header address is well-formed -- the locating report emits it --
            // and is simply not one any verb can act on. parseCellAddress says
            // so now, and says it identically for -get, -update and
            // -delete -cell: this used to be explained here and nowhere else,
            // so the same property had one account per verb and two of the
            // three blamed the shape of an address the tool had printed itself.
            // 標頭位址是格式正確的——定位報告就會產生它——它只是不是任何動詞能作用的位址。
            // 現在由 parseCellAddress 統一說明，而且 -get、-update、-delete -cell 說的
            // 是同一句：這段解釋過去只存在於這裡，於是同一個性質有三種說法，其中兩種
            // 怪罪的是「工具自己印出來的位址」的形狀。
            o.getCell = try parseCellAddress(addr, flag: arg)
            o.cellModifier = false; o.colModifier = false
        case "update":
            let addr = try need(arg)
            let val = try needData(arg)
            let (r, c) = try parseCellAddress(addr, flag: arg)
            o.edits.append(.update(record: r, column: c, value: val))
            o.cellModifier = false; o.colModifier = false
        case "encrypt": try once("-encrypt"); o.encryptCols = try need(arg)
        case "decrypt": try once("-decrypt"); o.decryptCols = try need(arg)
        case "hash": try once("-hash"); o.hashCols = try need(arg)
        case "keyfile": try once("-keyfile"); o.keyfile = try need(arg)
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
        case "log": try once("-log"); o.logPath = try need(arg)
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
    // A modifier left over at the end never found a verb to attach to. It used
    // to be accepted and ignored: `csv2 -cell -r -i f.csv` exited 0, and
    // `csv2 -insert 1 'z,z,z' -cell` exited 0 as well -- because the refusal
    // for `-insert -cell` reads the modifier at the moment the verb is parsed,
    // so writing `-cell` AFTER the two positional arguments walks straight
    // past it. The refusal was positional, not semantic.
    //
    // This is the "swallowed option" failure this project already has on
    // record from multissh: a flag that changes nothing and says nothing, so
    // the caller believes they asked for something they did not.
    //
    // 留到最後的修飾符，代表它從未找到可以依附的動詞。原本它會被接受並忽略：
    // `csv2 -cell -r -i f.csv` 以 0 結束，而 `csv2 -insert 1 'z,z,z' -cell` 也是——因為
    // 「-insert 不可與 -cell 併用」那個拒絕，是在「解析到該動詞的那一刻」去讀修飾符的，
    // 於是把 `-cell` 寫在兩個位置參數之後就直接繞了過去。那個拒絕是位置性的，不是語意性的。
    //
    // 這正是本專案已經記錄過的、multissh 被咬過的那種「被吞掉的選項」：一個什麼都不改、
    // 也什麼都不說的旗標，於是呼叫端以為自己要求了一件他其實沒有要求到的事。
    if o.cellModifier || o.colModifier {
        let which = o.cellModifier ? "-cell" : "-col"
        throw usageError(
            "\(which) is a modifier and has no verb to modify here; it attaches to the -delete (or -insert) that FOLLOWS it, so `-delete 1:2 \(which)` is not the same as `-delete \(which) 1:2`",
            "\(which) 是修飾符，此處沒有可修飾的動詞；它依附在「其後」的 -delete（或 -insert）上，因此 `-delete 1:2 \(which)` 與 `-delete \(which) 1:2` 不是同一件事")
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
    // omittingEmptySubsequences: false, or "1:" splits into ONE part and every
    // check below that asks for two is skipped -- which is how `-get 1:`
    // reached "expected r:c" again after being given its own reason. Swift's
    // default drops empty pieces, and the empty piece is the thing being
    // diagnosed here.
    // 要 omittingEmptySubsequences: false，否則 "1:" 只會切成「一段」，下面每一個「需要兩段」
    // 的檢查都會被跳過——那正是 `-get 1:` 在有了自己的理由之後，又回到「需要 r:c」的原因。
    // Swift 的預設會丟掉空的片段，而這裡要診斷的正是那個空片段。
    let parts = s.split(separator: ":", maxSplits: 1,
                        omittingEmptySubsequences: false).map(String.init)
    // A header address gets the reason, not "expected r:c". The form IS r:c --
    // the locating report printed it -- and answering a well-formed address
    // with a complaint about its shape sends the reader to check their quoting.
    // -get has explained this properly for a while; -update and -delete -cell
    // said "expected r:c" about their own tool's output, so one property had
    // three accounts depending on which verb you asked.
    // 標頭位址要得到的是「理由」，不是「需要 r:c」。那個形式**就是** r:c——是定位報告印出來的
    // ——而用「格式不對」去回答一個格式正確的位址，會把讀者送去檢查自己的引號。-get 早就講清楚了，
    // 而 -update 與 -delete -cell 對著自家工具的輸出說「需要 r:c」：同一個性質，問哪個動詞就有
    // 哪一種說法，總共三種。
    if parts.count == 2, ["0", "0a", "0b"].contains(parts[0]), !parts[1].isEmpty {
        // "any verb, -get included" named -get inside a -update failure, which
        // reads as a bug in the message rather than a fact about the tool.
        // The fact is the same without the example.
        // 「任何動詞，-get 也不行」會在一則 -update 的失敗裡點名 -get，那讀起來像是訊息本身
        // 出了錯，而不是關於這個工具的一項事實。拿掉那個例子，事實不變。
        throw usageError("\(flag): \(s) names a header cell (the locating report prints 0 on a .csv and 0a/0b on a .csv2), and no verb can address one. Records are numbered from 1",
                         "\(flag)：\(s) 指的是標頭儲存格（定位報告在 .csv 上印 0，在 .csv2 上印 0a／0b），而沒有任何動詞可以對它定址。紀錄從 1 開始編號")
    }
    // An empty column part gets its own reason. `-get 1:` answered "expected
    // r:c", which is a complaint about shape when the shape is right and one
    // half is missing -- and a file really can have a column whose name is
    // empty, which is addressable, by its number.
    // 空的欄位部分有自己的理由。`-get 1:` 原本回答「需要 r:c」，那是在形狀正確、只是缺了
    // 一半時去挑剔形狀——而一個檔案確實可以有一個「名字是空的」欄位，它定址得到，用欄號。
    if parts.count == 2, Int(parts[0]) != nil, parts[1].isEmpty {
        throw usageError("\(flag): \(s) names no column -- the part after the colon is empty. A column whose NAME is empty is addressed by its number, as in 1:2",
                         "\(flag)：\(s) 沒有指名任何欄位——冒號之後是空的。名字為空的欄位請用欄號定址，例如 1:2")
    }
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
    // `-o` and `--in-place` are as exclusive as `-o` and `-so`, and only the
    // first pair was checked. Given both, `--in-place` was silently discarded:
    // the named -o file was written, the in-place target was left
    // byte-for-byte unchanged, and the log recorded the edit -- so a caller
    // who asked for an in-place edit got rc=0, an audit entry, and an
    // untouched file.
    // `-o` 與 `--in-place` 的互斥程度，和 `-o` 與 `-so` 完全一樣，而只有前一對被檢查了。
    // 兩者同時給出時，`--in-place` 會被靜默丟棄：-o 指名的檔案被寫出、就地編輯的目標逐位元
    // 未變，而 log 記下了那次編輯——於是一個要求「就地編輯」的呼叫端，得到的是 rc=0、
    // 一筆稽核紀錄，以及一個沒有被動過的檔案。
    if o.output != nil && o.inPlace {
        throw usageError("-o and --in-place are mutually exclusive: one names a destination and the other says the input IS the destination",
                         "-o 與 --in-place 互斥：一個指名了目的地，另一個說「輸入就是目的地」")
    }
    if o.useStdout && o.inPlace {
        throw usageError("-so and --in-place are mutually exclusive", "-so 與 --in-place 互斥")
    }
    // `--build-index --no-index` was refused as contradictory and
    // `--verify-index --no-index` was not: it read the sidecar `--no-index`
    // forbids and reported `index OK`. One of the two had to move, and the
    // refusal is the one that matches what --no-index says it means.
    // `--build-index --no-index` 會被當成互相矛盾而拒絕，`--verify-index --no-index` 不會：
    // 它讀了 `--no-index` 明令不讀的那個 sidecar，並回報 `index OK`。兩者必須有一個改變，
    // 而「拒絕」才是符合 --no-index 自己所宣稱的意思的那一個。
    // `--build-index` REPLACES the verb rather than joining it, so given both
    // the index was built and the edit was silently dropped -- rc=0, and with
    // `--in-place` nothing printed at all, while the caller believed a cell had
    // changed. `--build-index --no-index` was already refused as
    // contradictory; this pair is equally impossible and was not.
    // `--build-index` 是「取代」動詞而不是「加在旁邊」，因此兩者同時給出時，索引被建立了、
    // 而編輯被靜默丟棄——rc=0，搭配 `--in-place` 時甚至什麼都不印，而呼叫端以為某一格改了。
    // `--build-index --no-index` 早就被當成矛盾拒絕；這一對同樣不可能兩全，卻沒有。
    // A READ verb is dropped the same way an edit is, and that refusal covered
    // only edits -- the same rule applied to half of where it holds, which is
    // this project's most frequent defect and was mine to make here.
    //
    // `--build-index -contains X` exited 0 having searched nothing, which is
    // indistinguishable from "found nothing"; the README documents that as
    // rc=0 too. `--build-index -get 1:1` put `index built: 5 records ...` on
    // stdout, so the README's own `val=$(csv2 -get ...)` recipe writes that
    // sentence into a data cell, at rc=0.
    //
    // `-r` is excluded because it is also the default: refusing it would refuse
    // the ordinary `csv2 --build-index -i f.csv`, which is the whole point of
    // the flag. Nothing is dropped in that case -- there is no verb to drop.
    // 讀取動詞被丟棄的方式與編輯完全相同，而那條拒絕只涵蓋了編輯——同一條規則只套用到它成立
    // 之處的一半，那是本專案最常見的缺陷形狀，而這一次是我犯的。
    // `--build-index -contains X` 以 0 結束、什麼也沒搜尋，那與「什麼也沒找到」無法區分，
    // 而 README 記載後者同樣是 rc=0。`--build-index -get 1:1` 會把「index built: …」印到
    // stdout，於是 README 自己那句 `val=$(csv2 -get …)` 會把那句話寫進一個資料儲存格，rc=0。
    // `-r` 不列入，因為它同時也是預設值：拒絕它等於拒絕 `csv2 --build-index -i f.csv`
    // 這個最平常的用法，而那正是這個旗標的用途。那種情況下沒有任何東西被丟棄——沒有動詞可丟。
    // `-r` counts when it was TYPED. It is also the default, so it cannot be
    // read off `o.read` alone -- but a caller who wrote it asked for output and
    // got none, which is the same silent drop as any other verb. Round 61
    // found the flags this list missed: -r, --json, -md, and the two
    // administrative flags given together.
    // 只有「被打出來」的 `-r` 算數。它同時也是預設值，因此不能只看 `o.read`——但一個真的
    // 寫了它的呼叫端，要的是輸出、而拿到的是沒有輸出，那與其他任何動詞被靜默丟棄是同一件事。
    // 第 61 回合找出了這份清單漏掉的那些：-r、--json、-md，以及那兩個管理用旗標同時給出。
    let selectionVerb: String? =
        o.contains != nil ? "-contains" :
        o.getCell != nil ? "-get" :
        o.head != nil ? "-head" :
        o.tail != nil ? "-tail" :
        o.mid != nil ? "-mid" :
        o.read ? "-r" :
        o.json ? "--json" :
        o.markdown ? "-md" : nil
    // Two administrative flags together drop one of each other, which is the
    // same failure with no verb involved at all.
    // 兩個管理用旗標同時給出時，其中一個會被另一個丟棄——那是同一種失敗，而且完全不涉及動詞。
    if o.buildIndex && o.verifyIndex {
        throw usageError("--build-index and --verify-index cannot both run: each replaces the operation, so one of them would be dropped",
                         "--build-index 與 --verify-index 不能同時執行：兩者都是「取代」該操作，因此其中一個會被丟棄")
    }
    for (flag, on) in [("--build-index", o.buildIndex), ("--verify-index", o.verifyIndex)] where on {
        if !o.edits.isEmpty {
            throw usageError("\(flag) and an edit verb cannot both run: \(flag) replaces the operation rather than joining it, so the edit would be silently dropped",
                             "\(flag) 與編輯動詞不能同時執行：\(flag) 是「取代」該操作而不是「加在旁邊」，因此那個編輯會被靜默丟棄")
        }
        if let verb = selectionVerb {
            throw usageError("\(flag) and \(verb) cannot both run: \(flag) replaces the operation rather than joining it, so \(verb) would produce nothing while the run still exited 0",
                             "\(flag) 與 \(verb) 不能同時執行：\(flag) 是「取代」該操作而不是「加在旁邊」，因此 \(verb) 什麼也不會產出，而那次執行仍然以 0 結束")
        }
    }
    // `-get` prints ONE cell. A transform's output depends on a marker in the
    // file's header -- the salt for `:enc:`, the fingerprint for `:hmac:` --
    // and `-get` writes no header. So `-get -encrypt` emitted ciphertext with
    // no salt anywhere: bytes nothing can ever decrypt, at rc=0. `-get`
    // already refuses --json, --pretty, -t and -rownum as ignored flags, with
    // a good message; the transforms were not on that list.
    // `-get` 印的是「一格」。轉換的輸出依賴檔案標頭裡的標記——`:enc:` 的 salt、`:hmac:` 的
    // 指紋——而 `-get` 不寫標頭。於是 `-get -encrypt` 吐出的是「salt 不存在於任何地方」的
    // 密文：一段沒有任何東西還原得了的位元組，rc=0。`-get` 早就會拒絕 --json、--pretty、
    // -t、-rownum 這些「會被忽略的旗標」，訊息也寫得很好；只是轉換不在那張清單上。
    if o.getCell != nil, o.encryptCols != nil || o.hashCols != nil || o.decryptCols != nil {
        throw usageError("-get prints one cell and writes no header, so a transform's marker -- the salt for -encrypt, the fingerprint for -hash -- has nowhere to go; the output could never be read back",
                         "-get 印的是一格、不寫標頭，因此轉換的標記——-encrypt 的 salt、-hash 的指紋——沒有地方可放；那個輸出永遠讀不回來")
    }
    // Its three siblings -- --a1, --physical, --filter -- all refuse without
    // -contains. This one was ignored.
    // 它的三個同輩——--a1、--physical、--filter——在沒有 -contains 時都會拒絕。只有這一個被忽略。
    if o.includeHeaders && o.contains == nil {
        throw usageError("--include-headers searches the header rows, so it needs -contains",
                         "--include-headers 是「連標頭列一起搜尋」，因此它需要 -contains")
    }
    if o.verifyIndex && o.noIndex {
        throw usageError("--verify-index and --no-index contradict each other: verifying means reading the sidecar",
                         "--verify-index 與 --no-index 互相矛盾：驗證就是要讀那個 sidecar")
    }
    // Documented as refused in two places -- the flag entry and the refusals
    // table -- and refused in neither. It fired only when validation happened
    // to fail, so a healthy file took the combination at rc=0 and an unhealthy
    // one got a message about it; the flag's own entry says it plainly:
    // "Refused with -append, which can only add bytes."
    //
    // The reason is worth stating where the refusal lives. --truncate-partial
    // means "discard the incomplete final record". Appending cannot discard
    // anything -- it can only add bytes after what is already there -- so the
    // combination asks for two things that cannot both happen, and the file
    // that comes out keeps the incomplete record AND gains a complete one
    // after it.
    //
    // 文件在兩個地方說它被拒絕——旗標條目與拒絕表——而兩處都沒有真的拒絕。它只在「驗證剛好
    // 失敗」時才觸發，於是一個健康的檔案會以 rc=0 接受這個組合，不健康的才會拿到訊息；
    // 而旗標自己的條目寫得很清楚：「與 -append 併用時被拒絕，後者只會增加位元組」。
    //
    // 理由值得寫在「拒絕」發生的地方。--truncate-partial 的意思是「丟掉不完整的最後一筆」，
    // 而追加沒有辦法丟掉任何東西——它只能在既有內容之後加上位元組——因此這個組合要求的兩件事
    // 不可能同時成立，而產生出來的檔案會同時保留那筆不完整的、並在其後多出一筆完整的。
    if o.truncatePartial, o.edits.contains(where: { if case .append = $0 { return true }; return false }) {
        throw usageError(
            // "the incomplete record" said there is one. This refusal fires on
            // the flags alone, before the file is read, so it fires on
            // complete files too and sent readers hunting for damage that was
            // not there. The two flags are incompatible as a REQUEST -- one
            // says drop the tail, the other can only add to it -- and that is
            // true whatever the file turns out to be.
            // 「那筆不完整的紀錄」等於說「有一筆」。這條拒絕只看旗標、在讀檔之前就觸發，
            // 因此對完整的檔案也會觸發，於是讓讀者去找一個並不存在的損壞。這兩個旗標
            // 作為一個「要求」就是不相容的——一個說丟掉尾巴，另一個只能往尾巴後面加——
            // 而那句話不論檔案後來是什麼樣子都成立。
            "--truncate-partial is refused with -append, whatever the file contains: one says discard an incomplete last record and the other can only add bytes after it, so the two cannot both be honoured in one run. If the file does have a torn tail, write a clean copy first (csv2 -r -t --truncate-partial -i FILE -o CLEAN) and append to that",
            "--truncate-partial 與 -append 併用會被拒絕，不論檔案內容為何：一個說「丟掉不完整的最後一筆」，另一個只能在它後面加上位元組，兩者無法在同一次執行中同時被滿足。若那個檔案確實有一條撕裂的尾巴，請先寫出一份乾淨的複本（csv2 -r -t --truncate-partial -i FILE -o CLEAN），再對那一份追加")
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
    if o.contextGiven {
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
    // The destination is not the only OTHER file a run touches. This guard
    // compared -i against -o and nothing else, and the document described that
    // comparison in detail -- spellings, symlinks, (device, inode), a
    // POSIX-only caveat -- while never saying which files it does not cover.
    // Three of them destroy data at rc=0 with both streams empty:
    //
    //   -o naming the KEYFILE           the ciphertext is written over the only
    //                                   copy of the key that decrypts it, and
    //                                   nothing is left to report it with
    //   -o naming the -log file         the audit trail for that very run is
    //                                   renamed away by the run it records
    //   -log naming the INPUT           the invocation line is appended into
    //                                   the file being read, which then fails
    //                                   its own field-count check for ever
    //
    // Each is a run that "did what it was told". The remedy is the comparison
    // that already exists, asked three more times.
    //
    // 目的地不是一次執行會碰到的唯一「另一個檔案」。這道守衛只比對 -i 與 -o，而文件把那次
    // 比對描述得非常仔細——拼法、symlink、(device, inode)、僅限 POSIX 的但書——卻從未說出它
    // 「沒有涵蓋」哪些檔案。其中三種會以 rc=0、兩條輸出流皆空的方式毀掉資料：`-o` 指向金鑰檔
    // （密文蓋掉唯一能解開它的那把金鑰）、`-o` 指向 -log 檔（那次執行把自己的稽核軌跡改名蓋掉）、
    // `-log` 指向輸入（呼叫紀錄被追加進正在被讀的那個檔案，於是它從此過不了自己的欄數檢查）。
    // 補救方式，就是把那個已經存在的比對再問三次。
    if let out = o.output, let kf = o.keyfile, sameFile(out, kf) {
        throw usageError(
            "-o \(out) is the keyfile; writing there destroys the only key that can decrypt what is being written",
            "-o \(out) 就是那個金鑰檔；寫到那裡會毀掉「唯一能解開正在被寫出的東西」的那把金鑰")
    }
    if let inp = o.input, let kf = o.keyfile, sameFile(inp, kf), o.inPlace {
        throw usageError(
            "-keyfile \(kf) is the input, and this run edits it in place; the key would be rewritten as CSV",
            "-keyfile \(kf) 就是輸入檔，而這次執行會就地編輯它；那把金鑰會被當成 CSV 重寫")
    }
    if let inp = o.input, let out = o.output, sameFile(inp, out), !o.inPlace {
        // Compared after resolving, not as typed. `-o ./data.csv` and
        // `-o link-to-data.csv` name the same file as `-i data.csv` and used to
        // slip past this, which mattered because the two are NOT equivalent:
        // only --in-place keeps a symlink and carries the original mode.
        //
        // The reason given here used to be "opening the output truncates it
        // before the input has been read". That is not true of this program --
        // -o writes a temp file and renames (T43e), so nothing is truncated and
        // the data survives. A refusal that explains itself with a danger the
        // code does not have teaches the reader something false about the tool.
        // The real reason is that this is an in-place edit written the long way
        // round, and the flag for it does more.
        // 比較的是解析過的路徑，不是打出來的字串。`-o ./data.csv` 與
        // `-o 指向 data 的連結` 都與 `-i data.csv` 是同一個檔案，過去都能繞過這條拒絕；
        // 而那是有差別的：只有 --in-place 會保留 symlink 並帶過原本的模式。
        //
        // 這裡原本的理由是「開啟輸出會在輸入讀完前把它截斷」。那對這支程式不成立——
        // -o 走的是暫存檔 + rename（T43e），沒有東西被截斷，資料也不會遺失。一條用
        // 「程式並不存在的危險」來解釋自己的拒絕，會讓讀者學到關於這支工具的錯誤知識。
        // 真正的理由是：這就是一次就地編輯，只是繞遠路寫，而那個旗標做的事更多。
        throw usageError("-i and -o name the same file; that is an in-place edit, so use --in-place, which also keeps a symlink pointing where it did and leaves the file's permissions as they were.",
                         "-i 與 -o 指向同一個檔案；那就是一次就地編輯，請用 --in-place——它還會讓 symlink 繼續指向原處，並保留該檔案原本的權限。")
    }
    if o.inPlace {
        guard let inp = o.input else {
            throw usageError("--in-place needs -i FILE", "--in-place 需要 -i FILE")
        }
        // A SELECTION is not an edit, and --in-place is the edit destination.
        //
        // `csv2 -head 1 -t -i f.csv --in-place` used to succeed: it wrote the
        // selection back over the input, so a 22-record file became a
        // 1-record file at rc=0, with nothing on either stream and -- because
        // the outcome line belongs to the edit path -- nothing in the log
        // either but the invocation. The README points an auditor at that
        // line to ask whether a write landed, so the most destructive
        // operation in the tool was also its least audited one.
        //
        // What stood between a caller and that was `-t`, a flag about
        // HEADERS: without it the write is refused because a headerless file
        // would lie about its format. A safety property resting on a
        // formatting flag is a property nobody chose.
        //
        // Refused rather than warned, because on this path a mistyped flag
        // and a deliberate crop produce the same bytes and the same rc. To
        // crop a file, write the selection to a new file; that is one more
        // command and it cannot be arrived at by accident.
        //
        // 選取不是編輯，而 --in-place 是「編輯」的目的地。
        //
        // `csv2 -head 1 -t -i f.csv --in-place` 原本會成功：它把那個選取寫回輸入，於是一個
        // 22 筆的檔案變成 1 筆，rc=0，兩條輸出流上什麼也沒有，而且——因為那行「結果」屬於
        // 編輯路徑——log 裡除了「呼叫」之外也什麼都沒有。README 叫稽核者去看那一行來判斷
        // 「這次寫入到底有沒有落地」，於是這個工具最具破壞性的操作，同時是它最少被稽核的。
        //
        // 擋在呼叫端與這件事之間的是 `-t`，一個關於「標頭」的旗標：沒有它，那次寫入會因為
        // 「無標頭的檔案會對自己的格式說謊」而被拒絕。一個建立在格式旗標上的安全性質，
        // 是沒有人選擇過的性質。
        //
        // 選擇拒絕而不是警告，因為在這條路徑上「打錯一個旗標」與「刻意裁切」產生的位元組
        // 與 rc 完全相同。要裁切一個檔案，請把選取寫到新檔案：那多一個指令，而它不會被
        // 誤打誤撞地做出來。
        // The test is "is a SELECTION present", not "is an edit verb absent".
        //
        // Those are different predicates, and the first version of this guard
        // used the second: `-head 1 -hash license -i f.csv --in-place` has an
        // edit verb of a kind, so the guard did not fire, and it left one
        // record of six at rc=0 with nothing on either stream -- the very
        // failure this block was added to stop, one flag away from the command
        // it does stop. `-encrypt`, `-decrypt` and `-hash` all reach it, and
        // the `-decrypt` form destroys ciphertext and the header salt
        // together, which this document says nobody can ever recover.
        //
        // A transform with no selection is still allowed: `-r -hash col
        // --in-place` rewrites every record and discards none, which is what
        // in-place protection is FOR.
        //
        // 判斷的是「有沒有選取」，不是「有沒有編輯動詞」。
        //
        // 那是兩個不同的謂詞，而這道守衛的第一版用的是後者：`-head 1 -hash license -i f.csv
        // --in-place` 有一個「算是編輯」的動詞，於是守衛沒有觸發，六筆只剩一筆，rc=0，兩條
        // 輸出流上什麼也沒有——正是這個區塊當初要擋下的那個失敗，而它離「確實被擋下的那個
        // 指令」只差一個旗標。`-encrypt`、`-decrypt`、`-hash` 都到得了，而 `-decrypt` 那個
        // 形式會把密文與檔頭裡的鹽一起銷毀，而本文件說那是任何人都再也救不回來的。
        //
        // 「有轉換、沒有選取」仍然允許：`-r -hash col --in-place` 會重寫每一筆、不丟掉任何
        // 一筆，而那正是「就地保護」存在的用途。
        let selecting = o.head != nil || o.tail != nil || o.mid != nil || o.contains != nil
        let transforming = o.encryptCols != nil || o.decryptCols != nil || o.hashCols != nil
        if selecting || (o.edits.isEmpty && !transforming) {
            let verb = o.head != nil ? "-head" : o.tail != nil ? "-tail"
                     : o.mid != nil ? "-mid" : o.contains != nil ? "-contains" : nil
            // Two different true sentences. A selection DISCARDS what it did
            // not name; a bare `-r` names everything, so saying it discards
            // records would be a message that is wrong about the command it
            // is refusing -- and a refusal explaining itself with a danger the
            // program does not have teaches the reader something false about
            // the tool, which is the note already written beside the -i/-o
            // refusal above.
            // 兩句各自為真的話。一個「選取」會丟掉它沒有指名的東西；而單獨的 `-r` 指名了
            // 全部，因此說它會丟掉紀錄，會是一則「對自己正在拒絕的那個指令說錯話」的訊息
            // ——而一條用「程式並不存在的危險」來解釋自己的拒絕，會讓讀者學到關於這支工具的
            // 錯誤知識，那正是上面 -i/-o 那條拒絕旁邊已經寫下的註記。
            if let v = verb {
                // "would discard every record it does not name" was the
                // reason, and it is not true of every run this refuses: `-mid
                // ,` and `-head 99` on a short file name every record there
                // is. A refusal whose stated reason is false of the command in
                // front of it teaches the reader something false about the
                // tool -- the note beside the -i/-o refusal above says the
                // same thing. What IS true of all of them is the shape: a
                // selection is not an edit, and the count of records it names
                // is not knowable before the file is read.
                // 「會丟掉它沒有指名的每一筆」原本是那個理由，而它對這條拒絕所擋下的每一次
                // 執行並不都成立：`-mid ,` 與短檔案上的 `-head 99` 指名了所有紀錄。一條
                // 「理由對眼前這個指令為假」的拒絕，會讓讀者學到關於這個工具的錯誤知識——
                // 上面 -i/-o 那條拒絕旁邊的註記說的正是同一件事。對它們全部都成立的是那個
                // 形狀：選取不是編輯，而它指名幾筆，要讀完檔案才知道。
                throw usageError(
                    "\(v) selects records and --in-place writes an EDIT back to its input; a selection is not an edit. Whether this one would have discarded anything is not knowable before the file is read, which is why it is refused rather than measured. Write it to a new file instead: csv2 \(v) ... -t -i \(inp) -o NEW.csv",
                    "\(v) 是「選取」，而 --in-place 是把一次「編輯」寫回它的輸入；選取不是編輯。這一次究竟會不會丟掉東西，在讀完檔案之前是無從得知的——那正是它被「拒絕」而不是被「衡量」的理由。請改寫到新檔案：csv2 \(v) ... -t -i \(inp) -o NEW.csv")
            }
            throw usageError(
                "--in-place applies an EDIT to its input, and this run has none: reading the file and writing it back over itself changes nothing. To repair or rewrite a file -- --truncate-partial, a format change -- write it to a new file: csv2 -r -t ... -i \(inp) -o NEW.csv",
                "--in-place 是把一次「編輯」套用到它的輸入上，而這次執行沒有編輯：把檔案讀出來再寫回它自己，什麼也不會改變。要修復或重寫一個檔案——--truncate-partial、格式轉換——請寫到新檔案：csv2 -r -t ... -i \(inp) -o NEW.csv")
        }
        // Resolved through symlinks, because `--in-place` means "edit this
        // file" and a symlink is not the file. Writing to the link's own path
        // made the temp-file-and-rename REPLACE the link with a regular file
        // and leave the target byte-for-byte unchanged -- rc=0, the link gone,
        // and the data the caller meant to edit untouched.
        //
        // Only the OUTPUT is resolved. The input keeps the path the caller
        // typed, so messages name the file they asked about rather than one
        // they have never seen.
        //
        // 解析 symlink，因為 `--in-place` 的意思是「編輯這個檔案」，而一個 symlink 不是那個
        // 檔案。寫到連結自身的路徑上，會讓「暫存檔 + rename」把連結「換成」一個一般檔案，
        // 而目標檔逐位元未變——rc=0、連結不見了、而呼叫端本來要改的資料沒有被動到。
        //
        // 只有「輸出」被解析。輸入保留呼叫端打出來的路徑，好讓訊息指名的是他問的那個檔案，
        // 而不是一個他從未見過的。
        if o.output == nil {
            o.output = resolved(inp)
        }
    }
    // The same rule on the other half. `-o` reaches its destination by
    // temp+rename too, so writing to a symlink's own path REPLACES the link
    // with a regular file and leaves the target byte-for-byte unchanged, at
    // rc=0 -- the shell's `>` follows the link and writes through it, which is
    // what a caller has every reason to expect. DP settled this for --in-place
    // and this is where the same sentence also applies.
    // 同一條規則的另一半。`-o` 也是以暫存檔 + rename 抵達目的地，因此寫到一個 symlink
    // 自身的路徑上，會把連結換成一般檔案，而目標檔逐位元未變、rc=0——shell 的 `>` 是
    // 跟著連結走、寫進目標的，而呼叫端完全有理由那樣預期。DP 為 --in-place 定下了這件事，
    // 而這裡是同一句話同樣成立的地方。
    // An empty -o is a variable that came out empty, and it resolves to the
    // current directory: the temp file then lands in the PARENT of where the
    // caller meant to write, and the failure arrives as a raw rename errno
    // quoting the internal temp filename -- not the documented two-line
    // refusal that the same condition (`-o adir`) produces one line below.
    // 空的 -o 是一個「算成了空字串」的變數，而它會解析成目前目錄：暫存檔於是落在呼叫端本來
    // 想寫的地方的「上一層」，而失敗是以一個原始的 rename errno 抵達、還引用了內部暫存檔名
    // ——而不是同一個條件（`-o adir`）在下面一行所產生的、有記載的那兩行拒絕。
    if let out = o.output, out.isEmpty {
        throw usageError("-o is empty; name a file, or use -so to write to a stream",
                         "-o 是空的；請指名一個檔案，或用 -so 寫到串流")
    }
    if !o.inPlace, let out = o.output {
        // Before resolving, because this message has to name the path the
        // caller typed. `-o` writes a temp file beside the destination and
        // renames it, which needs a directory entry that can be replaced --
        // a device, a FIFO or a directory cannot. The README has documented
        // this refusal ("Use -so") since before it existed: what actually
        // happened was "cannot create temporary file beside /dev/fd/1", a
        // failure that names neither the cause nor the way out, and a path the
        // caller never typed.
        // 在解析之前做，因為這則訊息必須指名「呼叫端打出來的那個路徑」。`-o` 是在目的地旁邊
        // 寫暫存檔再 rename，那需要一個「可以被取代的目錄項目」——裝置、FIFO 或目錄都不是。
        // README 從這條拒絕存在之前就寫著它（「請改用 -so」）：實際會發生的是「無法在
        // /dev/fd/1 旁建立暫存檔」，那既沒說原因、也沒說出路，而且指的是一個呼叫端從來沒有
        // 打過的路徑。
        if let k = Platform.fileKind(path: out), k != .regular {
            let kind = k == .directory ? "a directory" : k == .fifo ? "a FIFO" : "not a regular file"
            // The Chinese read "是不是一般檔案" -- "is is not a regular file" --
            // because the sentence supplies 是 and this arm supplied it again.
            // 中文原本讀成「是不是一般檔案」，因為句子已經給了「是」，而這一支又給了一次。
            let kindZh = k == .directory ? "一個目錄" : k == .fifo ? "一個 FIFO" : "一個裝置或其他非一般檔案"
            throw usageError(
                "-o \(out) is \(kind); -o writes a temp file beside the destination and renames it, which needs a regular file. Use -so to write to a stream",
                "-o \(out) 是\(kindZh)；-o 會在目的地旁邊寫暫存檔再 rename，那需要一個一般檔案。要寫到串流請用 -so")
        }
        // The directory has to accept a new file, because that is where the
        // temp file goes. Checked before resolving so the message names what
        // was typed: `-o /dev/stdout` with stdout redirected to a file
        // resolves to /dev/fd/1, and the failure that used to come out of the
        // sink named /dev/fd/1 -- a path the caller never wrote -- with "No
        // such file or directory" as the cause, which was not the cause.
        // 那個目錄必須容得下一個新檔案，因為暫存檔就寫在那裡。在解析之前檢查，好讓訊息
        // 指名「打出來的那個路徑」：`-o /dev/stdout` 在 stdout 被導向檔案時會解析成
        // /dev/fd/1，而原本由 sink 拋出的失敗指的就是 /dev/fd/1——一個呼叫端從未寫過的路徑
        // ——並以「No such file or directory」作為原因，而那並不是原因。
        let dir = (out as NSString).deletingLastPathComponent
        let dirName = dir.isEmpty ? "." : dir
        if !Platform.directoryAcceptsNewFiles(dir) {
            // A missing directory and an unwritable one need different
            // sentences: "use -so" is the answer to /dev, and nonsense in
            // reply to a typo.
            // 「目錄不存在」與「目錄不可寫」需要不同的句子：「請用 -so」是 /dev 的答案，
            // 拿來回答一個打錯的路徑則毫無意義。
            if Platform.fileKind(path: dirName) == nil {
                throw usageError("-o \(out): the directory \(dirName) does not exist",
                                 "-o \(out)：目錄 \(dirName) 不存在")
            }
            throw usageError(
                "-o \(out): a new file cannot be created in \(dirName), and -o needs one there for the temp file it renames into place. Use -so to write to a stream",
                "-o \(out)：在 \(dirName) 裡建不了新檔案，而 -o 需要在那裡放一個「稍後 rename 就位」的暫存檔。要寫到串流請用 -so")
        }
        o.output = resolved(out)
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
                // Two remedies were offered as equals and they are not.
                // Dropping --headers reads the file as it is. RENAMING makes
                // the suffix agree with --headers, and a `.csv2` renamed to
                // `.csv` then has its second header row read as data record 1
                // -- at rc=0, output that looks entirely plausible, and one
                // record more than the file has. A blind round followed the
                // rename because the message recommended it, and only caught
                // it by diffing record counts afterwards.
                // 兩條建議被並列成等價的，而它們不是。拿掉 --headers 是照檔案原本的樣子讀它；
                // 「改檔名」是讓副檔名去遷就 --headers，而一個 `.csv2` 改名成 `.csv` 之後，
                // 它的第二列標頭會被當成第 1 筆資料——rc=0、輸出看起來完全合理、而紀錄數比
                // 檔案實際多一筆。一個盲測回合照著這條建議去改檔名，事後靠比對紀錄數才發現。
                "\(inp) declares \(fmt.headerRows) header row(s) by its suffix, but --headers says \(h). The suffix declares the format; --headers is for input with no suffix to declare it. Drop --headers to read the file as it is. Renaming it instead makes the suffix agree with --headers, which is NOT the same thing: a header row then becomes data record 1, at rc=0, and nothing afterwards can tell it was one",
                "\(inp) 的副檔名宣告了 \(fmt.headerRows) 列標頭，但 --headers 說 \(h) 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請拿掉 --headers，照這個檔案原本的樣子讀它。改檔名是讓副檔名去遷就 --headers，那不是同一件事：一列標頭會因此變成第 1 筆資料，rc=0，而事後沒有任何東西看得出它曾經是標頭")
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
    if let out = o.output, let outFmt = Format.from(path: out),
       !(o.input?.lowercased().hasSuffix(".md") ?? false) {
        // A `.md` input is skipped HERE and checked in openInput instead. This
        // guard runs at parse time, before any file is opened, and how many
        // header rows a Markdown table has is a property of its first line --
        // it cannot be known from the name. Answering 1 by default said "the
        // input has 1 header row(s)" about a table rendered from a .csv2 that
        // has two, which is a false sentence in the one place a reader is
        // being told what their file is.
        // `.md` 輸入在**這裡**跳過，改在 openInput 檢查。這道守衛在解析參數時執行，那時任何檔案都
        // 還沒被開啟，而「一張 Markdown 表有幾列標頭」是它第一行的性質——從名字看不出來。預設回答
        // 1，會對一張「從有兩列標頭的 .csv2 算繪出來」的表說「輸入有 1 列標頭」，而那是一句假話，
        // 出現在「正要告訴讀者他的檔案是什麼」的那一個地方。
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
        // One flag or two, and the sentence has to read correctly either way.
        // Sharing a plural verb made `--a1 add to the address`, which reads as
        // though one flag were several -- a small thing that tells the reader
        // the message was assembled rather than written.
        // 一個旗標或兩個，這句話兩種情況都必須讀得通。共用一個複數動詞會造出
        // 「--a1 add to the address」，讀起來像是一個旗標卻用了複數——小事，但它會告訴讀者
        // 這句話是「拼出來的」，不是「寫出來的」。
        let flags = [o.physical ? "--physical" : nil, o.a1 ? "--a1" : nil].compactMap { $0 }
        let which = flags.joined(separator: " and ")
        let verb = flags.count > 1 ? "add" : "adds"
        let need = flags.count > 1 ? "they need" : "it needs"
        throw usageError(
            "\(which) \(verb) to the address in the locating report, so \(need) -contains without --filter, -md or --json",
            "\(which) 是附加在定位報告的位址上的，因此需要搭配 -contains，且不能同時給 --filter、-md 或 --json")
    }
    // -rownum adds a COLUMN, and --json names its fields rather than counting
    // them, so there is nowhere in a JSON object for a generated position to
    // go. It was accepted and dropped: no rownum key, `fields` unchanged,
    // rc=0. That is the same silence `--a1` and `--physical` are refused for
    // three lines up, and the same one `-get` refuses -rownum for BY NAME --
    // with the explicit reason that it would be ignored.
    // -rownum 加的是一個「欄」，而 --json 是替欄位命名而不是數位置，因此一個「生成的位置」
    // 在 JSON 物件裡無處可去。它原本會被接受然後丟掉：沒有 rownum 鍵、fields 不變、rc=0。
    // 那與三行之上 `--a1`、`--physical` 被拒絕的沉默是同一種，也與 `-get` 明文以「它會被
    // 忽略」為由拒絕 -rownum 的那一種相同。
    // --en and --zh choose which header row names the columns, so giving both
    // is a request with two answers. The last one silently won, order-
    // dependent, at rc=0 -- and this tool refuses `--headers 1 --headers 2`
    // with a message arguing that taking the last one silently is how
    // `-hash note -hash ver` leaves note in plaintext. Same hazard, and it was
    // handled two different ways.
    // --en 與 --zh 決定的是「由哪一列標頭來命名欄位」，因此兩個都給等於一個有兩個答案的要求。
    // 原本是「後面那個安靜地贏」，與順序有關，rc=0——而這個工具拒絕 `--headers 1 --headers 2`
    // 時所給的理由，正是「安靜地取最後一個，就是 `-hash note -hash ver` 把 note 留在明文的
    // 那條路」。同一類危險，卻用了兩種不同的處理方式。
    if o.langFlags > 1 {
        // Two different flags and the same flag twice are different mistakes,
        // and the message has to be true of the one in front of it -- the same
        // note that stands beside the -i/-o and --in-place refusals.
        // 「兩個不同的旗標」與「同一個旗標給兩次」是兩種不同的錯誤，而訊息必須對眼前這一個
        // 為真——與 -i/-o、--in-place 那兩條拒絕旁邊的註記是同一件事。
        if o.sawEn > 0 && o.sawZh > 0 {
            throw usageError("--en and --zh both choose which header row names the columns; give one",
                             "--en 與 --zh 都在決定「由哪一列標頭命名欄位」；請只給一個")
        }
        let f = o.sawEn > 1 ? "--en" : "--zh"
        throw usageError("\(f) is given more than once; a repeated flag is refused rather than taken once, because the second one may have been meant to change something",
                         "\(f) 給了不只一次；重複的旗標會被拒絕而不是「只取一次」，因為第二個很可能是想改變什麼")
    }
    if o.rownum && o.json {
        throw usageError(
            "-rownum adds a column and --json names fields instead of numbering them, so it would be ignored; --json already carries the record number in its `record` key",
            "-rownum 加的是一欄，而 --json 是替欄位命名、不是替它們編號，因此它會被忽略；--json 本來就以 `record` 鍵帶著紀錄號")
    }
    if o.contains == nil && o.filter && o.edits.isEmpty {
        throw usageError("--filter needs -contains", "--filter 需要搭配 -contains")
    }
    // --normalize decides how a SEARCH compares, and nothing else reads it.
    // Without -contains it was accepted and did nothing, while its two
    // neighbours in the same section -- --filter and --include-headers --
    // are both refused for exactly that. The rule this project keeps
    // rediscovering is that a flag the caller passed and the tool discarded is
    // indistinguishable from a flag that does not work.
    // --normalize 決定的是一次「搜尋」怎麼比較，沒有別的東西會讀它。沒有 -contains 時它會被
    // 接受然後什麼也不做，而同一節裡它的兩個鄰居——--filter 與 --include-headers——都正是為此
    // 被拒絕。這個專案一再重新發現的那條規則是：一個呼叫端給了、而工具丟棄了的旗標，與一個
    // 「壞掉的旗標」無從分辨。
    if o.normalize && o.contains == nil {
        throw usageError("--normalize decides how -contains compares, so it needs -contains; storage is never normalised",
                         "--normalize 決定的是 -contains 怎麼比較，因此需要搭配 -contains；儲存的內容永遠不會被正規化")
    }
    // An output SHAPE with an edit verb. An edit writes CSV -- that is what it
    // is for -- so --json and -md were accepted, ignored and exited 0, while
    // --a1 in the same position was refused and -md without -t on an edit was
    // refused for a different reason entirely. Three flags on one axis, three
    // behaviours.
    //
    // Refusing rather than honouring: writing a Markdown table to a .csv path
    // would produce a file this tool then refuses to read, which is the
    // failure the format rules exist to prevent.
    // 一個「輸出形狀」旗標與一個編輯動詞併用。編輯寫出的是 CSV——那正是它的用途——因此
    // --json 與 -md 被接受、被忽略、以 0 結束，而同一個位置的 --a1 會被拒絕，`-md` 少了 -t
    // 又會因為完全不同的理由被拒絕。同一個軸上的三個旗標，三種行為。
    // 選擇「拒絕」而不是「照做」：把一張 Markdown 表格寫進 .csv 路徑，會產生一個這支工具
    // 隨後拒絕讀取的檔案，而那正是格式規則要防止的失敗。
    if !o.edits.isEmpty || o.encryptCols != nil || o.decryptCols != nil || o.hashCols != nil {
        let shape = o.json ? "--json" : (o.markdown ? "-md" : nil)
        if let shape = shape {
            throw usageError(
                "\(shape) is an output shape and an edit writes CSV, so the two cannot be combined. Read with \(shape) in a separate run",
                "\(shape) 是一種輸出形狀，而編輯寫出的是 CSV，兩者不能併用。要用 \(shape) 讀，請另外執行一次")
        }
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
        // A number that is ALSO a column name is a guess waiting to happen.
        // The file `2,1` has a column named "2" at position 1 and one named
        // "1" at position 2; `-hash 2` took position 2 and hashed the column
        // called "1", at rc=0 with nothing on stderr. The caller asked for a
        // name they can see in the header and got a different column.
        //
        // Refused for the same reason two columns with one name are refused,
        // decided on 2026-08-18: picking one for you would be a guess. The way
        // out is the same shape as that one -- say which you mean.
        // 一個「同時也是欄名」的數字，是一次等著發生的猜測。檔案 `2,1` 的第 1 欄名叫 "2"、
        // 第 2 欄名叫 "1"；`-hash 2` 取的是位置 2，於是雜湊了名為 "1" 的那一欄，rc=0、
        // stderr 空白。呼叫端要的是他在標頭裡看得到的那個名字，拿到的是另一欄。
        // 拒絕的理由與「兩個欄位同名」那一條相同（2026-08-18 定案）：替你挑一個等於猜測。
        var named: [Int] = []
        for (i, f) in header.fields.enumerated() where baseName(headerName(f)) == token {
            named.append(i)
        }
        if !named.isEmpty {
            let where_ = named.map { "position \($0 + 1)" }.joined(separator: ", ")
            let whereZh = named.map { "第 \($0 + 1) 欄" }.joined(separator: "、")
            throw fault(
                "\"\(token)\" is both a column NUMBER and the NAME of a column (\(where_)); which one is meant cannot be decided without guessing. Rename the column, or address it by a number that is not also a name",
                "「\(token)」同時是一個欄「號」與某個欄位的「名字」（\(whereZh)）；不猜就無法決定你指的是哪一個。請改名，或改用一個不同時是名字的欄號")
        }
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
    // Before blaming the column: the caller may have pasted an address exactly
    // as --physical or --a1 printed it. `1:1@L2` splits into record 1 and
    // column "1@L2", and "no column named 1@L2" sends the reader looking for a
    // column that was never the problem. The README promises the printed
    // notation composes; under those two flags it does not, and the least this
    // can do is say which part to drop.
    //
    // Checked by stripping and re-resolving, not by pattern alone: a column
    // really can be called "id [primary]", and telling someone their own
    // column name is a decoration would be the same wrong answer in reverse.
    // 在怪罪欄位之前：呼叫端可能是把 --physical 或 --a1 印出來的位址原封不動貼了回來。
    // `1:1@L2` 會切成第 1 筆與欄位「1@L2」，而「沒有名為 1@L2 的欄位」會把讀者送去找一個
    // 從來就不是問題所在的欄位。README 承諾「印出來的寫法可以直接接下去」，在那兩個旗標下
    // 它做不到，而這裡至少能說出「該拿掉哪一段」。
    // 判斷方式是「拿掉之後再解析一次」，不是只看樣子：一個欄位真的可以叫做「id [primary]」，
    // 而把別人的欄名說成裝飾，是同一個錯誤的反面。
    if let bare = strippedLocation(token),
       header.fields.contains(where: { baseName(headerName($0)) == bare }) ||
       (Int(bare).map { $0 >= 1 && $0 <= header.count } ?? false) {
        throw fault(
            "\"\(token)\" is an address as --physical or --a1 prints it; the trailing location is not part of the address. Use \"\(bare)\" for the column, and note that only the plain r:c form composes",
            "「\(token)」是 --physical 或 --a1 印出來的位址形式；結尾那段位置資訊不屬於位址本身。欄位請用「\(bare)」，並注意只有單純的 r:c 形式可以直接接下去")
    }
    // Each name in quotes, because a name can contain the separator this list
    // uses. A file whose first column is called `a,b` produced
    //   the columns are: a,b, c
    // which reads as three columns and is not parseable by a human or a
    // script. The quotes cost nothing on ordinary names and are the only thing
    // that makes the awkward ones legible.
    // 每個名字都加引號，因為名字裡可以含有「這份清單用來分隔的那個字元」。第一欄叫做
    // `a,b` 的檔案原本會印出「the columns are: a,b, c」——讀起來像三欄，人與腳本都解析不了。
    // 對一般的名字加引號沒有任何代價，而它是讓那些尷尬的名字可讀的唯一辦法。
    // Both the name asked for and the names on offer go through the VALUE
    // escaper, not just the whole-line one. The difference is the backslash:
    // the line escape deliberately leaves it alone so that a message teaching
    // `\n` still reads as `\n`, and the consequence here was that a column
    // literally named `na\nme` and one containing a newline produced
    // byte-identical error lines -- while the INFO line recording the same
    // invocation told them apart. Applying the README's own unescape recipe to
    // either gave a name with a real newline in it, inventing a character for
    // the one that never had it, at rc=0 on the reading side.
    // 「被詢問的那個名字」與「檔案提供的那些名字」都走「值」的跳脫，而不只是整行的那一個。
    // 差別在反斜線：整行的跳脫刻意放過它，好讓一則在教 `\n` 的訊息仍然讀作 `\n`，而它在
    // 這裡的後果是——一個字面叫做 `na\nme` 的欄位，與一個名字裡含換行的欄位，產生的錯誤行
    // 逐位元組相同，而同一次執行的 INFO 行分得出來。把 README 自己那份解碼步驟套到任何一則
    // 上，得到的都是一個帶著真換行的名字：替那個從來沒有換行的名字發明了一個字元，rc=0。
    // The list of names is bounded. It was every column, in full, so a file
    // whose first column name is 50,000 characters long put a 50 KB line on
    // stderr -- on the line carrying the diagnosis, in a message whose
    // documented example is `no column named "caf<U+FFFD>"`. The locating
    // report cuts a value at 200 characters for this exact reason and says so;
    // a diagnostic listing what IS available had no such rule.
    // 那份名字清單有上界。原本是「每一欄、完整印出」，於是一個「第一欄名字有 50,000 個字元」
    // 的檔案，會在 stderr 上放一行 50 KB——就放在承載診斷的那一行上，而這則訊息在文件裡的
    // 範例是 `no column named "caf<U+FFFD>"`。定位報告正是為了同一個理由把值切在 200 個字元，
    // 而且說了出來；一個「列出有哪些可用」的診斷卻沒有這條規則。
    func shortName(_ n: String) -> String {
        guard n.count > 60 else { return n }
        return String(n.prefix(60)) + "…[+\(n.count - 60) more chars]"
    }
    let allNames = header.fields.map { "\"\(reportEscape(shortName(baseName(headerName($0)))))\"" }
    let shown = allNames.prefix(12)
    var names = shown.joined(separator: ", ")
    if allNames.count > shown.count {
        names += ", … and \(allNames.count - shown.count) more"
    }
    let asked = reportEscape(token)
    throw fault("no column named \"\(asked)\"; the columns are: \(names)",
              "沒有名為「\(asked)」的欄位；本檔案的欄位是：\(names)")
}

/// `1@L2` -> `1`, `1 [A2]` -> `1`. Nil when there is nothing that looks like
/// one of the two decorations the locating report can add.
/// `1@L2` → `1`、`1 [A2]` → `1`。若結尾沒有那兩種定位報告可能加上的裝飾，回傳 nil。
func strippedLocation(_ token: String) -> String? {
    if let at = token.range(of: "@L", options: .backwards) {
        let tail = token[at.upperBound...]
        if !tail.isEmpty, tail.allSatisfy({ $0.isNumber }) {
            return String(token[token.startIndex..<at.lowerBound])
        }
    }
    if token.hasSuffix("]"), let br = token.range(of: " [", options: .backwards) {
        let tail = token[br.upperBound..<token.index(before: token.endIndex)]
        if !tail.isEmpty, tail.first!.isLetter, tail.dropFirst().allSatisfy({ $0.isNumber }) {
            return String(token[token.startIndex..<br.lowerBound])
        }
    }
    return nil
}

/// `allMeansMarked` is true only for `-decrypt`, which is the only verb the
/// README gives the `all` keyword to: "COLS may be `all` to take every marked
/// column". The implementation gave it to every verb, so `-hash all` on a file
/// with no encrypted columns selected NOTHING and exited 0 having done nothing
/// -- the same silent no-op an empty column list used to be, reached by
/// another road. It also made a column genuinely named `all` unaddressable.
/// `allMeansMarked` 只在 `-decrypt` 時為真——README 只把 `all` 這個關鍵字給了它:
/// 「COLS 可以是 `all`，代表每一個被標記的欄位」。而實作把它給了每一個動詞，於是
/// `-hash all` 在一個沒有加密欄位的檔案上什麼也沒選中、以 0 結束、什麼也沒做——那正是
/// 「空欄位清單」曾經的那個靜默無操作，只是換了一條路走回來。它同時也讓一個真的叫做
/// `all` 的欄位無法被定址。
func resolveColumnList(_ spec: String, header: Record, allMeansMarked: Bool = false) throws -> [Int] {
    // An empty COLS is a refusal, not "protect nothing". `-hash ""` used to
    // exit 0 having done nothing at all: output byte-identical to the input, no
    // marker in the header, nothing on stderr -- while a WRONG column name was
    // refused by name. A script whose $COLS came out empty wrote an
    // unprotected file and every check this README offers reported success.
    // The tool's first requirement is that anything it cannot do must fail
    // loudly rather than quietly emit a half-correct file, and an empty
    // selection is the smallest possible version of exactly that.
    // 空的 COLS 是一次拒絕，不是「保護零個欄位」。`-hash ""` 原本會以 0 結束、什麼也沒做：
    // 輸出與輸入逐位元相同、標頭沒有標記、stderr 空白——而一個「錯的」欄名卻會被指名拒絕。
    // 一支 $COLS 算成空字串的腳本，寫出來的是一個未受保護的檔案，而 README 提供的每一種
    // 檢查都會回報成功。這支工具的第一條要求就是「做不到的事要大聲失敗，而不是安靜地產出
    // 一個半對的檔案」，而一個空的選取，正是那件事最小的版本。
    if spec.split(separator: ",").allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
        throw fault("no columns named: the column list is empty. Naming no columns cannot be distinguished from a variable that came out empty, so it is refused rather than treated as \"none\"",
                    "沒有指名任何欄位：欄位清單是空的。「一個欄位都不指」與「某個變數算成了空字串」無法區分，因此拒絕，而不是當成「零個」")
    }
    if spec == "all" && allMeansMarked {
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

/// The `-log` path against the other files this run names. Called before the
/// log is opened, because opening it is what would do the damage.
/// `-log` 的路徑，對上這次執行指名的其他檔案。在 log 被開啟之前呼叫——因為「開啟它」正是
/// 會造成損害的那一步。
func refuseLogAliases(_ o: Options) throws {
    guard let lg = o.logPath else { return }
    if let inp = o.input, sameFile(inp, lg) {
        throw usageError(
            "-log \(lg) is the input; appending the log into the file being read leaves a file csv2 cannot parse",
            "-log \(lg) 就是輸入檔；把 log 追加進「正在被讀的那個檔案」，會留下一個 csv2 解析不了的檔案")
    }
    if let out = o.output, sameFile(out, lg) {
        throw usageError(
            "-o \(out) is the -log file; the run would rename its own audit trail away",
            "-o \(out) 就是 -log 檔；那次執行會把自己的稽核軌跡改名蓋掉")
    }
    // The pair the first version of this function did not ask about, and the
    // worst of the six.
    //
    // `-log` naming the KEYFILE appends the invocation line to the key before
    // the key is derived. The run encrypts with "the original bytes plus one
    // log line" -- a value that existed for a few milliseconds and was never
    // written anywhere as such -- and then appends the outcome line, so the
    // file on disk is one line too long and any backup is one line too short.
    // Neither decrypts. Exit 0, nothing on either stream, and `-log` is the
    // flag a careful operator adds when doing something irreversible.
    //
    // 這是這個函式的第一版沒有問到的那一對，也是六對裡最糟的。
    //
    // `-log` 指向「金鑰檔」時，呼叫紀錄會在金鑰被推導之前被追加到那把金鑰上。於是那次執行
    // 用「原本的位元組加上一行 log」去加密——那個值只存在了幾毫秒，而且從來沒有以那個樣子被
    // 寫在任何地方——接著又追加了結果那一行，因此磁碟上的檔案多一行、任何備份少一行，兩者
    // 都解不開。rc=0，兩條輸出流上什麼也沒有，而 `-log` 正是一個謹慎的操作者在做不可逆的事
    // 情時會加上的旗標。
    if let kf = o.keyfile, sameFile(kf, lg) {
        throw usageError(
            "-log \(lg) is the keyfile; the log line would be appended to the key before the key is used, so nothing afterwards decrypts what this run writes",
            "-log \(lg) 就是金鑰檔；那一行 log 會在金鑰被使用之前被追加到它上面，於是事後沒有任何東西解得開這次執行寫出來的東西")
    }
}

func openInput(_ o: Options) throws -> InputPlan {
    if o.useStdin {
        let h = o.headersOverride ?? 1
        return InputPlan(format: h == 2 ? .csv2 : .csv, headerRows: h,
                         source: ByteSource(stdin: 1 << 16), describedPath: "<stdin>")
    }
    let path = o.input!
    // A Markdown table, translated into canonical .csv2 before the parser
    // sees it. Phase 8a: `-md` could write one and nothing could read one.
    // The header-row count comes back from the translation because it is
    // RECOVERABLE -- `-md` joins a .csv2's two titles with an unescaped
    // `<br>` -- so this needs no --headers and cannot be told a wrong one.
    // 一張 Markdown 表，在解析器看到它之前先翻譯成標準的 `.csv2`。第 8a 階段：`-md` 寫得出一張，
    // 而沒有任何東西讀得回一張。標頭列數由那次翻譯回傳，因為它是**還原得出來**的——`-md` 用一個
    // 未跳脫的 `<br>` 把 .csv2 的兩個標題接起來——因此這裡不需要 --headers，也不可能被告知一個
    // 錯的值。
    if path.lowercased().hasSuffix(".md") {
        if o.headersOverride != nil {
            throw fault(
                "--headers is refused with a .md input: how many header rows a Markdown table has is recoverable from the table itself, and a value given here could disagree with it",
                "--headers 與 .md 輸入併用會被拒絕：一張 Markdown 表有幾列標頭，從那張表本身就還原得出來，而在這裡給一個值可能與它不符")
        }
        let t = try MarkdownIn.translate(path: path, table: o.mdTable)
        // The never-convert guard, run here because here is where the answer
        // exists. Same sentence as the one in validate(), on purpose: two
        // spellings of one rule is how the two drift apart.
        // 那道「絕不轉換」的守衛在這裡執行，因為答案在這裡才存在。刻意與 validate() 裡那一句
        // 完全相同：同一條規則有兩種寫法，正是兩者漂開的方式。
        if let out = o.output, let outFmt = Format.from(path: out),
           t.headerRows != outFmt.headerRows {
            throw usageError(
                "the input has \(t.headerRows) header row(s) and \(out) declares \(outFmt.headerRows) by its suffix. csv2 will not convert between them: going to two rows would mean inventing a row of titles, and dropping to one would discard them. Choose an output suffix that matches, or write the header rows yourself.",
                "輸入有 \(t.headerRows) 列標頭，而 \(out) 的副檔名宣告 \(outFmt.headerRows) 列。csv2 不會替你轉換：轉成兩列意味著要發明一列標題，轉成一列則會丟掉它們。請改用相符的輸出副檔名，或自行寫出標頭列。")
        }
        return InputPlan(format: t.headerRows == 2 ? .csv2 : .csv, headerRows: t.headerRows,
                         source: ByteSource(bytes: t.bytes), describedPath: path)
    }
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

/// Reads the existing file and applies the SAME check the rewrite path applies.
/// It runs only when the file does not end in a newline, which is the only
/// state in which the tail can be a partial record -- so a file that ends
/// properly, which is nearly all of them, still costs the fast path nothing.
///
/// It exists because `-append --in-place` validated nothing for a `.csv` and
/// said rc=0 twice over. A file ending `zlib,1.3` where the header has three
/// columns took the append and produced a file csv2 itself then refused to
/// read, while THE SAME INPUT through `-o` was correctly refused -- one verb,
/// one input, opposite outcomes, and the difference documented only as a
/// big-O note. A file ending inside an unclosed quote absorbed the appended
/// record into that field, so a write that reported success had not happened.
/// Round 37 of the README-only blind testing, defects X and Y.
///
/// Cheaper checks were considered and are not sound. Reading back a bounded
/// window and parsing the tail after the last newline cannot tell a partial
/// record from a complete one that contains an embedded newline: both look
/// like a fragment, and the answer depends on the quote state at the start of
/// the record, which is only knowable by parsing from the front. Paying O(n)
/// on the one case that can be wrong beats being wrong quietly.
///
/// 讀取既有檔案，並套用「重寫路徑所套用的同一份檢查」。它只在檔案未以換行結尾時執行，
/// 而那是唯一「結尾可能是半筆」的狀態——因此一個正常結尾的檔案（幾乎全部都是）不必為
/// 快路徑多付任何成本。
/// 它之所以存在，是因為 `-append --in-place` 對 `.csv` 完全不驗證，而且以 rc=0 錯了兩次。
/// 一個以 `zlib,1.3` 結尾、而標頭有三欄的檔案，會照樣接受追加並產生一個 csv2 自己拒讀的
/// 檔案，而**同一份輸入**走 `-o` 會被正確拒絕——同一個動詞、同一份輸入、相反的結果，而兩者的
/// 差別只被寫成一個 O(1) 的括號註記。一個結束在未閉合引號裡的檔案，會把追加的那一筆吸進那個
/// 欄位，於是一次回報成功的寫入其實沒有發生。README-only 盲測第 37 回合，編號 X 與 Y。
/// 更便宜的檢查考慮過，而且不成立：讀回一段有界的視窗、解析最後一個換行之後的部分，分不出
/// 「半筆」與「一筆含內嵌換行的完整紀錄」——兩者看起來都是碎片，而答案取決於該紀錄開頭處的
/// 引號狀態，那只有從檔案前面解析才知道。在唯一可能出錯的那個情況上付 O(n)，好過安靜地弄錯。
/// Returns the number of line feeds in the file, which the append fast path
/// needs to know which physical line the appended record starts on. Counting
/// them here is free: this function already reads every byte.
///
/// `builder`, when given, is filled in from the same pass. The scan happens
/// either way -- see the long comment at the call site -- so an index costs
/// one grid entry per 256 records on top of it, and the alternative was the
/// only write path in the tool that left a file it had just read from end to
/// end without a sidecar.
///
/// 回傳檔案裡的換行數，追加快路徑需要它來決定被追加的紀錄從哪一個實體行開始。在這裡數
/// 是免費的：這個函式本來就會讀過每一個位元組。
///
/// 給了 `builder` 時，它也在同一次掃描中被填好。那次掃描無論如何都會發生（理由見呼叫處
/// 的長註解），因此一份索引的額外成本是每 256 筆一個格點——而不做的話，這會是本工具唯一
/// 一條「剛剛從頭到尾讀完一個檔案、卻沒有留下 sidecar」的寫入路徑。
@discardableResult
func validateBeforeAppend(path: String, format: Format, headerRows: Int,
                          truncatePartial: Bool,
                          builder: IndexBuilder? = nil,
                          lastTerminatorWasCRLF: UnsafeMutablePointer<Bool>? = nil) throws -> Int {
    let source = try ByteSource(path: path)
    defer { source.close() }
    var headers: [Record] = []
    var expected = 0
    var pending: Error?
    var lineFeeds = 0
    let parser = RecordParser(format: format, truncatePartial: truncatePartial) { rec in
        if headers.count < headerRows {
            headers.append(rec)
            if headers.count == headerRows {
                expected = headers[0].count
                builder?.headerEnded(at: UInt64(rec.offset + 1))
            }
            return true
        }
        var r = rec
        r.number = rec.number - headerRows
        do {
            try checkFieldCount(r, expected: expected,
                                what: "record \(r.number) (line \(r.line))")
        } catch {
            pending = error
            return false
        }
        builder?.add(record: r.number, at: UInt64(r.offset), line: UInt64(r.line),
                     spansLines: recordSpansLines(r, format: format))
        return true
    }
    while !parser.stopped, let c = source.next() {
        for b in c where b == BYTE_LF { lineFeeds += 1 }
        try parser.feed(c)
    }
    // finish() is what reports a file ending inside a quoted field, so it must
    // run even though nothing else here needs it.
    // finish() 才是回報「檔案結束在引號欄位內」的地方，因此即使此處沒有別的東西需要它，
    // 它也必須被執行。
    // The parser's own message for a file ending inside a quoted field says
    // "pass --truncate-partial to discard it" -- correct for every verb except
    // this one, which refuses that flag outright. The parser cannot know who
    // called it; this does, so it says the thing that works here. Round 74, JD.
    // 解析器對「檔案結束在引號欄位內」的訊息說「要丟棄它請給 --truncate-partial」——那對每一個
    // 動詞都對，除了這一個，而這一個會直接拒絕那個旗標。解析器不知道是誰叫它的；這裡知道，
    // 因此由這裡說出「在這裡行得通」的那句話。第 74 回合，JD。
    do {
        if !parser.stopped { try parser.finish() }
    } catch {
        let m = "\(error)"
        if m.contains("ends inside a quoted field") && !truncatePartial {
            throw fault(
                "the file ends inside a quoted field -- the closing quote is missing, so its last record is incomplete and -append cannot add after it. --truncate-partial is refused with -append (they contradict each other), so write a clean copy first: csv2 -r -t --truncate-partial -i \(path) -o CLEAN, and append to that.",
                "這個檔案結束在引號欄位內——缺少收尾的引號，因此它的最後一筆不完整，-append 無法接在它後面。--truncate-partial 與 -append 併用會被拒絕（兩者互相矛盾），所以請先寫出一份乾淨的複本：csv2 -r -t --truncate-partial -i \(path) -o CLEAN，再對那一份追加。")
        }
        throw error
    }
    if let e = pending { throw e }
    lastTerminatorWasCRLF?.pointee = parser.lastTerminatorWasCRLF
    return lineFeeds
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
        // A blank line is the common case and produced a message about field
        // counts, which is true and unhelpful: a reader looking at "record 2
        // (line 3) has 1 fields but the header has 2" goes hunting for a
        // missing comma. A file that merely ends with an extra newline lands
        // here too, and that is what most people will have.
        // 空白行是最常見的情況，而它得到的是一則關於欄數的訊息——那句話是對的，也幫不上忙：
        // 一個看著「第 2 筆（第 3 行）有 1 欄，標頭有 2 欄」的讀者，會去找一個少掉的逗號。
        // 一個「只是多了一個結尾換行」的檔案也會落在這裡，而多數人手上的正是那種。
        if r.count == 1, r.fields.first?.value.isEmpty == true {
            throw fault(
                "\(what) is a blank line, and a blank line is not a record with \(expected) empty fields; remove it. A file that ends with two newlines has one",
                "\(what) 是一個空白行，而空白行不是「一筆有 \(expected) 個空欄位的紀錄」；請把它移除。以兩個換行結尾的檔案就有一個")
        }
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
      foo.md             READ a Markdown table back. Header rows are recovered
                         from the table, so --headers is refused here.
                         --md-table N takes the Nth table out of a document;
                         without it the file must BE a table
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
      --build-index      build the sidecar now; otherwise one appears only as a
                         side effect of a write or a full read
      --verify-index     O(n) full check of the sidecar; the O(1) check the
                         normal path does is deliberately a heuristic
      --version  -V      --help  -h

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
///
/// This function does NOT escape, deliberately. The line it returns is written
/// through `Logger`, which escapes every message as it builds the line, so
/// escaping here too produced `\\n` where the input had a newline -- a value
/// that no longer round-trips, arrived at by two fixes each of which was right
/// on its own. Escaping belongs at exactly one point, and that point is where
/// the line is built, because it is the only one that covers messages nobody
/// has written yet.
/// 此處刻意「不」跳脫。它回傳的那一行是經由 `Logger` 寫出的，而 `Logger` 在建行時已經
/// 把每一則訊息跳脫過；這裡再跳脫一次，會讓輸入中的換行變成 `\\n`——一個再也還原不回去
/// 的值，而它來自兩個各自都正確的修正。跳脫只能發生在「一個」地方，而那個地方是建行的
/// 那一點，因為只有它涵蓋得到「還沒有人寫出來的訊息」。
/// An argument as the log can carry it: escaped, and quoted when it contains
/// anything that would make the line read as a different command. Without the
/// quoting, `-i "my file.csv"` logged as `-i my file.csv` -- an audit entry
/// naming a command nobody ran, and one that a reader would take as two
/// arguments.
/// 一個「log 載得動」的引數：經過跳脫，並在它含有「會讓這一行讀成另一個指令」的東西時加上
/// 引號。少了這一步，`-i "my file.csv"` 會記成 `-i my file.csv`——一則指名了「沒有人執行過的
/// 指令」的稽核紀錄，而讀者會把它讀成兩個引數。
private func loggedArg(_ a: String) -> String {
    let e = reportEscape(a)
    guard e.isEmpty || e.contains(" ") || e.contains("\"") || e.contains("\t") else { return e }
    return "\"\(e.replacingOccurrences(of: "\"", with: "\"\""))\""
}

func sanitizedCommandLine(_ argv: [String]) -> String {
    var out: [String] = []
    var i = 0
    while i < argv.count {
        let a = argv[i]
        out.append(loggedArg(a))
        switch normalizeFlag(a) {
        case "update":
            // keep the address, drop the value / 保留位址，去掉值
            if i + 1 < argv.count { out.append(loggedArg(argv[i + 1])) }
            if i + 2 < argv.count { out.append("<value>") }
            i += 3
            continue
        case "insert":
            if i + 1 < argv.count { out.append(loggedArg(argv[i + 1])) }
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
        // Before openLog, not in validate(). The log is opened first so that a
        // refusal reaches the audit trail -- which means a refusal ABOUT the
        // log has already been appended to whatever the log names by the time
        // validate() runs. Checked in validate() first, `-log` naming the
        // input left the input with an ERROR line appended: the message was
        // right, the file was still damaged, and the damage was the message.
        // 放在 openLog 之前，而不是放在 validate() 裡。log 之所以先被開啟，是為了讓「拒絕」
        // 也能進到稽核軌跡——而那表示：等到 validate() 執行時，一則「關於 log 本身」的拒絕
        // 已經被追加進 log 所指的那個檔案了。先寫在 validate() 裡時，`-log` 指向輸入會讓那個
        // 輸入多出一行 ERROR：訊息是對的，檔案照樣被弄壞了，而弄壞它的正是那則訊息。
        try refuseLogAliases(o)
        if let p = o.logPath { Logger.shared.openLog(path: p) }
        // Before validate(&o), because a bad knob is not a usage error about
        // the flags the caller typed -- it is the environment they are running
        // in, and it should be named before anything else can go wrong
        // because of it.
        // 放在 validate(&o) 之前，因為壞掉的旗標不是「呼叫端打了什麼」的用法錯誤，
        // 而是「他們身處的環境」，該在任何東西因它出錯之前先被指名。
        try validateEnvironment()
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
        // Escaped for the same reason the log line is, and for a promise of
        // its own: errors on stderr are documented as EXACTLY two lines,
        // English then Chinese. A message interpolating a column name that
        // contained a newline produced four, and a script reading the pair
        // took the injected line for part of the error.
        // 與 log 那一行同理，而且它自己還有一個承諾：stderr 上的錯誤在文件裡是「恰好兩行」，
        // 英文在前中文在後。一則插入了含換行欄名的訊息會產生四行，而依「兩行」去讀的腳本
        // 會把被注入的那一行當成錯誤訊息的一部分。
        Platform.writeStderr(
            "csv2: \(lineEscape(e.message))\ncsv2：\(lineEscape(e.messageZh))\n")
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
        Platform.writeStderr("csv2: \(lineEscape("\(error)"))\n")
        Logger.shared.close()
        return 1
    }
}

exit(main())

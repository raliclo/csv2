// =====================================================================
//  Bridge.swift — every question this viewer asks, it asks csv2.
//  Bridge.swift — 這個檢視器問的每一個問題，都是問 csv2。
//
//  THE VIEWER DOES NOT PARSE CSV. Not a comma split, not a quote state
//  machine, not an import of csv2's internals. It runs the binary and
//  decodes `--json`, and that is the whole reason it can be trusted: a
//  second parser would be a second set of answers, and the day they
//  disagreed the one on screen would be the one nobody tested.
//
//  **這個檢視器不解析 CSV。** 沒有逗號切割、沒有引號狀態機、也不 import csv2 的內部型別。
//  它執行那個二進位檔並解碼 `--json`，而那正是它可信的全部理由：第二個解析器就是第二組答案，
//  而它們哪天不一致時，螢幕上的那一組會是沒有人測過的那一組。
//
//  T84 asserts this by reading this source. It is a static check because
//  the failure it guards against does not show up at run time: a viewer
//  with its own splitter agrees with csv2 on every file anyone tries.
//  T84 以「讀這份原始碼」來斷言它。那是一個靜態檢查，因為它要防的失敗不會在執行期現形：
//  一個自己會切欄位的檢視器，在任何人試過的每一個檔案上都與 csv2 一致。
// =====================================================================

import Foundation

/// What one query returned, including the part most viewers throw away.
///
/// `status` is carried, not swallowed. Item seven of the plan's screen
/// section: a non-zero rc is a visible row on screen with the first line of
/// stderr, never a blank area. Phase 8 item four made `-mid` past the end an
/// error specifically so that there is something here to show -- discarding it
/// would undo that change from the other end.
///
/// 一次查詢回傳了什麼，包括多數檢視器會丟掉的那一部分。
///
/// `status` 是被帶著走的，不是被吞掉的。計畫「畫面」那一節的第七項：非零 rc 在畫面上是**一列
/// 看得見的東西**，帶著 stderr 的第一行，絕不是一片空白。第 8 階段第四項把 `-mid` 越界改成錯誤，
/// 正是為了讓這裡有東西可以顯示——把它丟掉等於從另一端把那次修正抵銷掉。
struct QueryResult: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
    var failed: Bool { status != 0 }
    /// The first line of stderr, which is the English one. csv2 prints English
    /// then Traditional Chinese; a status bar has room for one.
    /// stderr 的第一行，也就是英文那一行。csv2 先印英文再印繁中；狀態列只放得下一行。
    var firstErrorLine: String {
        stderr.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }
}

/// One record as `--json` gives it: the record number, the physical line, and
/// the fields BY NAME.
///
/// The fields arrive as a dictionary keyed by column name, which is what csv2
/// emits. The column ORDER therefore has to come from somewhere else -- the
/// meta line's header arrays -- and not from iterating a dictionary, which has
/// no order at all. A viewer that iterated it would show columns in a
/// different arrangement on different runs, and look like a rendering bug.
///
/// `--json` 給出的一筆紀錄：紀錄號、實體行號，以及**依欄名**的欄位。
///
/// 欄位是以「欄名為鍵」的字典抵達的，那是 csv2 輸出的形式。因此欄位的**順序**必須來自別的地方
/// ——meta 行的標頭陣列——而不是來自走訪一個字典，因為字典根本沒有順序。一個走訪它的檢視器會在
/// 不同次執行顯示不同的欄位排列，看起來像是算繪的臭蟲。
struct ViewRecord: Sendable, Identifiable {
    var id: Int { record }
    var record: Int
    var line: Int
    var fields: [String: String]
}

/// The header, as one or two rows.
///
/// Item three of the screen section: a `.csv2`'s English and Traditional
/// Chinese rows are TWO LINES stacked in one header cell, not joined. `-md`
/// joins them with `<br>` because Markdown has one header row; that is a limit
/// of that output format, not the shape of the data. SwiftUI has no such
/// limit, so it does not inherit it -- and a `.csv` shows ONE line, with no
/// invented empty second row put there for alignment.
///
/// 標頭，一列或兩列。
///
/// 畫面那一節的第三項：`.csv2` 的英文列與中文列是**兩行**，上下疊在同一個表頭儲存格裡，不合併。
/// `-md` 用 `<br>` 合併它們，是因為 Markdown 只有一列表頭；那是那個輸出格式的限制，不是資料的
/// 形狀。SwiftUI 沒有這個限制，所以不繼承它——而 `.csv` 就顯示**一行**，不會為了對齊發明一列
/// 空的中文標題。
struct ViewHeader: Sendable {
    var columns: [String]
    var columnsZh: [String]?
    var isTwoRow: Bool { columnsZh != nil }
}

/// Runs csv2. Nothing else in this program starts a process.
///
/// `Sendable` and free of stored mutable state on purpose: every call is
/// independent, which is item seven of the data section -- the viewer caches
/// nothing across queries, because the file may be rewritten between them and
/// a cache would show a mixture of two versions while looking like one.
///
/// 執行 csv2。這個程式裡沒有別的東西會啟動行程。
///
/// 刻意做成 `Sendable` 且不持有可變狀態：每一次呼叫都是獨立的，那是資料那一節的第七項——檢視器
/// 不跨查詢快取任何東西，因為那個檔案可能在兩次查詢之間被改寫，而一份快取會顯示兩個版本的混合，
/// 同時看起來像一個。
struct CSV2Bridge: Sendable {
    var binary: String
    var path: String

    /// The command a user could paste, for exactly this query.
    ///
    /// Item one of the screen section: selecting a cell has to produce
    /// something that can be carried back to the command line, because that is
    /// what this viewer is FOR. T86 does not check that the string looks
    /// plausible; it runs it.
    ///
    /// 使用者可以直接貼上的那一行指令，對應的正是這一次查詢。
    ///
    /// 畫面那一節的第一項：選中一格必須產生一個**帶得回命令列**的東西，因為那正是這個檢視器
    /// 存在的理由。T86 不檢查那個字串看起來合不合理；它**執行**它。
    func commandForCell(record: Int, column: Int) -> String {
        "\(shellQuote(binary)) -get \(record):\(column) -i \(shellQuote(path))"
    }

    func count() async -> QueryResult {
        await run(["-count", "-i", path])
    }

    func window(from a: Int, to b: Int) async -> QueryResult {
        await run(["-mid", "\(a),\(b)", "--json", "-i", path])
    }

    /// `/` in the plan's keyboard item: search is `-contains`, and the viewer
    /// jumps to the address it reports. It does not search the text it already
    /// has on screen -- that would find only what is loaded, and silently miss
    /// the rest of the file.
    /// 計畫鍵盤那一項裡的 `/`：搜尋就是 `-contains`，而檢視器跳到它回報的位址。它**不**搜尋自己
    /// 螢幕上已有的文字——那只會找到已載入的部分，並安靜地漏掉檔案的其餘部分。
    func search(_ needle: String) async -> QueryResult {
        await run(["-contains", needle, "-i", path])
    }

    func run(_ args: [String]) async -> QueryResult {
        await withCheckedContinuation { (k: CheckedContinuation<QueryResult, Never>) in
            // Off the main actor. The checkbox for this phase names it, and the
            // reason is not politeness: `-count` on a file with no sidecar is
            // O(n), and a scroll that blocks the main actor for a full scan is
            // a beachball on a keypress.
            // 離開 main actor。這個階段的核取方塊點名了它，而理由不是禮貌：在沒有 sidecar 的檔案
            // 上 `-count` 是 O(n)，而一次「讓 main actor 卡住整趟掃描」的捲動，會在一次按鍵上
            // 變成一顆彩球。
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: binary)
                p.arguments = args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                } catch {
                    k.resume(returning: QueryResult(
                        status: 127,
                        stdout: "",
                        stderr: "cannot run \(binary): \(error.localizedDescription)"))
                    return
                }
                // Both pipes are drained BEFORE waitUntilExit. A child that
                // fills a pipe buffer blocks writing to it, and a parent that
                // waits first deadlocks with it -- the viewer would hang on
                // exactly the large outputs it exists to show.
                // 兩條 pipe 都在 waitUntilExit **之前**被讀空。一個把 pipe buffer 填滿的子行程會
                // 卡在寫入上，而一個先 wait 的父行程會與它死鎖——那個檢視器會正好在「它存在所要
                // 顯示的大輸出」上掛住。
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                k.resume(returning: QueryResult(
                    status: p.terminationStatus,
                    stdout: decodeShowingInvalidBytes(o),
                    stderr: decodeShowingInvalidBytes(e)))
            }
        }
    }
}

/// Bytes that are not valid UTF-8 are SHOWN, not replaced.
///
/// Item six of the screen section. `String(decoding:as:)` substitutes U+FFFD
/// silently, and csv2 handles bytes and refuses to do that (T8). A viewer that
/// let the replacement back in at the last mile would display a file it had
/// quietly altered -- the most typical silent substitution in this tree, added
/// back at the one place nobody would look for it.
///
/// 不是合法 UTF-8 的位元組會**被顯示出來**，不會被替換掉。
///
/// 畫面那一節的第六項。`String(decoding:as:)` 會靜靜地換成 U+FFFD，而 csv2 以位元組為單位處理、
/// 拒絕那樣做（T8）。一個在最後一哩把那個替換加回來的檢視器，會顯示一個「它自己悄悄改過」的
/// 檔案——那是這棵樹上最典型的靜默替代，被加回在唯一沒有人會去找它的地方。
func decodeShowingInvalidBytes(_ d: Data) -> String {
    if let s = String(data: d, encoding: .utf8) { return s }
    var out = ""
    var i = d.startIndex
    while i < d.endIndex {
        // Longest valid UTF-8 run first, so text stays text.
        // 先取最長的合法 UTF-8 段，讓文字仍然是文字。
        var j = i
        while j < d.endIndex, String(data: d[i..<d.index(after: j)], encoding: .utf8) != nil {
            j = d.index(after: j)
        }
        if j > i {
            out += String(data: d[i..<j], encoding: .utf8) ?? ""
            i = j
        } else {
            out += String(format: "<0x%02X>", d[i])
            i = d.index(after: i)
        }
    }
    return out
}

/// Single quotes, POSIX style, for a command a person will paste into a shell.
/// 單引號，POSIX 形式，供人貼進 shell 的指令使用。
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

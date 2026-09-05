// =====================================================================
//  Model.swift — the window, the total, and the errors that stay visible.
//  Model.swift — 視窗、總數，以及那些留在畫面上的錯誤。
//
//  Everything here is decoded from `--json`. The one thing that is NOT
//  decoded from a record is the column ORDER: `--json` gives fields keyed
//  by name, and a dictionary has no order, so the order comes from the
//  meta line's header arrays. A viewer that iterated the dictionary would
//  arrange columns differently between runs and look like a rendering bug.
//  這裡的一切都從 `--json` 解碼而來。唯一**不是**從紀錄解碼的是欄位的**順序**：`--json` 給的是
//  以欄名為鍵的欄位，而字典沒有順序，所以順序來自 meta 行的標頭陣列。一個走訪字典的檢視器會在
//  不同次執行排出不同的欄序，看起來像算繪的臭蟲。
// =====================================================================

import Foundation

/// Parsed from the meta line and the record lines of one `--json` run.
/// 從一次 `--json` 執行的 meta 行與紀錄行解析出來。
struct Page: Sendable {
    var header: ViewHeader
    var rows: [ViewRecord]
}

enum PageError: Error, Sendable {
    case query(status: Int32, message: String)
    case malformed(String)
}

/// Decodes `--json` output. JSONSerialization, not a hand-rolled reader --
/// the whole premise of this viewer is that it does not write parsers.
/// 解碼 `--json` 的輸出。用 JSONSerialization，不是自己手寫的讀取器——這個檢視器的整個前提，
/// 就是它不寫解析器。
func decodePage(_ r: QueryResult) throws -> Page {
    if r.failed {
        throw PageError.query(status: r.status, message: r.firstErrorLine)
    }
    var header: ViewHeader?
    var rows: [ViewRecord] = []
    for line in r.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let d = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            throw PageError.malformed(String(line.prefix(80)))
        }
        if let meta = o["meta"] as? [String: Any] {
            // `header` is present whenever the file HAS a header row -- csv2
            // emits it positionally since LI, which this viewer is the reason
            // for. It is absent only for `--headers 0`, where there is no
            // header to carry, and the fallback below then takes the keys of
            // the first record and sorts them: stable between runs, and
            // openly not the file's order, because with no header row there
            // is no file order to be had.
            //
            // This comment said the opposite an hour ago -- "the meta line
            // only carries the names when -t was asked for" -- which was true
            // of csv2 before LI and false the moment it was fixed. Left
            // standing it would have sent the next reader looking for a
            // condition that no longer exists.
            //
            // 只要那個檔案**有**標頭列，`header` 就一定在——csv2 自 LI 起就依位置輸出它，而這個
            // 檢視器正是那次修正的起因。它只在 `--headers 0` 時不存在，因為那裡沒有標頭可帶；
            // 底下的退路於是取第一筆紀錄的鍵並排序：在不同次執行之間穩定，而且**公開地**不是
            // 檔案的順序——因為沒有標頭列時，根本沒有「檔案的順序」可言。
            //
            // 這段註解一小時前說的是相反的話——「meta 行只在給了 -t 時才帶欄名」——那在 LI 之前
            // 對 csv2 成立，而在它被修好的那一刻起就是假的。留著它，會讓下一個讀者去找一個
            // 已經不存在的條件。
            if let en = meta["header"] as? [String] {
                header = ViewHeader(columns: en, columnsZh: meta["header_zh"] as? [String])
            }
            continue
        }
        guard let rec = o["record"] as? Int,
              let fields = o["fields"] as? [String: String] else {
            throw PageError.malformed(String(line.prefix(80)))
        }
        rows.append(ViewRecord(record: rec,
                               line: (o["line"] as? Int) ?? 0,
                               fields: fields))
    }
    if header == nil {
        header = ViewHeader(columns: rows.first.map { $0.fields.keys.sorted() } ?? [],
                            columnsZh: nil)
    }
    return Page(header: header!, rows: rows)
}

/// What the screen is showing, and what went wrong if something did.
///
/// `total` comes from `-count`, which is what gives the scroll range its size
/// before anything is drawn. Without it a `List` discovers the total while
/// scrolling and the scrollbar moves under the user's hand.
///
/// 畫面正在顯示什麼，以及若有出錯、是什麼出錯了。
///
/// `total` 來自 `-count`，那是「在畫任何東西之前就決定捲動範圍」的來源。少了它，`List` 會邊捲邊
/// 發現總數，而捲軸會在使用者手下移動。
@MainActor
final class ViewerModel: ObservableObject {
    @Published var total: Int = 0
    @Published var page: Page = Page(header: ViewHeader(columns: [], columnsZh: nil), rows: [])
    @Published var errorLine: String = ""
    @Published var selected: (record: Int, column: Int)? = nil
    @Published var windowStart: Int = 1
    /// One query at a time. See rowAppeared.
    /// 一次一個查詢。見 rowAppeared。
    private var loading = false

    let bridge: CSV2Bridge
    let pageSize: Int

    init(bridge: CSV2Bridge, pageSize: Int = 200) {
        self.bridge = bridge
        self.pageSize = pageSize
    }

    /// The address as csv2 spells it, which is the thing worth copying.
    /// 以 csv2 的寫法表示的位址，那才是值得複製的東西。
    var addressText: String {
        guard let s = selected else { return "" }
        return "\(s.record):\(s.column)"
    }

    var commandText: String {
        guard let s = selected else { return "" }
        return bridge.commandForCell(record: s.record, column: s.column)
    }

    func loadTotal() async {
        let r = await bridge.count()
        if r.failed {
            errorLine = r.firstErrorLine
            total = 0
            return
        }
        total = Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        errorLine = ""
    }

    /// One window. Errors are recorded, not swallowed: item seven of the
    /// screen section, and the reason phase 8 item four turned a past-the-end
    /// start into an error in the first place.
    /// 一個視窗。錯誤被記下來，不被吞掉：畫面那一節的第七項，也正是第 8 階段第四項當初把「起點
    /// 越界」改成錯誤的理由。
    func loadWindow(from a: Int) async {
        guard total > 0 else { return }
        let start = max(1, min(a, total))
        let end = min(start + pageSize - 1, total)
        let r = await bridge.window(from: start, to: end)
        do {
            page = try decodePage(r)
            windowStart = start
            errorLine = ""
        } catch PageError.query(_, let m) {
            errorLine = m
        } catch {
            errorLine = "\(error)"
        }
    }

    /// Wrap-around is TWO queries, joined here. csv2 has no wrap-around form
    /// and will not grow one: record 300000 and record 1 are not adjacent in
    /// the file, and a tool that reported them as one range would be inventing
    /// data. Deciding they are adjacent on screen is the viewer's job.
    /// 繞回是**兩次查詢**，在這裡接起來。csv2 沒有繞回的查詢形式，也不會長出一個：第 300000 筆
    /// 與第 1 筆在檔案裡並不相鄰，而一個把它們回報成同一個範圍的工具是在發明資料。決定它們在
    /// 畫面上相鄰，是檢視器的工作。
    func loadWrapping(from a: Int) async {
        guard total > 0 else { return }
        let start = ((a - 1) % total + total) % total + 1
        let end = start + pageSize - 1
        if end <= total {
            await loadWindow(from: start)
            return
        }
        let firstR = await bridge.window(from: start, to: total)
        let rest = end - total
        let secondR = await bridge.window(from: 1, to: min(rest, total))
        do {
            var p = try decodePage(firstR)
            let q = try decodePage(secondR)
            p.rows.append(contentsOf: q.rows)
            page = p
            windowStart = start
            errorLine = ""
        } catch PageError.query(_, let m) {
            errorLine = m
        } catch {
            errorLine = "\(error)"
        }
    }

    /// A row scrolled into view. Loads the window containing it, and does
    /// nothing at all when that window is already the one on screen.
    ///
    /// The guard is not an optimisation. `LazyVStack` calls `onAppear` for
    /// every row it materialises, so scrolling through a page fires it dozens
    /// of times in a second; without the guard each call would start a
    /// process, and the viewer would spend a scroll launching csv2 rather than
    /// drawing. `loading` closes the same door for the calls that arrive while
    /// a query is still out.
    ///
    /// 一列捲進了可視範圍。載入包含它的那個視窗，而當那個視窗已經在畫面上時，**什麼也不做**。
    ///
    /// 那道守衛不是最佳化。`LazyVStack` 會為它具現化的每一列呼叫 `onAppear`，因此捲過一頁會在
    /// 一秒內觸發它幾十次；少了那道守衛，每一次呼叫都會啟動一個行程，而這個檢視器會把一次捲動
    /// 花在啟動 csv2 上、而不是畫圖上。`loading` 則對「查詢還在外面時抵達的那些呼叫」關上同一扇門。
    func rowAppeared(_ n: Int) {
        guard total > 0, !loading else { return }
        if n >= windowStart && n < windowStart + pageSize { return }
        let target = max(1, ((n - 1) / pageSize) * pageSize + 1)
        if target == windowStart { return }
        loading = true
        Task { @MainActor in
            await loadWindow(from: target)
            loading = false
        }
    }

    /// `/` — search is `-contains`, and the first address it reports is where
    /// we jump. Searching what is already on screen would find only what is
    /// loaded and silently miss the rest of the file.
    /// `/`——搜尋就是 `-contains`，而它回報的第一個位址就是我們跳過去的地方。搜尋螢幕上已有的
    /// 東西，只會找到已載入的部分，並安靜地漏掉檔案的其餘部分。
    func searchAndJump(_ needle: String) async {
        let r = await bridge.search(needle)
        if r.failed { errorLine = r.firstErrorLine; return }
        // The locating report is TAB separated and begins with `record:field`.
        // Splitting on the first colon of the first field is not CSV parsing --
        // it is reading csv2's own address syntax, which is what T84 allows.
        // 定位報告以 TAB 分隔，開頭是 `record:field`。在第一個欄位的第一個冒號處切開不是在解析
        // CSV——那是在讀 csv2 自己的位址語法，而那正是 T84 允許的。
        guard let first = r.stdout.split(separator: "\n").first,
              let addr = first.split(separator: "\t").first,
              let rec = Int(addr.split(separator: ":").first ?? "") else {
            errorLine = "no match"
            return
        }
        await loadWindow(from: rec)
        selected = (record: rec, column: Int(addr.split(separator: ":").dropFirst().first ?? "1") ?? 1)
    }
}

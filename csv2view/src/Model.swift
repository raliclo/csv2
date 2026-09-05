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
            // `header` may be absent: the meta line only carries the column
            // names when -t was asked for or when the shape needs them. When
            // it is absent the columns are taken from the first record, and
            // sorted, so the arrangement is at least STABLE between runs --
            // stable and possibly not the file's order beats unstable.
            // `header` 可能不存在：meta 行只在需要時才帶欄名。不存在時就取第一筆紀錄的欄名並
            // 排序，讓欄序至少在不同次執行之間**穩定**——「穩定但可能不是檔案的順序」勝過「不穩定」。
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

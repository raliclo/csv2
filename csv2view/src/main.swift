// =====================================================================
//  main.swift — the app, and the headless door its tests come in through.
//  main.swift — 這個 app，以及它的測試走進來的那扇無介面的門。
//
//  `--probe` runs the SAME code the window runs, without a window. It is
//  not a mock and not a second implementation: T85 to T89 drive
//  CSV2Bridge and ViewerModel, which is what the UI drives. A test that
//  exercised a copy of this logic would pass while the copy drifted.
//  `--probe` 執行的是**視窗會執行的同一段程式**，只是沒有視窗。它不是 mock，也不是第二份實作：
//  T85 到 T89 驅動的是 CSV2Bridge 與 ViewerModel，而那正是 UI 驅動的東西。一個運動到「這段邏輯的
//  一份複本」的測試，會在那份複本漂走時照樣通過。
//
//  There is no window here yet. The checkbox for this phase names four
//  things -- a List, a fixed row height, -mid/-count for the scroll range,
//  and queries off the main actor -- and the first three are drawing while
//  the fourth is the only one that can be wrong invisibly. What is here is
//  everything the drawing will sit on, with its behaviour pinned. The
//  SwiftUI layer is the next commit, not this one, and saying so is
//  cheaper than a half-drawn window that nothing tests.
//  這裡還沒有視窗。這個階段的核取方塊點名四件事——List、固定列高、用 -mid/-count 決定捲動範圍、
//  以及查詢離開 main actor——前三件是畫圖，而第四件是唯一一個「錯了也看不出來」的。這裡有的是
//  那些畫圖將要坐在上面的一切，而且行為被釘住了。SwiftUI 那一層是下一個 commit，不是這一個，
//  而說出這件事，比一個「畫了一半、沒有東西測」的視窗便宜。
// =====================================================================

import Foundation

/// A probe prints one line and exits with the status that matters.
/// 一個探測印出一行，並以那個重要的狀態結束。
func probeMain(_ args: [String]) async -> Int32 {
    guard args.count >= 3 else {
        FileHandle.standardError.write(Data("csv2view --probe NAME CSV2 FILE [ARGS...]\n".utf8))
        return 2
    }
    let name = args[0], binary = args[1], path = args[2]
    let rest = Array(args.dropFirst(3))
    let bridge = CSV2Bridge(binary: binary, path: path)

    switch name {
    case "count":
        let r = await bridge.count()
        print(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        return r.status

    case "command":
        // T86: the command a selected cell produces. Printed, so the test can
        // RUN it rather than admire it.
        // T86：選中一格所產生的那行指令。印出來，好讓測試能**執行**它，而不是欣賞它。
        let rec = Int(rest.first ?? "1") ?? 1
        let col = Int(rest.dropFirst().first ?? "1") ?? 1
        print(bridge.commandForCell(record: rec, column: col))
        return 0

    case "window":
        // T85: a failing query must reach the caller as a non-zero status AND
        // a visible message -- not an empty area that looks like empty data.
        // T85：一次失敗的查詢必須以非零狀態**與**一則看得見的訊息抵達呼叫端，而不是一片
        // 「看起來像空資料」的空白。
        let a = Int(rest.first ?? "1") ?? 1
        let b = Int(rest.dropFirst().first ?? "\(a)") ?? a
        let r = await bridge.window(from: a, to: b)
        if r.failed {
            print("ERROR \(r.status): \(r.firstErrorLine)")
            return r.status
        }
        do {
            let p = try decodePage(r)
            // Header shape first: one line for a .csv, two for a .csv2, and
            // never an invented empty second row.
            // 先報標頭形狀：`.csv` 一行、`.csv2` 兩行，而且絕不發明一列空的第二行。
            print("headerRows=\(p.header.isTwoRow ? 2 : 1) columns=\(p.header.columns.joined(separator: ","))")
            if let zh = p.header.columnsZh { print("headerZh=\(zh.joined(separator: ","))") }
            for row in p.rows {
                let vals = p.header.columns.map { row.fields[$0] ?? "" }
                print("\(row.record)@L\(row.line)\t\(vals.joined(separator: "\t"))")
            }
            return 0
        } catch PageError.query(let s, let m) {
            print("ERROR \(s): \(m)")
            return s
        } catch {
            print("MALFORMED: \(error)")
            return 3
        }

    case "jump", "wrap", "search":
        // These three drive ViewerModel, not CSV2Bridge: wrap-around, jumping
        // and search are the model's job, and testing the bridge under them
        // would leave the joining logic -- the part that can be wrong --
        // untested. The model is @MainActor because a view binds to it, so the
        // probe enters that actor rather than duplicating the model without it.
        // 這三個驅動的是 ViewerModel，不是 CSV2Bridge：繞回、跳轉與搜尋是模型的工作，而在它們
        // 底下去測 bridge，會讓「接起來」那一段——也就是**會出錯的那一段**——沒有被測到。模型是
        // @MainActor，因為會有一個 view 綁在它上面，所以探測**進入那個 actor**，而不是複製一份
        // 沒有 actor 的模型出來。
        return await MainActor.run { () -> Task<Int32, Never> in
            let m = ViewerModel(bridge: bridge, pageSize: Int(rest.dropFirst().first ?? "5") ?? 5)
            return Task { @MainActor in
                await m.loadTotal()
                if !m.errorLine.isEmpty { print("ERROR: \(m.errorLine)"); return 1 }
                switch name {
                case "jump":
                    await m.loadWindow(from: Int(rest.first ?? "1") ?? 1)
                case "wrap":
                    await m.loadWrapping(from: Int(rest.first ?? "1") ?? 1)
                default:
                    await m.searchAndJump(rest.first ?? "")
                }
                if !m.errorLine.isEmpty { print("ERROR: \(m.errorLine)"); return 1 }
                print("total=\(m.total) start=\(m.windowStart) address=\(m.addressText)")
                print("records=" + m.page.rows.map { "\($0.record)" }.joined(separator: ","))
                if !m.commandText.isEmpty { print("command=\(m.commandText)") }
                return 0
            }
        }.value

    case "decode":
        // T87 drives decodeShowingInvalidBytes -- the function the UI uses --
        // against the raw bytes of a file. Not a copy of it: a test that
        // exercised a copy would pass while the copy drifted, and the drift
        // that matters here is someone reaching for String(decoding:as:)
        // because it is shorter.
        // T87 驅動 decodeShowingInvalidBytes——**UI 用的那個函式**——對著一個檔案的原始位元組。
        // 不是它的複本：一個運動到複本的測試，會在複本漂走時照樣通過，而這裡真正要防的漂移，
        // 是某個人因為 String(decoding:as:) 比較短而伸手去拿它。
        guard let d = FileManager.default.contents(atPath: path) else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
            return 2
        }
        print(decodeShowingInvalidBytes(d), terminator: "")
        return 0

    default:
        FileHandle.standardError.write(Data("unknown probe: \(name)\n".utf8))
        return 2
    }
}

let argv = Array(CommandLine.arguments.dropFirst())
if argv.first == "--probe" {
    let code = await probeMain(Array(argv.dropFirst()))
    exit(code)
}

FileHandle.standardError.write(Data("""
csv2view: the window is not built yet; this binary carries the query layer and
its probes. Run `csv2view --probe window CSV2 FILE A B` to exercise it.
csv2view：視窗還沒有做，這個執行檔帶著查詢層與它的探測。
請用 `csv2view --probe window CSV2 FILE A B` 來運動它。

""".utf8))
exit(2)

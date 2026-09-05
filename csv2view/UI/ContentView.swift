// =====================================================================
//  ContentView.swift — the table, and the four things the checkbox names.
//  ContentView.swift — 那張表，以及核取方塊點名的那四件事。
//
//  This file draws. It asks csv2 nothing directly: every value it shows
//  came out of ViewerModel, which came out of `--json`. There is no comma
//  splitting and no quote state here either, and T84 scans this directory
//  as well as src/ -- a guard that covered only the layer below would have
//  missed the layer where a shortcut is most tempting.
//  這個檔案負責畫圖。它不直接問 csv2 任何事：它顯示的每一個值都來自 ViewerModel，而那來自
//  `--json`。這裡同樣沒有逗號切割、沒有引號狀態，而 T84 **連這個目錄一起掃**，不只掃 src/
//  ——一道只涵蓋下層的守衛，會漏掉「最想抄捷徑」的那一層。
// =====================================================================

import SwiftUI

/// Fixed, and that is a requirement rather than a style choice.
///
/// A row whose height depends on its content makes the scroll range depend on
/// what has been loaded, and the scrollbar then moves under the user's hand as
/// windows arrive. `-count` gives the total up front precisely so the range
/// can be decided before anything is drawn; a variable row height would throw
/// that away.
///
/// 固定，而那是需求、不是風格選擇。
///
/// 一個高度隨內容而變的列，會讓捲動範圍取決於「已經載入了什麼」，於是捲軸會在視窗抵達時
/// 在使用者手下移動。`-count` 事先給出總數，正是為了讓範圍在畫任何東西之前就決定；一個
/// 可變的列高會把那件事丟掉。
let kRowHeight: CGFloat = 22

struct ContentView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            table
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 360)
        .task { await model.loadTotal(); await model.loadWindow(from: 1) }
    }

    /// One line for a `.csv`, two for a `.csv2`, and never an invented empty
    /// second line put there for alignment. `-md` joins the two rows with
    /// `<br>` because Markdown has a single header row; that is a limit of
    /// that output format, not the shape of the data, and this does not
    /// inherit it.
    /// `.csv` 一行、`.csv2` 兩行，而且絕不為了對齊發明一列空的第二行。`-md` 用 `<br>` 合併那兩列，
    /// 是因為 Markdown 只有一列表頭；那是那個輸出格式的限制，不是資料的形狀，而這裡不繼承它。
    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 64, alignment: .trailing).padding(.trailing, 8)
            ForEach(Array(model.page.header.columns.enumerated()), id: \.offset) { i, name in
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).bold()
                    if let zh = model.page.header.columnsZh, i < zh.count {
                        Text(zh[i]).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 90, alignment: .leading)
                .padding(.horizontal, 6)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .font(.system(.body, design: .monospaced))
    }

    /// The scroll range is `1...total`, not `page.rows.count`.
    ///
    /// That is what makes the scrollbar honest: it is sized by how many
    /// records the FILE has, which `-count` answered before the first window
    /// arrived. A list built from the loaded rows would show a scrollbar that
    /// describes the window rather than the file.
    ///
    /// 捲動範圍是 `1...total`，不是 `page.rows.count`。
    ///
    /// 那正是捲軸誠實的原因：它的大小取決於**檔案**有幾筆，而那是 `-count` 在第一個視窗抵達之前
    /// 就回答的。一個用「已載入的列」建出來的清單，它的捲軸描述的是那個視窗、不是那個檔案。
    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(1...max(model.total, 1), id: \.self) { n in
                    row(n)
                        .frame(height: kRowHeight)
                        .background(model.selected?.record == n
                                    ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onAppear { model.rowAppeared(n) }
                }
            }
        }
    }

    private func row(_ n: Int) -> some View {
        let rec = model.page.rows.first { $0.record == n }
        return HStack(spacing: 0) {
            // The RECORD number, not the visual row. It is the same number
            // `-get r:c` takes, which is the whole point of showing it.
            // **紀錄號**，不是視覺上的第幾列。它與 `-get r:c` 收的是同一個號碼，而那正是顯示它
            // 的全部理由。
            Text("\(n)")
                .frame(width: 64, alignment: .trailing)
                .padding(.trailing, 8)
                .foregroundStyle(.secondary)
            if let r = rec {
                ForEach(Array(model.page.header.columns.enumerated()), id: \.offset) { i, name in
                    Text(r.fields[name] ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 90, alignment: .leading)
                        .padding(.horizontal, 6)
                        .onTapGesture { model.selected = (record: n, column: i + 1) }
                }
            } else {
                Text("…").foregroundStyle(.tertiary).padding(.horizontal, 6)
            }
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
        .contentShape(Rectangle())
    }

    /// The address, and the command. Item one of the plan's screen section:
    /// selecting a cell must produce something that can be carried back to the
    /// command line, because that is what this viewer is for. An error takes
    /// this bar over rather than hiding -- a failed query as a blank area is
    /// indistinguishable from empty data, which is the failure phase 8 item
    /// four turned into an error so that there would be something to show.
    /// 位址，以及那行指令。計畫畫面那一節的第一項：選中一格必須產生一個**帶得回命令列**的東西，
    /// 因為那正是這個檢視器存在的理由。錯誤會**接管**這一列而不是躲起來——一次失敗的查詢若是
    /// 一片空白，就與空資料分不出來，而那正是第 8 階段第四項把它變成錯誤、好讓這裡有東西可以
    /// 顯示的原因。
    private var statusBar: some View {
        HStack {
            if !model.errorLine.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(model.errorLine).lineLimit(1).textSelection(.enabled)
            } else if !model.addressText.isEmpty {
                Text(model.addressText).bold().textSelection(.enabled)
                Button("Copy as csv2 command") {
                    #if canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.commandText, forType: .string)
                    #endif
                }
                Text(model.commandText).lineLimit(1).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("\(model.total) records").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .font(.system(.callout, design: .monospaced))
    }
}

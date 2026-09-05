// =====================================================================
//  Window.swift — an NSWindow around the SwiftUI view, made by hand.
//  Window.swift — 親手為那個 SwiftUI view 造一個 NSWindow。
//
//  Not `@main App`. `main.swift` already owns top-level code -- the probe
//  door the tests come in through -- and Swift allows exactly one file to
//  have it. Choosing `@main` here would take that door away, and the tests
//  would have to drive a copy of the model instead of the model. The
//  window is worth less than the tests.
//  不用 `@main App`。`main.swift` 已經擁有最上層的程式碼——測試走進來的那扇探測門——而 Swift 只
//  允許一個檔案擁有它。在這裡選 `@main`，等於把那扇門拿掉，測試就得去驅動模型的一份複本、而
//  不是模型本身。**那個視窗沒有那些測試值錢。**
// =====================================================================

#if canImport(AppKit)
import AppKit
import SwiftUI

/// Opens the window and does not return.
///
/// `.regular` activation policy is set explicitly because this binary is not
/// inside an .app bundle: without it the process has no Dock presence, cannot
/// be brought to the front, and shows a window nobody can focus -- which looks
/// exactly like a hung program.
///
/// 開啟視窗，且不會返回。
///
/// 明確設定 `.regular` 啟動政策，因為這個執行檔不在 .app bundle 裡：少了它，這個行程不會出現在
/// Dock、無法被帶到最前面，並且顯示一個沒有人能取得焦點的視窗——那看起來與一個當掉的程式一模一樣。
@MainActor
func runViewerWindow(bridge: CSV2Bridge, title: String) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let model = ViewerModel(bridge: bridge)
    let host = NSHostingView(rootView: ContentView(model: model))

    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false)
    w.title = title
    w.contentView = host
    w.center()
    w.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
    // AppKit does not return from run(); this satisfies Never.
    // AppKit 不會從 run() 返回；這一行是為了滿足 Never。
    exit(0)
}
#endif

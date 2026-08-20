# 給 swift-corelibs-foundation 的回報:`FileHandle.write` 讓管線斷掉變成崩潰
# For swift-corelibs-foundation: FileHandle.write turns a broken pipe into a crash

**狀態:一份筆記,不會由本 session 送出。** 使用者已明示不要自行開 PR 或 issue;這一份
是留給「決定要送的人」的素材。csv2 這邊已經繞開了
(`Platform.writeAll`),因此送不送出不影響本專案;但這個缺陷會打到**每一支用 Foundation
寫 stdout 的 Swift 命令列工具**,而它們大多不會發現,因為在 macOS 上不會發生。

**Status: a note, and this session will not file it.** The user asked
explicitly that no PR or issue be opened from here; this is material for
whoever decides to. csv2 already works around it, so filing is not on this
project's critical path -- but the defect hits **every Swift command-line tool
that writes stdout through Foundation**, and most will never notice, because it
does not happen on macOS.

---

## 一句話 / One line

在 Linux 與 Windows 上,`FileHandle.write(_:)` 遇到 `EPIPE` 時不是回報錯誤,而是
**以 `try!` 觸發 fatal error**,行程死於 SIGILL(結束狀態 132)並印出一段 Swift backtrace。
一支 Unix filter 在讀取端離開時,應該安靜地死於 SIGPIPE(結束狀態 141)。

On Linux and Windows, `FileHandle.write(_:)` meets `EPIPE` and, instead of
surfacing an error, traps through `try!`: the process dies of SIGILL (exit 132)
and prints a Swift backtrace. A Unix filter whose reader has left should die
quietly of SIGPIPE (exit 141).

## 觀察到的輸出 / What it prints

```
Foundation/FileHandle.swift:709: Fatal error: 'try!' expression unexpectedly raised an error:
Error Domain=NSCocoaErrorDomain Code=512 "(null)"
UserInfo={NSUnderlyingError=Error Domain=NSPOSIXErrorDomain Code=32 "Broken pipe"}

*** Signal 4: Backtracing from 0x7fb7a36f8d71... done ***

*** Program crashed: Illegal instruction at 0x00007fb7a36f8d71 ***
```

那 2 KB 印在**執行 `| head` 的那個人**的 stderr 上。

## 最小重現 / Minimal reproduction

```swift
// pipecrash.swift
import Foundation
let out = FileHandle.standardOutput
let line = Data(String(repeating: "x", count: 4096).utf8)
for _ in 0..<100_000 { out.write(line) }
```

```sh
swiftc -o pipecrash pipecrash.swift
./pipecrash | head -c 10 ; echo "exit=${PIPESTATUS[0]}"
```

| 平台 / Platform | 結束狀態 / Exit | stderr | 來源 / Source |
|---|---|---|---|
| macOS 15,Swift 6.4,Darwin Foundation | **141**(SIGPIPE) | **0 bytes** | 上面那支程式,實測 |
| x86_64 Linux,Swift 6.3.3,corelibs | **132**(SIGILL) | **2511 bytes** | 上面那支程式,實測 |
| x86_64 Windows MSVC,Swift 6.3.3,corelibs | 132 | ~2 KB | csv2 的 T110d／T110e,尚未用這支程式重跑 |

macOS 與 Linux 兩列是用**這一支四行程式**跑出來的,不是從 csv2 推得的。

**macOS 與 Linux 兩列都是用這支獨立程式親自跑出來的**,不是從 csv2 的行為推得的。
Windows 那一列仍來自 csv2 的 T110d／T110e,標示如上,送出之前應該在那裡也跑一次同一支程式。

The macOS and Linux rows were produced by running this standalone program, not
inferred from csv2's behaviour. The Windows row still comes from csv2's own
T110d/T110e and is labelled as such; run the same program there before filing.

## 環境 / Environment

- Swift 6.4 on macOS(arm64-apple-macosx),行為正確
- Swift 6.3.3 on aarch64 Linux 與 x86_64 WSL2
- Swift 6.3.3 on x86_64-unknown-windows-msvc
- 觸發點:`Foundation/FileHandle.swift:709`(依 fatal error 訊息)

## 為什麼這是缺陷,而不是「照設計」/ Why this is a defect

1. **它與 Darwin 的 Foundation 不一致。** 同一份原始碼,同一個 API,在兩個平台上一個安靜
   死掉、一個崩潰。跨平台的 Foundation,這一點本身就足夠。
2. **`try!` 把一個「可預期的」執行期狀況當成程式錯誤。** `EPIPE` 不是 bug,它是 `| head`
   的正常結果。`try!` 的用途是「這裡不可能失敗」,而這裡顯然可能。
3. **它讓每一支這樣的工具都對使用者說謊。** 使用者輸入 `mytool | head`,得到的是一段
   Swift backtrace——看起來像是那支工具壞了。
4. **它無法在呼叫端被攔截。** `try!` 觸發的是 trap,不是可捕捉的錯誤;唯一的繞法是完全
   不用 `FileHandle.write`,那正是 csv2 現在做的事。

## 可能的修法 / Possible fixes

以「上游應該最容易接受」的順序:

1. **`write(_:)` 對 `EPIPE` 走 SIGPIPE 的預設處置**,而不是 trap——與 Darwin 一致,而且是
   filter 的正確行為。
2. **保留 `write(_:)` 的行為,但讓 `EPIPE` 不 trap**:回報錯誤,讓呼叫端決定。這會改變
   API 契約,較難被接受。
3. **最小改動:把 `try!` 換成「記錄後 `_exit(141)`」** 之類的處置。修掉崩潰,但把政策
   寫死在 Foundation 裡。

第 1 項最接近「本來就該是這樣」。

## csv2 這邊怎麼繞開的 / How csv2 works around it

`Platform.writeAll(fd:_:)`——一個直接的 `write(2)` 迴圈,在管線斷掉時把 `SIGPIPE` 還原成
預設處置並重新引發,於是行程以 141 死去、不印任何東西。Windows 沒有 SIGPIPE,直接產生 141。

只有 stdout 與 stderr 走這條路;檔案輸出仍用 `handle.write`,因為檔案不可能遇到管線斷掉
——而且 **Swift for Windows 把 `FileHandle.fileDescriptor` 標為不可用**
(「Cannot perform non-owning handle to fd conversion」),所以那條路徑在那裡根本走不通。
stdout 與 stderr 在 C runtime 中固定是 fd 1 與 2,不需要轉換。

由 T110d／T110e 斷言,並在四個平台上執行。

## 送出之前 / Before filing

- [x] macOS:141 / stderr 0 bytes(2026-08-20 實測)
- [x] Linux:132 / stderr 2511 bytes(2026-08-20 實測,同一支程式)
- [ ] Windows:用同一支程式重跑,目前那一列來自 csv2 的測試案例
- [ ] 確認 `FileHandle.swift:709` 在目前 main 分支上仍是同一段程式
- [ ] 搜尋既有 issue——這個形狀的問題不太可能沒有人回報過
- [ ] 決定送 issue 還是直接送 PR(第 1 項修法的 patch 很小)

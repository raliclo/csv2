# AGENTS.md

Guidance for coding agents working in this repository.
供 coding agent 在本 repo 工作時參考。

## Status: no implementation yet / 狀態：尚未實作

`plan/plan.md` is the only content. There is no source, no build script, no
binary. Do not write documentation, tests or release notes that describe
behaviour as if it exists — a README that promises a flag which does not work is
worse than no README, because it is believed.

`plan/plan.md` 是目前唯一的內容：沒有原始碼、沒有建置腳本、沒有執行檔。不要撰寫任何
把行為描述成「已存在」的文件、測試或發行說明——一份承諾了不存在旗標的 README 比沒有
README 更糟，因為它會被相信。

## Read the plan first / 先讀計畫

Every decision in `plan/plan.md` records *why*, and most of them came from a
specific failure in the parent project. Re-deciding them from scratch throws
that away. If a decision looks wrong, say so and cite the reason it gives;
do not quietly implement something else.

`plan/plan.md` 中的每項決定都記錄了「為什麼」，且多數源自母專案的一次具體失誤。
從頭重新決定等於丟掉那些代價。若覺得某項決定有誤，請指出並引用它給的理由；
不要安靜地改做別的。

## Development culture / 開發文化

- **Bilingual**: explanations, code comments and responses in both English and
  Traditional Chinese (繁體中文). Never Simplified Chinese.
  說明、註解與回覆一律中英雙語，繁體中文，不使用簡體。
- **Scripts in zsh**, matching multissh and the parent project.
  腳本一律使用 zsh，與 multissh 及母專案一致。
- **Swift style follows swift_tar**: plain `.swift` sources, Foundation +
  Dispatch, built with `swiftc` build scripts. No SwiftPM, no SwiftNIO.
  Swift 風格比照 swift_tar：純 `.swift` 原始檔，Foundation + Dispatch，
  以 `swiftc` 建置腳本編譯；不用 SwiftPM、不用 SwiftNIO。
- **Both platforms, always.** Built natively on the macOS host and
  cross-compiled to aarch64 Linux, with the same tests run on each and
  byte-identical output required. Linux Foundation is swift-corelibs-foundation,
  a separate implementation — passing on macOS is not evidence about Linux.
  Not shipping in the rootfs (current decision) does not relax this.
  **兩個平台都要。** 於 macOS host 原生建置，並交叉編譯至 aarch64 Linux，兩邊跑同一批
  測試且要求輸出逐位元相同。Linux 的 Foundation 是 swift-corelibs-foundation，另一份
  實作——「macOS 會過」對 Linux 不構成證據。暫不隨 rootfs 出貨並不放寬這一點。

## The one rule that matters most / 最重要的一條規則

**Fail loudly. Never produce half-correct output.**

This tool exists because scripts that split CSV on commas succeed, report what
they did, and leave the file wrong. Any code path that could emit a plausible
but incorrect record must instead exit non-zero with a message naming the
record and field. A wrong CSV is not detected by the next tool; it is detected
months later, if ever.

**要大聲失敗，絕不產生半對的輸出。** 本工具的存在，正是因為以逗號切割 CSV 的腳本會
「成功」執行、回報它做了什麼，然後留下一個錯的檔案。任何可能產生「看似合理但不正確」
紀錄的路徑，都必須改以非零結束並指出是哪一筆、哪一欄。錯的 CSV 不會被下一個工具發現，
而是在數個月後才被發現——如果還有機會被發現的話。

## Submodule rule / Submodule 規則

This repository is **ours**, with no upstream. `origin` is `raliclo/csv2` and is
both the pull source and the push target. The parent project's fork rule
(`origin` = upstream read-only, `ralic` = our fork) does **not** apply here,
because there is nothing to fork.

本 repo 是**我們自己的**，沒有上游。`origin` 即 `raliclo/csv2`，同時是拉取來源與推送
目標。母專案的 fork 規則（`origin` 為上游唯讀、`ralic` 為我們的 fork）在此**不適用**，
因為沒有東西可 fork。

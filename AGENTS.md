# AGENTS.md

Guidance for coding agents working in this repository.
供 coding agent 在本 repo 工作時參考。

## Status: phases 1–6 done; only phase 7 (shipping) remains / 狀態：第 1–6 階段完成，只剩第 7 階段（出貨）

```zsh
./compile_csv2.zsh      # builds release/csv2 with swiftc / 以 swiftc 建置 release/csv2
./test/test_csv2.zsh    # 0 FAIL; on macOS the one SKIP is T47 / 0 失敗；macOS 上唯一的 SKIP 是 T47

# the Linux half, driven from the parent project (boots a guest VM)
# Linux 那一半，由母專案驅動（會啟動 guest VM）
../test_submodules/run_csv2_test.zsh   # 0 FAIL
```

**The source list lives in `src/sources.list`, read by BOTH build scripts.**
Add a `.swift` file there, never to a script. The two scripts each carried
their own copy once and drifted; the Linux build then failed with
`cannot find 'runParallelSearch' in scope` -- a message naming a symbol, not
the missing file.
**原始檔清單在 `src/sources.list`，兩支建置腳本都讀它。** 新增 `.swift` 請加在那裡，
不要加進腳本。那兩支腳本曾各自持有一份而分岔，Linux 建置因此以
`cannot find 'runParallelSearch' in scope` 失敗——那個訊息指出的是符號，不是缺少的檔案。

Working: the RFC 4180 parser, `-r`, the selection flags, two-row headers,
`--json`, `-md` including `--pretty` with a UAX #11 width table, all four edit
verbs, `-hash`/`-encrypt`/`-decrypt`, `-debug`, `-log`, the `-append` O(1) fast
path, the `.index` sidecar with `--verify-index`, and parallel search.

Phase 6 is done: csv2 builds inside the aarch64 Linux guest and its output is
byte-identical to macOS across 12 compared invocations. Not implemented:
shipping (phase 7), which is a deliberate deferral rather than a gap.

可用：RFC 4180 解析器、`-r`、選取旗標、兩列標頭、`--json`、`-md`（含 `--pretty`
與 UAX #11 寬度表）、四個編輯動詞、`-hash`／`-encrypt`／`-decrypt`、`-debug`、
`-log`、`-append` 的 O(1) 快路徑、`.index` sidecar 與 `--verify-index`，以及平行搜尋。
第 6 階段已完成：csv2 能在 aarch64 Linux guest 內建置，且 12 組比對的輸出與 macOS
逐位元相同。未實作：出貨（第 7 階段），那是刻意暫緩而非缺口。

### Environment knobs / 環境變數

All exist so the logic can be TESTED without a 16 MiB fixture, not merely for
tuning. 全部的存在理由是「讓邏輯不需要 16 MiB 的 fixture 就能測試」，而不只是調校。

| Variable | Default | Effect |
|---|---|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | below this no index is read or written |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | set above the file size to force single-threaded |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | smaller values make a small file yield many chunks |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `-md --pretty` refuses above this rather than being OOM-killed |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | upper bound on `-tail N` / `-B N` |

**Do not document a flag as working until its case in `test/test_csv2.zsh`
passes.** A README that promises a flag which does not work is worse than no
README, because it is believed. The plan's phase checklists carry the same
rule: a box is ticked only when its test passes.

**在 `test/test_csv2.zsh` 中對應的案例通過之前，不要把任何旗標寫成「可用」。**
一份承諾了不存在旗標的 README 比沒有 README 更糟，因為它會被相信。計畫的階段
清單適用同一條規則：測試通過才打勾。

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
- **Scripts are zsh, named `.zsh`, with `#!/usr/bin/env zsh`.** Matching
  multissh and the parent project. `env zsh` rather than `/bin/zsh`: on the
  aarch64 Linux guest zsh is not at `/bin/zsh`, and phase 6 requires these
  scripts to run there unchanged. A subshell spawned from a script uses
  `zsh -c`, never `sh -c` — `/bin/sh` is dash on many Linux systems, so
  `sh -c` silently tests a different shell from the one the script is written in.
  腳本一律使用 zsh，副檔名 `.zsh`，shebang 為 `#!/usr/bin/env zsh`，與 multissh
  及母專案一致。用 `env zsh` 而非 `/bin/zsh`：aarch64 Linux guest 上的 zsh 不在
  `/bin/zsh`，而第 6 階段要求這些腳本能原封不動地在那裡執行。腳本內開子 shell 用
  `zsh -c`，絕不用 `sh -c`——許多 Linux 上的 `/bin/sh` 是 dash，`sh -c` 會靜默地
  測到一個與腳本語法不同的 shell。
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

## Who may call csv2 / 誰可以呼叫 csv2

**Inside the LinuxCS project, only TEST scripts call csv2.** The build and
maintenance scripts do not, and proposing to wire it into them is not a
suggestion this project wants.

**在 LinuxCS 專案內，只有「測試」腳本會呼叫 csv2。** 建置與維護腳本不會，也不要提議
把它接進去。

The reason is dependency direction: a script like `update_licenses.zsh` has to
run in environments where csv2 has not been built, and csv2 is deliberately not
shipped in the guest rootfs. A test script has no such problem -- it runs where
csv2 has just been built.

理由是相依性方向：`update_licenses.zsh` 這類腳本必須能在「csv2 尚未建置」的環境下執行，
而 csv2 又刻意不進 guest rootfs。測試腳本沒有這個問題——它就在剛建好 csv2 的地方執行。

So do not list "no real script uses it" as a gap. It is still true that csv2's
verification comes entirely from its own tests, which is a real limitation --
but the way past it here is changing the PLATFORM (phase 6) and changing the
READER (`read_easy`), not changing the caller.

因此不要把「沒有真實腳本在用它」列為缺口。「csv2 的驗證全部來自自己的測試」這件事仍然
為真，也仍然是一項限制——但在這裡繞過它的方法是換平台（第 6 階段）與換讀者
（`read_easy`），不是換呼叫者。

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

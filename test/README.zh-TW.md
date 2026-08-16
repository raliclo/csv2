# test

- **English: [README.md](README.md)**

`csv2` 的回歸測試。一份腳本，編號與計畫一一對應。

```zsh
./test_csv2.zsh                      # release/csv2 不存在時會先建置
CSV2=/path/to/csv2 ./test_csv2.zsh   # 測試指定的執行檔，例如 Linux 版
```

輸出同時送到終端機與腳本旁的 `test_csv2.log`。有任何案例失敗即以非零結束；
SKIP 不會讓整份測試失敗。

## 編號就是契約

每個案例是 `T<n>`，而 `T<n>` 就是 [`../plan/plan.md`](../plan/plan.md) 測試清單中
的同一個案例。因此一個失敗的案例會直接指出「為什麼該行為是這樣」的那一段，
不必讓人自己去找。

這個對應關係正是計畫的測試清單被重新編號的理由：它原本是兩段被接在一起的編號
（1–18，之後又一段 6–25），於是「測試 12」同時指兩個不同的案例，任何引用編號的
地方都已經有歧義。

## SKIP 是「被回報的狀態」，不是「被省略」

工具尚未能滿足的案例會印成 `SKIP` 並**附上原因**：

```
SKIP  T41 behaviour identical with no index (the .index sidecar is not implemented)
```

絕不安靜地略過。一份隱藏「沒跑什麼」的測試，回報的是它並不具備的涵蓋率——
那與「弄壞檔案之後仍以 0 結束的腳本」是同一種失敗模式。

目前狀態：macOS（arm64、Swift 6.4）上 **94 PASS、0 FAIL、1 SKIP**。guest 端由母專案在
每次變更後重新驗證；最近一次完整執行時兩邊回報相同的總數。

T47 是 macOS 上那個 SKIP，而且在這裡也只能是 SKIP：該案例斷言的是「**Linux** 版產生
相同的輸出」，因此它由母專案的 `../../test_submodules/run_csv2_test.zsh` 驅動——那支
腳本在 guest 內建置 csv2，並逐一以 sha256 比對 12 組呼叫。該 runner 回報
**25 PASS、0 FAIL**。

guest 內略過三項：T25 因為 guest 的 busybox 沒有可用的 `iconv` 來驗證 UTF-8；
T42 因為那裡取不到 `getconf _NPROCESSORS_ONLN`，測試無法確認有多於一個核心；
以及 T47 本身。三者都是**工具**缺席而非**性質**失敗——這正是它們是「附原因的 SKIP」
而不是 FAIL 的理由。

### 在第二個平台上跑，實際抓到了什麼

兩個 macOS 永遠不會顯現的缺陷，而且都在第一次執行時就出現：

- `getrusage(RUSAGE_SELF, &usage)` 在 Linux 上根本編譯不過。Darwin 宣告
  `getrusage(Int32, ...)`，glibc 宣告 `getrusage(__rusage_who_t, ...)`，而
  `RUSAGE_SELF` 被匯入為 `__rusage_who`。
- `--in-place` 安靜地什麼也沒做，然後以 0 結束。它用的是
  `FileManager.replaceItemAt`——在 swift-corelibs-foundation 中是另一份實作，
  結果是目的檔維持不變。現已改用 POSIX `rename(2)`，那本來就是設計指定的做法。

兩者都不是打錯字，都是讀起來完全正確的程式碼。

T9、T12、T13 曾經是 SKIP，理由更不舒服——程式碼確實走串流路徑，但「它是以環狀緩衝
寫的」並不構成「RSS 有上界」的證據。現在它們有量測了：csv2 在 `-debug` 下以一行
`metrics:` 回報峰值 RSS 與讀取位元組數，案例就對那些數字做斷言。其中 T13 顯示
`-mid 1,2` 在一個 3.3 MB 的檔案上只讀了 64 KiB——那正是它與 `-tail` 的關鍵差異。

計畫對 T9 的要求是「以大於記憶體的輸入驗證」。回歸測試造不出那種輸入，也不需要：
真正要證明的性質是「記憶體不隨輸入變大而變大」，兩個相差一個數量級的輸入可以直接
顯示這一點，而且只要幾秒鐘。

## 測試依賴的環境變數

| 變數 | 用於 |
|---|---|
| `CSV2_INDEX_MIN_BYTES` | T41／T46 —— 否則索引相關案例需要 16 MiB 的 fixture |
| `CSV2_PARALLEL_MIN_BYTES` | T42 —— 調高以強制走單執行緒，作為平行結果的比對基準 |
| `CSV2_PARALLEL_CHUNK_BYTES` | T42 —— 調小，讓小檔案也能切出多個區塊。一個只產生「一個區塊」的執行完全沒有測到邊界，在一個根本沒有切塊邏輯的實作上也會通過 |
| `CSV2_PRETTY_MAX_BYTES` | T19c —— 讓「拒絕」這條路徑能被觸及，而不必真的造出一張會耗盡記憶體的表 |

這些變數在工具中存在的理由正是如此，而且就寫在原始碼中它們各自的旁邊：一個不能被
調低的門檻，唯一的測試方式就是真的產生它本來要防的那種資料。

## Fixture

`fixtures/TARGET_PACKAGES.csv` 進版控。它是 2026-08-15 被 `${line%,*}` 弄壞的
那個真實檔案的複本——一個真正發生過的失敗案例，這也是 T1（round-trip 逐位元相同）
成為本測試中最有價值案例的原因。

之所以是複本而非指向母專案的路徑：計畫要求這份測試在 macOS 與 Linux guest 兩邊都
要能跑，而一個會伸出自己 repo 之外的測試，只在一台機器上成立。

其餘 fixture 全部**在腳本內產生**，而且是刻意的。當 fixture 的重點是特定的位元組
序列——單獨的 `\r`、UTF-8 BOM、落單的 `0xE9`、沒有結尾換行的檔案——把它提交進版控，
等於邀請編輯器、`.gitattributes` 規則或某個好意的格式化工具把它正規化掉。屆時測試
會繼續通過，但什麼都沒測到。用 `printf` 在腳本裡產生，可以把那串位元組放在原始碼中，
看得見，也不會漂移。

## 體例

比照 swift_tar 的測試腳本（`$HOME/proj/multissh/swift_tar/test_*.sh`）：pass/fail
計數、`ok`／`bad` 輔助函式、log 寫在腳本旁、暫存目錄建在同一層並由 trap 在結束時
移除。

沿用 `sos/linux_test/test_git_submodule.zsh` 的規則：**測行為，不測檔案存在**。
檢查「檔案有沒有產生」對「它正不正確」毫無證明力；本測試中有數個案例改以與參考
檔案的逐位元比對來斷言。

任何案例都不得假設 host 特有的路徑。這份測試必須原封不動地在 aarch64 Linux guest
上執行，而那裡的 `$HOME`、Homebrew prefix 與 multissh 金鑰目錄不是不同就是不存在。

## 新增案例

1. **先**加進 `../plan/plan.md` 的測試清單，附上編號與它存在的理由。一個沒有寫明
   理由的案例，會在半年後被某個正在整理的人刪掉。
2. 在此以相同編號、相同階段區段實作。
3. **通過之後才**在計畫裡打勾。在未經測試的項目上打勾，正是本專案一再遇到的那種
   「看起來成功」的失敗。

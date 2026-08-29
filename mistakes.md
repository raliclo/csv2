# mistakes — 這棵樹上「不會報錯的那一類錯誤」

供 [`mistakes_prevention`](file:///Users/raliclo/.claude/skills/mistakes_prevention/SKILL.md)
skill 使用。次數的權威來源是 [`mistakes_counter.csv2`](./mistakes_counter.csv2)，**一律經由
`csv2` 讀寫**——`corrective`、`shape`、`guard` 三欄都含引號內的逗號。

The authoritative counts live in `mistakes_counter.csv2` and are read and written through
`csv2` only: three of its columns contain commas inside quotes.

## 為什麼這份紀錄在這裡，而不是在母專案

**紀錄寫在 git project root。** 這裡是一個 repo（`sos/csv2` 是 submodule，`git rev-parse
--show-toplevel` 給的是這個目錄），母專案 `/Volumes/LinuxCS` 是另一個。兩者各有自己的一份，
互不寫入。

理由與「誰擁有一個目錄，誰就對它有最終判斷」是同一條：一次發生該歸在既有哪一條、還是另立新條，
擁有這棵樹的 session 知道得比別人多。跨 repo 寫進別人的紀錄，與在別人的目錄裡改檔是同一件事。

The record lives at the git project root — this directory, not the parent repo. Each tree
keeps its own; neither writes into the other's. Which entry an occurrence belongs to is a
judgement the owning session is best placed to make.

---

## 1. 測試量到的是環境或工具，不是被測物

**5 次 / 3 天**（2026-08-20、2026-08-27、2026-08-29），單日最多 3 次。

| 日期 | 案例 | 量尺是什麼 | 症狀 |
|---|---|---|---|
| 2026-08-20 | T129d/T129e（DR） | 那個平台沒有 `stat` | 測試在 macOS 通過、guest 失敗，程式兩邊做的事一模一樣 |
| 2026-08-27 | T203e/f 等三項（d2cdc50） | macOS 沒有 `getent` | **在 macOS 上通過**，因為它走的是退路，不是它指名的那條路 |
| 2026-08-29 | T217i（KF） | guest 的 `diff` 不印 `<`／`>` | 回報 `0 diff lines`，而三個節點給 6 |

那個 2026-08-27 的 commit 標題就是這一條最好的名字：**「三項在 macOS 上通過、而理由都不是
重點的檢查」**。

### 共同形狀

**測試碰到的是環境，不是被測物。** 三次都一樣：程式在各平台行為相同，不同的是量尺。

而它會往**兩個方向**壞，其中一個方向沒有人會去看：

- **在缺少某個工具的平台上「通過」** —— 走了退路，而一個通過的案例不會有人回去讀。這是危險的那一半。
- **在輸出格式不同的平台上「失敗」** —— 樣式沒命中。這一半至少會叫。

### 矯正措施

一個測試只在某個平台失敗（或只在某個平台通過）時，**先問「它在那裡量的是不是同一樣東西」，
再問「被測物有沒有平台差異」**。順序反過來就會去改程式。

- 測試不得依賴外部工具的**輸出格式**（`diff` 的 `<`／`>`、`wc` 的補空白）。
- 也不得依賴某個工具的**存在**（`stat`、`getent`）——若它可能缺席，那個案例要 SKIP 並說出原因，
  不是安靜地走退路。
- 要比較就用 `cmp`，或在 zsh 裡逐行比。
- **四個節點裡三個通過時，那三個是診斷的證據，不是把它打發掉的理由。** 真正的行為差異不會只在
  一個平台出現而另外三個一致。

### 現行防範：一個具體形狀被擋住了，一般形式還沒有

跨了三天、共五次。依 skill 的判準（**知道之後仍再犯**，而非同一個下午沒意識到），需要的是
**強制檢查**，不是再寫一次提醒。

**已落地：T218**（2026-08-29）。任何 `.zsh` 呼叫 `stat(1)` 都會被測試抓到；註解裡的反面示範
被刻意排除。而這個檢查**自己也被證明會咬**——一個確實呼叫 `stat -c` 的探針檔會產生非空結果，
那是 KF 之後加上的要求：在故意弄壞被證明會產生非空結果之前，一個空的結果什麼都證明不了。

寫它時它抓到了**自己**：T218b 那行探針字串。那是一次正確的命中（對象是字串，不是呼叫），也
順帶證明了這個檢查真的在掃整棵樹，包括測試檔本身。探針的文字因此改成組出來的。

**仍缺：一般形式。** T218 擋的是「用 `stat(1)`」這一個具體形狀，擋不住這一條真正的樣子——
依賴別的外部工具的**輸出格式**（KF 那次是 `diff` 的 `<`／`>`），或依賴某個工具**存在**而在它
缺席時安靜地走退路（T129d 的 `stat`、T203e/f 的 `getent`）。**後者是危險的那一半，因為它的
症狀是「通過」。**

下一個候選：在 `run_csv2_test.zsh` 的報告裡，把「只有一個平台不同意」當成**獨立的一類**標出來
——今天它混在 FAIL 清單裡，與「四個平台一起失敗」看起來一模一樣，而兩者要做的事完全不同。

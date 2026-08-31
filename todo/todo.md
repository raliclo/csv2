# todo

Items that are decided but not yet designed in full. The design itself lives in
[../plan/plan.md](../plan/plan.md).

尚未完整設計、但已確定要做的項目。設計本體見 [../plan/plan.md](../plan/plan.md)。

---

## Where these came from / 這些項目的來源

Items here are **decided but not yet designed in full**. Two other places hold
different things, and mixing them up makes all three useless:

此處的項目是**已確定要做、但尚未完整設計**的。另有兩處放的是不同的東西，混在一起會
讓三者都失去作用：

| Place | Holds |
|---|---|
| [`../plan/plan.md`](../plan/plan.md) phase checkboxes | what is built, ticked only when its test passes / 已完成的部分，測試通過才打勾 |
| `plan.md` 待決問題 | questions with **no decision yet** -- not todos / 尚**未有決定**的問題，不是待辦 |
| this file | decided, not yet designed / 已決定、尚未完整設計 |

The 2026-08-16 code review (`sos/review.md`) raised two csv2 items, **both now
closed**: the guest comparison swallowing csv2's exit status (fixed -- csv2 now
runs on its own, its status is checked, and only stdout is hashed), and the work
not being reproducible from parent HEAD (fixed -- both repositories are pushed
and the gitlink is updated). Nothing from that review is outstanding for csv2.

2026-08-16 的 code review（`sos/review.md`）提出兩項與 csv2 有關的問題，**兩項均已關閉**：
guest 比對吞掉 csv2 的結束狀態（已修——csv2 單獨執行、檢查狀態，且只對 stdout 計算
雜湊），以及工作無法由 parent HEAD 重現（已修——兩個 repo 都已推送、gitlink 已更新）。
該次 review 中沒有任何 csv2 項目仍待處理。

---

## 1. Install into the package manager's bin directory / 安裝到套件管理員的 bin 目錄

**Status (corrected 2026-08-20): the drop-in half is DONE, and so is the local
Windows half. What remains -- a Homebrew tap and a public scoop manifest -- is
one blockage wearing two names: this repository is private, and both need a URL
the installing machine can fetch.
/ 狀態（2026-08-20 更正）：drop-in 那一半、以及 Windows 的「本機」那一半**都已完成**。
剩下的——Homebrew tap 與一份公開的 scoop manifest——是同一個阻礙的兩個名字：本 repo 尚未
公開，而兩者都需要一個「安裝端抓得到」的 URL。**

This line was corrected once already, on 2026-08-19, and it went stale again
within a day: "no Windows build exists" survived a round in which the Windows
node built, installed and ran the suite. Correcting a status does not make it
self-maintaining, which is the whole reason the paragraph below says a status
is a claim about the world with nothing re-checking it.
這一行在 2026-08-19 才更正過一次，一天之內又過期了：「沒有 Windows build」熬過了一個
「Windows 節點完成建置、安裝並跑完測試」的回合。更正一行狀態，不會讓它從此自我維護——
而那正是下面那一段說「一行狀態是一個關於世界的宣稱，沒有任何東西會重新檢查它」的理由。

This section said "to do" long after `install.zsh` was written, which is the
same decay the stale PASS counts had: a status line is a claim about the world
and nothing re-checks it. `plan/plan.md`'s phase 7 had it ticked; this file did
not. When two places disagree about whether something is done, the one with a
test behind it wins -- and here that is the plan, because `install.zsh` ends by
running `csv2 --version` in a fresh shell and comparing.

這一節在 `install.zsh` 寫好之後很久仍寫著「待辦」，而那與那些過期的 PASS 數量是同一種衰減：
一行狀態是一個關於世界的宣稱，而沒有任何東西會重新檢查它。`plan/plan.md` 的第 7 階段已經
打勾，這個檔案沒有。**當兩個地方對「這件事做完了沒有」意見不同時，以「背後有測試的那一個」
為準**——而此處那是計畫，因為 `install.zsh` 的結尾是「在全新 shell 中執行 `csv2 --version`
並比對版本」。

| Part | State |
|---|---|
| drop-in `install.zsh` | **done** — `$(brew --prefix)/bin`, `/usr/local/bin` where the guest's PATH already has it, `~/.local/bin` fallback, `--uninstall`, `--dry-run`, verified by running / **已完成** |
| Homebrew tap + formula | blocked: `raliclo/csv2` is private / 被擋住：repo 尚未公開 |
| Windows scoop shim (the local half) | **done, and by not creating one** — `install.zsh` writes to `%LOCALAPPDATA%\csv2\csv2.exe`, the path the machine's existing shim already names; measured 2026-08-20: `command -v csv2` resolves through `~/scoop/shims/csv2.shim` to the build just made, and the suite runs there with no failures, skipping only what MSYS2 cannot offer / **已完成，而且是靠「不建立 shim」完成的**——`install.zsh` 寫到該機器既有 shim 本來就指著的位置；2026-08-20 實測如上。**一份公開的 scoop manifest（讓別人 `scoop install csv2`）與 Homebrew tap 被同一件事擋著：repo 尚未公開**——`plan/plan.md` 第 7 階段講的是那一半，這一列講的是本機這一半 |

`install.zsh` puts the built `csv2` binary where the platform's package manager
already has a directory on `PATH`, so that using the tool does not require
remembering a path.

`install.zsh` 把建好的 `csv2` 放到該平台套件管理員既有的、且已在 `PATH` 上的目錄，
使得使用這支工具不必記住任何路徑。

### macOS and Linux: ask `brew`, never hardcode / macOS 與 Linux：問 `brew`，絕不寫死

There are three different answers and **all three are wrong on the other two
platforms**:

| Platform | Homebrew prefix |
|---|---|
| macOS, Apple Silicon | `/opt/homebrew` — verified on this machine |
| macOS, Intel | `/usr/local` |
| Linuxbrew | `/home/linuxbrew/.linuxbrew` |

有三個不同的答案，而**任何一個寫死都會在另外兩個平台上錯**。

So the install directory is `$(brew --prefix)/bin`, obtained by running `brew`,
never a literal path. Hardcoding `/usr/local/bin` is the common version of this
mistake and it silently installs to a directory that exists but is not the one
`brew` is using.

因此安裝目錄一律是 `$(brew --prefix)/bin`，由執行 `brew` 取得，不寫任何字面路徑。
寫死 `/usr/local/bin` 是這個錯誤最常見的形式：它會安靜地裝進一個「存在、但不是
`brew` 正在使用」的目錄。

### This is NOT a Homebrew install, and the installer must say so / 這不是 Homebrew 安裝，安裝程式必須講明

Copying a binary into `$(brew --prefix)/bin` puts it in Homebrew's directory
without Homebrew knowing anything about it. Concretely:

- `brew list` will not show it
- `brew upgrade` will never update it
- `brew doctor` will report it as an unbrewed file
- a future `brew` operation on that directory may remove or overwrite it

把執行檔複製進 `$(brew --prefix)/bin`，是放進 Homebrew 的目錄而 Homebrew 對它一無所知：
`brew list` 不會列出它、`brew upgrade` 不會更新它、`brew doctor` 會回報它是 unbrewed
檔案，日後對該目錄的 `brew` 操作也可能移除或覆蓋它。

Therefore:

- The installer **prints this** rather than leaving it to be discovered. A user
  who believes `brew upgrade` maintains this binary will run an old version for
  a long time without noticing.
- `install.zsh --uninstall` **must exist**, because `brew uninstall` cannot
  remove something brew never installed.

因此：安裝程式**要主動印出這件事**，而不是留給使用者日後自行發現——以為
`brew upgrade` 會維護它的人，會在不知情的狀況下用著舊版本很久；並且
`install.zsh --uninstall` **必須存在**，因為 `brew uninstall` 無法移除 brew 沒裝過的東西。

### A real formula needs a public repository / 真正的 formula 需要公開的 repo

The proper answer is a tap (`raliclo/homebrew-tap`) with a formula. It is
blocked, and the blocker is specific rather than vague: **`raliclo/csv2` is
private**, and a Homebrew formula needs a source URL that the machine running
`brew install` can fetch.

正解是建立 tap（`raliclo/homebrew-tap`）與 formula。目前被擋住，而阻礙是具體的：
**`raliclo/csv2` 是 private**，而 Homebrew formula 需要一個「執行 `brew install`
的那台機器抓得到」的來源 URL。

So this is deferred until, and only until, the repository is made public. Until
then the drop-in above is the whole story, and the caveats above are why it has
to be honest about what it is.

因此這一項延後到 repo 公開之後才做，在那之前上述的 drop-in 就是全部——而正因如此，
它必須誠實說明自己是什麼。

### No brew: fall back to `~/.local/bin` / 沒有 brew 時退回 `~/.local/bin`

It needs no privileges, it conflicts with no package manager, and it is the
conventional user-level location.

**But check it is actually on `PATH`, and warn loudly if it is not.** A binary
installed to a directory that is not on `PATH` produces `command not found`,
which reads as "the install failed" when in fact it succeeded — and the user
will go looking in the wrong place.

它不需要權限、不與任何套件管理員衝突，也是慣用的使用者層級位置。**但必須檢查它確實在
`PATH` 上，不在就要大聲警告**：裝到不在 `PATH` 的目錄會得到 `command not found`，
那看起來像「安裝失敗」，實際上安裝是成功的——於是使用者會去查錯的方向。

### Windows: a scoop shim / Windows：scoop shim

Shims live in `%USERPROFILE%\scoop\shims` for a user install, `$env:SCOOP\shims`
when `SCOOP` is set, and `C:\ProgramData\scoop\shims` for a global install.
Resolve it by asking scoop, for the same reason as `brew --prefix`.

shim 位於使用者安裝的 `%USERPROFILE%\scoop\shims`、設有 `SCOOP` 時的
`$env:SCOOP\shims`，或全域安裝的 `C:\ProgramData\scoop\shims`。與 `brew --prefix`
同理，要用詢問的方式取得，不要寫死。

**The blocker to state up front: there is no Windows build of csv2.** The
targets today are the macOS host and aarch64 Linux. A shim has to point at
something, so this item is really a choice between two:

**必須先講明的阻礙：csv2 目前沒有 Windows build。** 現有目標是 macOS host 與
aarch64 Linux。shim 必須指向某個東西，所以這一項實際上是二選一：

| Option | Cost |
|---|---|
| Native Windows build | Swift on Windows — a real porting effort, and a third platform to keep green |
| `wsl.exe` wrapper shim | Cheap, and **the project has already done this**: `raliclo/zsh`'s `develop` branch is a Windows portable runtime built on exactly this pattern (MSYS2 shim, scoop packaging, `wsl.exe` wrapper) |

The wrapper is the recommendation. It reuses a pattern this project has already
paid for, and it does not add a platform to the test matrix — the binary being
wrapped is the Linux one that is already tested.

建議採用 wrapper：它沿用本專案已經付出過代價的模式，且不會為測試矩陣增加一個平台
——被包起來的執行檔就是那個已經在測的 Linux 版。

**Carry over one lesson from `swift_tar/build_tool_install-win.sh`:** check for
a scoop package with `scoop list <name>`, not by looking on `PATH`. Some names
resolve to a tool bundled with a different package, so a `PATH` check reports
"already installed" for something that is not the package you wanted.

**沿用 `swift_tar/build_tool_install-win.sh` 的一個教訓**：檢查 scoop 套件要用
`scoop list <name>`，不要查 `PATH`。有些指令名會解析到「別的套件所附帶的工具」，
於是查 `PATH` 會對一個並非你要的套件回報「已安裝」。

### Verify by running it, not by checking the file exists / 以執行來驗證，而非檢查檔案存在

The install step ends by running `csv2 --version` **in a fresh shell** and
comparing the output against the version just built.

Checking that the file landed proves nothing about which `csv2` will actually
run. `PATH` order decides that, silently, with no diagnostic — and that exact
risk is one of the reasons the plan rejected the name `csv` in the first place.
An installer that verifies the wrong thing is worse than one that verifies
nothing, because it reports success.

安裝的最後一步是**在一個全新的 shell 中**執行 `csv2 --version`，並與剛建置的版本比對。

檢查「檔案有沒有放進去」對「實際會執行到哪一支 `csv2`」毫無證明力：那是由 `PATH`
順序決定的，靜默、且沒有任何診斷訊息——而這正是計畫當初否決 `csv` 這個名字的理由之一。
一個驗證了錯誤對象的安裝程式，比完全不驗證更糟，因為它會回報成功。


---

## 2. Closed on 2026-08-16 / 2026-08-16 已關閉

Three items that were listed here are now implemented and tested. They are
recorded in [`../plan/plan.md`](../plan/plan.md) under "收尾時定案的三件事", with
the reasoning, and their tests are T48-T51. Kept as a short note rather than
deleted, so that a reader who remembers seeing them here can tell they were
finished rather than dropped.

原先列在此處的三項現已實作並通過測試。理由記在
[`../plan/plan.md`](../plan/plan.md) 的「收尾時定案的三件事」，測試為 T48–T51。
此處保留簡短紀錄而非直接刪除，讓記得曾在這裡看過它們的人能分辨那是「做完了」而不是
「被丟掉了」。

| Was | Now |
|---|---|
| `--a1` / `--physical` untested | shape fixed in the plan first, then T49 -- including the A1 path past column Z, which had never run / 先在計畫中訂下形狀才寫 T49，含從未被執行過的「Z 之後」路徑 |
| `-debug` had one of five levels | T50. A TRACE line was added first; a flag lowering the threshold to a level nothing logs at would be an option that does nothing / T50。先加了一行 TRACE 才加旗標——把門檻降到沒有東西記錄的層級，會是一個什麼也不做的選項 |
| an index only appeared as a side effect | `--build-index`, T51, with the rule intact: it changes no output and never fails the operation / `--build-index`、T51，並守住規則：不改變輸出、絕不使操作失敗 |

## 3. The UAX #11 width table is a hand-written subset / UAX #11 寬度表是手寫的子集

**Status: accepted, and now pinned by a test. / 狀態：接受現狀，且已有測試釘住。**

`src/Width.swift` carries about 90 ranges chosen to cover what this project
actually stores: Han, Hangul, fullwidth forms and the emoji blocks. It is not
the full East Asian Width table and it does not track Unicode revisions, so an
emoji added in a later Unicode version measures as width 1 and `--pretty`
misaligns that row by one column.

`src/Width.swift` 含約 90 個區間，涵蓋本專案實際會儲存的東西：漢字、諺文、全形形式與
emoji 區塊。它不是完整的 East Asian Width 表，也不追蹤 Unicode 修訂，因此較新 Unicode
版本新增的 emoji 會被算成寬度 1，`--pretty` 那一列就會歪一欄。

**What changed:** T48 now pins every sample from the plan's measured table --
`ok` 2, `套件名稱` 8, and each of the five emoji forms 2. That does not make the
table complete, but it means a regression in the ranges it DOES cover is caught,
which is the part that was missing.

**已改變的部分：** T48 現在釘住了計畫實測表中的每一個樣本——`ok` 2、`套件名稱` 8，
以及五種 emoji 形式各為 2。那不會讓這張表變完整，但它讓「已涵蓋範圍內的退步」會被抓到，
而那正是先前缺少的部分。

Still acceptable because `--pretty` is opt-in and the default minimal form needs
no width information at all -- that is precisely why the default is the minimal
form. It becomes a real problem only if `--pretty` ever becomes the default,
which it should not.

之所以仍可接受：`--pretty` 是選擇加入的，而預設的最小形式完全不需要寬度資訊——那正是
預設採用最小形式的理由。只有在 `--pretty` 變成預設時它才會成為真正的問題，而它不應該
變成預設。

The honest way to close it would be generating the ranges from the Unicode
character database rather than hand-picking them, which is a build-time
dependency this project does not currently have and should not take on for one
opt-in flag.

真正把它關閉的做法，是從 Unicode 字元資料庫「產生」這些區間而非手選——那是本專案目前
沒有、也不該為了一個選擇加入的旗標而引入的建置期依賴。

## ~~平行搜尋的記憶體沒有上界~~(2026-08-20 修正,見 known-defects 的 AR)

| 檔案大小 | 單執行緒峰值 RSS | 平行峰值 RSS |
|---|---|---|
| 25,888,899 | 9,207,808 | 60,456,960 |
| 51,888,899 | 9,207,808 | 102,023,168 |

**單執行緒對兩種大小都是 9.2 MB;平行約為檔案的兩倍,隨輸入線性成長。** 而它與
`CSV2_PARALLEL_CHUNK_BYTES` 無關——chunk 從 256 KiB 調到 16 MiB,RSS 都落在 50–60 MB,
所以「調小 chunk」救不了它。

README 已改為如實陳述(AO)。**尚未決定的是要不要改程式。**

要點:

- T9a／T9b／T9c 守的是 `-si`／`-so` 串流路徑的「RSS 不隨輸入成長」,而它們是對的。
  **沒有任何測試量過平行路徑的記憶體。** 無論最後怎麼決定,那個測試都該補上——否則
  下一次有人動平行路徑時,同樣沒有東西會說話。
- 1 GiB 的檔案在平行路徑上會是約 2 GiB。那可能超過使用者願意付的代價,而目前唯一的
  逃生口是 `CSV2_PARALLEL_MIN_BYTES` 調高到把平行整個關掉。
- 若要改:先弄清楚那兩倍是誰持有的。它不隨 chunk 變,所以不是「每個工作者各持一塊」。

Parallel search memory is unbounded: single-threaded peak RSS is 9 MB for both
a 25 MB and a 52 MB file, while parallel is roughly twice the file and grows
with it. It does not track CSV2_PARALLEL_CHUNK_BYTES, so shrinking chunks does
not help. The README now states this (AO); whether to change the code is open.
Whatever is decided, the missing test should be added -- T9a/b/c cover the
streaming path only, and nothing has ever measured the parallel path's memory.


**上面那一節已經解決,保留是因為它的推論錯了而那個錯誤值得留著。** 它假設記憶體由
「同時在飛的區塊」持有,並據此判斷「調小 chunk 救不了」。真正的成因是 `planChunks`
少了一個 autorelease pool——同一個缺陷的第三個發生地。拆穿那個假設只花了一次量測:
把批次強制降到 1,峰值 RSS 只變動百分之零點五。修正後 615 MB 的檔案從 608 MB 降到 23 MB。
測試 T108 已補上,那也是這一節當初點名缺少的東西。

## 4. 讓 `--physical` / `--a1` 的位址可以被接受,並且驗證它

`--physical` 印 `1:1@L2`、`--a1` 印 `1:1 [A2]`。目前把它們餵回去會被拒絕,而訊息會指出
那段結尾是裝飾(DX、T132d/e)。**拒絕是對的,但不是最好的答案。**

更好的答案是接受它們,並且**驗證那段裝飾**:`@L2` 說「這筆在第 2 實體行」,若檔案在你搜尋
之後變了,那個斷言就不成立,而那正是應該拒絕的時刻——一個帶著自我驗證的位址,比一個只能
自己記得「當時是第幾行」的位址有用得多。

需要的是「由紀錄號求出實體行號」這條路徑。索引 sidecar 已經記錄了紀錄邊界,但那是位元組
位移而非行號,而含有內嵌換行的檔案兩者不相等——這正是 `csv2view` 也在等的那一項
(見 README 的「Designed but not built」)。兩者可以一起做。

Accept `--physical` / `--a1` addresses AND validate the decoration: `@L2` is a
claim about where that record was, and refusing when it no longer holds is more
useful than refusing the notation. Needs record-number-to-physical-line, which
is the same thing csv2view is waiting for.


---

## 5. ~~第 11 階段的六條：一個編輯器有、而這個沒有的東西~~（2026-08-29 定案，2026-08-30／31 實作完成）

**六條全部落地，實測確認過每一條都在**（2026-09-01 的 code review）：`-update-where`
（唯一命中改值、多重命中列出每一個位址後拒絕、零命中拒絕）、`--value-file`／`--value-stdin`
（NUL 完整往返——那正是命令列傳不了、而這個旗標存在的理由）、`--dry-run`（不寫、無殘留暫存檔、
與 `--backup` 互斥）、`--backup`（含 `-append` 快路徑與 symlink 輸入兩個曾經漏掉的案例）、
`--md-style preserve`（編輯路徑也保留排版：只有被改的列變 compact）、`--json` 錯誤物件
（走 stderr、kebab-case code、結束狀態維持 1）。

計畫的核取方塊只剩「四個平台」未打勾。下方原文保留，因為它記著每一條的**理由**，而理由不會
因為實作完成而失效。



**設計本體在 [`../plan/plan.md`](../plan/plan.md) 的第 11 階段**，此處只列出「要做什麼」與
「彼此的相依」。每一條在寫進計畫之前都先實測過現況——KA 的教訓是「一張表的形式」很容易被當成
「一條具體的條目」引用出去。

決定連同一條貫穿的約束一起給出：**輸出永遠以 LF 作為行尾。** 那不是附帶條件，它是第 3 條當時
還沒有答案的那個衝突（散文原樣保留 vs 分隔符永遠 LF）的答案。

### 相依順序，不是優先順序

Markdown 那三條是一串，而**中間那一條是前提**：

```
2a. 編輯可以輸出 -md   ←── 沒有它，下面兩條都做不到
      ↓
1.  --md-table N --in-place   （把改好的表寫回原文件，散文保留）
      ↓
3a. --md-style preserve|compact|pretty   （預設 preserve）
```

`2a` 不是一個獨立提案。今天 `-md is an output shape and an edit writes CSV, so the two
cannot be combined` 這道拒絕，正好禁止「編輯一個 `.md` 並把 `.md` 寫回去」——而那就是第 1 條
本身。那道拒絕的推理在它涵蓋的範圍內成立，它漏掉的是：只有在**形狀與目的地互相矛盾**時兩者才
衝突，而 `-update … -md -o out.md` 是把同一種形狀說了兩次。

其餘三條彼此獨立，可以任何順序做。

| | 項目 | 一句話 |
|---|---|---|
| 2a | 編輯可以輸出 `-md` | 形狀與目的地一致時不再拒絕。前提。 |
| 1 | `--md-table N --in-place` | 只換掉第 N 張表的那幾行，散文帶著走（行尾正規化為 LF） |
| 3a | `--md-style preserve\|compact\|pretty` | 預設 `preserve`；輸入不是 `.md` 時 `preserve` 等於 `compact` |
| 4 | `-update-where OLD NEW` | 整格相等才算命中；0 個與 >1 個**都拒絕**，>1 時列出每一個位址 |
| 5 | `--value-file PATH` / `--value-stdin` | 檔案的位元組**就是**值，不裁切；只在「恰好一個吃值的動詞」時允許 |
| 6 | `--dry-run` | 一個旗標不是兩個（提案的 `--diff` 與它是同一件事）；印逐格前後對照，走 stdout |
| 7 | `--json` 錯誤物件 | 走 stderr、一行；**離開碼維持 1**；代碼是穩定的 kebab-case 字串 |
| 8 | `--in-place` 的 `--backup` | `-append --in-place` 是唯一沒有暫存檔可退的編輯 |

### 兩條沒有進來，理由不同

**「非 CSV 檔的 raw/line 模式」不做——實測發現已經可用。** `.txt`、`.swift` 與任何不是
`.csv`／`.csv2` 的副檔名，早就以 `lines` 讀進來，而 `-update 2:1` 在一個 `.swift` 上會改一行、
其餘不動，tab 與行尾空白都活著。代價有兩個而且都有文件：CRLF 會變 LF（**包括沒被編輯的那些
行**），沒有結尾換行的檔案會被補上一個。那兩件事現在是已定的政策，不再是開著的問題。

**`--backup` 在 2026-08-29 的第二份清單裡沒有出現，但也沒有被撤回。** 它留在這裡（第 8 項）。
若要撤回，說一聲就好——這裡不替使用者刪掉一個他已經說過要做的東西。

### 第 3a 條的量測（獨立回報，已在此重現）

同一天由 Windows 節點回報，對象是經 scoop shim 安裝的 `csv2 0.1.0 (30425be)`。四行的表，
改一格：

| 算繪模式 | 變動的 diff 行數 |
|---|---|
| 預設 `-md` | 6 |
| `--pretty` | 6 |
| 一個保留排版的寫出器會給 | 2 |

`--pretty` **連分隔列也會加寬**（`|---|` → `|------|`），因此它不是比較小的改動；它在第一次
接觸就是整表重寫，即使什麼都沒編輯。而「統一用 `--pretty` 就好」也不成立：只要任何一個值的
寬度改變，它就把每一列重排一次。

**值本身早就逐位元正確**——儲存格內被跳脫的 `\|`、backtick、`**bold**` 都活過往返——因此
`preserve` 只需要帶著 padding 走，永遠不需要對值做推理。那讓這件事是格式問題，不是資料問題，
也決定了它的優先順序：`git blame` 是這筆代價中比較持久的那一半，一次 code review 是一位讀者
一次，而 blame 是之後每一位讀者。

---

## `.csv2` 的讀取比 `.csv` 貴 1.8 倍——可能有一條不複製的快路徑（2026-08-26，JO）

第 77 回合量到、我親手重現：45 萬筆相同資料、輸出逐位元相同，`-r` 是 422 ms（`.csv`）對
767 ms（`.csv2`）。差值在 `-r`、`--json`、`-md` 上都是平的（約 350 ms），因此是「每個值都要付
的工」。**兩份 fixture 裡一個反斜線都沒有**，所以付的是「找跳脫」的錢，不是「解跳脫」的錢。

未評估的方向：欄位裡沒有 `\` 時走一條不配置、不複製的路徑（memchr 找 `\`，找不到就把原 slice
交出去）。若那條路徑存在而沒有被走到，這 350 ms 大部分是可以拿掉的。

**在動手之前**：先量「有多少比例的欄位真的含有跳脫」，以及那條路徑現在是不是已經存在——這棵樹
今天已經有一次「以為知道而沒有量」的紀錄（JM）。已寫進 README 作為使用者要知道的成本；這一條
是「能不能讓那個成本消失」，不是同一件事。

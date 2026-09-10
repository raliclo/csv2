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

> **狀態（2026-09-10 逐項重測）：五件全部完成。剩下的不是「做」，是「跑一次」。**
>
> Windows 的 scoop shim 於 2026-09-10 完成（`target_dir()` 改為讀 `csv2.shim`，在節點上雙向實測）。
> 而先前記著的那個阻礙——「兩者都還需要一個安裝端抓得到的 URL」——在 v0.1.1 出貨後不存在了：
> `Formula/csv2.rb` 有三個 v0.1.1 的 url 與 hash，`scoop/csv2.json` 有一個，全部由 `publish.zsh`
> 從封存產生、讀回確認，並在發布後從公開 URL 重新下載比對過。
>
> **仍然沒做的只有一件，而它正是這個專案自己的判準：實際跑一次安裝。**
> `brew install raliclo/csv2/csv2` 上一次實跑是 2026-09-08 的 v0.1.0（那一次找出了缺少
> `brew trust`——**那是靠跑它找到的，不是靠讀它**）。v0.1.1 的兩份套件檔尚未被任何一次真正的
> 安裝執行過。`scoop install csv2` 則從未跑過：那台機器上有一個 scoop 不管理的手放 shim，
> 安裝會與它相撞。
>
> **這件事需要動到使用者機器上的 Homebrew／scoop 狀態，所以留給人決定，不由測試代跑。**
>
> Status re-measured 2026-09-10: all five parts are done, and what remains is not building
> something but RUNNING it. The Windows shim landed today; the blockage recorded here -- both
> halves needing a URL the installing machine can fetch -- ended when v0.1.1 shipped. What has
> not happened is an actual install from the published v0.1.1 files. `brew install` was last run
> for real against v0.1.0 on 2026-09-08, which is how the missing `brew trust` was found: by
> running it, not by reading it. `scoop install` has never been run, because that machine
> carries a hand-placed shim scoop does not manage. Both change state on the user's machine, so
> the decision is theirs rather than a test's.
>
> ---
>
> **以下為 2026-09-05 那次盤點的原文，保留。**
>
> | 這一條宣稱的 | 現況 |
> |---|---|
> | 問 `brew`，絕不寫死 | ✅ `install.zsh` 裡 `brew --prefix` 出現 3 次 |
> | 明說「這不是 Homebrew 安裝」 | ✅ |
> | 沒有 brew 時退回 `~/.local/bin` | ✅ |
> | **Windows 的 scoop shim** | ✅ 2026-09-10 完成——`target_dir()` 現在讀 `csv2.shim`，在節點上雙向實測 |
> | 以執行來驗證，而非檢查檔案存在 | ✅ 以 `--version` 驗證 |
>
> 真正的 Homebrew formula 先前記著「被『`raliclo/csv2` 尚未公開』擋住」。**2026-09-08 實測時
> 那個 repo 已經是公開的、不帶憑證也抓得到**（`git ls-remote https://github.com/raliclo/csv2`
> 回傳 HEAD），所以那個阻礙不在了。剩下的是真正的工作：一個有版本的、可下載的產物。
>
> **這段狀態是因為一次盤點才寫的**：先前這一條看起來像「整條未開始」，而它其實只差一件。
> 一個「未關閉」的項目與一個「幾乎做完」的項目，在標題上長得一模一樣。
>
> Status measured item by item on 2026-09-05: four of the five are done, and only the Windows
> scoop shim is missing -- `install.zsh` has no `scoop` outside comments. The real Homebrew
> formula is separately blocked on the repository being private. Written down because a
> stocktake read this as "not started" when only one part remained: an open item and an
> almost-finished one look identical from the heading.

> **2026-09-10：Windows 的 shim 那一項完成了，而它揭示的是一個假設而不是一個缺口。**
>
> `install.zsh` 的 Windows 分支原本無條件印出 `%LOCALAPPDATA%/csv2`，附一段註解說明「那台機器上的
> shim 指的正是那個目錄」。**它確實是**——在節點上量測，`csv2.shim` 的內容是
> `path = "C:\Users\lowei\AppData\Local\csv2\csv2.exe"`。但那是一個關於**某一台機器**的事實，
> 而它上面六行的 macOS 分支並沒有對 Homebrew 做等價的假設：那裡跑的是 `brew --prefix`。
>
> 現在它**問 shim**。兩個方向都在節點上實測過：
>
> | 測試 | 結果 |
> |---|---|
> | 真實的 shim | `/c/Users/lowei/AppData/Local/csv2`（與寫死的值相同——所以這一半什麼都沒證明） |
> | 一個指向 `FAKEDIR` 的假 shim 放在 PATH 前面 | `/c/Users/lowei/FAKEDIR` ✅ **它真的在讀** |
>
> 第一次的「假 shim」測試沒有咬——**而錯的是測試**：我寫的是 `PATH=x cmd`，那只作用於 `cmd`
> 那一個命令，而 `command -v` 是稍後在函式裡執行的。改成先 `export` 再呼叫才測到。**一個
> 「沒咬」的結果，第一件要懷疑的是測試本身。**
>
> **仍未處理，且刻意不猜**：一個由 scoop **自己管理**的 csv2。那個節點上 `scoop prefix csv2`
> 回答「Could not find app path」——那裡的 shim 是手放的——所以那條分支在這裡無法被執行，而
> 一個沒被測過的拒絕比一個誠實的缺口更糟。真的遇到時要決定的是：寫進 scoop 的 app 目錄會與
> scoop 的 hash 驗證與升級衝突，所以正確的行為多半是**拒絕並要求用 `scoop update csv2`**。
>
> The Windows shim item is done. The branch used to print `%LOCALAPPDATA%/csv2` unconditionally
> with a comment saying the shim on that machine names that directory. It does -- measured --
> but that is a fact about one machine, and the macOS branch six lines up runs `brew --prefix`
> rather than assuming the equivalent. It now asks the shim, verified in both directions on the
> node: the real shim gives the same answer the hardcoded value did, which proves nothing on its
> own, and a fake shim naming FAKEDIR is followed to FAKEDIR, which does. The first attempt at
> that second half did not bite, and the TEST was wrong: `PATH=x cmd` applies to that one
> command, while `command -v` runs later inside the function. A check that does not bite is
> first of all a suspect check. Still unhandled and deliberately not guessed at: a csv2 that
> scoop itself manages, which cannot be exercised on that node.

**Status (corrected 2026-09-08): the drop-in half is DONE, and so is the local
Windows half. What remains -- a Homebrew tap and a public scoop manifest -- was
recorded as one blockage wearing two names, "this repository is private". THAT
IS NO LONGER TRUE: on 2026-09-08 `git ls-remote https://github.com/raliclo/csv2`
returned HEAD with no credentials at all. What both still need is a URL the
installing machine can fetch, and that is now ordinary work -- a tag, a
downloadable artefact, a sha256 -- not a blockage.
/ 狀態（2026-09-08 更正）：drop-in 那一半、以及 Windows 的「本機」那一半**都已完成**。
剩下的——Homebrew tap 與一份公開的 scoop manifest——先前被記成同一個阻礙的兩個名字：「本 repo
尚未公開」。**那已經不成立**：2026-09-08 時 `git ls-remote https://github.com/raliclo/csv2`
在完全不帶憑證的情況下回傳了 HEAD。兩者仍然需要一個「安裝端抓得到」的 URL，但那現在是**普通的
工作**——一個 tag、一份可下載的產物、一個 sha256——而不是一個阻礙。**

*這一段是第三次因為過期而被更正（2026-08-19、2026-08-20、2026-09-08），而前兩次的更正就寫在下面。
一個寫進檔案裡的「阻礙」，會與它所描述的世界反向漂移，而沒有任何東西會回報它——那正是
`todo/known-defects.md` 開頭要求「缺陷清單不要放在指令檔裡」的同一條理由。下次要寫阻礙時，
連同「怎麼一行指令驗證它還成不成立」一起寫。*

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
| Homebrew tap + formula | **no longer blocked** — the repo is public and fetchable anonymously as of 2026-09-08; what remains is a tagged, downloadable artefact with a sha256 / **阻礙已解除**——2026-09-08 起該 repo 公開且匿名抓得到；剩下的是一個有 tag、可下載、附 sha256 的產物 |
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

## ~~4. 讓 `--physical` / `--a1` 的位址可以被接受,並且驗證它~~ 已完成（2026-09-10）

### 2026-09-10：完成

四個動詞（`-get`、`-update`、`-delete -cell`、`--search-cell`）都接受帶裝飾的位址，並驗證那個
宣稱。驗證放在**分派之前的單一位置**（`validateLocationClaim`），四個動詞因此不可能各自漂走。

實作時發現的、原本沒有寫在這一節裡的三件事：

1. **兩種記法宣稱的是不同的東西。** `@L` 是實體行（`Record.line`），`[A3]` 是試算表列
   （紀錄號＋標頭列數）**與欄**。它們只在「紀錄跨行」時不同，而 `Ops.swift` 早就把這件事寫在
   印出它們的地方。因此 `[A3]` 那一半根本不需要掃描——它是算術——**只有 `@L` 需要停用索引 seek**。
2. **兩段裝飾會同時出現。** `--physical --a1` 一起給時印的是 `3:1@L6 [A4]`，而只剝一層會留下
   `3:1@L6`，接著以「沒有這個欄名」失敗。改成剝到沒有為止，並且**每一個宣稱都驗**——只驗第一個
   等於一道「在它沒看的那一半上放行」的守衛。
3. **`[A3]` 也宣稱了欄**，所以它抓得到一個「列的檢查」看不見的欄列對調。

`T132d`／`T132e` 原本斷言「帶裝飾的位址會被拒絕」，現在改成斷言那趟**來回**：報告印出來的位址
貼回去，要拿到報告裡那個值。那是比原本更強的斷言。

T302 共 19 個案例：四個動詞 × 兩種記法 × 成立／不成立，加上兩段並存時各自出錯、欄位對調、
有索引時仍然正確（那是唯一說出「seek 被停用」的案例），以及「沒有裝飾的位址不受影響」。
fixture 刻意含一筆跨三行的紀錄——**那是兩種記法唯一會不一致的情況，沒有它的 fixture 會讓一個錯的
實作把兩半都通過。**

Done. All four verbs accept a decorated address and validate the claim, in ONE place before the
dispatch so they cannot drift apart. Three things the section above did not know: the two
notations claim DIFFERENT things (physical line versus spreadsheet row plus column), so only the
`@L` half needs the index seek disabled and the `[A]` half is arithmetic; both decorations
appear together when both flags are given, and stripping once left an address that failed as a
column name; and `[A3]` claims a column too, which catches a transposition the row check cannot
see. T132d/e asserted the old refusal and now assert the round trip, which is the stronger
claim. T302 is nineteen cases over four verbs, two notations, both directions, with a fixture
carrying a record that spans three lines -- the only case where the notations disagree, and
without it a wrong implementation passes both halves.



`--physical` 印 `1:1@L2`、`--a1` 印 `1:1 [A2]`。目前把它們餵回去會被拒絕,而訊息會指出
那段結尾是裝飾(DX、T132d/e)。**拒絕是對的,但不是最好的答案。**

更好的答案是接受它們,並且**驗證那段裝飾**:`@L2` 說「這筆在第 2 實體行」,若檔案在你搜尋
之後變了,那個斷言就不成立,而那正是應該拒絕的時刻——一個帶著自我驗證的位址,比一個只能
自己記得「當時是第幾行」的位址有用得多。

需要的是「由紀錄號求出實體行號」這條路徑。索引 sidecar 已經記錄了紀錄邊界,但那是位元組
位移而非行號,而含有內嵌換行的檔案兩者不相等——這正是 `csv2view` 也在等的那一項
(見 README 的「Designed but not built」)。兩者可以一起做。

### 2026-09-10：這一節的前提是錯的，而修正它讓這件事小了一圈

上面寫著「需要的是**由紀錄號求出實體行號**這條路徑。索引 sidecar 已經記錄了紀錄邊界，但那是
位元組位移而非行號」。**讀程式碼之後：那條路徑已經存在。** `Record` 在 `src/Core.swift:256` 上
就有 `var line: Int`，而解析器一路在維護它——`--physical` 印得出 `@L2` 正是因為它拿得到。

真正的限制窄得多，而且只有一條：**索引 seek 之後行號不再是真的。** `planIndex()` 會從一個
位元組位移開始讀（`index hit: record N via grid point … at byte offset`），而那時已經跳過的
換行沒有被數。

於是設計決定是：**位址帶著位置宣稱時，不走索引 seek。** 那條宣稱講的正是檔案的實體排版，而索引
記的不是排版——用一個記不住行號的加速路徑去驗證一個關於行號的宣稱，本來就不成立。代價只落在
「有帶裝飾的那一次呼叫」上。

### 要做的四件事

1. **`parsedLocation(token)`**：擴充既有的 `strippedLocation()`（`src/main.swift`），讓它除了回傳
   去掉裝飾的字串，也回傳那個宣稱：`@L<n>` → 行號 n；` [A<n>]` → 欄號（由字母換算）與行號 n。
   `[A2]` 同時宣稱了欄與行，兩者都要驗。
2. **`parseCellAddress()`**：裝飾在**欄的那一段**上（`1:1@L2` 以 `:` 切開後是 `1` 與 `1@L2`）。
   剝掉它、把宣稱記進 `Options`。四個呼叫點：`--search-cell`、`-get`、`-update`、`-delete -cell`。
3. **索引**：有宣稱時停用 seek（不是停用寫入）。
4. **驗證**：在那一筆被取到的地方比對 `r.line`；不符就以「宣稱不成立」拒絕，而**不是**以「格式
   錯誤」拒絕——那兩者要說的是完全不同的事。

### 為什麼「不符」時要拒絕

`@L2` 是一個關於「你搜尋當下那個檔案」的宣稱。若檔案之後變了，那個宣稱就不成立——而那正是
應該拒絕的時刻。**一個帶著自我驗證的位址，比一個只靠自己記得「當時是第幾行」的位址有用得多**：
後者會安靜地編輯到別的紀錄。

### 測試要涵蓋的（每一項都要證明它會咬）

- 四個動詞 × 兩種記法 × （宣稱成立／宣稱不成立）
- **一個含有內嵌換行的檔案**——那是唯一「行號 ≠ 紀錄號」的情況，也是這整件事存在的理由
- 有索引存在時仍然正確（也就是 seek 真的被停用了）
- `[A2]` 的欄宣稱與位址的欄不一致時要拒絕

The premise of this section was wrong, and correcting it makes the work smaller. It said a
record-number-to-physical-line path was needed. `Record.line` already exists in Core.swift and
the parser maintains it -- which is how `--physical` prints `@L2` at all. The single real
constraint is narrower: after an INDEX SEEK the line number is no longer true, because the
newlines skipped over were never counted. So the design decision is that an address carrying a
location claim does not take the index seek. The claim is about physical layout; the index does
not record layout, and validating a claim about line numbers with a path that cannot count
lines was never going to work. The cost falls only on the decorated call.

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

## ~~`.csv2` 的讀取比 `.csv` 貴 1.8 倍~~（2026-08-31 由 `ba16417` 修正，2026-09-05 複量確認）

第 77 回合量到、我親手重現：45 萬筆相同資料、輸出逐位元相同，`-r` 是 422 ms（`.csv`）對
767 ms（`.csv2`）。差值在 `-r`、`--json`、`-md` 上都是平的（約 350 ms），因此是「每個值都要付
的工」。**兩份 fixture 裡一個反斜線都沒有**，所以付的是「找跳脫」的錢，不是「解跳脫」的錢。

未評估的方向：欄位裡沒有 `\` 時走一條不配置、不複製的路徑（memchr 找 `\`，找不到就把原 slice
交出去）。若那條路徑存在而沒有被走到，這 350 ms 大部分是可以拿掉的。

**在動手之前**：先量「有多少比例的欄位真的含有跳脫」，以及那條路徑現在是不是已經存在——這棵樹
今天已經有一次「以為知道而沒有量」的紀錄（JM）。已寫進 README 作為使用者要知道的成本；這一條
是「能不能讓那個成本消失」，不是同一件事。


### 已關閉（2026-09-05）

**修正**：`ba16417`（2026-08-31）。原本每個欄位都要**再掃一次**找反斜線才決定要不要
`unescape`；現在解析器在**已經逐位元組讀過去的時候**順手記下 `fieldHasBackslash`，只在旗標為真
時才呼叫。那把整趟第二次掃描拿掉了。

**複量（2026-09-05，交錯 10 輪、各取最小值）**：

| 格式 | 最小值 |
|---|---|
| `.csv` | 612 ms |
| `.csv2` | 614 ms |
| **比值** | **1.00x** |

原本記錄的是 **1.82x**（422 對 767 ms）。

**只有比值可比，絕對毫秒數不可比**：這次的 fixture 是為複量現造的（45 萬筆、四欄、18 MB、
一個反斜線都沒有），不是 2026-08-26 那一份。所以 612 對 422 什麼也說不了；而這一條當初宣稱的
就是比值，比值現在是 1.00。

**這一條是在一次盤點中被使用者指出「已經不成立」才發現的。** 同一次盤點還抓到 LB 的內文仍寫著
「已索取、尚未收到」，而答案早在前一天就到了。**一份 todo 與一份缺陷清單都會與它們描述的程式
反向漂移，而沒有任何東西會回報那件漂移**——這棵樹已經為此從全域 `CLAUDE.md` 刪掉過一張五條全部
不成立的表。唯一抓得到的動作是**回去量**。

Closed 2026-09-05. Fixed by ba16417 on 2026-08-31: the parser now records `fieldHasBackslash`
while it is already walking the bytes, instead of scanning each field a second time to decide
whether to unescape. Re-measured with ten interleaved rounds, minimum of each: 612 ms for
`.csv` against 614 ms for `.csv2`, a ratio of 1.00x where the entry recorded 1.82x. Only the
RATIO is comparable -- the fixture was made for this re-measurement and is not the original --
and the ratio is what the entry claimed. Found because a stocktake was told the claim was no
longer true; the same stocktake found LB still saying an answer had not arrived a day after it
had. A todo list and a defect list both drift away from the program they describe, nothing
reports the drift, and the only thing that catches it is measuring again.

## ~~guest 那個節點無法確認任何個別案例~~ 已修（2026-09-10）

### 2026-09-10：修好了，而這一條的前半在被修之前就已經過期

**動手前先讀了現況**，發現這一節寫的「report 完全沒有逐案例行，連 `T1` 都沒有一行」**已經不成立**
——`run_csv2_test.zsh` 後來補上了 `grep -E '^(FAIL|SKIP)'` 與總案例數。照著這一節去修，會產生一個
「看起來成功而什麼都沒改變」的 commit。

**真正還缺的只有一件**：一個**通過**的案例無法被指名確認。要回答「T249 在 guest 裡跑過嗎」，
只能跨兩份報告做算術。

而資料一直都在：csv2 的測試套件把每一個案例寫進 `test/test_csv2.log`，那在 repo 裡、也就是在
workspace 映像裡。缺的是「在每次執行的複本被刪掉之前把它取出來」。

**修法（母專案 `a2da14c`，第 6c 步）**：關機之後用 `debugfs` 從**映像**裡 dump——與 payload 進去時
同一支工具、同一個方向，不碰那條會截斷的主控台通道。

驗證不是問 `stat`，是問那個檔案一件**自洽**的事：逐案例的行數必須等於摘要行說的總數，因為兩者
出自同一次執行。實測 `1360 + 0 + 10 = 1370`，而一次「只取到一半」的 dump 在 `stat` 眼中是成功。

實測結果：不需要 e2fsck 重播；`T249a`–`T249d2` 在取出的 log 裡全部具名為 PASS。

Fixed, and the first half of this entry had gone stale before it was fixed: the report gained
FAIL/SKIP case names and a total after this was written, so following it would have produced a
commit that looked successful and changed nothing. What was actually missing was confirming a
PASSING case by name. The data was always in the workspace image; step 6c dumps
`/csv2/test/test_csv2.log` with debugfs after shutdown -- same tool and direction as the
payload, never the truncating console -- and verifies it by a self-consistency the file carries
(case lines against the summary's own total) rather than by `stat`, which calls a half-taken
dump a success.

`sos/test_submodules/run_csv2_test.zsh` 匯出的 report 與 console log **完全沒有逐案例行**——
連 `T1` 都沒有一行。2026-09-06 為了確認 T249 是否在 guest 內執行而查，才發現這件事。

因此四個節點裡有一個，我們只能靠「總數有沒有照預期移動」來判斷，而那是**代理**，不是量測。
這次它剛好夠用（1191 → 1194 恰好是 T249a/b/c，而 T55a0 因 busybox 沒有 openssl 而缺席），但
**一個案例若在 guest 裡安靜地不執行，只有總數會說話**，而總數同時被許多東西影響。

那支腳本在**母專案的樹**底下，不在這裡。依「誰擁有一個目錄，誰就對它有最終判斷」，這一項是
**要回報給母專案的建議**，不是這裡逕行修改的東西。建議的形狀：把 guest 內 `test_csv2.log` 的
內容一併帶回 host 端的 report，或至少帶回所有 `FAIL`／`SKIP` 行與案例總數的分項。

The guest harness exports only totals -- no per-case lines at all, not even T1. So on one of
the four nodes a case that silently stops running is visible only as a moved total, which is a
proxy rather than a measurement. The script belongs to the parent project's tree, so this is a
suggestion to report there, not something to change from here.

## ~~待確認：`run_csv2_test.zsh` 免疫於那個通道問題嗎~~ 已確認免疫

**2026-09-10 開啟，同日結案。** VM 回來後在同一個 commit 上走了這條路徑：12 組呼叫 host 與
guest 逐位元相同，套件在 guest 內的統計行**完整回來**——四位數的 PASS、一個 FAIL、六個 SKIP，
每一行都讀得懂，而那個 FAIL 是真的（T69b 的略過計數），已修。**零截斷。** 理由與這兩組證據已經寫進 `run_csv2_test.zsh` 的檔頭註解。

另外，擁有那台 VM 的 session 同日量了 multiscp：一個 2 MiB 隨機檔兩端 sha256 相同——**所以缺陷
在「命令輸出的回傳路徑」，不是整條連線。** 那 408 行仍然一條都不記成 csv2 的缺陷。

走 `helper/run_remote.zsh guest` 跑完整套件，得到 408 行輸出，而其中的失敗訊息斷在字中間、只剩一個
字元、是空字串。那些案例檢查的都是命令的**輸出**，所以那是通道在截斷，不是 csv2 變了。母專案那個
session 從另一側獨立撞到同一件事（大量輸出後掛住 500 秒），並已表示會查那支 helper 並替它加上時間
上限。

**要做的**：VM 回來後，在同一個 commit 上走 `sos/test_submodules/run_csv2_test.zsh` 跑一次。

- **通過** → 通道問題定案，而且「那條路為什麼存在」有了證據。**那時要把理由連同那四行證據補進
  `run_csv2_test.zsh` 的註解裡**——對方明確說了，那個理由目前不存在於任何檔案，所以下一個人還是會
  選看起來比較方便的 `run_remote.zsh`。
- **不通過** → 那就不是通道，我得回頭逐條查那些失敗。

**在它有結果之前，不要把那 408 行裡的任何一條記成缺陷。** 它們每一則都言之有物，而那正是它們危險的
地方。

Whether `run_csv2_test.zsh` is immune to the channel that truncated a full suite
run through `helper/run_remote.zsh guest` is not established. Run it on the same
commit when the VM returns. If it passes, the reason that path exists is proven
and belongs in that file's comments -- it is currently written down nowhere,
which is why the more convenient route gets picked. Until then, record none of
those 408 lines as defects: each one argues for itself, and that is exactly what
makes them dangerous.

## ~~aarch64 Linux 的封存還沒補上，而我先前寫的理由是假的~~ 已由下一節取代

**2026-09-09 開啟；2026-09-10 由「v0.1.1 要做的」那一節取代。** 這一條的診斷仍然為真（封存
缺席沒有好理由），但它提議的動作——補進 v0.1.0——已經被否決了，理由是 QD：內嵌的 build id
取決於建置當下有沒有 tag，所以現在補建的封存回報 `(v0.1.0)`，而已發布的三份回報 `(8d5600e)`。
同一份原始碼、兩種字串，重建改不了。**留著這一節而不標示，會讓讀的人自己去判斷哪一節是現行的。**

Superseded on 2026-09-10. The diagnosis holds; the proposed action, back-filling v0.1.0, does not,
because QD means an archive built now cannot carry its siblings' version string.

**2026-09-09。**

v0.1.0 出了三個平台。aarch64 Linux 有測試（1333/0/5）而沒有封存——**原因只是還沒在那台機器上跑
`release.zsh`**，沒有別的。

而我先前在這裡、在 `plan.md`、在 tag 訊息、在 release notes、以及在送給母專案 session 的一個請求裡，
都寫了另一個理由：「那個映像沒有 zstd」。**那是假的。** guest 裡有 `/usr/bin/zstd`，205848 bytes。

錯在第一步：我讀了 `sos/buildroot/configs/aarch64_efi_defconfig`——那是 **buildroot 上游自帶的範例**，
`git log` 顯示它最後一次改動是上游的 commit——而這個專案實際餵給 buildroot 的是
`sos/linux_kernal_vm_interactive/build/buildroot-multissh.config`，它的第 297 行就是
`BR2_PACKAGE_ZSTD=y`，而第 260 行是一段**解釋為什麼需要它**的註解。

**後面每一步推論都成立，而且每一步都忠實地繼承了那個假前提**：defconfig 裡沒有 → rootfs 裡沒有 →
guest 裡包不出來 → 只能出三個平台 → 去請別人加一行設定。一條推理鏈不會因為它自己是對的就變成真的。

### 要記住的那一句

**去問那台機器，不要問描述它的檔案。** 那台 guest 當時開著。`command -v zstd` 一行，比讀完那份
24 行的 defconfig 還快。

同一個形狀當天出現了第二次、小一號：我估 rootfs 成本時用的是**手邊 Debian 的** zstd（1 MiB），
而 guest 裡實際是 205 KB。

### 已修與改不了的

- release notes：**已更正**，明說先前那個理由是錯的、錯在哪。
- `git tag -a v0.1.0` 的訊息：**改不了**。tag 已推送，重打會動到別人可能已經抓過的東西，那比留著
  一句被更正過的話更糟。
- 送出去的那個請求：已致歉並說明。

### 待辦

新 VM 重建完成後，在 guest 裡跑 `./release.zsh`，把 aarch64 的封存掛到 v0.1.0 上。那時
`release.zsh` 自己的第三道拒絕會檢查 `zstd` 在不在——**而那正是這次我用「讀檔案」代替「執行」的
那一道**。

The aarch64 archive is simply not built yet. The reason I gave everywhere else --
that the image has no zstd -- was false: it has `/usr/bin/zstd`, 205848 bytes. I
read Buildroot's own upstream example defconfig and used it to answer a question
about OUR image; the configuration this project actually feeds to Buildroot sets
`BR2_PACKAGE_ZSTD=y` and carries a comment above it explaining why. Every step
after that first one was sound and faithfully inherited a false premise. The
lesson is one sentence: ask the machine, not the file that describes it. It was
booted at the time.

## ~~v0.1.1 要做的：aarch64 與另外三個平台一起出~~ 已出貨

### 2026-09-10：v0.1.1 出了，四個平台

`https://github.com/raliclo/csv2/releases/tag/v0.1.1`

| 平台 | 建置於 | build id |
|---|---|---|
| macOS arm64 | 本機 | `v0.1.1 / 4ae95f6` |
| Linux aarch64 | guest VM | `v0.1.1 / 4ae95f6` |
| Linux x86_64 | WSL2 | `v0.1.1 / 4ae95f63` |
| Windows x86_64 | Ralic-W11 | `v0.1.1 / 4ae95f6` |

**四份全部在 tag 上建置**，各自在「跑那個平台測試的那台機器」上；每一份的 sha256 都由產生它的
節點算一次、由這台機器獨立再算一次，兩者一致才收下。發布後每一個 asset 又從公開 URL 重新下載
比對過一次。

四節點在同一個 commit 上的測試：macOS 1385/0/1、WSL2 1380/0/1、guest 1360/0/9（T47 十二份輸出
逐位元相同）、Windows 1346/0/16。

### 出貨當中抓到的三件事

**沒有一件是靠推理抓到的，三件都是機器說的。**

1. **QI**：`release.zsh` 的版本號寫死（`VERSION=${VERSION:-0.1.0}`），於是它用一個 0.1.1 的執行檔
   產生了一份叫 `csv2-0.1.0-macos-arm64.tar.zst` 的封存，並回報「已驗證」——**那是真的**，它檢查
   的每一件事都成立，而其中沒有一件是那個名字。它同時覆蓋掉了已發布的 v0.1.0 封存的本機複本
   （已從公開 URL 還原）。
2. **`compile_csv2_win.bat` 裡一個多餘的 `)`**：它把 `if (` 區塊提前關掉，`_described` 變空，
   build id 退回純短雜湊——而那**仍然含有一個 commit**，所以形狀檢查（T303a）通過而值是錯的。
   T303d 因此改為比對**值**。
3. **`git fetch --tags` 在遠端 tag 移動過時會失敗**（拒絕覆蓋既有 tag），而我用 `&&` 串接又把訊息
   丟掉了——於是兩個節點的 merge 從來沒執行，卻回報 `at=v0.1.1`。要 `--force`。

### `publish.zsh --publish` 那條路現在走過了

先前只走過 dry run。這一次 `gh release create`、tag 推送、公開 URL 重新下載、Formula／scoop 的
改寫與讀回，全部實際執行過。**第 2 步（從各節點收集封存）仍然是手動的**，理由不變：那用的是這台
機器的 multissh 設定。

順帶記下收集時的兩件事：multiscp 對 Windows 節點要用 `C:/Users/...` 這種原生路徑形式，`/c/Users/...`
會**靜默地什麼都不做**（沒有錯誤、沒有完成訊息）；而 IPv6 位址要寫成 `[addr]:path`。

v0.1.1 shipped on four platforms, all four archives built AT the tag on the machine that runs
that platform's tests, each sha256 computed by the building node and independently by this one,
and every asset re-downloaded from its public URL afterwards. Three defects were caught during
the release and none by reasoning: release.zsh's hardcoded version naming a 0.1.1 build 0.1.0
while reporting "verified" (QI); a stray `)` in the batch build id, whose fallback still
contained a commit so the shape check passed on a wrong value; and `git fetch --tags` failing
when a remote tag has moved, chained with `&&` and its message discarded, so two nodes never
merged while reporting the tag they were still on.

---

### 原本的計畫（保留）


**2026-09-10 決定。** aarch64 的原始碼與測試在 guest 上都已驗證（T47 通過、套件在 guest 內
執行），但 **v0.1.0 不補封存**。理由是 QD：`--version` 內嵌的 build id 取決於「建置時有沒有
tag」，所以現在補建的 aarch64 會回報 `(v0.1.0)`，而已發布的三份是 tag 之前建的、回報 `(8d5600e)`
——同一份原始碼，兩種字串，而重建改不了。

**v0.1.1 時四個平台在同一個 tag 上、用修好的 `release.zsh`（QC）一起建**，版本字串自然一致。
屆時 aarch64 那一份的產生路徑是：在 guest 內跑 `./release.zsh`，**只回傳一行 sha256**，封存用
`multiscp` 拉回，host 端再算一次比對——兩條獨立的通道都要說同一個數字才算數。那條命令輸出通道
會截斷（見 `blind-test-flow.md`），所以「短到截不掉、而且截掉了看得出來」是設計的一部分。

Decided 2026-09-10: aarch64 ships in v0.1.1 with the other three rather than being back-filled
into v0.1.0, because QD means an archive built now cannot carry its siblings' version string.
The route is: run release.zsh in the guest returning ONE line of sha256, pull the archive with
multiscp, recompute on the host and compare -- two independent channels having to agree,
because the command-output channel truncates.

### 2026-09-10：那條路徑已經預演過一次，端到端

不是等到出貨才第一次跑。在 guest 內走完了整條路，產物丟棄：

```
guest  ./compile_csv2_linux.zsh          build_rc=0
       ./release/csv2 --version          csv2 0.1.0 (v0.1.0-18-ge204ad8)   ← 與 HEAD 相符
       ./release.zsh                     release_rc=0
       sha256                            266117c5be1ee2b5…005637db          ← 只回傳這一行
host   multiscp 拉回                      321,620 bytes
       openssl dgst -sha256              266117c5be1ee2b5…005637db          ← 獨立算出同一個
       封存內容                            csv2/ LICENSE README.md README.zh-TW.md
       那個執行檔                          ELF 64-bit LSB pie, ARM aarch64
```

**三個到 v0.1.1 才會第一次揭曉的問題，現在有答案了：**

1. `release.zsh` 結尾那段「解開封存、執行它、再讀一個 CSV」**從來沒有在 aarch64 上跑過**——現在跑過了，通過。
2. 「只回傳一行 sha256」在那條會截斷的通道上穩不穩——穩；而且就算它被截斷，第 3 步也會發現。
3. multiscp 拉回來的封存兩端對不對得上——對得上。

**而它在第一分鐘就付清了自己的成本**：`./compile_csv2_linux.zsh` 回傳 126——那個檔案在 repo 裡
從來沒有執行位元（QE）。接著它又抓到第二件事：那個修正並不在聲稱修好它的 commit 裡，而守衛
通過了（`mistakes.md` 第 1 條第二十、二十一次）。**兩件都只會在「有人打 `./`」時出現，而在此之前
沒有任何自動化路徑會那樣打。**

Rehearsed end to end on 2026-09-10, product discarded. All three questions that would otherwise
have first been answered during a release are now answered: release.zsh's extract-run-read tail
had never executed on aarch64 and does; the one-line-sha256 shape holds on the truncating
channel, and step 3 would catch it if it did not; multiscp's copy matches. It paid for itself
in the first minute -- `./compile_csv2_linux.zsh` exited 126, the file having never carried an
executable bit (QE) -- and then caught a second thing, that the fix was not in the commit that
claimed it while the guard passed anyway.

## 出貨流程只有一半是腳本 / Half the release is scripted

**加入於 2026-09-08，出完 v0.1.0 之後。2026-09-10 由 `publish.zsh` 做掉了第 1、3–7 步；
第 2 步（收集）刻意留在外面，理由見下。**

`release.zsh` 負責「一個節點」那一段，而且做得夠嚴：拒絕不乾淨的工作區、拒絕
「`--version` 與 HEAD 不符」的執行檔、指名檢查 `zstd`，最後解開封存、執行解開後的執行檔、
再讓它讀一個 CSV。

**其餘七步這次全是手動的：**

1. `git tag -a` 並推 tag
2. 用 `multiscp` 把封存從三個節點各自收回（它不支援多來源下載，所以是一個檔一次）
3. 收回後重新比對 sha256（傳輸會說「transfer complete」，那是宣稱不是驗證）
4. `gh release create` 與 release notes
5. 發布後從**公開 URL** 重新下載並再驗一次
6. 把三個 sha256 抄進 `Formula/csv2.rb`
7. 把其中一個 sha256 抄進 `scoop/csv2.json`

**為什麼這是待辦而不是「就這樣也行」**：這次出貨唯一的錯誤——formula 與 README 裡的 brew 指令
少了 `brew trust`——就落在手動那一半。它之所以被抓到，只是因為我去跑了那兩行；沒有任何東西會
回報它。而第 6、7 步是**抄一個 64 字元的十六進位字串**，抄錯了同樣沒有人會說話。

一支 `publish.zsh` 應該做完 1–7，而且要沿用 `release.zsh` 的態度：sha256 從封存**現算**、不從
別處抄；formula 與 manifest 的 URL 與 hash **產生**而非手填；發布後那一次公開 URL 的重新驗證是
流程的一部分，不是額外的好習慣。

### 2026-09-10：`publish.zsh` 做掉了第 1、3–7 步

預設是試跑，`--publish` 才會動。它在碰任何對外的東西之前先拒絕：工作區不乾淨、HEAD 領先
origin、tag 已存在、沒有 `gh` 或未登入。每一份封存的 sha256 都**現算**，並與建置節點寫下的
`.sha256` 比對（不一致代表檔案在傳輸中變了）；每一份都必須解得開、而且裡面有它宣稱的執行檔。
發布之後從**公開 URL** 重新下載每一個 asset 再比一次——「`gh release create` 以 0 結束」說的是
「上傳被接受了」，那與「陌生人下載到的就是我建出來的」是兩件事。第 6、7 步由 `rewrite_version`
與 `rewrite_pair` 產生，然後讀回來；兩個檔案裡只要還留著任何一個不是本次版本的版本號就拒絕。

**第 2 步（從三個節點收集）刻意不在裡面。** 它用的是這台機器的 multissh 設定——埠、主機名、
`~/.multissh/generated/` 底下那兩個 config——那不是這個 repo 裡的腳本能知道的事。同樣不在
裡面的還有建置與測試：一份封存必須在它的執行檔被建置**且**被測試的那台機器上產生，那正是
`release.zsh` 已經在做的事。

**尚未實測的那一半**：`--publish` 這條路只能靠真的發布一次來驗證，因此目前只走過 dry run
（用三份形狀正確的假 0.1.1 封存，六個步驟都列了出來）。風險最高的兩支——`rewrite_version` 與
`rewrite_pair`——是直接在 `Formula/csv2.rb` 與 `scoop/csv2.json` 的**複本**上跑過並檢查產物的，
其中一次就抓到了一個會弄爛 JSON 的缺陷（見 `mistakes.md` 第 6 條）。剩下沒被執行過的是
`gh release create`、tag 推送，以及公開 URL 的重新下載。

`publish.zsh` now does steps 1 and 3-7, dry-run by default. Step 2 -- collecting the archives
from three nodes -- is deliberately left out: it uses this machine's multissh setup, which a
script in this repository cannot know. Building and testing stay out for the same reason
`release.zsh` exists. Untested: the `--publish` path can only be verified by publishing, so
only the dry run has been exercised; the two riskiest functions were run against COPIES of the
package files and their products inspected, which is how a JSON-mangling defect was caught.

Half the release is scripted. `release.zsh` covers one node and is strict about
it; the other seven steps -- tag, collect from three nodes, re-checksum after
transfer, create the release, re-verify from the public URL, and copy three
sha256s into the formula and the manifest -- were done by hand for v0.1.0. The
only mistake in that release (the brew instructions were missing `brew trust`)
lived in the manual half, and steps 6 and 7 are transcribing a 64-character hex
string, which nothing reports getting wrong. A `publish.zsh` should compute the
hashes from the archives rather than copy them, and treat the post-publish
re-download as part of the procedure.

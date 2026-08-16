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

**Status: to do. The drop-in half is now unblocked; the tap and the shim are
not. / 狀態：待辦。drop-in 那一半已經沒有東西擋著，tap 與 shim 仍被擋住。**

There is a binary to install now (`./compile_csv2.zsh` → `release/csv2`), so
the `$(brew --prefix)/bin` drop-in, the `~/.local/bin` fallback, `--uninstall`
and the verify-by-running step can all be written today. What remains blocked
is blocked on things outside this repository:

現在已經有可安裝的執行檔（`./compile_csv2.zsh` → `release/csv2`），因此
`$(brew --prefix)/bin` 的 drop-in、退回 `~/.local/bin`、`--uninstall`，以及「以執行
來驗證」那一步，今天就可以寫。仍被擋住的部分，擋住它們的都是本 repo 之外的東西：

| Part | Blocked on |
|---|---|
| drop-in `install.zsh` | nothing — can be written now / 沒有，現在就能寫 |
| Homebrew tap + formula | `raliclo/csv2` is private / repo 尚未公開 |
| Windows scoop shim | no Windows build exists / 沒有 Windows build |

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

## 2. `--a1` and `--physical` have no test case / `--a1` 與 `--physical` 沒有測試案例

**Status: to do. Both work; neither is asserted. / 狀態：待辦。兩者都能運作，但都沒有被斷言。**

```sh
csv2 -contains busybox --physical --a1 -i TARGET_PACKAGES.csv
1:1@L2 [A1]	pkg_name	busybox
```

The plan specifies that both exist and why (`--physical` because a record can
span several lines, so a record number is not a line number; `--a1` because
spreadsheet users read `F12`, but it must never be the default since CSV need
not have a header and its column count need not be constant). What the plan
does **not** specify is the output shape. `12:6@L34` comes from the plan;
`[A1]` appended after it was chosen during implementation with nothing to check
it against.

計畫載明了兩者的存在與理由（`--physical`：一筆紀錄可跨多行，紀錄號不等於行號；
`--a1`：試算表使用者讀得懂 `F12`，但絕不能作為預設，因為 CSV 未必有標頭、欄數也未必
一致）。計畫**沒有**規定的是輸出形狀：`12:6@L34` 出自計畫，而附在其後的 `[A1]` 是實作
時自行決定的，沒有任何東西可以對照。

So the first step is not a test but a decision: fix the shape in the plan, give
the cases their T-numbers, then assert them. Writing a test against a shape
nobody chose only freezes an accident.

因此第一步不是寫測試而是做決定：先在計畫中訂下形狀、給案例編上 T 編號，再去斷言它。
針對一個沒有人選擇過的形狀寫測試，只會把一次偶然固化下來。

Worth checking while there: `--a1` past column Z becomes AA, AB. `a1Column()`
handles it, and nothing has ever run it past 26 columns -- the widest fixture
here has 10.

順帶要查的：`--a1` 超過 Z 之後會變成 AA、AB。`a1Column()` 有處理，但從來沒有東西
真的跑過 26 欄以上——此處最寬的素材只有 10 欄。

## 3. `-debug` has one level, not five / `-debug` 只有一級，不是五級

**Status: to do. / 狀態：待辦。**

`plan.md` defines `ERROR > WARN > INFO > DEBUG > TRACE` and says `-debug` lowers
the threshold to DEBUG, with "a form like `-debug=trace` able to lower it
further". The levels exist in `Logger`; the CLI only implements the DEBUG step,
so TRACE is unreachable.

`plan.md` 定義了 `ERROR > WARN > INFO > DEBUG > TRACE`，並說明 `-debug` 把門檻降到
DEBUG，而「`-debug=trace` 之類的形式可以再降」。層級在 `Logger` 中確實存在，但 CLI
只實作了 DEBUG 那一階，TRACE 因此無法達到。

Not urgent -- nothing currently logs at TRACE, so adding the flag before there
is anything to see would produce an option that does nothing. The useful order
is: find the first thing worth a TRACE line, then add both.

不急——目前沒有任何東西以 TRACE 記錄，在有東西可看之前先加旗標，只會得到一個什麼也
不做的選項。合理的順序是：先找到第一件值得寫成 TRACE 的事，再一起加上。

## 4. An index can only be created as a side effect / 索引只能以副作用的方式產生

**Status: to do. / 狀態：待辦。**

An index appears in exactly two situations: a write path builds one while
writing, and `-tail` builds one because it has to read the whole file anyway.
There is no way to ask for one.

索引只會在兩種情況下出現：寫入路徑邊寫邊建，以及 `-tail` 因為本來就必須讀完整個檔案
而順手建立。沒有任何方式可以「要求」產生一個。

That leaves a real gap. Someone who only ever runs `-mid` on a large `.csv2`
never gets an index, because `-mid` deliberately stops early and building one
there would cancel out the early stop -- correct per operation, but it means
the sidecar never appears for that user at all. The workaround is to run a
`-tail 1` for its side effect, which is not something anyone would guess.

這留下一個真實的缺口：只用 `-mid` 讀大型 `.csv2` 的人永遠不會得到索引，因為 `-mid`
刻意提前停止，在那裡建索引會抵銷掉提前停止——就單一操作而言是對的，但結果是那位使用者
根本不會出現 sidecar。目前的變通方式是跑一次 `-tail 1` 取其副作用，而那不是任何人猜得到的。

`--verify-index` already exists and requires an index to check, which makes the
absence more obvious: there is a flag to verify one and none to make one.

`--verify-index` 已經存在，而它需要一個索引才能檢查——這讓缺口更明顯：有旗標可以驗證
索引，卻沒有旗標可以建立索引。

The rule to preserve when adding it: **the index must stay an optimisation and
never a precondition**, so an explicit build must still be optional, must not
change any output, and must not fail an operation if the directory is
unwritable.

新增時要守住的規則：**索引必須維持是最佳化，永遠不是必要條件**——因此明示建立仍必須
是選用的、不得改變任何輸出，也不得在目錄不可寫時使操作失敗。

## 5. The UAX #11 width table is a hand-written subset / UAX #11 寬度表是手寫的子集

**Status: accepted for now; recorded so it is not mistaken for complete.
狀態：目前接受現狀；記錄在此以免被誤認為完整。**

`src/Width.swift` carries about 90 ranges chosen to cover what this project
actually stores: Han, Hangul, fullwidth forms, and the emoji blocks. It is not
the full East Asian Width table and it does not track Unicode revisions, so an
emoji added in a later Unicode version will be measured as width 1 and
`--pretty` will misalign that row by one column.

`src/Width.swift` 含約 90 個區間，涵蓋的是本專案實際會儲存的東西：漢字、諺文、全形
形式與 emoji 區塊。它不是完整的 East Asian Width 表，也不追蹤 Unicode 修訂，因此在
較新 Unicode 版本中新增的 emoji 會被算成寬度 1，`--pretty` 那一列就會歪一欄。

Acceptable because `--pretty` is opt-in and the default minimal form needs no
width information at all -- that is why the default is the minimal form. It
becomes a real problem only if `--pretty` ever becomes the default, which it
should not.

之所以可接受：`--pretty` 是選擇加入的，而預設的最小形式完全不需要寬度資訊——那正是
預設採用最小形式的理由。只有在 `--pretty` 變成預設時它才會成為真正的問題，而它不應該
變成預設。

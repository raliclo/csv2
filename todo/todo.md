# todo

Items that are decided but not yet designed in full. The design itself lives in
[../plan/plan.md](../plan/plan.md).

尚未完整設計、但已確定要做的項目。設計本體見 [../plan/plan.md](../plan/plan.md)。

---

## 1. Install into the package manager's bin directory / 安裝到套件管理員的 bin 目錄

**Status: to do. / 狀態：待辦。**

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

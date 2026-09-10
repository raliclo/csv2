@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 > nul
:: compile_csv2_win.bat -- build csv2.exe on Windows
::
:: NOTE: comments in this file are English-only ON PURPOSE. Non-ASCII bytes on
:: a comment line were found to corrupt cmd.exe's parsing of SUBSEQUENT lines
:: in this environment, reproducibly and independent of chcp. This is the one
:: file in csv2 that is not bilingual, and that is why. The Chinese
:: explanation lives in README.zh-TW.md.
::
:: csv2 has no C dependencies -- Foundation only, no libraries to link, no
:: module maps, no bridging header. That is the whole reason this file is
:: short compared with swift_tar's equivalent: there is nothing to find but
:: swiftc itself.
::
:: This is also called by compile_csv2.zsh when uname reports MSYS, MINGW, or
:: CYGWIN. It remains usable directly from cmd.exe.
::
:: Output: release\csv2.exe

cd /d "%~dp0"

set "_opt=-O"
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--debug" (
    set "_opt=-Onone"
    shift
    goto parse_args
)
echo [FAIL] Unknown option: %~1
exit /b 2
:args_done

where swiftc.exe > nul 2>&1
if errorlevel 1 (
    echo [FAIL] swiftc.exe not on PATH. Install the Swift toolchain for Windows
    echo        from swift.org, then open a new shell so PATH is picked up.
    exit /b 1
)

:: Swift on Windows links against the MSVC runtime and needs the C++ build
:: tools present, even for a project with no C of its own. vswhere is the
:: supported way to locate them; hardcoding a Visual Studio path breaks on the
:: next version, and on any machine that installed it elsewhere.
set "_vswhere=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
where cl.exe > nul 2>&1
if errorlevel 1 (
    if not exist "%_vswhere%" (
        echo [FAIL] Neither cl.exe nor vswhere.exe found. Install Visual Studio
        echo        with the "Desktop development with C++" workload.
        exit /b 1
    )
    set "_vsroot="
    for /f "usebackq delims=" %%I in (`"%_vswhere%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "_vsroot=%%I"
    if not defined _vsroot (
        echo [FAIL] MSVC C++ tools not found by vswhere.
        exit /b 1
    )
    if not exist "!_vsroot!\VC\Auxiliary\Build\vcvars64.bat" (
        echo [FAIL] vcvars64.bat not found under "!_vsroot!"
        exit /b 1
    )
    call "!_vsroot!\VC\Auxiliary\Build\vcvars64.bat" > nul
)

:: The build identity, produced before the list that names it is read. Same
:: three lines as the macOS and Linux scripts, in batch: git if there is a git,
:: and `unknown` if there is not, rather than a guess.
:: 這次建置的身分，在「指名它的那份清單」被讀取之前產生。與 macOS 與 Linux 腳本相同的三行，
:: 寫成 batch：有 git 就用 git，沒有就是 `unknown`，而不是用猜的。
:: The build id ALWAYS carries the commit, and says the tag when there is one.
:: `git describe --always` answers according to whether a tag existed WHEN THE
:: BUILD RAN, not according to the source, so the same commit produced
:: `(8d5600e)` before v0.1.0 was tagged and `(v0.1.0)` after. QD.
::
:: This is a COPY of build_id.zsh, which batch cannot source. T303 pins the
:: property both must satisfy, so a copy that drifts is reported rather than
:: found during a release.
:: 這個 build id **永遠帶著那個 commit**，而在有 tag 時也說出 tag。`git describe --always` 的答案
:: 取決於「建置執行的當下」有沒有 tag，不取決於原始碼，所以同一個 commit 在 v0.1.0 被打之前產生
:: `(8d5600e)`、之後產生 `(v0.1.0)`。QD。
::
:: 這是 build_id.zsh 的一份**副本**——batch source 不了它。T303 釘住兩者都必須滿足的那個性質，
:: 於是一份漂掉的副本會被回報，而不是在某次出貨當中才被發現。
set "_build=unknown"
set "_described="
set "_short="
for /f "usebackq tokens=* delims=" %%G in (`git describe --always --dirty 2^>nul`) do set "_described=%%G"
for /f "usebackq tokens=* delims=" %%G in (`git rev-parse --short HEAD 2^>nul`) do set "_short=%%G"
:: `if errorlevel 1` rather than `||`. Inside a parenthesised block, after a
:: redirected command, `||` in batch binds in ways that are hard to predict and
:: harder to test from another machine -- and this branch is the one that only
:: fires AT A TAG, which is to say during a release. The conventional form has
:: no such ambiguity.
:: 用 `if errorlevel 1` 而不是 `||`。在一個括號區塊內、又接在重導之後，batch 的 `||` 結合方式
:: 難以預測，而且更難從另一台機器上測——而這條分支**只在正好位於 tag 上時**才會觸發，也就是
:: 某次出貨當中。常規的寫法沒有這個歧義。
if not "!_described!"=="" (
    set "_build=!_described!"
    if not "!_short!"=="" (
        :: `echo(` with NO closing paren. Adding one closed the enclosing
        :: `if (` block early, `_described` came out empty, and the build fell
        :: back to the bare short hash -- which still CONTAINS a commit, so
        :: T303a's shape check passed while the value was wrong. Measured on
        :: the Windows node: the build said `(97e3908)` where MSYS `git
        :: describe` says `v0.1.0-34-g97e3908`.
        :: `echo(` 後面**不加**收尾括號。加了它會把外層的 `if (` 區塊提前關掉，`_described` 因此
        :: 是空的，建置退回純短雜湊——而那**仍然含有一個 commit**，所以 T303a 的形狀檢查照樣
        :: 通過，值卻是錯的。在 Windows 節點上量到：建置說 `(97e3908)`，而 MSYS 的 git describe
        :: 說 `v0.1.0-34-g97e3908`。
        echo(!_described!| findstr /C:"!_short!" >nul
        if errorlevel 1 set "_build=!_described! / !_short!"
    )
) else (
    if not "!_short!"=="" set "_build=!_short!"
)
> src\BuildInfo.swift echo // Generated by the build. Not in git: it changes with every commit.
>> src\BuildInfo.swift echo // 由建置產生。不進 git：它每個 commit 都會變。
>> src\BuildInfo.swift echo let CSV2_BUILD = "!_build!"

:: ONE source list, read from src\sources.list, the same file the macOS and
:: Linux builds read. Keeping a second copy here is how the Linux build once
:: drifted: it was missing a file, and the failure named a missing SYMBOL
:: rather than the missing FILE.
set "_sources="
for /f "usebackq tokens=* delims=" %%L in ("src\sources.list") do (
    set "_line=%%L"
    if not "!_line!"=="" (
        if not "!_line:~0,1!"=="#" (
            set "_win=!_line:/=\!"
            set "_sources=!_sources! !_win!"
        )
    )
)
if not defined _sources (
    echo [FAIL] src\sources.list produced no source files.
    exit /b 1
)

if not exist release mkdir release

echo Building csv2.exe ^(%_opt%^)
swiftc -swift-version 6 -warnings-as-errors %_opt% %_sources% -o release\csv2.exe
if errorlevel 1 (
    echo [FAIL] swiftc failed.
    exit /b 1
)

:: Verify by RUNNING it, not by checking the file exists. Whether the file
:: landed proves nothing about whether it works -- the same rule the macOS and
:: Linux builds follow.
release\csv2.exe --version > nul
if errorlevel 1 (
    echo [FAIL] csv2.exe was produced but does not run.
    exit /b 1
)
for /f "usebackq delims=" %%V in (`release\csv2.exe --version`) do set "_ver=%%V"
echo OK: !_ver! -^> release\csv2.exe
endlocal

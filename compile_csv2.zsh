#!/usr/bin/env zsh
# =====================================================================
# compile_csv2.zsh — detect the host platform and build csv2
# compile_csv2.zsh — 偵測 host 平台並建置 csv2
#
# Plain .swift sources compiled with swiftc, the same way swift_tar is
# built: Foundation + Dispatch only, no SwiftPM, no SwiftNIO. That choice
# is what keeps the Linux cross-compile step (phase 6) a matter of
# changing the target triple rather than porting a build system.
# 純 .swift 原始檔以 swiftc 建置，做法比照 swift_tar：只用 Foundation +
# Dispatch，不用 SwiftPM、不用 SwiftNIO。這個選擇讓日後的 Linux 交叉編譯
# （第 6 階段）只是換一個 target triple，而不是移植一套建置系統。
#
# Output / 輸出：release/csv2（macOS/Linux）或 release/csv2.exe（Windows）
#
# Usage / 用法：
#   ./compile_csv2.zsh            optimised build / 最佳化建置
#   ./compile_csv2.zsh --debug    -Onone with assertions / 不最佳化、保留斷言
#   ./compile_csv2.zsh -musl      Linux only: fully static against musl, for the
#                                 release archives; the default stays glibc, which
#                                 the Linux VM builds. See compile_csv2_linux.zsh.
#                                 僅限 Linux：對 musl 完全靜態，供發行封存；預設仍是
#                                 glibc，也就是 Linux VM 的建置。見 compile_csv2_linux.zsh。
# =====================================================================
set -e
cd "$(dirname "$0")"

HOST_KERNEL=$(uname -s)
case "$HOST_KERNEL" in
    MSYS*|MINGW*|CYGWIN*)
        # The native batch bootstrap locates and initialises MSVC before
        # invoking swiftc. Disable MSYS argument rewriting so cmd.exe receives
        # /d and /c as Windows switches rather than POSIX paths.
        # 原生 batch bootstrap 會先尋找並初始化 MSVC，再呼叫 swiftc。關閉 MSYS
        # 參數改寫，避免 cmd.exe 的 /d 與 /c 被當成 POSIX 路徑轉換。
        # `.\` is required. When the process carries
        # NoDefaultCurrentDirectoryInExePath, cmd.exe does not search the
        # current directory for an executable, and a bare name fails with
        # "'compile_csv2_win.bat' is not recognized as an internal or external
        # command" before the Swift build is reached; the node then keeps its
        # previous binary and the tests report on that. `.\` works with or
        # without the variable. The same variable hides vswhere.exe from
        # VsDevCmd.bat. QK.
        # `.\` 是必要的。行程帶著 NoDefaultCurrentDirectoryInExePath 時，cmd.exe 不會在當前目錄
        # 尋找執行檔，裸檔名會以「'compile_csv2_win.bat' is not recognized as an internal or
        # external command」失敗，根本走不到 Swift 建置；節點於是保留舊的執行檔，之後的測試
        # 測的是那一個。不論有無這個變數，`.\` 都有效。讓 VsDevCmd.bat 找不到 vswhere.exe 的
        # 也是同一個變數。QK。
        # The newest installed Swift, not whichever one this shell was started
        # with: after an upgrade deletes the old toolchain, a shell opened
        # before it names a swiftc that is gone. SR.
        # 用的是最新安裝的 Swift，而不是這個 shell 開啟時帶著的那一個：升級刪掉舊工具鏈後，
        # 在那之前開啟的 shell 指向的 swiftc 已經不存在。SR。
        source ./swift_windows_env.zsh
        MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c '.\compile_csv2_win.bat' "$@"
        exit $?
        ;;
    Darwin|Linux) ;;
    *)
        print -u2 -- "unsupported build platform: $HOST_KERNEL / 不支援的建置平台：$HOST_KERNEL"
        exit 1
        ;;
esac

OPT="-O"
for arg in "$@"; do
    case "$arg" in
        --debug) OPT="-Onone" ;;
        # Both spellings, as in multissh. Refused off Linux rather than ignored:
        # an ignored -musl hands release.zsh a binary the person believes static.
        # 兩種寫法都收，與 multissh 相同。在 Linux 以外拒絕而不是忽略：被忽略的 -musl 會把一個
        # 那個人以為是靜態的執行檔交給 release.zsh。
        -musl|--musl)
            [[ $HOST_KERNEL == Linux ]] || { print -u2 -- "-musl is for Linux only (this is $HOST_KERNEL) / -musl 僅限 Linux（這裡是 $HOST_KERNEL）"; exit 2 }
            ;;
        *) echo "unknown option: $arg / 未知選項：$arg" >&2; exit 2 ;;
    esac
done

# Linux builds in one place: compile_csv2_linux.zsh builds glibc by default and
# fully static musl with -musl, and knows where the SDK lives. A second copy of
# that here is how the two would drift. The swiftc on PATH is the toolchain it uses.
# Linux 只在一個地方建置：compile_csv2_linux.zsh 預設建置 glibc，加 -musl 時對 musl 完全靜態連結，
# 也知道 SDK 在哪裡。在這裡再寫一份，就是兩者開始分歧的方式。它用的是 PATH 上那個 swiftc 所屬的工具鏈。
if [[ $HOST_KERNEL == Linux ]]; then
    swiftc_path=$(command -v swiftc) || { print -u2 -- "swiftc not found on PATH / PATH 上找不到 swiftc"; exit 1 }
    SWIFT_PREFIX=${swiftc_path:A:h:h} SRC_DIR=${0:A:h} exec zsh "${0:A:h}/compile_csv2_linux.zsh" "$@"
fi

# Generated BEFORE the list is validated, because the list names
# src/BuildInfo.swift and the check would otherwise fail on a file this script
# is about to write.
# 在清單檢驗**之前**產生，因為清單裡列了 src/BuildInfo.swift，否則檢查會因為這支腳本
# 正要寫出的檔案而失敗。
# The build identity, written before the compile so it is part of it. A dirty
# tree is marked `-dirty`, because a dirty build is the one nobody can
# reproduce. One place decides the shape; see build_id.zsh for why it is not
# `git describe` alone. QD.
# 這次建置的身分，在編譯之前寫好，成為它的一部分。工作樹有未提交改動時標上 `-dirty`，
# 因為 dirty 的建置沒有人能重現。形狀由一個地方決定；為什麼不單用 `git describe`，
# 見 build_id.zsh。QD。
# build_id.zsh is not in the guest's payload -- run_csv2_test.zsh tars a fixed
# list of files -- and the payload has no .git either, so the answer there is
# `unknown` whatever computes it. A hard `source` would fail that build for
# nothing.
#
# With a git repo it IS worth failing: the id would otherwise come from a
# fallback written here, and a second copy of that rule is what build_id.zsh
# exists to prevent. QD.
#
# build_id.zsh 不在 guest 的 payload 裡（run_csv2_test.zsh 打包的是固定的檔案清單），而 payload
# 也沒有 .git，所以那裡的答案不論由誰計算都是 `unknown`。硬性 `source` 只會讓那次建置白白失敗。
#
# 有 git repo 時就該失敗：否則 id 會由寫在這裡的 fallback 產生，而那條規則的第二份副本，
# 正是 build_id.zsh 存在所要防止的。QD。
if [[ -r "${0:A:h}/build_id.zsh" ]]; then
    source "${0:A:h}/build_id.zsh"
    build_id=$(csv2_build_id "${0:A:h}")
elif git -C "${0:A:h}" rev-parse --git-dir >/dev/null 2>&1; then
    print -ru2 -- "build_id.zsh is missing beside this script, and this IS a git checkout; refusing to guess the build id"
    print -ru2 -- "build_id.zsh 不在這支腳本旁邊，而這**是**一個 git checkout；拒絕用猜的產生 build id"
    exit 1
else
    build_id=unknown
fi
print -r -- "// Generated by the build. Not in git: it changes with every commit." > "${0:A:h}/src/BuildInfo.swift"
print -r -- "// 由建置產生。不進 git：它每個 commit 都會變。" >> "${0:A:h}/src/BuildInfo.swift"
print -r -- "let CSV2_BUILD = \"$build_id\"" >> "${0:A:h}/src/BuildInfo.swift"

# One list, read from src/sources.list -- see the reasoning in that file.
# 只有一份清單，讀自 src/sources.list——理由寫在該檔中。
SOURCES=(${(f)"$(grep -v '^[[:space:]]*#' src/sources.list | grep -v '^[[:space:]]*$')"})
[[ ${#SOURCES} -gt 0 ]] || { print -u2 -- "src/sources.list is empty / src/sources.list 是空的"; exit 1 }

for f in $SOURCES; do
    if [[ ! -f "$f" ]]; then
        echo "missing source: $f / 缺少原始檔：$f" >&2
        exit 1
    fi
done

mkdir -p release

echo "Building csv2 for $HOST_KERNEL ($OPT) / 正在為 $HOST_KERNEL 建置 csv2（$OPT）"

# The lowest macOS a release runs on, stated here and nowhere else (T358
# reads it from this line). Without -target the floor followed whatever macOS
# did the build: v0.1.x and v0.2.0 came out at 26.0 because their builders
# ran 26, and a build on a newer macOS would have raised it unannounced. 26 is
# what every node runs, and the cases that fail on macOS 15 / Swift 6.1 (SU,
# SV) are outside it. The user decided this on 2026-11-07.
# 發行版能執行的最低 macOS，只寫在這裡（T358 從這一行讀取）。沒有 -target 時，下限跟著建置用的 macOS 走：
# v0.1.x 與 v0.2.0 的下限是 26.0，只因為建置它們的機器跑 26；換到更新的 macOS 建置，下限就會在沒人宣告的
# 情況下提高。26 是每個節點在跑的版本，而在 macOS 15／Swift 6.1 上失敗的案例（SU、SV）在範圍之外。
# 使用者於 2026-11-07 決定。
MACOS_MIN=26.0
swiftc -swift-version 6 -warnings-as-errors $OPT -target "$(uname -m)-apple-macos$MACOS_MIN" -o release/csv2 $SOURCES

# Verify by RUNNING it, not by checking the file exists. Whether the binary
# landed proves nothing about whether it works; this is the same reasoning as
# the install step's rule in todo/todo.md.
# 以執行來驗證，而非檢查檔案存在。檔案有沒有放進去，對它能不能運作毫無證明力；
# 這與 todo/todo.md 中安裝步驟的規則是同一個道理。
./release/csv2 --version >/dev/null
echo "OK: $(./release/csv2 --version) -> release/csv2"

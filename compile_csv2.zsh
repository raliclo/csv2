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
        MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c compile_csv2_win.bat "$@"
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
        *) echo "unknown option: $arg / 未知選項：$arg" >&2; exit 2 ;;
    esac
done

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
swiftc -swift-version 6 $OPT -o release/csv2 $SOURCES

# Verify by RUNNING it, not by checking the file exists. Whether the binary
# landed proves nothing about whether it works; this is the same reasoning as
# the install step's rule in todo/todo.md.
# 以執行來驗證，而非檢查檔案存在。檔案有沒有放進去，對它能不能運作毫無證明力；
# 這與 todo/todo.md 中安裝步驟的規則是同一個道理。
./release/csv2 --version >/dev/null
echo "OK: $(./release/csv2 --version) -> release/csv2"

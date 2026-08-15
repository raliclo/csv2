#!/usr/bin/env zsh
# =====================================================================
# compile_csv2.zsh — build csv2 on the macOS host
# compile_csv2.zsh — 在 macOS host 上建置 csv2
#
# Plain .swift sources compiled with swiftc, the same way swift_tar is
# built: Foundation + Dispatch only, no SwiftPM, no SwiftNIO. That choice
# is what keeps the Linux cross-compile step (phase 6) a matter of
# changing the target triple rather than porting a build system.
# 純 .swift 原始檔以 swiftc 建置，做法比照 swift_tar：只用 Foundation +
# Dispatch，不用 SwiftPM、不用 SwiftNIO。這個選擇讓日後的 Linux 交叉編譯
# （第 6 階段）只是換一個 target triple，而不是移植一套建置系統。
#
# Output / 輸出：release/csv2
#
# Usage / 用法：
#   ./compile_csv2.zsh            optimised build / 最佳化建置
#   ./compile_csv2.zsh --debug    -Onone with assertions / 不最佳化、保留斷言
# =====================================================================
set -e
cd "$(dirname "$0")"

OPT="-O"
for arg in "$@"; do
    case "$arg" in
        --debug) OPT="-Onone" ;;
        *) echo "unknown option: $arg / 未知選項：$arg" >&2; exit 2 ;;
    esac
done

# main.swift must come LAST. Swift only allows top-level statements in a file
# named main.swift, and the driver treats file order as significant for it.
# main.swift 必須排在最後。Swift 只允許名為 main.swift 的檔案含頂層敘述，
# 而 driver 對它的檔案順序是敏感的。
SOURCES=(
    src/Crypto.swift
    src/Core.swift
    src/Support.swift
    src/Width.swift
    src/Index.swift
    src/Parallel.swift
    src/Ops.swift
    src/Run.swift
    src/main.swift
)

for f in $SOURCES; do
    if [[ ! -f "$f" ]]; then
        echo "missing source: $f / 缺少原始檔：$f" >&2
        exit 1
    fi
done

mkdir -p release

echo "Building csv2 ($OPT) / 正在建置 csv2（$OPT）"
swiftc $OPT -o release/csv2 $SOURCES

# Verify by RUNNING it, not by checking the file exists. Whether the binary
# landed proves nothing about whether it works; this is the same reasoning as
# the install step's rule in todo/todo.md.
# 以執行來驗證，而非檢查檔案存在。檔案有沒有放進去，對它能不能運作毫無證明力；
# 這與 todo/todo.md 中安裝步驟的規則是同一個道理。
./release/csv2 --version >/dev/null
echo "OK: $(./release/csv2 --version) -> release/csv2"

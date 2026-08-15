#!/usr/bin/env zsh
# =====================================================================
# compile_csv2_linux.zsh — build csv2 as a Linux aarch64 ELF INSIDE the
#                          guest VM.
# compile_csv2_linux.zsh — 在 guest VM 內把 csv2 建置成 Linux aarch64 ELF。
#
# Kept separate from compile_csv2.zsh, which is the macOS host build. The
# two differ in exactly one place -- where swiftc lives -- and that is the
# whole point of csv2 having no C dependencies: swift_tar needs a sysroot,
# generated module maps and zlib headers for its Linux build, and csv2
# needs none of it. Foundation and Dispatch only.
# 與 compile_csv2.zsh（macOS host 版）分開。兩者只差一處——swiftc 在哪裡——
# 而這正是「csv2 沒有 C 依賴」的價值所在：swift_tar 的 Linux 建置需要 sysroot、
# 自行產生的 module map 與 zlib header，csv2 一樣都不需要，只用 Foundation
# 與 Dispatch。
#
# Expected in the guest / guest 內預期存在：
#   /workspace/opt/swift/usr/bin/swiftc    Swift toolchain
#   /workspace/csv2/src/*.swift            source, injected by the host driver
#
# Output / 輸出：$SRC_DIR/release/csv2  (aarch64 Linux ELF)
#
# Usage / 用法：
#   zsh /workspace/csv2/compile_csv2_linux.zsh
#   SRC_DIR=/elsewhere zsh compile_csv2_linux.zsh
# =====================================================================
set -eu

SWIFT_PREFIX=${SWIFT_PREFIX:-/workspace/opt/swift/usr}
SRC_DIR=${SRC_DIR:-/workspace/csv2}
SWIFTC="$SWIFT_PREFIX/bin/swiftc"

die() { print -u2 -- "compile_csv2_linux: $*"; exit 1 }

[[ -x "$SWIFTC" ]] || die "swiftc not found at $SWIFTC / 找不到 swiftc：$SWIFTC"
[[ -d "$SRC_DIR/src" ]] || die "source not found at $SRC_DIR/src / 找不到原始碼：$SRC_DIR/src"

cd "$SRC_DIR"

OPT="-O"
for arg in "$@"; do
    case "$arg" in
        --debug) OPT="-Onone" ;;
        *) die "unknown option: $arg / 未知選項：$arg" ;;
    esac
done

# One list, read from src/sources.list -- see the reasoning in that file.
# 只有一份清單，讀自 src/sources.list——理由寫在該檔中。
SOURCES=(${(f)"$(grep -v '^[[:space:]]*#' src/sources.list | grep -v '^[[:space:]]*$')"})
[[ ${#SOURCES} -gt 0 ]] || { print -u2 -- "src/sources.list is empty / src/sources.list 是空的"; exit 1 }

for f in $SOURCES; do
    [[ -f "$f" ]] || die "missing source: $f / 缺少原始檔：$f"
done

mkdir -p release

print -- "Building csv2 for aarch64 Linux ($OPT) / 正在為 aarch64 Linux 建置 csv2（$OPT）"
"$SWIFTC" $OPT -o release/csv2 $SOURCES

# Verify by RUNNING it, not by checking the file exists -- the same rule the
# macOS build follows. Here it also proves the Swift runtime resolves: a binary
# that links but cannot find libswiftCore at run time is the exact failure
# swift_tar hit with libxml2, and it is invisible until something runs it.
# 以執行來驗證，而非檢查檔案存在——與 macOS 版同一條規則。在這裡它還額外證明
# Swift runtime 解析得到：一個「連結成功但執行時找不到 libswiftCore」的執行檔，
# 正是 swift_tar 在 libxml2 上踩過的失敗，而它在真的被執行之前完全看不見。
./release/csv2 --version >/dev/null
print -- "OK: $(./release/csv2 --version) -> $SRC_DIR/release/csv2"
file release/csv2 2>/dev/null || true

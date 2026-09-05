#!/usr/bin/env zsh
# =====================================================================
# compile_csv2view.zsh — build the viewer. macOS only, and that is why it
#                        is a separate script and a separate suite.
# compile_csv2view.zsh — 建置檢視器。**只在 macOS**，而那正是它自成一支腳本、
#                        自成一份測試的原因。
#
# It is NOT called from compile_csv2.zsh and its tests are NOT called from
# test/test_csv2.zsh. Mixing them would make `./test/test_csv2.zsh`
# unrunnable everywhere without SwiftUI -- including the aarch64 Linux
# guest, which is one of the four nodes that suite must pass on. The plan
# says this in the phase-8 section, and it says it before any code.
#
# 它**不會**被 compile_csv2.zsh 呼叫，它的測試也**不會**被 test/test_csv2.zsh 呼叫。混在一起會讓
# `./test/test_csv2.zsh` 在任何沒有 SwiftUI 的地方都跑不起來——包括 aarch64 Linux guest，而那是
# 那份測試必須通過的四個節點之一。計畫在第 8 階段那一節就寫了這件事，而且寫在任何程式碼之前。
#
# Ends by RUNNING the product, not by checking the file exists. Same rule
# as compile_csv2.zsh, for the same reason: a binary that links and cannot
# start is invisible until something starts it.
# 結尾以**執行產物**驗證，而不是檢查檔案存在。與 compile_csv2.zsh 同一條規則、同一個理由：
# 一個「連結得起來卻起不動」的執行檔，在有東西真的去啟動它之前完全看不見。
# =====================================================================
set -eu

HERE="${0:A:h}"
cd "$HERE"

if [[ $(uname -s) != Darwin ]]; then
    print -u2 -- "csv2view builds on macOS only (got $(uname -s)) / csv2view 只在 macOS 上建置（實得 $(uname -s)）"
    exit 1
fi

OPT="-O"
for arg in "$@"; do
    case "$arg" in
        --debug) OPT="-Onone" ;;
        *) print -u2 -- "unknown option: $arg / 未知選項：$arg"; exit 1 ;;
    esac
done

mkdir -p release

# main.swift LAST. Swift requires top-level code to live in main.swift, and
# the file order decides which file is allowed to have it.
# main.swift **排在最後**。Swift 要求最上層的程式碼放在 main.swift，而檔案順序決定哪一個檔案
# 被允許擁有它。
SOURCES=(src/Bridge.swift src/Model.swift UI/ContentView.swift UI/Window.swift src/main.swift)
for f in $SOURCES; do
    [[ -f "$f" ]] || { print -u2 -- "missing source: $f / 缺少原始檔：$f"; exit 1 }
done

print -- "Building csv2view for $(uname -sm) ($OPT) / 正在為 $(uname -sm) 建置 csv2view（$OPT）"
swiftc -swift-version 6 -warnings-as-errors $OPT -o release/csv2view $SOURCES

# Run it. `--probe` with no arguments exits 2 and says how to use it, which is
# a successful start; the failure this catches is a binary that cannot start
# at all.
# 執行它。`--probe` 不帶參數會以 2 結束並說明用法，那是一次成功的啟動；這裡要抓的失敗是
# 「一個根本起不動的執行檔」。
if ./release/csv2view --probe 2>/dev/null; then
    print -u2 -- "csv2view --probe with no arguments should have failed / 不帶參數的 --probe 本應失敗"
    exit 1
fi
print -- "OK: csv2view -> $HERE/release/csv2view"

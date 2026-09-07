#!/usr/bin/env zsh
# =====================================================================
# benchmark.zsh — fail when the calibrated Swift 6 Windows timings regress
# benchmark.zsh — Swift 6 Windows 實測時間超過校準上限時失敗
#
# These are wall-clock guards, so they deliberately live outside the
# correctness suite. measure.zsh takes the best of repeated runs; the limits
# below retain 50–70% headroom over four measurements made on 2026-08-27.
# 這些是 wall-clock 守衛，因此刻意不放進正確性測試。measure.zsh 會在多次執行中
# 取最快值；下列上限相對 2026-08-27 的四次量測保留 50–70% 餘裕。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail

HERE=${0:A:h}
ROOT=${HERE:h}
# `release/csv2` on macOS and Linux, `release/csv2.exe` on Windows -- the same
# name compile_csv2.zsh's Windows branch produces. Hard-wiring the POSIX name
# made this script exit "build first" on a node that HAD just built, and the one
# Windows measurement on record was taken by passing CSV2= by hand, an
# incantation that appears nowhere. 2026-09-08.
# macOS 與 Linux 上是 `release/csv2`，Windows 上是 `release/csv2.exe`——也就是 compile_csv2.zsh
# 的 Windows 分支產生的那個名字。寫死 POSIX 那個名字，會讓這支腳本在一個**剛剛建置完成**的節點上
# 印出「build first」而結束，而現存唯一一份 Windows 量測，是靠手動傳入 CSV2= 取得的——那個咒語
# 不存在於任何地方。2026-09-08。
if [[ -z ${CSV2:-} ]]; then
    if [[ -x $ROOT/release/csv2 ]]; then
        CSV2=$ROOT/release/csv2
    elif [[ -x $ROOT/release/csv2.exe ]]; then
        CSV2=$ROOT/release/csv2.exe
    else
        CSV2=$ROOT/release/csv2
    fi
fi
[[ -x $CSV2.exe && ! -x $CSV2 ]] && CSV2=$CSV2.exe
: ${RECORDS:=200000}

if [[ $(uname -s) != (MSYS*|MINGW*|CYGWIN*) ]]; then
    print -u2 -- "benchmark limits are calibrated only for native Windows Swift 6 / 效能上限目前只對原生 Windows Swift 6 校準"
    exit 2
fi
if (( RECORDS != 200000 )); then
    print -u2 -- "benchmark limits require RECORDS=200000, got $RECORDS / 效能上限要求 RECORDS=200000，實得 $RECORDS"
    exit 2
fi

# Defaults are intentionally overridable for a separately calibrated runner.
# 預設值可被覆寫，供另一台已獨立校準的 runner 使用。
: ${CSV2_BENCH_MAX_SINGLE_SECONDS:=4.0}
: ${CSV2_BENCH_MAX_PARALLEL_SECONDS:=1.5}
: ${CSV2_BENCH_MAX_EDIT_SECONDS:=0.15}
: ${CSV2_BENCH_MAX_REWRITE_SECONDS:=4.0}
: ${MEASURE_OUTPUT:=$HERE/measure_output_windows.txt}

CSV2=$CSV2 RECORDS=$RECORDS MEASURE_OUTPUT=$MEASURE_OUTPUT "$HERE/measure.zsh"

reading() { # sed expression / sed 運算式
    sed -n "$1" "$MEASURE_OUTPUT" | tail -1
}
single=$(reading 's/^single-threaded : \([0-9.]*\) s.*/\1/p')
parallel=$(reading 's/^parallel        : \([0-9.]*\) s.*/\1/p')
edit=$(reading 's/^smallest edit   : \([0-9.]*\) s.*/\1/p')
rewrite=$(reading 's/^rewrite whole   : \([0-9.]*\) s.*/\1/p')

failed=0
guard() { # name actual maximum / 名稱 實測 上限
    local name=$1 actual=$2 maximum=$3
    if [[ -z $actual ]]; then
        print -u2 -- "FAIL $name: measurement is missing / 量測值缺失"
        failed=1
    elif (( actual <= maximum )); then
        print -r -- "PASS $name: ${actual}s <= ${maximum}s"
    else
        print -u2 -- "FAIL $name: ${actual}s > ${maximum}s"
        failed=1
    fi
}

print -r -- "# Swift 6 Windows performance limits / Swift 6 Windows 效能上限"
guard "single-threaded parse / 單執行緒剖析" $single $CSV2_BENCH_MAX_SINGLE_SECONDS
guard "parallel parse / 平行剖析" $parallel $CSV2_BENCH_MAX_PARALLEL_SECONDS
guard "small durable edit / 最小落地編輯" $edit $CSV2_BENCH_MAX_EDIT_SECONDS
guard "whole-file rewrite / 整檔重寫" $rewrite $CSV2_BENCH_MAX_REWRITE_SECONDS

(( failed == 0 )) || exit 1

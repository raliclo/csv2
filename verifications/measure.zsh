#!/usr/bin/env zsh
# =====================================================================
# measure.zsh — the three numbers plan/plan.md said to measure BEFORE
#               writing any code, and which nobody measured
# measure.zsh — plan/plan.md 說「寫程式之前應該先量」、而始終沒有人量的三個數字
#
# The plan's own words: "本專案有過『開機時間結論錯誤、事後要更正並修一輪文件』
# 的紀錄。這幾項要在寫程式之前量，不是事後。" They were not measured before, and
# every threshold in the scale section inherits from a host-side memchr figure
# of 2900 MiB/s that the plan itself says the real parser will miss by an order
# of magnitude. If that is true, the 16 MiB index and parallel thresholds were
# chosen against the wrong number.
# 計畫自己寫著：「這幾項要在寫程式之前量，不是事後。」它們沒有被事先量過，而規模那
# 一節的每個門檻都繼承自 host 端 2900 MiB/s 的 memchr 數字——計畫自己又說真正的解析器
# 會慢一個數量級。若真是如此，16 MiB 的索引與平行門檻就是對著錯的數字挑的。
#
# This is a MEASUREMENT, not a test: it has no pass/fail and asserts nothing.
# It prints numbers and writes them beside itself, so a later run can be
# compared against an earlier one.
# 這是「量測」而不是「測試」：它沒有通過／失敗，也不斷言任何事。它印出數字並寫在自己
# 旁邊，讓日後的執行能與先前的比較。
#
# Usage / 用法:
#   ./measure.zsh              measure with the defaults / 以預設值量測
#   RECORDS=20000 ./measure.zsh   smaller corpus, for a slow guest / 較小的語料，供慢速 guest 使用
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail
# EPOCHREALTIME comes from this module, not from the shell itself. Without it
# `setopt no_unset` turns the first timing into a fatal "parameter not set" --
# which is the correct behaviour and is why no_unset is on.
# EPOCHREALTIME 來自這個模組，不是 shell 內建。少了它，`setopt no_unset` 會讓第一次
# 計時直接以「parameter not set」中止——那是正確的行為，也正是開啟 no_unset 的理由。
zmodload zsh/datetime

HERE=${0:A:h}
ROOT=${HERE:h}
: ${CSV2:=$ROOT/release/csv2}
# Records, not megabytes. The corpus is built row by row, so the record count is
# what is actually controlled; a size knob would have to be reported as an
# estimate and would then disagree with the byte count printed below.
# 以「筆數」而非 MB 為單位。語料是一列一列產生的，能被真正控制的是筆數；若以大小為
# 旋鈕，它只能是估計值，並會與下方印出的實際位元組數不一致。
: ${RECORDS:=200000}

[[ -x $CSV2 ]] || { print -u2 -- "build first: $ROOT/compile_csv2.zsh"; exit 1 }

OUT=$HERE/measure_output.txt
TMP=$(mktemp -d "$HERE/.measure.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT INT TERM

say() { print -r -- "$1"; print -r -- "$1" >> $OUT }

: > $OUT
say "# csv2 measurements"
say "date    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "host    : $(uname -sm)"
say "binary  : $($CSV2 --version)"
say ""

# ---------------------------------------------------------------------
# Build the corpus. Real-shaped rows: quoted fields with embedded commas,
# because a parser measured on `a,b,c` is measured on the case it does not
# have to work for.
# 建立語料。列的形狀要接近真實：含逗號的引號欄位——因為拿 `a,b,c` 去量解析器，
# 量到的是它「不必費力」的那個案例。
# ---------------------------------------------------------------------
corpus=$TMP/big.csv2
{
  print -r -- 'pkg,version,size,source,purpose,notes,license'
  print -r -- '套件,版本,大小,來源,用途,註記,授權'
  i=0
  while (( i < RECORDS )); do
    print -r -- "pkg$i,1.$i.0,$((i % 900)) KiB,buildroot package,\"purpose, with a comma\",\"CORRECTED $i: prose with, commas and \"\"quotes\"\" in it\",MIT"
    (( i++ ))
  done
} > $corpus
actual=$(wc -c < $corpus | tr -d ' ')
records=$($CSV2 -r --json -i $corpus 2>/dev/null | tail -1 | grep -o '"records":[0-9]*' | cut -d: -f2)
say "corpus bytes : $actual"
say "corpus records: $records"
say ""

# ---------------------------------------------------------------------
# 1. Full RFC 4180 parse throughput.
#
# `-contains` with a needle that cannot match parses every field of every
# record and emits nothing, so what is timed is the parser rather than the
# writer. Timing `-r` instead would measure parse + encode + write and report a
# number for something nobody does.
# 1. 完整 RFC 4180 解析吞吐量。
# 以一個不可能命中的字串跑 `-contains`，會解析每一筆的每一欄卻不輸出任何東西，
# 因此計時到的是解析器而非寫出端。改用 `-r` 計時會量到「解析＋編碼＋寫出」，
# 得到一個沒有人在做的事情的數字。
# ---------------------------------------------------------------------
say "## 1. full RFC 4180 parse throughput / 完整解析吞吐量"
best=999999
for run in 1 2 3; do
    s=$EPOCHREALTIME
    CSV2_PARALLEL_MIN_BYTES=999999999 $CSV2 -contains 'ZZ_NO_SUCH_STRING_ZZ' -i $corpus -so >/dev/null 2>&1
    e=$EPOCHREALTIME
    d=$(( e - s ))
    (( d < best )) && best=$d
done
mbs=$(( actual / 1048576.0 / best ))
say "single-threaded : $(printf '%.3f' $best) s   $(printf '%.0f' $mbs) MiB/s"

# The worker count comes from csv2's own -debug, not from `getconf
# _NPROCESSORS_ONLN`. busybox has no getconf, so on the guest that call fails
# and the fallback would silently report one core -- turning a measurement into
# a guess that happens to look like a number. csv2 already knows how many
# workers it started, and that is the figure the speedup should be divided by.
# 工作者數量取自 csv2 自己的 -debug，而非 `getconf _NPROCESSORS_ONLN`。busybox 沒有
# getconf，在 guest 上那個呼叫會失敗、退回值會靜默地宣稱「單核」——把一次量測變成一個
# 長得像數字的猜測。csv2 本來就知道它啟動了幾個工作者，而加速比也該除以那個數字。
pbest=999999
for run in 1 2 3; do
    s=$EPOCHREALTIME
    CSV2_PARALLEL_MIN_BYTES=1000 $CSV2 -contains 'ZZ_NO_SUCH_STRING_ZZ' -i $corpus -so -debug \
        >/dev/null 2>$TMP/dbg.txt
    e=$EPOCHREALTIME
    d=$(( e - s ))
    (( d < pbest )) && pbest=$d
done
workers=$(grep -o '[0-9]* workers' $TMP/dbg.txt | head -1 | awk '{print $1}')
: ${workers:=1}
pmbs=$(( actual / 1048576.0 / pbest ))
speedup=$(( best / pbest ))
say "parallel        : $(printf '%.3f' $pbest) s   $(printf '%.0f' $pmbs) MiB/s   speedup $(printf '%.2f' $speedup)x on $workers workers"
say "efficiency      : $(printf '%.0f' $(( speedup / workers * 100 )))% of linear"
say "                  the boundary-finding pass is single-threaded, so this is"
say "                  expected to be well under 100%; record it rather than"
say "                  reading \"parallel\" as \"P times faster\"."
say "                  找紀錄邊界的那一遍是單執行緒的，因此這個數字理應遠低於 100%；"
say "                  把它記下來，不要把「平行」讀成「快 P 倍」。"
say ""

# ---------------------------------------------------------------------
# 2. The fixed cost of making a write durable.
#
# csv2 writes a temp file, flushes it, then renames. The flush is what makes
# "all-new or all-old" survive a crash rather than merely protecting concurrent
# readers, and it sets the floor for how fast a small edit can possibly be.
# 2. 讓一次寫入「落地」的固定成本。
# csv2 寫暫存檔、flush、再 rename。那個 flush 正是讓「要嘛全新、要嘛全舊」能撐過當機
# （而不只是保護並行讀者）的東西，也決定了「一次小編輯最快能有多快」的下限。
# ---------------------------------------------------------------------
say "## 2. durable-write floor / 落地寫入的下限"
small=$TMP/small.csv
print -r -- 'a,b,c' > $small
print -r -- '1,2,3' >> $small
sbest=999999
for run in 1 2 3 4 5; do
    s=$EPOCHREALTIME
    $CSV2 -update '1:1' "v$run" -i $small --in-place >/dev/null 2>&1
    e=$EPOCHREALTIME
    d=$(( e - s ))
    (( d < sbest )) && sbest=$d
done
say "smallest edit   : $(printf '%.4f' $sbest) s   (process start + parse + flush + rename)"
say "                  一次最小編輯的總時間，含行程啟動、解析、flush 與 rename"
say ""

# ---------------------------------------------------------------------
# 3. Write throughput, which is what every edit pays.
#
# Every edit except -append rewrites the whole file, so this number times the
# file size IS the cost of changing one cell.
# 3. 寫入吞吐量，也就是每一次編輯要付的代價。
# 除了 -append 之外的每一次編輯都會重寫整個檔案，因此這個數字乘上檔案大小，就是
# 「改一格」的成本。
# ---------------------------------------------------------------------
say "## 3. write throughput / 寫入吞吐量"
wbest=999999
for run in 1 2; do
    s=$EPOCHREALTIME
    $CSV2 -update '1:1' "w$run" -i $corpus -o $TMP/out.csv2 >/dev/null 2>&1
    e=$EPOCHREALTIME
    d=$(( e - s ))
    (( d < wbest )) && wbest=$d
done
wmbs=$(( actual / 1048576.0 / wbest ))
say "rewrite whole   : $(printf '%.3f' $wbest) s   $(printf '%.0f' $wmbs) MiB/s"
if (( RECORDS < 100000 )); then
    say "                  NOTE: at RECORDS=$RECORDS the fixed costs above"
    say "                  (process start, parse, flush) are a large share of"
    say "                  this, so the MiB/s figure understates the steady"
    say "                  rate. Only compare runs with the same RECORDS."
    say "                  注意：在 RECORDS=$RECORDS 下，上面那些固定成本（行程啟動、"
    say "                  解析、flush）佔了很大比例，因此 MiB/s 會低估穩態速率。"
    say "                  只能與相同 RECORDS 的執行相比。"
fi
say ""

# ---------------------------------------------------------------------
# What the numbers mean for the thresholds the plan chose.
# 這些數字對計畫所選門檻的意義。
# ---------------------------------------------------------------------
say "## what this says about the thresholds / 對門檻的意涵"
idx_s=$(( 16.0 / mbs ))
say "16 MiB at the measured parse rate : $(printf '%.3f' $idx_s) s"
say "  the index and parallel thresholds are both 16 MiB. That is the point at"
say "  which a full scan costs the above; judge whether it is worth a sidecar."
say "  索引與平行的門檻都是 16 MiB。那是「全掃描要花上述時間」的那個點；"
say "  是否值得為此維護一個 sidecar，據此判斷。"
say ""
say "1 GiB rewrite at the measured write rate : $(printf '%.1f' $(( 1024.0 / wmbs ))) s"
say "  plan/plan.md predicted 26 s from a 39 MiB/s figure."
say "  plan/plan.md 依 39 MiB/s 推得 26 秒。"

print -r -- ""
print -r -- "written to $OUT"

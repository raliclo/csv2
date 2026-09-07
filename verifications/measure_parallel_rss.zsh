#!/usr/bin/env zsh
# Measure parallel-search RSS with one fixed, large, matching corpus.
# 使用同一份大型、每筆命中的語料，量測平行搜尋的 RSS。

emulate -L zsh
setopt no_unset pipe_fail errexit
zmodload zsh/datetime

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
: ${RSS_RECORDS:=10000000}
# Named for the platform, because the repo keeps one committed record PER
# platform and this script used to write `measure_output.txt` on all of them.
# Running the documented command on the Windows node therefore overwrote the
# macOS record -- silently, in the working tree, where the next `git add -A`
# would have published Windows numbers under the macOS name. Found on
# 2026-09-08 when the node refused to pull: the only thing standing between
# that and a published wrong column was git noticing an unstaged change.
# 依平台命名，因為這個 repo 為**每個平台**各保存一份已提交的紀錄，而這支腳本先前在所有平台上
# 寫的都是 `measure_output.txt`。於是在 Windows 節點上執行那個被記載的指令，會覆蓋掉 macOS 的
# 那份紀錄——靜默地、就在工作複本裡，而下一次 `git add -A` 就會把 Windows 的數字掛在 macOS 的
# 名字底下發表出去。2026-09-08 因為節點拒絕 pull 才發現：擋在那與「發表一個錯誤欄位」之間的，
# 只有 git 注意到有一個未暫存的變更。
if [[ -z ${MEASURE_OUTPUT:-} ]]; then
    case $(uname -s) in
        Darwin)        MEASURE_OUTPUT=$HERE/measure_parallel_rss_output.txt ;;
        Linux)         MEASURE_OUTPUT=$HERE/measure_parallel_rss_output_linux.txt ;;
        MSYS*|MINGW*|CYGWIN*|Windows*) MEASURE_OUTPUT=$HERE/measure_parallel_rss_output_windows.txt ;;
        *)             MEASURE_OUTPUT=$HERE/measure_parallel_rss_output_$(uname -s).txt ;;
    esac
fi

[[ -x $CSV2 ]] || { print -u2 -- "build first: $ROOT/compile_csv2.zsh"; exit 1 }
(( RSS_RECORDS >= 10000000 )) || {
    print -u2 -- "RSS_RECORDS must be at least 10000000"
    exit 1
}

# errexit ends this script wherever it fails, and until 2026-09-08 it ended it
# with no output at all. A measurement harness that dies quietly is worse than
# one that crashes loudly: it leaves a plausible-looking partial file behind.
# errexit 會讓這支腳本在失敗的地方結束，而直到 2026-09-08 為止，它結束時什麼都不印。一支
# 安靜死掉的量測腳本，比大聲當掉的更糟：它會留下一個看起來很合理的半成品檔案。
TRAPZERR() {
    print -u2 -- "measure_parallel_rss.zsh failed at line $LINENO; $MEASURE_OUTPUT is incomplete"
    print -u2 -- "measure_parallel_rss.zsh 在第 $LINENO 行失敗；$MEASURE_OUTPUT 並不完整"
}

TMP=$(mktemp -d "$HERE/.measure-rss.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
trap 'exit 130' INT TERM
csv_corpus=$TMP/parallel-rss.csv
csv2_corpus=$TMP/parallel-rss.csv2

make_corpus() {
    local output=$1
    local format=$2
    {
        print -r -- 'id,value,description'
        if [[ $format == csv2 ]]; then
            print -r -- '識別,值,說明'
        fi
        i=1
        while (( i <= RSS_RECORDS )); do
            print -r -- "row$i,needle,parallel search record $i with fixed padding 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            (( i++ ))
        done
    } > $output
}

make_corpus $csv_corpus csv
make_corpus $csv2_corpus csv2

# A `.csv` takes the parallel path only when an `.index` beside it proves one
# record per line; CSV2_PARALLEL_MIN_BYTES=1 does not buy that, because the
# obstacle is not the size threshold. Without this line the two `.csv` rows of
# this table were SINGLE-THREADED runs published under a parallel heading, with
# the scan path's memory: 9.28 MiB where a real parallel search of the same
# corpus costs 36-52 MiB. A reader sizing a container from that number OOMs.
# OW.
#
# 一個 `.csv` 只有在旁邊有一個「證明每行一筆」的 `.index` 時才會走平行路徑；
# `CSV2_PARALLEL_MIN_BYTES=1` 買不到那件事，因為阻擋者不是大小門檻。少了這一行，這張表的
# 兩個 `.csv` 列就是**掛在平行標題底下的單執行緒量測**，帶著掃描路徑的記憶體用量：9.28 MiB，
# 而同一份語料真正的平行搜尋要 36–52 MiB。一個依那個數字去開容器的讀者會 OOM。OW。
"$CSV2" --build-index -i $csv_corpus >/dev/null

csv_bytes=$(wc -c < $csv_corpus | tr -d ' ')
csv2_bytes=$(wc -c < $csv2_corpus | tr -d ' ')
say() { print -r -- "$1"; print -r -- "$1" >> $MEASURE_OUTPUT }

: > $MEASURE_OUTPUT
say "# csv2 parallel RSS measurement"
say "date    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "host    : $(uname -sm)"
say "binary  : $($CSV2 --version)"
say "csv corpus bytes : $csv_bytes"
say "csv2 corpus bytes: $csv2_bytes"
say "corpus records   : $RSS_RECORDS"
say "search       : every data record matches 'needle'"
say "workers      : $(sysctl -n hw.ncpu 2>/dev/null || print unknown)"
say "chunk bytes  : ${CSV2_PARALLEL_CHUNK_BYTES:-default}"
say ""

# One run per row was not enough. On 2026-09-08 a single-run table put `.csv`
# at 9.4 s and `.csv2` at 37.1 s, while a run an hour earlier on the same host
# and binary put them the other way round -- a 4x swing that a single number
# reports as a fact about the FORMAT. Two 1.3 GB corpora do not both stay in
# the page cache, so whichever is searched first is searched warm, and the
# published ordering between formats was an artefact of that order.
#
# So: interleave, and keep the minimum. The elapsed time and the peak RSS are
# kept FROM THE SAME RUN -- pairing the fastest time with the smallest memory
# seen in any run would describe an execution that never happened.
#
# 一列跑一次是不夠的。2026-09-08 一份「每列一次」的表把 `.csv` 放在 9.4 秒、`.csv2` 放在
# 37.1 秒，而一小時前在同一台主機、同一個執行檔上的另一次執行，兩者的順序是反過來的——那是
# 4 倍的擺盪，而一個單一數字會把它回報成「關於**格式**的事實」。兩份 1.3 GB 的語料不會同時
# 留在 page cache 裡，於是先被搜尋的那一份就是熱的，而先前公布的「格式間排序」是那個順序的
# 產物。
#
# 因此：交錯執行，取最小值。經過時間與 peak RSS 取自**同一次執行**——把最快的時間配上任一次
# 執行中最小的記憶體，描述的會是一次從未發生過的執行。
typeset -A best_elapsed best_rss best_holding
for round in 1 2 3; do
    for cap in default 8388608; do
        for format in csv csv2; do
            corpus=$csv_corpus
            bytes=$csv_bytes
            [[ $format == csv2 ]] && corpus=$csv2_corpus && bytes=$csv2_bytes
            log=$TMP/$cap.$format.$round.log
            start=$EPOCHREALTIME
            if [[ $cap == default ]]; then
                env CSV2_PARALLEL_MIN_BYTES=1 "$CSV2" -contains needle -i $corpus -so -debug > /dev/null 2> $log
            else
                env CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_MAX_BYTES=$cap "$CSV2" \
                    -contains needle -i $corpus -so -debug > /dev/null 2> $log
            fi
            end=$EPOCHREALTIME
            elapsed=$(( end - start ))
            # Assert WHICH PATH was timed. This harness used to check only for a
            # `metrics:` line, which BOTH paths print, and for `parallel: holding`
            # lines, which a run under no cap pressure prints on NEITHER -- so a
            # single-threaded run produced a complete, plausible table at exit 0.
            # That is how OW survived: nothing here was ever asked the one
            # question the table's own heading answers.
            #
            # 斷言剛剛計時的是**哪一條路徑**。這支 harness 先前只檢查 `metrics:`（兩條路徑都會
            # 印）與 `parallel: holding`（沒有 cap 壓力時兩條路徑都不會印），於是一次單執行緒的
            # 執行會產生一張完整、合理的表並以 0 結束。OW 就是這樣活下來的：這裡從來沒有人被
            # 問過那張表的標題自己就在回答的那個問題。
            if ! grep -qE 'DEBUG (parallel: [0-9]+ chunks|parallel: trusting index)' $log; then
                print -u2 -- "$format ($cap) did not take the parallel path -- this table would be measuring something else"
                print -u2 -- "$format（$cap）沒有走平行路徑——這張表會量到別的東西"
                grep -E 'DEBUG (single-threaded|parallel)' $log | head -2 >&2
                exit 1
            fi
            metrics=$(grep -E 'metrics:' $log | tail -1)
            [[ -n $metrics ]] || { print -u2 -- "missing metrics for $format ($cap)"; exit 1; }
            rss=$(print -r -- $metrics | sed -n 's/.*peak_rss_bytes=\([0-9]*\).*/\1/p')
            [[ -n $rss ]] || { print -u2 -- "missing peak RSS for $format ($cap)"; exit 1; }
            key=$cap.$format
            if [[ -z ${best_elapsed[$key]:-} ]] || (( elapsed < best_elapsed[$key] )); then
                best_elapsed[$key]=$elapsed
                best_rss[$key]=$rss
                # `|| true`: with errexit AND pipe_fail, a grep that finds
                # nothing returns 1, the command substitution inherits it, and
                # the assignment kills the script -- SILENTLY, having already
                # truncated the output file. That is what happened on the first
                # run of this version: the published file was left holding a
                # header and no rows, which reads like a table that was cut
                # short rather than a run that died. There is no `holding` line
                # on the default-cap rows because there is no cap pressure, so
                # the empty case is the NORMAL one.
                # `|| true`：在 errexit 與 pipe_fail 之下，一個找不到東西的 grep 回傳 1，命令
                # 替換繼承它，而那個賦值會**無聲地**殺掉整支腳本——而且是在它已經清空輸出檔
                # 之後。這一版第一次執行時就是這樣：發表用的檔案只剩下一個表頭和零列，讀起來
                # 像是一張被截斷的表，而不是一次死掉的執行。預設 cap 的那兩列沒有 `holding`
                # 行，因為那裡沒有 cap 壓力——所以「空的」才是正常情況。
                best_holding[$key]=$(grep -E 'parallel: holding' $log | head -1 || true)
            fi
        done
    done
done

for cap in default 8388608; do
    if [[ $cap == default ]]; then
        label="default max"
    else
        label="8 MiB max"
    fi
    say "## $label (best of 3, interleaved / 交錯執行三輪取最小值)"
    for format in csv csv2; do
        bytes=$csv_bytes
        [[ $format == csv2 ]] && bytes=$csv2_bytes
        key=$cap.$format
        elapsed=${best_elapsed[$key]}
        mibps=$(( bytes / 1048576.0 / elapsed ))
        say "$format elapsed_seconds: $(printf '%.3f' $elapsed)"
        say "$format throughput_mib_per_sec: $(printf '%.1f' $mibps)"
        say "$format peak_rss_bytes: ${best_rss[$key]}"
        [[ -n ${best_holding[$key]} ]] && say "${best_holding[$key]}"
    done
    say ""
done

# The path the old table was actually measuring, kept as a row of its own.
#
# Without an index a `.csv` is not parallel at all -- so this line is both the
# single most useful tuning fact on the page (build one) and the evidence for
# what the four rows above used to be. If someone deletes the --build-index
# call, the numbers move back to THIS row and the assertion above fires; this
# row is what they would have moved to.
#
# 舊的那張表實際上在量的那條路徑，獨立成一列。
#
# 沒有索引時一個 `.csv` 根本不會平行——因此這一行同時是這一頁上最有用的一條調校事實（去建一個），
# 以及「上面那四列以前是什麼」的證據。若有人刪掉 --build-index 那個呼叫，數字會回到**這一列**，
# 而上面那道斷言會觸發；這一列就是它們會退回去的地方。
rm -f $csv_corpus.index
ni_best=999999
ni_rss=0
for round in 1 2 3; do
    log=$TMP/noindex.$round.log
    start=$EPOCHREALTIME
    env CSV2_PARALLEL_MIN_BYTES=1 "$CSV2" -contains needle -i $csv_corpus -so -debug > /dev/null 2> $log
    end=$EPOCHREALTIME
    elapsed=$(( end - start ))
    if ! grep -q 'DEBUG single-threaded' $log; then
        print -u2 -- "the no-index row went parallel; it is meant to be the fallback path"
        print -u2 -- "無索引那一列走了平行；它本來應該是後備路徑"
        exit 1
    fi
    if (( elapsed < ni_best )); then
        ni_best=$elapsed
        ni_rss=$(grep -E 'metrics:' $log | tail -1 | sed -n 's/.*peak_rss_bytes=\([0-9]*\).*/\1/p')
    fi
done
say "## csv with NO index -- the single-threaded fallback / 沒有索引的 csv——單執行緒後備路徑 (best of 3)"
say "csv-noindex elapsed_seconds: $(printf '%.3f' $ni_best)"
say "csv-noindex throughput_mib_per_sec: $(printf '%.1f' $(( csv_bytes / 1048576.0 / ni_best )))"
say "csv-noindex peak_rss_bytes: $ni_rss"
say ""

say "Each CSV and CSV2 pair used the same data records and command; only format and CSV2_PARALLEL_MAX_BYTES differed."
say "每一組 CSV 與 CSV2 使用相同資料列與指令；差異只有格式與 CSV2_PARALLEL_MAX_BYTES。"
say "written to $MEASURE_OUTPUT"

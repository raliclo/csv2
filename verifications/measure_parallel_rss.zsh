#!/usr/bin/env zsh
# Measure parallel-search RSS with one fixed, large, matching corpus.
# 使用同一份大型、每筆命中的語料，量測平行搜尋的 RSS。

emulate -L zsh
setopt no_unset pipe_fail errexit
zmodload zsh/datetime

HERE=${0:A:h}
ROOT=${HERE:h}
: ${CSV2:=$ROOT/release/csv2}
: ${RSS_RECORDS:=10000000}
: ${MEASURE_OUTPUT:=$HERE/measure_parallel_rss_output.txt}

[[ -x $CSV2 ]] || { print -u2 -- "build first: $ROOT/compile_csv2.zsh"; exit 1 }
(( RSS_RECORDS >= 10000000 )) || {
    print -u2 -- "RSS_RECORDS must be at least 10000000"
    exit 1
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

for cap in default 8388608; do
    if [[ $cap == default ]]; then
        label="default max"
    else
        label="8 MiB max"
    fi
    say "## $label"
    for format in csv csv2; do
        corpus=$csv_corpus
        bytes=$csv_bytes
        [[ $format == csv2 ]] && corpus=$csv2_corpus && bytes=$csv2_bytes
        log=$TMP/$cap.$format.log
        start=$EPOCHREALTIME
        if [[ $cap == default ]]; then
            env CSV2_PARALLEL_MIN_BYTES=1 "$CSV2" -contains needle -i $corpus -so -debug > /dev/null 2> $log
        else
            env CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_MAX_BYTES=$cap "$CSV2" \
                -contains needle -i $corpus -so -debug > /dev/null 2> $log
        fi
        end=$EPOCHREALTIME
        elapsed=$(( end - start ))
        metrics=$(grep -E 'metrics:' $log | tail -1)
        [[ -n $metrics ]] || { print -u2 -- "missing metrics for $format ($label)"; exit 1; }
        rss=$(print -r -- $metrics | sed -n 's/.*peak_rss_bytes=\([0-9]*\).*/\1/p')
        [[ -n $rss ]] || { print -u2 -- "missing peak RSS for $format ($label)"; exit 1; }
        mibps=$(( bytes / 1048576.0 / elapsed ))
        say "$format elapsed_seconds: $(printf '%.3f' $elapsed)"
        say "$format throughput_mib_per_sec: $(printf '%.1f' $mibps)"
        say "$format peak_rss_bytes: $rss"
        grep -E 'parallel: holding' $log | while IFS= read -r line; do say "$line"; done
    done
    say ""
done

say "Each CSV and CSV2 pair used the same data records and command; only format and CSV2_PARALLEL_MAX_BYTES differed."
say "每一組 CSV 與 CSV2 使用相同資料列與指令；差異只有格式與 CSV2_PARALLEL_MAX_BYTES。"
say "written to $MEASURE_OUTPUT"

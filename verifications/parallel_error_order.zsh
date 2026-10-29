#!/usr/bin/env zsh
# =====================================================================
# parallel_error_order.zsh — one broken file, one reason, every time.
# parallel_error_order.zsh — 同一個壞掉的檔案，每一次都給同一個原因。
#
# LE. If the parallel path kept whichever worker's error arrived FIRST, thread
# scheduling would decide which of two messages a user sees: "record 1
# (line 3): a raw newline inside a cell", or "record 2 (line 4) has 1 fields
# but the header has 2" -- the second being what a chunk that began mid-record
# saw, not what is wrong with the file. Someone following it to line 4 finds
# an ordinary row.
#
# LE。平行路徑若留住「最先**到達**」的那個 worker 的錯誤，使用者看到哪一則訊息就由執行緒排程
# 決定：「record 1 (line 3)：儲存格裡有裸換行」，或「record 2 (line 4) 有 1 欄而標頭有 2 欄」——
# 後者是「一個從紀錄中間開始的區塊」看到的東西，不是那個檔案真正的毛病。照著它去找第 4 行，
# 會看到一列正常的資料。
#
# WHY THIS IS NOT A CASE IN test_csv2.zsh:
# T118b runs each chunk size once, so it meets this race roughly one run in
# eighty. A case that catches a race 1.25% of the time is not a guard; it is a
# lottery ticket. The guard is this script, which runs the comparison enough
# times, under load, for absence to mean something.
#
# 為什麼這不是 test_csv2.zsh 裡的一個案例：
# T118b 每個 chunk 大小只跑一次，因此大約每八十次執行才遇到一次這個競態。一個「1.25% 的機率
# 抓得到競態」的案例不是守衛，是彩券。守衛是這支腳本：它跑夠多次、而且在負載下跑，好讓「沒有
# 出現」這件事有意義。
#
# Usage / 用法：
#   ./verifications/parallel_error_order.zsh              # 50 x 4 x 6 = 1200 runs
#   ROUNDS=200 ./verifications/parallel_error_order.zsh   # longer
#   PAR=12 ./verifications/parallel_error_order.zsh       # more contention
#
# Verified to BITE: with first-arrival ordering restored, a 1200-run pass
# reports both messages and exits 1. An unproven guard against a 1.25% race is
# indistinguishable from no guard.
# **證明它會咬**：還原成「先到者勝」之後，一次 1200 次的執行會回報兩種訊息，並以 1 結束。
# 一道未經證明的守衛，對一個 1.25% 的競態來說，與沒有守衛分不出來。
# =====================================================================
set -eu

HERE="${0:A:h}"
ROOT="${HERE:h}"
CSV2="${CSV2:-$ROOT/release/csv2}"
ROUNDS="${ROUNDS:-50}"
PAR="${PAR:-6}"

[[ -x "$CSV2" ]] || { print -u2 -- "no csv2 at $CSV2 / 找不到 csv2：$CSV2"; exit 1 }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A .csv2 holding what a .csv2 may not hold: a raw newline inside a quoted
# cell. The format promises one record per line, so the parallel path believes
# it -- which is how a chunk boundary lands inside a quoted field.
# 一個 .csv2 裡放了 .csv2 不允許的東西：引號欄位裡的裸換行。這個格式保證一筆一行，而平行路徑
# 相信它——那正是區塊邊界會落進引號欄位裡的原因。
printf 'pkg,note\ntext,text\nzlib,"has a\nraw newline"\nzstd,ok\n' > "$TMP/t.csv2"

# Contention comes from running the copies CONCURRENTLY, not from busy loops.
# A `( while :; do :; done ) &` load loop inherits every open descriptor, so
# piping this script into anything hangs waiting for an EOF the loops hold;
# and a trap that kills an empty list returns non-zero under `set -e`.
# Concurrent csv2 runs contend for the same cores, need no cleanup, and are
# closer to the load of a full suite run.
#
# 爭用來自「並行地跑那些複本」，不是來自忙迴圈。用 `( while :; do :; done ) &` 製造負載，那種
# 行程會繼承每一個已開啟的描述子，於是把這支腳本接進任何管線都會一直掛住，等一個被那些迴圈
# 持有的 EOF；而「kill 一個空清單」的 trap 在 `set -e` 之下會回傳非零。並行的 csv2 執行會爭用
# 同樣的核心、不需要善後，也更接近整套測試執行時的負載。
print -- "rounds=$ROUNDS x 4 chunk sizes x $PAR concurrent = $(( ROUNDS * 4 * PAR )) runs"

for r in {1..$ROUNDS}; do
    for cb in 4 8 16 64; do
        for c in {1..$PAR}; do
            CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=$cb \
                "$CSV2" -contains ok -i "$TMP/t.csv2" > /dev/null 2> "$TMP/e.$cb.$c" &
        done
    done
    wait
    for f in "$TMP"/e.*; do head -1 "$f" >> "$TMP/out"; done
done

sort "$TMP/out" | uniq -c | sort -rn > "$TMP/tally"
cat "$TMP/tally"

# Distinct messages, not "did the expected one appear". A second message is the
# defect even when the first is present, and counting only the expected one
# would report a clean run for a file that told two stories.
# 看的是「相異訊息有幾種」，不是「預期的那一則有沒有出現」。第二則訊息本身就是缺陷——即使第一則
# 也在——而只去數預期的那一則，會讓一個「說了兩個故事」的檔案回報成乾淨。
n=$(wc -l < "$TMP/tally" | tr -d ' ')
total=$(wc -l < "$TMP/out" | tr -d ' ')
if [[ "$n" == 1 ]]; then
    print -- "PASS: $total runs, one message / $total 次執行，一則訊息"
    exit 0
fi
print -u2 -- "FAIL: $total runs produced $n different messages / $total 次執行產生了 $n 種不同的訊息"
exit 1

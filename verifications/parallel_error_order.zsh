#!/usr/bin/env zsh
# =====================================================================
# parallel_error_order.zsh — one broken file, one reason, every time.
# parallel_error_order.zsh — 同一個壞掉的檔案，每一次都給同一個原因。
#
# LE. The parallel path kept whichever worker's error arrived FIRST, and the
# workers run concurrently, so which of two true statements a user saw was
# decided by thread scheduling. Measured before the fix: 1185 runs said
# "record 1 (line 3): a raw newline inside a cell" and 15 said "record 2
# (line 4) has 1 fields but the header has 2" -- the second being what a chunk
# that began mid-record saw, not what is wrong with the file. Someone following
# it to line 4 finds an ordinary row.
#
# LE。平行路徑留住的是「最先**到達**」的那個 worker 的錯誤，而 worker 是並行的，於是使用者
# 看到兩句都為真的話裡的哪一句，由執行緒排程決定。修正前量到：1185 次說「record 1 (line 3)：
# 儲存格裡有裸換行」，15 次說「record 2 (line 4) 有 1 欄而標頭有 2 欄」——後者是「一個從紀錄
# 中間開始的區塊」看到的東西，不是那個檔案真正的毛病。照著它去找第 4 行，會看到一列正常的資料。
#
# WHY THIS IS NOT A CASE IN test_csv2.zsh:
# T118b runs each chunk size once, so it met this roughly one run in eighty --
# it had been passing for as long as the defect existed and failed for the
# first time under the load of a full suite run. A case that catches a race
# 1.25% of the time is not a guard; it is a lottery ticket. The guard is this
# script, which runs the comparison enough times, under load, for absence to
# mean something.
#
# 為什麼這不是 test_csv2.zsh 裡的一個案例：
# T118b 每個 chunk 大小只跑一次，因此大約每八十次執行才遇到一次——在這個缺陷存在的整段期間
# 它都在通過，而第一次失敗是在一次完整執行的負載下。一個「1.25% 的機率抓得到競態」的案例
# 不是守衛，是彩券。守衛是這支腳本：它跑夠多次、而且在負載下跑，好讓「沒有出現」這件事有意義。
#
# Usage / 用法：
#   ./verifications/parallel_error_order.zsh              # 50 x 4 x 6 = 1200 runs
#   ROUNDS=200 ./verifications/parallel_error_order.zsh   # longer
#   PAR=12 ./verifications/parallel_error_order.zsh       # more contention
#
# Verified to BITE: with the fix reverted to first-arrival ordering, a 1200-run
# pass reported 1162 of one message and 38 of the other and exited 1. An
# unproven guard against a 1.25% race is indistinguishable from no guard.
# **證明它會咬**：把修正還原成「先到者勝」之後，一次 1200 次的執行回報 1162 對 38，並以 1 結束。
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
# The first version spawned `( while :; do :; done ) &` for load, and those
# inherit every open descriptor -- so piping this script into anything hung
# forever waiting for an EOF the loops were holding. They also have to be
# killed reliably, and a trap that kills an empty list returns non-zero under
# `set -e`. Concurrent csv2 runs contend for the same cores, need no cleanup,
# and are closer to what the suite was doing when this first appeared.
#
# 爭用來自「並行地跑那些複本」，不是來自忙迴圈。第一版用 `( while :; do :; done ) &` 製造
# 負載，而那種行程會繼承每一個已開啟的描述子——於是把這支腳本接進任何管線都會永遠掛住，
# 等一個被那些迴圈持有著的 EOF。它們也必須被可靠地收掉，而一個「kill 一個空清單」的 trap
# 在 `set -e` 之下會回傳非零。並行的 csv2 執行會爭用同樣的核心、不需要善後，而且更接近這件事
# 第一次出現時整套測試正在做的事。
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

#!/usr/bin/env zsh
# =====================================================================
# test_csv2.zsh — the regression suite for csv2
# test_csv2.zsh — csv2 的回歸測試
#
# Case numbering (T1..T47) matches plan/plan.md's test list exactly, so a
# failing case names the paragraph that explains why the behaviour is what
# it is. Cases the plan lists but that are not implemented yet are reported
# as SKIP with the reason, never quietly omitted -- a suite that hides what
# it did not run reports a coverage it does not have.
# 案例編號（T1..T47）與 plan/plan.md 的測試清單完全對應，因此一個失敗的案例
# 會直接指出解釋該行為的那一段。計畫列出但尚未實作的案例回報為 SKIP 並附原因，
# 絕不安靜略過——一份隱藏「沒跑什麼」的測試，回報的是它並不具備的涵蓋率。
#
# Style follows swift_tar's test scripts: pass/fail counters, a log beside
# the script, a temp dir in the same folder removed on exit. Behaviour is
# tested, never file existence.
# 體例比照 swift_tar 的測試腳本：pass/fail 計數、log 放在腳本旁、暫存目錄建在
# 同一層並於結束時移除。測行為，不測檔案存在。
#
# Usage / 用法:
#   ./test_csv2.zsh              build if needed, run everything
#   CSV2=/path/to/csv2 ./test_csv2.zsh    test a specific binary
# =====================================================================
set -uo pipefail

HERE="${0:A:h}"
ROOT="${HERE:h}"
: ${CSV2:="$ROOT/release/csv2"}

if [[ ! -x "$CSV2" ]]; then
    echo "building first / 先建置：$ROOT/compile_csv2.zsh"
    "$ROOT/compile_csv2.zsh" >/dev/null || { echo "build failed / 建置失敗" >&2; exit 1 }
fi

LOG="$HERE/test_csv2.log"
exec > >(tee "$LOG") 2>&1

echo "[Info] date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "[Info] csv2: $CSV2 ($($CSV2 --version))"
echo "[Info] uname: $(uname -sm)"
echo

TMP="$(mktemp -d "$HERE/.test_csv2.XXXXXX")"
cleanup() { rm -rf "$TMP" }
trap cleanup EXIT INT TERM

pass=0; fail=0; skip=0
# (( n++ )) evaluates to the OLD value, so it returns status 1 the first time a
# counter leaves 0. Harmless while this script does not set -e, but it is a trap
# left lying for whoever adds it.
# (( n++ )) 取的是舊值，因此計數器第一次離開 0 時回傳狀態 1。目前這支腳本沒有
# set -e 所以無害，但那是留給下一個加上 set -e 的人的陷阱。
ok()   { print -r -- "PASS  $1"; pass=$((pass + 1)) }
bad()  { print -r -- "FAIL  $1"; fail=$((fail + 1)) }
skipt(){ print -r -- "SKIP  $1"; skip=$((skip + 1)) }

# assert_same FILE_A FILE_B DESC — byte-identical or fail
# assert_same 檔A 檔B 說明 —— 逐位元相同才 PASS
assert_same() {
    if cmp -s "$1" "$2"; then ok "$3"; else bad "$3 (bytes differ / 位元組不同)"; fi
}
assert_eq() {   # actual expected desc
    if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi
}
assert_contains() { # haystack needle desc
    if [[ "$1" == *"$2"* ]]; then ok "$3"; else bad "$3 (missing '$2' in: ${1:0:200})"; fi
}
# assert_fails DESC -- cmd...  — the command MUST exit non-zero
# assert_fails 說明 -- 指令...  —— 該指令必須以非零結束
# One cell, extracted with csv2 rather than with `cut -d,`.
#
# The suite used `cut -d, -fN` on csv2's own output in twelve places. On this
# project's own fixture that is demonstrably wrong: TARGET_PACKAGES.csv has
# quoted commas in status_notes, and `cut -d, -f6` on record 1 returns a
# fragment of prose beginning mid-value. The encrypted variant happened to come
# out right only because `purpose` has no comma in that one record -- correct by
# luck, and correct until somebody edits the fixture.
#
# A test suite proving that comma splitting is unsafe, while splitting on commas
# to check its own results, is not a contradiction that can be left standing:
# the day the fixture changes, the check breaks in exactly the way the tool
# exists to prevent, and it breaks silently.
#
# Implemented by projection -- delete every other column, then take the record.
# That uses only operations csv2 defines, so the accessor is as correct as the
# parser it is testing. Test scripts are the one place in this tree permitted to
# invoke csv2 for this.
#
# 用 csv2 而不是 `cut -d,` 取出一格。
# 這份測試在十二處對 csv2 自己的輸出使用 `cut -d, -fN`。在本專案自己的 fixture 上，那是
# 可以實證的錯誤：TARGET_PACKAGES.csv 的 status_notes 含有引號內的逗號，對第 1 筆下
# `cut -d, -f6` 會回傳一段從值中間開始的散文碎片。加密後的版本之所以剛好正確，只因為那一筆
# 的 purpose 沒有逗號——正確得靠運氣，而且只正確到有人動了 fixture 為止。
# 一份證明「逗號切割不安全」的測試，自己卻用逗號切割來檢查結果，這個矛盾不能留著：fixture
# 改動的那一天，這個檢查會以這支工具存在所要防止的那種方式壞掉，而且是靜默地壞掉。
# 作法是「投影」——刪掉其餘每一欄，再取那一筆。它只用到 csv2 自己定義的操作，因此這個存取子
# 與它所測試的解析器一樣正確。測試腳本是這棵樹裡唯一被允許為此呼叫 csv2 的地方。
_project() {  # _project <file> <column-number> -> path to a one-column copy
    local f=$1 c=$2 i
    local n=$("$CSV2" -head 1 -t --json -i "$f" 2>/dev/null | head -1 \
              | grep -o '"fields":[0-9]*' | cut -d: -f2)
    local -a drop
    for i in {1..$n}; do (( i == c )) || drop+=(-delete -col $i); done
    "$CSV2" $drop -i "$f" -o "$TMP/.cell.$$.csv" 2>/dev/null || return 1
    print -r -- "$TMP/.cell.$$.csv"
}

# Returns the field AS CSV ENCODES IT: a value containing a comma, quote or
# newline comes back quoted. Decoding it here would mean writing a second
# parser inside the tests for the parser.
# 回傳的是「CSV 編碼後」的欄位：含逗號、引號或換行的值會帶著引號回來。在此解碼等於在
# 「解析器的測試」裡再寫一個解析器。
cell() {   # cell <file> <record> <column-number>
    local p=$(_project "$1" "$3") || return 1
    "$CSV2" -mid "$2,$2" -i "$p" 2>/dev/null
    rm -f "$p" "$p.index"
}

# The header cell, by the same projection. `head -1 | cut -d, -f2` was the last
# comma split left, and a header name is no safer than a value: it is a CSV
# field and may be quoted and contain a comma. After projection the whole line
# IS the field, so no split is needed at all.
# 標頭那一格，用同樣的投影取得。`head -1 | cut -d, -f2` 是最後殘留的逗號切割，而標頭名稱
# 並不比值安全：它就是一個 CSV 欄位，同樣可以帶引號並含有逗號。投影之後整行「就是」那個
# 欄位，於是根本不需要切割。
header_cell() {  # header_cell <file> <column-number>
    local p=$(_project "$1" "$2") || return 1
    head -1 "$p"
    rm -f "$p" "$p.index"
}

assert_fails() {
    local desc="$1"; shift; [[ "$1" == "--" ]] && shift
    local out
    if out="$("$@" 2>&1)"; then
        bad "$desc (exited 0, expected failure / 以 0 結束，預期應失敗)"
    else
        ok "$desc"
    fi
}
assert_succeeds() {
    local desc="$1"; shift; [[ "$1" == "--" ]] && shift
    local out
    if out="$("$@" 2>&1)"; then ok "$desc"; else bad "$desc ($out)"; fi
}

F="$HERE/fixtures"
PKG="$F/TARGET_PACKAGES.csv"

# ---------------------------------------------------------------------
# Generated fixtures. Built here rather than committed when the point of
# the fixture is a specific BYTE SEQUENCE -- a CR, a BOM, a lone 0xE9 --
# which an editor or a git filter can silently normalise away, leaving a
# test that passes by testing nothing.
# 產生式 fixture。當 fixture 的重點是特定的位元組序列（CR、BOM、單獨的 0xE9）
# 時在此產生而不進版控——那些位元組會被編輯器或 git filter 靜默正規化掉，
# 留下一個「因為什麼都沒測到而通過」的測試。
# ---------------------------------------------------------------------
printf 'a,b\r\n1,x\n2,y\r\n' > "$TMP/mixed.csv"
printf 'a,b\n1,"line1\r\nline2"\n' > "$TMP/quoted_crlf.csv"
printf 'a,b\r1,x\r2,y\r' > "$TMP/cronly.csv"
printf '\xef\xbb\xbfpkg,ver\nbusybox,1.37\n' > "$TMP/bom.csv"
printf 'a,b\n1,\xe9\n' > "$TMP/latin1.csv"
printf 'a,b,c\n1,2,3\n4,5\n' > "$TMP/ragged.csv"
printf 'a,b\nx,y\n' > "$TMP/nonl.csv"      # trailing newline present
printf 'a,b\nx,y' > "$TMP/nonl2.csv"       # NO trailing newline

# emoji, one record per line, .csv2
{
  printf 'name,note\n'
  printf '名稱,註記\n'
  printf 'zwj,\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7\xe2\x80\x8d\xf0\x9f\x91\xa6\n'
  printf 'skin,\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbd\n'
  printf 'flag,\xf0\x9f\x87\xb9\xf0\x9f\x87\xbc\n'
  printf 'keycap,1\xef\xb8\x8f\xe2\x83\xa3\n'
  printf 'han,\xe5\xa5\x97\xe4\xbb\xb6\xe5\x90\x8d\xe7\xa8\xb1\n'
} > "$TMP/emoji.csv2"

# The same letter in NFC and in NFD. macOS filesystems hand back NFD and
# Linux prefers NFC, so this is not a theoretical difference.
# 同一個字母的 NFC 與 NFD 形式。macOS 的檔案系統回傳 NFD、Linux 慣用 NFC，
# 因此這不是理論上的差別。
printf 'form,word\n形式,字\nnfc,caf\xc3\xa9\nnfd,cafe\xcc\x81\n' > "$TMP/norm.csv2"

# cells carrying a newline, a CR and a backslash, written escaped
# 含換行、CR 與反斜線的儲存格，以跳脫形式寫入
printf 'k,v\n鍵,值\nnl,a\\nb\ncr,a\\rb\nbs,a\\\\b\n' > "$TMP/esc.csv2"
printf 'k,v\n鍵,值\nbad,a\\qb\n' > "$TMP/badesc.csv2"

echo "--- Phase 1: parsing and round-trip / 第 1 階段：解析與 round-trip ---"

# T1 — the single most valuable test: the real file that was corrupted by
# ${line%,*} on 2026-08-15, asserted byte-identical after a round-trip.
"$CSV2" -r -t -i "$PKG" -o "$TMP/t1.csv" 2>/dev/null
assert_same "$PKG" "$TMP/t1.csv" "T1 quoted embedded commas round-trip byte-identical / 引號內嵌逗號 round-trip 逐位元相同"

# T2 — a timestamp column must still hold a timestamp after a round-trip.
# artifacts.csv had a commit string written into built_utc with nothing
# reporting it; this asserts the shape survives.
if [[ -f "$F/artifacts.csv" ]]; then
    "$CSV2" -r -t -i "$F/artifacts.csv" -o "$TMP/t2.csv" 2>/dev/null
    bad_ts=$("$CSV2" -contains "" -i "$TMP/t2.csv" 2>/dev/null | true)
    assert_same "$F/artifacts.csv" "$TMP/t2.csv" "T2 field types are not moved between columns / 欄位型別不被搬錯"
else
    # Same property on the fixture we do have: every cell of every record
    # comes back in the column it went in.
    a=$("$CSV2" -r -i "$PKG" | awk -F',' '{print NF}' | sort -u | tr '\n' ' ')
    b=$("$CSV2" -r -i "$TMP/t1.csv" | awk -F',' '{print NF}' | sort -u | tr '\n' ' ')
    assert_eq "$a" "$b" "T2 field types are not moved between columns / 欄位型別不被搬錯"
fi

# T3 — a ragged record is an error. Never pad, never truncate.
assert_fails "T3 mismatched field count is an error / 欄數不一致即報錯" -- \
    "$CSV2" -r -i "$TMP/ragged.csv" -so

# T4 — CRLF and LF in the SAME file, decided per record, and everything
# written out as LF.
"$CSV2" -r -t -i "$TMP/mixed.csv" -so > "$TMP/t4.out" 2>/dev/null
# LC_ALL=C because this counts CR BYTES. That is byte work by definition, and
# a multibyte locale can make tr reject the input rather than count it.
# LC_ALL=C，因為這裡數的是 CR「位元組」。那依定義就是位元組操作，而在多位元組
# locale 下 tr 可能會拒絕輸入而不是去數。
cr_count() { LC_ALL=C tr -dc '\r' < "$1" | wc -c | tr -d ' ' }
if [[ $(cr_count "$TMP/t4.out") -eq 0 && $(wc -l < "$TMP/t4.out") -eq 3 ]]; then
    ok "T4 mixed CRLF/LF parsed per record, written as LF / 混用逐筆判斷，一律寫 LF"
else
    bad "T4 mixed CRLF/LF (got $(wc -l < "$TMP/t4.out") lines, $(cr_count "$TMP/t4.out") CR)"
fi

# T5 — the opposite rule, which is easy to break while implementing T4:
# a CRLF INSIDE quotes is data and must survive byte for byte.
"$CSV2" -r -t -i "$TMP/quoted_crlf.csv" -o "$TMP/t5.csv" 2>/dev/null
assert_same "$TMP/quoted_crlf.csv" "$TMP/t5.csv" "T5 CRLF inside quotes preserved exactly / 引號內的 CRLF 原樣保留"

# T6 — a CR-only file gets its OWN message, not a field-count complaint.
out=$("$CSV2" -r -i "$TMP/cronly.csv" -so 2>&1)
assert_contains "$out" "CR line endings" "T6 CR-only file gets a dedicated message / CR-only 檔案有專屬訊息"

# T7 — BOM stripped on read, never written, and name addressing still works.
"$CSV2" -r -t -i "$TMP/bom.csv" -o "$TMP/t7.csv" 2>/dev/null
head_bytes=$(head -c 3 "$TMP/t7.csv" | xxd -p)
name_ok=$("$CSV2" -update '1:pkg' 'zzz' -i "$TMP/bom.csv" -o "$TMP/t7b.csv" 2>&1 && echo yes)
if [[ "$head_bytes" != "efbbbf" && "$name_ok" == "yes" ]]; then
    ok "T7 BOM stripped, not re-emitted, name addressing works / BOM 剝除、不再產生、以欄名定址正確"
else
    bad "T7 BOM (first bytes '$head_bytes', name addressing '$name_ok')"
fi

# T8 — a non-UTF-8 byte survives. Replacing it with U+FFFD would be data
# loss reported as success.
"$CSV2" -r -t -i "$TMP/latin1.csv" -o "$TMP/t8.csv" 2>/dev/null
assert_same "$TMP/latin1.csv" "$TMP/t8.csv" "T8 non-UTF-8 bytes round-trip unchanged / 非 UTF-8 位元組原樣 round-trip"

# T9 / T12 / T13 measure. csv2 reports peak RSS and bytes read under -debug,
# so these assert the streaming guarantees instead of trusting them.
#
# The plan asks for "an input larger than memory". A regression suite cannot
# build one, and it does not have to: the property that matters is that memory
# does not GROW with the input. Two inputs an order of magnitude apart show
# that directly, and run in seconds.
# 計畫要求「以大於記憶體的輸入驗證」。回歸測試造不出那種輸入，也不需要：真正
# 要證明的性質是「記憶體不隨輸入變大而變大」。兩個相差一個數量級的輸入可以直接
# 顯示這一點，而且只要幾秒鐘。
mk_rows() { # path records
    { print -r -- 'k,v,note'
      print -r -- '鍵,值,註記'
      for i in {1..$2}; do print -r -- "row$i,value$i,\"note, with comma $((i % 97))\""; done
    } > "$1"
}
mk_rows "$TMP/m_small.csv2" 2000
mk_rows "$TMP/m_big.csv2"   80000
rss_of() {  # reads the metrics line csv2 emits under -debug
    grep -o 'peak_rss_bytes=[0-9]*' "$1" | tail -1 | cut -d= -f2
}
read_of() {
    grep -o 'read_bytes=[0-9]*' "$1" | tail -1 | cut -d= -f2
}

cat "$TMP/m_small.csv2" | "$CSV2" -si --headers 2 -so -r -debug > /dev/null 2>"$TMP/m9a.txt"
cat "$TMP/m_big.csv2"   | "$CSV2" -si --headers 2 -so -r -debug > /dev/null 2>"$TMP/m9b.txt"
r_small=$(rss_of "$TMP/m9a.txt"); r_big=$(rss_of "$TMP/m9b.txt")
size_small=$(wc -c < "$TMP/m_small.csv2" | tr -d ' ')
size_big=$(wc -c < "$TMP/m_big.csv2" | tr -d ' ')
if [[ -n "$r_small" && -n "$r_big" && $((size_big / size_small)) -ge 10 && $r_big -lt $((r_small * 2)) ]]; then
    ok "T9 -si/-so RSS does not grow with the input (${size_small}B→${r_small}B, ${size_big}B→${r_big}B) / 串流 RSS 不隨輸入變大"
else
    bad "T9 streaming RSS (small ${size_small}B→${r_small}B, big ${size_big}B→${r_big}B)"
fi

echo
echo "--- Phase 2: selection and locating / 第 2 階段：選取與定位 ---"

# T10 — a record spanning several physical lines still reports the RECORD
# number, which is the CSV answer, not the line number.
out=$("$CSV2" -contains "line2" -i "$TMP/quoted_crlf.csv" 2>/dev/null)
assert_contains "$out" "1:2" "T10 record number correct across an embedded newline / 內嵌換行時紀錄號正確"

# T11 — the two halves of the -t rule.
"$CSV2" -head 3 -t -i "$PKG" -o "$TMP/t11.csv" 2>/dev/null
n=$("$CSV2" -r -i "$TMP/t11.csv" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "3" "T11a -head 3 -t output reads back as 3 records / -t 的輸出可讀回為 3 筆"
assert_fails "T11b -head without -t refuses to write a .csv2 / 無 -t 拒絕寫入 .csv2" -- \
    "$CSV2" -head 3 -i "$PKG" -o "$TMP/t11b.csv2"

# T12 — -tail keeps only N records, so its memory is set by N and not by the
# file. Measured with --no-index so this tests the ring buffer rather than the
# index seek, which would avoid the question entirely.
# T12 —— -tail 只保留 N 筆，因此它的記憶體由 N 決定而非由檔案決定。以 --no-index
# 量測，讓這裡測到的是環狀緩衝本身，而不是索引 seek——後者會直接繞過這個問題。
"$CSV2" -tail 10 --no-index -i "$TMP/m_small.csv2" -debug >/dev/null 2>"$TMP/m12a.txt"
"$CSV2" -tail 10 --no-index -i "$TMP/m_big.csv2"   -debug >/dev/null 2>"$TMP/m12b.txt"
t_small=$(rss_of "$TMP/m12a.txt"); t_big=$(rss_of "$TMP/m12b.txt")
if [[ -n "$t_small" && -n "$t_big" && $t_big -lt $((t_small * 2)) ]]; then
    ok "T12 -tail RSS is bounded by N, not by file size (${size_small}B→${t_small}B, ${size_big}B→${t_big}B) / -tail 的 RSS 由 N 決定，與檔案大小無關"
else
    bad "T12 -tail RSS (small→$t_small, big→$t_big)"
fi

# T13 — the property that separates -mid from -tail. If -mid were implemented
# as "read it all, then slice", this number would equal the file size and the
# cheapest range operation on a huge file would not be cheap at all.
# T13 —— 這是 -mid 與 -tail 的關鍵差異。若 -mid 被實作成「全讀再切片」，這個數字
# 會等於檔案大小，而「巨大檔案上最便宜的範圍操作」就一點也不便宜了。
"$CSV2" -mid 1,2 --no-index -i "$TMP/m_big.csv2" -debug >/dev/null 2>"$TMP/m13.txt"
mid_read=$(read_of "$TMP/m13.txt")
if [[ -n "$mid_read" && $mid_read -lt $((size_big / 10)) ]]; then
    ok "T13 -mid 1,2 read $mid_read of $size_big bytes, stopping at record b / -mid 只讀了 $mid_read／$size_big 位元組，在第 b 筆處停止"
else
    bad "T13 -mid read $mid_read of $size_big bytes (expected far less) / -mid 讀了 $mid_read／$size_big（預期應遠小於）"
fi

# T14 — the four -mid boundary rules, each with its own decided answer.
assert_fails "T14a -mid 7,3 (a>b) is an error, not silently swapped / a>b 報錯，不自動對調" -- \
    "$CSV2" -mid 7,3 -i "$PKG" -so
assert_fails "T14b -mid 0,3 (a<1) is an error / a<1 報錯" -- \
    "$CSV2" -mid 0,3 -i "$PKG" -so
n=$("$CSV2" -mid 20,999 -i "$PKG" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "2" "T14c -mid b past the end runs to EOF without an error / b 超界輸出到檔尾且不報錯"
n=$("$CSV2" -mid 900,999 -t -i "$PKG" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "1" "T14d -mid a past the end gives header only, still valid / a 超界只有標頭且仍合法"

# T15 — -rownum is output-side only: it must not shift addressing and must
# not be searchable, or a flag that "just prints one more column" would
# quietly change what every address means.
a=$("$CSV2" -contains "busybox" -i "$PKG" 2>/dev/null | head -1 | cut -f1)
b=$("$CSV2" -contains "busybox" -rownum -i "$PKG" 2>/dev/null | head -1 | cut -f1)
assert_eq "$b" "$a" "T15a -rownum does not change record:field addressing / -rownum 不改變定址"
c=$("$CSV2" -contains "1" -rownum -i "$PKG" 2>/dev/null | cut -f1 | cut -d: -f2 | sort -u | grep -c '^0$' || true)
assert_eq "$c" "0" "T15b the rownum column is never searched / rownum 欄不參與比對"

# The other half of the same fact, and the half that bites. Addresses stay put
# BECAUSE the printed row moves: with -rownum, pkg_name is address 1 and
# physical column 2. Round 16 of the blind testing found this documented
# nowhere -- the tool did the right thing and never said which numbering
# applied where, so anything reading the output by position gets everything
# shifted one right while every address it holds still means the old column.
# 同一件事的另一半，也是會咬人的那一半。位址之所以不動，正是因為印出來的那一列動了：
# 開了 -rownum 之後，pkg_name 的位址是 1、實體欄位是 2。盲測第 16 回合發現這件事在任何地方
# 都沒有被記載——工具做的是對的，卻從未說明哪一套編號適用於何處；於是任何「依位置」讀取
# 輸出的東西，看到的每一欄都往右移了一格，而它手上的每一個位址仍指向原本那一欄。
first_col=$("$CSV2" -head 1 -t -rownum -i "$PKG" 2>/dev/null | head -1 | cut -d, -f1)
assert_eq "$first_col" "rownum" \
    "T15c with -rownum the FIRST physical column is rownum / 開了 -rownum 之後，第一個實體欄位是 rownum"
addr_col=$("$CSV2" -contains "busybox" -rownum -i "$PKG" 2>/dev/null | head -1 | cut -f2)
assert_eq "$addr_col" "pkg_name" \
    "T15d while address 1 still names pkg_name: the two numberings differ by one / 而位址 1 仍指向 pkg_name：兩套編號差一格"

# T16 — context is counted in RECORDS and blocks are separated by --.
n0=$("$CSV2" -contains "invalid option" --filter -i "$PKG" 2>/dev/null | wc -l | tr -d ' ')
n=$("$CSV2" -contains "invalid option" -A 2 -i "$PKG" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n0" "1" "T16a the needle matches exactly one record / 該字串只命中一筆"
assert_eq "$n" "3" "T16b -A 2 gives 2 further RECORDS, not 2 lines / -A 2 給的是 2 筆而非 2 行"

echo
echo "--- Phase 3: two-row headers and output formats / 第 3 階段：兩列標頭與輸出格式 ---"

# T17 — the escaping that decides whether a Markdown table is correct or
# merely looks correct. status_notes is the same data source as T1.
md=$("$CSV2" -head 1 -t -md -i "$PKG" 2>/dev/null)
rows=$(print -r -- "$md" | wc -l | tr -d ' ')
assert_eq "$rows" "3" "T17a -md keeps one record on one row despite | and newlines / 含 | 與換行仍不切開表格"
cols_h=$(print -r -- "$md" | sed -n 1p | awk -F'|' '{print NF}')
cols_d=$(print -r -- "$md" | sed -n 3p | awk -F'|' '{print NF}')
assert_eq "$cols_d" "$cols_h" "T17b -md data row has the same column count as the header / 資料列欄數與標頭相同"

assert_fails "T18a -md without -t is an error / -md 未給 -t 即報錯" -- \
    "$CSV2" -head 1 -md -i "$PKG" -so
assert_fails "T18b -md into a .csv2 path is an error / -md 寫入 .csv2 即報錯" -- \
    "$CSV2" -head 1 -t -md -i "$PKG" -o "$TMP/t18.csv2"

# T19 — the trade --pretty makes, asserted from both sides.
#
# The alignment check uses Han and ASCII only. zsh's ${(m)#s} gives the
# display width, and it is right for CJK -- but it sums the scalars of a ZWJ
# sequence and calls the family emoji 8, which is the very mistake the width
# table exists to avoid. Using it as the oracle for emoji would assert the
# wrong answer.
# 對齊檢查只用中文與 ASCII。zsh 的 ${(m)#s} 給的是顯示寬度，對 CJK 是對的——但它
# 會把 ZWJ 序列的各 scalar 加總，說家庭 emoji 是 8，而那正是這張寬度表要避免的
# 錯誤。拿它當 emoji 的判準，會斷言出錯誤的答案。
{
  print -r -- 'a,b'
  print -r -- '甲,乙'
  print -r -- '套件名稱,x'          # 4 characters, 8 columns
  print -r -- 'abcdefgh,y'          # 8 characters, 8 columns
} > "$TMP/p19.csv2"
"$CSV2" -r -t -md --pretty -i "$TMP/p19.csv2" > "$TMP/p19.md" 2>/dev/null
widths=()
while IFS= read -r ln; do widths+=(${(m)#ln}); done < "$TMP/p19.md"
uniq_w=$(print -l -- $widths | sort -u | wc -l | tr -d ' ')
if [[ "$uniq_w" == "1" && ${#widths} -eq 4 ]]; then
    ok "T19a --pretty aligns by DISPLAY width: 套件名稱 counts 8, not 4 / --pretty 以顯示寬度對齊：套件名稱 算 8 而非 4"
else
    bad "T19a --pretty alignment (line widths: $widths)"
fi

# The default form is the minimal |a|b|, which renders identically and needs
# to know none of this -- which is why it is the default.
# The distinguishing property is padding, not any one line's text: the plain
# form pads nothing, the aligned form pads. Checking for a literal header line
# would only have tested how the two header rows are merged.
# 區分兩者的性質是「有沒有填空白」，而不是某一行的字面內容：未對齊的形式完全
# 不填，對齊的形式會填。去比對某一行的字面內容，只會測到兩列標頭怎麼合併。
pad_plain=$("$CSV2" -r -t -md -i "$TMP/p19.csv2" 2>/dev/null | grep -c '  ' || true)
pad_pretty=$(grep -c '  ' "$TMP/p19.md" || true)
if [[ "$pad_plain" == "0" && "$pad_pretty" -gt 0 ]]; then
    ok "T19b without --pretty nothing is padded; with it, cells are / 未給 --pretty 時完全不填空白，給了才填"
else
    bad "T19b padding (plain=$pad_plain lines padded, pretty=$pad_pretty)"
fi

# --pretty has already given up streaming, so on a large table the failure
# mode is the OOM killer -- and a killed process leaves no message at all.
# It must refuse instead.
# --pretty 已經放棄串流，因此在大表上的失敗模式是被 OOM killer 終結——而被殺掉的
# 行程不會留下任何訊息。它必須改為拒絕。
out=$(CSV2_PRETTY_MAX_BYTES=100 "$CSV2" -r -t -md --pretty -i "$TMP/m_big.csv2" 2>&1)
rc=$?
if [[ $rc -ne 0 && "$out" == *"--pretty"* ]]; then
    ok "T19c --pretty refuses a table too large to hold, rather than being OOM-killed / --pretty 對持有不下的表格選擇拒絕，而不是被 OOM 殺掉"
else
    bad "T19c --pretty over the limit (rc=$rc, out: ${out:0:160})"
fi

# And the other side of the trade: the unaligned form still streams.
"$CSV2" -r -t -md -i "$TMP/m_small.csv2" -debug >/dev/null 2>"$TMP/p19a.txt"
"$CSV2" -r -t -md -i "$TMP/m_big.csv2"   -debug >/dev/null 2>"$TMP/p19b.txt"
md_small=$(rss_of "$TMP/p19a.txt"); md_big=$(rss_of "$TMP/p19b.txt")
if [[ -n "$md_small" && -n "$md_big" && $md_big -lt $((md_small * 2)) ]]; then
    ok "T19d -md without --pretty still streams (${md_small}B→${md_big}B RSS) / 未加 --pretty 的 -md 仍然串流"
else
    bad "T19d -md streaming RSS (small→$md_small, big→$md_big)"
fi

# T20 — JSON Lines: metadata first, one object per hit, non-ASCII raw.
j=$("$CSV2" -contains "套件" -i "$TMP/emoji.csv2" --json 2>/dev/null)
assert_contains "$(print -r -- "$j" | head -1)" '"meta"' "T20a --json first line is metadata / --json 首行是 metadata"
assert_contains "$j" '套件' "T20b --json does not escape non-ASCII by default / 預設不跳脫非 ASCII"
ja=$("$CSV2" -contains "套件" -i "$TMP/emoji.csv2" --json-ascii 2>/dev/null)
if [[ "$ja" == *'\u5957'* && "$ja" != *'套'* ]]; then
    ok "T20c --json-ascii escapes non-ASCII / --json-ascii 會跳脫非 ASCII"
else
    bad "T20c --json-ascii (got: ${ja:0:200})"
fi

# T21 — the backslash escaping is lossless, and an undefined escape is an
# error rather than "keep it as written" (which would let two different
# byte sequences read back as one value).
"$CSV2" -r -t -i "$TMP/esc.csv2" -o "$TMP/t21.csv2" 2>/dev/null
assert_same "$TMP/esc.csv2" "$TMP/t21.csv2" "T21a .csv2 escaping is lossless / .csv2 跳脫無損"
assert_fails "T21b an undefined escape \\q is an error / 未定義跳脫序列報錯" -- \
    "$CSV2" -r -i "$TMP/badesc.csv2" -so

# T22 — the invariant that makes wc -l, sed -n Np and split -l correct on
# a .csv2 file.
"$CSV2" -r -t -i "$TMP/esc.csv2" -o "$TMP/t22.csv2" 2>/dev/null
lines=$(wc -l < "$TMP/t22.csv2" | tr -d ' ')
recs=$("$CSV2" -r -i "$TMP/t22.csv2" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$((lines - 2))" "$recs" "T22 .csv2 keeps one record per line / .csv2 一筆一行"

# T23 — emoji are free for a byte-level parser; this asserts it.
"$CSV2" -r -t -i "$TMP/emoji.csv2" -o "$TMP/t23.csv2" 2>/dev/null
assert_same "$TMP/emoji.csv2" "$TMP/t23.csv2" "T23 emoji round-trip byte-identical / emoji round-trip 逐位元相同"

# T24 — storage never normalises; only comparison does, and only on request.
"$CSV2" -r -t -i "$TMP/norm.csv2" -o "$TMP/t24.csv2" 2>/dev/null
assert_same "$TMP/norm.csv2" "$TMP/t24.csv2" "T24a NFC and NFD are both stored unchanged / NFC 與 NFD 都原樣保留"
n1=$("$CSV2" -contains "$(printf 'caf\xc3\xa9')" -i "$TMP/norm.csv2" 2>/dev/null | wc -l | tr -d ' ')
n2=$("$CSV2" -contains "$(printf 'caf\xc3\xa9')" --normalize -i "$TMP/norm.csv2" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$n1" -eq 1 && "$n2" -eq 2 ]]; then
    ok "T24b comparison is byte-wise unless --normalize / 比對預設逐位元組，--normalize 才正規化"
else
    bad "T24b normalize (plain=$n1 want 1, normalized=$n2 want 2)"
fi

# T25 — a long emoji cell echoed in output must still be valid UTF-8 after
# truncation. A tool that produces mojibake while reporting sends you the
# wrong way.
# T25 — truncation must land on a grapheme cluster boundary.
#
# Asserted by construction, with no external tool. The value is 300 identical
# ZWJ family emoji and the report's echo limit is 200 clusters, so the correct
# output is EXACTLY 200 families followed by the truncation marker. Building
# that expected string here and comparing it is strictly stronger than asking
# "is this valid UTF-8": it pins the truncation POINT, not merely the fact
# that nothing was cut in half.
#
# The earlier version used `iconv -f UTF-8 -t UTF-8` as the oracle. That made
# the case depend on a tool the guest's busybox does not provide, so it turned
# into a SKIP on the platform where byte-level behaviour matters most -- and a
# skip is exactly what this case should never be.
# T25 —— 截斷必須落在 grapheme cluster 邊界。
#
# 以「構造」來斷言，不依賴任何外部工具。值是 300 個相同的 ZWJ 家庭 emoji，而報告的
# 回顯上限是 200 個 cluster，因此正確的輸出恰好是 200 個家庭加上截斷標記。在此建出
# 那個預期字串並比對，比問「這是不是合法的 UTF-8」嚴格得多：它釘住的是截斷的「位置」，
# 而不只是「沒有把東西切成兩半」這個事實。
#
# 先前的版本以 `iconv -f UTF-8 -t UTF-8` 當判準，那讓這個案例依賴一個 guest 的
# busybox 並不提供的工具，於是它在「位元組層級行為最要緊」的那個平台上變成 SKIP
# ——而這個案例最不該變成的就是 SKIP。
family=$(printf '\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7\xe2\x80\x8d\xf0\x9f\x91\xa6')
long=""
for i in {1..300}; do long+=$family; done
printf 'k,v\n鍵,值\nlong,%s\n' "$long" > "$TMP/long.csv2"

want=""
for i in {1..200}; do want+=$family; done
want+="…[+100 more chars]"

got=$("$CSV2" -contains "$family" -i "$TMP/long.csv2" 2>&1 | head -1 | cut -f3)
if [[ "$got" == "$want" ]]; then
    ok "T25 truncation cuts at exactly 200 clusters, not mid-sequence / 截斷恰好在第 200 個 cluster，未切在序列中間"
else
    bad "T25 truncation point (got ${#got} chars, want ${#want}) / 截斷位置不符"
    print -r -- "      got tail:  $(print -r -- "$got" | LC_ALL=C tail -c 32 | LC_ALL=C od -An -tx1 | LC_ALL=C tr -d ' \n')"
    print -r -- "      want tail: $(print -r -- "$want" | LC_ALL=C tail -c 32 | LC_ALL=C od -An -tx1 | LC_ALL=C tr -d ' \n')"
fi

# And the complementary half: a cell whose bytes are NOT valid UTF-8 must be
# rendered as hex rather than emitted raw, so the report itself never becomes
# unreadable. csv2 decides this, so no external validator is needed here either.
# 另一半：位元組並非合法 UTF-8 的儲存格必須以十六進位呈現而非原樣輸出，讓報告本身
# 不會變成不可讀。這件事由 csv2 自己決定，因此此處同樣不需要外部驗證工具。
printf 'k,v\n鍵,值\nbad,x\xe9y\n' > "$TMP/nonutf8.csv2"
got=$("$CSV2" -contains "x" -i "$TMP/nonutf8.csv2" 2>&1 | head -1)
if [[ "$got" == *"non-UTF-8"* ]]; then
    ok "T25b a non-UTF-8 cell is echoed as hex, not raw bytes / 非 UTF-8 儲存格以十六進位回顯，不吐原始位元組"
else
    bad "T25b non-UTF-8 echo (got: ${got:0:80})"
fi

# T26 — stdin has no extension, so the format cannot be a declared fact and
# a default here would be a guess.
assert_fails "T26 -si without --headers is an error / -si 未給 --headers 即報錯" -- \
    zsh -c "cat '$PKG' | '$CSV2' -si -so -r"
assert_succeeds "T26b -si with --headers 1 works / -si 加 --headers 1 可用" -- \
    zsh -c "cat '$PKG' | '$CSV2' -si --headers 1 -so -r > /dev/null"

echo
echo "--- Phase 4: editing, encryption, logging / 第 4 階段：編輯、加密、記錄 ---"

# T27 — the whole point of "all indexes refer to the input".
"$CSV2" -delete 3 -delete 4 -i "$PKG" -o "$TMP/t27.csv" 2>/dev/null
orig3=$(cell "$PKG" 3 1)
orig5=$(cell "$PKG" 5 1)
new3=$(cell "$TMP/t27.csv" 3 1)
if [[ "$new3" == "$orig5" && "$new3" != "$orig3" ]]; then
    ok "T27 -delete 3 -delete 4 deletes INPUT records 3 and 4 / 刪的是輸入的第 3、4 筆"
else
    bad "T27 delete indexes (record 3 is now '$new3', input 5 was '$orig5')"
fi

# T28 — the failure mode that cost this project two restores from git.
cp "$PKG" "$TMP/t28.csv"
assert_fails "T28a -i and -o the same path is refused by default / 同路徑預設拒絕" -- \
    "$CSV2" -update '1:1' 'zzz' -i "$TMP/t28.csv" -o "$TMP/t28.csv"
"$CSV2" -update '1:1' 'zzz' -i "$TMP/t28.csv" --in-place 2>/dev/null
v=$(cell "$TMP/t28.csv" 1 1)
assert_eq "$v" "zzz" "T28b --in-place edits via temp file and rename / --in-place 以暫存檔加 rename 完成"
cp "$PKG" "$TMP/t28c.csv"
"$CSV2" -update '99:1' 'zzz' -i "$TMP/t28c.csv" --in-place 2>/dev/null
assert_same "$PKG" "$TMP/t28c.csv" "T28c a failed in-place edit leaves the original intact / 失敗時原檔完好"
# And leaves nothing beside it. A stray temp file next to a data file is the
# kind of debris a later glob picks up as if it were input -- the failure is
# then not the edit, it is whatever reads the directory next.
# 而且旁邊什麼都不留。資料檔旁的暫存殘骸，正是日後某個 glob 會當成輸入撿起來的那種東西
# ——屆時失敗的不是那次編輯，而是下一個讀取該目錄的東西。
stray=$(ls "$TMP" | grep -c "^t28c\.csv\." || true)
assert_eq "$stray" "0" \
    "T28d and leaves no temp file beside it / 且旁邊不留暫存檔"

# T29 — out of range is an error, never "grow the file to fit".
assert_fails "T29 -update 99:3 on a 21-record file is an error / 越界即錯誤" -- \
    "$CSV2" -update '99:3' 'x' -i "$PKG" -o "$TMP/t29.csv"

# T30 — blanking a cell must not change the field count. Tested on the
# column that actually contains quoted commas.
"$CSV2" -delete -cell '1:status_notes' -i "$PKG" -o "$TMP/t30.csv" 2>/dev/null
h=$("$CSV2" -head 1 -t -i "$TMP/t30.csv" --json 2>/dev/null | head -1 | grep -o '"fields":[0-9]*' | cut -d: -f2)
assert_succeeds "T30a a blanked cell leaves a readable file / 清空後檔案仍可讀" -- \
    "$CSV2" -r -i "$TMP/t30.csv" -so
assert_eq "$h" "7" "T30b -delete -cell does not change the field count / -delete -cell 不改變欄數"

# T31/T32 — the address form must match the flag; csv2 never infers which
# of two very different operations was meant.
assert_fails "T31a -delete 12:6 without -cell is an error / 缺 -cell 即報錯" -- \
    "$CSV2" -delete '12:6' -i "$PKG" -o "$TMP/x.csv"
assert_fails "T31b -delete -cell 5 (not r:c) is an error / 位址非 r:c 即報錯" -- \
    "$CSV2" -delete -cell '5' -i "$PKG" -o "$TMP/x.csv"
assert_fails "T32 -insert -cell is refused / -insert -cell 明確拒絕" -- \
    "$CSV2" -insert -cell 3 'a' -i "$PKG" -o "$TMP/x.csv"

# T33 — the field-count rule applied to the write side.
assert_fails "T33 -insert with the wrong field count is an error / 插入欄數不符即報錯" -- \
    "$CSV2" -insert 3 'only,two' -i "$PKG" -o "$TMP/x.csv"

# --- key material for the crypto cases / 加密案例所需的金鑰素材 ---
KEYDIR="$TMP/home/.multissh/generated"
mkdir -p "$KEYDIR"
head -c 64 /dev/urandom > "$KEYDIR/mldsa44-ed25519.key.raw"
chmod 600 "$KEYDIR/mldsa44-ed25519.key.raw"
head -c 64 /dev/urandom > "$TMP/other.key"
KEY="$KEYDIR/mldsa44-ed25519.key.raw"

# T34 — round-trip, and the property SHA-256 could never provide: a
# tampered cell FAILS rather than decrypting to something wrong.
"$CSV2" -encrypt status_notes -keyfile "$KEY" -i "$PKG" -o "$TMP/enc.csv" 2>/dev/null
"$CSV2" -decrypt status_notes -keyfile "$KEY" -i "$TMP/enc.csv" -o "$TMP/dec.csv" 2>/dev/null
assert_same "$PKG" "$TMP/dec.csv" "T34a encrypt then decrypt restores every byte / 加解密 round-trip 逐位元還原"
# Flip one character INSIDE the encrypted cell. Editing the end of the line
# would land in the license column and prove nothing about the AEAD.
# 在加密的儲存格「內部」改一個字元。改行尾會落在 license 欄，對 AEAD 什麼都
# 證明不了。
ct=$(cell "$TMP/enc.csv" 1 6)
flip=$(print -r -- "$ct" | sed 's/^A/B/; t; s/^./A/')
"$CSV2" -update '1:6' "$flip" -i "$TMP/enc.csv" -o "$TMP/tamper.csv" 2>/dev/null
assert_fails "T34b a tampered ciphertext fails to decrypt / 密文被竄改即解密失敗" -- \
    "$CSV2" -decrypt status_notes -keyfile "$KEY" -i "$TMP/tamper.csv" -o "$TMP/x.csv"

# T35 — encryption must not break the format it is applied to.
assert_succeeds "T35a an encrypted file is still readable by csv2 / 加密後仍可被讀取" -- \
    "$CSV2" -r -i "$TMP/enc.csv" -so
hdr=$(head -1 "$TMP/enc.csv")
if [[ "$hdr" == *"pkg_name"* && "$hdr" == *"status_notes:enc:"* ]]; then
    ok "T35b the header is never encrypted, only marked / 標頭未被加密，只被標記"
else
    bad "T35b header marking (got: ${hdr:0:120})"
fi

# T36 — determinism is the difference between the two features, and it is
# what tells you which one you actually want.
"$CSV2" -hash status_notes -i "$PKG" -o "$TMP/h1.csv" 2>/dev/null
"$CSV2" -hash status_notes -i "$PKG" -o "$TMP/h2.csv" 2>/dev/null
assert_same "$TMP/h1.csv" "$TMP/h2.csv" "T36a -hash is deterministic / -hash 是確定性的"
"$CSV2" -encrypt status_notes -keyfile "$KEY" -i "$PKG" -o "$TMP/e2.csv" 2>/dev/null
if cmp -s "$TMP/enc.csv" "$TMP/e2.csv"; then
    bad "T36b -encrypt produced identical output twice: the nonce is being reused / 兩次加密結果相同：nonce 被重用了"
else
    ok "T36b -encrypt uses a fresh nonce each run / -encrypt 每次使用新的 nonce"
fi

# T37 — no key is an error. Never generate one, never fall back: a fallback
# yields a file that decrypts with a key you did not mean to use.
out=$(HOME="$TMP/nowhere" "$CSV2" -encrypt status_notes --yes -i "$PKG" -o "$TMP/t37.csv" 2>&1)
rc=$?
if [[ $rc -ne 0 && "$out" == *"no key at"* && ! -f "$TMP/t37.csv" ]]; then
    ok "T37 a missing key is an error, with no fallback and no output / 找不到金鑰即報錯，不後援也不產生輸出"
else
    bad "T37 missing key (rc=$rc, output: ${out:0:160})"
fi

# T38 — a prompt that cannot be shown is never a yes.
out=$(HOME="$TMP/home" zsh -c "'$CSV2' -encrypt status_notes -i '$PKG' -o '$TMP/x2.csv' < /dev/null" 2>&1)
rc=$?
if [[ $rc -ne 0 && "$out" == *"tty"* ]]; then
    ok "T38 no tty means fail, never assume yes / 無 tty 時失敗，絕不視為同意"
else
    bad "T38 tty prompt (rc=$rc, output: ${out:0:160})"
fi

# T39 — the fingerprint turns "Poly1305 authentication failed", which reads
# like file corruption, into a message about the key.
out=$("$CSV2" -decrypt status_notes -keyfile "$TMP/other.key" -i "$TMP/enc.csv" -o "$TMP/x.csv" 2>&1)
assert_contains "$out" "fingerprint" "T39 a wrong key names the fingerprint mismatch / 金鑰不符時指出指紋不符"

# T40 — the log must never carry the plaintext of a protected column.
secret="TOPSECRET-$RANDOM"
"$CSV2" -update "1:status_notes" "$secret" -hash status_notes \
        -log "$TMP/t40.log" -i "$PKG" -o "$TMP/t40.csv" 2>/dev/null
if grep -q "$secret" "$TMP/t40.log" 2>/dev/null; then
    bad "T40 the log leaked the plaintext of a protected column / log 洩漏了受保護欄位的明文"
else
    ok "T40 the log redacts protected columns / log 對受保護欄位做遮蔽"
fi

echo
echo "--- Phase 5: index, parallel, append / 第 5 階段：索引、平行、追加 ---"

# A file with enough records to have several index grid points (stride 256)
# and, with the chunk size turned down, several parallel chunks. The
# thresholds are environment-overridable precisely so this does not need a
# 16 MiB fixture.
# 一個紀錄數足以產生多個索引格點（stride 256）的檔案；把區塊大小調小之後，
# 它也足以切出多個平行區塊。門檻之所以可由環境變數覆寫，正是為了讓這件事
# 不需要 16 MiB 的 fixture。
{
  print -r -- 'k,v,note'
  print -r -- '鍵,值,註記'
  for i in {1..3000}; do print -r -- "row$i,value$i,\"note, with comma $((i % 97))\""; done
} > "$TMP/idx.csv2"
export CSV2_INDEX_MIN_BYTES=1000

# The index is a by-product of writing, so an edit is what creates one.
"$CSV2" -update '1:v' 'CHANGED' -i "$TMP/idx.csv2" -o "$TMP/ix.csv2" 2>/dev/null
if [[ -f "$TMP/ix.csv2.index" ]]; then
    ok "T41a writing a file leaves an index beside it / 寫入時順手產生索引"
else
    bad "T41a no index was written / 沒有產生索引"
fi
assert_succeeds "T41b --verify-index confirms the index describes the file / --verify-index 確認索引與檔案相符" -- \
    "$CSV2" --verify-index -i "$TMP/ix.csv2"

# The rule the whole feature hangs from: with a good index, a missing one, a
# stale one and a truncated one, the output must be byte-identical and none
# may fail. An index that quickly gives you the wrong data is far worse than
# no index at all, so the default action on any doubt is to discard and scan.
# 整個功能所繫的那條規則：索引正確、不存在、過期、被截斷四種情況，輸出必須
# 逐位元相同，且都不得失敗。一個會很快給你錯資料的索引，比沒有索引糟得多，
# 因此只要有疑慮，預設動作就是丟棄並掃描。
cp "$TMP/ix.csv2.index" "$TMP/good.index"
"$CSV2" -mid 1500,1502 -i "$TMP/ix.csv2" > "$TMP/i_good.txt" 2>/dev/null
"$CSV2" -tail 3        -i "$TMP/ix.csv2" > "$TMP/t_good.txt" 2>/dev/null

rm -f "$TMP/ix.csv2.index"
"$CSV2" -mid 1500,1502 -i "$TMP/ix.csv2" > "$TMP/i_none.txt" 2>/dev/null
"$CSV2" -tail 3        -i "$TMP/ix.csv2" > "$TMP/t_none.txt" 2>/dev/null

# stale: same size, but the recorded content hash no longer matches
printf 'STALEBYTES' | dd of="$TMP/ix.csv2.index" bs=1 seek=64 conv=notrunc 2>/dev/null
cp "$TMP/good.index" "$TMP/ix.csv2.index"
printf 'STALEBYTES' | dd of="$TMP/ix.csv2.index" bs=1 seek=64 conv=notrunc 2>/dev/null
"$CSV2" -mid 1500,1502 -i "$TMP/ix.csv2" > "$TMP/i_stale.txt" 2>/dev/null
rc_stale=$?

# truncated: header intact, grid entries cut off
head -c 100 "$TMP/good.index" > "$TMP/ix.csv2.index"
"$CSV2" -mid 1500,1502 -i "$TMP/ix.csv2" > "$TMP/i_trunc.txt" 2>/dev/null
rc_trunc=$?

if cmp -s "$TMP/i_good.txt" "$TMP/i_none.txt" \
   && cmp -s "$TMP/i_good.txt" "$TMP/i_stale.txt" \
   && cmp -s "$TMP/i_good.txt" "$TMP/i_trunc.txt" \
   && cmp -s "$TMP/t_good.txt" "$TMP/t_none.txt" \
   && [[ $rc_stale -eq 0 && $rc_trunc -eq 0 ]]; then
    ok "T41c good/missing/stale/truncated index all give identical output and none fails / 索引正確、不存在、過期、截斷四種情況輸出相同且都不失敗"
else
    bad "T41c index degradation (stale rc=$rc_stale, truncated rc=$rc_trunc)"
fi
if [[ -s "$TMP/i_good.txt" ]]; then
    ok "T41d the comparison was not vacuous — the selection returned records / 比對不是空的：選取確實有回傳紀錄"
else
    bad "T41d the -mid selection returned nothing, so T41c compared empty files / -mid 沒有回傳任何東西，T41c 比的是空檔案"
fi
cp "$TMP/good.index" "$TMP/ix.csv2.index"

# T42 — the acceptance condition for going multi-core. The chunk size is
# turned down so the file yields many chunks: a run that produces ONE chunk
# exercises no boundary and would pass on an implementation with no chunking
# logic at all.
# The core count is read from csv2's own -debug line, not from `getconf`:
# busybox does not provide _NPROCESSORS_ONLN, which turned this case into a
# SKIP inside the guest -- on the platform whose DIFFERENT core count is
# precisely what the case exists to exercise. csv2 reports the worker count it
# actually used, which is the number that matters anyway.
# 核心數取自 csv2 自己的 -debug 輸出，而非 `getconf`：busybox 不提供
# _NPROCESSORS_ONLN，那讓這個案例在 guest 內變成 SKIP——而 guest 那個「不同的
# 核心數」正是本案例存在要測的東西。csv2 回報的是它實際使用的工作者數，那本來
# 就是真正要緊的數字。
CSV2_PARALLEL_MIN_BYTES=999999999 "$CSV2" -contains "comma 42" -i "$TMP/ix.csv2" \
    > "$TMP/p_single.txt" 2>/dev/null
CSV2_PARALLEL_MIN_BYTES=1000 CSV2_PARALLEL_CHUNK_BYTES=8192 "$CSV2" -contains "comma 42" \
    -i "$TMP/ix.csv2" -debug > "$TMP/p_multi.txt" 2>"$TMP/p_dbg.txt"
chunks=$(grep -o 'parallel: [0-9]* chunks' "$TMP/p_dbg.txt" | head -1 | awk '{print $2}')
workers=$(grep -o '[0-9]* workers' "$TMP/p_dbg.txt" | head -1 | awk '{print $1}')
if [[ -z "$workers" || "$workers" -lt 2 ]]; then
    # Genuinely one core: the parallel path cannot engage, so single and
    # "parallel" are the same code and comparing them proves nothing. Assert
    # what IS true there -- that asking for it still produces correct output.
    # 真的只有一個核心：平行路徑不會啟用，單執行緒與「平行」是同一段程式碼，比對
    # 它們什麼也證明不了。改為斷言在那裡確實成立的事——要求平行仍產生正確的輸出。
    if cmp -s "$TMP/p_single.txt" "$TMP/p_multi.txt" && [[ -s "$TMP/p_single.txt" ]]; then
        ok "T42 single core (${workers:-1} worker): output still correct / 單核（${workers:-1} 個工作者）：輸出仍正確"
    else
        bad "T42 single core output differs / 單核輸出不一致"
    fi
elif [[ -n "$chunks" && "$chunks" -gt 1 ]] && cmp -s "$TMP/p_single.txt" "$TMP/p_multi.txt" \
   && [[ -s "$TMP/p_single.txt" ]]; then
    ok "T42 parallel ($chunks chunks, $workers workers) and single-threaded output are byte-identical / 平行（$chunks 區塊、$workers 工作者）與單執行緒輸出逐位元相同"
else
    bad "T42 parallel vs single (chunks=${chunks:-none}, workers=${workers:-none}, single=$(wc -l < "$TMP/p_single.txt") lines)"
fi

# T43 — the whole point of the fast path: bytes written must not depend on
# how big the file already is. Measured in bytes via -log, not in seconds.
mk_big() { # path records
    { head -1 "$PKG"; } > "$1"
    local i=0
    while (( i < $2 )); do print -r -- "row$i,v,s,src,purpose,note,MIT" >> "$1"; ((i++)); done
}
mk_big "$TMP/small.csv" 50
mk_big "$TMP/big.csv" 40000
"$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i "$TMP/small.csv" --in-place -log "$TMP/a1.log" 2>/dev/null
"$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i "$TMP/big.csv"   --in-place -log "$TMP/a2.log" 2>/dev/null
w1=$(grep -o 'wrote [0-9]* bytes' "$TMP/a1.log" | tail -1 | awk '{print $2}')
w2=$(grep -o 'wrote [0-9]* bytes' "$TMP/a2.log" | tail -1 | awk '{print $2}')
s1=$(wc -c < "$TMP/small.csv" | tr -d ' ')
s2=$(wc -c < "$TMP/big.csv" | tr -d ' ')
if [[ -n "$w1" && "$w1" == "$w2" && "$s2" -gt $(( s1 * 10 )) ]]; then
    ok "T43 -append writes the same bytes regardless of file size ($w1 B into $s1 B and into $s2 B) / 追加的寫入量與檔案大小無關"
else
    bad "T43 append bytes (small=$w1 into $s1, big=$w2 into $s2)"
fi

# T44 — a .csv with no trailing newline must become TWO records, not one
# record glued onto the tail of the last.
cp "$TMP/nonl2.csv" "$TMP/t44.csv"
"$CSV2" -append 'p,q' -i "$TMP/t44.csv" --in-place 2>/dev/null
n=$("$CSV2" -r -i "$TMP/t44.csv" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "2" "T44 appending to a file with no trailing newline gives 2 records / 未以換行結尾者追加後為 2 筆"

# T45 — .csv2 promises an LF-terminated line per record, so a missing final
# LF is evidence of a torn write. Report it; never drop a record silently.
printf 'k,v\n鍵,值\na,1\nb,2\nc,' > "$TMP/torn.csv2"
assert_fails "T45a a torn .csv2 append is detected on read / 撕裂的追加在讀取時被偵測" -- \
    "$CSV2" -r -i "$TMP/torn.csv2" -so
assert_succeeds "T45b --truncate-partial makes dropping it explicit / --truncate-partial 讓丟棄成為明示" -- \
    "$CSV2" -r --truncate-partial -i "$TMP/torn.csv2" -so

# T46 — four combinations: before and after an append, each read with and
# without the index. The append fast path updates the index in O(1); if it
# instead let the index go stale, this is where that shows up.
# T46 —— 四種組合：追加前後，各自以有索引與無索引讀取。追加快路徑以 O(1) 更新
# 索引；若它反而讓索引過期，就會在這裡現形。
cp "$TMP/good.index" "$TMP/ix.csv2.index"
"$CSV2" -tail 2 -i "$TMP/ix.csv2" > "$TMP/b_idx.txt" 2>/dev/null
"$CSV2" -tail 2 --no-index -i "$TMP/ix.csv2" > "$TMP/b_noidx.txt" 2>/dev/null
"$CSV2" -append 'zz,last,"note, appended"' -i "$TMP/ix.csv2" --in-place 2>/dev/null
"$CSV2" -tail 2 -i "$TMP/ix.csv2" > "$TMP/a_idx.txt" 2>/dev/null
"$CSV2" -tail 2 --no-index -i "$TMP/ix.csv2" > "$TMP/a_noidx.txt" 2>/dev/null
if cmp -s "$TMP/b_idx.txt" "$TMP/b_noidx.txt" && cmp -s "$TMP/a_idx.txt" "$TMP/a_noidx.txt" \
   && ! cmp -s "$TMP/b_idx.txt" "$TMP/a_idx.txt"; then
    ok "T46a index and no-index agree both before and after an append / 追加前後，有索引與無索引的結果一致"
else
    bad "T46a index after append (before: $(cat "$TMP/b_idx.txt" | tr '\n' '|'), after: $(cat "$TMP/a_idx.txt" | tr '\n' '|'))"
fi
assert_succeeds "T46b --verify-index still passes after the append / 追加後 --verify-index 仍通過" -- \
    "$CSV2" --verify-index -i "$TMP/ix.csv2"
unset CSV2_INDEX_MIN_BYTES

echo
echo "--- Addressing, width and diagnostics / 定位、寬度與診斷 ---"

# T48 — the UAX #11 width table, pinned against the numbers the plan MEASURED.
#
# --pretty pads each cell to the column width, so the padding IS the measured
# width, read off without needing a width oracle of our own. zsh's ${(m)#s}
# cannot serve as that oracle: it sums the scalars of a ZWJ sequence and calls
# the family emoji 8, which is the very mistake this table exists to avoid.
# T48 —— UAX #11 寬度表，以計畫「實測」的數字釘住。
# --pretty 會把每個儲存格補到欄寬，因此補了幾格就是量到的寬度，不需要我們自己的
# 寬度判準。zsh 的 ${(m)#s} 不能當那個判準：它會把 ZWJ 序列的各 scalar 加總，說
# 家庭 emoji 是 8——而那正是這張表要避免的錯誤。
{
  print -r -- 'w,note'
  print -r -- '寬,註'
  print -r -- 'ok,x'
  printf '\xe5\xa5\x97\xe4\xbb\xb6\xe5\x90\x8d\xe7\xa8\xb1,x\n'
  printf '\xf0\x9f\x98\x80,x\n'
  printf '\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbd,x\n'
  printf '\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7\xe2\x80\x8d\xf0\x9f\x91\xa6,x\n'
  printf '\xf0\x9f\x87\xb9\xf0\x9f\x87\xbc,x\n'
  printf '1\xef\xb8\x8f\xe2\x83\xa3,x\n'
} > "$TMP/w.csv2"
"$CSV2" -r -t -md --pretty -i "$TMP/w.csv2" > "$TMP/w.md" 2>/dev/null
# trailing-space count of the first cell on a line
pad_of() { local c=${1#| }; c=${c%% |*}; local t=${c##*[! ]}; print -r -- ${#t} }
typeset -a wpad
while IFS= read -r ln; do
    [[ "$ln" == '|-'* ]] && continue
    wpad+=($(pad_of "$ln"))
done < "$TMP/w.md"
# header + 7 samples; column width is 8, set by 套件名稱.
# widths per the plan: ok 2, 套件名稱 8, and every emoji sample 2.
#
# One assertion PER SAMPLE, not one for the table. These eight used to collapse
# into a single if, so a failure said the table was wrong without saying which
# row -- and the rows fail for different reasons. A ZWJ family summed per scalar
# gives 8; a skin-tone pair summed per codepoint gives 4; a flag counted as
# clusters gives 1. Told which row moved, you know which of those it is; told
# only "the table is wrong", you start over.
#
# 一個樣本一個斷言，而不是整張表一個。這八個原本擠在同一個 if 裡，於是失敗時只說「表錯了」
# 卻不說是哪一列——而各列失敗的原因並不相同：ZWJ 家庭以 scalar 加總會得到 8、膚色配對以
# 碼位加總會得到 4、旗幟以 cluster 計數會得到 1。知道是哪一列動了，就知道是其中哪一種；
# 只被告知「表錯了」，就得從頭查起。
typeset -a wname wwant
wname=('header 寬' 'ok' '套件名稱' '😀' '👍🏽 skin-tone (2 codepoints, 1 cluster)' \
       '👨‍👩‍👧‍👦 ZWJ family (7 scalars, 1 cluster)' '🇹🇼 flag (2 scalars, 1 cluster)' \
       '1️⃣ keycap (3 scalars, 1 cluster)')
wwant=(6 6 0 6 6 6 6 6)
if (( ${#wpad} != 8 )); then
    bad "T48 expected 8 rows of padding, got ${#wpad}: $wpad / 預期 8 列的補白，實得 ${#wpad}"
else
    for i in {2..8}; do
        if (( wpad[i] == wwant[i] )); then
            ok "T48/$i ${wname[i]} pads $wpad[i], so it measures $(( 8 - wpad[i] )) columns / 補白 $wpad[i]，即量得 $(( 8 - wpad[i] )) 欄"
        else
            bad "T48/$i ${wname[i]} padded $wpad[i], want $wwant[i] (measured $(( 8 - wpad[i] )) columns, want $(( 8 - wwant[i] ))) / 補白 $wpad[i]，預期 $wwant[i]"
        fi
    done
fi

# T49 — the locating report's optional address parts.
#
# The plan specifies `12:6@L34` for --physical and says --a1 is offered as an
# ADDITIONAL output, never the default, because CSV need not have a header and
# its column count need not be constant. It does not specify the shape of the
# A1 part; that is fixed here and in the plan as ` [F12]` appended.
# T49 —— 定位報告的選用位址部分。
# 計畫規定了 --physical 的 `12:6@L34`，並說明 --a1 是「額外輸出」、絕不作為預設
# （因為 CSV 未必有標頭、欄數也未必一致）。計畫沒有規定 A1 那一段的形狀；此處與
# 計畫一併訂為在其後附加 ` [F12]`。
# The A1 ROW is the physical line, not the record number. Record 1 of a
# one-header-row CSV sits on physical line 2, and every spreadsheet calls that
# cell A2. This case asserted [A1] until 2026-08-18, which pinned a wrong
# answer: it also meant a header printed [E0], and A1 notation has no row 0.
# A1 的「列」取物理行號，不是紀錄號。一列標頭的 CSV，其第 1 筆位於實體第 2 行，
# 任何試算表都會叫那一格 A2。本案例在 2026-08-18 之前斷言的是 [A1]，那釘住了一個
# 錯誤答案：它同時意味著標頭會印出 [E0]，而 A1 記法沒有第 0 列。
addr=$("$CSV2" -contains busybox --physical --a1 -i "$PKG" 2>/dev/null | head -1 | cut -f1)
assert_eq "$addr" "1:1@L2 [A2]" "T49a --a1 uses the physical line as the spreadsheet row / --a1 以物理行號作為試算表列號"

plain=$("$CSV2" -contains busybox -i "$PKG" 2>/dev/null | head -1 | cut -f1)
assert_eq "$plain" "1:1" "T49b neither is on by default / 兩者預設都不啟用"

# Past column Z the notation becomes AA, AB. Nothing had ever run that code:
# the widest fixture here has 10 columns.
# 超過 Z 之後記法會變成 AA、AB。那段程式碼從來沒有被跑過：此處最寬的素材只有 10 欄。
{
  hdr=""; zh=""; row=""
  for i in {1..30}; do
    hdr+="c$i,"; zh+="欄$i,"; row+="v$i,"
  done
  print -r -- "${hdr%,}"
  print -r -- "${zh%,}"
  print -r -- "${row%,}"
} > "$TMP/wide.csv2"
a27=$("$CSV2" -contains v27 --a1 -i "$TMP/wide.csv2" 2>/dev/null | head -1 | cut -f1)
a28=$("$CSV2" -contains v28 --a1 -i "$TMP/wide.csv2" 2>/dev/null | head -1 | cut -f1)
a26=$("$CSV2" -contains v26 --a1 -i "$TMP/wide.csv2" 2>/dev/null | head -1 | cut -f1)
# Two header rows here, so record 1 is on physical line 3 -> row 3.
# 此處有兩列標頭，因此第 1 筆位於實體第 3 行 → 第 3 列。
if [[ "$a26" == "1:26 [Z3]" && "$a27" == "1:27 [AA3]" && "$a28" == "1:28 [AB3]" ]]; then
    ok "T49c A1 notation past column Z gives Z, AA, AB / A1 記法在 Z 之後給出 Z、AA、AB"
else
    bad "T49c A1 past Z (got 26=$a26 27=$a27 28=$a28)"
fi

# T52 — every refusal the README lists must actually refuse, and the tool must
# exit non-zero without leaving output behind. Two of the twelve had no test:
# an unknown flag, and -head with -tail. Documenting a refusal that does not
# happen is worse than not documenting it, because a reader will rely on it.
# T52 —— README 列出的每一條「拒絕」都必須真的拒絕，且必須以非零結束、不留下輸出。
# 十二條中有兩條原本沒有測試：未知旗標，以及 -head 與 -tail 併用。記載一條「其實不會
# 發生」的拒絕，比不記載更糟，因為讀者會依賴它。
assert_fails "T52a an unknown flag is refused, never swallowed / 未知旗標被拒，絕不被吞掉" -- \
    "$CSV2" --nonesuch -i "$PKG" -so
assert_fails "T52b -head with -tail is refused / -head 與 -tail 併用被拒" -- \
    "$CSV2" -head 3 -tail 3 -i "$PKG" -so

# The claim that a failed run leaves nothing behind is what makes -o safe to
# point at a real file. Asserted rather than assumed.
# 「失敗的執行不留下任何東西」這項宣稱，正是讓 -o 可以指向真實檔案的依據。要斷言，
# 不要假設。
rm -f "$TMP/t52.csv"
"$CSV2" -update '99:3' 'x' -i "$PKG" -o "$TMP/t52.csv" 2>/dev/null
if [[ ! -e "$TMP/t52.csv" ]]; then
    ok "T52c a failed run leaves no output file at all / 失敗的執行完全不留下輸出檔"
else
    bad "T52c a failed run left $TMP/t52.csv behind / 失敗的執行留下了輸出檔"
fi

# T53 — the locating report must survive the values it reports.
#
# The report is TAB-separated, one line per matching cell, and a value is
# arbitrary CSV content. Before this case existed, three matching cells whose
# values contained a TAB and a newline produced FOUR lines, `cut -f1` returned
# a fragment of prose where an address belongs, and csv2 exited 0. Found by a
# fresh agent given only the README, not by these tests -- every case here fed
# the report values that happened to contain neither character.
# T53 —— 定位報告必須撐得住它所回報的值。
# 報告以 TAB 分隔、每個命中的儲存格一行，而「值」是任意的 CSV 內容。在這個案例存在
# 之前，三個值含 TAB 與換行的命中儲存格產生了「四」行，`cut -f1` 在該是位址的地方
# 回傳一段散文，而 csv2 以 0 結束。這是一個「只讀 README」的全新 agent 發現的，不是
# 這份測試——此處每一個案例餵給報告的值，恰好都不含那兩個字元。
printf 'k,v\n' > "$TMP/t53.csv"
printf 'r1,"a|b needle"\n' >> "$TMP/t53.csv"
printf 'r2,"x\ty needle"\n' >> "$TMP/t53.csv"
printf 'r3,"line1\nline2 needle"\n' >> "$TMP/t53.csv"

lines=$("$CSV2" -contains needle -i "$TMP/t53.csv" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$lines" "3" "T53a three matching cells give three lines, whatever they contain / 三個命中的儲存格就是三行，不論內容為何"

# Every first field must be an address. A value leaking into column 1 is the
# failure that makes a downstream script read prose as a record number.
# 每一行的第一欄都必須是位址。值溢出到第 1 欄，正是讓下游腳本把散文讀成紀錄號的那個失敗。
bad_addr=$("$CSV2" -contains needle -i "$TMP/t53.csv" 2>/dev/null | cut -f1 | grep -cv '^[0-9]*:[0-9]*$' || true)
assert_eq "$bad_addr" "0" "T53b every first field is an address, never a fragment of a value / 第一欄一律是位址，絕不是值的碎片"

# The value is escaped with the same backslash convention .csv2 uses, plus \t,
# so cut -f3 yields the whole cell on one line and it is unambiguous.
# 值以 .csv2 既有的反斜線慣例加 \t 跳脫，因此 cut -f3 會在一行內取得完整的儲存格，
# 且沒有歧義。
v2=$("$CSV2" -contains needle -i "$TMP/t53.csv" 2>/dev/null | sed -n 2p | cut -f3)
v3=$("$CSV2" -contains needle -i "$TMP/t53.csv" 2>/dev/null | sed -n 3p | cut -f3)
if [[ "$v2" == 'x\ty needle' && "$v3" == 'line1\nline2 needle' ]]; then
    ok "T53c TAB and newline are escaped, so cut -f3 gets the whole cell / TAB 與換行被跳脫，cut -f3 取得完整儲存格"
else
    bad "T53c report escaping (f3 line2='$v2' line3='$v3')"
fi

# T54 — a failure prints exactly two lines, English then Chinese. It used to
# print three: ERROR is above the default WARN threshold, so routing the fatal
# error through the logger echoed it again with a timestamp even when no -log
# was asked for, and a script capturing stderr got it twice.
# T54 —— 失敗恰好印兩行，英文一行、中文一行。它原本印三行：ERROR 高於預設的 WARN
# 門檻，因此把致命錯誤送進 logger 會帶著時間戳再印一次——即使根本沒有要求 -log——
# 捕捉 stderr 的腳本會拿到重複的訊息。
n=$("$CSV2" --nonesuch -i "$PKG" 2>&1 >/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "2" "T54a a failure prints exactly two stderr lines, not a duplicated third / 失敗恰好印兩行，沒有重複的第三行"
# A RUNTIME error, not an argument error. An unknown flag is thrown while the
# arguments are still being parsed, so the -log path -- which comes from those
# same arguments -- has not been read yet and no file is open. That is correct,
# and the first version of this case asserted the opposite.
# 這裡用的是「執行期」錯誤而非參數錯誤。未知旗標是在參數還在解析時就丟出的，
# 而 -log 的路徑正來自同一批參數、當時還沒被讀到，檔案根本還沒開。那是正確行為，
# 而本案例的第一版斷言了相反的事。
rm -f "$TMP/t54.log"
"$CSV2" -update '99:3' 'x' -i "$PKG" -o "$TMP/t54.csv" -log "$TMP/t54.log" >/dev/null 2>&1
if [[ -s "$TMP/t54.log" ]] && grep -q 'ERROR' "$TMP/t54.log"; then
    ok "T54b a runtime error still reaches -log, where the record belongs / 執行期錯誤仍會進入 -log，紀錄該在的地方"
else
    bad "T54b the error did not reach the log file / 錯誤沒有進入 log 檔"
fi

n2=$("$CSV2" -update '99:3' 'x' -i "$PKG" -o "$TMP/t54b.csv" 2>&1 >/dev/null | wc -l | tr -d ' ')
assert_eq "$n2" "2" "T54c a runtime failure also prints exactly two lines / 執行期失敗同樣恰好印兩行"

# T55 — masking has to actually mask.
#
# `-hash` alone is unsalted SHA-256: deterministic, which is the point, and
# dictionary-attackable for exactly the same reason. A blind review recovered
# 3 of 21 licences from the hashed file with nothing but an SPDX word list,
# because `license` has a handful of possible values -- and low-cardinality
# columns are precisely the ones people reach for masking on.
# T55 —— 遮蔽必須真的能遮蔽。
# 單獨的 `-hash` 是無鹽的 SHA-256：確定性的（那正是重點），也正因為確定性而可被
# 字典攻擊。一次盲測僅憑一份 SPDX 詞表就從雜湊後的檔案還原了 21 個 license 中的 3 個
# ——因為 `license` 只有少數幾種可能值，而低基數欄位正是人們會拿來遮蔽的那種。
printf 'id,lic\na,MIT\nb,GPL\nc,MIT\n' > "$TMP/t55.csv"
head -c 64 /dev/urandom > "$TMP/t55.key"
head -c 64 /dev/urandom > "$TMP/t55b.key"

"$CSV2" -hash lic -i "$TMP/t55.csv" -o "$TMP/t55_plain.csv" -t 2>/dev/null
plain_mit=$(cell "$TMP/t55_plain.csv" 1 2)
# The unkeyed form is plain SHA-256 of the value, and this asserts it IS -- so
# that anyone reading the suite sees the exposure rather than inferring it.
# 無金鑰形式就是該值的純 SHA-256，此處直接斷言「它就是」——讓讀測試的人看見這個
# 暴露面，而不是自己去推論。
# An INDEPENDENT SHA-256, so this assertion means something: computing it with
# csv2 would only prove csv2 agrees with itself. macOS ships `shasum`, the
# guest's busybox ships `sha256sum`, and neither ships both -- so pick whichever
# is present rather than skipping the case on the platform that lacks one.
# 使用「獨立的」SHA-256，這個斷言才有意義：用 csv2 自己算只能證明它與自己一致。
# macOS 提供 `shasum`，guest 的 busybox 提供 `sha256sum`，兩邊都不會同時有——
# 因此挑存在的那一個，而不是在缺少其一的平台上把案例略過。
sha256_of() {
    if (( $+commands[sha256sum] )); then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}
want_sha=$(sha256_of 'MIT')
[[ -n "$want_sha" ]] || bad "T55a has no independent SHA-256 tool to check against / 沒有可用的獨立 SHA-256 工具可供比對"
assert_eq "$plain_mit" "$want_sha" "T55a -hash without a key is plain SHA-256 of the value, dictionary-attackable / 無金鑰的 -hash 就是該值的純 SHA-256，可被字典攻擊"

"$CSV2" -hash lic -keyfile "$TMP/t55.key" -i "$TMP/t55.csv" -o "$TMP/t55_keyed.csv" -t 2>/dev/null
keyed_mit=$(cell "$TMP/t55_keyed.csv" 1 2)
if [[ "$keyed_mit" != "$want_sha" && -n "$keyed_mit" ]]; then
    ok "T55b -hash with a key is not the plain SHA-256, so the dictionary does not apply / 有金鑰的 -hash 不是純 SHA-256，字典因此失效"
else
    bad "T55b keyed hash still matches the unkeyed digest / 有金鑰的雜湊仍等於無金鑰的摘要"
fi

# The whole reason to hash rather than encrypt is that equal values stay equal.
# Losing that would make the feature pointless, keyed or not.
# 選擇雜湊而非加密的全部理由，就是相等的值仍然相等。失去它，這個功能不論有沒有金鑰
# 都失去意義。
a=$(cell "$TMP/t55_keyed.csv" 1 2)
c=$(cell "$TMP/t55_keyed.csv" 3 2)
b=$(cell "$TMP/t55_keyed.csv" 2 2)
if [[ "$a" == "$c" && "$a" != "$b" ]]; then
    ok "T55c keyed hashing keeps equal values equal and unequal values unequal / 有金鑰的雜湊：相等仍相等、不等仍不等"
else
    bad "T55c keyed hash equality (a=${a:0:12} b=${b:0:12} c=${c:0:12})"
fi

"$CSV2" -hash lic -keyfile "$TMP/t55b.key" -i "$TMP/t55.csv" -o "$TMP/t55_other.csv" -t 2>/dev/null
if cmp -s "$TMP/t55_keyed.csv" "$TMP/t55_other.csv"; then
    bad "T55d a different key produced identical output / 換一把金鑰卻得到相同輸出"
else
    ok "T55d a different key gives different digests / 換一把金鑰得到不同的摘要"
fi

# The file records WHICH form was used. Without that a reader cannot tell a
# dictionary-attackable column from a protected one.
# 檔案記錄用的是哪一種形式。少了它，讀者分不出「可被字典攻擊的欄位」與「受保護的欄位」。
h_plain=$(header_cell "$TMP/t55_plain.csv" 2)
h_keyed=$(header_cell "$TMP/t55_keyed.csv" 2)
if [[ "$h_plain" == "lic:hash" && "$h_keyed" == lic:hmac:* ]]; then
    ok "T55e the header records which form was used / 標頭記錄了使用的是哪一種形式"
else
    bad "T55e header markers (plain='$h_plain' keyed='$h_keyed')"
fi

# And --json says so too. The JSON keys are the clean names, so without this a
# JSON consumer cannot tell a masked column from a plain one -- which would
# undercut the stated reason the meta line exists.
# --json 也要說明。JSON 的鍵是乾淨的欄名，因此少了這一項，JSON 的消費端分不出被遮蔽
# 的欄位與一般欄位——那會抵銷掉這行 metadata 存在的理由。
m_keyed=$("$CSV2" -head 1 -t --json -i "$TMP/t55_keyed.csv" 2>/dev/null | head -1)
m_clean=$("$CSV2" -head 1 -t --json -i "$PKG" 2>/dev/null | head -1)
if [[ "$m_keyed" == *'"protected":{"lic":"hmac"}'* && "$m_clean" != *protected* ]]; then
    ok "T55f --json meta names the protected columns, and omits the key when there are none / --json 的 metadata 指出受保護的欄位，沒有時則不出現該鍵"
else
    bad "T55f json protected meta (keyed='${m_keyed:0:90}')"
fi

# T56 — the six defects a read_easy pass found on 2026-08-16, every one of
# which happened silently at rc=0. Recorded as cases so they cannot come back;
# the reproductions are in todo/known-defects.md.
# T56 —— 2026-08-16 一次 read_easy 檢視找到的六項缺陷，每一項都在 rc=0 下靜默發生。
# 寫成案例以免它們回來；重現步驟在 todo/known-defects.md。

# 1. The salt and key fingerprint live ONLY in the header marker, and the salt
#    is fresh每run. Emitting ciphertext without its header made data that
#    nobody -- including its author -- could ever decrypt.
# 1. salt 與金鑰指紋只存在於標頭標記中，而 salt 每次執行都重新產生。不帶標頭寫出
#    密文，等於造出「任何人（含作者本人）都永遠解不開」的資料。
printf 'id,lic\na,MIT\nb,GPL\n' > "$TMP/t56.csv"
head -c 64 /dev/urandom > "$TMP/t56.key"
"$CSV2" -encrypt lic -keyfile "$TMP/t56.key" -head 1 -i "$TMP/t56.csv" > "$TMP/t56_enc.csv" 2>/dev/null
if head -1 "$TMP/t56_enc.csv" | grep -q ':enc:'; then
    ok "T56a -encrypt with a selection still writes the header that carries the salt / -encrypt 搭配選取仍會寫出承載 salt 的標頭"
else
    bad "T56a the salt marker is missing; the output is unrecoverable / salt 標記不見了，輸出不可還原"
fi
"$CSV2" -decrypt lic -keyfile "$TMP/t56.key" -i "$TMP/t56_enc.csv" -so > "$TMP/t56_dec.csv" 2>/dev/null
assert_contains "$(cat $TMP/t56_dec.csv)" "MIT" "T56b and the result decrypts back / 而且解得回來"

# 2/3. The suffix DECLARES the format. --headers contradicting it, or an output
#      suffix wanting a different header-row count, used to be accepted and
#      silently shifted the data by a row.
# 2/3. 副檔名「宣告」格式。--headers 與之牴觸、或輸出副檔名要求不同的標頭列數，
#      原本都會被接受，並靜默地把資料錯開一列。
assert_fails "T56c --headers contradicting the suffix is refused / --headers 與副檔名牴觸即拒絕" -- \
    "$CSV2" -r --headers 1 -i "$TMP/idx.csv2" -so
assert_fails "T56d .csv to .csv2 is refused rather than losing a record / .csv 轉 .csv2 即拒絕，而非少一筆" -- \
    "$CSV2" -r -t -i "$PKG" -o "$TMP/t56_conv.csv2"
assert_succeeds "T56e a matching suffix still works / 副檔名相符時照常可用" -- \
    "$CSV2" -r -t -i "$PKG" -o "$TMP/t56_same.csv"

# 4. Ending inside a quoted field means the closing quote never arrived. csv2
#    used to close it itself and emit a record nobody wrote, at rc=0.
# 4. 在引號欄位內結束，代表收尾的引號從未出現。csv2 原本會自己把它收掉，並在 rc=0
#    下吐出一筆沒有人寫過的紀錄。
printf 'a,b\n1,"unterminated\n' > "$TMP/t56_q.csv"
assert_fails "T56f an unterminated quote is an error, not an invented record / 未閉合引號是錯誤，不是憑空造出一筆" -- \
    "$CSV2" -r -t -i "$TMP/t56_q.csv" -so
n=$("$CSV2" -r -t --truncate-partial -i "$TMP/t56_q.csv" -so 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$n" "1" "T56g --truncate-partial actually discards it / --truncate-partial 真的會丟棄它"

# 5. Both header rows reported as `0`, giving two identical lines no reader
#    could tell apart.
# 5. 兩列標頭都回報為 `0`，產生兩行完全相同、讀者無從分辨的輸出。
n=$("$CSV2" -contains 值 --include-headers -i "$TMP/idx.csv2" 2>/dev/null | cut -f1 | grep -c '^0[ab]:' || true)
assert_eq "$n" "1" "T56h header hits are addressed 0a / 0b, not both 0 / 標頭命中以 0a／0b 定址，不是兩個都 0"

# 6. The lighter ones, all silent at rc=0.
# 6. 較輕的幾項，同樣都在 rc=0 下靜默。
if diff -q <("$CSV2" -head 1 -t -md --en -i "$TMP/idx.csv2" 2>/dev/null) \
           <("$CSV2" -head 1 -t -md -i "$TMP/idx.csv2" 2>/dev/null) >/dev/null 2>&1; then
    bad "T56i --en is byte-identical to giving no flag, so it does nothing / --en 與不給旗標逐位元相同，等於什麼都沒做"
else
    ok "T56i --en selects the English title only / --en 只取英文標題"
fi
rm -f "$TMP/t56.log"
"$CSV2" -r -i "$PKG" -log "$TMP/t56.log" >/dev/null 2>&1
if grep -qE 'DEBUG|TRACE' "$TMP/t56.log" 2>/dev/null; then
    bad "T56j the log file holds DEBUG/TRACE without -debug / 未給 -debug，log 檔卻含 DEBUG/TRACE"
else
    ok "T56j the log holds the operation record, not the debugging / log 存的是操作紀錄，不是除錯輸出"
fi
assert_fails "T56k -head -1 is a typo, not a request for nothing / -head -1 是打錯字，不是「請給我空的」" -- \
    "$CSV2" -head -1 -i "$PKG" -so
assert_fails "T56l --physical without a locating report is refused / 沒有定位報告時 --physical 被拒" -- \
    "$CSV2" -head 1 --physical -i "$PKG" -so

# T50 — -debug has five levels in the plan and had one in the CLI. TRACE was
# unreachable, so it is asserted here as reachable AND as not firing without it.
# T50 —— 計畫定義 -debug 有五個層級，CLI 只實作了一個，TRACE 無法達到。此處斷言它
# 可被達到，也斷言未指定時不會出現。
t_on=$("$CSV2" -head 2 -i "$PKG" -debug=trace 2>&1 >/dev/null | grep -c 'TRACE')
t_off=$("$CSV2" -head 2 -i "$PKG" -debug 2>&1 >/dev/null | grep -c 'TRACE')
if [[ "$t_on" -eq 2 && "$t_off" -eq 0 ]]; then
    ok "T50 -debug=trace emits one line per record; plain -debug emits none / -debug=trace 每筆一行，單純的 -debug 不輸出"
else
    bad "T50 trace level (with=$t_on want 2, without=$t_off want 0)"
fi

# T51 — an index used to appear only as a side effect, so a user who only runs
# -mid never got one. --build-index makes it askable, and must not break the
# rule that the index is an optimisation: same output with and without.
# T51 —— 索引原本只以副作用出現，於是只用 -mid 的使用者永遠得不到。--build-index 讓它
# 可被要求，且不得破壞「索引是最佳化」這條規則：有無索引輸出必須相同。
export CSV2_INDEX_MIN_BYTES=1000
cp "$TMP/idx.csv2" "$TMP/bi.csv2"
rm -f "$TMP/bi.csv2.index"
before=$("$CSV2" -mid 1500,1502 -i "$TMP/bi.csv2" 2>/dev/null)
assert_fails "T51a --verify-index fails when there is no index / 沒有索引時 --verify-index 失敗" -- \
    "$CSV2" --verify-index -i "$TMP/bi.csv2"
assert_succeeds "T51b --build-index creates one on demand / --build-index 可依需求建立" -- \
    "$CSV2" --build-index -i "$TMP/bi.csv2"
assert_succeeds "T51c and --verify-index then passes / 之後 --verify-index 通過" -- \
    "$CSV2" --verify-index -i "$TMP/bi.csv2"
after=$("$CSV2" -mid 1500,1502 -i "$TMP/bi.csv2" 2>/dev/null)
if [[ "$before" == "$after" && -n "$before" ]]; then
    ok "T51d building an index does not change the output / 建立索引不改變輸出"
else
    bad "T51d output changed after building an index / 建立索引後輸出改變了"
fi
assert_fails "T51e --build-index with --no-index is refused / --build-index 與 --no-index 併用被拒" -- \
    "$CSV2" --build-index --no-index -i "$TMP/bi.csv2"
unset CSV2_INDEX_MIN_BYTES

# ---------------------------------------------------------------------
# T57 -- deleting a whole column. Open question 5, decided yes on 2026-08-18.
#
# This is the mirror image of the `-insert -cell` refusal: inserting a field
# mid-record shifts every later field one column along, and removing one does
# the same in the other direction. Removing it from every record AND both
# header rows together is the only form of it that keeps alignment, which is
# why it is a whole-file verb and not a cell modifier.
#
# T57 —— 刪除一整欄。待決問題 5，2026-08-18 決定採用。
# 這是 `-insert -cell` 那條拒絕的鏡像：在一列中間插入欄位會讓後面每一欄往後位移一格，
# 移除一欄則在另一個方向上做同樣的事。唯有「每一筆與兩列標頭一起移除」才能保持對齊，
# 這也正是它是一個作用於整檔的動詞、而非儲存格修飾詞的原因。
# ---------------------------------------------------------------------
echo
echo "--- T57: deleting a whole column / 刪除一整欄 ---"

printf 'pkg,version,notes,license\n套件,版本,註記,授權\nbusybox,1.37.0,"fork raliclo/busybox, branch develop",GPL\nzlib,1.3.1,plain,Zlib\n' > "$TMP/dc.csv2"

assert_eq "$("$CSV2" -delete -col 3 -i "$TMP/dc.csv2" -so)" \
'pkg,version,license
套件,版本,授權
busybox,1.37.0,GPL
zlib,1.3.1,Zlib' \
    "T57a -delete -col N removes the column from every record and BOTH header rows / -delete -col N 從每一筆與兩列標頭中移除該欄"

assert_eq "$("$CSV2" -delete -col notes -i "$TMP/dc.csv2" -so)" \
    "$("$CSV2" -delete -col 3 -i "$TMP/dc.csv2" -so)" \
    "T57b by name and by number are the same column / 以名稱與以編號指的是同一欄"

# Two columns at once, addressed against the INPUT. Removing them one at a time
# would make the second index refer to the row as it stands after the first
# removal -- the off-by-one that makes 2 and 4 delete 2 and 5.
# 一次移除兩欄，索引都指向「輸入」。逐一移除會讓第二個索引指向第一次移除之後的那一列
# ——正是那種讓「2 和 4」刪成「2 和 5」的偏移。
assert_eq "$("$CSV2" -delete -col 2 -delete -col license -i "$TMP/dc.csv2" -so | head -2)" \
'pkg,notes
套件,註記' \
    "T57c two columns are resolved against the input, not one after the other / 兩欄都對輸入解析，而非逐一套用"

# The quoted field containing a comma is the one that caused the incident csv2
# was built after. It has to survive being shifted left by a column.
# 那個含逗號的引號欄位，正是引發 csv2 被建立之事故的那一種。它必須能在往左位移一欄之後
# 依然完好。
assert_contains "$("$CSV2" -delete -col 2 -delete -col license -i "$TMP/dc.csv2" -so)" \
    'busybox,"fork raliclo/busybox, branch develop"' \
    "T57d a quoted field containing a comma survives the shift / 含逗號的引號欄位在位移後仍完好"

assert_eq "$("$CSV2" -delete -col b -i "$TMP/dc.csv2" -so 2>&1 >/dev/null | head -1)" \
    'csv2: no column named "b"; the columns are: pkg, version, notes, license' \
    "T57e an unknown column name names the columns that do exist / 未知的欄位名稱會列出實際存在的欄位"

assert_fails "T57f removing every column is refused: a file with no columns is not a CSV file / 移除全部欄位被拒：沒有欄位的檔案不是 CSV 檔" -- \
    "$CSV2" -delete -col 1 -delete -col 2 -delete -col 3 -delete -col 4 -i "$TMP/dc.csv2" -so

# An edit aimed at a column that is being removed does nothing and reports that
# it did -- this project's signature failure. It is refused rather than ordered.
# 針對正被移除之欄位的編輯不會有效果，卻會回報它做了——本專案的招牌失敗。此處是拒絕，
# 而不是替它排出一個順序。
assert_fails "T57g -update on a column being removed is refused / 對正被移除之欄位下 -update 會被拒" -- \
    "$CSV2" -delete -col notes -update 1:notes X -i "$TMP/dc.csv2" -so
assert_fails "T57h -delete -cell on a column being removed is refused / 對正被移除之欄位下 -delete -cell 會被拒" -- \
    "$CSV2" -delete -col notes -delete -cell 1:notes -i "$TMP/dc.csv2" -so
assert_fails "T57i -hash on a column being removed is refused / 對正被移除之欄位下 -hash 會被拒" -- \
    "$CSV2" -delete -col license -hash license -i "$TMP/dc.csv2" -so

assert_fails "T57j -delete -col with -append is refused: the literal row would have to match two shapes / -delete -col 與 -append 併用被拒：那列字面值得同時符合兩種形狀" -- \
    "$CSV2" -delete -col notes -append 'a,b,c,d' -i "$TMP/dc.csv2" -so
assert_fails "T57k -cell and -col together are refused: they are opposites / -cell 與 -col 併用被拒：兩者是相反的" -- \
    "$CSV2" -delete -cell -col 3 -i "$TMP/dc.csv2" -so

# The modifier belongs to ONE verb. Before this was fixed, the second -delete
# inherited -col and removed COLUMN 1 while record 1 survived -- wrong in two
# directions, at rc=0. Asserted in both orders, because a fix that only works
# when the modified verb comes first is not a fix.
# 修飾詞屬於「一個」動詞。在修正之前，第二個 -delete 會繼承 -col 而移除「第 1 欄」，
# 那筆紀錄卻還在——在兩個方向上都錯，且 rc=0。兩種順序都斷言，因為一個只在「帶修飾詞的
# 動詞排前面」時才成立的修正，不算修正。
printf 'a,b,c\n1,2,3\n4,5,6\n' > "$TMP/dc1.csv"
assert_eq "$("$CSV2" -delete -col b -delete 1 -i "$TMP/dc1.csv" -so)" \
'a,c
4,6' \
    "T57l -col does not leak onto the next -delete / -col 不會沾染到下一個 -delete"
assert_eq "$("$CSV2" -delete 1 -delete -col b -i "$TMP/dc1.csv" -so)" \
'a,c
4,6' \
    "T57m and the same holds in the other order / 反過來的順序也一樣"
assert_eq "$("$CSV2" -delete -cell 1:2 -delete 2 -i "$TMP/dc1.csv" -so)" \
'a,b,c
1,,3' \
    "T57n -cell does not leak either: cell 1:2 is blanked and record 2 is deleted / -cell 同樣不會沾染：1:2 被清空、第 2 筆被刪除"
assert_fails "T57o -insert -cell is still refused after the modifier became per-verb / 修飾詞改為逐動詞之後，-insert -cell 仍被拒" -- \
    "$CSV2" -insert -cell 1 'x,y,z' -i "$TMP/dc1.csv" -so

# Single-row .csv has one header row to narrow, not two. The verb has to read
# the format rather than assume the file it was designed against.
# 單列標頭的 .csv 只有一列標頭要收窄，不是兩列。這個動詞必須依格式行事，而不是假設
# 它當初是對著哪一種檔案設計的。
assert_eq "$("$CSV2" -delete -col b -i "$TMP/dc1.csv" -so)" \
'a,c
1,3
4,6' \
    "T57p .csv narrows its single header row / .csv 收窄它那一列標頭"

cp "$TMP/dc.csv2" "$TMP/dc_ip.csv2"
assert_succeeds "T57q --in-place removes the column in the file itself / --in-place 直接在檔案本身移除該欄" -- \
    "$CSV2" -delete -col license -i "$TMP/dc_ip.csv2" --in-place
assert_eq "$(head -1 "$TMP/dc_ip.csv2")" 'pkg,version,notes' \
    "T57r and the file on disk is the narrowed one / 而磁碟上的檔案就是收窄後的那一份"

# A record whose field count disagrees with the header is still an error. The
# new verb must not become a way to reshape a file that was already malformed.
# 欄數與標頭不符的紀錄仍然是錯誤。這個新動詞不能變成「把本來就格式錯誤的檔案重塑一遍」
# 的途徑。
printf 'a,b,c\n1,2\n' > "$TMP/dc_rag.csv"
assert_fails "T57s a ragged record is still refused, not narrowed into agreement / 欄數不符的紀錄仍被拒，不會被收窄成剛好相符" -- \
    "$CSV2" -delete -col b -i "$TMP/dc_rag.csv" -so

# ---------------------------------------------------------------------
# T58 -- the README's worked error example is the REAL message.
#
# Found by a README-only reader on 2026-08-18: the console block showed one
# line ending in a full stop, so it read as the complete message. The real
# message has two further sentences and a second line in Chinese -- and the
# README asserts elsewhere that errors are "exactly two lines, English then
# Chinese", so its own example contradicted its own rule.
#
# Nobody would call that dangerous, which is exactly why it needs a test: a
# quoted example drifts silently every time a message is improved, and each
# drift is individually too small to notice. This asserts the README against
# the binary rather than against someone remembering to update it.
#
# T58 —— README 中那個錯誤訊息範例就是「真正的」訊息。
# 2026-08-18 由一位只讀 README 的讀者發現：那段 console 區塊只顯示一行、且以句號結尾，
# 於是讀起來就像是完整的訊息。真正的訊息還有兩句，以及第二行中文——而 README 在別處
# 主張錯誤「恰好兩行，英文在前中文在後」，因此它自己的範例牴觸了它自己的規則。
# 沒有人會覺得那很危險，而那正是它需要一個測試的原因：被引用的範例會在每次改善訊息時
# 靜默地飄移，而每一次飄移單獨看都小到不會被注意。這個案例把 README 對著執行檔斷言，
# 而不是對著「有沒有人記得更新它」。
# ---------------------------------------------------------------------
echo
echo "--- T58: the README's error example is the real message / README 的錯誤範例就是真正的訊息 ---"

printf 'pkg,ver\n套件,版本\nzlib,1.3.2\n' > "$TMP/rm.csv2"
"$CSV2" -r --headers 1 -i "$TMP/rm.csv2" 2> "$TMP/rm_err.txt" > "$TMP/rm_out.txt"
# The fixture name differs from the README's, so compare with it substituted
# back. Comparing anything less than the whole line would let the truncation
# this case exists to catch pass again.
# 這裡的檔名與 README 的不同，因此代換回去再比對。比對「不足一整行」的任何東西，都會讓
# 本案例所要抓的那種截斷再次矇混過關。
# Assert the file exists before grepping it. A missing README makes grep return
# an empty string, and comparing against an empty string is a test that reports
# on nothing -- which is how this case failed in the guest for a reason that had
# nothing to do with the README's contents.
# 先斷言檔案存在再 grep。README 不存在時 grep 會回傳空字串，而拿空字串去比對，是一個
# 什麼都沒有回報的測試——這個案例就是這樣在 guest 內以一個與 README 內容毫無關係的理由失敗的。
if [[ -f "$ROOT/README.md" ]]; then
    ok "T58z the README is present to compare against / 有 README 可供比對"
else
    bad "T58z $ROOT/README.md is missing; T58 cannot compare against a file that is not there / README 不存在，T58 無法對照一個不在的檔案"
fi
readme_en=$(grep -F 'declares 2 header row(s) by its suffix' "$ROOT/README.md" | head -1)
actual_en=$(head -1 "$TMP/rm_err.txt" | sed "s|$TMP/rm.csv2|vs-sqlite.csv2|")
assert_eq "$actual_en" "$readme_en" \
    "T58a the README quotes the English error line in full, not truncated at the first full stop / README 完整引用了英文錯誤行，而非在第一個句號處截斷"

readme_zh=$(grep -F '的副檔名宣告了 2 列標頭' "$ROOT/README.md" | head -1)
actual_zh=$(sed -n 2p "$TMP/rm_err.txt" | sed "s|$TMP/rm.csv2|vs-sqlite.csv2|")
assert_eq "$actual_zh" "$readme_zh" \
    "T58b and the Chinese line too, so the example matches the two-line rule the README states / 中文行也在，使該範例符合 README 自己陳述的兩行規則"

assert_eq "$(wc -l < "$TMP/rm_err.txt" | tr -d ' ')" "2" \
    "T58c the message really is exactly two lines / 該訊息確實恰好兩行"
assert_eq "$(wc -c < "$TMP/rm_out.txt" | tr -d ' ')" "0" \
    "T58d and stdout stays empty, as the README promises for a failed run / 而 stdout 保持為空，正如 README 對失敗執行的承諾"

# ---------------------------------------------------------------------
# T59 -- `-t` gates SELECTIONS, never EDITS.
#
# Found by a README-only reader on 2026-08-18. The README documents that `-t`
# is off by default and that writing headerless rows to a suffixed path is
# refused, and shows `-head 3 -o out.csv2` being refused for exactly that. From
# those two statements the reader concluded -- reasonably -- that editing a
# .csv2 without `-t` would also be refused, and was surprised when it was not.
# The behaviour was right and undocumented, which is the harder kind of gap to
# see from the inside: nothing is broken, so nothing draws attention to it.
#
# The asymmetry is deliberate. A selection produces a FRAGMENT, so whether the
# header goes with it is a question. An edit produces a FILE, so it is not one.
#
# T59 —— `-t` 管的是「選取」，從不管「編輯」。
# 2026-08-18 由一位只讀 README 的讀者發現。README 寫著 `-t` 預設關閉、且把不帶標頭的
# 資料列寫入有副檔名的路徑會被拒，並示範了 `-head 3 -o out.csv2` 正是因此被拒。讀者從
# 這兩句推論——而且推得合理——編輯 `.csv2` 而不給 `-t` 也會被拒，結果並沒有，於是感到意外。
# 行為是對的，只是沒有寫進文件；而那是從內部最難看見的一種缺口：沒有東西壞掉，因此沒有
# 東西會引起注意。
# 這個不對稱是刻意的：選取產生的是「片段」，標頭要不要跟著出去是一個問題；編輯產生的是
# 一個「檔案」，那就不是問題。
# ---------------------------------------------------------------------
echo
echo "--- T59: -t gates selections, never edits / -t 管選取，不管編輯 ---"

printf 'pkg,ver,note\n套件,版本,備註\nzlib,1.3.2,a\nzstd,1.5.6,b\n' > "$TMP/t59.csv2"

assert_fails "T59a a SELECTION into a .csv2 without -t is refused / 未給 -t 的「選取」寫入 .csv2 被拒" -- \
    "$CSV2" -head 1 -i "$TMP/t59.csv2" -o "$TMP/t59_sel.csv2"

assert_succeeds "T59b but an EDIT into a .csv2 without -t is not / 但未給 -t 的「編輯」寫入 .csv2 不會被拒" -- \
    "$CSV2" -update 1:note X -i "$TMP/t59.csv2" -o "$TMP/t59_ed.csv2"
assert_eq "$(head -2 "$TMP/t59_ed.csv2")" \
'pkg,ver,note
套件,版本,備註' \
    "T59c and both header rows are there, which is why it need not be refused / 而且兩列標頭都在，這正是它不必被拒的原因"

# The guarantee is only worth anything if the result reads back as the same
# shape. A file that merely LOOKS like it has headers is what the refusal in
# T59a exists to prevent.
# 這條保證唯有在「讀得回同樣的形狀」時才有價值。一個只是「看起來有標頭」的檔案，
# 正是 T59a 那條拒絕所要防止的東西。
assert_eq "$("$CSV2" -r -i "$TMP/t59_ed.csv2" | wc -l | tr -d ' ')" "2" \
    "T59d the edited file reads back as 2 data records, not 4 / 編輯後的檔案讀回來是 2 筆資料，不是 4 筆"

# -delete -col is the verb that changes the shape, so it is the one where a
# dropped header row would be hardest to notice: the file would still parse.
# -delete -col 是會改變形狀的那個動詞，因此也是「少了一列標頭」最難被察覺的地方：
# 那個檔案仍然解析得過。
assert_succeeds "T59e -delete -col into a .csv2 without -t is not refused either / -delete -col 未給 -t 寫入 .csv2 同樣不被拒" -- \
    "$CSV2" -delete -col ver -i "$TMP/t59.csv2" -o "$TMP/t59_col.csv2"
assert_eq "$(head -2 "$TMP/t59_col.csv2")" \
'pkg,note
套件,備註' \
    "T59f and both header rows were narrowed, not dropped / 兩列標頭都被收窄，而不是被丟掉"

# --in-place has no -o to inspect, and the append fast path does not go through
# the rewriting path at all -- so the guarantee has to be asserted there too.
# --in-place 沒有 -o 可檢查，而追加快路徑根本不走重寫那條路——因此這條保證在那裡也要斷言。
cp "$TMP/t59.csv2" "$TMP/t59_ap.csv2"
assert_succeeds "T59g the -append fast path does not need -t either / -append 快路徑同樣不需要 -t" -- \
    "$CSV2" -append 'x,9,c' -i "$TMP/t59_ap.csv2" --in-place
assert_eq "$(head -2 "$TMP/t59_ap.csv2")" \
'pkg,ver,note
套件,版本,備註' \
    "T59h and it leaves both header rows untouched / 而且兩列標頭原封不動"

# ---------------------------------------------------------------------
# T60 -- an error carries as much location as there IS, and the README says so.
#
# Round 6 of the blind testing passed, but the reader quoted a README sentence
# that turned out to be false: "Errors go to stderr as exactly two lines,
# English then Chinese, and name the record and field." The two-line half is
# true. The location half was an unconditional promise that one error in eight
# keeps -- the message the reader had just received named only `record 3`.
#
# An overclaim like this is worse than saying nothing, because it is exactly
# specific enough to write a script against: `cut` the address out of every
# error and you get a fragment of prose on the majority of them.
#
# T60 —— 錯誤帶的位置資訊「有多少帶多少」，而 README 據實陳述。
# 盲測第 6 回合通過了，但讀者引用的那句 README 後來證實為假：「錯誤訊息走 stderr，
# 恰好兩行，並指出是哪一筆、哪一欄。」兩行那半是真的；位置那半是一個無條件的承諾，
# 而八則錯誤中只有一則守得住——讀者當下收到的那則就只指出了 `record 3`。
# 這種過度宣稱比什麼都不說更糟，因為它「剛好具體到可以拿來寫腳本」：把位址從每則錯誤
# 中 cut 出來，多數情況下你會得到一段散文的碎片。
# ---------------------------------------------------------------------
echo
echo "--- T60: errors name as much location as exists / 錯誤有多少位置就帶多少 ---"

printf 'a,b\nA,B\n1,\\q\n' > "$TMP/t60_cell.csv2"
printf 'a,b,c\n1,2\n' > "$TMP/t60_rec.csv"
printf 'a,b\n1,2\n' > "$TMP/t60_ok.csv"

# At one cell: record AND field, because both are true.
# 錯在某一格：紀錄與欄位都指出，因為兩者都為真。
"$CSV2" -r -i "$TMP/t60_cell.csv2" 2> "$TMP/t60_a.txt" >/dev/null
assert_contains "$(head -1 "$TMP/t60_a.txt")" "record 3, field 2" \
    "T60a a fault at one cell names the record and the field / 錯在某一格時，紀錄與欄位都會指出"

# At one record, but no single field owns it: record only. Naming a field here
# would mean inventing one.
# 錯在某一筆、但不屬於任何單一欄位：只指出紀錄。在此指出欄位等於捏造一個。
"$CSV2" -r -i "$TMP/t60_rec.csv" 2> "$TMP/t60_b.txt" >/dev/null
assert_contains "$(head -1 "$TMP/t60_b.txt")" "record 1 (line 2)" \
    "T60b a fault at one record names the record / 錯在某一筆時會指出該筆"
if grep -q 'field [0-9]' "$TMP/t60_b.txt"; then
    bad "T60c a record-level fault must not invent a field number / 紀錄層級的錯誤不應捏造欄位號"
else
    ok "T60c and does not invent a field number / 且不會捏造欄位號"
fi

# In the arguments: neither, because it is thrown before a record is read.
# 錯在參數：兩者都不指出，因為它在讀到任何一筆之前就被丟出。
"$CSV2" --nope -i "$TMP/t60_ok.csv" 2> "$TMP/t60_c.txt" >/dev/null
if grep -qE 'record [0-9]' "$TMP/t60_c.txt"; then
    bad "T60d an argument error must not name a record / 參數錯誤不應指出紀錄"
else
    ok "T60d an argument error names no record, having read none / 參數錯誤不指出紀錄，因為它一筆都還沒讀"
fi

# Whole-file: neither. There is no record to name.
# 整個檔案層級：兩者都不指出，沒有紀錄可指。
"$CSV2" -r -i "$TMP/t60_nosuch.csv" 2> "$TMP/t60_e.txt" >/dev/null
if grep -qE 'record [0-9]' "$TMP/t60_e.txt"; then
    bad "T60e a whole-file error must not name a record / 檔案層級的錯誤不應指出紀錄"
else
    ok "T60e a whole-file error names no record either / 檔案層級的錯誤同樣不指出紀錄"
fi

# Whatever the category, the two-line rule holds -- that half of the sentence
# was always true and stays asserted.
# 不論屬於哪一類，兩行規則都成立——那半句一直為真，並持續被斷言。
for f in t60_a t60_b t60_c t60_e; do
    n=$(wc -l < "$TMP/$f.txt" | tr -d ' ')
    if [[ "$n" == "2" ]]; then
        ok "T60f/$f exactly two lines / 恰好兩行"
    else
        bad "T60f/$f expected 2 stderr lines, got $n / 預期 2 行，得到 $n 行"
    fi
done

# ---------------------------------------------------------------------
# T61 -- -si/-so really streams, and stdout is buffered in 64 KiB blocks.
#
# Round 9 of the blind testing pointed out that "without buffering the whole
# file" had never been demonstrated -- a pipeline that completes before you can
# watch it proves correctness, not streaming. It is measured here instead:
# the producer emits enough to exceed the buffer, then STALLS, and the test
# asserts output has already arrived while the input is still open.
#
# The complementary half matters just as much. Under 64 KiB nothing appears
# until the run ends, so piping csv2 into something watched live looks like a
# hang. That is worth asserting precisely because it is the behaviour someone
# will otherwise report as a bug.
#
# T61 —— -si/-so 確實是串流的，而 stdout 以 64 KiB 為單位緩衝。
# 盲測第 9 回合指出「不緩衝整個檔案」從未被實際展示過——一條在你來得及觀察之前就跑完的
# 管線，證明的是正確性而不是串流性。這裡改用量的：產生端先送出超過緩衝區的量，然後
# 「停住」，測試斷言在輸入仍開著的時候輸出就已經到了。
# 另一半同樣要緊：不足 64 KiB 時，要到執行結束才會有東西出現，因此把 csv2 接進一個
# 正在被盯著看的東西，看起來就像卡住。正因為那是別人否則會當成 bug 回報的行為，才值得斷言。
# ---------------------------------------------------------------------
echo
echo "--- T61: -si/-so streams, in 64 KiB blocks / -si/-so 是串流的，以 64 KiB 為單位 ---"

# Built by doubling rather than by looping 8192 times: the guest runs this
# suite too, and a zsh loop of that length there is slow enough to matter.
# 以「倍增」而非「迴圈 8192 次」產生：guest 也會跑這份測試，而在那裡跑那麼長的 zsh 迴圈
# 慢到會造成影響。
print -r -- '1,padpadpadpadpadpadpadpadpad' > "$TMP/t61_big"
repeat 13; do
    cat "$TMP/t61_big" "$TMP/t61_big" > "$TMP/t61_big2"
    mv "$TMP/t61_big2" "$TMP/t61_big"
done
big_bytes=$(wc -c < "$TMP/t61_big" | tr -d ' ')

rm -f "$TMP/t61.fifo"; mkfifo "$TMP/t61.fifo"
{ print -r -- 'a,b'; cat "$TMP/t61_big"; sleep 2; print -r -- '9,end' } > "$TMP/t61.fifo" &
"$CSV2" -si --headers 1 -r -so < "$TMP/t61.fifo" > "$TMP/t61.out" 2>/dev/null &
sleep 1
during=$(wc -c < "$TMP/t61.out" | tr -d ' ')
wait
after=$(wc -c < "$TMP/t61.out" | tr -d ' ')

if (( during > 0 && during < after )); then
    ok "T61a output arrives while the input is still open ($during of $after bytes at t=1s, from a ${big_bytes}B stream) / 輸入還開著時輸出就已到達"
else
    bad "T61a expected partial output at t=1s, got $during of $after bytes / 預期 t=1 秒時已有部分輸出，實得 $during／$after"
fi

# Same shape, under the buffer: nothing until close. 2000 records of ~29 bytes
# is ~58 KB, below 64 KiB.
# 同樣的形狀，但在緩衝區以下：直到結束前都沒有東西。2000 筆 × 約 29 位元組約 58 KB，
# 低於 64 KiB。
head -2000 "$TMP/t61_big" > "$TMP/t61_small"
rm -f "$TMP/t61b.fifo"; mkfifo "$TMP/t61b.fifo"
{ print -r -- 'a,b'; cat "$TMP/t61_small"; sleep 2; print -r -- '9,end' } > "$TMP/t61b.fifo" &
"$CSV2" -si --headers 1 -r -so < "$TMP/t61b.fifo" > "$TMP/t61b.out" 2>/dev/null &
sleep 1
small_during=$(wc -c < "$TMP/t61b.out" | tr -d ' ')
wait
assert_eq "$small_during" "0" \
    "T61b and under 64 KiB nothing arrives until the run ends, which is why it can look like a hang / 而不足 64 KiB 時要到執行結束才有東西，這正是它看起來像卡住的原因"

# The point of streaming is that memory does not track input size. T9 asserts
# this for a file; this asserts the pipeline the README's example actually uses.
# 串流的重點是記憶體不隨輸入大小成長。T9 對檔案斷言過這件事，這裡斷言的是 README 範例
# 實際使用的那條管線。
assert_eq "$(cat "$TMP/t61b.out" | wc -l | tr -d ' ')" "2001" \
    "T61c and the streamed output is complete: 2000 records plus the stalled one / 串流輸出是完整的：2000 筆加上停頓後那一筆"

# The worked pipeline example the README now shows has to actually work.
# README 現在展示的那條管線範例，必須真的能跑。
printf 'pkg_name,version\nbusybox,1.37.0\nzlib,1.3.2\n' > "$TMP/t61_pkg.csv"
assert_eq "$(cat "$TMP/t61_pkg.csv" | "$CSV2" -si --headers 1 -contains busybox --filter -so)" \
    'busybox,1.37.0' \
    "T61d -si/-so compose with a search verb, as the README's pipeline example shows / -si/-so 可與搜尋動詞組合，正如 README 的管線範例所示"

# ---------------------------------------------------------------------
# T62 -- the sidecar is named the whole filename plus ".index", and the README
# now says so with a worked example.
#
# Round 10 attacked the "an index is never a precondition" claim with a
# garbage-filled sidecar and could not break it. But the reader had to GUESS the
# sidecar's filename to run the attack at all: the README referred to it only
# abstractly. Someone adding it to .gitignore, or writing a cleanup script, was
# in the same position.
#
# The naming rule matters beyond convenience: appending to the WHOLE filename is
# what keeps foo.csv and foo.csv2 from sharing one sidecar. Replacing the
# extension instead would give both files "foo.index", and the two formats have
# different header counts -- so one file's index would describe the other's
# records, which is precisely the "quickly gives you the wrong data" case the
# README says is worse than no index at all.
#
# T62 —— sidecar 的名稱是「完整檔名加上 .index」，而 README 現在以實例寫出這件事。
# 第 10 回合用一個塞滿垃圾的 sidecar 攻擊「索引絕不是必要條件」這個宣稱，攻不破。但讀者
# 為了發動這個攻擊，必須先「猜」出 sidecar 的檔名：README 只以抽象方式提過它。想把它加進
# .gitignore、或想寫一支清理腳本的人，處境完全相同。
# 這條命名規則的意義不只是方便：附加在「完整檔名」之後，正是 foo.csv 與 foo.csv2 不會共用
# 同一個 sidecar 的原因。若改成替換副檔名，兩者都會是 foo.index，而這兩種格式的標頭列數
# 不同——於是其中一個檔案的索引會描述另一個檔案的紀錄，那正是 README 所說「很快給你錯資料」
# 、比完全沒有索引更糟的那種情況。
# ---------------------------------------------------------------------
echo
echo "--- T62: the sidecar is <filename>.index / sidecar 名稱是「完整檔名.index」 ---"

export CSV2_INDEX_MIN_BYTES=1
printf 'a,b\n1,x\n2,y\n3,z\n' > "$TMP/t62.csv"
printf 'a,b\nA,B\n1,x\n2,y\n3,z\n' > "$TMP/t62.csv2"
"$CSV2" -tail 2 -i "$TMP/t62.csv"  >/dev/null 2>&1
"$CSV2" -tail 2 -i "$TMP/t62.csv2" >/dev/null 2>&1

assert_succeeds "T62a the sidecar for x.csv is x.csv.index, the name the README now shows / x.csv 的 sidecar 就是 x.csv.index，即 README 現在寫出的那個名稱" -- \
    test -f "$TMP/t62.csv.index"
assert_succeeds "T62b and for x.csv2 it is x.csv2.index, so the two never collide / x.csv2 的則是 x.csv2.index，因此兩者永不相撞" -- \
    test -f "$TMP/t62.csv2.index"

# The collision this naming prevents would be silent: one format's index
# describing the other's records, with different header counts.
# 這個命名所防止的相撞會是靜默的：一種格式的索引描述著另一種格式的紀錄，而兩者標頭列數不同。
if [[ -f "$TMP/t62.index" ]]; then
    bad "T62c a shared x.index must not exist; that is the silent collision / 不應出現共用的 x.index，那正是那種靜默相撞"
else
    ok "T62c no shared x.index is produced / 不會產生共用的 x.index"
fi

# And the claim round 10 attacked, asserted rather than assumed: garbage in the
# sidecar changes nothing and is not an error.
# 以及第 10 回合所攻擊的那個宣稱，改為斷言而非假定：sidecar 塞垃圾不改變任何結果，也不是錯誤。
before=$("$CSV2" -tail 2 -i "$TMP/t62.csv" 2>/dev/null)
print -r -- 'GARBAGE NOT AN INDEX AT ALL 12345 !!!!' > "$TMP/t62.csv.index"
after=$("$CSV2" -tail 2 -i "$TMP/t62.csv" 2>"$TMP/t62_err.txt")
rc=$?
assert_eq "$after" "$before" \
    "T62d a garbage sidecar changes nothing / 塞了垃圾的 sidecar 不改變任何結果"
assert_eq "$rc" "0" "T62e and is not an error / 而且不是錯誤"
assert_eq "$(wc -c < "$TMP/t62_err.txt" | tr -d ' ')" "0" \
    "T62f and says nothing on stderr, since a fallback is not news / stderr 也不說話，因為「退回掃描」不是需要通知的事"

# Rewriting an index that ALREADY EXISTS is a different code path from writing
# the first one, and it is the one that broke: it went through
# FileManager.replaceItemAt, which fails on Linux. Nothing produced wrong data
# -- a stale index is discarded in favour of a scan -- so the only visible
# symptoms were a warning on stderr and an optimisation that silently never
# worked again after its first write. Assert the replacement actually happens,
# not merely that it is quiet about not happening.
# 改寫一個「已經存在」的索引，和寫出第一個索引走的是不同的程式路徑，而壞掉的正是前者：
# 它走的是 FileManager.replaceItemAt，在 Linux 上會失敗。沒有任何東西產生錯誤資料——過期
# 的索引會被丟棄改用掃描——因此唯一看得見的症狀，是 stderr 上的一則警告，以及一項在第一次
# 寫出之後就再也沒有生效的最佳化。這裡斷言「替換真的發生了」，而不只是「它安靜地沒發生」。
rm -f "$TMP/t62.csv.index"
"$CSV2" -tail 2 -i "$TMP/t62.csv" >/dev/null 2>&1
assert_succeeds "T62g the first index is written / 第一個索引寫出成功" -- \
    "$CSV2" --verify-index -i "$TMP/t62.csv"

print -r -- '4,w' >> "$TMP/t62.csv"
"$CSV2" -tail 2 -i "$TMP/t62.csv" >/dev/null 2>"$TMP/t62_rw.txt"
assert_succeeds "T62h and a SECOND write replaces it, so the index is not left stale / 第二次寫出會替換它，索引不會停在過期狀態" -- \
    "$CSV2" --verify-index -i "$TMP/t62.csv"
assert_eq "$(wc -c < "$TMP/t62_rw.txt" | tr -d ' ')" "0" \
    "T62i and replacing an index says nothing on stderr either / 替換索引時 stderr 同樣不說話"

unset CSV2_INDEX_MIN_BYTES

# ---------------------------------------------------------------------
# T63 -- with context on, --json says which record matched.
#
# Round 13 of the blind testing. -A/-B/-C imply --filter, and the reader
# noticed that the emitted stream is then a MIXTURE of matches and context with
# nothing separating them. grep distinguishes the two; the README says "as in
# grep" right next to the context flags, which invited exactly that expectation.
#
# The CSV output genuinely cannot mark them -- a marker in a CSV row is a field,
# and a row with an extra field is a broken record, so the tool would be
# corrupting its own format to be helpful. That half is documented instead.
# --json has no such constraint and now carries "match":true|false, but ONLY
# when context is on: without it every emitted record matched, so the key would
# be a constant on every line and a change to an output already documented and
# tested.
#
# T63 —— 有上下文時，--json 會說出是哪一筆命中。
# 盲測第 13 回合。-A/-B/-C 隱含 --filter，而讀者注意到送出的串流因此是命中與上下文的
# 「混合」，兩者之間沒有任何區別。grep 會區分這兩者；而 README 就在上下文旗標旁邊寫著
# 「和 grep 一樣」，正好招致了那個期待。
# CSV 輸出確實無法標記——在 CSV 列裡加標記就等於多一個欄位，而多一欄的列是壞掉的紀錄，
# 工具會為了幫忙而破壞自己的格式。那一半改以文件說明。--json 沒有這個限制，現在會帶
# "match":true|false，但「只在有上下文時」：否則送出的每一筆都是命中，那個鍵會在每一行
# 都是常數，同時也會更動一份已被記載且被測試的輸出。
# ---------------------------------------------------------------------
echo
echo "--- T63: context marks the match in --json / 有上下文時 --json 標出命中 ---"

printf 'pkg,ver\nbusybox,1\nzlib,2\nzstd,3\nncurses,4\n' > "$TMP/t63.csv"
"$CSV2" -contains zstd -C 1 --json -i "$TMP/t63.csv" > "$TMP/t63.json" 2>/dev/null

assert_eq "$(grep -c '"match":' "$TMP/t63.json" | tr -d ' ')" "3" \
    "T63a every record emitted under context carries a match key / 上下文模式下送出的每一筆都帶 match 鍵"
assert_eq "$(grep -c '"match":true' "$TMP/t63.json" | tr -d ' ')" "1" \
    "T63b exactly one is the match / 恰好一筆是命中"
assert_contains "$(grep '"match":true' "$TMP/t63.json")" '"record":3' \
    "T63c and it is record 3, the one that contains the needle / 而且是第 3 筆，也就是含有該字串的那一筆"
assert_contains "$(grep '"record":2' "$TMP/t63.json")" '"match":false' \
    "T63d the record before it is marked context, not match / 它前面那一筆被標為上下文而非命中"

# The count in the trailing meta is a COUNT. It agreeing with the number of
# marked matches is what makes it readable as anything at all.
# 末行 meta 裡的是「計數」。它與被標記為命中的筆數相符，才使它讀起來有意義。
assert_contains "$(tail -1 "$TMP/t63.json")" '"matched":1' \
    "T63e and the trailing count agrees with the marks / 末行的計數與標記相符"

# Without context the key must NOT appear: every record emitted is a match, so
# a constant true on every line is noise, and adding it would change output that
# is already documented.
# 沒有上下文時這個鍵不該出現：送出的每一筆都是命中，每行固定 true 是雜訊，而加上它會更動
# 一份已被記載的輸出。
"$CSV2" -contains zstd --filter --json -i "$TMP/t63.csv" > "$TMP/t63b.json" 2>/dev/null
assert_eq "$(grep -c '"match":' "$TMP/t63b.json" | tr -d ' ')" "0" \
    "T63f without context the key is absent, since every record emitted matched / 沒有上下文時該鍵不出現，因為送出的每一筆都是命中"

# And the CSV side stays valid CSV: three records, two fields each, no marker
# smuggled in as a field.
# CSV 那一側仍然是合法的 CSV：三筆、每筆兩欄，沒有任何標記被偷渡成欄位。
"$CSV2" -contains zstd -C 1 -i "$TMP/t63.csv" > "$TMP/t63.csv.out" 2>/dev/null
assert_eq "$(wc -l < "$TMP/t63.csv.out" | tr -d ' ')" "3" \
    "T63g the CSV output is three records / CSV 輸出是三筆紀錄"
# Counted by csv2, not by awk -F, -- the field count of a CSV file is exactly
# the thing a comma split gets wrong, and a test that uses the broken method to
# check the correct one proves nothing on the day it matters. Test scripts are
# the one place in this tree permitted to invoke csv2 for this.
# 由 csv2 來數，而不是 awk -F,——一個 CSV 檔的欄數，正是逗號切割會弄錯的那個東西；用壞掉
# 的方法去檢查正確的方法，在真正出事的那天什麼也證明不了。測試腳本是這棵樹裡唯一被允許
# 為此呼叫 csv2 的地方。
nf=$("$CSV2" -si --headers 1 -r --json < "$TMP/t63.csv.out" 2>/dev/null | head -1 | grep -o '"fields":[0-9]*' | cut -d: -f2)
assert_eq "$nf" "2" \
    "T63h each still has two fields: no marker smuggled in as a field / 每筆仍是兩欄：沒有標記被偷渡成欄位"

# ---------------------------------------------------------------------
# T64 -- the suite's own cell accessor is not decorative.
#
# Twelve places in this file used `cut -d, -fN` on csv2's output. They were
# replaced with cell(), which projects the column with -delete -col and then
# takes the record. This case asserts the replacement was NECESSARY rather than
# tidy: on this project's own fixture, the two disagree.
#
# If they ever agree, the fixture has lost the quoted comma that makes it a
# realistic test of a CSV parser, and several other cases quietly became weaker
# at the same moment. This is the tripwire for that.
#
# T64 —— 這份測試自己的取格存取子不是裝飾。
# 本檔案有十二處對 csv2 的輸出使用 `cut -d, -fN`，已改為 cell()——它以 -delete -col 投影出
# 該欄，再取那一筆。這個案例斷言那次替換是「必要的」而不只是整潔：在本專案自己的 fixture 上，
# 兩者的結果並不相同。
# 若哪天兩者一致了，代表 fixture 已失去那個「引號內的逗號」——而正是它使這份 fixture 成為
# 對 CSV 解析器有意義的測試；在同一刻，另外幾個案例也悄悄變弱了。這個案例就是那條絆線。
# ---------------------------------------------------------------------
echo
echo "--- T64: the cell accessor is necessary / 取格存取子是必要的 ---"

by_csv2=$(cell "$PKG" 1 6)
by_cut=$("$CSV2" -mid 1,1 -i "$PKG" 2>/dev/null | cut -d, -f6)
if [[ "$by_csv2" != "$by_cut" ]]; then
    ok "T64a cut -d, -f6 and csv2 disagree on the fixture, which is why cell() exists / cut -d, -f6 與 csv2 在 fixture 上結果不同，這正是 cell() 存在的理由"
else
    bad "T64a they agree; the fixture has lost its quoted comma and several cases just got weaker / 兩者一致了：fixture 已失去引號內的逗號，數個案例同時變弱"
fi

# And name what the wrong one actually returns, so the failure is legible rather
# than merely unequal: a comma split does not error, it hands back a fragment.
# 並指出「錯的那個」實際回傳了什麼，讓失敗看得懂而不只是「不相等」：逗號切割不會報錯，
# 它會交還一段碎片。
assert_contains "$by_cut" 'CORRECTED' \
    "T64b and the comma split returns a fragment of prose, not an error / 而逗號切割回傳的是一段散文碎片，不是錯誤"
# cell() returns the field as CSV ENCODES it, so a value containing commas
# comes back quoted. That is the honest answer -- the alternative is a decoder
# in the test suite, which would be a second implementation of the thing under
# test. Call sites compare names, base64 and hex digests, none of which quote.
# cell() 回傳的是 CSV「編碼後」的欄位，因此含逗號的值會帶著引號回來。那是誠實的答案——
# 另一個選擇是在測試裡放一個解碼器，而那等於為受測物再寫一份實作。各呼叫點比較的是名稱、
# base64 與十六進位摘要，都不會被加引號。
assert_eq "${by_csv2:0:10}" '"CORRECTED' \
    "T64c while csv2 returns the whole cell, quoted as CSV encodes it / csv2 回傳的則是完整儲存格，並帶著 CSV 的引號"
if (( ${#by_csv2} > ${#by_cut} )); then
    ok "T64d the whole cell is longer than the fragment (${#by_csv2} vs ${#by_cut} bytes) / 完整儲存格比碎片長"
else
    bad "T64d expected the whole cell to be longer than the fragment / 預期完整儲存格比碎片長"
fi

# ---------------------------------------------------------------------
# T65 -- the workaround the README recommends works on the shape it is
#        recommended FOR, and the shape next to it is a trap.
#
# Round 14. The README's advice for getting one value used to read "or
# -contains and take cut -f3", sitting a few lines above a --filter example
# whose output is CSV. `cut -f3` cuts on TAB and is right for the locating
# report; the same reflex applied to the CSV output beside it returns a
# fragment. A reader skimming had no way to see which shape the advice was for.
#
# Both halves are asserted here, because documenting only the safe one leaves
# the trap in place for whoever misreads it next.
#
# T65 —— README 建議的替代作法，在「它所建議的那個形狀」上有效，而旁邊那個形狀是陷阱。
# 第 14 回合。README 取單一值的建議原本寫作「或用 -contains 再 cut -f3」，而它上方幾行就是
# 一個輸出為 CSV 的 --filter 範例。`cut -f3` 切的是 TAB，對定位報告是正確的；同一個反射動作
# 用在旁邊那份 CSV 輸出上，回傳的是一段碎片。只是略讀的人，無從看出那個建議是給哪個形狀的。
# 兩半都在此斷言，因為只記載安全的那一半，等於把陷阱留給下一個讀錯的人。
# ---------------------------------------------------------------------
echo
echo "--- T65: the documented workaround, and the trap beside it / 文件建議的作法，以及它旁邊的陷阱 ---"

want=$(cell "$PKG" 1 6)
# The report route the README recommends: TAB-separated, values escaped.
# README 建議的報告路線：TAB 分隔、值有跳脫。
got=$("$CSV2" -contains 'CORRECTED' -i "$PKG" 2>/dev/null | head -1 | cut -f3)
if [[ -n "$got" && "${#got}" -gt 100 ]]; then
    ok "T65a cut -f3 on the locating report returns a whole cell (${#got} bytes) / 對定位報告下 cut -f3 取得的是完整儲存格"
else
    bad "T65a cut -f3 on the report returned ${#got} bytes: '$got' / 對報告下 cut -f3 只取得 ${#got} 位元組"
fi

# The report escapes, so the value it hands over survives a TAB cut whatever it
# contains -- that is what makes the recommendation safe rather than lucky.
# 報告會跳脫，因此它交出的值不論內容為何都能撐過一次 TAB 切割——正是這一點讓那個建議「安全」
# 而不是「幸運」。
if [[ "$got" != *$'\t'* && "$got" != *$'\n'* ]]; then
    ok "T65b and the report's escaping means that cut cannot be broken by the value / 報告的跳脫使該 cut 不會被值本身弄壞"
else
    bad "T65b the report handed over a raw TAB or newline, which breaks cut -f / 報告交出了原始 TAB 或換行，會弄壞 cut -f"
fi

# The trap: same reflex, CSV output, silent fragment at rc=0.
# 陷阱：同一個反射動作、CSV 輸出、rc=0 下的靜默碎片。
trap_got=$("$CSV2" -contains 'CORRECTED' --filter -i "$PKG" 2>/dev/null | head -1 | cut -d, -f6)
if (( ${#trap_got} < ${#want} )); then
    ok "T65c while cut -d, -f6 on --filter output truncates (${#trap_got} of ${#want} bytes), which is why the README now says not to / 而對 --filter 輸出下 cut -d, -f6 會截斷，這正是 README 現在明說不要這樣做的原因"
else
    bad "T65c expected the comma split to truncate; it returned ${#trap_got} of ${#want} bytes / 預期逗號切割會截斷，實得 ${#trap_got}／${#want}"
fi

# ---------------------------------------------------------------------
# T66 -- --include-headers, and which language names the column.
#
# Round 15 found that --include-headers had exactly one sentence in the README
# and no worked example, unlike every other addressing feature. The reader
# predicted the line format correctly from general principles -- and got the
# subtler part half right: they concluded the name column "always names the EN
# header". It does by default, but it follows --zh, not the matched row.
#
# That distinction is the whole reason 0a and 0b are separate addresses. The
# row that matched and the language the report is written in are two different
# things, and a report that conflated them would make a 0b hit indistinguishable
# from a 0a hit whenever the two titles happened to share a word.
#
# T66 —— --include-headers，以及是「哪一種語言」在為欄位命名。
# 第 15 回合發現 --include-headers 在 README 裡只有一句話、沒有任何實例，與其他每一項定址
# 功能都不同。讀者僅憑通則就正確預測了那一行的格式——但比較細的那一半只對了一半：他們的
# 結論是名稱欄「一律使用英文標頭」。預設時確實如此，但它跟隨的是 --zh，而不是「命中的那一列」。
# 這個區別正是 0a 與 0b 之所以是兩個不同位址的理由。「命中的是哪一列」與「這份報告以哪種
# 語言書寫」是兩件事；若報告把兩者混為一談，只要兩個標題剛好共用一個詞，0b 的命中就會與
# 0a 的命中無法區分。
# ---------------------------------------------------------------------
echo
echo "--- T66: --include-headers and the naming language / --include-headers 與命名語言 ---"

printf 'pkg,ver,note\n套件,版本,備註\nzlib,1.3.2,first\nzstd,1.5.6,second\n' > "$TMP/t66.csv2"

assert_eq "$("$CSV2" -contains note -i "$TMP/t66.csv2" 2>/dev/null)" "" \
    "T66a header text is invisible to search by default / 標頭文字預設對搜尋不可見"
assert_eq "$("$CSV2" -contains note --include-headers -i "$TMP/t66.csv2" 2>/dev/null)" \
    $'0a:3\tnote\tnote' \
    "T66b a hit in the first header row is 0a / 命中第一列標頭時位址是 0a"
assert_eq "$("$CSV2" -contains 備註 --include-headers -i "$TMP/t66.csv2" 2>/dev/null)" \
    $'0b:3\tnote\t備註' \
    "T66c a hit in the second is 0b, and the name column is still EN / 命中第二列時是 0b，而名稱欄仍是英文"
assert_eq "$("$CSV2" -contains 備註 --include-headers --zh -i "$TMP/t66.csv2" 2>/dev/null)" \
    $'0b:3\t備註\t備註' \
    "T66d --zh changes the NAME, not the address / --zh 改變的是名稱，不是位址"

# The name follows the flag rather than the matched row, so a DATA hit is named
# in Chinese under --zh too. Without this the two behaviours could be told apart
# only by reading the code.
# 名稱跟隨旗標而非命中的那一列，因此在 --zh 之下，「資料列」的命中同樣以中文命名。少了這一條，
# 這兩種行為只能靠讀原始碼才分得出來。
assert_eq "$("$CSV2" -contains first --zh -i "$TMP/t66.csv2" 2>/dev/null)" \
    $'1:3\t備註\tfirst' \
    "T66e and a data hit is named in Chinese under --zh as well / 在 --zh 之下，資料列的命中同樣以中文命名"

# ---------------------------------------------------------------------
# T67 -- --a1 counts the header rows, so the same record is a different
#        spreadsheet row in .csv and .csv2.
#
# Round 17 picked --a1 unprompted because it had one line in the README, no
# example, and no statement of how the header count affects the row. That is
# precisely the arithmetic a header-count-aware feature gets wrong: assume one
# header row regardless of format and every .csv2 address is off by one -- and
# still looks like a plausible cell reference, which is why nobody would notice.
#
# The tool was right. It was also undemonstrated, so being right was something a
# reader had to take on faith or rediscover by testing, which is what happened.
#
# T67 —— --a1 會把標頭列算進去，因此同一筆紀錄在 .csv 與 .csv2 中落在不同的試算表列。
# 第 17 回合在無人指定的情況下自己挑了 --a1，因為它在 README 裡只有一行、沒有實例，也沒有
# 說明標頭列數如何影響列號。而那正是「會依標頭列數而變」的功能最容易算錯的地方：若不論格式
# 一律假設一列標頭，那麼每一個 .csv2 的位址都會差一——而且看起來仍然是一個合理的儲存格參照，
# 這正是沒有人會注意到的原因。
# 工具是對的。但它也從未被示範過，於是「它是對的」這件事，讀者只能選擇相信，或自己測出來
# ——而後者正是實際發生的事。
# ---------------------------------------------------------------------
echo
echo "--- T67: --a1 counts the header rows / --a1 會把標頭列算進去 ---"

printf 'pkg,ver\nzlib,1\nzstd,2\n' > "$TMP/t67.csv"
printf 'pkg,ver\n套件,版本\nzlib,1\nzstd,2\n' > "$TMP/t67.csv2"

assert_eq "$("$CSV2" -contains zlib --a1 -i "$TMP/t67.csv" 2>/dev/null)" \
    $'1:1 [A2]\tpkg\tzlib' \
    "T67a in a .csv, data record 1 is spreadsheet row 2 / 在 .csv 中，第 1 筆資料是試算表第 2 列"
assert_eq "$("$CSV2" -contains zlib --a1 -i "$TMP/t67.csv2" 2>/dev/null)" \
    $'1:1 [A3]\tpkg\tzlib' \
    "T67b in a .csv2 it is row 3, because there are two header rows / 在 .csv2 中是第 3 列，因為標頭有兩列"
assert_eq "$("$CSV2" -contains zstd --a1 -i "$TMP/t67.csv2" 2>/dev/null)" \
    $'2:1 [A4]\tpkg\tzstd' \
    "T67c and the offset holds for the next record / 位移對下一筆同樣成立"

# The column letter comes from the field number, so a second-column hit is B --
# checked because a row that is right with a column that is wrong is still a
# wrong cell reference.
# 欄位字母由欄號換算而來，因此命中第二欄就是 B——之所以要查，是因為「列對了但欄錯了」仍然
# 是一個錯的儲存格參照。
assert_eq "$("$CSV2" -contains 1 --a1 -i "$TMP/t67.csv2" 2>/dev/null)" \
    $'1:2 [B3]\tver\t1' \
    "T67d and the column letter follows the field number / 欄位字母跟隨欄號"

# The refusal the reader hit first, which was asserted but never documented.
# 讀者第一次就撞上的那條拒絕——它有被斷言，卻從未被記載。
assert_fails "T67e --a1 without a locating report is refused / 沒有定位報告時 --a1 被拒" -- \
    "$CSV2" -r --a1 -i "$TMP/t67.csv2"
assert_fails "T67f and --a1 with --filter is refused too, for the same reason / 與 --filter 併用同樣被拒，理由相同" -- \
    "$CSV2" -contains zlib --filter --a1 -i "$TMP/t67.csv2"

echo
echo "--- Phase 6: cross-platform / 第 6 階段：跨平台 ---"
# T47 compares TWO platforms, so it cannot run from inside one of them. It is
# driven from the parent project by test_submodules/run_csv2_test.zsh, which
# builds csv2 in the guest and compares 12 invocations sha256 by sha256. This
# line reports where it lives rather than pretending the case does not exist.
# T47 比對的是「兩個平台」，因此無法從其中一個平台內部執行。它由母專案的
# test_submodules/run_csv2_test.zsh 驅動——在 guest 內建置 csv2，並逐一以 sha256
# 比對 12 組呼叫。這一行說明它在哪裡執行，而不是假裝這個案例不存在。
skipt "T47 macOS and aarch64 Linux produce byte-identical output / mac 與 Linux 輸出逐位元相同 (runs from the parent project: test_submodules/run_csv2_test.zsh / 由母專案的 test_submodules/run_csv2_test.zsh 執行)"

echo
echo "====================================================================="
print -r -- "PASS $pass   FAIL $fail   SKIP $skip"
print -r -- "通過 $pass   失敗 $fail   略過 $skip"
echo "log: $LOG"
echo "====================================================================="
(( fail == 0 )) || exit 1
exit 0

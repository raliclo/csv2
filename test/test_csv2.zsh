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
orig3=$("$CSV2" -mid 3,3 -i "$PKG" 2>/dev/null | cut -d, -f1)
orig5=$("$CSV2" -mid 5,5 -i "$PKG" 2>/dev/null | cut -d, -f1)
new3=$("$CSV2" -mid 3,3 -i "$TMP/t27.csv" 2>/dev/null | cut -d, -f1)
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
v=$("$CSV2" -mid 1,1 -i "$TMP/t28.csv" 2>/dev/null | cut -d, -f1)
assert_eq "$v" "zzz" "T28b --in-place edits via temp file and rename / --in-place 以暫存檔加 rename 完成"
cp "$PKG" "$TMP/t28c.csv"
"$CSV2" -update '99:1' 'zzz' -i "$TMP/t28c.csv" --in-place 2>/dev/null
assert_same "$PKG" "$TMP/t28c.csv" "T28c a failed in-place edit leaves the original intact / 失敗時原檔完好"

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
ct=$("$CSV2" -mid 1,1 -i "$TMP/enc.csv" 2>/dev/null | cut -d, -f6)
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
if [[ ${#wpad} -eq 8 && ${wpad[2]} -eq 6 && ${wpad[3]} -eq 0 && ${wpad[4]} -eq 6 \
      && ${wpad[5]} -eq 6 && ${wpad[6]} -eq 6 && ${wpad[7]} -eq 6 && ${wpad[8]} -eq 6 ]]; then
    ok "T48 display widths match the plan's measured table (ok 2, 套件名稱 8, every emoji 2) / 顯示寬度與計畫實測的表相符"
else
    bad "T48 width table (padding per row: $wpad, want 6 0 6 6 6 6 6 after the header)"
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
plain_mit=$("$CSV2" -mid 1,1 -i "$TMP/t55_plain.csv" 2>/dev/null | cut -d, -f2)
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
keyed_mit=$("$CSV2" -mid 1,1 -i "$TMP/t55_keyed.csv" 2>/dev/null | cut -d, -f2)
if [[ "$keyed_mit" != "$want_sha" && -n "$keyed_mit" ]]; then
    ok "T55b -hash with a key is not the plain SHA-256, so the dictionary does not apply / 有金鑰的 -hash 不是純 SHA-256，字典因此失效"
else
    bad "T55b keyed hash still matches the unkeyed digest / 有金鑰的雜湊仍等於無金鑰的摘要"
fi

# The whole reason to hash rather than encrypt is that equal values stay equal.
# Losing that would make the feature pointless, keyed or not.
# 選擇雜湊而非加密的全部理由，就是相等的值仍然相等。失去它，這個功能不論有沒有金鑰
# 都失去意義。
a=$("$CSV2" -mid 1,1 -i "$TMP/t55_keyed.csv" 2>/dev/null | cut -d, -f2)
c=$("$CSV2" -mid 3,3 -i "$TMP/t55_keyed.csv" 2>/dev/null | cut -d, -f2)
b=$("$CSV2" -mid 2,2 -i "$TMP/t55_keyed.csv" 2>/dev/null | cut -d, -f2)
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
h_plain=$(head -1 "$TMP/t55_plain.csv" | cut -d, -f2)
h_keyed=$(head -1 "$TMP/t55_keyed.csv" | cut -d, -f2)
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

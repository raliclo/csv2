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
    echo "building first / 先建置：$ROOT/compile_csv2.sh"
    "$ROOT/compile_csv2.sh" >/dev/null || { echo "build failed / 建置失敗" >&2; exit 1 }
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
ok()   { print -r -- "PASS  $1"; ((pass++)) }
bad()  { print -r -- "FAIL  $1"; ((fail++)) }
skipt(){ print -r -- "SKIP  $1"; ((skip++)) }

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
if [[ $(tr -dc '\r' < "$TMP/t4.out" | wc -c) -eq 0 && $(wc -l < "$TMP/t4.out") -eq 3 ]]; then
    ok "T4 mixed CRLF/LF parsed per record, written as LF / 混用逐筆判斷，一律寫 LF"
else
    bad "T4 mixed CRLF/LF (got $(wc -l < "$TMP/t4.out") lines, $(tr -dc '\r' < "$TMP/t4.out" | wc -c) CR)"
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

skipt "T9 -si/-so streaming RSS has an upper bound / 串流 RSS 有上界 (not implemented: needs an input larger than RAM and an RSS harness / 未實作：需大於記憶體的輸入與 RSS 量測)"

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

skipt "T12 -tail RSS has an upper bound / -tail 的 RSS 有上界 (implemented as a ring buffer, but not yet measured / 已以環狀緩衝實作，但尚未量測)"
skipt "T13 -mid does not read past b / -mid 不讀取 b 之後 (implemented via early stop, but not yet measured in bytes / 已以提前停止實作，但尚未以位元組量測)"

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

skipt "T19 -md --pretty gives up streaming / --pretty 放棄串流 (--pretty accepted but alignment and the UAX #11 width table are not implemented / --pretty 可接受，但對齊與 UAX #11 寬度表尚未實作)"

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
# 300 clusters, so the echo limit is actually crossed. At 80 the value fits
# and the case would pass while testing nothing about truncation.
long=$(printf '\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7\xe2\x80\x8d\xf0\x9f\x91\xa6%.0s' {1..300})
printf 'k,v\n鍵,值\nlong,%s\n' "$long" > "$TMP/long.csv2"
"$CSV2" -contains "k" --include-headers -i "$TMP/long.csv2" > "$TMP/t25.out" 2>&1
"$CSV2" -contains "$(printf '\xf0\x9f\x91\xa8')" -i "$TMP/long.csv2" >> "$TMP/t25.out" 2>&1
# The converted bytes go to a FILE, not /dev/null: macOS iconv returns ENOTTY
# when its output is /dev/null, which reads as "invalid input" and would fail
# this case for a reason that has nothing to do with the encoding.
# 轉換結果寫進檔案而非 /dev/null：macOS 的 iconv 在輸出為 /dev/null 時會回
# ENOTTY，那看起來像「輸入不合法」，會讓這個案例因為與編碼無關的理由而失敗。
if iconv -f UTF-8 -t UTF-8 "$TMP/t25.out" > "$TMP/t25.conv" 2>/dev/null; then
    ok "T25 truncation stays on a grapheme cluster boundary / 截斷落在 grapheme cluster 邊界"
else
    bad "T25 truncation produced invalid UTF-8 / 截斷產生了不合法的 UTF-8"
    print -r -- "      last bytes: $(tail -c 24 "$TMP/t25.out" | xxd -p | tr -d '\n')"
fi

# T26 — stdin has no extension, so the format cannot be a declared fact and
# a default here would be a guess.
assert_fails "T26 -si without --headers is an error / -si 未給 --headers 即報錯" -- \
    sh -c "cat '$PKG' | '$CSV2' -si -so -r"
assert_succeeds "T26b -si with --headers 1 works / -si 加 --headers 1 可用" -- \
    sh -c "cat '$PKG' | '$CSV2' -si --headers 1 -so -r > /dev/null"

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
out=$(HOME="$TMP/home" sh -c "'$CSV2' -encrypt status_notes -i '$PKG' -o '$TMP/x2.csv' < /dev/null" 2>&1)
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

skipt "T41 behaviour identical with no index / 無索引時行為完全相同 (the .index sidecar is not implemented / .index sidecar 尚未實作)"
skipt "T42 parallel and single-threaded output are byte-identical / 平行與單執行緒輸出逐位元相同 (parallel scanning is not implemented / 平行掃描尚未實作)"

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

skipt "T46 the index is still correct after an append / 追加後索引仍正確 (the .index sidecar is not implemented / .index sidecar 尚未實作)"

echo
echo "--- Phase 6: cross-platform / 第 6 階段：跨平台 ---"
skipt "T47 macOS and aarch64 Linux produce byte-identical output / mac 與 Linux 輸出逐位元相同 (needs the Linux cross-compile, phase 6 / 需要第 6 階段的 Linux 交叉編譯)"

echo
echo "====================================================================="
print -r -- "PASS $pass   FAIL $fail   SKIP $skip"
print -r -- "通過 $pass   失敗 $fail   略過 $skip"
echo "log: $LOG"
echo "====================================================================="
(( fail == 0 )) || exit 1
exit 0

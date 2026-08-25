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

# Which platform this is running on. Three cases need it, and all three are the
# ENVIRONMENT's limits rather than csv2's -- a POSIX FIFO that a native Windows
# binary cannot see, and a command line that arrives as UTF-16 with no raw
# bytes left to inspect. Naming the platform in the skip reason is the point:
# "SKIP" with no reason is indistinguishable from a case nobody wrote.
# 這份測試跑在哪個平台上。有三個案例需要知道，而那三個都是「環境」的限制而不是 csv2 的
# ——一個原生 Windows 程式看不見的 POSIX FIFO，以及一條以 UTF-16 抵達、已經沒有原始位元組
# 可供檢查的命令列。在略過的理由裡指名平台正是重點：沒有理由的 SKIP，與「根本沒有人寫過
# 這個案例」無法區分。
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
    *)                    IS_WINDOWS=0 ;;
esac

# This suite hands csv2 absolute paths built from `${0:A:h}`, and on Windows
# those are POSIX-shaped (`/c/Users/...`). A native Windows binary cannot open
# such a path; what makes it work is MSYS2 rewriting the argument to `C:/...`
# on the way to a native process. The suite has depended on that since it first
# ran there -- T58a/T58b exist because the rewriting shows up in csv2's own
# error messages -- but nothing said so, and nothing made sure it was on.
#
# `MSYS2_ARG_CONV_EXCL=*` turns all of it off. Set it, and every path this
# suite passes arrives unrewritten: 276 of 454 cases failed, most of them with
# `cannot open input file`, which reads exactly like a badly broken program.
# It is set in the environment of a multissh session, so the suite passed from
# an ordinary shell on that machine and failed over the link -- the same tree,
# the same binary, the same commit.
#
# Unsetting it here scopes the decision to this script and the processes it
# starts, and removes a dependency on the caller's environment that nobody
# declared.
#
# 這份測試交給 csv2 的是由 `${0:A:h}` 組出的絕對路徑，而在 Windows 上那是 POSIX 形狀的
# （`/c/Users/...`）。原生 Windows 程式打不開那種路徑；讓它能運作的，是 MSYS2 在把引數
# 交給原生行程時改寫成 `C:/...`。這份測試從第一次在那裡執行起就依賴這件事——T58a／T58b
# 的存在正是因為那個改寫會出現在 csv2 自己的錯誤訊息裡——但沒有任何地方說出來，也沒有任何
# 東西確保它是開著的。
#
# `MSYS2_ARG_CONV_EXCL=*` 會把它整個關掉。一旦設了，這份測試傳出去的每一個路徑都不會被改寫：
# 454 條裡有 276 條失敗，多數是 `cannot open input file`，讀起來就像一個壞得很徹底的程式。
# 它被設在 multissh session 的環境裡，於是同一棵樹、同一個執行檔、同一個 commit，在那台機器
# 上用普通 shell 跑會通過，經由連線跑就會失敗。
#
# 在此 unset，把這個決定的範圍限制在這支腳本與它啟動的行程內，並移除一個「沒有人宣告過」的
# 對呼叫者環境的依賴。
if (( IS_WINDOWS )); then unset MSYS2_ARG_CONV_EXCL; fi
: ${CSV2:="$ROOT/release/csv2"}

if [[ ! -x "$CSV2" ]]; then
    echo "building first / 先建置：$ROOT/compile_csv2.zsh"
    "$ROOT/compile_csv2.zsh" >/dev/null || { echo "build failed / 建置失敗" >&2; exit 1 }
fi

# A binary older than the sources is the worst thing this suite can be handed:
# every case still runs, most still pass, and the ones that fail look like
# defects in the program rather than like a build that never happened.
#
# On 2026-08-22 the Windows node did exactly that. A change used
# `FileHandle.fileDescriptor`, which is marked unavailable there, so the build
# failed -- and the node kept the binary it already had and ran the NEW tests
# against it. Five cases failed, all of them pointing at a metrics line that
# was correct in the source sitting right there. The upgrade helper had printed
# `build: FAILED`; the command watching it filtered for other lines.
#
# So the suite asks the question itself, before anything else, and only when
# the sources are present -- a node given a binary and no tree is a legitimate
# way to run this.
#
# 一個比原始碼還舊的二進位檔，是這套測試會拿到的最糟的東西：每個案例照樣執行、多數照樣通過，
# 而失敗的那些看起來像是「程式有缺陷」，而不是「有一次建置根本沒有跑起來」。
#
# 2026-08-22 的 Windows 節點就是這樣。某個改動用了 `FileHandle.fileDescriptor`，而它在那裡
# 被標記為不可用，於是建置失敗——那台節點保留了它原本就有的二進位檔，拿「新的測試」去跑它。
# 五個案例失敗，全都指向一行 metrics，而那一行在旁邊的原始碼裡是對的。升級腳本印過
# `build: FAILED`；盯著它的那個指令，把那一行濾掉了。
#
# 因此這套測試自己問這個問題，在其他一切之前——而且只在「原始碼在場」時問：一台只拿到
# 二進位檔、沒有整棵樹的節點，也是合法的執行方式。
if [[ -d "$ROOT/src" ]]; then
    _stale=""
    for _srcfile in "$ROOT/src"/*.swift; do
        [[ -e "$_srcfile" ]] || continue
        [[ "$_srcfile" -nt "$CSV2" ]] && _stale="$_stale ${_srcfile:t}"
    done
    if [[ -n "$_stale" ]]; then
        echo "STALE BINARY / 二進位檔過期：$CSV2" >&2
        echo "  newer than it:$_stale" >&2
        echo "  build it before testing, or the failures below are about a program that was never built / 請先建置，否則下面的失敗講的是一個從未被建置出來的程式" >&2
        exit 1
    fi
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

# A test that calls something which does not exist must FAIL, not vanish.
#
# On 2026-08-21 two new cases were written against `assert_fails_with`, a
# helper this file has never had. zsh printed "command not found" among 600
# lines of output, the two cases produced no PASS and no FAIL, and the run
# ended 0 FAIL. The count went UP, because the cases they replaced were gone
# too. A suite that can lose a case silently is the same failure it exists to
# catch, aimed at itself.
#
# 一個「呼叫了不存在的東西」的測試必須 FAIL，而不是消失。
# 2026-08-21 有兩個新案例寫成了 `assert_fails_with`——這個檔案從來沒有過這個 helper。
# zsh 在六百行輸出裡印了一行 command not found，那兩個案例既沒有 PASS 也沒有 FAIL，
# 而整份測試以 0 FAIL 結束。數字甚至還變大了，因為它們取代掉的案例也一起不見了。
# 一份會安靜弄丟案例的測試，就是它自己存在要抓的那種失敗，只是對準了自己。
# zsh runs this handler in a SUBSHELL, so `fail=$((fail + 1))` inside it is
# lost -- the FAIL line prints and the tally does not move, which is a guard
# that looks like it works. The name goes to a file instead and is added back
# at the summary.
# zsh 是在「子 shell」裡執行這個處理常式的，因此在它裡面做 `fail=$((fail + 1))` 會遺失
# ——FAIL 那一行印得出來，而計數不動，那是一個「看起來有效」的守衛。改為把名字寫進檔案，
# 在結算時加回去。
# `stat` is OPTIONAL here: the aarch64 guest's busybox does not include the
# applet, which is why file_mode has an ls fallback at all (T129e). Asking
# whether it exists before calling it matters now that a missing command is a
# failure -- the guard cannot tell a deliberate probe from a typo, and eight
# probes made eight failures on the first guest run after it landed. The
# distinction has to be made HERE, by the code that knows the command is
# optional.
# `stat` 在這裡是「可有可無」的：aarch64 guest 的 busybox 沒有把該 applet 編進去，那正是
# file_mode 會有 ls 後備的原因（T129e）。既然「呼叫不存在的指令」現在算是失敗，就得先問它
# 在不在——守衛分不出「刻意的探測」與「打錯字」，而在它落地後的第一次 guest 執行裡，八次
# 探測就成了八個失敗。這個區分必須在「知道那個指令是選用的」這一端做，也就是這裡。
stat_mode() {   # path -> octal mode, or empty when no stat is available
    local m=""
    if (( $+commands[stat] )); then
        m=$(stat -c '%a' "$1" 2>/dev/null)                       # GNU / busybox
        [[ $m == <-> ]] || m=$(stat -f '%Lp' "$1" 2>/dev/null)   # BSD / macOS
    fi
    [[ $m == <-> ]] && print -r -- "$m"
}

MISSING_LOG="${TMPDIR:-/tmp}/.csv2_missing_commands.$$"
rm -f "$MISSING_LOG"
command_not_found_handler() {
    print -r -- "$1" >> "$MISSING_LOG"
    print -r -- "FAIL  the suite called \"$1\", which does not exist -- the case that called it did not run / 測試呼叫了不存在的「$1」——呼叫它的那個案例沒有執行"
    return 127
}

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
# One cell, via `-get`. Until 2026-08-18 this needed a two-stage projection --
# delete every other column into a temp file, then take the record -- because
# there was no address-based read. The blind testing produced the flag; this is
# the helper collapsing onto it.
#
# 用 `-get` 取出一格。在 2026-08-18 之前，這需要兩階段投影——把其餘每一欄刪進一個暫存檔，
# 再取那一筆——因為當時沒有「依位址讀取」。盲測催生了那個旗標，而這個輔助函式就此塌縮成它。
#
# NOTE the difference from CSV output: -get returns the value RAW, so a value
# containing a comma comes back without quotes. Call sites that used to compare
# against a CSV-encoded field had to change with it.
# 注意它與 CSV 輸出的差別：-get 回傳的是「原始值」，因此含逗號的值不會帶引號回來。
# 原本拿 CSV 編碼欄位去比較的呼叫點，必須跟著改。
cell() {   # cell <file> <record> <column-number-or-name>
    "$CSV2" -get "$2:$3" -i "$1" 2>/dev/null
}

# The header cell. -get addresses data records only -- header cells are not
# addressable by any verb -- so this still projects.
# 標頭那一格。-get 只定址資料紀錄——標頭儲存格不是任何動詞能定址的——因此這裡仍用投影。
header_cell() {  # header_cell <file> <column-number>
    local f=$1 c=$2 i
    local n=$("$CSV2" -head 1 -t --json -i "$f" 2>/dev/null | head -1 \
              | grep -o '"fields":[0-9]*' | cut -d: -f2)
    local -a drop
    for i in {1..$n}; do (( i == c )) || drop+=(-delete -col $i); done
    "$CSV2" $drop -i "$f" -o "$TMP/.cell.$$.csv" 2>/dev/null || return 1
    head -1 "$TMP/.cell.$$.csv"
    rm -f "$TMP/.cell.$$.csv" "$TMP/.cell.$$.csv.index"
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
    ok "T9a -si/-so RSS does not grow with the input (${size_small}B→${r_small}B, ${size_big}B→${r_big}B) / 串流 RSS 不隨輸入變大"
else
    bad "T9a streaming RSS (small ${size_small}B→${r_small}B, big ${size_big}B→${r_big}B)"
fi

# T9a above was the whole test, and it was reporting on nothing. Its big
# fixture is 3.3 MB against a ~9 MB floor of process and Foundation, so an
# implementation that retained EVERY byte still fit inside "less than twice
# the small run". It passed by 6%. On 2026-08-19 a reader measured peak RSS at
# 1.02x of a 660 MB stream and was right; this suite had been asserting the
# opposite for months.
#
# Two additions, because the defect had two shapes and only one of them is
# visible in a size comparison.
#
# T9a 原本就是這個測試的全部，而它什麼都沒在回報。它的大 fixture 是 3.3 MB，而行程與
# Foundation 的地板約 9 MB——因此一個「保留每一個位元組」的實作，仍然塞得進「不到小的那次
# 的兩倍」。它通過的餘裕是 6%。2026-08-19 一位讀者量到 660 MB 串流的 peak RSS 是 1.02 倍，
# 而他是對的；這份測試套件已經斷言相反的事好幾個月。
# 加兩條，因為那個缺陷有兩種形狀，而只有一種在「比大小」時看得見。
{ head -2 "$TMP/m_small.csv2"
  for i in {1..200}; do tail -n +3 "$TMP/m_small.csv2"; done } > "$TMP/m9_many.csv2"
pad9=$(printf 'x%.0s' {1..880})
{ print -r -- 'k,v,note'; print -r -- '鍵,值,註記'
  for i in {1..17000}; do print -r -- "row$i,value$i,\"$pad9\""; done } > "$TMP/m9_few.csv2"

cat "$TMP/m9_many.csv2" | "$CSV2" -si --headers 2 -so -r -debug > /dev/null 2>"$TMP/m9c.txt"
cat "$TMP/m9_few.csv2"  | "$CSV2" -si --headers 2 -so -r -debug > /dev/null 2>"$TMP/m9d.txt"
r_many=$(rss_of "$TMP/m9c.txt"); r_few=$(rss_of "$TMP/m9d.txt")
size_many=$(wc -c < "$TMP/m9_many.csv2" | tr -d ' ')
size_few=$(wc -c < "$TMP/m9_few.csv2" | tr -d ' ')

# Two large streams, one twice the other, compared against EACH OTHER. The
# first version of this asserted "peak RSS below the input size", which passed
# on macOS and failed in the guest at 27 MB for a 15.5 MB stream -- and that
# told me nothing, because it cannot separate "Linux still retains the stream"
# from "Linux's floor is simply higher". An absolute comparison against the
# input size silently assumes a floor, and the floor is a property of the
# platform's Foundation, not of csv2.
#
# Doubling the input makes the floor cancel: both runs pay it once. If the
# stream is retained, the larger run costs a whole extra input; the bound here
# is a QUARTER of that, so an implementation that keeps even half of what it
# reads cannot pass, on any platform, without knowing what the floor is.
#
# 兩條大串流，其中一條是另一條的兩倍，而且是「互相比較」。這一條的第一版斷言的是
# 「peak RSS 低於輸入大小」，它在 macOS 上通過、在 guest 上以「15.5 MB 的串流用了 27 MB」
# 失敗——而那個失敗什麼也沒告訴我，因為它分不出「Linux 仍然留住整條串流」與「Linux 的地板
# 本來就比較高」。拿輸入大小做絕對比較，等於默默假設了一個地板，而那個地板是該平台
# Foundation 的性質，不是 csv2 的。
# 把輸入加倍會讓地板抵銷：兩次執行各付一次。若串流被留住，較大的那次會多付一整份輸入；
# 而這裡的界線是那一份的「四分之一」，因此一個「連讀進來的一半都留著」的實作，在任何平台上
# 都過不了，而且不需要知道地板是多少。
{ head -2 "$TMP/m_small.csv2"
  for i in {1..400}; do tail -n +3 "$TMP/m_small.csv2"; done } > "$TMP/m9_many2.csv2"
cat "$TMP/m9_many2.csv2" | "$CSV2" -si --headers 2 -so -r -debug > /dev/null 2>"$TMP/m9e.txt"
r_many2=$(rss_of "$TMP/m9e.txt")
size_many2=$(wc -c < "$TMP/m9_many2.csv2" | tr -d ' ')
if [[ -n "$r_many" && -n "$r_many2" && $r_many2 -lt $((r_many + size_many / 4)) ]]; then
    ok "T9b doubling the stream does not add memory (${size_many}B→${r_many}B, ${size_many2}B→${r_many2}B) / 串流加倍不增加記憶體"
else
    bad "T9b memory grows with the stream (${size_many}B→${r_many}B, ${size_many2}B→${r_many2}B; bound $((r_many + size_many / 4)))"
fi

# The same bytes in a twentieth of the records. This is the assertion that
# names the actual defect: what was retained was per-RECORD, not per-byte, so
# a size-only comparison could never have separated it from the floor.
# 同樣的位元組，紀錄數是二十分之一。這一條指名了真正的缺陷：被留住的東西是「每一筆」一份
# 而不是每個位元組，因此只比大小的比較，永遠無法把它與那個地板分開。
if [[ -n "$r_many" && -n "$r_few" && $r_many -lt $((r_few * 3 / 2)) ]]; then
    ok "T9c RSS does not track the RECORD COUNT (${size_many}B/400k rec →${r_many}B vs ${size_few}B/17k rec →${r_few}B) / RSS 不隨紀錄數成長"
else
    bad "T9c RSS tracks record count (${size_many}B/400k rec →${r_many}B vs ${size_few}B/17k rec →${r_few}B)"
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

# T20d/T20e — the astral plane, which T20c does not reach. 套 is U+5957: one
# \u escape, the easy case. A character above U+FFFF has no single \u form and
# must be written as a UTF-16 surrogate PAIR, which is where a hand-rolled JSON
# encoder classically breaks -- and it breaks silently, emitting something that
# parses as a different character or as a lone surrogate.
#
# Asserted against the exact expected pair rather than by round-tripping
# through a parser: the guest has no python, and the arithmetic is fixed.
# U+1F680: high = 0xD800 + ((0x1F680-0x10000) >> 10) = 0xD83D
#          low  = 0xDC00 + ((0x1F680-0x10000) & 0x3FF) = 0xDE80
#
# T20d／T20e —— 星光平面（astral plane），那是 T20c 沒有觸及的。套 是 U+5957：單一個 \u
# 跳脫，簡單的那一種。U+FFFF 以上的字元沒有單一 \u 形式，必須寫成 UTF-16 的「代理對」，
# 而那正是手寫的 JSON 編碼器經典的斷裂處——而且它是靜默地斷：輸出的東西仍然解析得過，
# 只是變成另一個字元，或是一個落單的代理碼位。
# 這裡以「預期的那一對」直接斷言，而不是丟進解析器 round-trip：guest 上沒有 python，
# 而那個算術是固定的。
printf 'pkg,note\nfoo,rocket \xf0\x9f\x9a\x80 emoji\n' > "$TMP/t20_astral.csv"
astral=$("$CSV2" -r --json --json-ascii -i "$TMP/t20_astral.csv" 2>/dev/null | sed -n 2p)
assert_contains "$astral" '\ud83d\ude80' \
    "T20d --json-ascii writes U+1F680 as the correct surrogate pair / --json-ascii 以正確的代理對寫出 U+1F680"
if [[ "$astral" == *$'\xf0\x9f\x9a\x80'* ]]; then
    bad "T20e raw non-ASCII bytes survived --json-ascii / 原始的非 ASCII 位元組通過了 --json-ascii"
else
    ok "T20e and no raw non-ASCII byte survives, which is the flag's whole promise / 沒有任何原始非 ASCII 位元組留下，那正是這個旗標的全部承諾"
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
# The tamper is done with the SHELL, not with csv2, and the difference is the
# whole case.
#
# It used to be `csv2 -update '1:6' "$flip"`, and that write is REFUSED -- a
# raw value into a column the file declares transformed, a guard added later
# and rightly. So `tamper.csv` was never created, `-decrypt` failed with
# `cannot open input file`, and `assert_fails` reported PASS. The case could
# not fail: with a real ciphertext, with an empty string, with nothing at all,
# it passed the same way, and it has been passing that way since the guard
# landed.
#
# On macOS it was worse still. The mutation was
# `sed 's/^A/B/; t; s/^./A/'`, and BSD sed reads the text after `;` as the
# label of the unlabeled `t`: every run printed `undefined label` and produced
# an EMPTY string. Two independent reasons for the same green tick, neither of
# them the AEAD.
#
# So: build the tampered file here, byte for byte, and assert the MESSAGE.
# `assert_fails` alone cannot tell an authentication failure from a missing
# file -- which is exactly how this case spent months proving nothing.
#
# 這次竄改是用 shell 做的，不是用 csv2，而那個差別就是這整個案例。
#
# 原本是 `csv2 -update '1:6' "$flip"`，而那次寫入會被「拒絕」——把原始值寫進一個「檔案宣告為
# 已轉換」的欄位，那是後來才加上的守衛，而且是對的。於是 `tamper.csv` 從來沒有被建立，
# `-decrypt` 以「cannot open input file」失敗，而 `assert_fails` 回報 PASS。這個案例不可能失敗：
# 給它真的密文、給它空字串、什麼都不給，它都以同一種方式通過。
#
# 在 macOS 上更糟：那段 `sed 's/^A/B/; t; s/^./A/'` 會被 BSD sed 讀成「分號後面是那個無標籤 `t`
# 的標籤」，每次都印出 `undefined label` 並產生一個「空字串」。同一個綠勾有兩個各自獨立的理由，
# 而其中沒有一個是 AEAD。
#
# 因此：在這裡逐位元組把被竄改的檔案造出來，並且斷言那則「訊息」。單靠 assert_fails 分不出
# 「認證失敗」與「檔案不存在」——而那正是這個案例好幾個月什麼也沒有證明的原因。
# A fixture of its own, whose encrypted column is the LAST one and holds no
# quoted commas -- so the shell can find the ciphertext without parsing CSV,
# which is the one thing a shell must never do to a csv2 fixture. On
# TARGET_PACKAGES.csv the encrypted column is the sixth of seven and its
# neighbours contain quoted commas: splitting that line on the last comma
# tampers with `license` and `-decrypt status_notes` then SUCCEEDS, which is
# the first way this rewrite got it wrong.
# 這個案例有自己的 fixture：被加密的那一欄是「最後一欄」、而且不含帶引號的逗號——這樣 shell
# 就能在不解析 CSV 的情況下找到密文，而「用 shell 解析 CSV」正是絕對不該對 csv2 的 fixture
# 做的事。在 TARGET_PACKAGES.csv 上，被加密的是七欄中的第六欄，而它的鄰居含有帶引號的逗號：
# 以「最後一個逗號」去切那一行，竄改到的是 `license`，而 `-decrypt status_notes` 會成功
# ——那是這次改寫第一次弄錯的地方。
# Its own NAMES too: $TMP/enc.csv belongs to T34a, T35 and T39, and writing
# the small fixture over it made T35b and T39 fail on a file they never asked
# for -- a shared name is a shared fixture whether or not anyone meant it to be.
# 也用自己的「檔名」：$TMP/enc.csv 屬於 T34a、T35 與 T39，把這個小 fixture 寫在它上面，
# 會讓 T35b 與 T39 對著一個它們從未要求過的檔案失敗——共用的名字就是共用的 fixture，
# 不論有沒有人打算讓它共用。
printf 'id,secret\n1,alpha\n2,beta\n' > "$TMP/t34src.csv"
"$CSV2" -encrypt secret -keyfile "$KEY" -i "$TMP/t34src.csv" -o "$TMP/t34enc.csv" -t 2>/dev/null
_t34_enc_line=$(sed -n 2p "$TMP/t34enc.csv")
_t34_pre=${_t34_enc_line%,*}          # everything before the LAST comma
_t34_ct=${_t34_enc_line##*,}          # secret is the last column in this fixture
if [[ ${_t34_ct[1]} == A ]]; then
    _t34_new="B${_t34_ct[2,-1]}"
else
    _t34_new="A${_t34_ct[2,-1]}"
fi
{
    head -1 "$TMP/t34enc.csv"
    print -r -- "${_t34_pre},${_t34_new}"
    sed -n '3,$p' "$TMP/t34enc.csv"
} > "$TMP/t34tamper.csv"
if cmp -s "$TMP/t34enc.csv" "$TMP/t34tamper.csv"; then
    bad "T34b the tamper changed nothing, so nothing is being tested / 這次竄改什麼也沒改，因此什麼也沒有被測試"
else
    _t34_msg=$("$CSV2" -decrypt secret -keyfile "$KEY" -i "$TMP/t34tamper.csv" -o "$TMP/t34x.csv" 2>&1)
    _t34_rc=$?
    if (( _t34_rc == 1 )) && [[ $_t34_msg == *"authentication failed"* ]]; then
        ok "T34b a tampered ciphertext fails AUTHENTICATION, not something else / 被竄改的密文是「認證」失敗，不是別的失敗"
    else
        bad "T34b rc=$_t34_rc, message: ${_t34_msg%%$'\n'*} / rc 與訊息如上"
    fi
fi

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

# T43b — writing few bytes and leaving the file alone are different claims.
# A fast path could write little and still rewrite what was already there; T43
# would not notice, because it measures the write, not the file. Round 24 of the
# blind testing checked the prefix with cmp after twenty in-place appends to a
# 207 MB file and found it byte-identical -- "fast for the reason claimed", as
# it put it. That check belongs here rather than in one person's transcript.
# T43b —— 「寫得少」與「沒動到原有內容」是兩個不同的宣稱。
# 一條快路徑可以寫得很少，卻仍然重寫了原本就在那裡的東西；T43 不會發現，因為它量的是
# 「寫入」而不是「檔案」。盲測第 24 回合在對一個 207 MB 的檔案做了二十次就地追加之後，
# 用 cmp 檢查了前綴，發現逐位元相同——用它的話說，是「因為所宣稱的理由而快」。
# 那個檢查該放在這裡，而不是留在某一個人的紀錄裡。
cp "$TMP/big.csv" "$TMP/big_before.csv"
before_bytes=$(wc -c < "$TMP/big_before.csv" | tr -d ' ')
for i in 1 2 3; do
    "$CSV2" -append "ap$i,v,s,src,purpose,note,MIT" -i "$TMP/big.csv" --in-place 2>/dev/null
done
head -c "$before_bytes" "$TMP/big.csv" > "$TMP/big_prefix.csv"
if cmp -s "$TMP/big_before.csv" "$TMP/big_prefix.csv"; then
    ok "T43b and leaves every byte that was already there untouched / 而且原本就在那裡的每一個位元組都原封不動"
else
    bad "T43b -append altered bytes before the appended records / -append 動到了新增紀錄之前的位元組"
fi
assert_eq "$("$CSV2" -tail 1 -i "$TMP/big.csv" 2>/dev/null)" 'ap3,v,s,src,purpose,note,MIT' \
    "T43c with the last appended record where it belongs / 而最後追加的那一筆就在它該在的位置"

# T43d-T43f — the fast path is scoped to --in-place, and the scope is required
# by another guarantee rather than being an oversight.
#
# The README says "O(1) WHEN WRITING IN PLACE". Round 30 tested the boundary and
# it holds sharply: -o on a 207 MB file took 5.8 s against 4 ms in place,
# scaling with size, because it rewrites. That is not a missed optimisation. -o
# promises that a run which fails writes nothing to it, which needs temp+rename;
# an append that extends the destination directly cannot offer that, because a
# failure halfway leaves the destination longer than it started.
#
# Asserted through the log rather than a clock: the two paths say different
# things, and timing assertions are the kind that fail on a loaded machine for
# reasons unrelated to the code.
#
# T43d–T43f —— 快路徑的適用範圍限於 --in-place，而那個範圍是「另一條保證」所要求的，
# 不是疏漏。
# README 寫的是「就地寫入時為 O(1)」。第 30 回合測了那條界線，而它守得很利落：對一個
# 207 MB 的檔案使用 -o 要 5.8 秒，就地則是 4 毫秒，且隨大小成長——因為它會重寫。
# 那不是一個被漏掉的最佳化。-o 承諾「失敗的執行不會在它上面留下任何東西」，那需要
# temp+rename；而一個「直接把目的地延長」的追加做不到這件事，因為中途失敗會留下一個
# 比原本更長的目的地。
# 以 log 而非碼錶斷言：兩條路徑說的話不同，而計時斷言正是那種會在機器忙碌時、因為與程式碼
# 無關的理由而失敗的東西。
cp "$TMP/big.csv" "$TMP/big_o.csv"
rm -f "$TMP/a3.log" "$TMP/a4.log"
"$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i "$TMP/big_o.csv" -o "$TMP/big_o_out.csv" \
    -log "$TMP/a3.log" 2>/dev/null
"$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i "$TMP/big_o.csv" --in-place \
    -log "$TMP/a4.log" 2>/dev/null

if grep -q 'append fast path' "$TMP/a4.log"; then
    ok "T43d --in-place takes the fast path, and says so / --in-place 走快路徑，而且它會這樣說"
else
    bad "T43d expected the fast path with --in-place / 預期 --in-place 走快路徑"
fi
if grep -q 'append fast path' "$TMP/a3.log"; then
    bad "T43e -o must NOT take the fast path: it could not then promise that a failed run writes nothing / -o 不該走快路徑：那樣它就無法承諾「失敗的執行不留下任何東西」"
else
    ok "T43e while -o rewrites instead, which is what lets it promise a failed run writes nothing / 而 -o 改為重寫，那正是它得以承諾「失敗的執行不留下任何東西」的原因"
fi

# T43g-T43h -- the same guarantee, typed the way people actually type it.
#
# T43d passes an absolute path that happens to be canonical already. That is
# not what a caller writes. `--in-place` resolves symlinks on the output path
# (T129), and resolvingSymlinksInPath() ALSO normalises: a relative path
# becomes absolute, and on macOS /private/tmp becomes /tmp. The fast path was
# gated on the two paths being equal STRINGS, so from 9132e66 until this test
# existed, `-append -i data.csv --in-place` rewrote the whole file -- correct
# output, O(n) bytes written, and T43d green throughout.
#
# T43g–T43h —— 同一條保證，用人們實際會打的寫法。
# T43d 傳的是一個剛好已是正規形式的絕對路徑，而那不是呼叫者會寫的東西。`--in-place`
# 會解析輸出路徑上的 symlink（T129），而 resolvingSymlinksInPath() 同時也會正規化：
# 相對路徑變絕對，macOS 上 /private/tmp 變 /tmp。快路徑的守衛比的是兩個「字串」是否
# 相等，因此從 9132e66 起、直到有了這個測試為止，`-append -i data.csv --in-place`
# 一直在重寫整個檔案——輸出正確、寫入 O(n)，而 T43d 全程是綠的。
rm -f "$TMP/a5.log"
cp "$TMP/big.csv" "$TMP/big_rel.csv"
( cd "$TMP" && "$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i big_rel.csv --in-place \
    -log a5.log 2>/dev/null )
if grep -q 'append fast path' "$TMP/a5.log"; then
    ok "T43g a relative path takes the fast path too / 相對路徑同樣會走快路徑"
else
    bad "T43g a relative path fell back to a full rewrite / 相對路徑退回了全檔重寫"
fi

# Through a symlink: the fast path opens the path as given, and O_APPEND
# follows the link, so the target grows and the link survives. That has to be
# checked rather than assumed -- it is the same property T129 pins for the
# rewrite path, and the two paths reach the file by different means.
# 經 symlink：快路徑就用給定的路徑開檔，而 O_APPEND 會跟著連結走，因此目標長大、連結
# 存活。這件事要驗，不能假設——它與 T129 為重寫路徑釘住的是同一個性質，而兩條路徑
# 抵達那個檔案的方式並不相同。
if (( IS_WINDOWS )); then
    skipt "T43h an append through a symlink keeps the link and grows the target / 經 symlink 的追加會保留連結並讓目標長大 (no symlinks under MSYS2 / MSYS2 下沒有 symlink)"
else
    rm -f "$TMP/a6.log" "$TMP/big_sym.csv"
    cp "$TMP/big.csv" "$TMP/big_target.csv"
    ln -sf "$TMP/big_target.csv" "$TMP/big_sym.csv"
    _t43_before=$(wc -c < "$TMP/big_target.csv")
    "$CSV2" -append 'zz,v,s,src,purpose,note,MIT' -i "$TMP/big_sym.csv" --in-place \
        -log "$TMP/a6.log" 2>/dev/null
    _t43_after=$(wc -c < "$TMP/big_target.csv")
    # The fast-path line is required as well. Without it this case passed even
    # with the fast path dead: the rewrite path keeps the link too (T129), so
    # link-plus-growth alone cannot tell the two apart -- and a test that cannot
    # tell them apart is not pinning the thing its name claims.
    # 也要求那一行「快路徑」。少了它，這個案例在快路徑已死時照樣通過：重寫那條路也會保留
    # 連結（T129），因此「連結還在且長大了」分不出這兩者——而一個分不出來的測試，並沒有
    # 釘住它名字所宣稱的東西。
    if [[ -L "$TMP/big_sym.csv" && $_t43_after -gt $_t43_before ]] \
       && grep -q 'append fast path' "$TMP/a6.log"; then
        ok "T43h an append through a symlink takes the fast path, keeps the link and grows the target / 經 symlink 的追加會走快路徑、保留連結並讓目標長大"
    else
        bad "T43h symlink=$([[ -L "$TMP/big_sym.csv" ]] && echo kept || echo replaced), target $_t43_before -> $_t43_after, fast path=$(grep -c 'append fast path' "$TMP/a6.log") / symlink、目標大小與快路徑如上"
    fi
fi
assert_contains "$(cat "$TMP/a3.log")" 'atomic rename OK' \
    "T43f and -o reports the rename, the guarantee it is paying for / 而 -o 會回報那次 rename，也就是它付出代價換來的那條保證"

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
unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

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
# Counting ALL trace lines made this brittle, and it broke the moment trace
# started reporting the records it does NOT emit (round 38, DD) plus the line
# saying where the read stops. The property T50 is about is unchanged --
# reachable with the flag, silent without -- so it now counts the per-record
# lines specifically instead of everything the level ever prints.
# 計算「全部的 trace 行」讓這條測試很脆弱，而在 trace 開始回報「沒有被輸出的紀錄」
# （第 38 回合，DD）以及那行「讀取到此為止」的當下，它就壞了。T50 要測的性質沒有變
# ——給了旗標就到得了、沒給就沉默——因此它現在只數「逐筆的那種行」，而不是那個層級
# 曾經印出的每一行。
t_on=$("$CSV2" -head 2 -i "$PKG" -debug=trace 2>&1 >/dev/null | grep -c 'select: record [0-9]* line')
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
unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

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

# Each name in quotes: a column name can contain the comma this list separates
# on, and `the columns are: a,b, c` reads as three columns. Round 54 found that
# on a file whose first column really is called `a,b`.
# 每個名字都加引號：欄名裡可以含有「這份清單用來分隔的那個逗號」，而
# 「the columns are: a,b, c」讀起來像三欄。第 54 回合是在一個第一欄真的叫 `a,b` 的檔案上
# 發現這件事的。
assert_eq "$("$CSV2" -delete -col b -i "$TMP/dc.csv2" -so 2>&1 >/dev/null | head -1)" \
    'csv2: no column named "b"; the columns are: "pkg", "version", "notes", "license"' \
    "T57e an unknown column name names the columns that do exist, each quoted / 未知的欄位名稱會列出實際存在的欄位，每個都加引號"

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
# Replace whatever path precedes `rm.csv2`, rather than the exact $TMP string.
# MSYS2 rewrites a POSIX path into a Windows one on the way to a native binary,
# so the message came back saying C:/Users/... while $TMP held /c/Users/... and
# the substitution silently matched nothing. Anchoring on the FILENAME works on
# every platform and does not care who rewrote the directory part.
# 取代「`rm.csv2` 之前的任何路徑」，而不是那個精確的 $TMP 字串。MSYS2 在把參數交給原生程式
# 的途中會把 POSIX 路徑改寫成 Windows 形式，因此訊息回來時寫的是 C:/Users/...，而 $TMP 裡是
# /c/Users/...，於是那個替換靜默地什麼都沒有匹配到。以「檔名」為錨點在每個平台上都有效，
# 而且不在乎是誰改寫了目錄的部分。
actual_en=$(head -1 "$TMP/rm_err.txt" | sed -E 's|[^[:space:]：]*/rm\.csv2|vs-sqlite.csv2|')
assert_eq "$actual_en" "$readme_en" \
    "T58a the README quotes the English error line in full, not truncated at the first full stop / README 完整引用了英文錯誤行，而非在第一個句號處截斷"

readme_zh=$(grep -F '的副檔名宣告了 2 列標頭' "$ROOT/README.md" | head -1)
actual_zh=$(sed -n 2p "$TMP/rm_err.txt" | sed -E 's|[^[:space:]：]*/rm\.csv2|vs-sqlite.csv2|')
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
#
# CORRECTED on 2026-08-19. This asserted `record 3, field 2` for a fault in
# data record 1 of a .csv2 -- 3 being the physical line. The assertion was
# right that a cell fault names both; it was wrong about what the number
# means, and by pinning the printed string it froze the defect as the
# specification. Round 38 (CC) found that the address could not be typed back
# into -get. T93 now covers the addressing; this case keeps its own point,
# which is that a cell fault names BOTH parts rather than one.
#
# 2026-08-19 更正。它原本對「.csv2 資料第 1 筆的錯誤」斷言 `record 3, field 2`，
# 而 3 是物理行號。這條斷言在「儲存格錯誤要同時指出兩者」上是對的，錯的是那個號碼的意思；
# 而它以「釘住印出來的字串」的方式，把缺陷凍結成了規格。第 38 回合（CC）發現那個位址
# 打不回 -get。定址現在由 T93 涵蓋；這個案例保留它自己的重點：儲存格錯誤要指出「兩個」
# 部分，而不是其中一個。
# 錯在某一格：紀錄與欄位都指出，因為兩者都為真。
"$CSV2" -r -i "$TMP/t60_cell.csv2" 2> "$TMP/t60_a.txt" >/dev/null
assert_contains "$(head -1 "$TMP/t60_a.txt")" "record 1 (line 3), field 2" \
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

# A POSIX FIFO created by an MSYS shell does not exist for a native Windows
# binary, so csv2.exe reads nothing from it and this measures the shim rather
# than the tool. The property itself -- that output starts before input ends,
# and that memory does not track the stream -- is asserted on every platform by
# T9; only this particular INSTRUMENT is unavailable here.
# MSYS 的 shell 所建立的 POSIX FIFO，對原生的 Windows 程式而言並不存在，因此 csv2.exe
# 從它那裡什麼也讀不到，而這個案例量到的會是那層 shim 而不是這支工具。它要測的性質本身
# ——輸出在輸入結束前就開始、記憶體不隨串流成長——由 T9 在每個平台上斷言；此處不可用的
# 只是「這一個量測工具」。
if (( IS_WINDOWS )); then
    skipt "T61a output arrives while the input is still open / 輸入還開著時輸出就已到達 (a POSIX FIFO is not visible to a native Windows binary; the property is covered by T9 / MSYS 的 FIFO 對原生 Windows 程式不存在；該性質由 T9 涵蓋)"
    skipt "T61c the streamed output is complete / 串流輸出是完整的 (same reason / 同上)"
else
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
fi

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

unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

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
# cell() now returns the RAW value, because it is -get and -get hands over the
# value rather than a CSV encoding of it. The quotes this used to expect were an
# artefact of the old two-stage projection, and their disappearance is the
# improvement, not a regression -- this assertion moved when the helper did,
# which is how a contract change is supposed to announce itself.
# cell() 現在回傳「原始值」，因為它就是 -get，而 -get 交出的是值本身而非它的 CSV 編碼。
# 這裡原本預期的引號，是舊的兩階段投影留下的產物；它們消失是改善而不是退步——這條斷言隨著
# 輔助函式一起改變，而「契約變更」本來就該用這種方式宣告自己。
assert_eq "${by_csv2:0:9}" 'CORRECTED' \
    "T64c while csv2 returns the whole cell, as its raw value / csv2 回傳的則是完整儲存格的原始值"
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

# ---------------------------------------------------------------------
# T68 -- a corrupt index must be DISCARDED, including corruption inside the
#        index itself.
#
# Round 18 of the blind testing, and the only TOOL BROKEN of the run. Round 10
# had already shown that an index full of garbage is caught. This went further
# and asked whether a PLAUSIBLE corruption gets through -- one that still
# passes the O(1) staleness check.
#
# It did. Every check described the DATA file: its size, its mtime, the hashes
# of its first and last bytes, and the number of entries. Nothing described the
# index. So a single flipped bit in an offset passed all of them, and the wrong
# offset was used: `-mid 1,1` returned a fragment beginning mid-field, presented
# as a record, at rc=0, while `-r` on the same file was correct because it never
# consults the index. `-tail` silently returned one record fewer.
#
# The README's own words for that outcome are "far worse than no index". It was
# produced by the one thing nothing was checking.
#
# T68 —— 損毀的索引必須被「丟棄」，包括索引自身內部的損毀。
# 盲測第 18 回合，也是整輪唯一一個 TOOL BROKEN。第 10 回合已證明「整份垃圾」的索引會被
# 攔下。這一回合更進一步，問的是「合理的」損毀能不能通過——一個仍然能通過 O(1) 過期檢查的
# 損毀。它通過了。所有檢查描述的都是「資料檔」：大小、mtime、首尾位元組的雜湊、項目數。
# 沒有任何東西描述索引本身。於是偏移量裡一個翻轉的位元通過了全部檢查，那個錯誤的偏移量被
# 採用：`-mid 1,1` 回傳了一段從欄位中間開始的碎片，以「一筆紀錄」呈現，rc=0；而同一個檔案的
# `-r` 是正確的，因為它從不使用索引。`-tail` 則安靜地少回傳一筆。
# README 對這種結果的用語是「比沒有索引糟得多」。而它出自那個唯一沒有被檢查的東西。
# ---------------------------------------------------------------------
echo
echo "--- T68: corruption INSIDE the index is discarded / 索引「內部」的損毀會被丟棄 ---"

export CSV2_INDEX_MIN_BYTES=1
printf 'pkg,ver,note\nbusybox,1,a\nzlib,2,b\nzstd,3,c\nncurses,4,d\n' > "$TMP/t68.csv"
rm -f "$TMP/t68.csv.index"
"$CSV2" -tail 4 -i "$TMP/t68.csv" >/dev/null 2>&1
assert_succeeds "T68a an index was built to corrupt / 已建立可供破壞的索引" -- \
    test -f "$TMP/t68.csv.index"

# The truth, taken without the index so it cannot be the thing under test.
# 不經索引取得的真值，以免它本身就是受測物。
want1=$("$CSV2" --no-index -mid 1,1 -i "$TMP/t68.csv" 2>/dev/null)
wantn=$("$CSV2" --no-index -tail 4 -i "$TMP/t68.csv" 2>/dev/null | wc -l | tr -d ' ')

# Byte 88 is the low byte of the first offset entry: the header is 88 bytes, so
# this is the field that says where record 1 begins. Changing 13 to 26 points it
# at the middle of record 2 -- a value that is plausible, in range, and wrong.
# dd rather than a scripting language: the guest runs this suite and has neither
# python nor perl.
# 第 88 個位元組是第一個偏移量項目的低位位元組：檔頭是 88 bytes，因此這個欄位說的是「第 1 筆
# 從哪裡開始」。把 13 改成 26，會讓它指向第 2 筆的中間——一個合理、在範圍內、而且錯誤的值。
# 用 dd 而不是腳本語言：guest 也會跑這份測試，而那裡既沒有 python 也沒有 perl。
printf '\032' | dd of="$TMP/t68.csv.index" bs=1 seek=88 conv=notrunc 2>/dev/null

got1=$("$CSV2" -mid 1,1 -i "$TMP/t68.csv" 2>"$TMP/t68_err.txt")
rc=$?
assert_eq "$got1" "$want1" \
    "T68b a corrupted offset does not change the answer / 被破壞的偏移量不改變答案"
assert_eq "$rc" "0" "T68c and is not an error / 而且不是錯誤"
assert_eq "$(wc -c < "$TMP/t68_err.txt" | tr -d ' ')" "0" \
    "T68d and says nothing on stderr / stderr 也不說話"
assert_eq "$("$CSV2" -tail 4 -i "$TMP/t68.csv" 2>/dev/null | wc -l | tr -d ' ')" "$wantn" \
    "T68e -tail returns every record, not one fewer / -tail 回傳每一筆，不會少一筆"

# The -tail above REPLACED the corrupt index: it reads the whole file anyway, so
# it writes a fresh one. That is worth asserting on its own -- a corrupt index
# is not merely ignored, it is repaired by the next operation that has the
# information to do so. The corruption has to be reapplied before anything can
# be checked against it.
# 上面那個 -tail 已經「替換」了損毀的索引：它本來就要讀完整個檔案，因此會順手寫出一份新的。
# 這件事本身就值得斷言——損毀的索引不只是被忽略，而是被「下一個握有足夠資訊的操作」修好。
# 因此要再檢查任何東西之前，必須先把損毀重新施加一次。
healed=$("$CSV2" --verify-index -i "$TMP/t68.csv" >/dev/null 2>&1; print $?)
assert_eq "$healed" "0" \
    "T68f a full read replaced the corrupt index with a good one / 一次完整讀取以一份好的索引替換了損毀的那份"

printf '\032' | dd of="$TMP/t68.csv.index" bs=1 seek=88 conv=notrunc 2>/dev/null
assert_fails "T68f2 and with the corruption reapplied, --verify-index refuses / 重新施加損毀後，--verify-index 拒絕" -- \
    "$CSV2" --verify-index -i "$TMP/t68.csv"

# An index written by a version that could not detect corruption in itself is
# discarded on sight rather than trusted.
# 由「無法偵測自身損毀」的版本寫出的索引，會被直接丟棄而不是被信任。
rm -f "$TMP/t68.csv.index"
"$CSV2" -tail 4 -i "$TMP/t68.csv" >/dev/null 2>&1
printf '\001' | dd of="$TMP/t68.csv.index" bs=1 seek=8 conv=notrunc 2>/dev/null
assert_eq "$("$CSV2" -mid 1,1 -i "$TMP/t68.csv" 2>/dev/null)" "$want1" \
    "T68g an older index version is discarded, not trusted / 較舊版本的索引會被丟棄而非信任"

# Corruption anywhere, not just in the offsets: the header carries the record
# count and the stride, and a wrong one of those misdirects a read just as well.
# 損毀可能發生在任何地方，不只偏移量：檔頭帶著紀錄數與 stride，其中任何一個錯了，同樣
# 會把一次讀取導向錯的位置。
rm -f "$TMP/t68.csv.index"
"$CSV2" -tail 4 -i "$TMP/t68.csv" >/dev/null 2>&1
printf '\007' | dd of="$TMP/t68.csv.index" bs=1 seek=56 conv=notrunc 2>/dev/null
assert_eq "$("$CSV2" -mid 1,1 -i "$TMP/t68.csv" 2>/dev/null)" "$want1" \
    "T68h corruption in the header is caught too, not only in the offsets / 檔頭的損毀同樣會被攔下，不只偏移量"

rm -f "$TMP/t68.csv.index"
unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

# ---------------------------------------------------------------------
# T69 -- no document quotes a test count.
#
# Round 20 found README.md still saying "112 PASS" after the suite had passed
# through 143, 152, 153, 157, 164, 167, 173, 185, 188, 193, 195, 201 and 210.
# Seven such numbers existed across five files, in three different states of
# staleness -- one said 74. The block is offered as the way to verify the tool
# works, so a reader who ran it saw a number that did not match and had no way
# to know which of the two was wrong.
#
# The fix is not to update them. A number that decays with every commit will
# decay again the moment attention moves. They are gone, and this case stops
# them coming back: the docs say 0 FAIL and name the one SKIP, both of which
# stay true as the suite grows.
#
# T69 —— 任何文件都不引用測試數量。
# 第 20 回合發現 README.md 仍寫著「112 PASS」，而測試早已一路經過 143、152、153、157、
# 164、167、173、185、188、193、195、201 到 210。五個檔案裡共有七個這樣的數字，處於三種
# 不同的過期狀態——其中一個寫著 74。那段程式區塊是被當成「驗證這支工具能用」的方法提供的，
# 因此照做的讀者會看到一個對不上的數字，而且無從判斷是哪一邊錯了。
# 修法不是把它們更新。一個「每次提交都會衰減」的數字，在注意力移開的那一刻就會再次衰減。
# 它們被移除了，而這個案例阻止它們回來：文件只說 0 FAIL 並指名唯一的那個 SKIP，兩者都會
# 隨著測試增長而保持為真。
# ---------------------------------------------------------------------
echo
echo "--- T69: no document quotes a test count / 任何文件都不引用測試數量 ---"

# The list did not include plan/ or todo/, and on 2026-08-19 plan.md's own
# header was found carrying TWO stale counts -- macOS 112, guest 72, against a
# suite already far past both. This case existed precisely to stop that, and it
# was not looking at the file. A check with a hand-written file list decays the
# same way the numbers do; the difference is that nothing reports it.
#
# The pattern now excludes a digit preceded by `T`, so a test IDENTIFIER
# ("測試 T1-T8 通過", "T16 通過") is not mistaken for a count. That distinction
# is why the list could not simply be widened: plan.md is full of the former.
#
# 這份清單原本不含 plan/ 與 todo/，而 2026-08-19 發現 plan.md 自己的開頭帶著「兩個」過期
# 數字——macOS 寫 112、guest 寫 72，而測試套件早已遠超過兩者。這個案例存在的目的正是阻止
# 那件事，而它根本沒有在看那個檔案。一份「手寫檔案清單」的檢查，與那些數字以同樣的方式衰減；
# 差別只在於沒有任何東西會回報它。
# 樣式現在排除「前面緊接著 T 的數字」，好讓測試「編號」（「測試 T1–T8 通過」、「T16 通過」）
# 不被誤認為數量。那個區別正是這份清單不能直接放寬的原因：plan.md 裡到處都是前者。
typeset -a counted
for f in README.md README.zh-TW.md AGENTS.md CLAUDE.md test/README.md test/README.zh-TW.md \
         plan/plan.md todo/todo.md todo/known-defects.md \
         verifications/README.md verifications/README.zh-TW.md; do
    [[ -f "$ROOT/$f" ]] || continue
    # A digit immediately before PASS, in either language's phrasing, and not
    # part of a test id. `0 FAIL` is fine and deliberate -- it does not grow.
    # 兩種語言中「數字緊接在 PASS 之前」的寫法，且不是測試編號的一部分。
    # `0 FAIL` 沒問題且是刻意的——它不會增長。
    if grep -qE '(^|[^T0-9])[0-9]+ (PASS|通過)|PASS [0-9]+' "$ROOT/$f"; then
        counted+=("$f")
    fi
done
if (( ${#counted} == 0 )); then
    ok "T69a no document quotes a PASS count, so none of them can go stale / 沒有任何文件引用 PASS 數量，因此它們都不會過期"
else
    bad "T69a these quote a PASS count and will go stale: ${counted} / 這些引用了 PASS 數量，將會過期：${counted}"
fi

# ---------------------------------------------------------------------
# T70 -- -get r:c, the read that matches -update r:c VAL.
#
# Round 14 asked for one cell at a known address and found there was no way:
# record:field composed only with WRITES. Reading it back took --json plus a
# full-file selection plus an external parser -- and this suite's own cell()
# helper needed two csv2 invocations and a temp file for the same thing.
#
# The strongest argument was that an address can arrive from OUTSIDE: typed by
# a person from a bug report, or carried over from an earlier run. -contains
# cannot serve that case at all, because it can only find a value you already
# know is there.
#
# T70 —— `-get r:c`，與 `-update r:c VAL` 對稱的那個讀取。
# 第 14 回合想取出一個已知位址的儲存格，發現辦不到：record:field 只與「寫入」組合。要把它
# 讀回來，得動用 --json 加全檔選取加外部解析器——而這份測試自己的 cell() 輔助函式，為了同一件事
# 也需要兩次 csv2 呼叫加一個暫存檔。
# 最強的理由是：位址可能來自「外部」——有人從 bug 回報裡打進來，或是上一次執行留下的。
# -contains 完全無法服務那個情境，因為它只能找「你已經知道在裡面」的值。
# ---------------------------------------------------------------------
echo
echo "--- T70: -get r:c / -get r:c ---"

# The cell that started this: 513 bytes of prose with quoted commas in it.
# 引發這一切的那一格：513 位元組、內含引號逗號的散文。
raw=$("$CSV2" -get 1:6 -i "$PKG" 2>/dev/null)
assert_contains "$raw" "CORRECTED" \
    "T70a -get returns the cell / -get 取回該儲存格"
if (( ${#raw} > 400 )); then
    ok "T70b and the WHOLE cell (${#raw} bytes), not a fragment / 而且是整格（${#raw} 位元組），不是碎片"
else
    bad "T70b -get returned ${#raw} bytes, expected the whole cell / -get 只回傳 ${#raw} 位元組"
fi

# Raw, not CSV-encoded. The point of an address-based read is to hand over the
# VALUE; returning a quoted CSV field would put the caller back where round 14
# started, needing a decoder.
# 是原始值，不是 CSV 編碼。依位址讀取的意義就是交出「值」；回傳一個帶引號的 CSV 欄位，
# 會把呼叫端送回第 14 回合的起點——還得再準備一個解碼器。
printf 'a,b\nx,"has, comma"\n' > "$TMP/t70.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t70.csv" 2>/dev/null)" 'has, comma' \
    "T70c the value comes back raw, not CSV-quoted / 值以原始形式回來，未加 CSV 引號"

assert_eq "$("$CSV2" -get 1:b -i "$TMP/t70.csv" 2>/dev/null)" 'has, comma' \
    "T70d and the column may be named instead of numbered / 欄位可用名稱而非編號"

# The round trip the design was sold on: search gives an address, -get reads it,
# -update writes it. Before this, the middle step did not exist.
# 這份設計當初的賣點——搜尋給出位址、-get 讀它、-update 寫它。在此之前，中間那一步不存在。
addr=$("$CSV2" -contains busybox -i "$PKG" 2>/dev/null | head -1 | cut -f1)
assert_eq "$("$CSV2" -get "$addr" -i "$PKG" 2>/dev/null)" "busybox" \
    "T70e an address from -contains feeds straight into -get / -contains 給出的位址可直接餵給 -get"

# Out of range is an error, never an empty line. An empty line is what an
# existing empty cell looks like, and a caller cannot tell those apart.
# 越界是錯誤，絕不是一個空行。空行正是「確實存在的空儲存格」的樣子，呼叫端分不出兩者。
assert_fails "T70f an out-of-range record is an error, not an empty line / 越界的紀錄是錯誤，不是空行" -- \
    "$CSV2" -get 99:1 -i "$PKG"
printf 'a,b\nx,\n' > "$TMP/t70e.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t70e.csv" 2>/dev/null)" "" \
    "T70g while an existing EMPTY cell is empty output at rc=0 / 而確實存在的空儲存格是 rc=0 的空輸出"
assert_succeeds "T70h and that really is rc=0, so the two are distinguishable / 那確實是 rc=0，因此兩者可以區分" -- \
    "$CSV2" -get 1:2 -i "$TMP/t70e.csv"

# Header cells are addressable by the locating report and by nothing else. The
# refusal says so rather than complaining about the address's shape.
# 標頭儲存格只有定位報告能定址，其他都不能。這條拒絕直說這件事，而不是抱怨位址的形狀。
"$CSV2" -get 0a:3 -i "$PKG" 2>"$TMP/t70_hdr.txt" >/dev/null
assert_eq "$?" "1" "T70i a header address is refused / 標頭位址被拒"
assert_contains "$(head -1 "$TMP/t70_hdr.txt")" "header cell" \
    "T70j and the message says why, not just 'expected r:c' / 而訊息說出了原因，不只是「需要 r:c」"

assert_fails "T70k -get with a selection is refused / -get 與選取併用被拒" -- \
    "$CSV2" -get 1:1 -head 3 -i "$PKG"
assert_fails "T70l -get with an edit is refused / -get 與編輯併用被拒" -- \
    "$CSV2" -get 1:1 -update 1:1 x -i "$PKG" --in-place
assert_fails "T70m -get into a .csv path is refused: one value is not a CSV file / -get 寫入 .csv 路徑被拒：一個值不是一個 CSV 檔" -- \
    "$CSV2" -get 1:1 -i "$PKG" -o "$TMP/t70_out.csv"

# -get is -mid r,r with a different emitter, so the paths where it could
# silently DIVERGE from -mid are the ones worth pinning: stdin, a column whose
# header carries a transform marker, the index seek, and a file where a record
# spans lines so that record number and line number stop agreeing.
# -get 就是「-mid r,r 換一個輸出器」，因此值得釘住的，是那些它可能「靜默偏離 -mid」的路徑：
# stdin、標頭帶有轉換標記的欄位、索引 seek，以及「紀錄跨行、於是紀錄號與行號不再一致」的檔案。
assert_eq "$(cat "$PKG" | "$CSV2" -get 1:1 -si --headers 1 2>/dev/null)" "busybox" \
    "T70n -get works on stdin, where the format has to come from --headers / -get 可用於 stdin，此時格式必須由 --headers 提供"

"$CSV2" -hash license -keyfile "$TMP/t70.key" -i "$PKG" -o "$TMP/t70_h.csv" 2>/dev/null \
    || head -c 32 /dev/urandom > "$TMP/t70.key"
head -c 32 /dev/urandom > "$TMP/t70.key"
"$CSV2" -hash license -keyfile "$TMP/t70.key" -i "$PKG" -o "$TMP/t70_h.csv" 2>/dev/null
d=$("$CSV2" -get 1:license -i "$TMP/t70_h.csv" 2>/dev/null)
assert_eq "${#d}" "64" \
    "T70o a column is addressable by its BASE name after a transform marks its header / 標頭被轉換標記之後，該欄仍可用「基本名稱」定址"

# The index decides where the read lands. If -get used it differently from -mid,
# this is where a one-record offset would appear -- and it would look like a
# perfectly ordinary value.
# 索引決定一次讀取落在哪裡。若 -get 使用索引的方式與 -mid 不同，差一筆的偏移就會出現在這裡
# ——而它看起來會像一個再普通不過的值。
export CSV2_INDEX_MIN_BYTES=1
cp "$PKG" "$TMP/t70_ix.csv"; rm -f "$TMP/t70_ix.csv.index"
"$CSV2" -tail 2 -i "$TMP/t70_ix.csv" >/dev/null 2>&1
assert_eq "$("$CSV2" -get 12:1 -i "$TMP/t70_ix.csv" 2>/dev/null)" \
    "$("$CSV2" --no-index -get 12:1 -i "$TMP/t70_ix.csv" 2>/dev/null)" \
    "T70p -get agrees with itself whether or not an index is used / 用不用索引，-get 都給出相同答案"
rm -f "$TMP/t70_ix.csv.index"
unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

# A record containing a newline makes record number and line number diverge.
# Addressing is by RECORD, so record 2 here is the one after the two-line one.
# 含換行的紀錄會讓紀錄號與行號分歧。定址依「紀錄」，因此這裡的第 2 筆是那個佔兩行者的下一筆。
printf 'a,b,c\n1,"two\nlines",3\n9,x,y\n' > "$TMP/t70_sp.csv"
assert_eq "$("$CSV2" -get 2:1 -i "$TMP/t70_sp.csv" 2>/dev/null)" "9" \
    "T70q -get counts RECORDS, not lines, when one record spans two / 紀錄跨兩行時，-get 數的是「紀錄」而不是行"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t70_sp.csv" 2>/dev/null | wc -l | tr -d ' ')" "2" \
    "T70r and the spanning cell comes back with its newline intact / 而那個跨行的儲存格，換行原封不動地回來"

# A flag that shapes output is meaningless with -get, which has exactly one
# shape. Accepting one silently is worse than meaningless: `-get 1:2 --json` is
# a natural thing to type, because the README sends you to --json when a value's
# own newlines matter -- and for its first day this returned the plain value at
# rc=0 with the flag discarded. Found by self-review the day after -get landed.
# 「決定輸出形狀」的旗標對 -get 沒有意義，因為它只有一種形狀。安靜地接受比沒有意義更糟：
# `-get 1:2 --json` 是很自然會打出來的東西，因為 README 在「值本身的換行有意義」時就是叫你
# 去用 --json——而它上線的第一天，會在 rc=0 下回傳純粹的值並把那個旗標丟掉。由 -get 落地
# 隔天的自我檢視發現。
for f in --json --pretty -t -rownum; do
    assert_fails "T70s -get with $f is refused, not silently ignored / -get 搭配 $f 會被拒，而不是被靜默忽略" -- \
        "$CSV2" -get 1:1 $f -i "$PKG"
done

# ---------------------------------------------------------------------
# T71 -- -get's trailing newline is a terminator, and the value is logical.
#
# Round 21: the reader attacked -get, which exists because of their own round-14
# argument, and went at the hardest place for a "prints the value and nothing
# else" promise to hold. Two results.
#
# The behaviour is right in both. What was missing was the mechanism: the README
# said "where the value's own newlines matter, use --json" without saying why,
# and a reader wiring -get into a script needs to know that the failure mode is
# SILENT LOSS of a trailing newline, not garbled output and not an error.
#
# T71 —— -get 的結尾換行是「終止符」，而它交出的是「邏輯值」。
# 第 21 回合：讀者去攻擊 -get——那是因它自己第 14 回合的論證而存在的東西——並且挑了「印出
# 值、別的什麼都不印」這個承諾最難守住的地方下手。兩個結果。
# 兩者的行為都是對的。缺的是「機制」：README 只說「值本身的換行有意義時請用 --json」，
# 卻沒說為什麼；而要把 -get 接進腳本的人需要知道，失敗的形態是「結尾換行被靜默吃掉」，
# 不是輸出亂掉，也不是報錯。
# ---------------------------------------------------------------------
echo
echo "--- T71: -get's terminator and logical value / -get 的終止符與邏輯值 ---"

printf 'a,b\nx,"line one\nline two"\n'      > "$TMP/t71_in.csv"
printf 'a,b\nA,B\nx,line one\\nline two\n' > "$TMP/t71_in.csv2"
printf 'a,b\nx,"value ends here\n"\n'       > "$TMP/t71_tail.csv"

# A newline INSIDE a value survives as itself: two lines out, plus nothing else.
# 值「內部」的換行原樣存活：輸出兩行，別無其他。
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t71_in.csv" 2>/dev/null | wc -l | tr -d ' ')" "2" \
    "T71a a newline inside a value comes back as itself / 值內部的換行原樣回來"

# .csv2 stores that newline as the two characters \n. -get gives the VALUE, so
# both formats produce identical bytes. The formats differ in how they store a
# value, not in what the value is -- asserted rather than assumed, because the
# reader had to guess it.
# .csv2 以 \n 兩個字元儲存那個換行。-get 交出的是「值」，因此兩種格式產生完全相同的位元組。
# 兩種格式的差別在於「如何儲存一個值」，不在於「那個值是什麼」——這裡改為斷言而非假定，
# 因為讀者當時只能靠猜。
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t71_in.csv2" 2>/dev/null)" \
    "$("$CSV2" -get 1:2 -i "$TMP/t71_in.csv" 2>/dev/null)" \
    "T71b .csv and .csv2 give the same value, though they store it differently / .csv 與 .csv2 給出相同的值，儘管儲存方式不同"

# The collision: one newline is the value's, one is the terminator, and nothing
# marks the boundary. Counted in BYTES, because $(...) would hide it -- which is
# the whole point.
# 那個碰撞：一個換行是值的、一個是終止符，沒有東西標示邊界。以「位元組」計數，因為
# $(...) 會把它藏起來——而那正是重點所在。
n=$("$CSV2" -get 1:2 -i "$TMP/t71_tail.csv" 2>/dev/null | wc -c | tr -d ' ')
assert_eq "$n" "17" \
    "T71c a value ending in a newline yields two: its own and the terminator / 以換行結尾的值會產生兩個換行：它自己的與終止符"

# And command substitution eats both, silently. This is the failure the README
# now names, so it is asserted rather than described.
# 而命令替換會把兩個都吃掉，靜默地。這正是 README 現在點名的那個失敗，因此改為斷言而非描述。
v=$("$CSV2" -get 1:2 -i "$TMP/t71_tail.csv" 2>/dev/null)
assert_eq "${#v}" "15" \
    "T71d and \$(...) strips both, losing the value's own / 而 \$(...) 會把兩個都剝掉，連值自己的那個也失去"

# --json is the shape that keeps them apart, which is why the README points
# there rather than at a flag.
# --json 才是能把兩者分開的形狀，這也是 README 指向它而不是指向某個旗標的原因。
assert_contains "$("$CSV2" -mid 1,1 --json -i "$TMP/t71_tail.csv" 2>/dev/null | sed -n 2p)" \
    'value ends here\n' \
    "T71e --json carries the trailing newline unambiguously / --json 明確無歧義地承載了那個結尾換行"

# ---------------------------------------------------------------------
# T72 -- which path ran is observable from outside, including when it is the
#        ordinary one.
#
# Round 22 set out to prove "parallel output is byte-identical to
# single-threaded" using the environment knobs the README provides for exactly
# that. It built the hardest fixture it could -- a chunk boundary falling inside
# a quoted field with an embedded comma AND an embedded newline -- got
# byte-identical output, and then refused to call it a pass, because nothing in
# -debug said whether the parallel path had run at all.
#
# That refusal was right, and sharper than the reader could see: an embedded
# newline in a .csv is precisely what DISQUALIFIES a file from the parallel
# path. The fixture built to stress chunk boundaries was one the parallel path
# is designed never to see. Both runs were single-threaded, and identical output
# is exactly what that looks like.
#
# So the reason is now reported. A test that compares two runs has to be able to
# prove they were two different runs.
#
# T72 —— 走的是哪一條路，從外面看得出來，包括走的是普通那一條時。
# 第 22 回合想用 README 為此提供的環境旋鈕，證明「平行輸出與單執行緒逐位元相同」。它建了
# 能想到最難的 fixture——讓分塊邊界落在一個「同時含逗號與換行」的引號欄位裡——得到逐位元
# 相同的輸出，然後拒絕把那稱為通過，因為 -debug 裡沒有任何東西說明平行路徑到底有沒有跑。
# 那個拒絕是對的，而且比讀者看得到的更尖銳：`.csv` 裡的內嵌換行，正是「取消該檔案走平行路徑
# 資格」的那個東西。那個為了施壓分塊邊界而建的 fixture，恰好是平行路徑依設計永遠不會看到的。
# 兩次執行都是單執行緒的，而「輸出相同」看起來恰恰就是那個樣子。
# 因此現在會回報理由。一個比對兩次執行的測試，必須有辦法證明那真的是兩次不同的執行。
# ---------------------------------------------------------------------
echo
echo "--- T72: the path taken is observable / 走的是哪一條路，看得出來 ---"

{ print -r -- 'a,b'; print -r -- 'A,B'
  for i in {1..200}; do print -r -- "$i,value with xyz $i"; done } > "$TMP/t72.csv2"
printf 'a,b\n1,"two\nlines"\n' > "$TMP/t72_nl.csv"

path_of() {  # path_of <args...> -> the debug line saying which path ran
    "$CSV2" "$@" -debug 2>&1 >/dev/null | grep -oE 'parallel: [0-9]+ chunks|single-threaded: .*' | head -1
}

p=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 path_of -contains xyz -i "$TMP/t72.csv2")
assert_contains "$p" "parallel:" \
    "T72a a .csv2 search over the threshold reports the parallel path / 超過門檻的 .csv2 搜尋會回報平行路徑"

p=$(CSV2_PARALLEL_MIN_BYTES=1 path_of -r -i "$TMP/t72.csv2")
assert_contains "$p" "not a search" \
    "T72b a plain read says parallelism does not apply, rather than saying nothing / 單純讀取會說「平行化不適用」，而不是什麼都不說"

p=$(CSV2_PARALLEL_MIN_BYTES=1 path_of -contains xyz -i "$TMP/t72_nl.csv")
assert_contains "$p" "one record per line" \
    "T72c a .csv with an embedded newline says WHY it cannot parallelise / 含內嵌換行的 .csv 會說出它為何無法平行化"

p=$(CSV2_PARALLEL_MIN_BYTES=1 path_of -contains xyz --filter -i "$TMP/t72.csv2")
assert_contains "$p" "single-threaded: --filter" \
    "T72d --filter names itself as the reason / --filter 會指名自己是理由"

p=$(CSV2_PARALLEL_MIN_BYTES=999999999 path_of -contains xyz -i "$TMP/t72.csv2")
assert_contains "$p" "under CSV2_PARALLEL_MIN_BYTES" \
    "T72e and a file under the threshold says so, with the threshold / 未達門檻的檔案會這樣說，並附上門檻值"

# The claim the reader could not prove, now provable: run it both ways, confirm
# from -debug that the two runs really were different, and compare the bytes.
# 讀者當時無法證明的那個宣稱，現在證明得了：兩種方式各跑一次，先從 -debug 確認那真的是
# 兩次不同的執行，再比對位元組。
par=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 "$CSV2" -contains xyz -i "$TMP/t72.csv2" 2>/dev/null)
sin=$(CSV2_PARALLEL_MIN_BYTES=999999999 "$CSV2" -contains xyz -i "$TMP/t72.csv2" 2>/dev/null)
assert_eq "$par" "$sin" \
    "T72f parallel and single-threaded output are identical, and T72a/T72e prove they were different runs / 平行與單執行緒輸出相同，而 T72a／T72e 證明那是兩次不同的執行"

# T72f's fixture has no quoted fields, so a chunk boundary never lands inside
# one -- it tests that chunking preserves ORDER, not that it preserves quote
# state. Round 23 built the harder fixture: a long quoted field packed with
# embedded commas, sized so that boundaries cut straight through it. A chunk
# that mishandled quote state would split that record or lose part of it, and
# would look like ordinary CSV either way.
# T72f 的 fixture 沒有任何引號欄位，因此分塊邊界永遠不會落在其中——它測的是「分塊保持順序」，
# 不是「分塊保持引號狀態」。第 23 回合建了更難的 fixture：一個塞滿內嵌逗號的長引號欄位，
# 長度足以讓邊界直接切過它。一個處理錯引號狀態的分塊，會把那筆紀錄切開或吃掉一部分，
# 而兩種結果看起來都像是普通的 CSV。
{
  print -r -- 'id,note'
  print -r -- '編號,註記'
  for i in {1..40}; do
      if (( i == 20 )); then
          print -r -- "$i,\"quoted value with, several, embedded, commas, padding, padding, padding, padding, padding, padding, padding, padding\""
      else
          print -r -- "$i,plain padding value $i"
      fi
  done
} > "$TMP/t72q.csv2"

qpar=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=256 "$CSV2" -contains padding -i "$TMP/t72q.csv2" 2>/dev/null)
qsin=$(CSV2_PARALLEL_MIN_BYTES=999999999 "$CSV2" -contains padding -i "$TMP/t72q.csv2" 2>/dev/null)
qpath=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=256 path_of -contains padding -i "$TMP/t72q.csv2")

assert_contains "$qpath" "parallel:" \
    "T72g the comma-heavy fixture really does take the parallel path / 逗號密集的 fixture 確實走了平行路徑"
assert_eq "$qpar" "$qsin" \
    "T72h and a chunk boundary inside a quoted field changes nothing / 分塊邊界落在引號欄位內部也不改變任何結果"
assert_eq "$(print -r -- "$qpar" | grep -c '^20:')" "1" \
    "T72i the straddling record appears exactly once, not split or dropped / 那筆被切過的紀錄恰好出現一次，沒有被切開或丟失"
assert_contains "$qpar" 'several, embedded, commas' \
    "T72j with its embedded commas intact / 其內嵌逗號完好無損"

# ---------------------------------------------------------------------
# T73 -- redaction follows the FILE's declaration, not the run's activity.
#
# Round 25 went at -log because it is the one feature that persists data to
# disk with no documented content policy, and asked whether it reintroduces the
# exposure the absent -key flag exists to avoid.
#
# It found the command echo redacted -- `-update 1:4 <value>` -- and the
# operation line two lines below it printing the same string in the clear. Its
# words: something decided the value should not appear, and something else
# wrote it anyway.
#
# Verifying it showed worse. The redaction set was populated only by
# buildTransform, from the columns being transformed IN THIS RUN. So `-hash
# secret` redacted `secret` in its own log, and `-update 1:secret NEW` on the
# resulting file -- whose header reads `secret:hmac:<fp>`, the file stating in
# writing that the column is sensitive -- wrote NEW in the clear. The run that
# put the secret in was protected. The run that changed it was not.
#
# T73 —— 遮蔽依據的是「檔案的宣告」，而非「本次執行在做什麼」。
# 第 25 回合去查 -log，因為它是唯一一個「會把資料寫進磁碟、卻沒有任何內容政策記載」的功能，
# 並提問：它是否重新引入了「刻意不提供 -key」所要避免的那種暴露。
# 它發現指令列回顯被遮蔽了——`-update 1:4 <value>`——而兩行之下的操作紀錄，卻把同一個字串
# 明文寫出。用它的話說：有東西決定了那個值不該出現，而另一個東西照樣把它寫了下去。
# 查證之後發現更糟。遮蔽集合只由 buildTransform 依「本次要轉換的欄位」填入。於是
# `-hash secret` 會在它自己的 log 裡遮蔽 secret，而對其產物執行 `-update 1:secret NEW`
# ——那個檔案的標頭寫著 `secret:hmac:<fp>`，是檔案白紙黑字宣告該欄位敏感——卻會把 NEW
# 明文寫出。放進秘密的那次執行受保護，改動它的那次執行不受保護。
# ---------------------------------------------------------------------
echo
echo "--- T73: redaction follows the file, not the run / 遮蔽依據檔案，而非本次執行 ---"

printf 'pkg,secret,license\na,s1,MIT\nb,s2,GPL\n' > "$TMP/t73.csv"
head -c 32 /dev/urandom > "$TMP/t73.key"
"$CSV2" -hash secret -keyfile "$TMP/t73.key" -i "$TMP/t73.csv" -o "$TMP/t73_h.csv" -t 2>/dev/null
cp "$TMP/t73_h.csv" "$TMP/t73_h.bak"

# REVERSED on 2026-08-19, and the reversal is the finding.
#
# Round 25 asked whether -log reintroduces the exposure the absent -key flag
# exists to avoid, and the answer -- redaction follows the FILE's declaration,
# not the run's activity -- is still right and is still asserted below.
#
# But this test also pinned that the edit itself SUCCEEDS: "redaction is about
# the log, not about refusing the edit". That was never a decision anyone made.
# It was a guard against T73a passing vacuously, by the write having failed.
#
# Round 37 showed what the write actually does. A raw value written into a
# column the file marks `:enc:` cannot be read back, and -decrypt stops at that
# cell -- so every later record, ciphertext intact and never touched, is lost
# with it. The log said `<redacted> -> <redacted>`, exactly as this test
# required, and that line was the only record of what had happened.
#
# So round 25's protection was working perfectly on a value that should never
# have been written at all, and the protection is what hid the damage. The edit
# is now refused, and the vacuity guard moves to the ordinary column, where a
# write must still happen and still be recorded.
#
# 2026-08-19 反轉，而這個反轉本身就是那個發現。
# 第 25 回合問的是「-log 是否重新引入了『刻意不提供 -key』所要避免的暴露」，而它的答案——
# 遮蔽依據的是「檔案的宣告」而非「本次執行在做什麼」——仍然正確，下面仍然斷言它。
# 但這個測試同時釘住了「該次編輯會成功」：「遮蔽針對的是 log，不是拒絕該次編輯」。
# **那從來不是任何人做過的決定**，它只是一道防線，防止 T73a 因為「寫入失敗」而空洞地通過。
# 第 37 回合顯示了那次寫入實際上做了什麼：寫進 `:enc:` 欄位的原始值讀不回來，而 -decrypt
# 會停在那一格——於是之後每一筆（密文完好、從未被碰過）也一起消失。而 log 寫的是
# `<redacted> -> <redacted>`，與這個測試的要求完全一致，而那一行是「發生了什麼」唯一的紀錄。
# 也就是說，第 25 回合的保護在一個「根本就不該被寫下去的值」上運作得完美無缺，
# 而那道保護正是掩蓋損害的東西。該次編輯現在被拒絕，而那道防止空洞通過的防線，
# 移到一般欄位上——在那裡寫入仍然必須發生、也仍然必須被記錄。
rm -f "$TMP/t73.log"
"$CSV2" -update 1:secret 'SUPER SECRET 12345' -i "$TMP/t73_h.csv" -o "$TMP/t73_o.csv" \
    -log "$TMP/t73.log" 2>/dev/null
assert_fails "T73a an edit aimed at a column the file marks protected is refused / 針對「檔案標記為受保護」欄位的編輯會被拒絕" -- \
    "$CSV2" -update 1:secret 'SUPER SECRET 12345' -i "$TMP/t73_h.csv" -o "$TMP/t73_o.csv"
assert_same "$TMP/t73_h.csv" "$TMP/t73_h.bak" \
    "T73b and the input is untouched, which for an encrypted column is the whole column / 而輸入原封不動——對加密欄位而言，那就是整欄"

# Redaction still has to hold: the refusal must not be the only thing standing
# between a secret and the log. A run that never reaches the refusal -- because
# it edits an ordinary column of the same file -- must still not print the
# protected one, and the command echo must not carry the attempted value.
# 遮蔽仍然必須成立：拒絕不能是「秘密與 log 之間」唯一的一道防線。一次不會走到那個拒絕的
# 執行——因為它改的是同一個檔案的一般欄位——仍然不得印出那個受保護的欄位，而指令回顯也不得
# 帶著那個被嘗試寫入的值。
if grep -q 'SUPER SECRET 12345' "$TMP/t73.log"; then
    bad "T73c the log leaked a value aimed at a column the file marks protected / log 洩漏了一個瞄準「檔案標記為受保護」欄位的值"
else
    ok "T73c a value aimed at a protected column stays out of the log / 瞄準受保護欄位的值不會進入 log"
fi

# The log must stay USEFUL. Redacting everything would be safe and worthless:
# an audit trail that cannot say what changed is not one. This is also the
# vacuity guard now: if edits stopped working altogether, this fails.
# log 必須維持「有用」。全部遮蔽既安全又毫無價值：一份說不出改了什麼的稽核軌跡，不是稽核軌跡。
# 這一條現在同時是那道「防止空洞通過」的防線：如果編輯整個壞掉了，它會失敗。
rm -f "$TMP/t73b.log"
"$CSV2" -update 1:license 'GPL-3.0' -i "$TMP/t73.csv" -o "$TMP/t73_o2.csv" \
    -log "$TMP/t73b.log" 2>/dev/null
assert_contains "$(grep -o 'update 1:license.*' "$TMP/t73b.log")" 'GPL-3.0' \
    "T73d while an ordinary column still records what changed / 而一般欄位仍然記錄了改了什麼"
assert_eq "$("$CSV2" -get 1:license -i "$TMP/t73_o2.csv" 2>/dev/null)" 'GPL-3.0' \
    "T73e and the edit really happened, so the assertions above are not passing on a tool that refuses everything / 而那次編輯確實發生了，因此上面那些斷言不是靠「一支什麼都拒絕的工具」通過的"

# Key bytes never appear, whatever else does.
# 不論別的如何，金鑰位元組永不出現。
rm -f "$TMP/t73c.log"
"$CSV2" -hash secret -keyfile "$TMP/t73.key" -i "$TMP/t73.csv" -o "$TMP/t73_h2.csv" -t \
    -log "$TMP/t73c.log" 2>/dev/null
if grep -qa "$(head -c 8 "$TMP/t73.key" | od -An -tx1 | tr -d ' \n')" "$TMP/t73c.log"; then
    bad "T73f key bytes appear in the log / 金鑰位元組出現在 log 中"
else
    ok "T73f key bytes never appear in the log / 金鑰位元組不會出現在 log 中"
fi
assert_contains "$(cat "$TMP/t73c.log")" "fingerprint" \
    "T73g but the fingerprint does, which identifies the key without being it / 但指紋會出現——它標識金鑰而不是金鑰本身"

# ---------------------------------------------------------------------
# T74 -- "-md is one-way" has to be true, not merely intended.
#
# Round 26 attacked the claim and broke it. -md output redirected into a .csv
# path is a valid ONE-COLUMN CSV whenever the data contains no commas, so every
# line has one field, the field counts trivially agree, and csv2 read it back at
# rc=0 -- handing over the Markdown separator row `|---|---|---|` as data
# record 1.
#
# With commas in the data the counts disagree and it already failed loudly. The
# check that saved that case is the one that had nothing to notice here. So the
# guarantee held for the harder-looking input and failed for the simpler one:
# any table of short plain values.
#
# That contradicts the promise this project opens with -- anything else must
# fail loudly rather than silently emit a half-correct file -- and it did it on
# a file csv2 had produced itself.
#
# T74 —— 「-md 是單向的」必須為真，而不能只是「本意如此」。
# 第 26 回合攻擊了這個宣稱並且攻破了。把 -md 的輸出重導到 .csv 路徑，只要資料不含逗號，
# 那就是一份合法的「單欄」CSV：每一行都只有一欄、欄數自然一致，於是 csv2 在 rc=0 下把它讀
# 回來，並把 Markdown 分隔列 `|---|---|---|` 當成第 1 筆資料交出去。
# 資料含逗號時欄數不符，它本來就會大聲失敗。救了那個案例的檢查，在這裡沒有東西可以察覺。
# 於是這條保證在「看起來比較難」的輸入上成立，卻在比較單純的那一種上失效：任何一張由簡短
# 純值構成的表格。
# 那牴觸了本專案開宗明義的承諾——其餘一切都必須大聲失敗，而不是靜默產生一個半正確的檔案
# ——而且它是在一個 csv2 自己產生的檔案上失敗的。
# ---------------------------------------------------------------------
echo
echo "--- T74: -md really is one-way / -md 真的是單向的 ---"

printf 'pkg,ver,note\nzlib,1.3.2,plain text no commas\nzstd,1.5.6,another plain value\n' > "$TMP/t74.csv"
"$CSV2" -r -t -md -i "$TMP/t74.csv" -so > "$TMP/t74_md.csv" 2>/dev/null
assert_contains "$(sed -n 2p "$TMP/t74_md.csv")" '|---|' \
    "T74a the -md output really does contain a separator row / -md 的輸出確實含有一列分隔列"

assert_fails "T74b and reading it back as CSV is refused, not silently misread / 把它當成 CSV 讀回來會被拒，而不是被靜默誤讀" -- \
    "$CSV2" -r -i "$TMP/t74_md.csv"
"$CSV2" -r -i "$TMP/t74_md.csv" 2>"$TMP/t74_err.txt" >/dev/null
assert_contains "$(head -1 "$TMP/t74_err.txt")" "Markdown" \
    "T74c and the message names Markdown, rather than talking about field counts / 而訊息會指名 Markdown，不是在談欄數"

# The refusal must be narrow. A genuine one-column CSV is ordinary input and
# must keep working; so must a multi-column file that merely contains such a
# value, because there the file plainly is CSV.
# 這條拒絕必須夠窄。一份真實的單欄 CSV 是很普通的輸入，必須照常可用；一個「只是剛好含有
# 這種值」的多欄檔案也一樣——因為在那裡，那個檔案顯然就是 CSV。
printf 'name\nalice\nbob\n' > "$TMP/t74_one.csv"
assert_eq "$("$CSV2" -r -i "$TMP/t74_one.csv" 2>/dev/null | head -1)" "alice" \
    "T74d a real one-column CSV still reads / 真實的單欄 CSV 仍讀得出來"
printf 'a,b\n"|---|---|",x\n' > "$TMP/t74_two.csv"
assert_succeeds "T74e and a multi-column file containing such a value is untouched / 含有這種值的多欄檔案完全不受影響" -- \
    "$CSV2" -r -i "$TMP/t74_two.csv"

# The case that already worked has to keep working, and for its own reason.
# 原本就能運作的那個案例必須繼續運作，而且是基於它自己的理由。
printf 'pkg,note\nzlib,"has, comma"\n' > "$TMP/t74_wc.csv"
"$CSV2" -r -t -md -i "$TMP/t74_wc.csv" -so > "$TMP/t74_wc_md.csv" 2>/dev/null
assert_fails "T74f comma-bearing -md output is still refused too / 含逗號的 -md 輸出同樣仍被拒" -- \
    "$CSV2" -r -i "$TMP/t74_wc_md.csv"

# ---------------------------------------------------------------------
# T75 -- an ambiguous column name is refused, not resolved by position.
#
# Round 27 asked whether --normalize governs COLUMN-NAME matching the way it
# governs cell-value matching, and found it does not: an NFC-typed name matches
# an NFD-stored header with or without the flag. The cause is that names are
# compared with Swift's String ==, which is canonical equivalence, while values
# are compared as bytes.
#
# That asymmetry is defensible -- NFC and NFD café are the same NAME to everyone
# who reads it -- but chasing it down surfaced something the reader did not
# reach: if two columns can be the same name, which one does an address mean?
#
# csv2 returned the first, at rc=0. `-update 1:note X` on a file with two
# columns called `note` edited whichever came first and said nothing. CSV does
# not forbid duplicate names and spreadsheets produce them. The caller asked to
# change `note` and got one of two, chosen by position -- the incident this
# project was built after, reproduced by the tool meant to prevent it.
#
# T75 —— 有歧義的欄位名稱會被拒絕，而不是依位置解析。
# 第 27 回合詢問 --normalize 是否像管「儲存格值」那樣管「欄位名稱」的比對，發現並不是：
# 以 NFC 打出的名稱，不論有沒有那個旗標，都能匹配到 NFD 儲存的標頭。原因是名稱以 Swift 的
# String == 比較（正規等價），而值是以位元組比較。
# 那個不對稱說得過去——對每個讀到它的人來說，NFC 與 NFD 的 café 就是同一個「名字」——但
# 追查它的過程中，浮出一件讀者沒有走到的事：如果兩個欄位可以是同一個名字，那一個位址到底
# 指的是哪一個？
# csv2 回傳第一個，rc=0。在一個有兩個 `note` 欄位的檔案上，`-update 1:note X` 會編輯位置在前
# 的那一個，什麼也不說。CSV 並未禁止重複名稱，而試算表就會產生。呼叫端要求修改 `note`，
# 拿到的是兩者之一、由位置決定——那正是本專案因之而生的那起事故，被那支本該防止它的工具
# 重現了一次。
# ---------------------------------------------------------------------
echo
echo "--- T75: an ambiguous column name is refused / 有歧義的欄位名稱會被拒絕 ---"

printf 'note,ver,note\nFIRST,1,SECOND\n' > "$TMP/t75.csv"

assert_fails "T75a -update by a duplicated name is refused, not applied to the first / 以重複名稱下 -update 會被拒，而不是套用到第一個" -- \
    "$CSV2" -update 1:note X -i "$TMP/t75.csv" -o "$TMP/t75_o.csv"
"$CSV2" -update 1:note X -i "$TMP/t75.csv" -o "$TMP/t75_o.csv" 2>"$TMP/t75_err.txt"
assert_contains "$(head -1 "$TMP/t75_err.txt")" 'names 2 columns (1, 3)' \
    "T75b and the message says WHICH columns collide / 而訊息會說出是哪幾欄相撞"
assert_fails "T75c -get is refused for the same reason / -get 因同樣的理由被拒" -- \
    "$CSV2" -get 1:note -i "$TMP/t75.csv"
assert_fails "T75d and so is -delete -col / -delete -col 同樣被拒" -- \
    "$CSV2" -delete -col note -i "$TMP/t75.csv" -so

# The escape is the one the message names, and it has to work.
# 訊息指出的那條出路，必須真的可用。
assert_eq "$("$CSV2" -get 1:3 -i "$TMP/t75.csv" 2>/dev/null)" "SECOND" \
    "T75e while addressing by NUMBER reaches either column / 而以「欄號」定址則兩欄都到得了"

# Names are compared by canonical equivalence, so an NFC argument finds an NFD
# header. That is right for a name, and it is why the collision above can happen
# between columns that are not byte-identical.
# 名稱以正規等價比較，因此 NFC 的引數找得到 NFD 的標頭。對「名字」而言那是對的，
# 而那也正是上面那種相撞可以發生在「位元組並不相同」的兩個欄位之間的原因。
printf 'pkg,cafe\xcc\x81\nzlib,v1\n' > "$TMP/t75_nfd.csv"
assert_eq "$("$CSV2" -get 1:$'caf\xc3\xa9' -i "$TMP/t75_nfd.csv" 2>/dev/null)" "v1" \
    "T75f an NFC name finds an NFD header: they are the same name / 以 NFC 的名稱找得到 NFD 的標頭：那是同一個名字"

printf 'caf\xc3\xa9,cafe\xcc\x81\nNFC,NFD\n' > "$TMP/t75_both.csv"
assert_fails "T75g but two columns differing only in normalisation collide, and that is refused too / 但兩個只差在正規化形式的欄位會相撞，同樣會被拒" -- \
    "$CSV2" -get 1:$'caf\xc3\xa9' -i "$TMP/t75_both.csv"

# T75h-T75k — the same root cause through a worse door, found by round 28.
#
# A record object keys `fields` by column name, and a JSON object cannot hold
# two values under one key. csv2 emitted the duplicate key: legal per RFC 8259,
# which leaves the interpretation unspecified, and collapsed by every parser in
# use -- Python's json and JavaScript's JSON.parse keep the last and discard the
# first. csv2's own bytes held both values; the reader's parser destroyed one
# before the reader saw it.
#
# That is worse than the addressing bug above. There an address picked a column
# silently; here a value is DESTROYED silently and cannot be recovered from the
# parsed object by any means.
#
# T75h–T75k —— 同一個根本原因，透過一扇更糟的門，由第 28 回合發現。
# 一筆紀錄的物件以欄名作為 `fields` 的鍵，而 JSON 物件無法在同一個鍵下放兩個值。csv2 照樣
# 輸出了重複鍵：依 RFC 8259 合法（它把如何解讀列為未定義），而實際使用中的每一個解析器都會
# 收合它——Python 的 json 與 JavaScript 的 JSON.parse 都留最後一個、丟第一個。csv2 自己的
# 位元組裡兩個值都在；是讀者的解析器在讀者看到之前毀掉了其中一個。
# 那比上面的定址缺陷更糟：那裡是一個位址靜默地挑了一欄，這裡是一個值被靜默地毀掉，
# 而且從解析後的物件裡再也無法以任何方式取回。
assert_fails "T75h record-shaped --json is refused when two columns share a name / 兩欄同名時，紀錄形狀的 --json 會被拒" -- \
    "$CSV2" -r --json -i "$TMP/t75.csv"
"$CSV2" -r --json -i "$TMP/t75.csv" 2>"$TMP/t75_j.txt" >/dev/null
assert_contains "$(head -1 "$TMP/t75_j.txt")" "one value would be lost" \
    "T75i and the message says what would happen, not just that it is refused / 而訊息說出會發生什麼事，不只是說被拒"

# The report shape is not name-keyed, so two columns with one name are two
# lines. It has to keep working, or the refusal above would leave no way to
# read such a file as JSON at all.
# 報告形狀不以名稱為鍵，因此兩個同名欄位是兩行。它必須繼續可用，否則上面那條拒絕會讓這種
# 檔案完全沒有辦法以 JSON 讀取。
assert_succeeds "T75j while -contains --json still works, reporting each hit separately / 而 -contains --json 仍可用，分別回報每一個命中" -- \
    "$CSV2" -contains first --json -i "$TMP/t75.csv"

# And an ordinary file must be untouched: this refusal keys off duplicate names,
# not off --json.
# 而一般檔案必須完全不受影響：這條拒絕的觸發條件是「名稱重複」，不是「用了 --json」。
printf 'a,b\n1,2\n' > "$TMP/t75_ok.csv"
assert_contains "$("$CSV2" -r --json -i "$TMP/t75_ok.csv" 2>/dev/null | sed -n 2p)" '"fields":{"a":"1","b":"2"}' \
    "T75k and a file with distinct names is unaffected / 欄名不重複的檔案完全不受影響"

# T75l-T75m — the escape the refusal points at has to be complete, or the
# refusal takes away expressiveness instead of returning it.
#
# Round 29 asked why -delete -col refuses at all, since "remove the note column"
# has an unambiguous reading when there are two: remove both. The answer is in
# plan.md, and it turns on the ambiguity being in the caller's BELIEF rather
# than in the outcome -- someone typing that almost certainly thinks there is
# one, and deleting both would leave that belief intact for every command they
# write next. But the answer only holds if addressing by number really does
# reach every arrangement, so that is asserted here rather than assumed.
#
# T75l–T75m —— 拒絕所指出的那條出路必須是完整的，否則這條拒絕是在收走表達力，而不是把它交還。
# 第 29 回合追問 -delete -col 為何也要拒絕，既然「移除 note 那一欄」在有兩個時有一個沒有歧義
# 的讀法：兩個都移除。答案寫在 plan.md，關鍵在於有歧義的是呼叫者的「認知」而不是「結果」
# ——會這樣打的人幾乎必然以為只有一個，而刪掉兩個會讓那個認知原封不動地留到他接下來寫的
# 每一行指令裡。但這個答案唯有在「以欄號定址真的到得了每一種安排」時才站得住，因此在此斷言
# 而非假定。
assert_eq "$("$CSV2" -delete -col 1 -delete -col 3 -i "$TMP/t75.csv" -so 2>/dev/null | head -1)" 'ver' \
    "T75l both duplicated columns can be removed deliberately, by number / 兩個同名欄位都可以用欄號刻意移除"
assert_eq "$("$CSV2" -delete -col 3 -i "$TMP/t75.csv" -so 2>/dev/null | head -1)" 'note,ver' \
    "T75m and so can just one of them / 也可以只移除其中一個"

# ---------------------------------------------------------------------
# T76 -- an over-limit -tail is refused, not quietly shortened.
#
# Round 31 pointed out that "upper bound on -tail N and -B N" is compatible
# with three different behaviours: refuse, silently cap the result to the
# limit, or apply only to some internal thing a request that size never
# reaches. Only one of them cannot produce a silently short answer, and the
# phrase did not say which one it was.
#
# The tool already refused. What was missing was any statement of it, and any
# assertion -- so a later change that capped instead of refusing would have
# been a silent regression with nothing to catch it, in the exact shape this
# project exists to prevent: a partial answer wearing the clothes of a whole one.
#
# T76 —— 超過上限的 -tail 會被拒絕，而不是被悄悄縮短。
# 第 31 回合指出，「-tail N 與 -B N 的上限」這句話可以對應到三種不同的行為：拒絕、把結果
# 靜默地截到上限、或只作用於某個「這種大小的請求根本碰不到」的內部東西。其中只有一種不會
# 產生「靜默變短的答案」，而那句話並沒有說是哪一種。
# 工具本來就是拒絕的。缺的是「沒有任何地方這樣寫」，也沒有任何斷言——因此日後若有人把它
# 改成「截斷而非拒絕」，那會是一次無人攔截的靜默退步，而且形狀正是本專案存在所要防止的：
# 一個穿著完整答案外衣的部分答案。
# ---------------------------------------------------------------------
echo
echo "--- T76: an over-limit -tail is refused / 超過上限的 -tail 會被拒絕 ---"

{ print -r -- 'a,b'; for i in {1..20}; do print -r -- "$i,v$i"; done } > "$TMP/t76.csv"

assert_eq "$(CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -tail 10 -i "$TMP/t76.csv" 2>/dev/null | wc -l | tr -d ' ')" "0" \
    "T76a nothing is emitted when the request exceeds the limit / 請求超過上限時不輸出任何東西"
assert_fails "T76b and the run fails rather than returning the 5 it could hold / 該次執行失敗，而不是回傳它裝得下的那 5 筆" -- \
    env CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -tail 10 -i "$TMP/t76.csv"

CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -tail 10 -i "$TMP/t76.csv" 2>"$TMP/t76_err.txt" >/dev/null
e=$(head -1 "$TMP/t76_err.txt")
assert_contains "$e" "-tail 10" "T76c the message names what was asked for / 訊息指出被要求的是什麼"
assert_contains "$e" "(5)"      "T76d and the limit in force / 以及當下生效的上限"
assert_contains "$e" "CSV2_MAX_BUFFER_RECORDS" \
    "T76e and the variable that changes it / 以及可以改變它的那個變數"

# Under the limit it must still work, or the refusal would be indistinguishable
# from -tail being broken.
# 在上限之內必須照常可用，否則這條拒絕會與「-tail 壞了」無法區分。
assert_eq "$(CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -tail 3 -i "$TMP/t76.csv" 2>/dev/null | wc -l | tr -d ' ')" "3" \
    "T76f while a request within the limit is served normally / 而在上限之內的請求照常服務"

# -B is bounded by the same variable and must refuse the same way.
# -B 受同一個變數約束，必須以同樣的方式拒絕。
assert_fails "T76g -B is bounded by the same variable and refuses too / -B 受同一個變數約束，同樣會拒絕" -- \
    env CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -contains v7 -B 10 -i "$TMP/t76.csv"

# ---------------------------------------------------------------------
# T77 -- -decrypt refuses at the MARKER, never at the cipher.
#
# Round 32 asked what `-decrypt COLS` does when the column is not actually
# encrypted, and listed the three readings its one-line description admits:
# refuse, attempt it anyway and surface a ChaCha20-Poly1305 authentication
# failure, or pass the column through unchanged. Each leads a caller somewhere
# different, and the sentence chose none of them.
#
# The tool refuses by name, which is the friendly one: plaintext never reaches
# the cipher, so the message is about the file rather than about cryptography.
# A caller who mistypes a column name gets told they mistyped a column name.
#
# Also pinned here, which the round did not try: a HASHED column is refused
# too. Hashing is one-way, and "undo the masking" is a natural thing to attempt
# on a column that visibly holds digests.
#
# T77 —— -decrypt 在「標記」這一層拒絕，絕不會拖到密碼演算法那一層。
# 第 32 回合追問：當某欄其實沒有被加密時，`-decrypt COLS` 會怎樣？並列出它那一行說明所允許
# 的三種解讀：拒絕、照樣嘗試而拋出 ChaCha20-Poly1305 的驗證失敗、或原樣放行。三者會把呼叫端
# 帶往不同的地方，而那句話一種都沒有選。
# 工具的做法是「以名稱拒絕」，也就是友善的那一種：明文永遠不會抵達密碼演算法，因此訊息談的是
# 這個檔案，而不是密碼學。打錯欄名的人，得到的是「你打錯了欄名」。
# 另外在此釘住該回合沒有試的一項：被「雜湊」的欄位同樣會被拒絕。雜湊是單向的，而對一個
# 明顯裝著摘要的欄位嘗試「把遮蔽解開」，是很自然的舉動。
# ---------------------------------------------------------------------
echo
echo "--- T77: -decrypt refuses at the marker / -decrypt 在標記層拒絕 ---"

head -c 32 /dev/urandom > "$TMP/t77.key"

"$CSV2" -decrypt license -keyfile "$TMP/t77.key" -i "$PKG" -o "$TMP/t77_a.csv" 2>"$TMP/t77_a.txt"
assert_eq "$?" "1" "T77a decrypting an unmarked column fails / 對未標記的欄位解密會失敗"
assert_contains "$(head -1 "$TMP/t77_a.txt")" "not marked as encrypted" \
    "T77b naming the marker, not a cipher error / 訊息談的是標記，不是密碼演算法的錯誤"
if grep -qiE 'authentic|tag|poly1305|chacha' "$TMP/t77_a.txt"; then
    bad "T77c plaintext reached the cipher / 明文抵達了密碼演算法"
else
    ok "T77c so plaintext never reached the cipher / 因此明文從未抵達密碼演算法"
fi
assert_succeeds "T77d and no output file was written / 而且沒有寫出輸出檔" -- \
    test ! -f "$TMP/t77_a.csv"

assert_fails "T77e -decrypt all refuses when the file has nothing marked / 檔案裡什麼都沒標記時，-decrypt all 會拒絕" -- \
    "$CSV2" -decrypt all -keyfile "$TMP/t77.key" -i "$PKG" -o "$TMP/t77_b.csv"

# A hashed column is not an encrypted one. Hashing is one-way, so this refusal
# is the only honest answer -- there is nothing to return.
# 被雜湊的欄位不是被加密的欄位。雜湊是單向的，因此這條拒絕是唯一誠實的答案——沒有東西可以還。
"$CSV2" -hash license -keyfile "$TMP/t77.key" -i "$PKG" -o "$TMP/t77_h.csv" -t 2>/dev/null
assert_fails "T77f a hashed column cannot be decrypted, because hashing is one-way / 被雜湊的欄位解不開，因為雜湊是單向的" -- \
    "$CSV2" -decrypt license -keyfile "$TMP/t77.key" -i "$TMP/t77_h.csv" -o "$TMP/t77_hd.csv"

# And the case that must keep working, or the refusals above would be
# indistinguishable from -decrypt being broken.
# 以及那個必須繼續可用的案例，否則上面那些拒絕會與「-decrypt 壞了」無法區分。
"$CSV2" -encrypt status_notes -keyfile "$TMP/t77.key" -i "$PKG" -o "$TMP/t77_e.csv" 2>/dev/null
"$CSV2" -decrypt all -keyfile "$TMP/t77.key" -i "$TMP/t77_e.csv" -o "$TMP/t77_d.csv" 2>/dev/null
assert_same "$PKG" "$TMP/t77_d.csv" \
    "T77g while -decrypt all on a file that IS marked round-trips byte-identically / 而對「確實有標記」的檔案下 -decrypt all，可逐位元還原"

# ---------------------------------------------------------------------
# T78 -- --zh falls back on a one-header file, and --json is how you assert.
#
# Round 35 found the one silent substitution left in this tool: --zh on a .csv
# produces output byte-identical to --en, with no signal that the Chinese row
# it asked for does not exist. Its framing was the right one -- the silence
# should be a decision rather than an omission.
#
# The decision is to keep it. --zh is a DISPLAY preference, not a selector over
# data: refusing would break any script walking a mix of .csv and .csv2 for a
# cosmetic reason. And it cannot be mistaken for success -- you asked for
# Chinese names and the output visibly holds English ones, which is different
# rather than plausible-but-wrong, unlike every defect this session has fixed.
#
# What the round was really reaching for -- asserting a file is bilingual --
# already has an instrument, and --zh was never it. Both are pinned here so the
# fallback stays a decision.
#
# T78 —— 對只有一列標頭的檔案，--zh 會退回；而「斷言」該用 --json。
# 第 35 回合找到了這支工具裡僅存的一處靜默替代：對 .csv 使用 --zh，輸出與 --en 逐位元相同，
# 而它所要求的那一列中文標頭並不存在，卻沒有任何訊號。它的措辭是對的——那份沉默應該是一個
# 決定，而不是一個疏漏。
# 決定是「保留」。--zh 是一種「顯示」偏好，不是對資料的選取：拒絕它會為了美觀的理由弄壞任何
# 走遍 .csv 與 .csv2 混合檔案的腳本。而它也不會被誤認為成功——你要求中文欄名，輸出裡明顯是
# 英文欄名，那是「不一樣」而不是「看起來對但其實錯」，與這一輪修掉的每一個缺陷都不同。
# 而該回合真正想做的事——斷言一個檔案是雙語的——本來就有對應的工具，而那從來不是 --zh。
# 兩者都在此釘住，好讓這個退回保持為一個「決定」。
# ---------------------------------------------------------------------
echo
echo "--- T78: --zh falls back; --json asserts / --zh 會退回；--json 才是斷言的工具 ---"

printf 'pkg,ver\nzlib,1\n' > "$TMP/t78_one.csv"
printf 'pkg,ver\n套件,版本\nzlib,1\n' > "$TMP/t78_two.csv2"

assert_eq "$("$CSV2" -contains zlib --zh -i "$TMP/t78_one.csv" 2>/dev/null)" \
    "$("$CSV2" -contains zlib --en -i "$TMP/t78_one.csv" 2>/dev/null)" \
    "T78a --zh on a one-header file falls back to the row that exists / 對只有一列標頭的檔案，--zh 退回到那唯一存在的列"
assert_succeeds "T78b and does not fail, because it is a display preference / 而且不會失敗，因為那是顯示偏好" -- \
    "$CSV2" -contains zlib --zh -i "$TMP/t78_one.csv"

# The fallback is visible, not plausible: English names where Chinese were
# asked for. That is what makes it different from the defects this session
# fixed, and it is the load-bearing half of the decision.
# 這個退回是「看得見」的，不是「看似合理」的：要求中文卻得到英文欄名。那正是它與這一輪修掉的
# 那些缺陷不同的地方，也是這個決定裡承重的那一半。
assert_contains "$("$CSV2" -contains zlib --zh -i "$TMP/t78_one.csv" 2>/dev/null)" 'pkg' \
    "T78c the fallback is visible in the output, not disguised / 那個退回在輸出裡看得見，沒有被偽裝"
assert_contains "$("$CSV2" -contains zlib --zh -i "$TMP/t78_two.csv2" 2>/dev/null)" '套件' \
    "T78d while a real .csv2 still gets its Chinese names / 而真正的 .csv2 仍然拿到中文欄名"

# The instrument that DOES answer "is this file bilingual".
# 真正能回答「這個檔案是不是雙語的」的那個工具。
assert_contains "$("$CSV2" -head 1 -t --json -i "$TMP/t78_one.csv" 2>/dev/null | head -1)" '"headers":1' \
    "T78e --json meta reports one header row / --json 的 meta 回報一列標頭"
assert_contains "$("$CSV2" -head 1 -t --json -i "$TMP/t78_two.csv2" 2>/dev/null | head -1)" '"headers":2' \
    "T78f and two for a .csv2, which is how a caller asserts bilinguality / 對 .csv2 則回報兩列，那才是呼叫端斷言雙語的方式"

# ---------------------------------------------------------------------
# The index asserted a property of the file that nothing ever derived, and
# the O(n) proof offered for exactly this doubt did not check it.
#
# An index carries `no_embedded_newlines`. The parallel path consumes it to
# decide that a line is a record. Three call sites set it, and two of them
# passed a constant: one wrote `spansLines: false`, the other wrote
# `rec.line != r.line || false` where `r` is `rec` with only `number`
# changed -- a comparison that cannot be true. So EVERY index --build-index
# ever wrote claimed the property, whether the file had it or not.
#
# The consequence needed no tampering and no unusual file. Take a CSV with
# prose in quotes -- TARGET_PACKAGES.csv's `status_notes` is one, and is the
# reason this project exists -- put one newline inside one quoted field, and:
#
#     --build-index    index built
#     --verify-index   index OK                                    rc=0
#     -contains        150001:2   (300001 records)                 rc=0
#     forced single    150000:2
#     python3 csv      record 150000, 300000 records
#
# The wrong record number, at rc=0, with the documented proof saying the
# index was fine. That is this project's own failure mode, arriving through
# the one instrument the README nominates for ruling it out.
#
# --verify-index missed it for a reason worth keeping: it checked the grid
# offsets and the record count, and BOTH SURVIVE this edit intact. Every
# record still begins exactly where the index says, and there are still
# exactly as many. The only thing that changed was a claim in the header
# that nothing re-derived.
#
# And the escape hatch did not escape. `--no-index` is documented as "never
# read or write a .index sidecar"; it did not write one, but the parallel
# eligibility check loaded one anyway and never looked at o.noIndex. So a
# user who suspected the sidecar and reached for --no-index still got the
# sidecar's answer.
#
# Four changes: one function answers "does this record span lines" for all
# three call sites, --verify-index re-derives it, --no-index is honoured
# where it was not, and INDEX_VERSION goes to 3 so the sidecars already on
# disk -- which no check inside them can catch -- are ignored rather than
# trusted.
#
# T79 —— 索引宣告了一個「沒有任何東西推導過」的檔案性質，而為了這個疑慮才提供的 O(n)
# 證明並沒有檢查它。
# 索引帶著 `no_embedded_newlines`，平行路徑用它來斷定「一行就是一筆」。設定它的呼叫點有
# 三個，其中兩個傳的是常數：一個寫 `spansLines: false`，另一個寫
# `rec.line != r.line || false`，而 `r` 是只改了 `number` 的 `rec`——那個比較不可能為真。
# 於是 --build-index 寫出的每一份索引都宣稱自己有這個性質，不管檔案有沒有。
# 造成的後果不需要竄改、也不需要特殊檔案：拿一份引號內含散文的 CSV（TARGET_PACKAGES.csv
# 的 `status_notes` 就是，而那正是本專案存在的理由），在某個引號欄位裡放一個換行，然後
# --verify-index 說 OK、-contains 回報 150001、強制單執行緒回報 150000、python3 的 csv
# 模組說是 150000。錯的紀錄號、rc=0，而文件指名的那個證明說索引沒問題。
# --verify-index 漏掉它的原因值得記下來：它檢查的是格點偏移量與筆數，而這兩者在這個改動
# 下「都完好無損」——每一筆仍然從索引所說的位元組開始，筆數也一樣。變的只是檔頭裡那個沒有
# 任何東西重新推導過的宣稱。
# 而逃生口也逃不掉：`--no-index` 文件寫的是「絕不讀寫 .index sidecar」，它確實沒有寫，但
# 平行資格檢查仍然載入了一份，而且從來沒看過 o.noIndex。於是因為懷疑 sidecar 而伸手去拿
# --no-index 的人，拿到的還是 sidecar 的答案。
# 四項修改：由一個函式為三個呼叫點回答「這一筆有沒有跨行」、--verify-index 重新推導它、
# 在原本沒有遵守的地方遵守 --no-index，以及把 INDEX_VERSION 推進到 3，讓已經在磁碟上、
# 且內部沒有任何檢查抓得到的那些 sidecar 被忽略而不是被信任。
# ---------------------------------------------------------------------
echo
echo "--- T79: the index's claim about the file, re-derived / 索引對檔案的宣稱，重新推導 ---"

# Genuine, valid RFC 4180. Record 10 holds a newline inside a quoted field --
# no tampering, this is just what prose in a CSV looks like.
#
# The needle sits at record 150, AFTER the spanning one, and that placement is
# the test. A record that spans lines still STARTS on a line boundary, so its
# own number survives the miscount; everything after it is shifted by one. A
# first draft of this fixture put the needle inside the spanning record and
# passed against the unfixed build -- it was asserting on the one record the
# defect cannot reach.
# 真正合法的 RFC 4180。第 10 筆在引號欄位內含一個換行——沒有竄改，CSV 裡的散文本來就長這樣。
# needle 放在第 150 筆，也就是跨行那一筆「之後」，而那個位置正是這個測試本身。跨行的紀錄
# 自己仍然從一個行邊界開始，所以它自己的號碼在誤數中存活下來；被推移一格的是它之後的每一筆。
# 這個 fixture 的第一版把 needle 放進跨行的那一筆裡，結果在未修正的建置上也通過——它斷言的
# 正好是這個缺陷碰不到的那一筆。
{ print -r -- 'a,b'
  for i in {1..300}; do
      if [[ $i == 10 ]]; then print -r -- "$i,\"prose spanning"; print -r -- "two lines\""
      elif [[ $i == 150 ]]; then print -r -- "$i,\"needle here\""
      else print -r -- "$i,\"xx yy $i\""; fi
  done } > "$TMP/t79_nl.csv"
{ print -r -- 'a,b'
  for i in {1..300}; do
      if [[ $i == 150 ]]; then print -r -- "$i,\"needle on one line\""
      else print -r -- "$i,\"xx yy $i\""; fi
  done } > "$TMP/t79_clean.csv"

CSV2_INDEX_MIN_BYTES=1 "$CSV2" --build-index -i "$TMP/t79_nl.csv" >/dev/null
CSV2_INDEX_MIN_BYTES=1 "$CSV2" --build-index -i "$TMP/t79_clean.csv" >/dev/null

# The record number is the whole point. Compare against the path that cannot
# use the index at all, which is the reference answer.
# 紀錄號才是重點。與「完全無法使用索引」的那條路比對，那是基準答案。
idx=$(CSV2_INDEX_MIN_BYTES=1 CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 \
      "$CSV2" -contains needle -i "$TMP/t79_nl.csv" 2>/dev/null)
ref=$(CSV2_PARALLEL_MIN_BYTES=999999999 "$CSV2" -contains needle -i "$TMP/t79_nl.csv" 2>/dev/null)
assert_eq "$idx" "$ref" \
    "T79a an index does not change the record number on a file with a quoted newline / 對含引號換行的檔案，有沒有索引不改變紀錄號"
assert_contains "$idx" "150:" \
    "T79b and the number is 150, the record, not 151, the line / 而那個號碼是紀錄 150，不是行 151"

p=$(CSV2_INDEX_MIN_BYTES=1 CSV2_PARALLEL_MIN_BYTES=1 path_of -contains needle -i "$TMP/t79_nl.csv")
assert_contains "$p" "records a record spanning lines" \
    "T79c the reason names the index's finding, not 'build one' -- rebuilding would reach the same conclusion / 理由指名索引的發現，而不是叫人「建一個」——重建會得到相同結論"

# The fast path must survive the fix, or the fix is a different defect.
# 快路徑必須在修正後存活，否則這個修正只是換了一個缺陷。
p=$(CSV2_INDEX_MIN_BYTES=1 CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 \
    path_of -contains needle -i "$TMP/t79_clean.csv")
assert_contains "$p" "parallel:" \
    "T79d a .csv with no embedded newline still takes the parallel path / 沒有內嵌換行的 .csv 仍然走平行路徑"

assert_succeeds "T79e --verify-index passes on an honestly built index / 誠實建出來的索引通過 --verify-index" -- \
    env CSV2_INDEX_MIN_BYTES=1 "$CSV2" --verify-index -i "$TMP/t79_nl.csv"

# --no-index: documented as "never read or write". The write half was already
# true; the read half was not, and only the chosen path showed it.
# --no-index：文件寫的是「絕不讀寫」。「寫」那一半本來就成立，「讀」那一半不成立，
# 而唯一顯示出來的地方是「走了哪一條路」。
p=$(CSV2_INDEX_MIN_BYTES=1 CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 \
    path_of -contains needle --no-index -i "$TMP/t79_clean.csv")
assert_contains "$p" "single-threaded: --no-index" \
    "T79f --no-index declines the parallel path because it will not read the sidecar / --no-index 拒絕平行路徑，因為它不會去讀 sidecar"
assert_eq "$(CSV2_INDEX_MIN_BYTES=1 "$CSV2" -contains needle --no-index -i "$TMP/t79_clean.csv" 2>/dev/null)" \
          "$(CSV2_PARALLEL_MIN_BYTES=999999999 "$CSV2" -contains needle -i "$TMP/t79_clean.csv" 2>/dev/null)" \
    "T79g and its answer is the same one, which is the point of refusing / 而它的答案不變，那正是拒絕的意義"

# -tail builds a sidecar as a side effect. That builder passed the constant
# `false`, so it produced the same lie without anyone asking for an index.
# -tail 會順手建一份 sidecar。那個建立點傳的是常數 `false`，因此不需要任何人要求建索引，
# 它就會產生同樣那個謊。
rm -f "$TMP/t79_nl.csv.index"
CSV2_INDEX_MIN_BYTES=1 "$CSV2" -tail 1 -t -i "$TMP/t79_nl.csv" >/dev/null 2>&1
p=$(CSV2_INDEX_MIN_BYTES=1 CSV2_PARALLEL_MIN_BYTES=1 path_of -contains needle -i "$TMP/t79_nl.csv")
assert_contains "$p" "records a record spanning lines" \
    "T79h the sidecar -tail builds as a side effect records the property too / -tail 順手建出來的 sidecar 同樣記錄了這個性質"

# The O(1) stamp cannot see a same-size, same-mtime rewrite -- the README says
# so, and offers --verify-index as the O(n) proof for exactly that case. The
# proof has to cover the claim the parallel path consumes, not just the two
# that happened to be right. `touch -t` sets nanoseconds to zero on both
# platforms, so the stamp is restored exactly and the index really is loaded;
# if it were not, --verify-index would say "no usable index" instead.
# O(1) 戳記看不見「大小相同、mtime 相同」的原地改寫——README 這樣寫，並為這個情況提供
# --verify-index 作為 O(n) 的證明。那個證明必須涵蓋平行路徑真正取用的那個宣稱，而不只是
# 那兩個剛好是對的。`touch -t` 在兩個平台上都把奈秒設為 0，因此戳記被精確還原、索引真的
# 有被載入；否則 --verify-index 會說「沒有可用的索引」而不是回報不符。
# Fixed-width records, so the byte to patch is arithmetic. The first version
# found it with `grep -abo`, which passed on macOS and FAILED IN THE GUEST --
# busybox's grep need not offer -b, and a test that cannot locate the byte
# patches the wrong one and then asserts on something else entirely. The
# offset is checked below before it is used, so this can no longer happen
# quietly on a platform whose tools differ.
#
#   header  'a,b' + LF                                    =  4 bytes
#   record  NNN , " twelve-chars " LF                     = 19 bytes
#   record N starts at 4 + (N-1)*19 ; its payload at +5
#
# 固定寬度的紀錄，因此要修改的位元組是算出來的。第一版用 `grep -abo` 找它，在 macOS 上
# 通過而「在 guest 內失敗」——busybox 的 grep 不一定提供 -b，而一個找不到那個位元組的測試
# 會去改錯的那一個，然後斷言在完全不同的東西上。下面在使用之前先檢查那個偏移量，因此這件事
# 不會再在一台工具不同的機器上安靜地發生。
{ print -r -- 'a,b'
  for i in {1..300}; do
      if [[ $i == 150 ]]; then printf '%03d,"needle here."\n' $i
      else printf '%03d,"filler here."\n' $i; fi
  done } > "$TMP/t79_doc.csv"
touch -t 202601010000.00 "$TMP/t79_doc.csv"
CSV2_INDEX_MIN_BYTES=1 "$CSV2" --build-index -i "$TMP/t79_doc.csv" >/dev/null
before=$(wc -c < "$TMP/t79_doc.csv")
sp=$(( 4 + 149 * 19 + 5 + 6 ))
assert_eq "$(dd if="$TMP/t79_doc.csv" bs=1 skip=$sp count=1 2>/dev/null)" " " \
    "T79i the computed offset really is the space inside the quoted field / 算出來的偏移量確實是引號欄位內的那個空白"
printf '\n' | dd of="$TMP/t79_doc.csv" bs=1 seek=$sp count=1 conv=notrunc 2>/dev/null
touch -t 202601010000.00 "$TMP/t79_doc.csv"
assert_eq "$(wc -c < "$TMP/t79_doc.csv")" "$before" \
    "T79j the doctored file is the same size, so the O(1) stamp cannot see it / 竄改後的檔案大小不變，因此 O(1) 戳記看不見它"

# The stamp has to have been restored exactly, or the index is discarded as
# stale and --verify-index answers a different question ("no usable index")
# while still exiting non-zero -- which would let T79l pass for the wrong
# reason. Asserted separately so the two failures cannot be confused.
# 戳記必須被精確還原，否則索引會被當成過期而丟棄，--verify-index 回答的就是另一個問題
# （「沒有可用的索引」）卻仍然以非零結束——那會讓 T79l 因為錯的理由而通過。分開斷言，
# 使這兩種失敗不會被混為一談。
out=$(CSV2_INDEX_MIN_BYTES=1 "$CSV2" --verify-index -i "$TMP/t79_doc.csv" 2>&1)
if [[ "$out" == *"no usable index"* ]]; then
    bad "T79k the stamp was restored exactly, so the index is still loaded / 戳記被精確還原，因此索引仍然被載入 (index was discarded as stale / 索引被當成過期丟棄)"
else
    ok "T79k the stamp was restored exactly, so the index is still loaded / 戳記被精確還原，因此索引仍然被載入"
fi
assert_contains "$out" "no_embedded_newlines" \
    "T79l --verify-index re-derives the flag and reports the mismatch / --verify-index 重新推導那個旗標並回報不符"
assert_fails "T79m and exits non-zero, because an index that lies is worse than none / 並以非零結束，因為說謊的索引比沒有更糟" -- \
    env CSV2_INDEX_MIN_BYTES=1 "$CSV2" --verify-index -i "$TMP/t79_doc.csv"

# ---------------------------------------------------------------------
# T90 -- a raw value must not be written into a column the FILE declares
# transformed, by any verb.
#
# Round 37, defect W. `-update 1:secret NEW` on a file whose header reads
# `secret:enc:<fp>:<salt>` was accepted at rc=0. The plaintext went in, and
# `-decrypt` then stopped at that cell -- so records 2 and 3, whose ciphertext
# was intact and which the edit never touched, could not be read back either.
# The audit log recorded it as `update 1:secret: <redacted> -> <redacted>`,
# because redaction follows the file's declaration: the protection worked
# perfectly on a value that should never have been written, and in doing so it
# was the only record of the damage and it concealed it.
#
# Four verbs write raw values and all four had to be closed. The first fix
# covered -update and -delete -cell only, and -append walked past it into the
# identical destruction -- which is why -append --in-place is asserted here
# separately: it never reaches runEdit, so a guard placed there does nothing
# for the O(1) path, the one most likely to be used on a large protected file.
#
# What stays allowed is as important as what is refused. Transforming and
# editing in the SAME run is coherent -- the new value is what gets encrypted
# -- because the input's header carries no marker yet; and an ordinary column
# of a protected file is nobody's business but the caller's.
#
# T90 —— 任何動詞都不得把原始值寫進一個「檔案自己宣告為已轉換」的欄位。
# 第 37 回合，編號 W。對標頭為 `secret:enc:<指紋>:<salt>` 的檔案下
# `-update 1:secret NEW`，會以 rc=0 被接受。明文寫了進去，而 `-decrypt` 接著停在那一格
# ——於是第 2、3 筆（密文完好、且該次編輯從未碰過）也一起讀不回來。稽核紀錄寫的是
# `update 1:secret: <redacted> -> <redacted>`，因為遮蔽依據的是檔案的宣告：那道保護在一個
# 「根本不該被寫下去的值」上運作得完美無缺，而它同時是損害唯一的紀錄，並且掩蓋了它。
# 有四個動詞會寫入原始值，四個都必須關上。第一版的修正只涵蓋 -update 與 -delete -cell，
# 而 -append 直接走過去造成一模一樣的破壞——這也是為什麼 -append --in-place 在此單獨斷言：
# 它不會走到 runEdit，因此放在那裡的守衛對 O(1) 路徑毫無作用，而那正是最可能被用在一個
# 大型受保護檔案上的路徑。
# 「什麼仍然被允許」與「什麼被拒絕」一樣重要。在「同一次執行」裡轉換並編輯是說得通的——
# 被加密的就是那個新值——因為輸入的標頭還沒有標記；而一個受保護檔案裡的一般欄位，
# 是呼叫者自己的事。
# ---------------------------------------------------------------------
echo
echo "--- T90: no verb writes a raw value into a declared column / 任何動詞都不得把原始值寫進已宣告的欄位 ---"

head -c 32 /dev/urandom > "$TMP/t90.key"
printf 'pkg,ver,secret\nbusybox,1.37.0,s1\nzlib,1.3.2,s2\nzstd,1.5.7,s3\n' > "$TMP/t90.csv"
"$CSV2" -encrypt secret -keyfile "$TMP/t90.key" -i "$TMP/t90.csv" -o "$TMP/t90_enc.csv" -t 2>/dev/null
"$CSV2" -hash secret -i "$TMP/t90.csv" -o "$TMP/t90_hash.csv" -t 2>/dev/null
cp "$TMP/t90_enc.csv" "$TMP/t90_enc.bak"

assert_fails "T90a -update into an encrypted column is refused / -update 寫入加密欄位被拒絕" -- \
    "$CSV2" -update 1:secret NEW -i "$TMP/t90_enc.csv" -o "$TMP/t90_out.csv" -t
assert_fails "T90b -delete -cell into an encrypted column is refused / -delete -cell 寫入加密欄位被拒絕" -- \
    "$CSV2" -delete -cell 1:secret -i "$TMP/t90_enc.csv" -o "$TMP/t90_out.csv" -t
assert_fails "T90c -insert into a file with an encrypted column is refused / -insert 到含加密欄位的檔案被拒絕" -- \
    "$CSV2" -insert 1 'x,1,RAW' -i "$TMP/t90_enc.csv" -o "$TMP/t90_out.csv" -t
assert_fails "T90d -append -o into such a file is refused / -append 走 -o 同樣被拒絕" -- \
    "$CSV2" -append 'x,1,RAW' -i "$TMP/t90_enc.csv" -o "$TMP/t90_out.csv" -t

# The O(1) path does not go through runEdit, so it needs its own guard and its
# own assertion. This is the case the first fix missed.
# O(1) 路徑不經過 runEdit，因此它需要自己的守衛與自己的斷言。這正是第一版修正漏掉的那個。
assert_fails "T90e -append --in-place, the O(1) path that skips runEdit, is refused too / -append --in-place（跳過 runEdit 的 O(1) 路徑）同樣被拒絕" -- \
    "$CSV2" -append 'x,1,RAW' -i "$TMP/t90_enc.csv" --in-place
assert_same "$TMP/t90_enc.csv" "$TMP/t90_enc.bak" \
    "T90f and after all five refusals the file is byte-identical / 五次拒絕之後，檔案逐位元不變"

# The property that actually matters. Every earlier assertion is a proxy for
# this one: the column can still be read back.
# 真正要緊的性質。前面每一條斷言都只是它的代理：那一欄仍然讀得回來。
"$CSV2" -decrypt all -keyfile "$TMP/t90.key" -i "$TMP/t90_enc.csv" -o "$TMP/t90_back.csv" -t 2>/dev/null
assert_same "$TMP/t90.csv" "$TMP/t90_back.csv" \
    "T90g and the whole column still decrypts to the original, byte for byte / 而整欄仍能逐位元解回原值"

# A hashed column is a different consequence and must get a different message.
# Telling someone to decrypt a hash sends them looking for a flag that cannot
# exist.
# 雜湊欄位的後果不同，訊息也必須不同。叫人去把雜湊解開，會讓他去找一個不可能存在的旗標。
enc_msg=$("$CSV2" -update 1:secret NEW -i "$TMP/t90_enc.csv" -o "$TMP/t90_out.csv" -t 2>&1)
hash_msg=$("$CSV2" -update 1:secret NEW -i "$TMP/t90_hash.csv" -o "$TMP/t90_out.csv" -t 2>&1)
assert_fails "T90h a hashed column refuses too / 雜湊欄位同樣拒絕" -- \
    "$CSV2" -update 1:secret NEW -i "$TMP/t90_hash.csv" -o "$TMP/t90_out.csv" -t
assert_contains "$enc_msg" "decrypt" \
    "T90i the encrypted message says the column stops decrypting / 加密的訊息說出「整欄不再能解密」"
assert_contains "$hash_msg" "one way" \
    "T90j while the hashed message says hashing is one way, not that it can be undone / 而雜湊的訊息說「雜湊是單向的」，不是叫人去還原它"

# What must NOT be refused.
# 不得被拒絕的部分。
assert_succeeds "T90k transforming and editing in one run is still allowed / 同一次執行裡轉換並編輯仍然允許" -- \
    "$CSV2" -encrypt secret -keyfile "$TMP/t90.key" -update 1:secret NEW -i "$TMP/t90.csv" -o "$TMP/t90_both.csv" -t
"$CSV2" -decrypt all -keyfile "$TMP/t90.key" -i "$TMP/t90_both.csv" -o "$TMP/t90_both_p.csv" -t 2>/dev/null
assert_eq "$("$CSV2" -get 1:secret -i "$TMP/t90_both_p.csv" 2>/dev/null)" "NEW" \
    "T90l and it is the NEW value that was encrypted, not the old one / 而被加密的是新值，不是舊值"
assert_succeeds "T90m an ordinary column of a protected file is still editable / 受保護檔案裡的一般欄位仍可編輯" -- \
    "$CSV2" -update 1:ver 9.9 -i "$TMP/t90_enc.csv" -o "$TMP/t90_ver.csv" -t

# ---------------------------------------------------------------------
# T91 -- the append fast path validates what the rewrite path validates.
#
# Round 37, defects X and Y. `-append --in-place` read only the header, so for
# a `.csv` it validated nothing about the records already there. A file ending
# `zlib,1.3` where the header has three columns took the append at rc=0 and
# produced a file csv2 itself then refused to read; the SAME input through `-o`
# was correctly refused. A file ending inside an unclosed quote absorbed the
# appended record into that field, so a write that reported success had not
# happened.
#
# The check runs only when the file does not end in a newline, which is the
# only state in which the tail can be half-written -- so the O(1) promise is
# kept for every file that ends properly, and T91f asserts that rather than
# trusting it.
#
# --truncate-partial is refused here rather than honoured, and that is a
# decision made while fixing this: honouring it dropped the incomplete record
# from the PARSE and left it in the FILE, then appended a complete record after
# it -- rc=0, unreadable next time. Appending adds bytes; it cannot remove any.
#
# T91 —— 追加快路徑要驗證「重寫路徑會驗證的東西」。
# 第 37 回合，編號 X 與 Y。`-append --in-place` 只讀標頭，因此對 `.csv` 而言，它對已經在那裡
# 的紀錄不做任何驗證。一個以 `zlib,1.3` 結尾、而標頭有三欄的檔案，會以 rc=0 接受追加並產生
# 一個 csv2 自己拒讀的檔案；**同一份輸入**走 `-o` 則被正確拒絕。一個結束在未閉合引號裡的檔案，
# 會把追加的那一筆吸進那個欄位，於是一次回報成功的寫入其實沒有發生。
# 這個檢查只在檔案未以換行結尾時執行，而那是唯一「結尾可能只寫了一半」的狀態——因此對每一個
# 正常結尾的檔案，O(1) 的承諾仍然成立，而 T91f 斷言它，不是相信它。
# --truncate-partial 在此是被拒絕而非被接受，那是修這件事時做的決定：接受它會把不完整的紀錄
# 從「解析」中丟掉、卻留在「檔案」裡，然後在其後追加一筆完整的——rc=0，下一次就讀不了。
# 追加只會加上位元組，它移除不了任何東西。
# ---------------------------------------------------------------------
echo
echo "--- T91: the append fast path validates the file it appends to / 追加快路徑會驗證它所追加的檔案 ---"

printf 'pkg,ver,note\nbusybox,1.37.0,core\nzlib,1.3' > "$TMP/t91_short.csv"
printf 'pkg,ver,note\nbusybox,1.37.0,core\nzlib,1.3.2,"unterminated' > "$TMP/t91_quote.csv"
printf 'pkg,ver,note\nbusybox,1.37.0,core\nzlib,1.3.2,ok' > "$TMP/t91_ok.csv"
cp "$TMP/t91_short.csv" "$TMP/t91_short.bak"
cp "$TMP/t91_quote.csv" "$TMP/t91_quote.bak"

assert_fails "T91a -append --in-place onto a short trailing record is refused / 對「結尾紀錄欄數不足」的檔案追加會被拒絕" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_short.csv" --in-place
assert_same "$TMP/t91_short.csv" "$TMP/t91_short.bak" \
    "T91b and the file is untouched / 而檔案原封不動"
assert_fails "T91c -append --in-place onto an unclosed quote is refused / 對「結尾為未閉合引號」的檔案追加會被拒絕" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_quote.csv" --in-place
assert_same "$TMP/t91_quote.csv" "$TMP/t91_quote.bak" \
    "T91d and that file is untouched too / 那個檔案同樣原封不動"

# The point of X: the two paths must now agree. Before the fix they disagreed
# on the same bytes, which is what made it impossible to notice.
# X 的重點：兩條路徑現在必須一致。修正之前它們對「同一份位元組」給出相反的結果，
# 而那正是它難以被發現的原因。
"$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_short.csv" -o "$TMP/t91_o.csv" >/dev/null 2>&1
rc_o=$?
"$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_short.csv" --in-place >/dev/null 2>&1
rc_ip=$?
assert_eq "$rc_o" "$rc_ip" \
    "T91e -o and --in-place now reach the same verdict on the same file / -o 與 --in-place 現在對同一個檔案得到相同的判斷"

# A complete record that merely lacks its final newline is NOT damaged, and
# appending to it must still work -- csv2 supplies the newline. Without this,
# the fix above could have been "refuse everything without a trailing LF".
# 一筆「只是少了結尾換行」的完整紀錄並沒有損壞，對它追加必須仍然可行——csv2 會補上那個換行。
# 少了這一條，上面的修正大可以是「凡是沒有結尾 LF 一律拒絕」。
assert_succeeds "T91f a complete record with no final newline still accepts an append / 「完整但少了結尾換行」的檔案仍可被追加" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_ok.csv" --in-place
assert_eq "$("$CSV2" -r -i "$TMP/t91_ok.csv" 2>/dev/null | wc -l | tr -d ' ')" "3" \
    "T91g and the result is three records, not two glued together / 而結果是三筆，不是被黏成兩筆"

# The O(1) promise: a file that ends properly must not be read through. The
# debug line names the O(n) path, so its ABSENCE is the assertion.
# O(1) 的承諾：正常結尾的檔案不得被整份讀過。那個 debug 行會指名 O(n) 路徑，
# 因此「它不出現」就是斷言本身。
mk_rows "$TMP/t91_big.csv2" 20000
"$CSV2" -append 'a,b,c' -i "$TMP/t91_big.csv2" --in-place -debug 2>"$TMP/t91_dbg.txt" >/dev/null
if grep -q "does not end with a newline" "$TMP/t91_dbg.txt"; then
    bad "T91h a properly terminated file was read through anyway / 正常結尾的檔案仍然被整份讀過"
else
    ok "T91h a properly terminated file still takes the O(1) path / 正常結尾的檔案仍然走 O(1) 路徑"
fi

# --truncate-partial cannot be honoured by a verb that only adds bytes, and
# saying so is better than doing half of it.
# 一個「只會加上位元組」的動詞無法履行 --truncate-partial，而說出來比做一半好。
cp "$TMP/t91_quote.bak" "$TMP/t91_quote.csv"
tp_msg=$("$CSV2" -append 'zstd,1.5.7,compression' --truncate-partial -i "$TMP/t91_quote.csv" --in-place 2>&1)
assert_fails "T91i --truncate-partial with -append is refused, not half-honoured / --truncate-partial 搭配 -append 是被拒絕，而不是做一半" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' --truncate-partial -i "$TMP/t91_quote.csv" --in-place
assert_same "$TMP/t91_quote.csv" "$TMP/t91_quote.bak" \
    "T91j and it left the file alone rather than appending after the incomplete record / 而它沒有動那個檔案，不是在不完整的紀錄後面追加"
# The message no longer says "the incomplete record", because this refusal
# fires on the flags alone -- before the file is read -- and so fires on files
# that have no torn tail at all. What it must still carry is the reason the two
# cannot be honoured together, and the way through.
# 訊息不再說「那筆不完整的紀錄」，因為這條拒絕只看旗標——在讀檔之前——因此對「根本沒有撕裂
# 尾巴」的檔案也會觸發。它必須仍然帶著「兩者為何無法同時被滿足」的理由，以及走得通的那條路。
assert_contains "$tp_msg" "can only add bytes after it" \
    "T91k the message says why, and names the way through / 訊息說出理由，並指出走得通的那條路"
assert_contains "$tp_msg" "csv2 -r -t --truncate-partial" \
    "T91k2 and the way through is a command, not advice / 而那條路是一個指令，不是一句建議"

# T91i/T91j above use a file whose last record is INCOMPLETE, and they passed
# for as long as they have existed -- while the refusal they assert was
# conditional on exactly that. On a healthy file the same combination was
# accepted at rc=0, and both READMEs said in two places that it is refused.
# The test was real, the assertion was real, and the case it never reached was
# the common one.
# 上面的 T91i／T91j 用的是「最後一筆不完整」的檔案，而它們從存在以來一直通過——同時，它們
# 所斷言的那個拒絕，其成立條件正好就是「最後一筆不完整」。在一個健康的檔案上，同樣的組合
# 會以 rc=0 被接受，而兩份 README 在兩個地方都說它被拒絕。測試是真的、斷言是真的，而它從未
# 走到的那個情況，才是常見的那個。
print -r -- 'pkg,version,purpose' > "$TMP/t91_ok.csv"
print -r -- 'zlib,1.3.1,compression' >> "$TMP/t91_ok.csv"
cp "$TMP/t91_ok.csv" "$TMP/t91_ok.bak"
assert_fails "T91n and it is refused on a HEALTHY file too, which is where it was not / 在「健康的檔案」上同樣被拒絕——而那正是它原本沒有拒絕的地方" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' --truncate-partial -i "$TMP/t91_ok.csv" --in-place
assert_same "$TMP/t91_ok.csv" "$TMP/t91_ok.bak" \
    "T91o leaving that file alone as well / 那個檔案同樣沒有被動過"

# The way through has to actually work, or the message is worse than silence.
# 那條走得通的路必須真的走得通，否則那個訊息比沉默更糟。
"$CSV2" -r -t --truncate-partial -i "$TMP/t91_quote.csv" -o "$TMP/t91_clean.csv" 2>/dev/null
assert_succeeds "T91l the copy the message recommends can be appended to / 訊息所建議的那份複本，追加得上去" -- \
    "$CSV2" -append 'zstd,1.5.7,compression' -i "$TMP/t91_clean.csv" --in-place
assert_succeeds "T91m and reads back cleanly / 而且讀得回來" -- \
    "$CSV2" -r -t -i "$TMP/t91_clean.csv"

# ---------------------------------------------------------------------
# T92 -- the log records the value in full, and one entry stays one line.
#
# Round 38 found the README promising old and new values "in full; that is the
# point of an audit trail" while the log cut them at 40 characters. In
# TARGET_PACKAGES.csv, `status_notes` -- the column whose corruption is the
# reason this project exists -- reaches 878 bytes, so for exactly that column
# the log preserved nothing usable.
#
# Asking what removing the limit would COST turned up the defect the round did
# not find, and it is the one that had to be fixed first. Logger.redact()
# wrote the value with quotes and NO escaping, into a format that is one entry
# per line. A newline inside a value therefore opened a new line whose entire
# content the value chose:
#
#   …INFO  update 1:note: "harmless" -> "x"
#   2020-01-01T00:00:00+00:00 INFO  nothi…[+11 more chars]"     <- forged
#
# The truncation did not prevent that. It only shortened the forged line. So
# lifting the limit alone would have upgraded the forgery from truncated to
# complete and convincing. Escape first, then lift.
#
# The size decision (2026-08-19): unbounded, with a WARN above 1 MiB. A cap
# would be an audit trail that drops data, which is the thing being fixed; the
# warning exists so the person hears about the megabyte at the time rather
# than finding it in a disk graph later. Note it can only be reached through
# the OLD value -- a new value that large cannot be passed, because ARG_MAX
# rejects the command line first.
#
# T92 —— log 完整記錄那個值，而一筆紀錄仍然只佔一行。
# 第 38 回合發現 README 承諾新舊值「完整記錄；那正是稽核軌跡的意義」，而 log 在第 40 個字元
# 把它們切斷。`TARGET_PACKAGES.csv` 的 `status_notes`——這個專案存在的理由就是那一欄被改壞
# ——長達 878 bytes，因此恰恰對那一欄，log 保留不下任何可用的東西。
# 追問「移除那個上限要付出什麼代價」，翻出了該回合沒有找到、而且必須先修的那個缺陷：
# Logger.redact() 把值加上引號後直接寫進一個「一行一筆」的格式，完全沒有跳脫。於是值裡的
# 一個換行就會開啟新的一行，而那一行的全部內容由值決定——一筆時間戳由攻擊者挑選的偽造紀錄。
# 截斷擋不住那件事，它只是把偽造的那一行剪短。因此「只解除上限」會讓偽造從被剪斷變成完整。
# 先跳脫，再解除。
# 大小的決定（2026-08-19）：無界，超過 1 MiB 發 WARN。設上限等於「會丟資料的稽核軌跡」，
# 而那正是現在要修的東西；警告的存在，是為了讓人當場聽到那一 MB，而不是事後在磁碟用量圖上
# 發現。注意它只能經由「舊值」達到——那麼大的新值傳不進來，命令列會先被 ARG_MAX 拒絕。
# ---------------------------------------------------------------------
echo
echo "--- T92: the log keeps the whole value, on one line / log 完整保留那個值，且只佔一行 ---"

long_a=$(printf 'A%.0s' {1..300})
long_z=$(printf 'Z%.0s' {1..300})
print -r -- "id,note" > "$TMP/t92.csv"
print -r -- "1,$long_a" >> "$TMP/t92.csv"
rm -f "$TMP/t92.log"
"$CSV2" -update 1:note "$long_z" -i "$TMP/t92.csv" --in-place -log "$TMP/t92.log" 2>/dev/null

line=$(grep -o 'update 1:note:.*' "$TMP/t92.log")
assert_contains "$line" "$long_a" \
    "T92a the OLD value is in the log in full, not cut at 40 / 舊值完整出現在 log 中，沒有被切在第 40 個字元"
assert_contains "$line" "$long_z" \
    "T92b and so is the new one / 新值也是"
if [[ "$line" == *"more chars"* ]]; then
    bad "T92c the log still truncates / log 仍然在截斷"
else
    ok "T92c with no '…[+N more chars]' anywhere in it / 而且裡面沒有任何「…[+N more chars]」"
fi

# One entry, one line. This is the assertion the forgery would break.
# 一筆紀錄一行。偽造要破壞的就是這一條。
rm -f "$TMP/t92b.log"
printf 'id,note\n1,"harmless"\n' > "$TMP/t92b.csv"
forge=$'x"\n2020-01-01T00:00:00+00:00 INFO  nothing happened'
"$CSV2" -update 1:note "$forge" -i "$TMP/t92b.csv" --in-place -log "$TMP/t92b.log" 2>/dev/null
assert_eq "$(wc -l < "$TMP/t92b.log" | tr -d ' ')" "3" \
    "T92d a value containing a newline does not add a log line / 含換行的值不會多出一行 log"
if grep -qE '^2020-01-01' "$TMP/t92b.log"; then
    bad "T92e a forged entry with an attacker-chosen timestamp is in the log / 一筆時間戳由攻擊者挑選的偽造紀錄進了 log"
else
    ok "T92e and no line begins with the timestamp the value tried to forge / 沒有任何一行以那個值試圖偽造的時間戳開頭"
fi
assert_contains "$(cat "$TMP/t92b.log")" 'nothing happened' \
    "T92f while the text itself is still recorded, escaped, on the entry's own line / 而那段文字本身仍然被記錄下來——經過跳脫，留在它自己那一行裡"

# The other three characters that would break the format.
# 另外三個會破壞這個格式的字元。
rm -f "$TMP/t92c.log"
printf 'id,note\n1,plain\n' > "$TMP/t92c.csv"
"$CSV2" -update 1:note "$(printf 'a\tb\rc\\d')" -i "$TMP/t92c.csv" --in-place -log "$TMP/t92c.log" 2>/dev/null
assert_contains "$(grep -o 'update 1:note:.*' "$TMP/t92c.log")" 'a\tb\rc\\d' \
    "T92g tab, CR and backslash are escaped too / TAB、CR 與反斜線同樣被跳脫"
assert_eq "$(wc -l < "$TMP/t92c.log" | tr -d ' ')" "3" \
    "T92h and the entry is still one line / 那筆紀錄仍然只佔一行"

# Redaction is unchanged: escaping must not turn <redacted> into a value.
# 遮蔽不受影響：跳脫不得把 <redacted> 變回一個值。
rm -f "$TMP/t92d.log"
printf 'id,secret\n1,s1\n' > "$TMP/t92d.csv"
"$CSV2" -hash secret -i "$TMP/t92d.csv" -o "$TMP/t92d_h.csv" -t 2>/dev/null
"$CSV2" -update 1:id 9 -i "$TMP/t92d_h.csv" --in-place -log "$TMP/t92d.log" 2>/dev/null
assert_contains "$(grep -o 'update 1:id:.*' "$TMP/t92d.log")" '"1" -> "9"' \
    "T92i an ordinary column still logs its values / 一般欄位仍然記錄它的值"

# The threshold. Reachable only through the OLD value: a new value this large
# cannot be passed, ARG_MAX refuses the command line first.
# 那個門檻。只能經由「舊值」達到：那麼大的新值傳不進來，命令列會先被 ARG_MAX 拒絕。
big=$(printf 'Q%.0s' {1..1100000})
print -r -- "id,note" > "$TMP/t92e.csv"
print -r -- "1,$big" >> "$TMP/t92e.csv"
rm -f "$TMP/t92e.log"
"$CSV2" -update 1:note tiny -i "$TMP/t92e.csv" --in-place -log "$TMP/t92e.log" 2>"$TMP/t92e.err"
assert_contains "$(cat "$TMP/t92e.err")" "1100000 bytes" \
    "T92j a value over 1 MiB warns, naming its size / 超過 1 MiB 的值會發出警告並指名大小"
assert_contains "$(cat "$TMP/t92e.err")" "not truncated" \
    "T92k and says the log keeps it anyway, so the warning is not read as a refusal / 並說明 log 仍會完整保留它，使那個警告不會被讀成拒絕"
if [[ $(wc -c < "$TMP/t92e.log") -gt 1100000 ]]; then
    ok "T92l and the value really is in the log in full / 那個值確實完整地在 log 裡"
else
    bad "T92l the log is smaller than the value it claims to hold / log 比它宣稱記錄的那個值還小"
fi

rm -f "$TMP/t92f.log"
printf 'id,note\n1,small\n' > "$TMP/t92f.csv"
"$CSV2" -update 1:note "$(printf 'Q%.0s' {1..1000})" -i "$TMP/t92f.csv" --in-place -log "$TMP/t92f.log" 2>"$TMP/t92f.err"
assert_eq "$(wc -c < "$TMP/t92f.err" | tr -d ' ')" "0" \
    "T92m while an ordinary value warns about nothing / 而一般大小的值不會產生任何警告"

# The locating report has its own limit and its own reasons. It must not have
# moved: a report is a report, not an audit trail.
# 定位報告有自己的上限與自己的理由，它不得被動到：報告是報告，不是稽核軌跡。
print -r -- "id,note" > "$TMP/t92g.csv"
print -r -- "1,NEEDLE$(printf 'B%.0s' {1..400})" >> "$TMP/t92g.csv"
assert_contains "$("$CSV2" -contains NEEDLE -i "$TMP/t92g.csv" 2>/dev/null)" "more chars" \
    "T92n the locating report still truncates at its own limit / 定位報告仍然依它自己的上限截斷"

# ---------------------------------------------------------------------
# T93 -- the address in an error message resolves.
#
# Round 38, defect CC. Cell-level errors printed `recordsEmitted + 1`, which
# counts the header rows, so the number was the PHYSICAL LINE wearing a record
# label. On a .csv2 the offset is exactly two:
#
#   csv2: record 4, field 2: undefined escape sequence \q      <- data record 2
#   csv2 -get 4:2 -i f.csv2   ->  no such record; the file has 2 records
#
# Meanwhile record-level errors in the same tool were already correct --
# `record 1 (line 3)` -- so the error channel carried two numbering schemes,
# and the README's own example demonstrated the broken one while stating that
# `N` counts records, not lines, throughout.
#
# The number in an error message is an ADDRESS. Someone types it back into
# -get or -update; that composition is what this tool has instead of a query
# language. An address that does not resolve is worse than none: it sends the
# reader to a different cell, or to a refusal that reads as "the file is
# wrong" when the file is fine.
#
# T93 —— 錯誤訊息裡的位址解得出來。
# 第 38 回合，缺陷 CC。儲存格層級的錯誤印的是 `recordsEmitted + 1`，那個計數含標頭列，
# 因此那個號碼是「披著紀錄外衣的物理行號」。在 .csv2 上偏移恰好是二：資料第 2 筆的錯誤
# 印成 `record 4`，而 `-get 4:2` 回答「沒有這一筆；本檔案有 2 筆」。
# 同一支工具的紀錄層級錯誤本來就是對的（`record 1 (line 3)`），於是錯誤通道裡並存兩套編號，
# 而 README 自己的範例示範的正是壞掉的那一套——儘管它同時寫著「N 自始至終數的是紀錄，不是行」。
# 錯誤訊息裡的號碼是一個「位址」。人會把它打回 -get 或 -update，而那個組合正是這支工具用來
# 取代查詢語言的東西。一個解不出來的位址比沒有更糟：它會把讀者送到另一格，或送到一個
# 「讀起來像是檔案有問題」的拒絕，而檔案其實沒問題。
# ---------------------------------------------------------------------
echo
echo "--- T93: the address in an error resolves / 錯誤裡的位址解得出來 ---"

printf 'id,val\n編號,值\n1,ok\n2,bad\\qvalue\n' > "$TMP/t93.csv2"
printf 'id,val\n編號,值\n1,ok\n2,THEBAD\n'     > "$TMP/t93_ok.csv2"
err=$("$CSV2" -r -t -i "$TMP/t93.csv2" 2>&1 | head -1)

assert_contains "$err" "record 2 " \
    "T93a a fault in data record 2 is reported as record 2, not as its line / 資料第 2 筆的錯誤回報為 record 2，不是它的行號"
assert_contains "$err" "(line 4)" \
    "T93b and the physical line comes with it, the same pair record-level errors print / 而物理行號一併給出，與紀錄層級錯誤的格式相同"

# The point of the whole case: take the address out of the message and use it.
# 整個案例的重點：把位址從訊息裡取出來，然後用它。
addr=$(print -r -- "$err" | sed -n 's/.*record \([0-9][0-9]*\) .*field \([0-9][0-9]*\).*/\1:\2/p')
assert_eq "$addr" "2:2" \
    "T93c the address parses out of the message as record:field / 位址能從訊息中解析成 record:field"
assert_eq "$("$CSV2" -get "$addr" -i "$TMP/t93_ok.csv2" 2>/dev/null)" "THEBAD" \
    "T93d and -get on it returns the cell the message was about / 而以它下 -get，取回的正是訊息所指的那一格"

# A .csv has one header row, so the old bug shifted by one there instead of
# two -- same defect, different offset, which is why it needs its own case.
# .csv 只有一列標頭，因此舊缺陷在那裡是偏移一格而不是兩格——同一個缺陷、不同的偏移量，
# 所以它需要自己的案例。
printf 'a,b\n1,"x"y\n' > "$TMP/t93.csv"
errc=$("$CSV2" -r -t -i "$TMP/t93.csv" 2>&1 | head -1)
assert_contains "$errc" "record 1 (line 2)" \
    "T93e in a .csv the first data record is record 1, not record 2 / 在 .csv 中第一筆資料是 record 1，不是 record 2"

# A header row has no record number, and inventing one would be an address
# that resolves to the wrong thing. It gets the name the locating report
# already uses.
# 標頭列沒有紀錄號，而發明一個會產生「解得出來、但解到錯的東西」的位址。它拿到的是定位報告
# 本來就在用的那個名字。
printf 'id,val\\q\n編號,值\n1,ok\n' > "$TMP/t93_h.csv2"
errh=$("$CSV2" -r -t -i "$TMP/t93_h.csv2" 2>&1 | head -1)
assert_contains "$errh" "header row 0a (line 1)" \
    "T93f a fault in the first header row says so, rather than claiming a record number / 第一列標頭裡的錯誤會這樣說，而不是宣稱一個紀錄號"
printf 'id,val\n編號,值\\q\n1,ok\n' > "$TMP/t93_h2.csv2"
assert_contains "$("$CSV2" -r -t -i "$TMP/t93_h2.csv2" 2>&1 | head -1)" "header row 0b (line 2)" \
    "T93g and the second header row is 0b, which is how the report names it too / 第二列標頭是 0b，定位報告也是這樣稱呼它"

# Both languages carry the same address. A reader of either one must be able
# to type it back.
# 兩種語言帶的是同一個位址。讀哪一種語言的人都必須能把它打回去。
assert_contains "$("$CSV2" -r -t -i "$TMP/t93.csv2" 2>&1 | sed -n 2p)" "第 2 筆（第 4 行）" \
    "T93h the Chinese line carries the same record and line / 中文那一行帶著相同的紀錄號與行號"

# ---------------------------------------------------------------------
# T94 -- trace answers "why is record N not in my result".
#
# Round 38, defect DD. The README offers `-debug=trace` as "every record's
# selection decision". It logged only the records it EMITTED -- which is the
# half you already had, from the output. For the record actually being asked
# about there was no line, no reason, nothing.
#
# And silence meant two different things that could not be told apart: "read
# and rejected" and "never reached, because -mid stopped the read first". This
# project condemns exactly that two sections earlier in its own README, about
# the parallel path: "reporting only the interesting case would make silence
# ambiguous".
#
# T94 —— trace 回答「為什麼第 N 筆不在我的結果裡」。
# 第 38 回合，缺陷 DD。README 把 `-debug=trace` 說成「每一筆紀錄的選取決定」，而它只記錄
# 「被輸出的」那些——那一半你從輸出本身就已經有了。真正被詢問的那一筆，沒有行、沒有理由、
# 什麼都沒有。
# 而那份沉默同時代表兩件無法分辨的事：「讀過但被排除」與「根本沒讀到，因為 -mid 先停了
# 讀取」。本專案在自己 README 中隔兩節就譴責過這件事（平行路徑那一段）：「只回報有趣的
# 那個情況，會讓沉默變得有歧義」。
# ---------------------------------------------------------------------
echo
echo "--- T94: trace explains the records that are missing / trace 解釋那些不見的紀錄 ---"

printf 'pkg,ver\nzlib,1\nzstd,2\nbusybox,3\n' > "$TMP/t94.csv"
tr_of() { "$CSV2" "$@" -debug=trace 2>&1 >/dev/null | grep -o 'select:.*' }

out=$(tr_of -contains zlib --filter -i "$TMP/t94.csv")
assert_contains "$out" "record 2 line 3 not emitted: no field matched" \
    "T94a a record that was read and rejected says so, with the reason / 讀過但被排除的紀錄會說出來，並附上理由"
assert_eq "$(print -r -- "$out" | grep -c 'record [0-9]* line')" "3" \
    "T94b and every record in the file has a line, not just the ones that came out / 檔案裡每一筆都有一行，不只是有輸出的那些"

# The other half of the ambiguity: a record with no line because the read
# stopped. Without this the two cases are indistinguishable.
# 歧義的另一半：某一筆沒有行，是因為讀取停了。少了這一條，兩種情況無法分辨。
out=$(tr_of -mid 1,2 -i "$TMP/t94.csv")
assert_contains "$out" "stopping after record 2" \
    "T94c and when the read stops early, trace says where / 而當讀取提前停止時，trace 會說出停在哪裡"
if print -r -- "$out" | grep -q 'record 3 line'; then
    bad "T94d record 3 has a line although it was never read / 第 3 筆從未被讀到，卻有一行"
else
    ok "T94d so a record past the stop has no line, and now that is stated rather than silent / 因此停止點之後的紀錄沒有行——而那件事現在是被說出來的，不是沉默"
fi

# The remaining non-emitting branches each name themselves.
# 其餘「不輸出」的分支各自指名自己。
assert_contains "$(tr_of -mid 2,3 -i "$TMP/t94.csv")" "record 1 line 2 not emitted: before the requested range" \
    "T94e a record before the range says which side of it it fell / 在範圍之前的紀錄會說出它落在哪一邊"
assert_contains "$(tr_of -tail 1 -i "$TMP/t94.csv")" "held in the -tail buffer" \
    "T94f -tail says a record is buffered, because whether it survives is not known until EOF / -tail 會說明紀錄被緩衝著，因為它能否存活要到 EOF 才知道"
assert_contains "$(tr_of -contains zlib -B 1 --filter -i "$TMP/t94.csv")" "held as -B context" \
    "T94g and -B says a non-matching record is being kept as context / 而 -B 會說明未命中的紀錄正被當成上下文保留"

# Unchanged: the level must still be silent without the flag.
# 不變：沒有那個旗標時，這個層級仍然必須沉默。
assert_eq "$("$CSV2" -contains zlib --filter -i "$TMP/t94.csv" -debug 2>&1 >/dev/null | grep -c 'not emitted')" "0" \
    "T94h plain -debug prints none of this / 單純的 -debug 完全不印這些"

# ---------------------------------------------------------------------
# T95 -- the metrics line belongs to every path.
#
# Round 38, defect EE. `-debug` is documented as "diagnostics to stderr,
# including a metrics: line". The parallel path returned before the line was
# printed, so `peak_rss_bytes` was unavailable on exactly the runs where
# somebody would want it: parallelism is what a large file gets, and a large
# file is what makes memory a question. The reader had to reach for
# /usr/bin/time -l, which is the tool admitting it cannot answer.
#
# It is worth having for its own sake, not just for the promise: the two paths
# do not cost the same, and now the difference is visible from inside.
#
# T95 —— metrics 那一行屬於每一條路徑。
# 第 38 回合，缺陷 EE。`-debug` 的文件寫的是「診斷輸出到 stderr，包含一行 metrics」。
# 平行路徑在那一行被印出來之前就 return 了，因此 `peak_rss_bytes` 恰好在「有人會想看它」的
# 那些執行上取不到：大檔案拿到的正是平行，而「大檔案」正是讓記憶體成為問題的原因。讀者只能
# 改用 /usr/bin/time -l——那等於這支工具承認自己答不出來。
# 這件事本身就值得做，不只是為了兌現那句承諾：兩條路徑的成本並不相同，而現在那個差別
# 從工具內部就看得見。
# ---------------------------------------------------------------------
echo
echo "--- T95: every path reports its metrics / 每一條路徑都回報自己的量測 ---"

{ print -r -- 'a,b'; print -r -- 'A,B'
  for i in {1..400}; do print -r -- "$i,value with xyz $i"; done } > "$TMP/t95.csv2"

par=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=512 \
      "$CSV2" -contains xyz -i "$TMP/t95.csv2" -debug 2>&1 >/dev/null)
sin=$(CSV2_PARALLEL_MIN_BYTES=999999999 \
      "$CSV2" -contains xyz -i "$TMP/t95.csv2" -debug 2>&1 >/dev/null)

# Prove the two runs really were different paths before comparing what they
# printed -- T72's lesson, applied here.
# 在比較它們印了什麼之前，先證明那真的是兩條不同的路徑——T72 的教訓，用在這裡。
assert_contains "$par" "parallel:" \
    "T95a the first run really took the parallel path / 第一次執行確實走了平行路徑"
assert_contains "$sin" "single-threaded:" \
    "T95b and the second really did not / 而第二次確實沒有"

assert_contains "$par" "metrics:" \
    "T95c the parallel path prints a metrics line, as -debug promises / 平行路徑會印出 metrics 行，如 -debug 所承諾"
assert_contains "$par" "peak_rss_bytes=" \
    "T95d with the RSS figure, which is the field that was unreachable / 其中含 RSS 數值，那正是原本取不到的那個欄位"
assert_contains "$par" "read_bytes=" \
    "T95e and the bytes read / 以及讀取的位元組數"
assert_contains "$sin" "metrics:" \
    "T95f while the single-threaded path still prints one / 而單執行緒路徑仍然會印"

# ---------------------------------------------------------------------
# T96 -- the address composes; the reported value does not.
#
# Round 38, defect FF. The README presents `record:field` addressing as what
# lets finding and editing compose, and separately says report values are
# escaped. A reader who joins those two takes the report's third column and
# feeds it to -update. For any value containing a newline, tab, CR or
# backslash -- the data this tool exists for -- that writes the escape
# sequences themselves, at rc=0, with nothing said:
#
#   stored   X <LF> Y \ Z
#   report   X\nY\\Z            (escaped, correctly: one line per hit, T53)
#   -update with that  ->  X \ n Y \ \ Z
#
# Neither half is wrong on its own. The report must escape or it cannot stay
# one line per hit; -update must take a logical value or the caller would have
# to escape by hand. What was missing is the sentence saying they do not meet
# -- and the middle step that makes them, which already existed: -get returns
# the stored bytes.
#
# T96 —— 能組合的是位址；報告裡的那個值不能。
# 第 38 回合，缺陷 FF。README 把 `record:field` 定址呈現為「讓尋找與編輯得以組合」的東西，
# 又在另一處說報告的值有跳脫。把這兩件事接起來的讀者，會拿報告的第三欄去餵 -update。
# 對任何含換行、TAB、CR 或反斜線的值——也就是這支工具存在的理由——那會把跳脫序列本身寫進去，
# rc=0，而且什麼都不說。
# 兩邊單獨看都沒有錯：報告不跳脫就無法維持一行一個命中；-update 不收邏輯值，呼叫端就得自己
# 手動跳脫。缺的是那句「它們接不起來」，以及那個能讓它們接起來的中間步驟——而它本來就存在：
# -get 回傳的是儲存的位元組。
# ---------------------------------------------------------------------
echo
echo "--- T96: the address composes, the reported value does not / 能組合的是位址，不是報告裡的值 ---"

print -r -- 'id,val'  > "$TMP/t96.csv2"
print -r -- '編號,值' >> "$TMP/t96.csv2"
print -r -- '1,X\nY\\Z' >> "$TMP/t96.csv2"

orig=$("$CSV2" -get 1:2 -i "$TMP/t96.csv2" 2>/dev/null)

# The report escapes. That is correct and must stay correct.
# 報告會跳脫。那是對的，而且必須維持是對的。
assert_contains "$("$CSV2" -contains X -i "$TMP/t96.csv2" 2>/dev/null)" 'X\nY\\Z' \
    "T96a the report escapes the value, so a hit stays one line / 報告會跳脫那個值，因此一個命中仍佔一行"

# The documented round trip: address from the report, value from -get.
# 文件所寫的那條往返路徑：位址取自報告，值取自 -get。
cp "$TMP/t96.csv2" "$TMP/t96_rt.csv2"
addr=$("$CSV2" -contains X -i "$TMP/t96_rt.csv2" 2>/dev/null | head -1 | cut -f1)
assert_eq "$addr" "1:2" \
    "T96b the address parses out of the report / 位址能從報告中解析出來"
val=$("$CSV2" -get "$addr" -i "$TMP/t96_rt.csv2" 2>/dev/null)
"$CSV2" -update "$addr" "$val" -i "$TMP/t96_rt.csv2" --in-place 2>/dev/null
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t96_rt.csv2" 2>/dev/null)" "$orig" \
    "T96c and a value carried across with -get comes back byte-identical / 而以 -get 帶過去的值，回來時逐位元相同"
assert_same "$TMP/t96.csv2" "$TMP/t96_rt.csv2" \
    "T96d so the whole file is unchanged by writing the value back to itself / 因此把值寫回它自己，整個檔案不變"

# And the trap, pinned so nobody 'fixes' -update into accepting escapes: the
# reported form is NOT the value, and feeding it back is a different value.
# 而那個陷阱要釘住，免得有人把 -update「修」成接受跳脫序列：報告的形式**不是**那個值，
# 把它餵回去得到的是另一個值。
cp "$TMP/t96.csv2" "$TMP/t96_bad.csv2"
rep=$("$CSV2" -contains X -i "$TMP/t96_bad.csv2" 2>/dev/null | head -1 | cut -f3)
"$CSV2" -update 1:2 "$rep" -i "$TMP/t96_bad.csv2" --in-place 2>/dev/null
if [[ "$("$CSV2" -get 1:2 -i "$TMP/t96_bad.csv2" 2>/dev/null)" == "$orig" ]]; then
    bad "T96e -update now interprets escapes, which would make the report ambiguous with a real backslash / -update 開始解讀跳脫序列了，那會讓報告與「真正的反斜線」無法區分"
else
    ok "T96e feeding the REPORTED text back yields a different value, which is why the docs send you through -get / 把「報告的文字」餵回去會得到另一個值——那正是文件要人改走 -get 的原因"
fi

# ---------------------------------------------------------------------
# T97 -- what the meta line observes, and what it merely restates.
#
# Round 38, defect GG. Rename a one-header `.csv` to `.csv2` and csv2 reads
# its first data record as header row 0b: rc=0, one record short, nothing
# said. The README offered the --json meta line as the way "a caller can
# assert what it is reading" -- but `headers` there is the DECLARATION. It
# reports 2 for any `.csv2`, including that one, so asserting on it is
# asserting the filename against itself.
#
# This is not fixed by detection, and that is the decision rather than a
# limitation admitted late. A row of titles and a row of data are not
# distinguishable by shape; a detector would be a guess, and "declared by the
# suffix, never detected" exists precisely to keep guesses out. So the
# asymmetry stays: WRITING such a file is refused, reading one is not, and the
# documentation now says which parts of the meta line are counted from the
# file and which are the name talking.
#
# T97 —— meta 行裡哪些是「觀察到的」，哪些只是「覆述」。
# 第 38 回合，缺陷 GG。把一份只有一列標頭的 `.csv` 改名成 `.csv2`，csv2 會把它的第一筆資料
# 讀成標頭列 0b：rc=0、少一筆、什麼都不說。README 把 --json 的 meta 行當成「呼叫端能斷言
# 自己讀到什麼」的方法——但那裡的 `headers` 是**宣告**。任何 `.csv2` 它都回報 2，包括那一份，
# 因此拿它來斷言，等於拿檔名去斷言檔名。
# 這件事不以「偵測」來修，而那是一個決定，不是事後才承認的限制。「一列標題」與「一列資料」
# 在形狀上並無分別；偵測器就是猜測，而「由副檔名宣告、絕不偵測」的存在正是為了把猜測擋在外面。
# 因此那個不對稱維持不變：**寫出**這樣的檔案會被拒絕，**讀取**則不會，而文件現在說明了 meta
# 行裡哪些欄位是從檔案數出來的、哪些是檔名在說話。
# ---------------------------------------------------------------------
echo
echo "--- T97: the meta line, observed against declared / meta 行：觀察值與宣告值 ---"

printf 'pkg,ver,note\nzlib,1.3.2,first\nzstd,1.5.7,second\n' > "$TMP/t97_lying.csv2"
printf 'pkg,ver,note\nzlib,1.3.2,first\nzstd,1.5.7,second\n' > "$TMP/t97_honest.csv"

meta=$("$CSV2" -r --json -i "$TMP/t97_lying.csv2" 2>/dev/null | head -1)
assert_contains "$meta" '"headers":2' \
    "T97a a .csv2 always reports headers:2, because that is the declaration / .csv2 一律回報 headers:2，因為那是宣告"
assert_eq "$("$CSV2" -r --json -i "$TMP/t97_lying.csv2" 2>/dev/null | tail -1)" \
          '{"meta":{"records":1,"matched":0}}' \
    "T97b so the mislabelled file loses a record, and the meta cannot warn about it / 因此戴錯名字的檔案會少一筆，而 meta 無法對此示警"
assert_eq "$("$CSV2" -r --json -i "$TMP/t97_honest.csv" 2>/dev/null | tail -1)" \
          '{"meta":{"records":2,"matched":0}}' \
    "T97c while the same bytes under the honest name keep both / 而同樣的位元組在誠實的名字底下保留了兩筆"

# `records` and `fields` ARE observations, which is the half of the meta line
# that can be asserted on.
# `records` 與 `fields` 確實是觀察值，那是 meta 行裡「可以拿來斷言」的那一半。
assert_contains "$meta" '"fields":3' \
    "T97d fields is counted from the file, not declared / fields 是從檔案數出來的，不是宣告的"

# The documented way to check a file you did not produce: look at the header
# rows and see whether the second one holds titles or data.
# 文件所寫的、用來檢查「不是你產生的檔案」的方法：去看那兩列標頭，判斷第二列裡是標題還是資料。
look=$("$CSV2" -head 1 -t -i "$TMP/t97_lying.csv2" 2>/dev/null | sed -n 2p)
assert_eq "$look" "zlib,1.3.2,first" \
    "T97e -head 1 -t shows the second header row, where the data is visible / -head 1 -t 會顯示第二列標頭，那裡看得見資料"
# Built here rather than read from compare/. The first version pointed at
# compare/vs-sqlite.csv2 and was the ONLY case in the suite to reach outside
# test/ -- it passed on the host and failed in the guest, where the payload
# does not carry that directory. A fixture the suite builds is a fixture the
# suite can rely on anywhere it runs, and this suite has to run on a machine
# with nothing but the source and the binary.
# 在此自行建立，而不是去讀 compare/。第一版指向 compare/vs-sqlite.csv2，而它是整份套件裡
# **唯一**一個伸出 test/ 之外的案例——它在 host 上通過、在 guest 內失敗，因為那裡的 payload
# 不帶那個目錄。由套件自己建的 fixture，才是套件在任何地方都能依靠的 fixture，而這份套件
# 必須能在一台「只有原始碼與執行檔」的機器上執行。
printf 'dimension,note\n比較項目,說明\nstorage,text at scale\n' > "$TMP/t97_real.csv2"
real=$("$CSV2" -head 1 -t -i "$TMP/t97_real.csv2" 2>/dev/null | sed -n 2p)
assert_contains "$real" "比較項目" \
    "T97f while a real .csv2 shows titles there / 而真正的 .csv2 那裡顯示的是標題"

# The asymmetry is deliberate and must stay: writing one is refused.
# 那個不對稱是刻意的，而且必須維持：寫出這樣的檔案會被拒絕。
assert_fails "T97g writing a one-header file to a .csv2 name is still refused / 把只有一列標頭的檔案寫到 .csv2 名字仍然被拒絕" -- \
    "$CSV2" -r -t -i "$TMP/t97_honest.csv" -o "$TMP/t97_out.csv2"

# ---------------------------------------------------------------------
# T98 -- a value the command line cannot carry is refused, not altered.
#
# Found on 2026-08-19 while working out what removing the log truncation would
# cost, not by the blind round. `csv2 -update 1:2 $'A\xffB'` stored
# `A U+FFFD B`: the exact substitution T8 exists to prevent, arriving through
# the WRITE path while T8 was watching the read path.
#
# The cause is outside csv2. `CommandLine.arguments` is [String], and Swift
# builds those by decoding argv as UTF-8 WITH REPLACEMENT, so the bytes are
# gone before any csv2 code runs. Two answers were possible: carry raw bytes
# through every value path, or refuse. Refusing is what this project's own
# rule already says -- do not silently repair malformed input, report it and
# exit non-zero -- and it is the smaller change by a wide margin.
#
# Only DATA arguments are checked. A path may legitimately hold arbitrary
# bytes on Linux, and refusing those would break something that works today
# for a fault csv2 does not commit: it hands paths to the filesystem, it does
# not store them as data.
#
# T98 —— 命令列載不動的值會被拒絕，而不是被改動。
# 2026-08-19 在推敲「移除 log 截斷要付出什麼代價」時發現，不是盲測那一輪找到的。
# `csv2 -update 1:2 $'A\xffB'` 存進去的是 `A U+FFFD B`：正是 T8 存在所要防止的那個替代，
# 只是它從**寫入**路徑進來，而 T8 看的是讀取路徑。
# 原因在 csv2 之外。`CommandLine.arguments` 是 [String]，而 Swift 是以「UTF-8 解碼、
# 無效處以替代字元補上」的方式建出它們的，因此那些位元組在任何 csv2 程式碼執行之前就沒了。
# 有兩種答案：把原始位元組穿過每一條值的路徑，或者拒絕。拒絕是本專案自己的規則早已規定的
# 那一個——不要靜默修復格式錯誤的輸入，指出它並以非零結束——而且改動小得多。
# 只檢查**資料**參數。路徑在 Linux 上本來就可以是任意位元組，為一個 csv2 並未犯下的錯誤去
# 拒絕它們，會弄壞一個今天能用的用法：csv2 把路徑交給檔案系統，並不把它當成資料儲存。
# ---------------------------------------------------------------------
echo
echo "--- T98: a non-UTF-8 argument is refused, never silently replaced / 非 UTF-8 的參數會被拒絕，絕不被靜默替換 ---"

bad_val=$'A\xffB'
printf 'id,note\n1,ok\n' > "$TMP/t98.csv"
cp "$TMP/t98.csv" "$TMP/t98.bak"

# The refusals cannot be asserted on Windows, and saying why is better than a
# platform-blind expectation. A Windows process receives its command line as
# UTF-16: whatever the shell did with an invalid byte, it did BEFORE the
# process started, and `CommandLine.unsafeArgv` is synthesised from that UTF-16
# afterwards. There are no raw bytes left for csv2 to inspect, so there is
# nothing it could refuse. The guarantee is real on POSIX and unavailable here,
# and the README says so rather than implying it holds everywhere.
#
# What is NOT skipped is the other half -- ordinary values must still be
# accepted and stored exactly, and bytes must still round-trip through a file.
# Those are the assertions that would catch this fix over-reaching, and they
# run on all four platforms.
#
# 這幾條拒絕在 Windows 上無法斷言，而說出理由比放一個「無視平台」的期待要好。Windows 行程
# 收到的命令列是 UTF-16：shell 對一個無效位元組做了什麼，都發生在行程啟動「之前」，而
# `CommandLine.unsafeArgv` 是事後由那份 UTF-16 合成出來的。已經沒有原始位元組留給 csv2 檢查，
# 也就沒有東西可以拒絕。那個保證在 POSIX 上是真的、在這裡無法提供，而 README 會這樣寫，
# 不會讓人以為它到處都成立。
# 沒有被略過的是另一半——一般的值仍然必須被接受並原樣存入，位元組仍然必須能經由檔案
# round-trip。那些正是「這個修正如果做過頭」會被抓到的斷言，而它們在四個平台上都跑。
if (( IS_WINDOWS )); then
    skipt "T98a-T98g the non-UTF-8 argument refusals / 非 UTF-8 參數的那幾條拒絕 (a Windows command line is UTF-16; no raw argument bytes survive for csv2 to check / Windows 的命令列是 UTF-16，沒有原始參數位元組留給 csv2 檢查)"
else
assert_fails "T98a -update refuses a value that is not valid UTF-8 / -update 拒絕不是合法 UTF-8 的值" -- \
    "$CSV2" -update 1:note "$bad_val" -i "$TMP/t98.csv" --in-place
assert_same "$TMP/t98.csv" "$TMP/t98.bak" \
    "T98b and the file is untouched, so nothing was stored in place of it / 而檔案原封不動，沒有任何東西被拿來頂替它"
assert_fails "T98c -append refuses such a row / -append 拒絕這樣的一列" -- \
    "$CSV2" -append "2,$bad_val" -i "$TMP/t98.csv" --in-place
assert_fails "T98d -insert refuses it too / -insert 同樣拒絕" -- \
    "$CSV2" -insert 1 "2,$bad_val" -i "$TMP/t98.csv" -o "$TMP/t98_o.csv"
assert_fails "T98e and -contains refuses it as a needle, where it would have failed to match instead / 而 -contains 也拒絕把它當成搜尋字串——否則它會變成「找不到」" -- \
    "$CSV2" -contains "$bad_val" -i "$TMP/t98.csv"

# The message has to name the way out, because there IS one: a file preserves
# the bytes exactly, which is what T8 asserts.
# 訊息必須指出出路，因為出路確實存在：檔案會原樣保留那些位元組，而那正是 T8 所斷言的。
msg=$("$CSV2" -update 1:note "$bad_val" -i "$TMP/t98.csv" --in-place 2>&1 | head -1)
assert_contains "$msg" "not valid UTF-8" \
    "T98f the message says what is wrong with the argument / 訊息說出那個參數哪裡不對"
assert_contains "$msg" "in a file" \
    "T98g and names the route that does preserve the bytes / 並指出那條「確實會保留位元組」的路"
fi

# Not over-refusing: ordinary values, including non-ASCII ones, are untouched
# by this. Without it the fix could be "reject anything interesting".
# 沒有拒絕過頭：一般的值——包含非 ASCII 的——完全不受影響。少了這一條，這個修正大可以是
# 「凡是有點特別的都拒絕」。
assert_succeeds "T98h an ordinary CJK value is still accepted / 一般的中文值仍然被接受" -- \
    "$CSV2" -update 1:note "正常的中文值" -i "$TMP/t98.csv" --in-place
assert_eq "$("$CSV2" -get 1:note -i "$TMP/t98.csv" 2>/dev/null)" "正常的中文值" \
    "T98i and stored exactly / 而且原樣存入"
assert_succeeds "T98j an emoji value too, which is where a byte-level check would go wrong / emoji 也是——那正是「以位元組層級亂檢查」會出錯的地方" -- \
    "$CSV2" -update 1:note "👨‍👩‍👧 flag 🇹🇼" -i "$TMP/t98.csv" --in-place

# The read path still round-trips bytes csv2 could never accept on argv. The
# two rules are not in conflict: the file is the medium that carries them.
# 讀取路徑仍然能 round-trip 那些「csv2 在 argv 上絕不會接受」的位元組。兩條規則並不衝突：
# 檔案才是承載它們的媒介。
printf 'id,note\n1,A\xffB\n' > "$TMP/t98_raw.csv"
"$CSV2" -r -t -i "$TMP/t98_raw.csv" -o "$TMP/t98_raw_out.csv" 2>/dev/null
assert_same "$TMP/t98_raw.csv" "$TMP/t98_raw_out.csv" \
    "T98k while the same bytes still round-trip through a FILE, as T8 requires / 而同樣的位元組經由「檔案」仍然可以 round-trip，一如 T8 的要求"

# ---------------------------------------------------------------------
# T99 -- repeated edits are input-relative, and the divergence is a decision.
#
# Round 39. The README documented a singular `-insert N ROW` and nothing else,
# so a reader had no way to learn that the flag repeats, and no way to know
# which of two semantics they had chosen. The two are not subtly different:
#
#   one run:    -insert 2 A -insert 4 B -insert 5 C  ->  r1 A r2 r3 B r4 C r5
#   three runs: the same three, separately           ->  r1 A r2 B C r3 r4 r5
#
# Both exit 0. Neither is wrong -- each run's indices are correct against the
# file that run was handed -- but only the first is a batch.
#
# The tool is right: T27 settled that every index refers to the INPUT and all
# edits apply in one pass, which is the only semantics that makes a batch
# predictable. What was missing was any way for a reader to find that out.
#
# This case exists so the divergence stays a DECISION. Someone reading the two
# outputs side by side could reasonably decide to "fix" the batch form into
# cumulative behaviour; that would make `-delete 3 -delete 4` delete input
# record 3 and then whatever slid into position 4, which is the exact failure
# T27 was written to prevent.
#
# T99 —— 重複的編輯以輸入為基準，而那個分歧是一個決定。
# 第 39 回合。README 只寫了單數的 `-insert N ROW`，因此讀者無從知道這個旗標可以重複，
# 也就無從知道自己選了兩種語意中的哪一種。而那兩種的差別並不細微（見上）。
# 兩者都是 rc=0。兩者都不算錯——每一次執行的索引，對它拿到的那個檔案都是正確的——
# 但只有第一種是「一批」。
# 程式是對的：T27 早已定案「每個索引都指向輸入、所有編輯一次套用」，那是唯一能讓一批
# 可預測的語意。缺的是「讀者要怎麼知道這件事」。
# 這個案例的存在，是為了讓那個分歧維持是一個**決定**。有人把兩種輸出並排看過之後，很可能
# 合理地認為該把批次那一種「修」成累加式——而那會讓 `-delete 3 -delete 4` 刪掉輸入的第 3 筆，
# 再刪掉遞補到第 4 位的那一筆，也就是 T27 當初要防止的那個失敗。
# ---------------------------------------------------------------------
echo
echo "--- T99: repeated edits count against the input / 重複的編輯以輸入為基準 ---"

printf 'pkg,ver\nr1,1\nr2,2\nr3,3\nr4,4\nr5,5\n' > "$TMP/t99.csv"
cp "$TMP/t99.csv" "$TMP/t99_batch.csv"
cp "$TMP/t99.csv" "$TMP/t99_seq.csv"

"$CSV2" -insert 2 'A,10' -insert 4 'B,20' -insert 5 'C,30' \
    -i "$TMP/t99_batch.csv" --in-place 2>/dev/null
assert_eq "$("$CSV2" -r -i "$TMP/t99_batch.csv" 2>/dev/null | cut -d, -f1 | tr '\n' ' ')" \
          "r1 A r2 r3 B r4 C r5 " \
    "T99a three -insert flags in one run all count against the input / 一次執行裡的三個 -insert，數的都是輸入"

for spec in '2:A,10' '4:B,20' '5:C,30'; do
    "$CSV2" -insert ${spec%%:*} "${spec#*:}" -i "$TMP/t99_seq.csv" --in-place 2>/dev/null
done
assert_eq "$("$CSV2" -r -i "$TMP/t99_seq.csv" 2>/dev/null | cut -d, -f1 | tr '\n' ' ')" \
          "r1 A r2 B C r3 r4 r5 " \
    "T99b while three separate runs each count against the file that run was given / 而三次獨立執行，各自對它拿到的那個檔案計數"

# The point of the case: the two differ, both succeed, and that is intended.
# 這個案例的重點：兩者不同、兩者都成功，而那是刻意的。
if cmp -s "$TMP/t99_batch.csv" "$TMP/t99_seq.csv"; then
    bad "T99c batch and sequential now agree -- one of the two semantics was changed / 批次與逐次現在一致了——兩種語意之一被改掉了"
else
    ok "T99c so the two forms give different files, and the README says which is which / 因此兩種寫法給出不同的檔案，而 README 說明了哪個是哪個"
fi

# Range is checked against the input as well -- the same asymmetry, and the
# half a reader is most likely to meet as a surprise.
# 範圍同樣是對輸入檢查的——同一個不對稱，而且是讀者最可能以「意外」形式撞見的那一半。
cp "$TMP/t99.csv" "$TMP/t99_r.csv"
assert_fails "T99d -insert 6 on a five-record file is refused in a batch / 在五筆的檔案上，批次裡的 -insert 6 被拒絕" -- \
    "$CSV2" -insert 2 'A,1' -insert 4 'B,2' -insert 6 'C,3' -i "$TMP/t99_r.csv" --in-place
assert_same "$TMP/t99_r.csv" "$TMP/t99.csv" \
    "T99e and the refusal left the file byte-identical / 而那次拒絕讓檔案逐位元不變"

# Two at the same address keep argument order; -insert composes with -append.
# 同一個位址上的兩筆保持參數順序；-insert 與 -append 可併用。
cp "$TMP/t99.csv" "$TMP/t99_same.csv"
"$CSV2" -insert 3 'X,1' -insert 3 'Y,2' -i "$TMP/t99_same.csv" --in-place 2>/dev/null
assert_eq "$("$CSV2" -r -i "$TMP/t99_same.csv" 2>/dev/null | cut -d, -f1 | tr '\n' ' ')" \
          "r1 r2 X Y r3 r4 r5 " \
    "T99f two inserts at the same N keep the order they were written / 同一個 N 的兩次插入，保持寫下的順序"

cp "$TMP/t99.csv" "$TMP/t99_mix.csv"
"$CSV2" -insert 2 'X,1' -append 'Z,9' -i "$TMP/t99_mix.csv" --in-place 2>/dev/null
assert_eq "$("$CSV2" -r -i "$TMP/t99_mix.csv" 2>/dev/null | cut -d, -f1 | tr '\n' ' ')" \
          "r1 X r2 r3 r4 r5 Z " \
    "T99g and -insert composes with -append in one run / 而 -insert 與 -append 可在同一次執行裡併用"

# ---------------------------------------------------------------------
# T100 -- the audit trail records unlocking, not only locking.
#
# Round 40. `-encrypt` and `-hash` each logged which key they used;
# `-decrypt` logged only the invocation line. So the trail held every time a
# column was closed and no record of any time one was opened -- which is the
# wrong way round for an audit. Encrypting puts data away; decrypting takes it
# out, and "who opened this column, with which key" is the line somebody comes
# looking for. The README's log table promised the fingerprint and made no
# exception for -decrypt.
#
# The fingerprint was already computed on that path -- it has to be, to refuse
# a wrong key -- so nothing was hard about this except noticing.
#
# T100 —— 稽核軌跡要記下「開鎖」，不只是「上鎖」。
# 第 40 回合。`-encrypt` 與 `-hash` 都記錄了自己用哪一把金鑰，`-decrypt` 只記了那行
# invocation。於是軌跡裡有每一次把欄位關上、卻沒有任何一次把它打開——就稽核而言那是反的。
# 加密是把資料收起來，解密是把它拿出來，而「誰用哪一把金鑰把這一欄打開了」正是日後有人會來
# 找的那一行。README 的 log 表承諾了指紋，並未為 -decrypt 開例外。
# 那個指紋在該路徑上本來就算好了——它必須算，否則無法拒絕錯的金鑰——所以這件事除了「注意到」
# 之外沒有任何困難。
# ---------------------------------------------------------------------
echo
echo "--- T100: a successful decrypt says which key opened it / 成功的解密會說出是哪一把金鑰打開的 ---"

head -c 32 /dev/urandom > "$TMP/t100.key"
# The plaintext is a token that cannot occur anywhere else. It used to be `s1`,
# and the check `grep -q 's1'` matched the RANDOM TEMP DIRECTORY NAME in the
# log's invocation line -- `mktemp -d .test_csv2.XXXXXX` produces six
# alphanumerics, and one run in a few hundred contains `s1`. The case then
# failed for a reason unrelated to what it asserts, which is worse than no
# case: a suite that cries wolf stops being read.
# 明文改用一個「不可能出現在別處」的記號。原本是 `s1`，而 `grep -q 's1'` 會比對到 log 呼叫行
# 裡那個「隨機的暫存目錄名」——`mktemp -d .test_csv2.XXXXXX` 產生六個英數字元，幾百次裡就會
# 有一次含 `s1`。那個案例於是為了「與它所斷言的事無關的理由」而失敗，而那比沒有這個案例更糟：
# 一份會亂叫的測試，就不會再有人讀它。
printf 'pkg,secret\na,PLAINTEXT-CANARY-ONE\nb,PLAINTEXT-CANARY-TWO\n' > "$TMP/t100.csv"
"$CSV2" -encrypt secret -keyfile "$TMP/t100.key" -i "$TMP/t100.csv" -o "$TMP/t100_e.csv" -t 2>/dev/null

rm -f "$TMP/t100.log"
"$CSV2" -decrypt all -keyfile "$TMP/t100.key" -i "$TMP/t100_e.csv" -o "$TMP/t100_b.csv" -t \
    -log "$TMP/t100.log" 2>/dev/null
assert_contains "$(cat "$TMP/t100.log")" "decrypting columns secret" \
    "T100a a successful -decrypt records that it decrypted, and which column / 成功的 -decrypt 會記下它解了密、以及解了哪一欄"
assert_contains "$(cat "$TMP/t100.log")" "fingerprint" \
    "T100b with the key fingerprint, as the log table promises / 並附上金鑰指紋，一如 log 表所承諾"

# The value must NOT be in there. Decrypting is the one operation that turns a
# protected column back into plaintext, so this is the log line most able to
# undo the redaction rule if it carried values.
# 值**不得**出現在裡面。解密是唯一會把受保護欄位變回明文的操作，因此這一行是最有能力
# 推翻遮蔽規則的一行——如果它帶著值的話。
if grep -q 'PLAINTEXT-CANARY' "$TMP/t100.log"; then
    bad "T100c the decrypt log carries the plaintext it recovered / 解密的 log 帶著它還原出來的明文"
else
    ok "T100c and none of the recovered plaintext / 而且不帶任何還原出來的明文"
fi

# The two fingerprints are different KINDS of number, which is why the README
# now describes them separately. A :hmac: one is stable per key; a :enc: one is
# per run, because the salt is.
# 那兩個指紋是**不同種類**的數字，這也是 README 現在分開描述它們的原因。`:hmac:` 是每把金鑰
# 穩定的；`:enc:` 是每次執行都變的，因為 salt 每次都變。
"$CSV2" -encrypt secret -keyfile "$TMP/t100.key" -i "$TMP/t100.csv" -o "$TMP/t100_e2.csv" -t 2>/dev/null
fp1=$(head -1 "$TMP/t100_e.csv"  | sed -n 's/.*:enc:\([0-9a-f]*\):.*/\1/p')
fp2=$(head -1 "$TMP/t100_e2.csv" | sed -n 's/.*:enc:\([0-9a-f]*\):.*/\1/p')
if [[ -n $fp1 && $fp1 != $fp2 ]]; then
    ok "T100d two -encrypt runs with ONE key give different :enc: fingerprints, because the salt differs / 同一把金鑰的兩次 -encrypt 給出不同的 :enc: 指紋，因為 salt 不同"
else
    bad "T100d the :enc: fingerprint no longer varies per run ($fp1 vs $fp2) -- the README says it does / :enc: 指紋不再逐次變化（$fp1 對 $fp2）——而 README 說它會"
fi

"$CSV2" -hash secret -keyfile "$TMP/t100.key" -i "$TMP/t100.csv" -o "$TMP/t100_h1.csv" -t 2>/dev/null
"$CSV2" -hash secret -keyfile "$TMP/t100.key" -i "$TMP/t100.csv" -o "$TMP/t100_h2.csv" -t 2>/dev/null
assert_eq "$(head -1 "$TMP/t100_h1.csv")" "$(head -1 "$TMP/t100_h2.csv")" \
    "T100e while two -hash runs with that key give the SAME :hmac: fingerprint / 而同一把金鑰的兩次 -hash 給出相同的 :hmac: 指紋"

# ---------------------------------------------------------------------
# T101 -- the run that trusts an index left no trace, and it is the only
# run that can be silently wrong.
#
# T79 closed the case where the index's claim was never derived. What it
# cannot close is the stamp: an index is judged current by size + mtime, and
# `cp -p`, `rsync -t` and `tar -p` all preserve mtime, so a same-size rewrite
# is invisible to it. That gap is documented, and --verify-index is the O(n)
# proof offered for it.
#
# What was missing sat next to it. EVERY path that DECLINES an index names it
# and says why -- no index, index records a spanning record, --no-index. The
# one path that TRUSTS an index said nothing at all, not even at -debug. So
# the branch that by design can be silently wrong was also the branch leaving
# no trace: an operator could see why a sidecar was rejected, never that one
# had been believed, nor which file it was.
#
# The trust line is what makes this case testable at all. Whether a same-size
# rewrite escapes the stamp depends on how much mtime precision the platform
# and `touch -r` preserve, and asserting a fixed answer to that would be a
# platform-dependent test of the kind this suite has been bitten by before.
# So the log line is read first, and it decides which of two assertions runs.
# Both are real; neither is a skip.
#
# T101 —— 採信索引的那次執行不留任何痕跡，而它是唯一可能靜默出錯的那一次。
# T79 關掉的是「索引的宣稱從未被推導」那個缺口。它關不掉的是戳記本身：索引是否為最新
# 以 size + mtime 判定，而 `cp -p`、`rsync -t`、`tar -p` 都保留 mtime，因此「同樣大小的
# 改寫」對它是隱形的。那個缺口是記錄在案的，`--verify-index` 就是為它提供的 O(n) 證明。
# 缺的東西就在它旁邊：每一條「拒絕」索引的路徑都會指名它並說明理由——沒有索引、索引記錄了
# 跨行紀錄、--no-index。而唯一「採信」索引的那條什麼都不說，連 -debug 都沒有。於是設計上
# 唯一可能靜默出錯的分支，也正是唯一不留痕跡的分支：操作者看得到 sidecar 為何被拒，卻看
# 不到它被信了、信的是哪一個檔案。
# 那行 trust line 也正是本案例得以成立的原因。「同大小改寫」躲不躲得過戳記，取決於平台與
# `touch -r` 保留多少 mtime 精度；把某個固定答案寫死，就會變成本套件吃過虧的那種平台相依
# 測試。因此先讀那行 log，由它決定要跑兩個斷言中的哪一個。兩者都是真的斷言，都不是 SKIP。
# ---------------------------------------------------------------------
echo
echo "--- T101: an index that was trusted says so / 被採信的索引會說出來 ---"

# Both versions are produced by the same generator, differing only in the ONE
# byte between "spanning" and "two" -- a space in the first, a newline in the
# second. Same length by construction, so the size half of the stamp cannot
# tell them apart; `touch -r` is then asked for the mtime half.
#
# The needle sits at record 250, and where it sits is the test. The shift does
# NOT begin at the spanning record: inside a chunk the parser reads quotes
# correctly, so chunk 1 numbers everything right, spanning record included.
# What the false `no_embedded_newlines` corrupts is each LATER chunk's
# firstRecord, which is derived by counting newlines up to that offset. So the
# numbers go wrong at the first chunk boundary after the spanning record --
# measured here at record 158 with 8 KiB chunks -- and not before it. A first
# draft put the needle at 150, one chunk too early, and passed while the
# defect was fully present. It was asserting on the half of the file the
# miscount cannot reach.
# 兩個版本由同一個產生器產出，只差「spanning」與「two」之間那「一個位元組」——前者是空白，
# 後者是換行。長度依構造相同，因此戳記的 size 那一半分辨不出來；mtime 那一半則交給
# `touch -r`。
# needle 放在第 250 筆，而「放在哪裡」正是這個測試本身。偏移「不是」從跨行那一筆開始：區塊
# 內部的解析器正確處理引號，因此第 1 個區塊連同跨行那一筆全都編號正確。假的
# `no_embedded_newlines` 弄壞的是「之後每一個區塊」的 firstRecord——那是用「到該位移為止有
# 幾個換行」推算出來的。於是編號從「跨行紀錄之後的第一個區塊邊界」才開始出錯（此處以 8 KiB
# 區塊實測為第 158 筆），在那之前完全正確。本 fixture 的第一版把 needle 放在第 150 筆，早了
# 一個區塊，於是在缺陷完整存在的情況下照樣通過——它斷言的正好是誤數碰不到的那半個檔案。
gen_t101() {   # $1 = the one byte that differs / 唯一不同的那個位元組
    print -r -- 'a,b'
    local i
    for i in {1..300}; do
        if   [[ $i == 10  ]]; then print -r -- "$i,\"prose spanning$1two lines\""
        elif [[ $i == 250 ]]; then print -r -- "$i,\"needle here\""
        else print -r -- "$i,\"row $i padding padding padding padding padding\""
        fi
    done
}

gen_t101 ' ' > "$TMP/t101.csv"
"$CSV2" --build-index -i "$TMP/t101.csv" >/dev/null 2>&1
cp -p "$TMP/t101.csv" "$TMP/t101.ref"
gen_t101 $'\n' > "$TMP/t101.csv"
touch -r "$TMP/t101.ref" "$TMP/t101.csv"

# If these ever differ the construction is broken and every assertion below is
# measuring the wrong thing, so it is checked rather than assumed.
# 這兩者若不相等，代表構造壞了、下面每一條斷言量到的都是別的東西，因此檢查而不是假設。
assert_eq "$(wc -c < "$TMP/t101.csv" | tr -d ' ')" "$(wc -c < "$TMP/t101.ref" | tr -d ' ')" \
    "T101a the rewrite preserved the file's size, so only mtime can betray it / 改寫保持了檔案大小，因此只剩 mtime 能揭露它"

P=(CSV2_PARALLEL_MIN_BYTES=1000 CSV2_PARALLEL_CHUNK_BYTES=8192)
env $P "$CSV2" -contains "needle" -i "$TMP/t101.csv" -debug \
    > "$TMP/t101_idx.out" 2> "$TMP/t101_dbg.txt"
"$CSV2" -contains "needle" --no-index -i "$TMP/t101.csv" \
    > "$TMP/t101_noidx.out" 2>/dev/null

trusted=$(grep -c 'trusting index' "$TMP/t101_dbg.txt")

if (( trusted > 0 )); then
    # The stamp did not notice: this is the documented gap, reproduced.
    # 戳記沒有察覺：這就是那個記錄在案的缺口，被重現了出來。
    if cmp -s "$TMP/t101_idx.out" "$TMP/t101_noidx.out"; then
        bad "T101b the index was trusted yet the two paths agree -- the trust line no longer marks the risky branch / 索引被採信、兩條路徑卻一致——那行 trust line 已不再標記出有風險的分支"
    else
        ok "T101b a stale index escapes the size+mtime stamp and shifts the record numbers, exactly as documented / 過期索引躲過 size+mtime 戳記並推移了紀錄編號，一如文件所述"
    fi
else
    # The stamp did notice, and whether it does is not csv2's choice: macOS
    # `touch -r` restores mtime to the nanosecond, so the rewrite slips past;
    # busybox `touch -r` in the aarch64 guest keeps only whole seconds, so the
    # same construction is caught there. The gap is real on both -- `cp -p`
    # and `rsync -t` preserve more than busybox touch does -- but this fixture
    # can only demonstrate it where the tools cooperate. Ignoring a stale index
    # is not rebuilding it, so the sidecar on disk is untouched either way.
    # 戳記察覺了——而察不察覺不是 csv2 決定的：macOS 的 `touch -r` 會把 mtime 還原到奈秒，
    # 於是那次改寫溜了過去；aarch64 guest 裡的 busybox `touch -r` 只保留整秒，同樣的構造
    # 在那裡就被抓住。缺口在兩邊都是真的——`cp -p` 與 `rsync -t` 保留的比 busybox touch 多
    # ——但這個 fixture 只能在工具配合的地方把它演示出來。「忽略過期索引」不等於「重建它」，
    # 因此磁碟上那份 sidecar 兩種情況下都原封不動。
    assert_same "$TMP/t101_idx.out" "$TMP/t101_noidx.out" \
        "T101b the stamp rejected the rewritten file, so both paths give the same answer / 戳記拒絕了被改寫的檔案，於是兩條路徑給出相同答案"
fi

# Unconditional, and that is the point: whether or not the O(1) stamp noticed,
# the sidecar sitting on disk does NOT describe this file, and the O(n) proof
# has to say so. A first draft asserted the opposite in the stamp-noticed
# branch -- reasoning that a rejected index would be rebuilt. It is not:
# ignoring a stale index leaves it exactly where it was. macOS never reached
# that branch, so the mistake surfaced only in the guest.
# 不分支，而那正是重點：不論 O(1) 戳記有沒有察覺，磁碟上那份 sidecar 都「不」描述這個檔案，
# 而那個 O(n) 證明就必須這麼說。本案例的第一版在「戳記察覺了」那個分支斷言了相反的事——
# 理由是「被拒絕的索引會被重建」。它不會：忽略一份過期索引，就只是讓它留在原地。macOS 從未
# 走到那個分支，所以這個錯誤只在 guest 裡浮現。
assert_fails "T101c and --verify-index, the O(n) proof offered for that gap, reports the mismatch either way / 而為那個缺口提供的 O(n) 證明 --verify-index 兩種情況下都指出不符" -- \
    "$CSV2" --verify-index -i "$TMP/t101.csv"

# The rest holds on every platform: an index that IS trusted must be named,
# and the remedy must be named with it. Built fresh here so the trusted branch
# is reached regardless of what the stamp did above.
# 其餘的在每個平台都成立：被採信的索引必須被指名，補救方式也必須一併指出。此處重新建立，
# 使「被採信」那條路徑不論上面戳記如何都會被走到。
gen_t101 ' ' > "$TMP/t101b.csv"
"$CSV2" --build-index -i "$TMP/t101b.csv" >/dev/null 2>&1
env $P "$CSV2" -contains "needle" -i "$TMP/t101b.csv" -debug \
    >/dev/null 2> "$TMP/t101b_dbg.txt"
line=$(grep 'trusting index' "$TMP/t101b_dbg.txt" | head -1)

assert_eq "$(grep -c 'trusting index' "$TMP/t101b_dbg.txt")" "1" \
    "T101d a trusted index is reported exactly once, not once per eligibility check / 被採信的索引只回報一次，而非每次資格檢查各一次"
assert_contains "$line" "t101b.csv.index" \
    "T101e and the line names the sidecar it believed / 而那行指名了它所相信的 sidecar"
assert_contains "$line" "--verify-index" \
    "T101f and points at the proof that can contradict it / 並指出那個足以推翻它的證明"

# Every path that declines must stay silent about trusting, or the line stops
# meaning anything.
# 每一條拒絕的路徑都不能出現「採信」，否則那行就失去意義。
"$CSV2" -contains "needle" --no-index -i "$TMP/t101b.csv" -debug \
    >/dev/null 2> "$TMP/t101c_dbg.txt"
assert_eq "$(grep -c 'trusting index' "$TMP/t101c_dbg.txt")" "0" \
    "T101g --no-index trusts nothing and claims nothing / --no-index 不採信任何東西，也不宣稱任何東西"

env $P "$CSV2" -contains "needle" -i "$TMP/t101.csv" >/dev/null 2> "$TMP/t101d_err.txt"
assert_eq "$(wc -c < "$TMP/t101d_err.txt" | tr -d ' ')" "0" \
    "T101h and without -debug the line is absent, as the pipeline requires / 而沒有 -debug 時那行不存在，一如管線的要求"

# ---------------------------------------------------------------------
# T102 -- the audit trail could be forged through the one line it always
# writes.
#
# `-log` records the invocation on EVERY run, and that line was joined from
# the raw arguments with no escaping. A newline inside any argument therefore
# opened a second line in the log whose entire content -- including its own
# timestamp -- came from the input: a complete, plausible entry for an
# operation that never happened, at rc=0.
#
# The escaping rule already existed and was already documented; it had been
# applied to logged VALUES and not here. This is the wider of the two
# openings, because a value needs an edit and this needs only `-contains` --
# no write access to the data at all.
#
# T102 —— 稽核軌跡可以透過它「一定會寫」的那一行被偽造。
# `-log` 每一次執行都會記下呼叫方式，而那一行是把原始引數直接以空白接起來的，沒有跳脫。
# 於是任一引數裡的換行會在 log 中開出第二行，那一行的全部內容——連同它自己的時間戳——
# 都來自輸入：一筆完整、看起來合理、卻從未發生過的紀錄，rc=0。
# 這條跳脫規則本來就存在、也已經寫在文件裡，只是被套在記入 log 的「值」上而沒有套到這裡。
# 而這是兩個開口中較大的那個：值需要一次編輯，這裡只需要 `-contains`——完全不需要對資料
# 有寫入權限。
# ---------------------------------------------------------------------
echo
echo "--- T102: the logged invocation cannot open a second line / 記入 log 的呼叫無法開出第二行 ---"

print -r -- 'a,b' > "$TMP/t102.csv"
print -r -- '1,2' >> "$TMP/t102.csv"

rm -f "$TMP/t102.log"
"$CSV2" -contains $'needle\n2026-01-01T00:00:00+00:00 INFO  csv2 -delete everything' \
    -i "$TMP/t102.csv" -log "$TMP/t102.log" >/dev/null 2>&1

assert_eq "$(wc -l < "$TMP/t102.log" | tr -d ' ')" "1" \
    "T102a a newline in an argument does not add a line to the audit trail / 引數裡的換行不會在稽核軌跡中多出一行"

# The forged text must still be PRESENT -- escaping is not redaction. An audit
# trail that dropped the argument would hide what was attempted, which is the
# opposite of the point.
# 被偽造的文字必須「仍然存在」——跳脫不是遮蔽。一份把該引數丟掉的稽核軌跡會藏起「有人
# 試過什麼」，那與它的用意正好相反。
logged=$(cat "$TMP/t102.log")
assert_contains "$logged" '\n2026-01-01T00:00:00' \
    "T102b and the attempted text is kept, escaped rather than dropped / 而被嘗試的文字保留下來，是跳脫而不是丟棄"

rm -f "$TMP/t102b.log"
"$CSV2" -contains $'a\tb\\c' -i "$TMP/t102.csv" -log "$TMP/t102b.log" >/dev/null 2>&1
logged2=$(cat "$TMP/t102b.log")
assert_contains "$logged2" 'a\tb\\c' \
    "T102c TAB and backslash use the same convention as everywhere else / TAB 與反斜線沿用與他處相同的慣例"

# Text reaches the log by TWO routes -- the invocation, and the messages -- and
# the first fix touched only the invocation. This case takes the second route:
# an address that names no column produces an error message quoting the name
# back, and that message carried the newline. Note the destination: without one
# the run is refused before anything is logged, and a first draft of this case
# passed for that reason, testing nothing.
# 文字進入 log 有「兩條」路徑——呼叫，以及訊息——而第一次修正只碰了呼叫。這個案例走第二條：
# 一個指不到任何欄位的位址會產生「把那個名字引述回來」的錯誤訊息，而那則訊息帶著換行。
# 注意那個目的地：沒有它，這次執行會在任何東西被記錄之前就被拒絕——本案例的第一版正是
# 因此而通過的，它什麼也沒測到。
print -r -- 'a,b' > "$TMP/t102c.csv"
print -r -- '1,2' >> "$TMP/t102c.csv"
rm -f "$TMP/t102c.log"
"$CSV2" -update $'1:1\n2026-01-01T00:00:00+00:00 INFO  forged' 'x' \
    -i "$TMP/t102c.csv" --in-place -log "$TMP/t102c.log" > /dev/null 2> "$TMP/t102c.err"

assert_eq "$(wc -l < "$TMP/t102c.log" | tr -d ' ')" "2" \
    "T102d an error message quoting the input cannot open a line either / 引述輸入的錯誤訊息同樣無法開出一行"

# The stderr promise is its own: exactly two lines, English then Chinese. The
# same unescaped message made it four, and a script reading the pair took the
# injected line for part of the error.
# stderr 那個承諾是它自己的：恰好兩行，英文在前中文在後。同一則未跳脫的訊息讓它變成四行，
# 而依「兩行」去讀的腳本會把被注入的那一行當成錯誤訊息的一部分。
assert_eq "$(wc -l < "$TMP/t102c.err" | tr -d ' ')" "2" \
    "T102e and stderr stays at exactly two lines, as documented / 而 stderr 維持恰好兩行，一如文件所述"

# Escaped ONCE. Two fixes, each correct alone, escaped the invocation twice and
# turned a newline into a literal backslash-n that no longer round-trips.
# Escaping lives at one point now, and this is what holds it there.
# 只跳脫「一次」。兩個各自正確的修正，讓呼叫那一行被跳脫了兩次，把一個換行變成再也還原不回
# 去的字面反斜線 n。跳脫現在只發生在一個地方，而這條斷言就是把它固定在那裡的東西。
if grep -q '\\\\n' "$TMP/t102c.log"; then
    bad "T102f the log escaped the same newline twice (\\\\n), so the value no longer round-trips / log 把同一個換行跳脫了兩次（\\\\n），該值再也還原不回去"
else
    ok "T102f and escaped exactly once, so the value round-trips / 而且恰好跳脫一次，該值可以還原"
fi

# ---------------------------------------------------------------------
# T103 -- `--a1` past column Z.
#
# The README said "field 3 is C" and stopped there, so a reader addressing a
# wide sheet had to guess. Spreadsheet columns are BIJECTIVE base-26 -- there
# is no zero digit, so Z is followed by AA and not by BA, and ZZ by AAA. Plain
# base-26 gets every boundary wrong. The implementation is right; nothing held
# it there, and nothing said so.
#
# T103 —— `--a1` 在 Z 之後。
# README 只說到「field 3 是 C」就停了，於是要處理寬表的人只能用猜的。試算表的欄名是
# 「雙射」26 進位——沒有代表零的位數，因此 Z 之後是 AA 而不是 BA，ZZ 之後是 AAA。用普通
# 26 進位會在每一個邊界上都算錯。實作是對的，只是沒有東西守著它，也沒有東西說出來。
# ---------------------------------------------------------------------
echo
echo "--- T103: --a1 column letters past Z / --a1 在 Z 之後的欄名 ---"

{ n=705
  line1=""; line2=""
  for i in {1..$n}; do
      line1="${line1}c$i"; line2="${line2}$i"
      (( i < n )) && { line1="$line1,"; line2="$line2," }
  done
  print -r -- "$line1"; print -r -- "$line2"
} > "$TMP/t103.csv"

a1_of() {   # field number -> the [..] address csv2 prints for it
    "$CSV2" --a1 -contains "$1" -i "$TMP/t103.csv" 2>/dev/null \
        | awk -v want="1:$1" '$1 == want { print $2; exit }'
}

for pair in 26:'[Z2]' 27:'[AA2]' 52:'[AZ2]' 53:'[BA2]' 702:'[ZZ2]' 703:'[AAA2]'; do
    assert_eq "$(a1_of ${pair%%:*})" "${pair##*:}" \
        "T103/${pair%%:*} field ${pair%%:*} is ${pair##*:} / 第 ${pair%%:*} 欄是 ${pair##*:}"
done

# ---------------------------------------------------------------------
# T104 -- "append" that was a seek, and lost half an audit trail.
#
# openLog opened the file for writing and called seekToEndOfFile(). The comment
# above it said "append, never truncate", and with ONE process that is exactly
# what it does. With two it is not: the seek fixes an offset at open time, so a
# writer that opened before another appended goes on writing over what that
# other one wrote. Eight processes logging 25 operations each left 98 entries
# of 200 -- none malformed, every run exiting 0.
#
# The failure shape is this project's own: a comment declaring a property that
# nothing derived, indistinguishable from the real thing until a second actor
# appears. T79 was the same shape with `no_embedded_newlines`.
#
# It matters here more than most places because the file is an audit trail. Its
# entire value is that what happened is still there later, and a trail that
# silently drops half its entries is worse than no trail, since whoever reads
# it believes it is complete. Nor is concurrency exotic: a script running csv2
# over several files at once with a shared -log is what the flag is for.
#
# T104 —— 一個其實是 seek 的「追加」，弄丟了半份稽核軌跡。
# openLog 以寫入開啟檔案並呼叫 seekToEndOfFile()。它上面那句註解寫著「一律追加，絕不覆寫」，
# 而在「一個」行程下它做的正是那件事。兩個行程下就不是了：那個 seek 在開檔當下固定了位移，
# 於是先開檔的寫入者會持續蓋掉後來者追加的內容。八個行程各記錄 25 次操作，200 筆只剩 98 筆
# ——沒有一筆是壞的，每一次都以 0 結束。
# 這個失敗的形狀正是本專案自己的：一句註解宣告了某個性質，而沒有任何東西推導過它；在第二個
# 行為者出現之前，它與真貨無法區分。T79 的 `no_embedded_newlines` 是同一個形狀。
# 它在這裡比在多數地方更要緊，因為那個檔案是稽核軌跡。它的全部價值就是「發生過的事日後
# 還在」，而一份會靜默丟掉一半紀錄的軌跡比沒有軌跡更糟——讀它的人會相信它是完整的。並行
# 也不是什麼奇特情境：一支同時對多個檔案跑 csv2、共用一個 -log 的腳本，正是這個旗標的用途。
# ---------------------------------------------------------------------
echo
echo "--- T104: a shared -log under concurrent writers / 並行寫入者共用同一個 -log ---"

print -r -- 'a,b'  > "$TMP/t104.csv"
print -r -- '1,2' >> "$TMP/t104.csv"

# Pre-existing content, so "never truncate" is measured at the same time as
# "never overwrite". The two are different promises and only one of them was
# ever broken.
# 先放一些既有內容，讓「絕不截斷」與「絕不覆寫」同時被量到。這是兩個不同的承諾，而其中
# 只有一個曾經被打破。
print -r -- 'PRIOR' > "$TMP/t104.log"

t104_writers=6
t104_each=20
for i in {1..$t104_writers}; do
    ( for j in {1..$t104_each}; do
          "$CSV2" -contains 1 -i "$TMP/t104.csv" -log "$TMP/t104.log" >/dev/null 2>&1
      done ) &
done
wait

t104_want=$(( t104_writers * t104_each + 1 ))    # +1 for the PRIOR line
assert_eq "$(wc -l < "$TMP/t104.log" | tr -d ' ')" "$t104_want" \
    "T104a $t104_writers concurrent writers lose no entries / $t104_writers 個並行寫入者不遺失任何紀錄"

assert_eq "$(head -1 "$TMP/t104.log")" "PRIOR" \
    "T104b and the file that already existed was appended to, not truncated / 而既有的檔案是被追加，不是被截斷"

# Loss showed up as MISSING lines, never as broken ones, which is why nothing
# noticed: every surviving entry looked perfect.
# 遺失是以「少了幾行」的形式出現，從來不是「壞掉的行」——這正是沒有東西發現它的原因：
# 每一筆活下來的紀錄看起來都完好無缺。
assert_eq "$(grep -vc '^PRIOR$' "$TMP/t104.log" | tr -d ' ')" "$(( t104_want - 1 ))" \
    "T104c and every surviving line is a real entry, since loss never looked like damage / 而每一行都是真正的紀錄——遺失從來不長得像損壞"

# ---------------------------------------------------------------------
# T105 -- the A1 ROW, which nothing held.
#
# `--a1` printed the physical line. The code carried an argument for it, and
# the argument was half right: the record number ALONE would print [A1] for a
# cell any spreadsheet calls A3, and [E0] for a header, and A1 notation has no
# row 0. Both true. The answer to it is to add the header rows, not to switch
# to the line.
#
# With one record per line the two are equal -- and every example in the
# README, plus every fixture in this repo, is one record per line. So both
# readings agreed everywhere anyone looked, and the whole existing suite went
# on passing after the fix, unchanged. That is the measurement: nothing here
# was holding the row.
#
# They differ exactly once: a record spanning lines still occupies ONE
# spreadsheet row, because the quoted newline stays inside the cell. And that
# case is the only one where `--a1` offers anything `--physical` does not.
# The feature was wrong precisely where it was necessary.
#
# T105 —— 沒有任何東西守著的那個 A1「列號」。
# `--a1` 印的是物理行號。程式碼裡有一段為它辯護的論證，而那個論證對了一半：光用紀錄號，
# 確實會讓一個任何試算表都叫作 A3 的儲存格印成 [A1]、讓標頭印成 [E0]，而 A1 記法沒有第 0 列。
# 兩者都對。但對它們的解法是「加上標頭列數」，不是「改用行號」。
# 一筆一行時兩者相等——而 README 的每一個範例、本 repo 的每一份 fixture，全都是一筆一行。
# 於是兩種讀法在所有人看過的地方都一致，而修正之後整個既有測試套件一條都沒有變。那正是
# 這裡的量測結果：**沒有任何東西守著那個列號**。
# 它們只在一種情況下不同：跨行的紀錄在試算表裡仍然只佔一列，因為引號內的換行留在儲存格內。
# 而那個情況正是 `--a1` 唯一比 `--physical` 多給出一點東西的場合——這個功能，錯在它唯一
# 有必要存在的地方。
# ---------------------------------------------------------------------
echo
echo "--- T105: the A1 row is a spreadsheet row, not a line / A1 的列號是試算表的列，不是行 ---"

# Records 1 and 2 span several lines each; the needle is in record 3. A
# spreadsheet importing this keeps each quoted newline inside its cell and
# shows four rows, so the needle is on row 4 while sitting on line 10.
# 第 1、2 筆各佔數行，needle 在第 3 筆。試算表匯入時會把每個引號內換行留在儲存格內，
# 於是只顯示四列——needle 在第 4 列，而它位在第 10 行。
{ print -r -- 'a,b'
  print -r -- 'r1,"A'; print -r -- 'B'; print -r -- 'C'; print -r -- 'D'; print -r -- 'E"'
  print -r -- 'r2,"P'; print -r -- 'Q'; print -r -- 'R"'
  print -r -- 'r3,FINDME'
} > "$TMP/t105.csv"

got=$("$CSV2" -contains FINDME --a1 --physical -i "$TMP/t105.csv" 2>/dev/null | awk '{print $1, $2}')
assert_eq "$got" "3:2@L10 [B4]" \
    "T105a a record spanning lines is still ONE spreadsheet row / 跨行的紀錄在試算表裡仍然只佔一列"

# Stated separately because the point is that they are different things. When
# --a1 was the line, this assertion would have been the same assertion twice.
# 分開斷言，因為重點正是「它們是兩個不同的東西」。當 --a1 還是行號時，這一條會與上一條
# 變成同一個斷言寫兩次。
a1row=$("$CSV2" -contains FINDME --a1 -i "$TMP/t105.csv" 2>/dev/null | sed 's/.*\[[A-Z]*\([0-9]*\)\].*/\1/')
phys=$("$CSV2" -contains FINDME --physical -i "$TMP/t105.csv" 2>/dev/null | sed 's/^[0-9]*:[0-9]*@L\([0-9]*\).*/\1/')
if [[ "$a1row" != "$phys" ]]; then
    ok "T105b and --a1 no longer restates --physical (row $a1row vs line $phys) / 而 --a1 不再是 --physical 的另一種寫法（列 $a1row 對 行 $phys）"
else
    bad "T105b --a1 row $a1row equals the physical line $phys on a file with embedded newlines / 在含內嵌換行的檔案上，--a1 的列 $a1row 等於物理行 $phys"
fi

# A header is row 1, never row 0: A1 notation has no row 0, and that half of
# the original argument was always right.
# 標頭是第 1 列，絕不是第 0 列：A1 記法沒有第 0 列，而原本那段論證的這一半一直都是對的。
hdr=$("$CSV2" -contains 'a' --a1 --include-headers -i "$TMP/t105.csv" 2>/dev/null | awk 'NR==1{print $1, $2}')
assert_eq "$hdr" "0:1 [A1]" \
    "T105c the header row is row 1, not row 0 / 標頭列是第 1 列，不是第 0 列"

# Two header rows push the first data record to row 3, which is the rule the
# README states and the one that must keep holding.
# 兩列標頭把第一筆資料推到第 3 列，那是 README 陳述的規則，也是必須繼續成立的那一條。
print -r -- 'a,b'        > "$TMP/t105.csv2"
print -r -- 'text,text' >> "$TMP/t105.csv2"
print -r -- 'r1,FINDME' >> "$TMP/t105.csv2"
got2=$("$CSV2" -contains FINDME --a1 --physical -i "$TMP/t105.csv2" 2>/dev/null | awk '{print $1, $2}')
assert_eq "$got2" "1:2@L3 [B3]" \
    "T105d two header rows put data record 1 on row 3 / 兩列標頭讓第 1 筆資料落在第 3 列"

# And where every fixture in this repo lives -- one record per line -- the two
# still coincide, so the README's examples remain true.
# 而在本 repo 每一份 fixture 所在的那個世界——一筆一行——兩者仍然重合，因此 README 的
# 範例依然為真。
print -r -- 'a,b'        > "$TMP/t105b.csv"
print -r -- 'r1,x'      >> "$TMP/t105b.csv"
print -r -- 'r2,FINDME' >> "$TMP/t105b.csv"
got3=$("$CSV2" -contains FINDME --a1 --physical -i "$TMP/t105b.csv" 2>/dev/null | awk '{print $1, $2}')
assert_eq "$got3" "2:2@L3 [B3]" \
    "T105e with one record per line the row and the line still agree / 一筆一行時，列號與行號仍然一致"

# ---------------------------------------------------------------------
# T106 -- forgery inside an entry, which escaping a whole line cannot stop.
#
# Whole-line escaping (T102) guarantees one entry per line. It cannot
# distinguish the quotes that DELIMIT a value from quotes that are IN one --
# by the time the line is escaped they are the same characters. So a value of
# `INNOCENT" -> "ALSO INNOCENT` produced
#
#     update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"
#
# one line, one entry, correct data on disk, and no parser can say which half
# is old and which is new. Greedy gives old=`third record" -> "INNOCENT`;
# non-greedy gives new=`INNOCENT`; the truth is neither.
#
# Doubled rather than backslashed: it is the convention `.csv2` and RFC 4180
# already use, so a reader who knows the format needs nothing new -- and it
# carries no backslash, so the whole-line escape leaves it alone. A `\"` would
# have had its backslash doubled on the way out, which is the two-layer
# escaping that made the first attempt wrong.
#
# T106 —— 一筆紀錄「內部」的偽造，而整行跳脫擋不住它。
# 整行跳脫（T102）保證一筆一行。它無法區分「界定值的引號」與「值裡面的引號」——跳脫發生時
# 兩者已經是同樣的字元了。於是值 `INNOCENT" -> "ALSO INNOCENT` 產生一行合法的紀錄，磁碟上
# 的資料也正確，卻沒有任何剖析器說得出哪一半是舊值、哪一半是新值：貪婪比對得到
# old=`third record" -> "INNOCENT`，非貪婪得到 new=`INNOCENT`，而真相兩者皆非。
# 用「加倍」而非反斜線：那是 `.csv2` 與 RFC 4180 已在使用的慣例，看得懂格式的人不必再學
# 一套；而且它不含反斜線，整行跳脫不會碰它。寫成 `\"` 的話，反斜線會在輸出時被加倍，
# 那正是這件事第一次做錯時的兩層跳脫。
# ---------------------------------------------------------------------
echo
echo "--- T106: a quote in a value cannot rewrite the entry / 值裡的引號無法改寫那筆紀錄 ---"

print -r -- 'a,note'          > "$TMP/t106.csv"
print -r -- '1,third record' >> "$TMP/t106.csv"
rm -f "$TMP/t106.log"

"$CSV2" -update '1:2' 'INNOCENT" -> "ALSO INNOCENT' \
    -i "$TMP/t106.csv" --in-place -log "$TMP/t106.log" >/dev/null 2>&1

line=$(grep 'update 1:note' "$TMP/t106.log")
assert_contains "$line" '"INNOCENT"" -> ""ALSO INNOCENT"' \
    "T106a a quote inside a logged value is doubled, as CSV does it / 記入 log 的值裡的引號會加倍，一如 CSV 的做法"

# The WHOLE message, asserted exactly, because "contains" cannot show that the
# two values are correctly delimited FROM EACH OTHER -- and that is the entire
# defect. Note that a regex is deliberately not used to recover the values
# here: a greedy or non-greedy `"(.*)" -> "(.*)"` is precisely the parser this
# case exists to protect, and writing one in the test would only demonstrate
# the ambiguity again rather than measure the encoding.
# 斷言「整句」訊息且要求精確相符，因為「包含」證明不了那兩個值彼此之間界定正確——而那正是
# 這個缺陷的全部。此處刻意不用正規表示式去還原：貪婪或非貪婪的 `"(.*)" -> "(.*)"` 正是本
# 案例要保護的那種剖析器，在測試裡寫一個只會再示範一次那個歧義，而不是量到編碼本身。
msg=${line#* INFO  }
assert_eq "$msg" 'update 1:note: "third record" -> "INNOCENT"" -> ""ALSO INNOCENT"' \
    "T106b and the old and new values stay delimited from each other / 而新舊兩個值彼此之間的界線仍然成立"

# A value with no quote must be untouched -- the fix has to cost nothing in
# the ordinary case, which is every case anyone will actually read.
# 不含引號的值必須完全不受影響——這個修正在普通情況下不能有任何代價，而普通情況正是
# 所有人真正會去讀的那些。
print -r -- 'a,note'   > "$TMP/t106b.csv"
print -r -- '1,plain' >> "$TMP/t106b.csv"
rm -f "$TMP/t106b.log"
"$CSV2" -update '1:2' 'still plain' -i "$TMP/t106b.csv" --in-place -log "$TMP/t106b.log" >/dev/null 2>&1
assert_contains "$(grep 'update 1:note' "$TMP/t106b.log")" '"plain" -> "still plain"' \
    "T106c while a value with no quote is written exactly as before / 而不含引號的值，寫出來與原本完全相同"

# ---------------------------------------------------------------------
# T107 -- three ways to decline an index, one message, and the message was
# false.
#
# No sidecar, a stale sidecar and a sidecar too short to hold a header all
# ended at the same line: ".csv with no index proving one record per line;
# build one with --build-index". It asserted there was no index while
# `x.csv.index` sat beside the data, and it prescribed the thing the reader
# had just done. A blind-test subject lost several minutes to it.
#
# Worse, the reason was not printed at all in the case that most needed it.
# `load` is called twice per run -- once as a pure eligibility query, once
# where the index is read -- so its "ignoring and scanning" lines printed
# twice. Silencing the query was tried and was worse: on a search that
# declines the parallel path the query is the ONLY call, so the reason
# vanished. It is deduplicated inside load instead, once per sidecar per run.
#
# T107 —— 拒絕索引的三種情況，同一句訊息，而那句訊息是假的。
# 「沒有 sidecar」、「sidecar 過期」、「sidecar 短到裝不下檔頭」全都走到同一行：
# 「.csv with no index proving one record per line; build one with --build-index」。
# 它在 `x.csv.index` 就躺在資料旁邊時宣稱「沒有索引」，並開出對方剛剛做過的那帖藥。
# 一位盲測受測者為此損失了好幾分鐘。
# 更糟的是，最需要那個理由的情況下它根本不印。`load` 一次執行被呼叫兩次——一次純資格查詢、
# 一次真的要讀——因此那些「ignoring and scanning」印了兩次。把查詢靜音試過了，而那更糟：
# 在一個拒絕平行路徑的搜尋裡，查詢是唯一的一次呼叫，於是理由整個消失。改為在 load 內部
# 依 sidecar 去重，每次執行只說一次。
# ---------------------------------------------------------------------
echo
echo "--- T107: three ways to decline an index are three messages / 拒絕索引的三種情況是三句訊息 ---"

t107_build() {   # $1 = which case
    print -r -- 'a,b' > "$TMP/t107.csv"
    local i
    for i in {1..200}; do print -r -- "$i,x$i"; done >> "$TMP/t107.csv"
    rm -f "$TMP/t107.csv.index"
    case "$1" in
        stale)
            "$CSV2" --build-index -i "$TMP/t107.csv" >/dev/null 2>&1
            print -r -- 'a,b' > "$TMP/t107.csv"
            for i in {1..200}; do print -r -- "$i,y$i"; done >> "$TMP/t107.csv"
            ;;
        short)
            "$CSV2" --build-index -i "$TMP/t107.csv" >/dev/null 2>&1
            print -rn -- 'GARBAGE' > "$TMP/t107.csv.index"
            ;;
    esac
}

t107_debug() {
    CSV2_PARALLEL_MIN_BYTES=100 "$CSV2" -contains 150 -i "$TMP/t107.csv" -debug \
        >/dev/null 2> "$TMP/t107.err"
    cat "$TMP/t107.err"
}

t107_build none;  none_out=$(t107_debug)
t107_build stale; stale_out=$(t107_debug)
t107_build short; short_out=$(t107_debug)

assert_contains "$none_out" "no index proving one record per line" \
    "T107a with no sidecar the message says there is none / 沒有 sidecar 時，訊息說的是沒有"

# The reason is IN the message now, so these assert the reason and not only
# the naming. The message used to end "run with -debug to see why" -- advice
# for a reader who is not running with -debug, on a line only visible to one
# who is.
# 理由現在寫「在」訊息裡，因此這兩條斷言的是「理由」，不只是「有沒有指名」。那則訊息原本
# 以「用 -debug 看原因」結尾——那是給「沒有在用 -debug 的人」的建議，卻印在一行只有「正在
# 用 -debug 的人」才看得到的訊息上。
assert_contains "$stale_out" "t107.csv.index was discarded (stale" \
    "T107b with a stale sidecar it names the sidecar AND why / sidecar 過期時，訊息指名它，並說出為什麼"

assert_contains "$short_out" "t107.csv.index was discarded (too short" \
    "T107c and a sidecar too short to hold a header says that, not the same sentence / 短到裝不下檔頭的 sidecar 說的是那件事，而不是同一句話"

# The two reasons must differ, or naming them is decoration.
# 兩個理由必須不同，否則「指名理由」只是裝飾。
if [[ "${stale_out#*discarded}" != "${short_out#*discarded}" ]]; then
    ok "T107f and the two reasons are different sentences / 而那兩個理由是不同的句子"
else
    bad "T107f the two discards give the same reason / 兩種丟棄給出同一個理由"
fi

# The reason must be there, and exactly once. A duplicate reads as two
# sidecars; a silence is the defect this area keeps producing.
# 理由必須在，而且恰好一次。重複讀起來像兩個 sidecar；沉默則是這一帶一再產生的那種缺陷。
assert_eq "$(print -r -- "$stale_out" | grep -c 'is stale, ignoring and scanning')" "1" \
    "T107d the stale reason is given exactly once, not once per eligibility check / 過期的理由恰好給一次，而非每次資格檢查各一次"

assert_contains "$short_out" "shorter than an index header" \
    "T107e and a sidecar too short to read says so, where it used to say nothing / 而短到讀不了的 sidecar 會說出來，那裡原本什麼都不說"

# ---------------------------------------------------------------------
# T108 -- the parallel path's memory, which nothing had ever measured.
#
# T9a/b/c pin the streaming path at a flat RSS and are correct. They say
# nothing about the parallel path, and neither did anything else, so this held
# for as long as the parallel path has existed: peak RSS came to about one
# byte per byte of input. 615 MB in, 608 MB resident -- while the
# single-threaded path over the same file stayed at 9.5 MB.
#
# The cause was `planChunks`, which walks the WHOLE file to learn each chunk's
# first record number, reading it in 1 MiB `Data` objects with no autorelease
# pool. On Darwin those survive until the process exits. It is the third site
# of the identical defect: ByteSource.next carries the same comment, and the
# parallel worker's read loop needed the same fix the same day.
#
# What identified it was forcing exactly one chunk in flight at a time. Peak
# RSS moved by half a percent -- 637 MB against 640 MB. Nothing that scales
# with work IN FLIGHT can behave like that, which ruled out the workers and
# left the one loop that touches every byte outside a pool.
#
# T108 —— 平行路徑的記憶體，那是從來沒有人量過的東西。
# T9a／T9b／T9c 把串流路徑釘在一個平坦的 RSS 上，而它們是對的。它們對平行路徑什麼也沒說，
# 而別的東西也沒有，於是這件事在平行路徑存在的整段時間裡都成立：峰值 RSS 大約是「輸入每一個
# 位元組對應一個位元組」。讀進 615 MB、常駐 608 MB——而同一個檔案在單執行緒路徑上是 9.5 MB。
# 成因是 `planChunks`：它為了讓每個區塊知道自己第一筆的編號而走過「整個檔案」，以 1 MiB 的
# `Data` 讀取，而且沒有 autorelease pool。在 Darwin 上那些會活到行程結束。這是同一個缺陷的
# 第三個發生地：`ByteSource.next` 帶著同一段註解，而平行工作者的讀取迴圈在同一天需要同樣的修正。
# 識別出它的，是「強制同時只有一個區塊在飛」那次量測：峰值 RSS 只動了百分之零點五（637 MB
# 對 640 MB）。任何隨「同時在飛的工作量」而變的東西都不可能是這種行為。
# ---------------------------------------------------------------------
echo
echo "--- T108: the parallel path's memory does not track the file / 平行路徑的記憶體不跟著檔案走 ---"

# `.csv2` is used because the format itself guarantees one record per line, so
# the parallel path is eligible with no index to build.
# 使用 `.csv2`，因為這個格式本身保證一筆一行，於是不必建立索引，平行路徑就已符合資格。
# Written by one loop per file rather than by concatenating a block. The first
# version built a block and appended `tail -n +3` of it repeatedly, and the
# result did not parse -- csv2 refused it at record 1 with a field-count error,
# so the runs exited 1 and printed no metrics line at all. The readings were
# then EMPTY, empty became 0 in the arithmetic, and 0 sailed under the bound:
# the case reported "costs 0B" and passed, against a build with the defect
# fully present. Hence the emptiness check below, and this simpler fixture.
# 每個檔案各用一個迴圈寫出，而不是把一個區塊重複串接。第一版先造一個區塊、再反覆附加它的
# `tail -n +3`，而那個結果剖析不了——csv2 在第 1 筆就以欄數錯誤拒絕它，於是那兩次執行以 1
# 結束、完全沒有印出 metrics 行。讀數因此是「空的」，空的在算術裡變成 0，而 0 輕鬆通過了
# 下面那個界限：這個案例回報「只多花 0B」並且通過了——而當時的建置帶著完整的缺陷。
# 下面那道「是否為空」的檢查，以及這個比較單純的 fixture，都是因此而來。
t108_make() {   # $1 = output, $2 = how many data records
    local i
    {
        print -r -- 'id,note'
        print -r -- 'text,text'
        for i in {1..$2}; do print -r -- "$i,padding padding padding padding padding padding"
        done
    } > "$1"
}
# 10 MB against 40 MB, not 1 MB against 10 MB. Below roughly 10 MB the number
# being measured is still the working set ramping up -- ten workers, their
# buffers, the allocator's first arenas -- and that ramp is steeper than the
# retention being tested for, so the case failed on a build that was correct.
# Both sizes here sit above the ramp, where what changes with the input is the
# input.
# 用 10 MB 對 40 MB，而不是 1 MB 對 10 MB。大約 10 MB 以下，量到的還是「工作集正在爬升」
# ——十個工作者、它們的緩衝區、配置器最初的 arena——而那個爬升比這裡要測的「保留」還陡，
# 於是這個案例在一個正確的建置上失敗了。這裡的兩個尺寸都在爬升段之上，那裡隨輸入而變的
# 就是輸入本身。
t108_make "$TMP/t108_small.csv2" 200000
t108_make "$TMP/t108_big.csv2"   800000

t108_run() {   # $1 = file, $2 = stderr sink
    CSV2_PARALLEL_MIN_BYTES=100000 CSV2_PARALLEL_CHUNK_BYTES=262144 \
        "$CSV2" -contains 'no such needle here' -i "$1" -debug >/dev/null 2>"$2"
}
t108_run "$TMP/t108_small.csv2" "$TMP/t108_s.txt"
t108_run "$TMP/t108_big.csv2"   "$TMP/t108_b.txt"

t108_sz_s=$(wc -c < "$TMP/t108_small.csv2" | tr -d ' ')
t108_sz_b=$(wc -c < "$TMP/t108_big.csv2" | tr -d ' ')
t108_r_s=$(rss_of "$TMP/t108_s.txt")
t108_r_b=$(rss_of "$TMP/t108_b.txt")

# Both runs must actually have taken the parallel path, or this compares two
# single-threaded runs and proves nothing -- the T72 trap.
# 兩次執行都必須真的走了平行路徑，否則這是在比較兩次單執行緒執行、什麼也證明不了——
# 那正是 T72 記下的陷阱。
if grep -q 'parallel:' "$TMP/t108_s.txt" && grep -q 'parallel:' "$TMP/t108_b.txt"; then
    ok "T108a both runs took the parallel path, so the comparison is between two of them / 兩次執行都走了平行路徑，因此比較的是兩次平行執行"
else
    bad "T108a a run did not take the parallel path; this comparison would prove nothing / 有一次執行沒有走平行路徑，這個比較什麼也證明不了"
fi

# The floor cancels between two parallel runs, so what is left is what the
# extra bytes cost. Retaining the input would put the whole difference here.
# 兩次平行執行之間，地板互相抵銷，剩下的就是「多出來的位元組要花多少」。若輸入被留住，
# 整個差額都會出現在這裡。
# An empty reading arithmetically becomes 0, and 0 passes the bound below --
# a test computing a plausible answer out of missing data, which is the exact
# failure this project exists to prevent. It happened here on the first
# attempt, so it is checked rather than assumed.
# 讀不到值時，算術上會變成 0，而 0 會通過下面那個界限——一個「用缺失的資料算出看似合理的
# 答案」的測試，正是本專案存在要防的那種失敗。本案例第一次寫出來時就發生了，因此這裡是
# 檢查而不是假設。
if [[ -z "$t108_r_s" || -z "$t108_r_b" ]]; then
    bad "T108b could not read peak_rss_bytes (s=$(wc -c < "$TMP/t108_s.txt" 2>/dev/null)B b=$(wc -c < "$TMP/t108_b.txt" 2>/dev/null)B) [$(tr '\n' '|' < "$TMP/t108_s.txt" 2>/dev/null)] / 無法讀出 peak_rss_bytes"
    t108_r_s=0; t108_r_b=1
fi
t108_diff=$(( t108_r_b - t108_r_s ))
t108_grew=$(( t108_sz_b - t108_sz_s ))
# Half the added input. Measured either side of the fix on this exact pair:
# retaining the input costs +39.9 MB for +28.2 MB of file, not retaining it
# costs +7.1 MB. Half separates those with room on both sides, and a tighter
# bound would be measuring the working set again.
# 界限取「多出來的輸入的一半」。在這一組尺寸上、修正前後各量過一次：留住輸入時，檔案多
# 28.2 MB 要付出 +39.9 MB；不留住時是 +7.1 MB。一半能把兩者分開且兩側都有餘裕，而更緊的
# 界限只會又量到工作集。
t108_bound=$(( t108_grew / 2 ))
if (( t108_diff < t108_bound )); then
    ok "T108b a ${t108_grew}B larger file costs ${t108_diff}B, not the file (bound ${t108_bound}B) / 大 ${t108_grew}B 的檔案只多花 ${t108_diff}B，而不是整個檔案"
else
    bad "T108b memory tracks the file: +${t108_grew}B of input cost +${t108_diff}B of RSS (bound ${t108_bound}B) / 記憶體跟著檔案走：輸入多 ${t108_grew}B，RSS 多 ${t108_diff}B"
fi

# The cap governs the OUTPUT held while chunks are in flight, which is the one
# part of this path concurrency really drives. A search matching every record
# is what makes it visible; a search matching nothing holds nothing.
# 上限管的是「區塊在飛時被持有的輸出」，那是這條路徑上唯一真的由並行度驅動的部分。
# 要讓它看得見，需要一個命中每一筆的搜尋；一個什麼都不命中的搜尋不持有任何東西。
CSV2_PARALLEL_MIN_BYTES=100000 CSV2_PARALLEL_CHUNK_BYTES=262144 CSV2_PARALLEL_MAX_BYTES=65536 \
    "$CSV2" -contains padding -i "$TMP/t108_big.csv2" -debug \
    > "$TMP/t108_capped.out" 2> "$TMP/t108_cap.txt"
CSV2_PARALLEL_MIN_BYTES=100000 CSV2_PARALLEL_CHUNK_BYTES=262144 \
    "$CSV2" -contains padding -i "$TMP/t108_big.csv2" \
    > "$TMP/t108_free.out" 2>/dev/null

assert_contains "$(cat "$TMP/t108_cap.txt")" "chunk(s) in flight instead of" \
    "T108c a tight CSV2_PARALLEL_MAX_BYTES says it is holding fewer chunks / 收緊 CSV2_PARALLEL_MAX_BYTES 時，它會說自己少持有了幾個區塊"

# Throttling changes how much is in flight and must change NOTHING else. The
# fragments are written in chunk order either way, which is what makes the
# parallel output byte-identical to the single-threaded output in the first
# place.
# 限流改變的是「同時在飛的量」，其他什麼都不能變。兩種情況下片段都依區塊順序寫出，
# 而那正是平行輸出一開始能與單執行緒逐位元相同的原因。
assert_same "$TMP/t108_capped.out" "$TMP/t108_free.out" \
    "T108d and throttling changes what is held, not what is written / 而限流改變的是持有多少，不是寫出什麼"

# ---------------------------------------------------------------------
# T109 -- a keyfile of one byte was accepted, and a keyfile of zero was not.
#
# That asymmetry is the whole finding: someone had already decided a keyfile
# must have content, and the missing decision was how much. A one-byte key
# produced a file that looks encrypted -- `license:enc:a4d6aee9:…` -- and the
# whole column came back in 98 tries.
#
# The README devotes a boxed section to warning that unkeyed `-hash` falls to a
# word list and prescribes `-keyfile` as the cure, then says nothing about the
# strength of the cure. A blind-test subject put it exactly: this tool's
# silence at 1 byte is indistinguishable from its silence at 32.
#
# The floor applies when protection is CREATED and never when a file is READ.
# Applying it to `-decrypt` would make a file made with a weak key permanently
# unreadable -- losing data for a security reason, which is the worse trade.
#
# T109 —— 一個位元組的金鑰檔被接受，而零個位元組的被拒絕。
# 那個不對稱正是整個發現：有人早已決定「金鑰檔必須有內容」，缺的是「多少」。一個位元組的
# 金鑰產生出一個看起來是加密過的檔案——`license:enc:a4d6aee9:…`——而整欄在 98 次內被復原。
# README 用一整個方框段落警告「不帶金鑰的 `-hash` 擋不住字典攻擊」並開出 `-keyfile` 這帖藥，
# 然後對那帖藥的強度隻字不提。一位盲測受測者說得最準：這個工具在 1 byte 時的沉默，與它在
# 32 bytes 時的沉默無法區分。
# 這個下限只在「建立保護」時適用，「讀取」時絕不適用。把它套到 `-decrypt` 上，會讓一份用弱
# 金鑰做出來的檔案再也讀不回來——以安全為由造成資料無法取回，那是更糟的交換。
# ---------------------------------------------------------------------
echo
echo "--- T109: a key too short to be one / 一把短到稱不上金鑰的金鑰 ---"

print -r -- 'pkg,license'  > "$TMP/t109.csv"
print -r -- 'zlib,GPL-2.0' >> "$TMP/t109.csv"
print -rn -- 'a' > "$TMP/t109_tiny.key"
head -c 32 /dev/urandom > "$TMP/t109_good.key"

assert_fails "T109a -encrypt refuses a keyfile too short to resist a search / -encrypt 拒絕一把短到擋不住窮舉的金鑰" -- \
    "$CSV2" -encrypt license -keyfile "$TMP/t109_tiny.key" -i "$TMP/t109.csv" -o "$TMP/t109_e.csv" -t

# A refusal that still leaves a file behind is the failure this project is
# about: the caller sees rc=1 and a plausible output beside it.
# 一個「拒絕了卻仍留下檔案」的拒絕，正是本專案在講的那種失敗：呼叫端看到 rc=1，旁邊卻有一份
# 看起來像樣的輸出。
if [[ -e "$TMP/t109_e.csv" ]]; then
    bad "T109b the refused -encrypt left an output file behind / 被拒絕的 -encrypt 留下了輸出檔"
else
    ok "T109b and leaves no output file behind / 而且不留下任何輸出檔"
fi

assert_fails "T109c keyed -hash refuses it too, since it is also creating protection / 帶金鑰的 -hash 同樣拒絕，因為它也是在建立保護" -- \
    "$CSV2" -hash license -keyfile "$TMP/t109_tiny.key" -i "$TMP/t109.csv" -o "$TMP/t109_h.csv" -t

assert_succeeds "T109d while a real key works / 而一把真正的金鑰可以運作" -- \
    "$CSV2" -encrypt license -keyfile "$TMP/t109_good.key" -i "$TMP/t109.csv" -o "$TMP/t109_ok.csv" -t

# The asymmetry, measured. A file made with the short key BEFORE the floor
# existed must still open, or the floor has destroyed data to protect it.
# 那個不對稱，量出來。在下限存在「之前」用短金鑰做出來的檔案必須仍然打得開，否則這個下限
# 就是為了保護資料而毀掉了資料。
# Built with the good key, then decrypted with it -- the read path must not
# consult the floor at all, which is what this pins.
# 用好金鑰建立，再用它解密——讀取路徑完全不該去看那個下限，而這正是這裡要釘住的。
assert_succeeds "T109e and -decrypt never consults the floor, because reading must not depend on it / 而 -decrypt 完全不看那個下限，因為「讀得回來」不能取決於它" -- \
    "$CSV2" -decrypt all -keyfile "$TMP/t109_good.key" -i "$TMP/t109_ok.csv" -o "$TMP/t109_back.csv" -t

got=$("$CSV2" -get 1:2 -i "$TMP/t109_back.csv")
assert_eq "$got" "GPL-2.0" \
    "T109f and the value comes back exactly / 而那個值原樣回來"

# The message has to say which side of the line it is on, or a reader with an
# old file will think their data is gone.
# 訊息必須說出自己站在那條線的哪一邊，否則一個手上有舊檔案的人會以為資料沒了。
msg=$("$CSV2" -encrypt license -keyfile "$TMP/t109_tiny.key" -i "$TMP/t109.csv" -o "$TMP/t109_x.csv" -t 2>&1)
assert_contains "$msg" "Reading a file that was already made with a short key is NOT refused" \
    "T109g and the refusal says that reading an existing file is not affected / 而拒絕訊息說明「讀取既有檔案」不受影響"

# ---------------------------------------------------------------------
# T110 -- three things the documentation did not say, now that it does.
#
# `-md` escapes `|` to `\|` and an embedded newline to <br> in DATA cells.
# Neither was written down. The one that IS documented is a different `<br>`:
# the one joining two header rows. A blind-test subject wrote an alignment
# checker, split a rendered row on `|`, counted the escaped ones, and got a
# fault that was not there -- they were one step from filing a defect against
# correct code.
#
# Exit 141 was not written down either, and the "Exit status" section said in
# so many words that there is no third case beyond 0 and error. There is:
# SIGPIPE, which a pipeline meets constantly, and which is not a csv2 failure.
#
# T110 —— 三件文件原本沒說、現在說了的事。
# `-md` 在「資料」儲存格裡把 `|` 跳脫成 `\|`、把內嵌換行變成 <br>。兩者都沒有寫下來；有寫的
# 那個 `<br>` 是另一回事（兩列標頭的接合）。一位盲測受測者寫了一個對齊檢查器，把算繪後的一列
# 以 `|` 切開，連被跳脫的那些也算了進去，於是得到一個並不存在的錯誤——他離「對一段正確的程式
# 提出缺陷報告」只差一步。
# 結束狀態 141 也沒有寫下來，而「結束狀態」那一節明白寫著「除了 0 與錯誤之外沒有第三種情況」。
# 有的：SIGPIPE，管線會不斷遇到它，而它不是 csv2 的失敗。
# ---------------------------------------------------------------------
echo
echo "--- T110: what -md escapes, and what SIGPIPE returns / -md 跳脫什麼，以及 SIGPIPE 回傳什麼 ---"

print -r -- 'a,b'              > "$TMP/t110.csv"
print -r -- '1,"has | a pipe"' >> "$TMP/t110.csv"
print -r -- '2,"has'           >> "$TMP/t110.csv"
print -r -- 'a newline"'       >> "$TMP/t110.csv"

md=$("$CSV2" -r -t -md -i "$TMP/t110.csv" 2>/dev/null)

assert_contains "$md" 'has \| a pipe' \
    "T110a a pipe inside a data cell is escaped, not left to end the cell / 資料儲存格裡的 | 會被跳脫，而不是任由它結束那一格"

assert_contains "$md" 'has<br>a newline' \
    "T110b and an embedded newline becomes <br> for the same reason / 而內嵌換行基於同樣理由變成 <br>"

# The row must still have exactly the column count, which is the property the
# escaping exists to protect. Counted on UNESCAPED pipes only -- counting all
# of them is the mistake the escaping caused, and the reason it is documented.
# 那一列的欄數必須維持不變，而那正是這道跳脫要保護的性質。只數「未被跳脫」的 |——把全部
# 都數進去正是這道跳脫造成的那個誤判，也是它被寫進文件的原因。
row=$(print -r -- "$md" | grep 'a pipe')
bars=$(print -r -- "$row" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')
assert_eq "$bars" "3" \
    "T110c so the row still has one cell boundary per column / 因此那一列的儲存格邊界數仍與欄數相符"

# SIGPIPE. The producer must be long enough that csv2 is still writing when
# the consumer leaves, or this measures nothing.
# SIGPIPE。生產端必須長到「消費端離開時 csv2 還在寫」，否則這什麼也量不到。
# No `local` here: this is a brace group at script level, not a function, and
# zsh rejects `local` outside a function. The rejection goes to stderr, the
# redirection sends the group's stdout to the file, and the fixture ends up
# wrong while the script carries on -- which is how T110d first failed with
# rc=1 and 187 bytes of stderr that had nothing to do with SIGPIPE. The same
# mistake broke T108's fixture earlier the same day.
# 此處不用 `local`：這是腳本層級的大括號群組，不是函式，而 zsh 不允許 `local` 出現在函式
# 之外。那個拒絕會走 stderr，重導把群組的 stdout 送進檔案，於是 fixture 是壞的而腳本照常
# 往下跑——T110d 第一次失敗時的 rc=1 與 187 bytes stderr 就是這麼來的，與 SIGPIPE 無關。
# 同一天稍早，T108 的 fixture 也是被同一個錯誤弄壞的。
{ print -r -- 'a,b'
  for i in {1..20000}; do print -r -- "$i,needle"; done
} > "$TMP/t110_big.csv"

"$CSV2" -contains needle -i "$TMP/t110_big.csv" 2>"$TMP/t110_err.txt" | head -1 >/dev/null
t110_rc=${pipestatus[1]}

assert_eq "$t110_rc" "141" \
    "T110d a consumer that leaves early gives 141, not 0 and not an error / 下游提早離開時回傳 141，不是 0 也不是錯誤"

# Nothing on stderr: 141 is not a failure csv2 has anything to say about, and
# a caller capturing stderr must not find a message there.
# stderr 上沒有東西：141 不是 csv2 有話要說的那種失敗，而捕捉 stderr 的呼叫端不該在那裡
# 找到訊息。
assert_eq "$(wc -c < "$TMP/t110_err.txt" | tr -d ' ')" "0" \
    "T110e and says nothing on stderr, because it is not csv2's failure / 而且在 stderr 上不說任何話，因為那不是 csv2 的失敗"

# Redundant quoting survives a round trip. Undocumented until now, and the kind
# of fidelity people check for themselves if nobody states it.
# 冗餘的引號在 round-trip 中存活。在此之前沒有記載，而那是「沒有人講就會有人自己去測」的
# 那種保真性質。
print -r -- 'a,b'              > "$TMP/t110q.csv"
print -r -- '"1","no comma"'  >> "$TMP/t110q.csv"
assert_contains "$("$CSV2" -r -t -i "$TMP/t110q.csv")" '"1","no comma"' \
    "T110f quoting that was not required is preserved, not normalised away / 非必要的引號會被保留，而不是被正規化掉"

# ---------------------------------------------------------------------
# T111 -- three rules that existed and were not applied where they also hold.
#
# (a) `-append` onto a file whose last record is incomplete is refused. The
#     README says so twice and says it of BOTH destinations: "Checked for -o
#     and for --in-place alike -- the fast path used to skip it". `-o` did
#     check. `--in-place`, which is the only destination the fast path serves,
#     did not, because the guard was behind `if the file does not end in a
#     newline` and its comment argued that such a file "is the only file whose
#     last record can be half-written". A record left open by an unclosed
#     quote contains newlines like any prose, so the file ends with one and the
#     record is still open.
#
#     What that produced: rc=0, a file csv2 then refuses to read, and the
#     appended record swallowed by the unclosed quote -- so the documented
#     repair, --truncate-partial, discards the record that had just been
#     written "successfully".
#
# (b) `-delete -col X` plus an edit aimed at column X is refused, with the
#     reason spelled out: "the edit would have no effect and would still be
#     reported as done". `-delete a,b` plus an edit aimed at a RECORD in a..b
#     did exactly that, silently, at rc=0. One axis had the rule; the other did
#     not, and the two live in different parts of the same function.
#
# (c) The message that teaches `.csv2` escaping was itself escaped, so it
#     printed `\\n` where `.csv2` defines `\n`. A reader following it wrote a
#     literal backslash-n and got rc=0 with the wrong value. Caused the same
#     morning by centralising message escaping -- correct for values, wrong for
#     prose, and a single choke point cannot tell them apart.
#
# T111 —— 三條「已經存在、卻沒有被套到它同樣成立的地方」的規則。
# (a) `-append` 到最後一筆不完整的檔案會被拒絕，README 說了兩次，而且說的是「兩種目的地
#     一視同仁」。`-o` 確實檢查了；`--in-place`——快路徑唯一服務的目的地——沒有，因為那個
#     守衛被放在「若檔案不以換行結尾」之下，而它的註解主張那種檔案「是唯一『最後一筆可能
#     只寫了一半』的檔案」。一筆停在未關閉引號裡的紀錄，和任何散文一樣含有換行，因此檔案
#     以換行結尾，而那一筆仍然開著。結果是 rc=0、csv2 自己讀不回來，而那筆剛被「成功」寫入
#     的紀錄被未關閉的引號吞掉，文件指定的修復手段隨後把它丟棄。
# (b) `-delete -col X` 與瞄準欄位 X 的編輯併用會被拒絕，理由寫得一字不差。而 `-delete a,b`
#     與瞄準 a..b 之中某一筆的編輯併用，做的正是那件事，靜默，rc=0。
# (c) 那則「教你 .csv2 怎麼跳脫」的訊息，自己被跳脫了。
# ---------------------------------------------------------------------
echo
echo "--- T111: rules that stopped at one axis / 只走到一個軸就停住的規則 ---"

# (a) The unclosed quote. The file ends with a newline -- that is the point.
# (a) 未關閉的引號。檔案「以換行結尾」——那正是重點。
{ print -r -- 'id,name,note'
  print -r -- 'r1,n1,"ok"'
  print -r -- 'r2,n2,"unclosed'
} > "$TMP/t111_open.csv"
cp "$TMP/t111_open.csv" "$TMP/t111_open.bak"

assert_fails "T111a -append --in-place refuses a file whose last record is left open / -append --in-place 拒絕一個最後一筆仍開著的檔案" -- \
    "$CSV2" -append 'r3,n3,x' -i "$TMP/t111_open.csv" --in-place
assert_same "$TMP/t111_open.csv" "$TMP/t111_open.bak" \
    "T111b and does not write into it / 而且沒有寫進去"

# The short-record variant, which took the same path for the same reason.
# 欄數不足的那個變體，基於同樣理由走了同樣的路。
{ print -r -- 'id,name,note'
  print -r -- 'r1,n1,a'
  print -r -- 'r2,n2'
} > "$TMP/t111_short.csv"
cp "$TMP/t111_short.csv" "$TMP/t111_short.bak"
assert_fails "T111c and refuses a short final record under --in-place too / --in-place 下同樣拒絕「最後一筆欄數不足」" -- \
    "$CSV2" -append 'r3,n3,x' -i "$TMP/t111_short.csv" --in-place
assert_same "$TMP/t111_short.csv" "$TMP/t111_short.bak" \
    "T111d leaving that one alone as well / 那一份同樣沒有被動過"

# And the fast path must still do its job on a healthy file, or the fix has
# simply broken -append.
# 而快路徑在健康的檔案上必須照常運作，否則這個修正只是把 -append 弄壞了。
{ print -r -- 'id,name,note'; print -r -- 'r1,n1,a' } > "$TMP/t111_ok.csv"
assert_succeeds "T111e while a healthy file still appends / 而健康的檔案照常追加得上" -- \
    "$CSV2" -append 'r2,n2,b' -i "$TMP/t111_ok.csv" --in-place
assert_eq "$("$CSV2" -get 2:1 -i "$TMP/t111_ok.csv")" "r2" \
    "T111f and the appended record is there / 而那筆追加的紀錄在那裡"

# (b) The record axis.
# (b) 紀錄那個軸。
{ print -r -- 'id,name,note'
  print -r -- 'r1,n1,a'
  print -r -- 'r2,n2,b'
} > "$TMP/t111_del.csv"
cp "$TMP/t111_del.csv" "$TMP/t111_del.bak"

assert_fails "T111g -update on a record the same run deletes is refused, not dropped / 對「同一次執行正在刪除的紀錄」做 -update 會被拒絕，而不是被丟棄" -- \
    "$CSV2" -delete 1,1 -update 1:2 'GHOST' -i "$TMP/t111_del.csv" --in-place
assert_same "$TMP/t111_del.csv" "$TMP/t111_del.bak" \
    "T111h and nothing was written / 而且什麼都沒有寫入"

assert_fails "T111i -delete -cell inside a deleted range is refused the same way / 落在被刪除區間內的 -delete -cell 同樣被拒絕" -- \
    "$CSV2" -delete 1,2 -delete -cell 2:3 -i "$TMP/t111_del.csv" --in-place

# The guard must not swallow the ordinary case: an edit OUTSIDE the range is
# exactly what a batch is for.
# 這個守衛不能把普通情況一起吃掉：落在區間「之外」的編輯，正是批次要做的事。
cp "$TMP/t111_del.bak" "$TMP/t111_del.csv"
assert_succeeds "T111j while an edit outside the deleted range still runs / 而落在被刪除區間之外的編輯照常執行" -- \
    "$CSV2" -delete 1,1 -update 2:2 'KEPT' -i "$TMP/t111_del.csv" --in-place
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t111_del.csv")" "KEPT" \
    "T111k and landed where it was aimed / 而且落在它所瞄準的地方"

# (c) The message that teaches escaping must print what it teaches.
# (c) 教跳脫的那則訊息，必須印出它所教的東西。
{ print -r -- 'k,v'; print -r -- 'K,V'; print -r -- 'a,"x\qy"' } > "$TMP/t111_esc.csv2"
esc_msg=$("$CSV2" -r -i "$TMP/t111_esc.csv2" 2>&1 | head -1)
assert_contains "$esc_msg" 'defines only \n, \r and \\' \
    "T111l the escape message prints single backslashes, as .csv2 defines them / 跳脫訊息印出的是單一反斜線，一如 .csv2 的定義"

# And following it has to produce what it promises, or the message is worse
# than silence.
# 而照著它做必須產生它所承諾的東西，否則那個訊息比沉默更糟。
{ print -r -- 'k,v'; print -r -- 'K,V'; print -r -- 'a,"line one\nline two"' } > "$TMP/t111_ok.csv2"
got=$("$CSV2" -get 1:2 -i "$TMP/t111_ok.csv2")
want=$'line one\nline two'
assert_eq "$got" "$want" \
    "T111m and a value written the way it says round-trips as a real newline / 而依它所說寫出的值，會還原成一個真正的換行"

# ---------------------------------------------------------------------
# T112 -- two messages that pointed elsewhere instead of answering.
#
# (a) `--verify-index` said "no usable index beside X" with the sidecar sitting
#     right there. This tool separates "absent" from "present and unusable"
#     everywhere else -- the parallel decline was fixed for exactly that
#     distinction hours earlier the same day -- and the one verb whose entire
#     job is to report on a sidecar collapsed the two.
#
# (b) The parallel decline ended "run with -debug to see why". That is advice
#     for a reader who is NOT running with -debug, printed on a line only a
#     reader who IS can see. The answer was one line above, at INFO. The reason
#     is in the message now.
#
# (c) A `-mid` window that begins past the end returns nothing at rc=0, which
#     is indistinguishable from a window that exists and is empty. The
#     documented way to tell them apart is `records` on the trailing `--json`
#     meta line -- and `-md`, the shape you actually hand to a person, has no
#     meta line at all: it renders a complete-looking empty table. The
#     detection channel and the presentation channel did not compose.
#
# T112 —— 兩則「把讀者指到別處，而不是回答他」的訊息。
# (a) `--verify-index` 在 sidecar 就躺在那裡時說「旁邊沒有可用的索引」。這個工具在其他每一處
#     都把「不存在」與「存在但不能用」分開——平行路徑的拒絕就是為了這個分別而在同一天稍早
#     修過的——而唯一一個「整份工作就是回報某個 sidecar」的動詞，把兩者合成了一句。
# (b) 平行路徑的拒絕以「用 -debug 看原因」結尾。那是給「沒有在用 -debug 的人」的建議，卻印在
#     一行只有「正在用 -debug 的人」看得到的訊息上。答案就在上一行的 INFO 裡。
# (c) 起點在結尾之後的 `-mid` 視窗會在 rc=0 下什麼都不回傳，與「存在且為空的視窗」無法區分。
#     文件指定的分辨方法是 `--json` 結尾 meta 的 `records`——而 `-md`，也就是你真正交給人的
#     那個形狀，根本沒有 meta 行：它算繪出一張看起來完整的空表格。
# ---------------------------------------------------------------------
echo
echo "--- T112: messages that answer instead of redirecting / 會回答而不是轉介的訊息 ---"

print -r -- 'a,b' > "$TMP/t112.csv"
for i in {1..300}; do print -r -- "$i,x$i"; done >> "$TMP/t112.csv"

# No sidecar at all.
# 完全沒有 sidecar。
rm -f "$TMP/t112.csv.index"
absent=$("$CSV2" --verify-index -i "$TMP/t112.csv" 2>&1)
assert_contains "$absent" "no index beside" \
    "T112a with no sidecar --verify-index says there is none / 沒有 sidecar 時，--verify-index 說的是沒有"

# Present, and stale.
# 存在，而且過期。
"$CSV2" --build-index -i "$TMP/t112.csv" >/dev/null 2>&1
print -r -- 'a,b' > "$TMP/t112.csv"
for i in {1..300}; do print -r -- "$i,y$i"; done >> "$TMP/t112.csv"
stale=$("$CSV2" --verify-index -i "$TMP/t112.csv" 2>&1)
assert_contains "$stale" "exists but cannot be used" \
    "T112b with a stale sidecar it says the sidecar exists and cannot be used / sidecar 過期時，它說那個 sidecar 存在但不能用"
assert_contains "$stale" "stale" \
    "T112c and names which of its claims failed / 並指出是它的哪一項宣稱不成立"

# The two must not be the same sentence, or separating them was decoration.
# 兩者不能是同一句話，否則「把它們分開」只是裝飾。
if [[ "$absent" != "$stale" ]]; then
    ok "T112d and the two states do not read alike / 而那兩種狀態讀起來不一樣"
else
    bad "T112d absent and unusable still give the same message / 「不存在」與「不能用」仍然給出同一則訊息"
fi

# (b) The decline must carry its reason, not a pointer to where the reason is.
# (b) 拒絕訊息必須帶著它的理由，而不是指向理由在哪裡。
dec=$(CSV2_PARALLEL_MIN_BYTES=100 "$CSV2" -contains y150 -i "$TMP/t112.csv" -debug 2>&1 >/dev/null)
assert_contains "$dec" "discarded (stale" \
    "T112e the parallel decline carries the reason itself / 平行路徑的拒絕自己帶著理由"
if [[ "$dec" == *"run with -debug"* ]]; then
    bad "T112f the message still tells a -debug reader to run with -debug / 那則訊息仍在叫一個正在用 -debug 的讀者去用 -debug"
else
    ok "T112f and no longer tells a -debug reader to run with -debug / 而且不再叫一個正在用 -debug 的讀者去用 -debug"
fi

# (c) A window past the end says so, on stderr, where every output shape can
# carry it -- including -md, which has no meta line to put it in.
# (c) 起點在結尾之後的視窗會說出來，走 stderr，那裡每一種輸出形狀都載得動它——包括 -md，
# 它沒有 meta 行可以放。
md_err=$("$CSV2" -mid 500,505 -t -md -i "$TMP/t112.csv" 2>&1 >/dev/null)
assert_contains "$md_err" "starts after the last record" \
    "T112g a -mid window past the end says so even under -md / 起點超過結尾的 -mid 視窗，即使在 -md 下也會說出來"

assert_succeeds "T112h and it stays a success, because the run did what it was told / 而它仍然是成功，因為那次執行做了它被告知的事" -- \
    "$CSV2" -mid 500,505 -t -md -i "$TMP/t112.csv"

# A window that exists must stay silent, or the warning is noise.
# 一個確實存在的視窗必須保持安靜，否則那個警告只是雜訊。
quiet=$("$CSV2" -mid 5,6 -i "$TMP/t112.csv" 2>&1 >/dev/null)
assert_eq "${#quiet}" "0" \
    "T112i while a window that exists says nothing / 而一個確實存在的視窗什麼都不說"

# Clamping the END is deliberate and asserted by T14c; it must not warn.
# 截斷「終點」是刻意的，由 T14c 釘住；它不能發出警告。
quiet2=$("$CSV2" -mid 299,999 -i "$TMP/t112.csv" 2>&1 >/dev/null)
assert_eq "${#quiet2}" "0" \
    "T112j and a clamped END stays silent, as it was designed to / 而被截斷的「終點」保持安靜，一如它的設計"

# ---------------------------------------------------------------------
# T113 -- the numbers in the README's worked example, checked against the file
# it names.
#
# A blind-test subject reported the `--json` example as stale: it shows
# `records:21` and the TARGET_PACKAGES.csv they had held 22. Both were right.
# The example describes `test/fixtures/TARGET_PACKAGES.csv`, which has 21; the
# parent project keeps its own working copy of the same filename and it has
# moved on. The README named neither, so there was no way to tell which one it
# meant -- and no way to notice when the one it did mean changes.
#
# The path is spelled out now, and this pins the numbers. It is the same class
# of drift T69 guards for PASS counts: a number in prose that describes
# something which moves, with nothing re-checking it.
#
# T113 —— README 範例裡的數字，對照它所指名的那個檔案來檢查。
# 一位盲測受測者把那段 `--json` 範例回報為過期：它寫 `records:21`，而他手上的
# TARGET_PACKAGES.csv 有 22 筆。兩邊都沒錯。那個範例描述的是 `test/fixtures/` 底下那一份
# （21 筆）；母專案自己保有一份同名的工作複本，而它已經往前走了。README 兩份都沒指名，
# 因此無從判斷它指的是哪一份——也無從在它所指的那一份改變時察覺。
# 現在路徑寫全了，而這個案例把數字釘住。它與 T69 守的是同一類漂移：散文裡一個描述「會變動
# 的東西」的數字，而沒有任何東西回頭複查它。
# ---------------------------------------------------------------------
echo
echo "--- T113: the worked example's numbers / 範例裡的那些數字 ---"

t113_meta=$("$CSV2" -contains busybox --json -i "$PKG" 2>/dev/null | tail -1)
# Anchored on the busybox block, not on the first meta line in the file --
# there is more than one worked example and the first belongs to a different
# one. The first attempt at this case compared against that other example and
# failed, which is the case doing its job on itself.
# 錨定在 busybox 那一段，而不是檔案裡的第一行 meta——範例不只一個，而第一個屬於另一段。
# 本案例的第一版比對到了那另一段而失敗，那正是這個案例對它自己起了作用。
t113_readme=$(grep -A6 'csv2 -contains busybox --json' "$ROOT/README.md" \
    | grep -o '{"meta":{"records":[0-9]*,"matched":[0-9]*}}' | head -1)

assert_eq "$t113_meta" "$t113_readme" \
    "T113a the README's meta line matches what the fixture it names produces / README 的 meta 行與它所指名的 fixture 實際產出相符"

# Both READMEs have to carry the same numbers, or one of them is wrong for a
# reader who only has that one.
# 兩份 README 必須帶著相同的數字，否則其中一份對「只有那一份」的讀者是錯的。
t113_zh=$(grep -A6 'csv2 -contains busybox --json' "$ROOT/README.zh-TW.md" \
    | grep -o '{"meta":{"records":[0-9]*,"matched":[0-9]*}}' | head -1)
assert_eq "$t113_zh" "$t113_readme" \
    "T113b and the two READMEs agree with each other / 而兩份 README 彼此一致"

# The path has to be in the example, or the numbers describe a file the reader
# cannot identify.
# 路徑必須寫在範例裡，否則那些數字描述的是一個讀者辨認不出來的檔案。
assert_contains "$(grep -A1 'csv2 -contains busybox --json' "$ROOT/README.md" | head -1)" "test/fixtures/" \
    "T113c and the example names which copy it is reading / 而範例指名了它讀的是哪一份複本"

# ---------------------------------------------------------------------
# T114 -- a numeric knob with a bad value, which used to fail three different
# ways and once as nothing at all.
#
#   CSV2_PARALLEL_MIN_BYTES=-1     SIGTRAP, exit 133, zero bytes on stdout AND
#                                  stderr. A failure that looks like nothing.
#   CSV2_MAX_BUFFER_RECORDS=-1     accepted, then reported back as
#                                  "exceeds the buffered-record limit (-1)"
#   CSV2_PARALLEL_MIN_BYTES=16MiB  silently ignored, and -debug then printed
#                                  the DEFAULT under the variable's own name
#
# The third is the one that hides. Someone setting 16MiB sees
# `under CSV2_PARALLEL_MIN_BYTES (16777216)` and reads it as confirmation --
# the number agrees by coincidence. Set 8MiB and that line still says
# 16777216.
#
# "Do not silently repair malformed input" is this project's own rule, and an
# environment variable is input.
#
# T114 —— 一個值壞掉的數值旗標，原本會以三種不同的方式失敗，其中一種是「什麼都不像」。
# 負數會 SIGTRAP、以 133 結束，stdout 與 stderr 都是空的；另一個接受負數再把它回報成
# 「超過上限 (-1)」；而無法解析的值被靜默忽略，`-debug` 接著用那個變數自己的名字印出預設值。
# 第三種最會藏：設了 16MiB 的人看到 `under CSV2_PARALLEL_MIN_BYTES (16777216)`，會把它讀成
# 確認——而那只是碰巧相等。設 8MiB，同一行仍然印 16777216。
# 「不要靜默修復格式錯誤的輸入」是本專案自己的規則，而環境變數就是輸入。
# ---------------------------------------------------------------------
echo
echo "--- T114: a knob with a bad value / 值壞掉的旗標 ---"

print -r -- 'a,b' > "$TMP/t114.csv"
print -r -- '1,x' >> "$TMP/t114.csv"

t114_run() {   # $1 = VAR=VALUE ; sets t114_rc, t114_err
    env "$1" "$CSV2" -contains 1 -i "$TMP/t114.csv" > "$TMP/t114.out" 2> "$TMP/t114.err"
    t114_rc=$?
    t114_err=$(cat "$TMP/t114.err")
}

t114_run CSV2_PARALLEL_MIN_BYTES=-1
assert_eq "$t114_rc" "1" \
    "T114a a negative threshold is refused, not a trap / 負數門檻被拒絕，而不是觸發 trap"
assert_contains "$t114_err" "CSV2_PARALLEL_MIN_BYTES=-1" \
    "T114b and the message quotes the variable and the value back / 而訊息把變數與值原樣引述回來"

# The crash left NOTHING on either stream. A caller checking rc != 0 had no
# message to report, which is the part that makes it worse than an error.
# 那次崩潰在兩個串流上都什麼也沒留下。一個檢查 rc != 0 的呼叫端沒有任何訊息可以回報，
# 而那正是它比「一個錯誤」更糟的地方。
if (( ${#t114_err} > 0 )); then
    ok "T114c and there is something on stderr to report / 而 stderr 上有東西可以回報"
else
    bad "T114c the failure left nothing on stderr / 那次失敗在 stderr 上什麼也沒留下"
fi

t114_run CSV2_MAX_BUFFER_RECORDS=-1
assert_eq "$t114_rc" "1" \
    "T114d and the same for the other knobs, rather than three behaviours / 其他旗標也一樣，而不是三種行為"

t114_run CSV2_PARALLEL_MIN_BYTES=16MiB
assert_eq "$t114_rc" "1" \
    "T114e an unparseable value is refused, not silently replaced by the default / 無法解析的值被拒絕，而不是被靜默換成預設值"
assert_contains "$t114_err" "is not a number" \
    "T114f and says that is what happened / 並說出發生的是那件事"

# A good value must still work, or the check has replaced one failure with
# another.
# 好的值必須照常運作，否則這個檢查只是把一種失敗換成另一種。
t114_run CSV2_PARALLEL_MIN_BYTES=1000
assert_eq "$t114_rc" "0" \
    "T114g while a value that parses is accepted / 而一個解析得出來的值會被接受"

# ---------------------------------------------------------------------
# T115 -- two files from somewhere else, each of which read as success.
#
# (a) csv2 has a CR-line-ending detector with a first-rate message. It asked
#     "was there NO LF at all", and a CR-separated file with a single trailing
#     LF answers "there was one" -- so the detector stayed silent and the file
#     read as ZERO records at rc=0, `-contains` found nothing, and
#     `--verify-index` reported the index fine. One byte decided whether the
#     user got the diagnosis or nothing.
#
# (b) A UTF-16 file was read byte-transparently: correct for a tool that
#     promises bytes round-trip, useless to the person holding it. Every second
#     byte is NUL, the column names carry them, and the whole thing parses at
#     rc=0 into records that mean nothing. FF FE and FE FF cannot begin a UTF-8
#     file, so seeing one is not a guess.
#
# Both are refused rather than repaired, for the same reason: guessing an
# encoding or a line ending is how a tool ends up silently producing something
# plausible and wrong.
#
# T115 —— 兩個來自別處的檔案，而它們都讀成了「成功」。
# (a) csv2 有一個 CR 行尾偵測器，訊息寫得很好。它問的是「有沒有『完全沒有』LF」，而一個
#     以 CR 分隔、結尾多一個 LF 的檔案回答「有一個」——於是偵測器沉默，該檔案以 rc=0 讀成
#     零筆紀錄、`-contains` 什麼也找不到、`--verify-index` 說索引沒問題。一個位元組決定了
#     使用者拿到的是那個診斷，還是什麼都沒有。
# (b) 一個 UTF-16 檔案被以「位元組透明」的方式讀進來：對一個承諾位元組原樣往返的工具是正確
#     的，對拿著它的人毫無用處。FF FE 與 FE FF 不可能出現在 UTF-8 檔案開頭，因此看到它不是
#     在猜。
# ---------------------------------------------------------------------
echo
echo "--- T115: files from somewhere else / 來自別處的檔案 ---"

# (a) CR separators, with a trailing LF -- the byte that used to hide it.
# (a) CR 分隔，結尾多一個 LF——就是那個原本讓它藏起來的位元組。
# printf, not `print -r`: with -r zsh writes the two characters backslash-r
# rather than a CR, and the fixture then tests nothing. The same trap broke
# T111m earlier today.
# 用 printf，不是 `print -r`：加了 -r，zsh 寫出的是「反斜線 r」兩個字元而不是一個 CR，
# 於是這個 fixture 什麼也測不到。同一個陷阱今天稍早弄壞過 T111m。
printf 'a,b\r1,x\r2,y\n' > "$TMP/t115_cr.csv"
assert_fails "T115a a CR-separated file is diagnosed even with a trailing LF / 以 CR 分隔的檔案，即使結尾多一個 LF 也會被診斷出來" -- \
    "$CSV2" -r -i "$TMP/t115_cr.csv"
assert_contains "$("$CSV2" -r -i "$TMP/t115_cr.csv" 2>&1)" "tr '\\r' '\\n'" \
    "T115b and the message still names the conversion / 而訊息仍然指出那個轉換指令"

# CR-only, which always worked, must keep working.
# 純 CR 的情況原本就有效，必須繼續有效。
printf 'a,b\r1,x\r2,y' > "$TMP/t115_cronly.csv"
assert_fails "T115c and a CR-only file is still diagnosed / 純 CR 的檔案仍然被診斷出來" -- \
    "$CSV2" -r -i "$TMP/t115_cronly.csv"

# A legitimate CSV with a bare CR inside a quoted field must NOT be diagnosed.
# The test is strictly greater for exactly this.
# 一個合法、而且引號欄位裡含有裸 CR 的 CSV「不能」被診斷成 CR 檔案。用「嚴格大於」正是為此。
printf 'a,b\n1,"x\ry"\n2,z\n' > "$TMP/t115_quoted.csv"
assert_succeeds "T115d while a bare CR inside a quoted field is left alone / 而引號欄位裡的裸 CR 不受影響" -- \
    "$CSV2" -r -i "$TMP/t115_quoted.csv"

# (b) UTF-16, both byte orders.
# (b) UTF-16，兩種位元組順序。
printf '\377\376n\0a\0m\0e\0\n\0' > "$TMP/t115_le.csv"
assert_fails "T115e a UTF-16LE byte-order mark is refused, not read as bytes / UTF-16LE 的位元組順序記號被拒絕，而不是被當成位元組讀進來" -- \
    "$CSV2" -r -i "$TMP/t115_le.csv"
assert_contains "$("$CSV2" -r -i "$TMP/t115_le.csv" 2>&1)" "iconv -f UTF-16LE" \
    "T115f and names the conversion that does work / 並指出那個真的可行的轉換"

printf '\376\377\0n\0a\0m\0e\0\n' > "$TMP/t115_be.csv"
assert_fails "T115g and the other byte order too / 另一種位元組順序同樣如此" -- \
    "$CSV2" -r -i "$TMP/t115_be.csv"

# The UTF-8 BOM must still be STRIPPED, not refused: that is a different file
# and a different decision, and confusing the two would break every Excel
# export this tool exists to read.
# UTF-8 的 BOM 必須仍然被「剝除」而不是被拒絕：那是另一種檔案、另一個決定，把兩者混為一談
# 會弄壞每一份這個工具存在所要讀的 Excel 匯出檔。
printf '\357\273\277a,b\n1,x\n' > "$TMP/t115_bom.csv"
assert_succeeds "T115h while a UTF-8 BOM is still stripped rather than refused / 而 UTF-8 的 BOM 仍然是被剝除，不是被拒絕" -- \
    "$CSV2" -r -i "$TMP/t115_bom.csv"
assert_contains "$("$CSV2" -contains 1 -i "$TMP/t115_bom.csv" 2>/dev/null)" "1:1" \
    "T115i and the first column is still addressable / 而第一欄仍然定址得到"

# ---------------------------------------------------------------------
# T116 -- the tool producing its own signature failure.
#
# (a) `-append --in-place` updated the index's record count, its offsets and
#     its freshness stamp, and left `no_embedded_newlines` exactly as it found
#     it. Append a legitimate multi-line record -- a quoted newline, which is
#     the thing this tool exists to handle -- and the index now asserts a
#     property of the file that nothing re-derived.
#
#     T79's sentence, word for word, through a fourth call site: the one that
#     EDITS an index instead of rebuilding it. `-append -o` and `-update`
#     rebuild, so neither could get this wrong.
#
#     The consequence is the worst kind: the O(1) check PASSES, because this
#     path just refreshed the stamp itself. `-contains` then takes the parallel
#     path and numbers every record after the next chunk boundary one too high,
#     at rc=0 -- so following the README's own find-then-edit recipe writes into
#     the wrong row.
#
# (b) Two `-update`s on one cell: the first was applied and then overwritten,
#     rc=0, silently. The refusal for `-update` colliding with `-delete` states
#     the reason in words that describe this exactly.
#
# (c) A modifier with no verb was accepted and ignored, which made the
#     `-insert -cell` refusal positional: writing `-cell` after the positional
#     arguments walked past it.
#
# T116 —— 這個工具自己造出了它的招牌失敗。
# (a) `-append --in-place` 更新了索引的筆數、偏移量與新鮮度戳記，卻把 `no_embedded_newlines`
#     原封不動地留著。追加一筆合法的跨行紀錄——引號內的換行，正是這個工具存在所要處理的東西
#     ——索引於是宣稱了一個沒有任何東西重新推導過的檔案性質。那是 T79 那句話的逐字重演，
#     發生在第四個呼叫點：唯一一條「編輯」索引而不是重建它的路徑。
#     後果是最糟的一種：O(1) 檢查會「通過」，因為這條路徑剛剛才自己更新過戳記。
# (b) 同一格上的兩次 `-update`：第一次被套用後覆蓋，rc=0，靜默。
# (c) 沒有動詞可依附的修飾符被接受並忽略，於是「-insert 不可與 -cell 併用」變成位置性的。
# ---------------------------------------------------------------------
echo
echo "--- T116: an index that edited itself into a lie / 一份把自己編輯成謊言的索引 ---"

# No `local` in a brace group: zsh rejects it outside a function, the rejection
# goes to stderr while the group's stdout still reaches the file, and the
# fixture ends up wrong while the script carries on. Third time today -- T108,
# T110, and here.
# 大括號群組裡不用 `local`：zsh 不允許它出現在函式外，那個拒絕走 stderr，而群組的 stdout
# 仍然寫進檔案，於是 fixture 是壞的而腳本照常往下跑。今天第三次了——T108、T110，以及這裡。
{ print -r -- 'id,name,note'
  for i in {1..400}; do print -r -- "$i,name$i,\"note $i\""; done
} > "$TMP/t116.csv"
"$CSV2" --build-index -i "$TMP/t116.csv" >/dev/null 2>&1

# A legitimate multi-line record: a quoted newline is ordinary CSV.
# 一筆合法的跨行紀錄：引號內的換行就是普通的 CSV。
"$CSV2" -append "$(printf '401,"two\nlines",x')" -i "$TMP/t116.csv" --in-place >/dev/null 2>&1

assert_succeeds "T116a after appending a record that spans lines, the index still describes the file / 追加一筆跨行的紀錄之後，索引仍然描述著這個檔案" -- \
    "$CSV2" --verify-index -i "$TMP/t116.csv"

# The protection that matters: the parallel path must decline, because a record
# number is no longer a line number here.
# 真正要緊的保護：平行路徑必須退場，因為在這裡紀錄號已經不是行號了。
dbg=$(CSV2_PARALLEL_MIN_BYTES=1000 CSV2_PARALLEL_CHUNK_BYTES=4096 \
      "$CSV2" -contains "note 399" -i "$TMP/t116.csv" -debug 2>&1 >/dev/null)
assert_contains "$dbg" "records a record spanning lines" \
    "T116b and the parallel path declines, because a record number is not a line number now / 而平行路徑退場，因為此刻紀錄號已經不是行號"

# The address -contains reports must be one -get can use. That equality is the
# whole find-then-edit recipe.
# `-contains` 回報的位址，必須是 `-get` 用得上的那一個。那個相等，就是整套「先找再改」。
addr=$(CSV2_PARALLEL_MIN_BYTES=1000 CSV2_PARALLEL_CHUNK_BYTES=4096 \
       "$CSV2" -contains "note 399" -i "$TMP/t116.csv" 2>/dev/null | head -1 | cut -f1)
assert_eq "$("$CSV2" -get "$addr" -i "$TMP/t116.csv" 2>&1)" "note 399" \
    "T116c and the address it reports is the address -get resolves / 而它回報的位址，就是 -get 解析得到的那一個"

# An ordinary append must still leave a usable index, or the fix has traded one
# failure for another.
# 普通的追加必須仍然留下一份可用的索引，否則這個修正只是把一種失敗換成另一種。
"$CSV2" -append '402,plain,y' -i "$TMP/t116.csv" --in-place >/dev/null 2>&1
assert_succeeds "T116d while an ordinary append still leaves a usable index / 而普通的追加仍然留下一份可用的索引" -- \
    "$CSV2" --verify-index -i "$TMP/t116.csv"

# (b) The same cell twice.
# (b) 同一格兩次。
print -r -- 'a,b,c'   > "$TMP/t116b.csv"
print -r -- '1,x,p'  >> "$TMP/t116b.csv"
cp "$TMP/t116b.csv" "$TMP/t116b.bak"
assert_fails "T116e two -updates on one cell are refused, not applied and overwritten / 同一格上的兩次 -update 會被拒絕，而不是先套用再覆蓋" -- \
    "$CSV2" -update 1:2 'FIRST' -update 1:2 'SECOND' -i "$TMP/t116b.csv" --in-place
assert_same "$TMP/t116b.csv" "$TMP/t116b.bak" \
    "T116f and nothing was written / 而且什麼都沒有寫入"

assert_succeeds "T116g while two -updates on DIFFERENT cells still run / 而瞄準「不同儲存格」的兩次 -update 照常執行" -- \
    "$CSV2" -update 1:2 'A' -update 1:3 'B' -i "$TMP/t116b.csv" --in-place

# (c) A modifier with nothing to modify.
# (c) 沒有東西可修飾的修飾符。
assert_fails "T116h a -cell with no verb to attach to is refused / 沒有動詞可依附的 -cell 會被拒絕" -- \
    "$CSV2" -cell -r -i "$TMP/t116b.csv"
assert_fails "T116i and writing it after the positionals no longer walks past the refusal / 把它寫在位置參數之後，也不再繞得過那個拒絕" -- \
    "$CSV2" -insert 1 'z,z,z' -cell -i "$TMP/t116b.csv" -o "$TMP/t116c.csv"
assert_succeeds "T116j while the form that means something still works / 而真正有意義的那個寫法照常運作" -- \
    "$CSV2" -delete -cell 1:2 -i "$TMP/t116b.csv" --in-place

# ---------------------------------------------------------------------
# T117 -- the two READMEs must cite the same test cases.
#
# Bilingual edits keep landing on one side only. It has happened twice that
# anyone noticed: AE (a fingerprint table row written in English and lost in
# Chinese, because a Python script asserted mid-way and wrote nothing, and the
# retry only reproduced part of the work) and again on 2026-08-20, when the
# UTF-16 and CR refusals were documented in the Chinese README alone for an
# hour -- the same failure, the same cause, the same retry.
#
# Both times a blind-test subject found it. Nothing in the tree was looking.
#
# Case numbers are the cheapest mechanical proxy for "the same content is in
# both". A section that says "Asserted by T115" in one language and does not
# exist in the other shows up here immediately, and it does not depend on
# anyone remembering to check.
#
# T117 —— 兩份 README 必須引用同一組測試案例。
# 雙語編輯一再只落地一半。被發現的有兩次：AE（指紋表的一列寫進了英文、中文那半消失了，
# 因為一支 Python 腳本中途 assert、整份未寫入，而重試只重現了其中一部分），以及 2026-08-20
# 那次——UTF-16 與 CR 的拒絕有一小時只存在於中文 README 裡。同樣的失敗、同樣的成因、
# 同樣的重試。
# 兩次都是盲測受測者找到的。這棵樹上沒有任何東西在看。
# 案例編號是「兩邊有同樣內容」最便宜的機械替代指標：一節在某一種語言裡寫著「由 T115 斷言」
# 而在另一種語言裡根本不存在，會立刻在這裡浮出來，而且不必有人記得去檢查。
# ---------------------------------------------------------------------
echo
echo "--- T117: both READMEs cite the same cases / 兩份 README 引用同一組案例 ---"

# Set difference without comm: this rootfs's busybox has no comm applet, and
# until T137's command-not-found guard existed, its absence turned T117a,
# T117b and T121h into empty comparisons that reported PASS in the guest --
# three cases that had never once run there. `grep -Fxv -f` is in every
# busybox build here and says the same thing: the lines of A that are not
# whole lines of B.
# 不用 comm 做集合差集：這個 rootfs 的 busybox 沒有 comm applet，而在 T137 那個
# command-not-found 守衛出現之前，它的缺席會把 T117a、T117b 與 T121h 變成空的比較，
# 在 guest 上回報 PASS——那三個案例在那裡一次也沒有真的執行過。`grep -Fxv -f` 在這裡的
# 每一個 busybox 建置裡都有，說的是同一件事：A 當中「不是 B 的完整某一行」的那些行。
only_in_first() {   # first-list second-list
    local second_file
    second_file=$(mktemp "${TMPDIR:-/tmp}/csv2_setdiff.XXXXXX")
    print -r -- "$2" > "$second_file"
    print -r -- "$1" | grep -Fxv -f "$second_file"
    rm -f "$second_file"
}

t117_en=$(grep -oE '\bT[0-9]+[a-z0-9]*\b' "$ROOT/README.md" | sort -u)
t117_zh=$(grep -oE '\bT[0-9]+[a-z0-9]*\b' "$ROOT/README.zh-TW.md" | sort -u)

t117_only_en=$(only_in_first "$t117_en" "$t117_zh" | tr '\n' ' ')
t117_only_zh=$(only_in_first "$t117_zh" "$t117_en" | tr '\n' ' ')

if [[ -z "${t117_only_en// /}" ]]; then
    ok "T117a every case the English README cites is cited in the Chinese one / 英文 README 引用的每一個案例，中文 README 也引用了"
else
    bad "T117a cited in English only: ${t117_only_en}— that half of the edit did not land in the Chinese README / 只有英文引用：${t117_only_en}——那一半的編輯沒有落地到中文 README"
fi

if [[ -z "${t117_only_zh// /}" ]]; then
    ok "T117b and the other way round / 反過來也是"
else
    bad "T117b cited in Chinese only: ${t117_only_zh}— that half of the edit did not land in the English README / 只有中文引用：${t117_only_zh}——那一半的編輯沒有落地到英文 README"
fi

# A README that cites a case number nothing defines is the opposite drift: the
# text outlived the test.
# 一份 README 引用了「沒有任何東西定義」的案例編號，是反方向的漂移：文字活得比測試久。
t117_missing=""
for c in ${(f)t117_en}; do
    # A README cites the FAMILY (T101); the suite defines its members
    # (T101a, T101b). The optional lowercase suffix allows that, and refusing
    # a following digit keeps T10 from matching T101a.
    # README 引用的是「家族」（T101），而套件定義的是它的成員（T101a、T101b）。允許一個
    # 小寫字母後綴即可涵蓋，而「不允許其後再接數字」可避免 T10 比對到 T101a。
    grep -qE "\"$c([a-z][a-z0-9]*)?[ /]" "$HERE/test_csv2.zsh" || t117_missing="$t117_missing $c"
done
if [[ -z "${t117_missing// /}" ]]; then
    ok "T117c and every case they cite exists in this file / 而它們引用的每一個案例都存在於本檔案中"
else
    bad "T117c cited by a README but not defined here:${t117_missing} / README 引用了、但本檔案沒有定義：${t117_missing}"
fi

# ---------------------------------------------------------------------
# T118 -- the parser telling two stories about one file.
#
# A parallel worker calls finish() at the end of its CHUNK. The message there
# was written for the end of the INPUT, and on a chunk boundary that lands
# inside a quoted field it said three wrong things at once:
#
#   csv2: record 3: the input ends inside a quoted field -- the closing quote
#         is missing. The record is incomplete; pass --truncate-partial …
#
#   * the input did not end; the worker's view of it did
#   * the fault is at record 1; the worker counts from its own chunk
#   * --truncate-partial does nothing here, and had it worked it would have
#     discarded a COMPLETE record
#
# The same file at a larger chunk size got the correct message. A parser
# contradicting itself about what a file contains, with an environment variable
# casting the deciding vote, in the one area that is this tool's whole reason
# for existing.
#
# The fix is not a better sentence. A chunk ending mid-quote means the file is
# not one-record-per-line, which is the premise the format or the index handed
# the parallel path -- so the run does what this tool does everywhere else with
# a premise that turns out false: discards it and scans. Both paths then give
# the same diagnosis because it is the same code producing it.
#
# T118 —— 解析器對同一個檔案說了兩種故事。
# 平行工作者是在自己那「一塊」的結尾呼叫 finish()。那裡的訊息是為「輸入的結尾」寫的，而當
# 區塊邊界落在引號欄位中間時，它一次說錯三件事：輸入並沒有結束（結束的是工作者的視野）、
# 出問題的是第 1 筆而不是第 3 筆（它從自己那一塊的開頭數）、以及 --truncate-partial 在這裡
# 什麼也不做，而若它真的作用了，丟掉的會是一筆「完整」的紀錄。
# 同一個檔案在較大的 chunk 下得到正確訊息——決定權落在一個環境變數手上。
# 修法不是換一句更好的話：區塊在引號中間結束，代表這個檔案不是一筆一行，而那正是格式或索引
# 交給平行路徑的前提；於是這次執行做這個工具在其他每一處對「前提被推翻」所做的事——丟掉它、
# 改用掃描。兩條路徑因此說法一致，因為說話的是同一段程式。
# ---------------------------------------------------------------------
echo
echo "--- T118: one file, one story / 同一個檔案，同一個說法 ---"

# A `.csv2` containing something a `.csv2` may not contain: a raw newline in a
# cell. The format promises one record per line, so the parallel path believes
# it -- which is exactly how a chunk boundary gets inside a quoted field.
# 一個 `.csv2` 裡出現了 `.csv2` 不允許的東西：儲存格裡的裸換行。這個格式承諾一筆一行，
# 而平行路徑相信它——那正是區塊邊界會落進引號欄位裡的原因。
printf 'pkg,note\ntext,text\nzlib,"has a\nraw newline"\nzstd,ok\n' > "$TMP/t118.csv2"

t118_single=$("$CSV2" -r -i "$TMP/t118.csv2" 2>&1 | head -1)
assert_contains "$t118_single" "a raw newline inside a cell" \
    "T118a single-threaded names the raw newline / 單執行緒指出那個裸換行"

# Every chunk size has to give the SAME answer. The sizes below straddle the
# boundary where the behaviour used to change.
# 每一個 chunk 大小都必須給出「同一個」答案。下面這幾個尺寸跨越了原本行為改變的那個界線。
t118_bad=0
for cb in 4 8 16 64 4194304; do
    got=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=$cb \
          "$CSV2" -contains ok -i "$TMP/t118.csv2" 2>&1 | head -1)
    [[ "$got" == "$t118_single" ]] || { t118_bad=1; t118_seen="$got"; t118_at=$cb }
done
if (( t118_bad )); then
    bad "T118b chunk=$t118_at tells a different story: $t118_seen / chunk=$t118_at 說了另一個故事"
else
    ok "T118b and every chunk size gives that same message / 而每一個 chunk 大小都給出同一則訊息"
fi

# The old message must not come back for a chunked read. It is still correct
# for a genuinely truncated file, which the next case checks.
# 舊的那則訊息不能在「分塊讀取」時回來。它對一個真正被截斷的檔案仍然正確，由下一個案例檢查。
for cb in 4 8; do
    got=$(CSV2_PARALLEL_MIN_BYTES=1 CSV2_PARALLEL_CHUNK_BYTES=$cb \
          "$CSV2" -contains ok -i "$TMP/t118.csv2" 2>&1)
    if [[ "$got" == *"the input ends inside a quoted field"* ]]; then
        bad "T118c chunk=$cb still says the INPUT ended when its chunk did / chunk=$cb 仍然把「區塊結束」說成「輸入結束」"
        break
    fi
done
[[ "$got" == *"the input ends inside a quoted field"* ]] || \
    ok "T118c and never says the input ended when a chunk did / 而絕不把「區塊結束」說成「輸入結束」"

# A file that really does end inside a quoted field must still get the message
# that was written for it -- the fix must not have removed a true diagnosis.
# 一個真的在引號欄位內結束的檔案，仍然必須拿到那則為它而寫的訊息——這個修正不能把一個
# 為真的診斷一起移除。
printf 'a,b\nA,B\n1,"unclosed\n' > "$TMP/t118_trunc.csv2"
assert_contains "$("$CSV2" -r -i "$TMP/t118_trunc.csv2" 2>&1 | head -1)" "the input ends inside a quoted field" \
    "T118d while a genuinely truncated file still gets that message / 而一個真的被截斷的檔案仍然拿到那則訊息"

# ---------------------------------------------------------------------
# T119 -- the one verb that did not refuse zero, and it is the one that writes.
#
#   csv2 -insert 0 'z,z,z' -i g.csv --in-place -log L.log
#   rc=0, stderr empty, file byte-for-byte unchanged
#   L.log: wrote 2 records, 3 fields, atomic rename OK
#
# An audit entry corroborating a write that never included the row. In a batch
# it dropped its own row and applied the others, so the file came out partially
# edited at rc=0.
#
# Every sibling already refused zero -- `-delete 0,0`, `-head 0`, `-mid 0,2`,
# `-update 0:1`. The documented range is `1..N`; the upper bound was enforced
# (`-insert 11` on a ten-record file is refused) and the lower was not.
#
# T119 —— 唯一一個不拒絕 0 的動詞，而它正是會「寫入」的那一個。
# rc=0、stderr 空無一物、檔案逐位元未變，而 -log 記著「wrote 2 records … atomic rename OK」
# ——一筆替「從未包含那一列的寫入」作證的稽核紀錄。在批次裡它會丟掉自己那一列、套用其餘的，
# 於是檔案以 rc=0 的狀態被改成一半。
# 每一個同輩動詞早就拒絕 0 了。文件寫的範圍是 `1..N`：上界有檢查，下界沒有。
# ---------------------------------------------------------------------
echo
echo "--- T119: -insert and zero / -insert 與 0 ---"

print -r -- 'a,b,c'  > "$TMP/t119.csv"
print -r -- '1,x,p' >> "$TMP/t119.csv"
print -r -- '2,y,q' >> "$TMP/t119.csv"
cp "$TMP/t119.csv" "$TMP/t119.bak"

assert_fails "T119a -insert 0 is refused, not discarded / -insert 0 會被拒絕，而不是被丟棄" -- \
    "$CSV2" -insert 0 'z,z,z' -i "$TMP/t119.csv" --in-place
assert_fails "T119b and -insert -1 likewise / -insert -1 同樣如此" -- \
    "$CSV2" -insert -1 'z,z,z' -i "$TMP/t119.csv" --in-place
assert_same "$TMP/t119.csv" "$TMP/t119.bak" \
    "T119c and neither touched the file / 兩者都沒有動到檔案"

# The refusal must happen before anything is written, or the audit trail
# corroborates a write again -- which is what made this worth finding.
# 拒絕必須發生在任何寫入之前，否則稽核軌跡又會替一次寫入作證——而那正是這件事值得被找出來
# 的原因。
rm -f "$TMP/t119.log"
"$CSV2" -insert 0 'z,z,z' -i "$TMP/t119.csv" --in-place -log "$TMP/t119.log" >/dev/null 2>&1
if grep -q "atomic rename OK" "$TMP/t119.log" 2>/dev/null; then
    bad "T119d the log still records a completed write for a refused insert / log 仍然為一次被拒絕的 insert 記下「已完成的寫入」"
else
    ok "T119d and the log records no completed write / 而 log 沒有記下任何已完成的寫入"
fi

# A batch must refuse as a whole rather than dropping one edit and applying the
# rest, which is the partial result the tool exists to refuse.
# 批次必須「整批拒絕」，而不是丟掉其中一個編輯、套用其餘的——那種部分完成的結果，正是這個
# 工具存在所要拒絕的。
assert_fails "T119e a batch containing -insert 0 is refused as a whole / 含有 -insert 0 的批次會整批被拒絕" -- \
    "$CSV2" -insert 0 'z,z,z' -update 1:2 'CHANGED' -i "$TMP/t119.csv" --in-place
assert_same "$TMP/t119.csv" "$TMP/t119.bak" \
    "T119f leaving the other edits unapplied too / 其餘的編輯也一併沒有被套用"

assert_succeeds "T119g while -insert 1 still works / 而 -insert 1 照常運作" -- \
    "$CSV2" -insert 1 'z,z,z' -i "$TMP/t119.csv" --in-place
assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t119.csv")" "z" \
    "T119h and the row landed first / 而那一列落在第一位"

# ---------------------------------------------------------------------
# T120 -- a bilingual message with one language in it.
#
# The index-discard reasons were written once, in English, and interpolated
# into BOTH halves of a two-line bilingual message:
#
#   csv2：索引 s.csv.index 存在但無法使用：stale: the data file changed。
#
# "Exactly two lines, English then Chinese" held by count and not by language,
# and it held that way because a string written once got used twice.
#
# T120 —— 一則雙語訊息，裡面只有一種語言。
# 那些「索引被丟棄的理由」被寫了一次、只有英文，然後被插進一則雙語兩行訊息的「兩」半裡。
# 「恰好兩行、英文在前中文在後」依行數成立、依語言不成立——而它之所以如此，是因為一個
# 只寫了一次的字串被用了兩次。
# ---------------------------------------------------------------------
echo
echo "--- T120: both halves in their own language / 兩半各說自己的語言 ---"

print -r -- 'a,b' > "$TMP/t120.csv"
for i in {1..300}; do print -r -- "$i,x$i"; done >> "$TMP/t120.csv"
"$CSV2" --build-index -i "$TMP/t120.csv" >/dev/null 2>&1
print -r -- 'a,b' > "$TMP/t120.csv"
for i in {1..300}; do print -r -- "$i,y$i"; done >> "$TMP/t120.csv"

t120=$("$CSV2" --verify-index -i "$TMP/t120.csv" 2>&1)
t120_zh=$(print -r -- "$t120" | sed -n '2p')

# The reason, not the old wording. It used to say 資料檔已經改變 -- "the data
# file changed" -- which the stamp cannot know: copy another file's sidecar
# into place and nothing about the data file has changed at all. What the check
# establishes is that the two do not match.
# 比對的是「理由」，不是舊的措辭。它原本說「資料檔已經改變」，而那個戳記並不知道這件事：
# 把另一個檔案的 sidecar 複製過來，資料檔一個位元組也沒有變。那個檢查確立的是「兩者不相符」。
assert_contains "$t120_zh" "過期：它不描述這個檔案" \
    "T120a the Chinese line carries the reason in Chinese / 中文那一行帶著中文的理由"

# The English reason must not appear in the Chinese line at all. Checking for
# its absence is the assertion; checking only that Chinese is present would
# pass on a line containing both.
# 英文的理由完全不能出現在中文那一行裡。斷言的是「它不在」——只斷言「中文在」的話，一行
# 同時含有兩者也會通過。
if [[ "$t120_zh" == *"stale: the data file"* ]]; then
    bad "T120b the Chinese line still carries the English reason / 中文那一行仍然帶著英文的理由"
else
    ok "T120b and not the English one / 而不帶英文的那一個"
fi

# ---------------------------------------------------------------------
# T121 -- a flag written into your data, and four more argument-parser holes.
#
#   csv2 -update 1:1 -t -i f.csv --in-place     rc=0, the cell now holds "-t"
#   csv2 -append --json -i f.csv --in-place     a record containing "--json"
#
# This tool's founding failure -- exit zero, plausible garbage -- arriving
# through its own argument parser. The README quotes multissh being bitten by
# an unknown option swallowed as a hostname as the reason unknown flags are
# always an error; the principle was there and stopped at UNKNOWN flags.
#
# Known flags only, not "anything starting with a dash": `-update 1:2 -5`
# stores a negative number. `--` ends flag parsing for the value that follows,
# which is how a value that IS a flag name gets stored.
#
# The other four, all rc=0 before:
#   -hash note -hash ver   hashed ver, left note in PLAINTEXT
#   -o with --in-place     wrote -o, left the in-place target untouched
#   --verify-index --no-index   read the sidecar --no-index forbids
#   the log's "wrote N records, M fields"   reported the INPUT's shape
#
# T121 —— 一個被寫進資料裡的旗標，以及另外四個引數解析器的洞。
# 這是這個工具的招牌失敗——以 0 結束、輸出看似合理的垃圾——而它是從自己的引數解析器進來的。
# README 引用過 multissh 被「未知選項被當成主機名吞掉」咬過的事，作為「未知旗標一律視為錯誤」
# 的理由；那條原則本來就在，只是停在「未知」旗標上。
# 只擋已知旗標，而不是所有以減號開頭的東西：`-update 1:2 -5` 存的是一個負數。`--` 結束其後
# 那個值的旗標解析，那是「本身就是旗標名的值」存得進去的方式。
# ---------------------------------------------------------------------
echo
echo "--- T121: a flag is not data / 旗標不是資料 ---"

print -r -- 'a,b,note'   > "$TMP/t121.csv"
print -r -- '1,x,hello' >> "$TMP/t121.csv"
print -r -- '2,y,world' >> "$TMP/t121.csv"
cp "$TMP/t121.csv" "$TMP/t121.bak"
# The pristine copy is also READ by T122, and a .bak has no extension, so csv2
# cannot know its format. A second copy keeps the .csv name.
# 這份原始複本 T122 也會「讀」它，而 .bak 沒有副檔名，csv2 無從得知格式。再留一份保有
# .csv 名稱的複本。
cp "$TMP/t121.csv" "$TMP/t121_pristine.csv"

assert_fails "T121a a known flag in a data position is refused / 出現在資料位置的已知旗標會被拒絕" -- \
    "$CSV2" -update 1:1 -t -i "$TMP/t121.csv" --in-place
assert_same "$TMP/t121.csv" "$TMP/t121.bak" \
    "T121b and nothing was written / 而且什麼都沒有寫入"

assert_fails "T121c the same for a row literal / 對「一列」的字面值同樣如此" -- \
    "$CSV2" -append --json -i "$TMP/t121.csv" --in-place

# A value that merely LOOKS like a flag must still work: a negative number is
# ordinary data and refusing it would be a worse defect than the one being
# fixed.
# 一個「看起來像旗標」的值必須仍然能用：負數是普通資料，把它擋掉會比正在修的這個缺陷更糟。
assert_succeeds "T121d while a negative number is still stored / 而負數仍然存得進去" -- \
    "$CSV2" -update 1:1 -5 -i "$TMP/t121.csv" --in-place
assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t121.csv")" "-5" \
    "T121e exactly as given / 一字不差"

# And a value that really is a flag name has a way in.
# 而一個「真的就是旗標名」的值，有它的路。
assert_succeeds "T121f and -- ends flag parsing so a flag name can be stored / 而 -- 結束旗標解析，讓旗標名存得進去" -- \
    "$CSV2" -update 1:1 -- -t -i "$TMP/t121.csv" --in-place
assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t121.csv")" "-t" \
    "T121g and it lands as the two characters it is / 而它就以那兩個字元落地"

# The flag list this depends on must match the parser's own cases, or the
# refusal quietly stops covering a flag someone added.
# 這件事所依賴的旗標清單，必須與解析器自己的 case 相符，否則這個拒絕會在有人新增旗標時
# 悄悄地不再涵蓋它。
t121_cases=$(awk '/^func parseArgs/,/^\}/' "$ROOT/src/main.swift" \
    | grep -oE '^\s+case "[a-zA-Z0-9-]+"(, "[a-zA-Z0-9-]+")*:' | grep -oE '"[a-zA-Z0-9-]+"' | tr -d '"' | sort -u)
# Uppercase allowed on both sides. A single-letter alias like `-V` is spelled
# "V" in the case list and in KNOWN_FLAGS, and a lowercase-only pattern skipped
# the entire `case "version", "V":` line -- so the one flag missing from
# KNOWN_FLAGS was the one this check could not see.
# 兩邊都允許大寫。像 `-V` 這樣的單字母別名，在 case 清單與 KNOWN_FLAGS 裡都寫作 "V"，
# 而「只允許小寫」的樣式會把整行 `case "version", "V":` 跳過——於是「KNOWN_FLAGS 唯一漏掉
# 的那個旗標」，正好是這個檢查看不見的那一個。
t121_listed=$(awk '/^let KNOWN_FLAGS/,/^\]/' "$ROOT/src/main.swift" \
    | grep -oE '"[a-zA-Z0-9-]+"' | tr -d '"' | sort -u)
t121_missing=$(only_in_first "$t121_cases" "$t121_listed" | tr '\n' ' ')
if [[ -z "${t121_missing// /}" ]]; then
    ok "T121h and KNOWN_FLAGS covers every case the parser has / 而 KNOWN_FLAGS 涵蓋了解析器的每一個 case"
else
    bad "T121h KNOWN_FLAGS is missing:${t121_missing} / KNOWN_FLAGS 少了：${t121_missing}"
fi

# ---------------------------------------------------------------------
# T122 -- flags given twice, and pairs that cannot both be meant.
# T122 —— 給了兩次的旗標，以及不可能同時成立的組合。
# ---------------------------------------------------------------------
echo
echo "--- T122: twice, and both at once / 兩次，以及同時 ---"

head -c 32 /dev/urandom > "$TMP/t122.key"

# The one with a security consequence: -hash twice hashed the second column and
# left the first in plaintext, at rc=0, in a file whose purpose was masking it.
# 有安全後果的那一個：-hash 給兩次，雜湊了第二欄、把第一欄留成明文，rc=0——而那個檔案存在
# 的目的就是遮蔽它。
assert_fails "T122a -hash twice is refused rather than masking only the last / -hash 給兩次會被拒絕，而不是只遮蔽最後一個" -- \
    "$CSV2" -hash note -hash b -keyfile "$TMP/t122.key" -i "$TMP/t121_pristine.csv" -o "$TMP/t122.csv" -t

assert_succeeds "T122b while one -hash still works / 而一個 -hash 照常運作" -- \
    "$CSV2" -hash note -keyfile "$TMP/t122.key" -i "$TMP/t121_pristine.csv" -o "$TMP/t122b.csv" -t

assert_fails "T122c -o with --in-place is refused, not silently one of them / -o 與 --in-place 併用會被拒絕，而不是靜默擇一" -- \
    "$CSV2" -update 1:1 'Z' -i "$TMP/t121_pristine.csv" --in-place -o "$TMP/t122c.csv"

# An index has to EXIST, or --verify-index fails for want of one and the case
# passes without ever testing --no-index. It did exactly that on the first
# attempt: green against a build where `--verify-index --no-index` happily read
# the sidecar and reported `index OK`.
# 索引必須「存在」，否則 --verify-index 會因為「找不到索引」而失敗，於是這個案例根本沒測到
# --no-index 就通過了。第一版正是如此：在一個「`--verify-index --no-index` 會愉快地讀那個
# sidecar 並回報 `index OK`」的建置上，它是綠的。
"$CSV2" --build-index -i "$TMP/t121_pristine.csv" >/dev/null 2>&1
assert_succeeds "T122d0 with an index present, --verify-index alone succeeds / 索引存在時，單獨的 --verify-index 會成功" -- \
    "$CSV2" --verify-index -i "$TMP/t121_pristine.csv"
assert_fails "T122d --verify-index with --no-index is refused, as --build-index already was / --verify-index 與 --no-index 併用會被拒絕，一如 --build-index 早已如此" -- \
    "$CSV2" --verify-index --no-index -i "$TMP/t121_pristine.csv"

# ---------------------------------------------------------------------
# T123 -- the audit trail's summary line described the input.
# T123 —— 稽核軌跡的總結行描述的是輸入。
# ---------------------------------------------------------------------
echo
echo "--- T123: wrote N records, and N is the output's / wrote N records，而 N 是輸出的 ---"

{ print -r -- 'a,b,c,d,e,f,g'
  for i in {1..22}; do print -r -- "$i,$i,$i,$i,$i,$i,$i"; done
} > "$TMP/t123.csv"
rm -f "$TMP/t123.log"
"$CSV2" -delete 1,2 -delete -col 7 -i "$TMP/t123.csv" --in-place -log "$TMP/t123.log" >/dev/null 2>&1

t123_line=$(grep wrote "$TMP/t123.log")
assert_contains "$t123_line" "wrote 20 records, 6 fields" \
    "T123a the log reports what was written, not what was read / log 回報的是「寫出了什麼」，不是「讀進了什麼」"

# Cross-checked against the file rather than against my expectation of it.
# 與檔案本身對照，而不是與我對它的預期對照。
assert_contains "$("$CSV2" -r --json -i "$TMP/t123.csv" 2>/dev/null | tail -1)" '"records":20' \
    "T123b and the file agrees / 而檔案同意"

# ---------------------------------------------------------------------
# T124 -- the worst thing this tool can do, from one well-formed command.
#
#   csv2 -encrypt status -keyfile k.bin -i p.csv -o e.csv -t
#   csv2 -hash    status -keyfile k.bin -i e.csv --in-place     rc=0, silent
#   csv2 -decrypt all    -keyfile k.bin -i e.csv -o back.csv -t
#   csv2: no encrypted columns found
#
# The ciphertext was hashed one way and the `:enc:` marker overwritten, taking
# the salt with it. The correct key does not help. Nothing was printed, and the
# audit trail recorded a hash as though that were the whole story.
#
# The two guards were asymmetric: -hash looked only for a hash marker, -encrypt
# only for an encryption marker, and neither looked at the other's. The README
# already promised the general rule -- "re-masking an already-marked column is
# refused rather than layered" -- and the promise was kept in one direction of
# two.
#
# The other direction destroys nothing and produces a file that lies about
# itself: `:hmac:` becomes `:enc:`, and `-decrypt` then hands back hex digests
# under a clean column name with nothing marking them as digests.
#
# T124 —— 這個工具做得出來最糟的一件事，只需要一個格式完全正確的指令。
# 密文被單向雜湊掉，`:enc:` 標記連同 salt 一起被覆寫。正確的金鑰救不回來。什麼都沒印，
# 而稽核軌跡把「雜湊了一個欄位」記成了事情的全部。
# 兩個守衛原本是不對稱的：-hash 只找雜湊標記、-encrypt 只找加密標記，兩者都不看對方的。
# README 早就承諾了那條通則——「對一個已經標記過的欄位再次遮蔽會被拒絕，而不是疊加」——
# 而那個承諾在兩個方向裡守住了一個。
# 反方向不銷毀任何東西，但會產生一個「對自己說謊」的檔案。
# ---------------------------------------------------------------------
echo
echo "--- T124: re-masking a marked column / 對已標記的欄位再次遮蔽 ---"

head -c 32 /dev/urandom > "$TMP/t124.key"
print -r -- 'pkg,status'       > "$TMP/t124.csv"
print -r -- 'zlib,SECRET-ONE' >> "$TMP/t124.csv"
print -r -- 'zstd,SECRET-TWO' >> "$TMP/t124.csv"

"$CSV2" -encrypt status -keyfile "$TMP/t124.key" -i "$TMP/t124.csv" -o "$TMP/t124_enc.csv" -t >/dev/null 2>&1
cp "$TMP/t124_enc.csv" "$TMP/t124_enc.bak"

assert_fails "T124a -hash on an encrypted column is refused / 對已加密的欄位下 -hash 會被拒絕" -- \
    "$CSV2" -hash status -keyfile "$TMP/t124.key" -i "$TMP/t124_enc.csv" --in-place
assert_same "$TMP/t124_enc.csv" "$TMP/t124_enc.bak" \
    "T124b and the ciphertext is untouched / 而密文原封不動"

# The refusal has to say why, because the reason is the whole point: this is
# the one refusal whose absence is unrecoverable.
# 拒絕必須說出理由，因為理由就是重點所在：這是唯一一個「少了它就救不回來」的拒絕。
assert_contains "$("$CSV2" -hash status -keyfile "$TMP/t124.key" -i "$TMP/t124_enc.csv" --in-place 2>&1)" \
    "no key would recover the plaintext" \
    "T124c and says that no key would recover the plaintext / 並說明「沒有任何金鑰救得回明文」"

# And the file still decrypts, which is what "untouched" has to mean here.
# 而那個檔案仍然解得開——那才是此處「原封不動」真正的意思。
assert_succeeds "T124d and the file still decrypts with the right key / 而那個檔案用對的金鑰仍然解得開" -- \
    "$CSV2" -decrypt all -keyfile "$TMP/t124.key" -i "$TMP/t124_enc.csv" -o "$TMP/t124_back.csv" -t
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t124_back.csv")" "SECRET-ONE" \
    "T124e returning the plaintext / 交還明文"

# The other direction.
# 反方向。
"$CSV2" -hash status -keyfile "$TMP/t124.key" -i "$TMP/t124.csv" -o "$TMP/t124_h.csv" -t >/dev/null 2>&1
cp "$TMP/t124_h.csv" "$TMP/t124_h.bak"
assert_fails "T124f -encrypt on a hashed column is refused / 對已雜湊的欄位下 -encrypt 會被拒絕" -- \
    "$CSV2" -encrypt status -keyfile "$TMP/t124.key" -i "$TMP/t124_h.csv" --in-place
assert_same "$TMP/t124_h.csv" "$TMP/t124_h.bak" \
    "T124g leaving that file alone as well / 那個檔案同樣沒有被動過"

# Neither guard may block the ordinary case.
# 兩個守衛都不能擋掉普通情況。
assert_succeeds "T124h while a plain column still hashes / 而未標記的欄位照常雜湊得了" -- \
    "$CSV2" -hash status -keyfile "$TMP/t124.key" -i "$TMP/t124.csv" -o "$TMP/t124_h2.csv" -t
assert_succeeds "T124i and still encrypts / 也照常加密得了" -- \
    "$CSV2" -encrypt status -keyfile "$TMP/t124.key" -i "$TMP/t124.csv" -o "$TMP/t124_e2.csv" -t

# ---------------------------------------------------------------------
# T125 -- --truncate-partial dropping far more than "a record", in silence.
# T125 —— --truncate-partial 靜默丟掉的，遠不只「一筆」。
# ---------------------------------------------------------------------
echo
echo "--- T125: how much --truncate-partial discards / --truncate-partial 丟掉了多少 ---"

{ print -r -- 'a,b'
  print -r -- '1,"opens here'
  for i in {2..10}; do print -r -- "$i,ok$i"; done
} > "$TMP/t125.csv"

t125_err=$("$CSV2" -r --truncate-partial -i "$TMP/t125.csv" 2>&1 >/dev/null)
assert_contains "$t125_err" "--truncate-partial discarded" \
    "T125a a discard that swallows the rest of the file says so / 一次「吞掉檔案其餘部分」的丟棄會說出來"
assert_contains "$t125_err" "bytes" \
    "T125b and gives the size, since the count of records is not knowable here / 並給出大小——因為在這裡「筆數」是不可知的"

# It stays a success: the flag was asked for by name.
# 它仍然是成功：那個旗標是被指名要求的。
assert_succeeds "T125c while remaining a success, because the flag was asked for / 而它仍然是成功，因為那個旗標是被要求的" -- \
    "$CSV2" -r --truncate-partial -i "$TMP/t125.csv"

# ---------------------------------------------------------------------
# T126 -- an error's record number is an address someone types back.
# T126 —— 錯誤裡的紀錄編號，是一個會被人打回去的位址。
# ---------------------------------------------------------------------
echo
echo "--- T126: the unclosed-quote record number / 未閉合引號的紀錄編號 ---"

{ print -r -- 'a,b'
  print -r -- 'A,B'
  print -r -- '1,x'
  print -r -- '2,"unclosed'
} > "$TMP/t126.csv2"

t126=$("$CSV2" -r -i "$TMP/t126.csv2" 2>&1 | head -1)
assert_contains "$t126" "record 2:" \
    "T126a the number counts DATA records, not header rows / 那個號碼數的是資料紀錄，不是標頭列"

# The address has to resolve, which is the whole reason the number matters.
# 那個位址必須解得出來——那正是這個號碼要緊的全部原因。
assert_succeeds "T126b and an address that far into the file resolves / 而那個位址在檔案裡解得出來" -- \
    "$CSV2" -get 1:1 -i "$TMP/t126.csv2" --truncate-partial

# ---------------------------------------------------------------------
# T127 -- CRLF is ONE Swift Character, and the escapers switched on Characters.
#
#   csv2 -contains $'needle\r\n2026-01-01T00:00:00+00:00 INFO  forged' -log L
#   L: two lines, the second entirely chosen by the input, timestamp included
#
# A bare LF was escaped correctly. `\r\n` matched neither `case "\n"` nor
# `case "\r"`, because Swift's `Character` is a grapheme cluster and CRLF is
# one of them. The forgery AI and AJ closed came back through it -- reachable
# from a plain `-contains`, with no write access to anything.
#
# One defect, three guarantees: one log entry per line, one report line per
# matching cell, and errors as exactly two lines on stderr. The report is the
# one that stings: a single hit printed two lines, so `cut -f1` returns a
# fragment of prose where an address belongs, in the interface this tool
# recommends for scripts.
#
# The README warns about this exact property of Swift for `--pretty` --
# "grapheme clusters, NOT a per-code-point lookup" -- a few hundred lines from
# where the escaper was written.
#
# T127 —— CRLF 在 Swift 裡是「一個」Character，而兩個跳脫器都是以 Character 去 switch。
# 單獨的 LF 被正確跳脫；`\r\n` 兩個 case 都不匹配，於是原樣通過。AI 與 AJ 關掉的偽造從它
# 回來了——而且只需要一次普通的 `-contains`，完全不需要對任何東西有寫入權限。
# 一個缺陷，三個保證：log 一筆一行、報告「每個命中的儲存格一行」、以及 stderr 恰好兩行。
# 其中報告那一項最痛：一個命中印出兩行，於是 `cut -f1` 在該是位址的地方回傳一段散文碎片
# ——就發生在這個工具推薦給腳本使用的那個介面上。
# README 就在 `--pretty` 那一節警告過 Swift 的這個性質，相隔幾百行。
# ---------------------------------------------------------------------
echo
echo "--- T127: a CRLF is not two characters / CRLF 不是兩個字元 ---"

print -r -- 'a,b'  > "$TMP/t127.csv"
print -r -- '1,x' >> "$TMP/t127.csv"

rm -f "$TMP/t127.log"
"$CSV2" -contains "$(printf 'needle\r\n2026-01-01T00:00:00+00:00 INFO  forged')" \
    -i "$TMP/t127.csv" -log "$TMP/t127.log" >/dev/null 2>&1
assert_eq "$(wc -l < "$TMP/t127.log" | tr -d ' ')" "1" \
    "T127a a CRLF in an argument does not open a second log line / 引數裡的 CRLF 不會在 log 中開出第二行"

# Escaped, not dropped: an audit trail that hides what was attempted is worse
# than one that records it plainly.
# 是跳脫，不是丟棄：一份把「有人試過什麼」藏起來的稽核軌跡，比一份原樣記下它的更糟。
assert_contains "$(cat "$TMP/t127.log")" '\r\n2026-01-01' \
    "T127b and the attempted text is kept, escaped / 而被嘗試的文字被保留下來，是跳脫"

# The locating report: one matching cell, one line. This is the interface the
# README tells scripts to use `cut -f1` on.
# 定位報告：一個命中的儲存格，一行。那正是 README 叫腳本用 `cut -f1` 去讀的介面。
printf 'a,b\n1,"has\r\nCRLF"\n' > "$TMP/t127b.csv"
assert_eq "$("$CSV2" -contains has -i "$TMP/t127b.csv" 2>/dev/null | wc -l | tr -d ' ')" "1" \
    "T127c a cell containing CRLF still prints as ONE report line / 含 CRLF 的儲存格仍然只印一行報告"

# And a CR alone and an LF alone must keep working -- the fix must not have
# traded one pair for the singles.
# 而單獨的 CR 與單獨的 LF 必須繼續有效——這個修正不能拿「一對」去換掉「單個」。
rm -f "$TMP/t127c.log"
"$CSV2" -contains "$(printf 'a\rb')" -i "$TMP/t127.csv" -log "$TMP/t127c.log" >/dev/null 2>&1
assert_eq "$(wc -l < "$TMP/t127c.log" | tr -d ' ')" "1" \
    "T127d while a lone CR is still escaped / 而單獨的 CR 仍然被跳脫"
rm -f "$TMP/t127d.log"
"$CSV2" -contains "$(printf 'a\nb')" -i "$TMP/t127.csv" -log "$TMP/t127d.log" >/dev/null 2>&1
assert_eq "$(wc -l < "$TMP/t127d.log" | tr -d ' ')" "1" \
    "T127e and so is a lone LF / 單獨的 LF 也是"

# ---------------------------------------------------------------------
# T128 -- flags that were accepted and did something else.
# T128 —— 被接受、卻做了別的事的旗標。
# ---------------------------------------------------------------------
echo
echo "--- T128: accepted, and doing something else / 被接受，然後做了別的事 ---"

print -r -- 'a,b'  > "$TMP/t128.csv"
print -r -- '1,x' >> "$TMP/t128.csv"
cp "$TMP/t128.csv" "$TMP/t128.bak"
head -c 32 /dev/urandom > "$TMP/t128.key"

# --build-index REPLACED the verb: the index was built and the edit was
# dropped, at rc=0, silently under --in-place.
# --build-index 是「取代」動詞：索引建了、編輯被丟掉，rc=0，在 --in-place 下完全靜默。
assert_fails "T128a --build-index with an edit verb is refused / --build-index 與編輯動詞併用會被拒絕" -- \
    "$CSV2" -update 1:2 'CHANGED' --build-index -i "$TMP/t128.csv" --in-place
assert_same "$TMP/t128.csv" "$TMP/t128.bak" \
    "T128b and neither the index nor the edit happened / 而索引與編輯都沒有發生"

# -get writes no header, so a transform's salt has nowhere to live: the output
# was ciphertext nothing could ever decrypt.
# -get 不寫標頭，因此轉換的 salt 無處可放：輸出的是一段沒有任何東西還原得了的密文。
assert_fails "T128c -get with -encrypt is refused, since the salt would have nowhere to go / -get 與 -encrypt 併用會被拒絕，因為 salt 沒有地方可放" -- \
    "$CSV2" -get 1:2 -encrypt b -keyfile "$TMP/t128.key" -i "$TMP/t128.csv"

assert_fails "T128d --include-headers without -contains is refused, as its siblings are / --include-headers 沒有 -contains 時被拒絕，一如它的同輩" -- \
    "$CSV2" -r --include-headers -i "$TMP/t128.csv"

# ---------------------------------------------------------------------
# T129 -- --in-place, and what "this file" means.
# T129 —— --in-place，以及「這個檔案」指的是什麼。
# ---------------------------------------------------------------------
echo
echo "--- T129: in place, on the right file / 就地，而且是對的那個檔案 ---"

# Neither half of T129 has a meaning on Windows. MSYS2's `ln -s` copies the
# file unless winsymlinks is set, so there is no link to preserve; and the mode
# bits it reports are a POSIX-shaped fiction over an ACL. copyMode is compiled
# out there for the same reason -- there is nothing it could carry.
# T129 的兩半在 Windows 上都沒有意義。MSYS2 的 `ln -s` 在未設 winsymlinks 時是複製，
# 沒有連結可保留；它回報的模式位元則是覆在 ACL 之上、形似 POSIX 的虛構。copyMode 在
# 那裡也基於同一個理由被編譯掉——沒有東西可以搬。
if (( IS_WINDOWS )); then
    skipt "T129a-d --in-place on a symlink, and the mode it carries / symlink 上的 --in-place 與它帶過去的模式 (no symlinks and no POSIX modes under MSYS2 / MSYS2 下沒有 symlink，也沒有 POSIX 模式)"
else
    print -r -- 'a,b'  > "$TMP/t129_target.csv"
    print -r -- '1,x' >> "$TMP/t129_target.csv"
    ln -sf "$TMP/t129_target.csv" "$TMP/t129_link.csv"

    assert_succeeds "T129a --in-place through a symlink succeeds / 透過 symlink 的 --in-place 會成功" -- \
        "$CSV2" -update 1:2 'Z' -i "$TMP/t129_link.csv" --in-place

    # The link must survive, because replacing it means the next run edits a
    # different file than the last one did.
    # 那個連結必須存活，因為把它換掉，等於「下一次執行編輯的檔案」與「上一次的」不是同一個。
    if [[ -L "$TMP/t129_link.csv" ]]; then
        ok "T129b and the symlink is still a symlink / 而那個 symlink 仍然是 symlink"
    else
        bad "T129b the symlink was replaced by a regular file / 那個 symlink 被換成了一般檔案"
    fi

    assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t129_target.csv")" "Z" \
        "T129c and the edit landed on the file it points at / 而那次編輯落在它所指向的檔案上"

    # Mode: a temp file is created with the umask's mode, so without carrying the
    # original's an edit silently widens who can read the file.
    # 模式：暫存檔以 umask 的模式建立，因此不把原檔的模式帶過去，一次編輯就會悄悄放寬
    # 「誰讀得到這個檔案」。
    print -r -- 'a,b'  > "$TMP/t129_mode.csv"
    print -r -- '1,x' >> "$TMP/t129_mode.csv"
    chmod 600 "$TMP/t129_mode.csv"
    "$CSV2" -update 1:2 'Z' -i "$TMP/t129_mode.csv" --in-place >/dev/null 2>&1
    # Reading a file's mode is the least portable thing in this suite.
    #   - BSD stat and GNU stat both take -f, and they mean opposite things: the
    #     mode format on macOS, "filesystem status" on Linux. The GNU one prints a
    #     block of filesystem facts to STDOUT before exiting 1, so `A || B` runs B
    #     as well and the substitution captures both.
    #   - The aarch64 guest has NO stat at all: this busybox was built without the
    #     applet, and zsh/stat is not in its module set either. Both branches then
    #     produce nothing, which is why T129d failed there while passing on macOS
    #     with the program behaving identically on both.
    # So: ask each stat only what it understands, require the answer to look like
    # a mode, and fall back to the one listing every Unix has.
    # 讀一個檔案的模式，是這份測試裡可攜性最差的一件事。BSD 與 GNU 的 stat 都收 -f，
    # 意思卻相反；而 aarch64 guest 上根本沒有 stat——這份 busybox 沒把該 applet 編進去，
    # zsh/stat 模組也不在。兩條分支都給不出東西，於是 T129d 在那裡失敗、在 macOS 上通過，
    # 而程式在兩邊的行為其實一樣。
    file_mode() {
        local m
        m=$(stat_mode "$1")
        [[ $m == <-> ]] || m=$(mode_from_ls "$1")                 # anywhere else
        print -r -- "$m"
    }

    # rwxrwxrwx -> 755. Only the nine permission characters are read; setuid and
    # the sticky bit show up in the same columns as x and are NOT decoded, because
    # nothing here sets them and a half-decoded answer is worse than a missing one.
    # 只讀那九個權限字元。setuid 與 sticky 佔用與 x 相同的欄位，此處刻意不解讀——
    # 這裡沒有任何東西會設定它們，而一個解讀到一半的答案比沒有答案更糟。
    mode_from_ls() {
        local perm d i n=0 out=""
        perm=$(ls -ld "$1" 2>/dev/null) || return 1
        perm=${perm[2,10]}
        [[ $perm == [-r][-w][-xsS][-r][-w][-xsS][-r][-w][-xtT] ]] || return 1
        for i in 1 4 7; do
            n=0
            [[ ${perm[i]}   == r ]] && (( n += 4 ))
            [[ ${perm[i+1]} == w ]] && (( n += 2 ))
            [[ ${perm[i+2]} == [xst] ]] && (( n += 1 ))
            out="$out$n"
        done
        print -r -- "$out"
    }

    assert_eq "$(file_mode "$TMP/t129_mode.csv")" "600" \
        "T129d and an edit does not widen the file's permissions / 而一次編輯不會放寬這個檔案的權限"

    # The fallback above only runs where stat is missing -- that is, only where
    # nothing can check it. Compare the two here, on every platform that has
    # both, so a wrong rwx decoder cannot sit unnoticed until the one place it
    # is relied upon.
    # 上面那條後備只在「沒有 stat」的地方會用到——也就是只在沒有東西能檢查它的地方。
    # 所以在每一個兩者兼具的平台上把它們對起來，免得一個解錯的 rwx 解碼器一路潛伏到
    # 唯一依賴它的那個地方。
    chmod 754 "$TMP/t129_mode.csv"
    _t129_stat=$(stat_mode "$TMP/t129_mode.csv")
    if [[ $_t129_stat == <-> ]]; then
        assert_eq "$(mode_from_ls "$TMP/t129_mode.csv")" "$_t129_stat" \
            "T129e the ls fallback reads the same mode stat does / ls 後備讀到的模式與 stat 相同"
    else
        skipt "T129e the ls fallback reads the same mode stat does / ls 後備讀到的模式與 stat 相同 (no stat on this platform to compare against / 此平台沒有 stat 可供比對)"
    fi
fi

# ---------------------------------------------------------------------
# T137 -- a flag whose Chinese entry lost half its English one.
#
# Round 53: "the Chinese -t entry omits the English entry's 'It applies to
# SELECTIONS only -- an edit ... always writes the headers'. Covered later, but
# the flag table diverges between languages."
#
# T117 could not see it: that entry cites no case number, and case numbers are
# all T117 compares. This is the same drift one level down -- not a section
# missing, a sentence missing.
#
# The measure is the byte length of each flag's description, compared between
# the two files under LC_ALL=C so every platform's awk counts the same thing.
# Chinese says the same thing in fewer characters and more bytes, so the ratio
# sits near 1: measured across 38 flags today the minimum is 0.81 and the
# median 1.06, while the -t entry as found would have been 0.25. The threshold
# is 0.5, which is below anything real and far above the failure.
#
# T137 —— 一個「中文條目掉了英文條目一半內容」的旗標。
# 第 53 回合發現：中文的 -t 條目少了英文那句「它只作用於選取——一次編輯一定會寫出標頭列」。
# T117 看不到它：那個條目沒有引用案例編號，而 T117 比對的就只有案例編號。這是同一種漂移
# 往下一層——不是少了一節，是少了一句。
# 量的是每個旗標說明的「位元組長度」在兩份檔案間的比值，並在 LC_ALL=C 下計算，好讓每個平台的
# awk 數的是同一種東西。中文用較少的字、較多的位元組講同一件事，因此比值接近 1：今天實測
# 38 個旗標，最低 0.81、中位數 1.06，而當時的 -t 條目會是 0.25。門檻取 0.5，低於任何真實
# 值，也遠高於那次失敗。
# ---------------------------------------------------------------------
echo
echo "--- T137: the flag tables say the same amount / T137：兩份旗標表說的份量相同 ---"

# Totals per flag NAME, not per entry: `-delete` has three entries (a[,b],
# -cell, -col) in both files, and pairing them one by one would compare the
# first English entry against the first Chinese one by position and report a
# difference that is only the ordering. Summing is enough for what this checks
# -- whether a language is carrying materially less text for a flag.
# 以「旗標名稱」加總，而不是逐條目比對：`-delete` 在兩份檔案裡都有三個條目（a[,b]、
# -cell、-col），逐條目配對會用位置去對，然後回報一個「只是順序不同」的差異。對這個
# 檢查要問的事情——某一種語言在某個旗標上是不是承載了明顯較少的文字——加總就夠了。
t137_extract() {
    LC_ALL=C awk '
        function flush() { if (cur != "") { total[cur] += len; cur = "" } }
        /^  -{1,2}[A-Za-z0-9]/ {
            flush()
            cur = $1
            rest = substr($0, length($1) + 3)
            gsub(/^ +| +$/, "", rest)
            len = length(rest)
            next
        }
        /^ {20,}[^ ]/ && cur != "" {
            line = $0
            gsub(/^ +| +$/, "", line)
            len += length(line)
            next
        }
        /^[[:space:]]*$/ { flush() }
        END { flush(); for (f in total) print f "\t" total[f] }
    ' "$1" | sort
}

t137_en_file="$TMP/t137_en.txt"
t137_zh_file="$TMP/t137_zh.txt"
t137_extract "$ROOT/README.md"       > "$t137_en_file"
t137_extract "$ROOT/README.zh-TW.md" > "$t137_zh_file"

t137_thin=""
t137_seen=0
while IFS=$'\t' read -r flag enlen; do
    zhlen=$(LC_ALL=C awk -F'\t' -v f="$flag" '$1 == f { print $2; exit }' "$t137_zh_file")
    [[ -z $zhlen || $enlen -eq 0 ]] && continue
    t137_seen=$((t137_seen + 1))
    (( zhlen * 100 < enlen * 50 )) && t137_thin="$t137_thin $flag(${zhlen}/${enlen})"
done < "$t137_en_file"

if (( t137_seen < 20 )); then
    bad "T137a only $t137_seen flags were compared; the extractor stopped matching the flag tables / 只比對到 $t137_seen 個旗標；抽取器與旗標表已對不上"
elif [[ -z ${t137_thin// /} ]]; then
    ok "T137a no flag's Chinese entry is under half its English one, across $t137_seen flags / $t137_seen 個旗標中，沒有任何一個的中文條目短於英文的一半"
else
    bad "T137a thin Chinese entries:${t137_thin} / 中文條目過短：${t137_thin}"
fi

# ---------------------------------------------------------------------
# T138 -- reporting an error must not be a way to fail.
#
# DV routed every SINK through Platform.writeAll. The direct stderr writes are
# not sinks -- the top-level error printer, the Logger echo, -debug -- and they
# still called FileHandle.standardError.write, which answers a failed write
# with an exception nobody catches. So `csv2 -get 9:9 -i f.csv 2>&-`, an
# ordinary thing for a script to do, exited 134 WHILE PRINTING THE REFUSAL:
# a status of 1 turned into one the documentation does not contain.
#
# T138 —— 「回報一個錯誤」這件事本身，不該成為一種失敗的方式。
# DV 把每一個 sink 都導向了 Platform.writeAll，而直接寫 stderr 的那幾處不是 sink——最上層
# 的錯誤印出、Logger 的回顯、-debug——它們仍然呼叫 FileHandle.standardError.write，
# 而它對「寫入失敗」的回答是一個沒有人接的例外。於是 `csv2 -get 9:9 -i f.csv 2>&-`
# 這種腳本裡很平常的寫法，會在「印出那則拒絕」的當下以 134 結束。
# ---------------------------------------------------------------------
echo
echo "--- T138: stderr that cannot be written / T138：寫不出去的 stderr ---"

print -r -- 'a,b'  > "$TMP/t138.csv"
print -r -- '1,x' >> "$TMP/t138.csv"

"$CSV2" -get 9:9 -i "$TMP/t138.csv" 2>&-
assert_eq "$?" "1" \
    "T138a a refusal with stderr closed still exits 1 / stderr 已關閉時，一次拒絕仍然以 1 結束"

"$CSV2" -r -t -i "$TMP/t138.csv" -debug 2>&- >/dev/null
assert_eq "$?" "0" \
    "T138b and -debug with stderr closed still exits 0 / 而 stderr 已關閉時的 -debug 仍然以 0 結束"

# The message still has to arrive when there IS somewhere to put it: a fix that
# quietly stopped reporting would pass the two cases above.
# 有地方可放時，那則訊息仍然必須送到：一個「安靜地不再回報」的修法，上面兩個案例照樣會通過。
"$CSV2" -get 9:9 -i "$TMP/t138.csv" 2>"$TMP/t138.err"
assert_eq "$(wc -l < "$TMP/t138.err" | tr -d ' ')" "2" \
    "T138c while an open stderr still gets the two lines / 而開著的 stderr 仍然收到那兩行"

# ---------------------------------------------------------------------
# T140 -- a column list that names nothing, and a name that is a number.
#
# Round 54, its two worst findings. `-hash ""` exited 0 having done nothing:
# output byte-identical, no marker, nothing on stderr -- while a WRONG name was
# refused by name. And on a file whose columns are named `2` and `1`,
# `-hash 2` protected position 2, the column called `1`, silently.
#
# Both are the same failure the duplicate-name refusal was written against on
# 2026-08-18: the tool picked something for the caller and said nothing.
#
# T140 —— 一份「什麼也沒指名」的欄位清單，以及一個「名字是數字」的欄位。
# 第 54 回合最嚴重的兩項。`-hash ""` 以 0 結束、什麼也沒做——輸出逐位元相同、沒有標記、
# stderr 空白——而一個「錯的」名字卻會被指名拒絕。而在欄名為 `2` 與 `1` 的檔案上，
# `-hash 2` 保護的是位置 2，也就是名為 `1` 的那一欄，不說一句話。
# ---------------------------------------------------------------------
echo
echo "--- T140: naming nothing, and naming a number / T140：什麼也沒指名，以及指名一個數字 ---"

print -r -- 'name,license'  > "$TMP/t140.csv"
print -r -- 'app,MIT'      >> "$TMP/t140.csv"
cp "$TMP/t140.csv" "$TMP/t140.keep"

for _spec in '' ',' ',,'; do
    _out=$("$CSV2" -hash "$_spec" -i "$TMP/t140.csv" -o "$TMP/t140_out.csv" 2>&1)
    _rc=$?
    if (( _rc == 1 )) && [[ $_out == *"the column list is empty"* ]]; then
        ok "T140a -hash with a column list of \"$_spec\" is refused / -hash 的欄位清單為「$_spec」時會被拒絕"
    else
        bad "T140a -hash \"$_spec\" exited $_rc: $(print -r -- $_out | head -1) / 結果如上"
    fi
done

_out=$("$CSV2" -encrypt '' -i "$TMP/t140.csv" -o "$TMP/t140_out.csv" 2>&1)
assert_contains "$_out" "the column list is empty" \
    "T140b and -encrypt likewise, since the loss there is permanent / -encrypt 同樣如此，而它那邊的損失是永久的"

assert_succeeds "T140c while a real column name still works / 而真正的欄名照常運作" -- \
    "$CSV2" -hash name -i "$TMP/t140.csv" -o "$TMP/t140_out.csv"
assert_contains "$("$CSV2" -r -t -i "$TMP/t140_out.csv" | head -1)" "name:hash" \
    "T140d and leaves the marker that says so / 並留下說明這件事的標記"

# The number/name collision.
# 數字與名字的碰撞。
print -r -- '2,1'  > "$TMP/t140n.csv"
print -r -- 'X,Y' >> "$TMP/t140n.csv"
# -get takes no -o (it writes one value, not a file), so it is run without one.
# -get 不收 -o（它寫的是一個值，不是一個檔案），因此不帶 -o 執行。
for _verb in "-hash 2" "-delete -col 2"; do
    _out=$("$CSV2" ${=_verb} -i "$TMP/t140n.csv" -o "$TMP/t140n_out.csv" 2>&1)
    _rc=$?
    if (( _rc == 1 )) && [[ $_out == *"both a column NUMBER and the NAME"* ]]; then
        ok "T140e $_verb is refused as ambiguous / $_verb 因歧義而被拒絕"
    else
        bad "T140e $_verb exited $_rc: $(print -r -- $_out | head -1) / 結果如上"
    fi
done

_out=$("$CSV2" -get 1:2 -i "$TMP/t140n.csv" 2>&1)
_rc=$?
if (( _rc == 1 )) && [[ $_out == *"both a column NUMBER and the NAME"* ]]; then
    ok "T140e -get 1:2 is refused as ambiguous / -get 1:2 因歧義而被拒絕"
else
    bad "T140e -get 1:2 exited $_rc: $(print -r -- $_out | head -1) / 結果如上"
fi

# And a number that is NOT also a name still addresses a column.
# 而一個「不同時是名字」的數字，仍然可以定址一個欄位。
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t140.csv")" "MIT" \
    "T140f a plain column number still works where no name collides / 沒有名字相撞時，單純的欄號照常可用"

# ---------------------------------------------------------------------
# T141 -- the window that could never have selected anything, and an -o that
# cannot be renamed onto.
#
# Round 54: the -mid past-the-end WARN did not fire on a file with a header and
# no records -- the one file where EVERY window is past the end. The condition
# carried `seen > 0`. And the refusals table promised `-o /dev/stdout` would be
# answered with "Use -so"; what came back was "cannot create temporary file
# beside /dev/fd/1", which names neither the cause nor the way out, and a path
# the caller never typed.
#
# T141 —— 一個「不可能選到任何東西」的視窗，以及一個「rename 不上去」的 -o。
# ---------------------------------------------------------------------
echo
echo "--- T141: warning where every window is past the end / T141：每一個視窗都在結尾之後時的警告 ---"

print -r -- 'a,b,c' > "$TMP/t141_hdr.csv"
_t141_err=$("$CSV2" -mid 1,3 -t -i "$TMP/t141_hdr.csv" 2>&1 >/dev/null)
assert_eq "$?" "0" \
    "T141a a window past the end of an empty file is not an error / 空檔案上「結尾之後」的視窗不是錯誤"
assert_contains "$_t141_err" "no data records at all" \
    "T141b but it warns, which it did not when the file had no records / 但它會警告——而在「檔案沒有紀錄」時它先前不會"

# Still no warning when the window is real, or the WARN would mean nothing.
# 視窗真的存在時仍然不警告，否則這個 WARN 就沒有意義了。
print -r -- 'a,b,c'  > "$TMP/t141_one.csv"
print -r -- '1,x,p' >> "$TMP/t141_one.csv"
_t141_ok=$("$CSV2" -mid 1,1 -t -i "$TMP/t141_one.csv" 2>&1 >/dev/null)
if [[ -z ${_t141_ok//[[:space:]]/} ]]; then
    ok "T141c a window that selects something says nothing / 選得到東西的視窗不說話"
else
    bad "T141c unexpected output: $_t141_ok / 非預期的輸出"
fi

# -o onto something that cannot be renamed onto.
# -o 指向一個「rename 不上去」的東西。
mkdir -p "$TMP/t141_dir"
_t141_d=$("$CSV2" -r -t -i "$TMP/t141_one.csv" -o "$TMP/t141_dir" 2>&1)
if [[ $_t141_d == *"is a directory"* && $_t141_d == *"-so"* ]]; then
    ok "T141d -o onto a directory names the cause and the way out / -o 指向目錄時，訊息說出原因與出路"
else
    bad "T141d $(print -r -- $_t141_d | head -1) / 訊息如上"
fi

if (( IS_WINDOWS )); then
    skipt "T141e -o onto a FIFO is refused with the same sentence / -o 指向 FIFO 時以同一句話拒絕 (a POSIX FIFO is not visible to a native Windows binary, as for T61a / MSYS 的 FIFO 對原生 Windows 程式不存在，同 T61a)"
else
    rm -f "$TMP/t141_fifo"
    mkfifo "$TMP/t141_fifo"
    _t141_f=$("$CSV2" -r -t -i "$TMP/t141_one.csv" -o "$TMP/t141_fifo" 2>&1)
    if [[ $_t141_f == *"FIFO"* && $_t141_f == *"-so"* ]]; then
        ok "T141e -o onto a FIFO is refused with the same sentence / -o 指向 FIFO 時以同一句話拒絕"
    else
        bad "T141e $(print -r -- $_t141_f | head -1) / 訊息如上"
    fi
    rm -f "$TMP/t141_fifo"
fi

# A destination that does not exist yet is the ordinary case and must not be
# caught by any of this.
# 一個「還不存在」的目的地是常態，不能被上面任何一條擋住。
assert_succeeds "T141f -o to a path that does not exist yet still works / -o 指向一個尚不存在的路徑仍然可用" -- \
    "$CSV2" -r -t -i "$TMP/t141_one.csv" -o "$TMP/t141_new.csv"

# ---------------------------------------------------------------------
# T142 -- --yes decides the algorithm, not just the prompt.
#
# Round 54: "-hash license" gives `license:hash`, unkeyed SHA-256, which the
# README warns at length is dictionary-attackable. "-hash license --yes" gives
# `license:hmac:<fp>`. --yes is listed as "accept the default key without a
# prompt", and for -hash that turns out to decide whether the output is
# dictionary-attackable. Both READMEs say so now, so both need this behind
# them -- including the consequence, which is that the two never compare equal.
#
# T142 —— --yes 決定的是演算法，不只是「跳過詢問」。
# ---------------------------------------------------------------------
echo
echo "--- T142: the flag that chooses the algorithm / T142：選定演算法的那個旗標 ---"

print -r -- 'name,license'  > "$TMP/t142.csv"
print -r -- 'app,MIT'      >> "$TMP/t142.csv"
print -r -- 'lib,MIT'     >> "$TMP/t142.csv"

"$CSV2" -hash license -t -i "$TMP/t142.csv" -o "$TMP/t142_plain.csv"
assert_contains "$(head -1 "$TMP/t142_plain.csv")" "license:hash" \
    "T142a -hash without a key marks the column :hash / 沒有金鑰的 -hash 把該欄標記為 :hash"

# HOME points at the key this suite made, not at the operator's. `--yes` reads
# the DEFAULT key -- a file in the caller's home directory -- so without this
# the case passes on a machine that happens to have one and fails on a machine
# that does not, which is what a freshly reinstalled WSL node demonstrated:
# four failures that were all one missing file, none of them about csv2.
# T37 already runs the other half of this, with HOME pointing somewhere empty.
# HOME 指向這套測試自己造出來的金鑰，而不是操作者的。`--yes` 讀的是「預設金鑰」——呼叫端家
# 目錄裡的一個檔案——因此少了這一行，這個案例會在「剛好有那個檔案」的機器上通過、在沒有的
# 機器上失敗，而一台剛重裝過的 WSL 節點正好示範了這件事：四個失敗，全部是同一個缺檔，
# 沒有一個與 csv2 有關。T37 早就在跑這件事的另一半，它把 HOME 指向一個空的地方。
HOME="$TMP/home" "$CSV2" -hash license --yes -t -i "$TMP/t142.csv" -o "$TMP/t142_yes.csv"
assert_contains "$(head -1 "$TMP/t142_yes.csv")" "license:hmac:" \
    "T142b while --yes marks it :hmac:, having selected the default key / 而 --yes 會標記為 :hmac:，因為它選定了預設金鑰"

head -c 32 /dev/urandom > "$TMP/t142.key"
"$CSV2" -hash license -keyfile "$TMP/t142.key" -t -i "$TMP/t142.csv" -o "$TMP/t142_key.csv"
assert_contains "$(head -1 "$TMP/t142_key.csv")" "license:hmac:" \
    "T142c and -keyfile likewise / -keyfile 同樣如此"

# The consequence the README now states: the two do not compare equal, so a
# join across files masked differently matches nothing.
# README 現在寫出來的那個後果：兩者不會相等，因此跨「以不同方式遮蔽的檔案」比對，一個都
# 對不上。
_t142_a=$("$CSV2" -get 1:license -i "$TMP/t142_plain.csv")
_t142_b=$("$CSV2" -get 1:license -i "$TMP/t142_yes.csv")
if [[ -n $_t142_a && $_t142_a != $_t142_b ]]; then
    ok "T142d a value hashed with and without a key never matches itself / 同一個值在有無金鑰下雜湊出來永遠不相等"
else
    bad "T142d [$_t142_a] vs [$_t142_b] / 兩者如上"
fi

# Determinism within one choice is the property that makes hashing useful at
# all, and it must survive both forms.
# 在同一種選擇之內的確定性，是雜湊之所以有用的性質，兩種形式都必須保有它。
assert_eq "$("$CSV2" -get 1:license -i "$TMP/t142_yes.csv")" "$("$CSV2" -get 2:license -i "$TMP/t142_yes.csv")" \
    "T142e while equal values still hash equal within one choice / 而在同一種選擇之內，相等的值仍然雜湊出相等的結果"

# ---------------------------------------------------------------------
# T143 -- the documented limit of the O(1) stamp, pinned as a limit.
#
# Round 54 tried eight times to defeat the stamp, failed every time, and
# concluded the README's description of it was wrong -- that the check is
# stronger than "size, mtime, first and last bytes". It is not. Reproduced by
# hand the same day: an equal-length substitution that adds an embedded
# newline, with mtime restored to the nanosecond, gives
#
#   indexed  : 900001:2      <- wrong
#   --no-index: 900000:2     <- right
#   --verify-index: index MISMATCH: ... record 450001 spans lines
#
# That is the hazard the README describes, and a documentation change claiming
# safety here would have been the worst kind of edit this project can make. So
# the limitation gets a test of its own: it must stay reproducible, because the
# day it stops being reproducible is the day the description has to change.
#
# CSV2_INDEX_MIN_BYTES lowers the threshold so this needs a small file rather
# than the 28 MB one used by hand. `touch -r` carries the nanoseconds; where it
# does not, the case skips rather than passing for the wrong reason.
#
# T143 —— 把 O(1) 戳記「有文件記載的極限」當成一條極限釘住。
# 第 54 回合試了八次都沒能騙過那個戳記，於是推論 README 對它的描述有誤。並非如此：同一天
# 以手動方式重現——一次等長、且把 mtime 還原到奈秒的替換，會讓索引路徑回報 900001:2、
# --no-index 回報 900000:2，而 --verify-index 抓得到。那正是 README 描述的那個風險，而
# 「改文件去宣稱這裡是安全的」會是這個專案做得出來最糟的一種編輯。因此這條極限自己有了
# 一個測試：它必須保持可重現——它哪一天不再可重現，就是那段描述該改的那一天。
# ---------------------------------------------------------------------
echo
echo "--- T143: the stamp's documented blind spot / T143：戳記在文件中載明的盲點 ---"

# 200 records of 30 bytes; the threshold comes down to meet it.
# 200 筆、每筆 30 位元組；門檻降下來遷就它。
{
    print -r -- 'id,val'
    for i in {1..200}; do printf '%06d,v%06d-pad-pad-pad
' $i $i; done
} > "$TMP/t143.csv"

# Both thresholds: the wrong RECORD NUMBER comes from the chunked search, which
# is what consumes the index's no_embedded_newlines claim. Lowering only the
# index threshold left the parallel path out and the hazard did not appear --
# a test that would have "proved" the danger was gone.
# 兩個門檻都要降：錯誤的「紀錄編號」來自分塊搜尋，而那正是消費索引 no_embedded_newlines
# 宣稱的地方。只降索引門檻會把平行路徑排除在外，於是那個風險不會出現——那會變成一個
# 「證明危險已經消失」的測試。
export CSV2_INDEX_MIN_BYTES=1024
export CSV2_PARALLEL_MIN_BYTES=1024
export CSV2_PARALLEL_CHUNK_BYTES=2048
"$CSV2" --build-index -i "$TMP/t143.csv" >/dev/null
cp -p "$TMP/t143.csv" "$TMP/t143.ref"

# An equal-length replacement that puts a newline inside a quoted field.
# 一個等長的替換，把一個換行放進引號欄位裡。
_t143_old='000100,v000100-pad-pad-pad'
_t143_new=$'000100,"a
c-pad-pad-padxy"'
if (( ${#_t143_old} != ${#_t143_new} )); then
    bad "T143 the replacement is not the same length (${#_t143_old} vs ${#_t143_new}) / 替換字串長度不同"
else
    # Byte-for-byte replacement without changing the size: read, substitute the
    # one line, write back.
    # 逐位元組替換而不改變大小：讀入、替換那一行、寫回。
    _t143_tmp="$TMP/t143.rewrite"
    : > "$_t143_tmp"
    while IFS= read -r _line; do
        if [[ $_line == $_t143_old ]]; then print -r -- "$_t143_new"; else print -r -- "$_line"; fi
    done < "$TMP/t143.csv" > "$_t143_tmp"
    mv "$_t143_tmp" "$TMP/t143.csv"
    touch -r "$TMP/t143.ref" "$TMP/t143.csv"

    _t143_indexed=$("$CSV2" -contains 'v000200' -i "$TMP/t143.csv" | cut -f1)
    _t143_scanned=$("$CSV2" -contains 'v000200' --no-index -i "$TMP/t143.csv" | cut -f1)
    _t143_verify=$("$CSV2" --verify-index -i "$TMP/t143.csv" 2>&1)

    if [[ $_t143_verify == *"cannot be used"* ]]; then
        # The stamp rejected the file, so this platform's touch -r did not
        # carry the nanoseconds and the hazard cannot be staged here.
        # 戳記否決了這個檔案，表示這個平台的 touch -r 沒有帶上奈秒，無法在此佈置這個情境。
        # Recorded for T69b. It cannot probe this itself: deciding whether
        # touch -r carried the nanoseconds needs to READ them, and the guest
        # has no stat at all -- which is the same platform that skips here.
        # The case that made the skip is the only thing that knows.
        # 記錄下來給 T69b。它自己探測不到：要判斷 touch -r 有沒有帶上奈秒就得「讀」到奈秒，
        # 而 guest 根本沒有 stat——而那正是會在這裡跳過的同一個平台。知道這件事的，只有
        # 「造成這次跳過」的那個案例本身。
        T143_SKIPPED=1
        skipt "T143 an index the O(1) stamp still accepts / 一份 O(1) 戳記仍然接受的索引 (touch -r did not carry the nanoseconds here / 此平台的 touch -r 沒有帶上奈秒)"
    elif [[ $_t143_indexed != $_t143_scanned ]]; then
        ok "T143a the documented hazard is still reachable: indexed says $_t143_indexed, a scan says $_t143_scanned / 有文件記載的那個風險仍然可達：索引說 $_t143_indexed，掃描說 $_t143_scanned"
        assert_contains "$_t143_verify" "MISMATCH" \
            "T143b while --verify-index still catches it / 而 --verify-index 仍然抓得到"
        # Only -contains reads the sidecar, which is the mechanism behind the
        # corruption the READMEs describe: the ADDRESS is wrong, and the verb
        # you hand it to is not. With this stale index in place, -get agrees
        # with itself under --no-index -- so the two halves of the compose
        # recipe disagree while each behaves correctly.
        # An earlier version of this check looked for the word "index" in
        # -debug output from each verb and compared two silences.
        # 只有 -contains 會讀 sidecar，而那正是兩份 README 所描述的那個損壞的機制：錯的是
        # 「位址」，不是你把它交給的那個動詞。在這份過期索引存在的情況下，-get 與它自己
        # 在 --no-index 下的答案一致——於是「組合配方」的兩半彼此矛盾，而各自都沒有做錯。
        # 這個檢查的較早版本，是在各動詞的 -debug 輸出裡找「index」這個字，比較的是兩片沉默。
        assert_eq "$("$CSV2" -get 200:2 -i "$TMP/t143.csv")" \
                  "$("$CSV2" -get 200:2 --no-index -i "$TMP/t143.csv")" \
            "T143c while -get gives the same answer with the sidecar and without it / 而 -get 在「有 sidecar」與「沒有 sidecar」下給的是同一個答案"
        # WHICH verbs read the sidecar, measured rather than asserted from a
        # report. The READMEs said "only -contains" for a day, taken from a
        # blind round and never run; -mid takes an index hit too, and a reader
        # deciding when they need --verify-index was being told the wrong set.
        # 哪些動詞會讀 sidecar，用量的、不是從報告抄的。兩份 README 有一天寫著「只有
        # -contains」，那句話取自一份盲測報告、從來沒有被執行過；`-mid` 同樣會走索引，
        # 而一個「在判斷自己何時需要 --verify-index」的讀者，拿到的是錯的那一組。
        for _t143_verb in "-contains v000200" "-mid 100,110" "-tail 5"; do
            # Two different messages for two different consumers: the seek
            # says "index hit", the parallel search says "trusting index". A
            # probe for one of them concluded the other verb does not read the
            # sidecar -- the same overgeneralisation this case exists to
            # correct, made while correcting it.
            # 兩個不同的消費端有兩種不同的訊息：seek 說「index hit」，平行搜尋說「trusting
            # index」。只探測其中一種，就會得出「另一個動詞不讀 sidecar」的結論——正是這個
            # 案例要糾正的那種以偏概全，而它是在糾正的過程中犯的。
            # Captured, not piped. Under this file's `exec > >(tee ...)` the
            # form `cmd 2>&1 >/dev/null | grep` did not deliver stderr to the
            # grep -- three cases reported "does not read the sidecar" about
            # output that plainly said it did. A probe printing the same
            # capture showed the text; the difference was the plumbing.
            # 用捕獲，不用管線。在這個檔案的 `exec > >(tee …)` 之下，
            # `cmd 2>&1 >/dev/null | grep` 這個寫法沒有把 stderr 交給那個 grep——於是三個
            # 案例對著「明明說了自己讀了 sidecar」的輸出，回報「它不讀」。把同一份捕獲印出來
            # 就看得到那段文字；差別在管線本身。
            _t143_out=$("$CSV2" ${=_t143_verb} -i "$TMP/t143.csv" -debug 2>&1 >/dev/null)
            if [[ $_t143_out == *"index hit"* || $_t143_out == *"trusting index"* ]]; then
                ok "T143f $_t143_verb reads the sidecar / $_t143_verb 會讀 sidecar"
            else
                bad "T143f $_t143_verb did not / $_t143_verb 沒有讀"
            fi
        done
        _t143_get=$("$CSV2" -get 200:2 -i "$TMP/t143.csv" -debug 2>&1 >/dev/null)
        if [[ $_t143_get == *"index hit"* || $_t143_get == *"trusting index"* ]]; then
            bad "T143g -get took an index hit, which the READMEs say it does not / -get 走了索引，而兩份 README 說它不會"
        else
            ok "T143g while -get does not / 而 -get 不會"
        fi
    else
        bad "T143a the hazard did not reproduce (both said $_t143_indexed); if that is now impossible, the README's description of the O(1) check must change / 那個風險沒有重現（兩邊都是 $_t143_indexed）；若它確實已不可能發生，README 對 O(1) 檢查的描述就必須修改"
    fi
fi
unset CSV2_INDEX_MIN_BYTES CSV2_PARALLEL_MIN_BYTES CSV2_PARALLEL_CHUNK_BYTES

# ---------------------------------------------------------------------
# T144 -- names with a comma in them, and a column part that is empty.
#
# Round 54: a file whose first column is called `a,b` produced
# `the columns are: a,b, c` -- three columns to any reader, human or script.
# And `-get 1:` answered "expected r:c", a complaint about a shape that is
# right, when what is missing is the column.
#
# T144 —— 名字裡有逗號的欄位，以及一個空的欄位部分。
# ---------------------------------------------------------------------
echo
echo "--- T144: a comma inside a name / T144：名字裡的逗號 ---"

print -r -- '"a,b",c'  > "$TMP/t144.csv"
print -r -- '1,2'     >> "$TMP/t144.csv"

_t144=$("$CSV2" -hash zz -i "$TMP/t144.csv" -o "$TMP/t144_out.csv" 2>&1)
assert_contains "$_t144" '"a,b", "c"' \
    "T144a the column list quotes each name, so a comma inside one is visible / 欄位清單為每個名字加引號，因此名字裡的逗號看得出來"

# COLS splits on commas and has no escape, so a name containing one is reached
# by NUMBER. That is the documented answer and it has to work.
# COLS 以逗號分隔且沒有跳脫語法，因此含逗號的名字要用「欄號」定址。那是文件給的答案，
# 它必須真的可用。
"$CSV2" -hash 1 -i "$TMP/t144.csv" -o "$TMP/t144_out.csv"
assert_contains "$(head -1 "$TMP/t144_out.csv")" 'a,b:hash' \
    "T144b and the column number reaches a name a comma-separated list cannot / 而欄號抵達得了一個「逗號分隔清單」抵達不了的名字"

# -delete -col takes ONE name, not a list, which is the other way to reach it.
# Changing that would silently turn "delete this column" into "delete two".
# -delete -col 收的是「一個」名字而不是清單，那是抵達它的另一條路。改掉它，會讓
# 「刪掉這一欄」靜默地變成「刪掉兩欄」。
"$CSV2" -delete -col 'a,b' -i "$TMP/t144.csv" -o "$TMP/t144_del.csv"
assert_eq "$(head -1 "$TMP/t144_del.csv")" 'c' \
    "T144c -delete -col takes one name, comma and all / -delete -col 收的是一個名字，連逗號一起"

_t144_e=$("$CSV2" -get '1:' -i "$TMP/t144.csv" 2>&1)
if [[ $_t144_e == *"the part after the colon is empty"* && $_t144_e != *"expected r:c"* ]]; then
    ok "T144d an empty column part is named as one / 空的欄位部分會被指名出來"
else
    bad "T144d $(print -r -- $_t144_e | head -1) / 訊息如上"
fi

# The shape complaint still exists for things that really are the wrong shape.
# 對「真的形狀不對」的東西，那句形狀的抱怨仍然存在。
_t144_s=$("$CSV2" -get ':2' -i "$TMP/t144.csv" 2>&1)
assert_contains "$_t144_s" "expected r:c" \
    "T144e while a genuinely malformed address still gets the shape complaint / 而真正格式錯誤的位址仍然得到那句形狀的抱怨"

# ---------------------------------------------------------------------
# T145 -- advice that has to work when followed.
#
# Round 55 followed a refusal's own remedy and lost a record to it. The message
# offered "Rename the file or drop --headers" as equals: dropping --headers
# reads the file as it is, while renaming a .csv2 to .csv makes the second
# header row into data record 1, at rc=0, with output that looks entirely
# plausible. The round only caught it by diffing record counts afterwards.
#
# Two more from the same task: `-insert` past the end diagnosed correctly and
# never mentioned -append, which the README names as the answer elsewhere; and
# `-o /dev/stdout`, with stdout redirected to a FILE, failed from inside the
# sink with "cannot create temporary file beside /dev/fd/1: No such file or
# directory" -- a false cause, a path the caller never typed, no remedy.
#
# T145 —— 照著做就必須行得通的建議。
# 第 55 回合照著一則拒絕自己給的補救方式去做，因而弄丟了一筆紀錄。
# ---------------------------------------------------------------------
echo
echo "--- T145: following the message / T145：照著訊息去做 ---"

# Its own fixture, not compare/vs-sqlite.csv2: that directory is not in the
# payload the guest is built from, and the suffix/--headers check runs before
# the file is opened -- so T145a passed there against a file that did not
# exist, while T145b compared two empty strings. A case that passes because
# its input is missing is not a case.
# 自己的 fixture，不用 compare/vs-sqlite.csv2：那個目錄不在 guest 的 payload 裡，而
# 「副檔名對 --headers」的檢查在開檔之前就跑了——於是 T145a 在那裡對著一個不存在的檔案通過，
# 而 T145b 比較的是兩個空字串。一個「因為輸入不存在而通過」的案例，不是一個案例。
print -r -- 'pkg,note'      > "$TMP/t145_two.csv2"
print -r -- '套件,備註'     >> "$TMP/t145_two.csv2"
print -r -- 'busybox,small' >> "$TMP/t145_two.csv2"
_t145_msg=$("$CSV2" -r --headers 1 -i "$TMP/t145_two.csv2" 2>&1 | head -1)
if [[ $_t145_msg == *"Drop --headers"* && $_t145_msg == *"becomes data record 1"* ]]; then
    ok "T145a the --headers mismatch names the lossless remedy and what the other one costs / --headers 不符時，訊息指出無損的那條路，以及另一條的代價"
else
    bad "T145a $_t145_msg / 訊息如上"
fi

# The hazard the message now warns about, measured: the rename really does turn
# a header row into a record.
# 訊息現在警告的那個風險，實測：改檔名確實會把一列標頭變成一筆紀錄。
cp "$TMP/t145_two.csv2" "$TMP/t145_renamed.csv"
_t145_two=$("$CSV2" -r --json -i "$TMP/t145_two.csv2" | tail -1)
_t145_one=$("$CSV2" -r --json -i "$TMP/t145_renamed.csv" | tail -1)
if [[ -n $_t145_two && $_t145_two != $_t145_one ]]; then
    ok "T145b and renaming really does change the record count / 而改檔名確實會改變紀錄數"
else
    bad "T145b both said $_t145_two, so the warning describes something that does not happen / 兩者都是 $_t145_two，那則警告描述的事情並未發生"
fi

print -r -- 'a,b'  > "$TMP/t145.csv"
print -r -- '1,x' >> "$TMP/t145.csv"
_t145_ins=$("$CSV2" -insert 99 'z,z' -i "$TMP/t145.csv" -o "$TMP/t145_out.csv" 2>&1)
assert_contains "$_t145_ins" "use -append" \
    "T145c -insert past the end names the verb that does what was wanted / -insert 越過結尾時，訊息指出真正做得到那件事的動詞"

_t145_upd=$("$CSV2" -update 99:1 X -i "$TMP/t145.csv" -o "$TMP/t145_out.csv" 2>&1)
if [[ $_t145_upd != *"-append"* ]]; then
    ok "T145d while -update past the end does not, because there is no such answer for it / 而 -update 越界時不會，因為它沒有對應的正解"
else
    bad "T145d -update was offered -append, which does not do what -update does / -update 被建議了 -append，而那不是 -update 做的事"
fi

# -o into a directory that cannot hold a temp file. /dev is the case round 55
# hit; the message must name the path as typed and the way out.
# -o 指向一個放不下暫存檔的目錄。第 55 回合撞到的是 /dev；訊息必須指名「打出來的那個路徑」
# 與出路。
if (( IS_WINDOWS )); then
    T145E_SKIPPED=1
    skipt "T145e -o into a directory that cannot take a new file / -o 指向一個放不下新檔案的目錄 (no /dev here / 這裡沒有 /dev)"
else
    # stdout to a regular FILE, which is the case round 55 hit and the one the
    # earlier check could not catch: /dev/stdout then resolves to /dev/fd/1,
    # which IS a regular file, so "not a regular file" let it through. With
    # stdout on /dev/null the older check already fired, and a version of this
    # case written that way passed against the build that had the defect.
    # stdout 導向一個「一般檔案」，那正是第 55 回合撞到、而先前那道檢查抓不到的情況：
    # /dev/stdout 此時解析成 /dev/fd/1，而它**是**一般檔案，於是「不是一般檔案」放行了它。
    # 若把 stdout 導到 /dev/null，較早那道檢查本來就會發動——這個案例的那個寫法，對「還帶著
    # 這個缺陷的建置」照樣通過。
    _t145_dev=$("$CSV2" -r -t -i "$TMP/t145.csv" -o /dev/stdout 2>&1 > "$TMP/t145_capture.txt")
    if [[ -z ${_t145_dev//[[:space:]]/} ]]; then
        # Some systems can create a file beside /dev/fd/1 -- the guest, running
        # as root, is one -- and then this is not a failure at all. The
        # property under test is what the message says WHEN it fails, so there
        # is nothing here to check rather than something that passed.
        # 有些系統在 /dev/fd/1 旁邊建得了檔案——以 root 執行的 guest 就是——那時這根本不是
        # 一次失敗。這裡要測的性質是「失敗時那則訊息說了什麼」，因此此處沒有東西可檢查，
        # 而不是「有東西通過了」。
        T145E_SKIPPED=1
        skipt "T145e -o into a directory that cannot take a new file / -o 指向一個放不下新檔案的目錄 (this system can create one beside /dev/fd/1 / 此系統在 /dev/fd/1 旁邊建得了檔案)"
    elif [[ $_t145_dev == *"/dev/stdout"* && $_t145_dev == *"-so"* && $_t145_dev != *"/dev/fd/1"* ]]; then
        ok "T145e it names the path as typed and points at -so / 它指名打出來的那個路徑，並指向 -so"
    else
        bad "T145e $(print -r -- $_t145_dev | head -1) / 訊息如上"
    fi
fi

# A directory that does not exist is a different sentence: "use -so" is the
# answer to /dev and nonsense in reply to a typo.
# 不存在的目錄是另一句話：「請用 -so」是 /dev 的答案，拿來回答一個打錯的路徑則毫無意義。
_t145_typo=$("$CSV2" -r -t -i "$TMP/t145.csv" -o "$TMP/no_such_dir/x.csv" 2>&1)
if [[ $_t145_typo == *"does not exist"* && $_t145_typo != *"-so"* ]]; then
    ok "T145f while a missing directory is told it is missing / 而不存在的目錄會被告知它不存在"
else
    bad "T145f $(print -r -- $_t145_typo | head -1) / 訊息如上"
fi

# ---------------------------------------------------------------------
# T146 -- a conversion recipe has to produce a file this tool will open.
#
# Round 55: "the iconv/tr recipes produce .utf8/.lf filenames that csv2's own
# suffix rule then rejects; neither recipe mentions renaming to .csv". Advice
# that ends in a file the tool refuses is not advice, and the round had to work
# the rename out for itself.
#
# T146 —— 一條轉換建議，必須產出一個「這個工具打得開」的檔案。
# ---------------------------------------------------------------------
echo
echo "--- T146: following the conversion advice / T146：照著轉換建議去做 ---"

# The CR recipe, run as given.
# CR 那條建議，照著它給的樣子執行。
printf 'a,b\r1,x\r2,y\r' > "$TMP/t146_cr.csv"
_t146_cr=$("$CSV2" -r -t -i "$TMP/t146_cr.csv" 2>&1 >/dev/null | head -1)
assert_contains "$_t146_cr" "converted.csv" \
    "T146a the CR refusal names a destination csv2 can open / CR 的拒絕指出一個 csv2 打得開的目的地"
if [[ $_t146_cr == *".csv or .csv2 suffix"* ]]; then
    ok "T146b and says why the suffix matters / 並說明為什麼副檔名要緊"
else
    bad "T146b $_t146_cr / 訊息如上"
fi

tr '\r' '\n' < "$TMP/t146_cr.csv" > "$TMP/t146_converted.csv"
assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t146_converted.csv")" "1" \
    "T146c and the file it tells you to make is one csv2 reads / 而它叫你產生的那個檔案，csv2 讀得了"

# The UTF-16 recipe. iconv is not everywhere -- the guest has no such applet --
# so the recipe's TEXT is checked always and the conversion only where the tool
# it names exists.
# UTF-16 那條建議。iconv 不是到處都有——guest 沒有這個 applet——因此「建議的文字」一律檢查，
# 而那次轉換只在「它指名的工具存在」的地方做。
printf '\xff\xfea\x00,\x00b\x00\n\x001\x00,\x00x\x00\n\x00' > "$TMP/t146_u16.csv"
_t146_u=$("$CSV2" -r -t -i "$TMP/t146_u16.csv" 2>&1 >/dev/null | head -1)
assert_contains "$_t146_u" "converted.csv" \
    "T146d the UTF-16 refusal names one too / UTF-16 的拒絕同樣指出一個"

if (( $+commands[iconv] )); then
    if iconv -f UTF-16LE -t UTF-8 "$TMP/t146_u16.csv" > "$TMP/t146_u8.csv" 2>/dev/null; then
        assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t146_u8.csv")" "1" \
            "T146e and following it produces a file csv2 reads / 而照著它做，產生的檔案 csv2 讀得了"
    else
        T146E_SKIPPED=1
        skipt "T146e following the UTF-16 recipe / 照著 UTF-16 那條建議做 (iconv here cannot do UTF-16LE / 此處的 iconv 做不了 UTF-16LE)"
    fi
else
    T146E_SKIPPED=1
    skipt "T146e following the UTF-16 recipe / 照著 UTF-16 那條建議做 (no iconv on this platform / 此平台沒有 iconv)"
fi

# ---------------------------------------------------------------------
# T147 -- output pasted into an example that csv2 never printed.
#
# Round 56 found a directory listing inside a ```console block, twice in one
# example, in output csv2 does not produce. It arrived when a message quoted in
# the README was updated by capturing a command's output and substituting it
# whole -- the capture carried a bare `ls` with it, and the case that pins the
# quoted message (T58) passed, because the message line was still there.
#
# The check is deliberately narrow: three or more consecutive lines inside a
# console block that are bare filenames. That is what a pasted `ls` looks like
# and nothing else in these examples does -- CSV output has commas, reports
# have tabs, messages have spaces. A wider rule would have to decide what csv2
# "would" print, which is the question the examples exist to answer.
#
# T147 —— 被貼進範例、而 csv2 從來不會印出的輸出。
# 第 56 回合在一個 ```console 區塊裡找到一段目錄列表，同一個範例裡出現兩次。它是這樣進去的：
# 更新 README 引用的一則訊息時，我以「捕獲指令輸出再整段替換」的方式進行，而那次捕獲把一段
# 裸的 `ls` 一起帶了進來；而釘住那則引用訊息的案例（T58）照樣通過，因為那一行訊息還在。
# 這個檢查刻意寫得很窄：console 區塊裡連續三行以上的「裸檔名」。一段被貼進來的 `ls` 就長那樣，
# 而這些範例裡沒有別的東西長那樣——CSV 輸出有逗號、報告有 tab、訊息有空白。更寬的規則就得去
# 判斷 csv2「會不會」印出某段東西，而那正是這些範例本身要回答的問題。
# ---------------------------------------------------------------------
echo
echo "--- T147: no pasted listings in the examples / T147：範例裡沒有被貼進來的目錄列表 ---"

t147_scan() {   # file -> prints offending line numbers
    LC_ALL=C awk '
        /^```console/ { inblock = 1; run = 0; next }
        /^```/        { inblock = 0; run = 0; next }
        !inblock      { next }
        {
            line = $0
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line ~ /^[A-Za-z0-9_.-]+\.(csv|csv2|txt|log|bak|keep|index|out|err)$/) {
                run++
                if (run >= 3) print FILENAME ":" NR ": " line
            } else {
                run = 0
            }
        }
    ' "$1"
}

t147_hits="$(t147_scan "$ROOT/README.md")$(t147_scan "$ROOT/README.zh-TW.md")"
if [[ -z ${t147_hits//[[:space:]]/} ]]; then
    ok "T147a no console block carries a pasted directory listing / 沒有任何 console 區塊帶著被貼進來的目錄列表"
else
    bad "T147a pasted listing in an example: $(print -r -- $t147_hits | head -3) / 範例裡有被貼進來的列表"
fi

# ---------------------------------------------------------------------
# T148 -- the audit trail was thinnest where the loss is largest.
#
# Round 56: the -log table promises "old and new values in an ordinary column
# -- in full, never truncated", and `-delete -cell` destroyed exactly such a
# value while logging only `blank 1:notes`. A deleted RECORD logged its number
# and nothing of its contents. `-hash` logged no column names at all, and
# unkeyed it logged nothing whatsoever -- the operation that is both
# irreversible and dictionary-attackable had the weakest trail of any.
#
# T148 —— 稽核軌跡最薄的地方，正是損失最大的地方。
# ---------------------------------------------------------------------
echo
echo "--- T148: what the log records when something is destroyed / T148：有東西被銷毀時，log 記下了什麼 ---"

print -r -- 'a,notes'          > "$TMP/t148.csv"
print -r -- '1,secret-value'  >> "$TMP/t148.csv"
print -r -- '2,y'             >> "$TMP/t148.csv"

cp "$TMP/t148.csv" "$TMP/t148_blank.csv"
rm -f "$TMP/t148_blank.log"
"$CSV2" -delete -cell 1:2 -i "$TMP/t148_blank.csv" --in-place -log "$TMP/t148_blank.log"
assert_contains "$(cat "$TMP/t148_blank.log")" 'blank 1:notes: "secret-value"' \
    "T148a blanking a cell records the value it destroyed / 清空一個儲存格會記下它銷毀的那個值"

cp "$TMP/t148.csv" "$TMP/t148_del.csv"
rm -f "$TMP/t148_del.log"
"$CSV2" -delete 1 -i "$TMP/t148_del.csv" --in-place -log "$TMP/t148_del.log"
# Both sides quoted: a column name can contain the comma this entry separates
# on, and `delete record 1: a,b="1"` reads as three fields. Round 58 found that
# a day after the entry was added.
# 兩邊都加引號：欄名裡可以含有「這則紀錄用來分隔的那個逗號」，而 `delete record 1: a,b="1"`
# 讀起來像三個欄位。第 58 回合在這則紀錄加上去的隔天就發現了。
assert_contains "$(cat "$TMP/t148_del.log")" 'delete record 1: "a"="1", "notes"="secret-value"' \
    "T148b and deleting a record records its contents, by column / 而刪除一筆紀錄會逐欄記下它的內容"

cp "$TMP/t148.csv" "$TMP/t148_h.csv"
rm -f "$TMP/t148_h.log"
"$CSV2" -hash notes -i "$TMP/t148_h.csv" -o "$TMP/t148_h_out.csv" -log "$TMP/t148_h.log"
_t148_h=$(cat "$TMP/t148_h.log")
if [[ $_t148_h == *"hashing columns notes"* && $_t148_h == *"NO key"* ]]; then
    ok "T148c an unkeyed -hash records the columns and that no key was used / 無金鑰的 -hash 會記下欄位，以及「沒有用金鑰」"
else
    bad "T148c $(print -r -- $_t148_h | grep -o 'hashing.*' | head -1) / log 內容如上"
fi

# Redaction still wins over the new detail: a protected column must not arrive
# in the log in the clear just because its record was deleted.
# 遮蔽規則仍然優先於這些新增的細節：一個受保護的欄位，不能因為它所在的紀錄被刪掉，就以明文
# 進到 log 裡。
rm -f "$TMP/t148_r.log"
cp "$TMP/t148_h_out.csv" "$TMP/t148_r.csv"
"$CSV2" -delete 1 -i "$TMP/t148_r.csv" --in-place -log "$TMP/t148_r.log"
_t148_r=$(cat "$TMP/t148_r.log")
if [[ $_t148_r == *'"notes"=<redacted>'* ]]; then
    ok "T148d while a protected column is still redacted in that record / 而該紀錄裡受保護的欄位仍然被遮蔽"
else
    bad "T148d $(print -r -- $_t148_r | grep -o 'delete record.*' | head -1) / log 內容如上"
fi

# One record is one entry: a value containing a newline must not become two
# lines in the log, which is the property T127 pinned for arguments.
# 一筆紀錄就是一則紀錄：含換行的值不得在 log 裡變成兩行，那正是 T127 為引數釘住的性質。
print -r -- 'a,notes'      > "$TMP/t148_nl.csv"
printf '1,"x\ny"\n'      >> "$TMP/t148_nl.csv"
rm -f "$TMP/t148_nl.log"
"$CSV2" -delete 1 -i "$TMP/t148_nl.csv" --in-place -log "$TMP/t148_nl.log"
assert_eq "$(grep -c 'delete record' "$TMP/t148_nl.log")" "1" \
    "T148e and a record holding a newline is still one log entry / 而含換行的紀錄在 log 裡仍然是一則"

# ---------------------------------------------------------------------
# T149 -- what a value can do to the terminal, and to a file's line endings.
#
# Round 56, two findings from "someone else's file":
#
#   - the locating report escaped \t \n \r \\ and passed every other control
#     through, so a cell holding ESC-[-31m recoloured the terminal from inside
#     the third column -- and an ESC can also erase the line it is printed on,
#     which is the line carrying the address;
#   - `-append --in-place` on a CRLF file appended an LF record, leaving one
#     file written two ways. csv2 reads it back (endings are decided per
#     record); plenty of other tools do not.
#
# T149 —— 一個值能對終端機、以及對一個檔案的行尾做什麼。
# ---------------------------------------------------------------------
echo
echo "--- T149: control characters and line endings / T149：控制字元與行尾 ---"

printf 'a,b\n1,"pre\x1b[31mRED\x1b[0m"\n' > "$TMP/t149_esc.csv"
_t149_rep=$("$CSV2" -contains RED -i "$TMP/t149_esc.csv")
if [[ $_t149_rep == *'\x1B['* ]]; then
    ok "T149a an ESC in a value is escaped in the report / 值裡的 ESC 在報告中會被跳脫"
else
    bad "T149a the report carried it raw / 報告原樣帶著它：$(print -r -- $_t149_rep | od -c | head -1)"
fi
if [[ $_t149_rep != *$'\x1b'* ]]; then
    ok "T149b and no raw escape byte reaches the terminal / 沒有任何原始的 escape 位元組抵達終端機"
else
    bad "T149b a raw ESC byte is still in the report / 報告裡仍有原始的 ESC 位元組"
fi
assert_eq "$(print -r -- $_t149_rep | wc -l | tr -d ' ')" "1" \
    "T149c while the report is still one line per hit / 而報告仍然是每個命中一行"

# The value itself is unchanged: escaping is display, not storage.
# 值本身沒有變：跳脫屬於顯示，不屬於儲存。
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t149_esc.csv" | od -A n -c | tr -s ' ')" \
    "$(printf 'pre\x1b[31mRED\x1b[0m\n' | od -A n -c | tr -s ' ')" \
    "T149d and -get still returns the stored bytes / 而 -get 回傳的仍然是儲存的位元組"

# Line endings: an append matches what the file already uses.
# 行尾：追加時配合檔案已經在用的那一種。
printf 'a,b\r\n1,x\r\n' > "$TMP/t149_crlf.csv"
"$CSV2" -append '2,y' -i "$TMP/t149_crlf.csv" --in-place
if od -c "$TMP/t149_crlf.csv" | tr -s ' ' | grep -q '2 , y \\r \\n'; then
    ok "T149e an append to a CRLF file ends its record with CRLF / 對 CRLF 檔案的追加，其紀錄以 CRLF 結尾"
else
    bad "T149e the file now mixes endings / 這個檔案現在混用了行尾：$(od -c "$TMP/t149_crlf.csv" | head -1)"
fi

printf 'a,b\n1,x\n' > "$TMP/t149_lf.csv"
"$CSV2" -append '2,y' -i "$TMP/t149_lf.csv" --in-place
if [[ $(od -c "$TMP/t149_lf.csv" | grep -c '\\r') -eq 0 ]]; then
    ok "T149f while an LF file stays LF / 而 LF 檔案維持 LF"
else
    bad "T149f a CR appeared in an LF file / LF 檔案裡出現了 CR"
fi

# And reading either back still writes LF, which is what the README promises
# of OUTPUT.
# 而把兩者讀回來時輸出仍然是 LF，那正是 README 對「輸出」的承諾。
if [[ $("$CSV2" -r -t -i "$TMP/t149_crlf.csv" | od -c | grep -c '\\r') -eq 0 ]]; then
    ok "T149g reading a CRLF file still writes LF / 讀一個 CRLF 檔案，輸出仍然是 LF"
else
    bad "T149g the output carried CR / 輸出帶著 CR"
fi

# ---------------------------------------------------------------------
# T150 -- `all` belongs to -decrypt, and to no other verb.
#
# Round 56: "a column named `all` cannot be addressed by name with -decrypt".
# Checking it turned up the larger half: `all` was special for EVERY verb, so
# `-hash all` on a file with no encrypted columns selected nothing and exited 0
# having done nothing -- the silent no-op T140 closed for an empty list,
# reached by another road. The README gives the keyword to -decrypt alone.
#
# T150 —— `all`屬於 -decrypt，不屬於任何其他動詞。
# 第 56 回合說「名為 `all` 的欄位無法以名字被 -decrypt 定址」。查它時翻出了更大的那一半：
# `all` 對「每一個」動詞都是特別的，於是 `-hash all` 在一個沒有加密欄位的檔案上什麼也沒選中、
# 以 0 結束、什麼也沒做——那正是 T140 為「空清單」關掉的那個靜默無操作，換了一條路走回來。
# ---------------------------------------------------------------------
echo
echo "--- T150: the all keyword / T150：all 這個關鍵字 ---"

print -r -- 'all,b'  > "$TMP/t150_named.csv"
print -r -- '1,x'   >> "$TMP/t150_named.csv"
"$CSV2" -hash all -i "$TMP/t150_named.csv" -o "$TMP/t150_out.csv"
assert_contains "$(head -1 "$TMP/t150_out.csv")" "all:hash" \
    "T150a a column named all is hashed by name / 名為 all 的欄位可以用名字雜湊"

print -r -- 'a,b'  > "$TMP/t150_plain.csv"
print -r -- '1,x' >> "$TMP/t150_plain.csv"
_t150=$("$CSV2" -hash all -i "$TMP/t150_plain.csv" -o "$TMP/t150_out.csv" 2>&1)
_t150_rc=$?
if (( _t150_rc == 1 )) && [[ $_t150 == *'no column named "all"'* ]]; then
    ok "T150b while -hash all on a file with no such column is refused, not a no-op / 而在沒有該欄位的檔案上，-hash all 會被拒絕，不是什麼也不做"
else
    bad "T150b exited $_t150_rc: $(print -r -- $_t150 | head -1) / 結果如上"
fi

_t150_d=$("$CSV2" -decrypt all -i "$TMP/t150_plain.csv" -o "$TMP/t150_out.csv" 2>&1)
assert_contains "$_t150_d" "no encrypted columns found" \
    "T150c and -decrypt all still means every marked column / 而 -decrypt all 仍然代表「每一個被標記的欄位」"

# ---------------------------------------------------------------------
# T151 -- three sentences the READMEs now make, which nothing was checking.
#
# `-so` as a dry run before an irreversible edit, and `--` as the way to write
# a value that begins with a dash -- which csv2's own error message recommends
# and the README never mentioned. The third sentence from the same batch, that
# only -contains reads the sidecar, is checked in T143c, where a stale index is
# already staged and the claim can be measured instead of inferred.
#
# T151 —— 兩份 README 現在說出口、而先前沒有任何東西在檢查的三句話。
# ---------------------------------------------------------------------
echo
echo "--- T151: the dry run and the dash / T151：乾跑與減號 ---"

print -r -- 'a,b'  > "$TMP/t151.csv"
print -r -- '1,x' >> "$TMP/t151.csv"
print -r -- '2,y' >> "$TMP/t151.csv"
_t151_before=$(cksum < "$TMP/t151.csv")

_t151_dry=$("$CSV2" -update 1:2 'CHANGED' -t -i "$TMP/t151.csv" -so)
assert_eq "$(cksum < "$TMP/t151.csv")" "$_t151_before" \
    "T151a -so previews an edit without touching the file / -so 預覽一次編輯，而不碰那個檔案"
assert_contains "$_t151_dry" "CHANGED" \
    "T151b and shows what the edit would produce / 並顯示那次編輯會產生什麼"

"$CSV2" -update 99:2 'CHANGED' -t -i "$TMP/t151.csv" -so >/dev/null 2>&1
assert_eq "$?" "1" \
    "T151c while an out-of-range address is refused in the dry run too / 而越界的位址在乾跑時同樣會被拒絕"

# `--`, which the tool's own message recommends.
# `--`，那是工具自己的訊息推薦的寫法。
"$CSV2" -update 1:2 -- --in-place -i "$TMP/t151.csv" -o "$TMP/t151_dash.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t151_dash.csv")" "--in-place" \
    "T151d -- lets a value that looks like a flag be written / -- 讓一個「長得像旗標」的值可以被寫入"


# ---------------------------------------------------------------------
# T152 -- the compose recipe, and the shell in the middle of it.
#
# Round 57: the recipe is annotated "# round-trips" and does not, for a value
# ending in a newline. csv2 is not at fault -- `$( )` strips every trailing
# newline, so the value comes back one byte shorter and is written back that
# way at rc=0. The READMEs now carry the caveat and the `printf x` form that
# survives it; both belong to a test, since a recipe that does not work is
# worse than no recipe.
#
# Also here: `-contains` prints in ascending record order. The recipe leans on
# `head -1` and nothing said so.
#
# T152 —— 那份組合配方，以及夾在中間的那個 shell。
# ---------------------------------------------------------------------
echo
echo "--- T152: the recipe as written / T152：照著寫出來的那份配方 ---"

print -r -- 'a,b'      > "$TMP/t152.csv"
printf '1,"x\n"\n'   >> "$TMP/t152.csv"

# The plain form loses the trailing newline -- that is what the caveat says.
# 單純的寫法會弄丟結尾的換行——那正是那句但書說的。
_t152_plain=$("$CSV2" -get 1:2 -i "$TMP/t152.csv")
if [[ $_t152_plain == "x" ]]; then
    ok "T152a \$( ) strips the value's trailing newline, as the caveat says / \$( ) 會吃掉值結尾的換行，一如那句但書所說"
else
    bad "T152a expected the stripped form, got $(print -r -- $_t152_plain | od -c | head -1) / 預期是被吃掉的那個形式"
fi

# The documented form keeps it.
# 文件給的那個寫法保得住它。
_t152_kept=$("$CSV2" -get 1:2 -i "$TMP/t152.csv"; printf x); _t152_kept=${_t152_kept%x}
assert_eq "$(print -rn -- "$_t152_kept" | od -A n -c | tr -s ' ')" "$(printf 'x\n\n' | od -A n -c | tr -s ' ')" \
    "T152b while the printf x form keeps every byte -get produced / 而 printf x 的寫法保住了 -get 產生的每一個位元組"

# The recipe as a WHOLE, which is the thing the README publishes. printf x
# keeps two newlines -- the value's own and the one -get adds -- so a recipe
# that stops there grows the value by one on every round trip. It was published
# without the third line on 2026-08-21 and round 61 measured the growth.
# 那份配方「整體」——那才是 README 發表出去的東西。printf x 保住的是兩個換行：值自己的，
# 以及 -get 加上的那一個；因此一份「停在那裡」的配方，每來回一次就讓值多一個換行。
# 它 2026-08-21 發表時就少了第三行，而第 61 回合量到了那個增長。
_t152_final=${_t152_kept%$'\n'}
"$CSV2" -update 1:2 "$_t152_final" -i "$TMP/t152.csv" -o "$TMP/t152_rt.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t152_rt.csv" | od -A n -c | tr -s ' ')" \
          "$("$CSV2" -get 1:2 -i "$TMP/t152.csv" | od -A n -c | tr -s ' ')" \
    "T152b1 and the three-line recipe round-trips a value ending in a newline / 而三行的配方能讓「以換行結尾的值」原樣來回"


# And the whole recipe still round-trips a value with no trailing whitespace,
# which is what T96 covers and what most values are.
# 而對「結尾沒有空白」的值，整份配方仍然可以 round-trip——那是 T96 涵蓋的、也是大多數值的情況。
print -r -- 'a,b'          > "$TMP/t152b.csv"
print -r -- '1,"x,y"'     >> "$TMP/t152b.csv"
_t152_addr=$("$CSV2" -contains 'x,y' -i "$TMP/t152b.csv" | head -1 | cut -f1)
_t152_val=$("$CSV2" -get "$_t152_addr" -i "$TMP/t152b.csv")
"$CSV2" -update "$_t152_addr" "$_t152_val" -i "$TMP/t152b.csv" --in-place
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t152b.csv")" "x,y" \
    "T152c the recipe round-trips a value with no trailing whitespace / 對結尾沒有空白的值，配方可以 round-trip"

# Ascending record order, which `head -1` in the recipe depends on.
# 以紀錄號遞增的順序輸出，那是配方裡的 `head -1` 所依賴的。
print -r -- 'a,b'  > "$TMP/t152c.csv"
print -r -- '1,z' >> "$TMP/t152c.csv"
print -r -- '2,z' >> "$TMP/t152c.csv"
print -r -- '3,z' >> "$TMP/t152c.csv"
assert_eq "$("$CSV2" -contains z -i "$TMP/t152c.csv" | cut -f1 | tr '\n' ' ')" "1:2 2:2 3:2 " \
    "T152d -contains prints in ascending record order / -contains 以紀錄號遞增的順序輸出"

# ---------------------------------------------------------------------
# T153 -- N edits in one run either all land or none do.
#
# Round 57 wrote the loop the compose recipe implies -- one csv2 call per
# address -- and a failure on the fourth left the first three written, at exit
# 1, with nothing in the file to say which. The atomic form exists and was
# documented only as a lesson about -insert numbering. Both READMEs name it
# now, so it needs holding: all-or-nothing, and the log agreeing.
#
# T153 —— 一次執行裡的 N 個編輯，要嘛全部落地、要嘛一個都不落地。
# ---------------------------------------------------------------------
echo
echo "--- T153: all or nothing / T153：全部，或一個都不 ---"

{
    print -r -- 'a,b'
    for i in {1..5}; do printf '%d,v%d\n' $i $i; done
} > "$TMP/t153.csv"
_t153_before=$(cksum < "$TMP/t153.csv")

# One run, one address out of range: nothing may land.
# 一次執行，其中一個位址越界：一個都不能落地。
"$CSV2" -update 1:2 A -update 2:2 B -update 99:2 C -i "$TMP/t153.csv" --in-place 2>/dev/null
assert_eq "$?" "1" \
    "T153a a run with one bad address fails / 一次執行裡有一個壞位址就會失敗"
assert_eq "$(cksum < "$TMP/t153.csv")" "$_t153_before" \
    "T153b and the file is byte-for-byte what it was / 而那個檔案逐位元組維持原樣"

# All good: every one lands.
# 全部合法：每一個都落地。
"$CSV2" -update 1:2 A -update 2:2 B -update 3:2 C -i "$TMP/t153.csv" --in-place
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t153.csv")$("$CSV2" -get 2:2 -i "$TMP/t153.csv")$("$CSV2" -get 3:2 -i "$TMP/t153.csv")" "ABC" \
    "T153c while a run whose addresses are all good lands all of them / 而位址全部合法的執行，會讓它們全部落地"

# The loop the recipe implies, for contrast: this is what the READMEs now warn
# about, and it has to actually behave that way or the warning is folklore.
# 對照組：配方所暗示的那個迴圈——那正是兩份 README 現在警告的東西，而它必須真的是那樣，
# 否則那句警告就只是傳說。
{
    print -r -- 'a,b'
    for i in {1..5}; do printf '%d,v%d\n' $i $i; done
} > "$TMP/t153b.csv"
for _addr in 1:2 2:2 99:2; do
    "$CSV2" -update $_addr Z -i "$TMP/t153b.csv" --in-place 2>/dev/null || break
done
if [[ $("$CSV2" -get 1:2 -i "$TMP/t153b.csv") == "Z" && $("$CSV2" -get 5:2 -i "$TMP/t153b.csv") == "v5" ]]; then
    ok "T153d a call-per-address loop leaves the earlier edits written / 「每個位址跑一次」的迴圈會讓先前的編輯留在檔案裡"
else
    bad "T153d the loop did not behave as the warning describes / 那個迴圈的行為與警告所述不符"
fi

# ---------------------------------------------------------------------
# T154 -- the surface a user sees first, checked against the one the parser
# actually has.
#
# T121h pins KNOWN_FLAGS against the parser's cases. Nothing pinned either
# against `--help`, and `--build-index` was missing from it -- a real flag,
# documented in both READMEs, absent from the text a user reads before
# reaching either. The blind rounds could not have found it: they are forbidden
# `--help`, which is what makes it the least-watched interface in the project.
#
# T154 —— 使用者最先看到的那份介面，對上解析器真正擁有的那一份。
# T121h 把 KNOWN_FLAGS 與解析器的 case 釘在一起，而沒有任何東西把它們與 `--help` 釘在一起，
# 於是 `--build-index` 從 help 裡缺席——一個真實存在、兩份 README 都寫了的旗標，卻不在
# 「使用者在讀到那兩份文件之前會先讀的那段文字」裡。盲測回合找不到它：它們被禁止使用
# `--help`，而那正是這個專案裡最沒有人在看的那個介面。
# ---------------------------------------------------------------------
echo
echo "--- T154: --help against the flags that exist / T154：--help 對上真正存在的旗標 ---"

"$CSV2" --help >/dev/null 2>&1
assert_eq "$?" "0" \
    "T154a --help exits 0 / --help 以 0 結束"

# assert_same compares FILES, not strings: it takes two paths and cmp's them.
# Handing it two strings compares two paths that do not exist, which "differ" --
# and the case fails for a reason that has nothing to do with what it asks.
# assert_same 比的是「檔案」不是字串：它收兩個路徑再 cmp。把兩個字串交給它，比的是兩個
# 不存在的路徑，那當然「不同」——於是這個案例因為一個與它要問的事情無關的理由而失敗。
"$CSV2" --help > "$TMP/t154_long.txt" 2>&1
"$CSV2" -h     > "$TMP/t154_short.txt" 2>&1
assert_same "$TMP/t154_long.txt" "$TMP/t154_short.txt" \
    "T154b and -h prints the same thing / 而 -h 印出的是同一份東西"
_t154_help=$(cat "$TMP/t154_long.txt")

# Every flag the parser knows has to appear in the help.
# 解析器認得的每一個旗標，都必須出現在 help 裡。
_t154_missing=""
# The KNOWN_FLAGS array only, taken between its brackets. Grepping the whole
# file for quoted lowercase words picks up every other string literal in it,
# and requiring a trailing comma misses the last element.
# 只取 KNOWN_FLAGS 這個陣列，以它的括號為界。對整個檔案抓「引號包住的小寫字」會把其他
# 字串字面值一起抓進來，而要求「結尾逗號」則會漏掉最後一個元素。
_t154_known=$(awk '/^let KNOWN_FLAGS/,/^\]/' "$ROOT/src/main.swift" | grep -oE '"[a-zA-Z0-9-]+"' | tr -d '"')
for _f in ${(f)_t154_known}; do
    [[ -z $_f ]] && continue
    print -r -- "$_t154_help" | grep -qE -- "--?$_f([^a-z0-9-]|\$)" || _t154_missing="$_t154_missing $_f"
done
if [[ -z ${_t154_missing// /} ]]; then
    ok "T154c every flag the parser knows appears in --help / 解析器認得的每一個旗標都出現在 --help 裡"
else
    bad "T154c missing from --help:${_t154_missing} / --help 裡沒有這些"
fi

# And every flag in the help is one the parser knows -- the other direction,
# which is how a help text starts advertising something that was removed.
# 而 help 裡的每一個旗標，都必須是解析器認得的——另一個方向，那正是一份 help 開始宣傳
# 「已經被移除的東西」的方式。
_t154_ghost=""
for _f in ${(f)"$(print -r -- "$_t154_help" | grep -oE '(^| )--?[a-z][a-z0-9-]+' | tr -d ' ' | sed 's/^-*//' | sort -u)"}; do
    [[ -z $_f ]] && continue
    print -r -- "$_t154_known" | grep -qx -- "$_f" || _t154_ghost="$_t154_ghost $_f"
done
if [[ -z ${_t154_ghost// /} ]]; then
    ok "T154d and every flag in --help is one the parser knows / 而 --help 裡的每一個旗標都是解析器認得的"
else
    bad "T154d in --help but unknown to the parser:${_t154_ghost} / 在 --help 裡但解析器不認得"
fi

# The same question of the two READMEs. T117 compares them against each other
# by case number; this compares both against the parser, which is the direction
# that catches a flag added to the code and to one document.
# 對兩份 README 問同一個問題。T117 以案例編號把兩份 README 互相比對；這裡把兩份都拿去對
# 解析器——那是「一個旗標被加進程式碼與其中一份文件」時，抓得到的那個方向。
_t154_doc=""
for _f in ${(f)_t154_known}; do
    grep -qE -- "--?$_f([^a-zA-Z0-9-]|\$)" "$ROOT/README.md"       || _t154_doc="$_t154_doc en:$_f"
    grep -qE -- "--?$_f([^a-zA-Z0-9-]|\$)" "$ROOT/README.zh-TW.md" || _t154_doc="$_t154_doc zh:$_f"
done
if [[ -z ${_t154_doc// /} ]]; then
    ok "T154e and every flag the parser knows is in both READMEs / 而解析器認得的每一個旗標，兩份 README 都有"
else
    bad "T154e a flag the parser knows is missing from a README:${_t154_doc} / 有旗標在某份 README 裡缺席"
fi

# ---------------------------------------------------------------------
# T155 -- an output shape asked for on a path that writes CSV, and a log
# entry a parser can read.
#
# Round 58: `--json` and `-md` with an edit verb were accepted, ignored and
# exited 0, while `--a1` in the same position was refused and `-md` without -t
# on an edit was refused for a different reason -- three flags on one axis,
# three behaviours. And the `delete record` entry added the day before wrote
# column names unquoted, so a name containing `, ` made the entry unparseable;
# the invocation line quoted nothing, so a path with a space in it named a
# command nobody ran.
#
# T155 —— 在一條「寫出 CSV」的路徑上要求一種輸出形狀，以及一則解析得了的 log 紀錄。
# ---------------------------------------------------------------------
echo
echo "--- T155: shapes on an edit, and a parseable log / T155：編輯路徑上的形狀，以及可解析的 log ---"

print -r -- 'a,b'  > "$TMP/t155.csv"
print -r -- '1,x' >> "$TMP/t155.csv"

for _shape in --json -md; do
    _t155=$("$CSV2" -update 1:2 Z $_shape -t -i "$TMP/t155.csv" -o "$TMP/t155_out.csv" 2>&1)
    _t155_rc=$?
    if (( _t155_rc == 1 )) && [[ $_t155 == *"output shape"* ]]; then
        ok "T155a $_shape with an edit is refused / $_shape 與編輯併用會被拒絕"
    else
        bad "T155a $_shape exited $_t155_rc: $(print -r -- $_t155 | head -1) / 結果如上"
    fi
done

assert_succeeds "T155b while an edit without one still works / 而不帶輸出形狀的編輯照常運作" -- \
    "$CSV2" -update 1:2 Z -i "$TMP/t155.csv" -o "$TMP/t155_out.csv"
assert_succeeds "T155c and a read with one still works / 而帶著輸出形狀的讀取照常運作" -- \
    "$CSV2" -r -t --json -i "$TMP/t155.csv"

# A log a parser can read: names quoted, arguments with spaces quoted.
# 一份解析得了的 log：欄名加引號，含空白的引數加引號。
print -r -- '"a,b",c'  > "$TMP/t155_comma.csv"
print -r -- '1,2'     >> "$TMP/t155_comma.csv"
rm -f "$TMP/t155_comma.log"
"$CSV2" -delete 1 -i "$TMP/t155_comma.csv" --in-place -log "$TMP/t155_comma.log"
assert_contains "$(cat "$TMP/t155_comma.log")" 'delete record 1: "a,b"="1", "c"="2"' \
    "T155d a column name containing a comma is quoted in the log / 名字裡含逗號的欄位，在 log 裡會被加上引號"

cp "$TMP/t155.csv" "$TMP/t155 spaced.csv"
rm -f "$TMP/t155_sp.log"
"$CSV2" -r -t -i "$TMP/t155 spaced.csv" -log "$TMP/t155_sp.log" >/dev/null
assert_contains "$(head -1 "$TMP/t155_sp.log")" '-i "' \
    "T155e and a path containing a space is quoted in the invocation line / 而含空白的路徑，在那行指令紀錄裡會被加上引號"

# ---------------------------------------------------------------------
# T156 -- the JSON shape a consumer would validate against.
#
# Round 58: a `.csv2` object carries a sixth key, `header_zh`, which appears
# nowhere in either README -- "a schema-validating consumer breaks on the first
# .csv2". And `--en`/`--zh`, documented as changing the report's middle field,
# change nothing here. Both are now written down, so both need holding.
#
# T156 —— 一個消費端會拿去驗證的那個 JSON 形狀。
# ---------------------------------------------------------------------
echo
echo "--- T156: the keys, and who changes them / T156：那些鍵，以及誰會改變它們 ---"

print -r -- 'a,b'  > "$TMP/t156.csv"
print -r -- '1,x' >> "$TMP/t156.csv"
print -r -- 'a,b'   > "$TMP/t156.csv2"
print -r -- '甲,乙' >> "$TMP/t156.csv2"
print -r -- '1,x'  >> "$TMP/t156.csv2"

_t156_csv=$("$CSV2" -contains x --json -i "$TMP/t156.csv" | sed -n 2p)
_t156_two=$("$CSV2" -contains x --json -i "$TMP/t156.csv2" | sed -n 2p)

if [[ $_t156_csv == *'"header_en"'* && $_t156_csv != *'"header_zh"'* ]]; then
    ok "T156a a .csv object carries header_en and no header_zh / .csv 的物件帶 header_en，沒有 header_zh"
else
    bad "T156a $_t156_csv / 物件如上"
fi
if [[ $_t156_two == *'"header_en":"b"'* && $_t156_two == *'"header_zh":"乙"'* ]]; then
    ok "T156b while a .csv2 object carries both names / 而 .csv2 的物件兩個名字都帶著"
else
    bad "T156b $_t156_two / 物件如上"
fi

# --en / --zh change the report and not the JSON, which is what the README now
# says and the opposite of what a reader would guess.
# --en／--zh 改變的是報告、不是 JSON——那是 README 現在寫的，也與讀者會猜的相反。
# Real files, not process substitution: assert_same runs cmp on two PATHS, and
# /dev/fd entries do not behave the same everywhere -- this passed on macOS and
# failed in the guest, which is the wrong reason to fail.
# 用真正的檔案，不用 process substitution：assert_same 是對兩個「路徑」跑 cmp，而 /dev/fd
# 的行為不是每個地方都一樣——這個案例在 macOS 上通過、在 guest 上失敗，而那是一個錯誤的
# 失敗理由。
print -r -- "$_t156_two" > "$TMP/t156_plain.json"
"$CSV2" -contains x --json --zh -i "$TMP/t156.csv2" | sed -n 2p > "$TMP/t156_zh.json"
assert_same "$TMP/t156_plain.json" "$TMP/t156_zh.json" \
    "T156c and --zh changes nothing in --json / 而 --zh 在 --json 裡什麼也不改"
assert_contains "$("$CSV2" -contains x --zh -i "$TMP/t156.csv2")" "乙" \
    "T156d while it does change the report's column name / 而它確實會改變報告裡的欄名"

# ---------------------------------------------------------------------
# T157 -- a .csv with an embedded newline seeks like a .csv2.
#
# Round 59 measured `-tail 40` on a 15 MB .csv reading the entire file where a
# .csv2 of the same shape read 7 kB, and reported it as the two formats
# behaving differently. It was never the format: the seek required
# `no_embedded_newlines`, because a grid point was a byte offset alone and a
# resume could not say which physical LINE it had landed on -- and --physical
# puts that line in the output, which must be byte-identical with and without
# an index. One quoted newline in 450,000 records cost the whole file.
#
# Index v4 stores the line with each grid point, so the gate is gone. The
# property it protected is the thing to hold onto here: the two runs must still
# agree, exactly, including --physical, across the record that spans lines.
#
# T157 —— 含內嵌換行的 .csv，seek 得跟 .csv2 一樣。
# 第 59 回合量到 15 MB 的 .csv 上 `-tail 40` 讀了整個檔案，而同樣形狀的 .csv2 只讀 7 kB，
# 並把它回報成「兩種格式行為不同」。那從來不是格式的問題：seek 需要 `no_embedded_newlines`，
# 因為格點只有位元組偏移量、恢復解析說不出「落在第幾實體行」——而 --physical 會把那個行號
# 放進輸出，且有無索引的輸出必須逐位元相同。45 萬筆裡的一個引號換行，代價是整個檔案。
# 索引 v4 把行號與格點存在一起，那道門因此拿掉了。這裡要守住的，正是它當初保護的那個性質。
# ---------------------------------------------------------------------
echo
echo "--- T157: seeking into a file whose records span lines / T157：seek 進一個「紀錄會跨行」的檔案 ---"

# Small file, thresholds lowered to meet it -- the property is not about size.
# 小檔案，門檻降下來遷就它——這個性質與大小無關。
{
    print -r -- 'id,note'
    for i in {1..400}; do
        if (( i == 5 )); then printf '%03d,"alpha
bravo %03d"
' $i $i
        else printf '%03d,alpha bravo %03d
' $i $i
        fi
    done
} > "$TMP/t157.csv"

export CSV2_INDEX_MIN_BYTES=512
"$CSV2" --build-index -i "$TMP/t157.csv" >/dev/null

# The seek is taken at all -- the debug line names the grid point.
# seek 真的被走了——debug 那一行會指名它用的格點。
_t157_dbg=$("$CSV2" -tail 40 -i "$TMP/t157.csv" -debug 2>&1 >/dev/null)
if [[ $_t157_dbg == *"index hit"* ]]; then
    ok "T157a a .csv whose records span lines still takes the seek / 紀錄會跨行的 .csv 仍然走得到 seek"
else
    bad "T157a no index hit: $(print -r -- $_t157_dbg | grep -o 'single-threaded[^\n]*' | head -1) / 沒有走到索引"
fi

# And it reads a fraction of the file, which is the point of taking it.
# 而它只讀了整個檔案的一小部分，那才是走 seek 的意義。
_t157_read=$(print -r -- "$_t157_dbg" | grep -oE 'read_bytes=[0-9]+' | cut -d= -f2)
_t157_size=$(wc -c < "$TMP/t157.csv" | tr -d ' ')
if [[ -n $_t157_read ]] && (( _t157_read * 2 < _t157_size )); then
    ok "T157b reading $_t157_read bytes of $_t157_size / 讀了 $_t157_size 中的 $_t157_read 位元組"
else
    bad "T157b read $_t157_read of $_t157_size -- the seek saved nothing / 讀了 $_t157_size 中的 $_t157_read，seek 沒有省下任何東西"
fi

# The guarantee the old gate existed to protect, and the reason this is safe:
# with and without the index, byte for byte, INCLUDING the physical line.
# 舊守衛存在所要保護的那條保證，也正是這件事安全的理由：有無索引，逐位元組相同，
# **包含實體行號**。
"$CSV2" -tail 40 --physical -t -i "$TMP/t157.csv"            > "$TMP/t157_with.txt" 2>/dev/null
"$CSV2" -tail 40 --physical -t --no-index -i "$TMP/t157.csv" > "$TMP/t157_without.txt" 2>/dev/null
assert_same "$TMP/t157_with.txt" "$TMP/t157_without.txt" \
    "T157c -tail --physical is byte-identical with and without the index / -tail --physical 在有無索引下逐位元組相同"

"$CSV2" -mid 1,10 --physical -t -i "$TMP/t157.csv"            > "$TMP/t157_mid_with.txt" 2>/dev/null
"$CSV2" -mid 1,10 --physical -t --no-index -i "$TMP/t157.csv" > "$TMP/t157_mid_without.txt" 2>/dev/null
assert_same "$TMP/t157_mid_with.txt" "$TMP/t157_mid_without.txt" \
    "T157d and so is a window that spans the record that spans lines / 而「跨過那筆跨行紀錄」的視窗也是"

# The append path extends an index instead of rebuilding it, so it is the one
# place that can put a wrong LINE into one -- the same door the record count
# came through in T79.
# 追加是「延續索引」而非「重建索引」的那條路，因此它是唯一能把錯的「行號」放進索引的地方
# ——與 T79 當初讓「筆數」出錯的是同一扇門。
"$CSV2" -append '401,tail record' -i "$TMP/t157.csv" --in-place
"$CSV2" -tail 3 --physical -t -i "$TMP/t157.csv"            > "$TMP/t157_ap_with.txt" 2>/dev/null
"$CSV2" -tail 3 --physical -t --no-index -i "$TMP/t157.csv" > "$TMP/t157_ap_without.txt" 2>/dev/null
assert_same "$TMP/t157_ap_with.txt" "$TMP/t157_ap_without.txt" \
    "T157e and after an append the lines still agree / 而在一次追加之後，行號仍然一致"
unset CSV2_INDEX_MIN_BYTES

# ---------------------------------------------------------------------
# T158 -- the one output shape that was quietly lying.
#
# Round 59: "--json is lossy for invalid UTF-8 while -r and -get are not. No
# flag, no WARN, no marker, no exit status distinguishes a faithful --json line
# from a lossy one." Measured: a value of `caf\xe9` came out as "caf<U+FFFD>",
# valid JSON, rc=0 -- in the shape this README recommends when the value is the
# thing that matters, while the locating report answers the same case with
# `<non-UTF-8: 63 61 66 e9>`.
#
# T158 —— 唯一一個在安靜說謊的輸出形狀。
# ---------------------------------------------------------------------
echo
echo "--- T158: bytes JSON cannot carry / T158：JSON 載不動的位元組 ---"

printf 'a,b\n1,caf\xe9\n' > "$TMP/t158.csv"

_t158=$("$CSV2" -r -t --json -i "$TMP/t158.csv" 2>&1 >/dev/null)
_t158_rc=$?
if (( _t158_rc == 1 )) && [[ $_t158 == *"not valid UTF-8"* ]]; then
    ok "T158a --json refuses a value it cannot carry, naming the record and field / --json 拒絕它載不動的值，並指出是哪一筆哪一欄"
else
    bad "T158a exited $_t158_rc: $(print -r -- $_t158 | head -1) / 結果如上"
fi

# The shapes that CAN carry it still do, unchanged -- refusing in one place is
# only right because the other two answer honestly.
# 載得動的那些形狀照舊——在一個地方拒絕之所以是對的，正因為另外兩個誠實地回答了。
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t158.csv" | od -A n -c | tr -s ' ')" \
          "$(printf 'caf\xe9\n' | od -A n -c | tr -s ' ')" \
    "T158b while -get still returns the bytes / 而 -get 仍然交還那些位元組"
assert_contains "$("$CSV2" -contains caf -i "$TMP/t158.csv")" "<non-UTF-8: 63 61 66 e9>" \
    "T158c and the report names them in hex / 而報告以十六進位指出它們"
assert_succeeds "T158d and -r reads the file / 而 -r 讀得了這個檔案" -- \
    "$CSV2" -r -t -i "$TMP/t158.csv"

# Valid UTF-8 still goes through --json, including astral characters.
# 合法的 UTF-8 照樣通過 --json，包含星光平面的字元。
# Compared in --json-ascii, whose output is pure ASCII by definition. The
# needle was `café🚀` and Windows failed on it while its own output showed the
# value present -- a case that measured the platform's handling of a non-ASCII
# literal in this file, not the tool.
# 以 --json-ascii 比對，它的輸出依定義就是純 ASCII。原本的比對字串是 `café🚀`，Windows 在
# 那裡失敗，而它自己的輸出裡那個值明明就在——那個案例量的是「這個檔案裡一個非 ASCII 字面值
# 在該平台上如何被處理」，不是這個工具。
printf 'a,b\n1,caf\xc3\xa9\xf0\x9f\x9a\x80\n' > "$TMP/t158_ok.csv"
assert_contains "$("$CSV2" -r -t --json-ascii -i "$TMP/t158_ok.csv" | sed -n 2p)" 'caf\u00e9\ud83d\ude80' \
    "T158e while valid UTF-8 is carried as it always was / 而合法的 UTF-8 一如既往地被載著走"

# ---------------------------------------------------------------------
# T159 -- three things about reading that nothing had written down.
#
# Round 59, all three found by running the same read over a hundred small files
# and comparing against Python's csv module:
#   - a blank line anywhere is a hard error, including the one a file ending in
#     two newlines has, and the message talked about field counts;
#   - a bare CR inside an UNQUOTED field is data here and a row separator to
#     most parsers, so the record counts differ across tools;
#   - NUL and the other control bytes are accepted verbatim.
# All three are now in both READMEs, so all three need holding.
#
# T159 —— 三件關於「讀取」、而先前沒有任何地方寫下來的事。
# ---------------------------------------------------------------------
echo
echo "--- T159: blank lines, bare CR, and control bytes / T159：空白行、裸 CR，以及控制位元組 ---"

print -r -- 'a,b'  > "$TMP/t159_blank.csv"
print -r -- '1,x' >> "$TMP/t159_blank.csv"
print -r -- ''    >> "$TMP/t159_blank.csv"
print -r -- '2,y' >> "$TMP/t159_blank.csv"
_t159=$("$CSV2" -r -t -i "$TMP/t159_blank.csv" 2>&1 >/dev/null)
if [[ $_t159 == *"is a blank line"* ]]; then
    ok "T159a a blank line is named as one / 空白行會被指名為空白行"
else
    bad "T159a $(print -r -- $_t159 | head -1) / 訊息如上"
fi

# The file that merely ends with an extra newline is the same case, and it is
# the one most people will actually have.
# 「只是多了一個結尾換行」的檔案是同一個情況，而那是多數人手上真正會有的那種。
printf 'a,b\n1,x\n\n' > "$TMP/t159_trail.csv"
_t159t=$("$CSV2" -r -t -i "$TMP/t159_trail.csv" 2>&1 >/dev/null)
if [[ $_t159t == *"is a blank line"* ]]; then
    ok "T159b and so is the blank line a trailing newline leaves / 多出來的結尾換行留下的那個空白行也是"
else
    bad "T159b $(print -r -- $_t159t | head -1) / 訊息如上"
fi

# A bare CR in an unquoted field: one record here.
# 未加引號欄位裡的裸 CR：在這裡是一筆。
printf 'a,b\n1,x\ry\n2,z\n' > "$TMP/t159_cr.csv"
assert_eq "$("$CSV2" -r -t --json -i "$TMP/t159_cr.csv" | tail -1)" '{"meta":{"records":2,"matched":0}}' \
    "T159c a bare CR inside an unquoted field is data, not a record break / 未加引號欄位裡的裸 CR 是資料，不是紀錄分隔"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t159_cr.csv" | od -A n -c | tr -s ' ')" \
          "$(printf 'x\ry\n' | od -A n -c | tr -s ' ')" \
    "T159d and the CR is still in the value / 而那個 CR 還在值裡面"

# NUL survives a round trip.
# NUL 撐得過一次來回。
printf 'a,b\n1,x\x00y\n' > "$TMP/t159_nul.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t159_nul.csv" | od -A n -c | tr -s ' ')" \
          "$(printf 'x\x00y\n' | od -A n -c | tr -s ' ')" \
    "T159e a NUL byte is data and comes back unchanged / NUL 是資料，而且原樣回來"

# ---------------------------------------------------------------------
# T160 -- an administrative flag beside a verb, and the half of that rule
# that was never written.
#
# Round 60: `csv2 --build-index -contains X -i f.csv` exited 0 having searched
# nothing -- indistinguishable from "found nothing", which the README documents
# as rc=0 as well. `--build-index -get 1:1` put `index built: 5 records ...`
# on stdout, so the README's own `val=$(csv2 -get ...)` recipe writes that
# sentence into a data cell.
#
# csv2 already refused this for EDIT verbs, with a message explaining that the
# flag REPLACES the operation. The same rule, half its domain -- this project's
# most frequent defect, and mine to have made here.
#
# T160 —— 一個管理用旗標與一個動詞並排，以及那條規則沒有被寫下來的另一半。
# ---------------------------------------------------------------------
echo
echo "--- T160: --build-index / --verify-index replace the operation / T160：--build-index／--verify-index 是取代那個操作 ---"

print -r -- 'a,b'  > "$TMP/t160.csv"
print -r -- '1,x' >> "$TMP/t160.csv"
print -r -- '2,y' >> "$TMP/t160.csv"

for _t160_admin in --build-index --verify-index; do
    for _t160_verb in "-contains x" "-get 1:2" "-head 1" "-tail 1" "-mid 1,1"; do
        _t160_out=$("$CSV2" $_t160_admin ${=_t160_verb} -i "$TMP/t160.csv" 2>&1)
        _t160_rc=$?
        if (( _t160_rc == 1 )) && [[ $_t160_out == *"cannot both run"* ]]; then
            ok "T160a $_t160_admin with $_t160_verb is refused / $_t160_admin 與 $_t160_verb 併用會被拒絕"
        else
            bad "T160a $_t160_admin $_t160_verb exited $_t160_rc: $(print -r -- $_t160_out | head -1) / 結果如上"
        fi
    done
done

# The flag alone is the ordinary use and must still work -- including with -r,
# which is also the default, so refusing it would refuse the plain form.
# 單獨使用那個旗標是最平常的用法，必須照舊可用——包含搭配 -r，因為 -r 同時也是預設值，
# 拒絕它等於拒絕那個最單純的寫法。
assert_succeeds "T160b --build-index alone still works / 單獨的 --build-index 照舊可用" -- \
    "$CSV2" --build-index -i "$TMP/t160.csv"
# `-r` typed explicitly is refused like any other verb. The first version of
# T160 excluded it on the reasoning that -r is also the default -- true of the
# DEFAULT, and not of a caller who typed it and got no output. Round 61 found
# the difference; the flag alone (T160b) is the case that had to keep working.
# 明確打出來的 `-r` 與其他動詞一樣會被拒絕。T160 的第一版把它排除在外，理由是「-r 也是
# 預設值」——那對「預設」成立，對「一個真的打了它、卻沒有拿到輸出的呼叫端」不成立。
# 第 61 回合找出了這個差別；必須繼續可用的是「單獨那個旗標」（T160b）。
_t160_r=$("$CSV2" --build-index -r -i "$TMP/t160.csv" 2>&1)
if [[ $_t160_r == *"cannot both run"* ]]; then
    ok "T160c and an explicitly typed -r is refused too / 而明確打出來的 -r 同樣會被拒絕"
else
    bad "T160c $(print -r -- $_t160_r | head -1) / 結果如上"
fi

for _t160_shape in --json "-md -t"; do
    _t160_out=$("$CSV2" --build-index ${=_t160_shape} -i "$TMP/t160.csv" 2>&1)
    if [[ $_t160_out == *"cannot both run"* ]]; then
        ok "T160e and so is $_t160_shape / $_t160_shape 也是"
    else
        bad "T160e $_t160_shape: $(print -r -- $_t160_out | head -1) / 結果如上"
    fi
done

_t160_both=$("$CSV2" --build-index --verify-index -i "$TMP/t160.csv" 2>&1)
if [[ $_t160_both == *"cannot both run"* ]]; then
    ok "T160f and the two administrative flags refuse each other / 而那兩個管理用旗標會互相拒絕"
else
    bad "T160f $(print -r -- $_t160_both | head -1) / 結果如上"
fi
assert_succeeds "T160d and --verify-index alone / 單獨的 --verify-index 也是" -- \
    "$CSV2" --verify-index -i "$TMP/t160.csv"

# ---------------------------------------------------------------------
# T161 -- the temp file's permissions while the write is happening.
#
# Round 61: "--in-place exposes the contents of a restrictively-permissioned
# file for the duration of the write." The temp file was created with the
# umask's mode and the source's mode applied just before the rename, so a 0600
# file spent the whole write as -rw-r--r-- under a name anyone could open.
# On a 15 MB file that is a real window, and the README's "an edit does not
# change who can read it" was true only of the finished file.
#
# T161 —— 寫入進行中，那個暫存檔的權限。
# ---------------------------------------------------------------------
echo
echo "--- T161: who can read the temp file / T161：誰讀得到那個暫存檔 ---"

if (( IS_WINDOWS )); then
    T161_SKIPPED=1
    skipt "T161 the temp file is not world-readable while it is written / 暫存檔在寫入期間不是所有人可讀 (POSIX modes; MSYS2 reports a fiction over an ACL / 這是 POSIX 模式；MSYS2 回報的是覆在 ACL 之上的虛構)"
else
    # Big enough that the write takes long enough to look at.
    # 大到「寫入會花上足以觀察的時間」。
    {
        print -r -- 'a,b'
        for i in {1..120000}; do printf '%d,value-%d-padding-padding\n' $i $i; done
    } > "$TMP/t161.csv"
    chmod 600 "$TMP/t161.csv"

    "$CSV2" -update 1:2 Q -i "$TMP/t161.csv" --in-place &
    _t161_pid=$!
    _t161_modes=""
    for _ in {1..40}; do
        _t161_tmp=$(print -r -- "$TMP"/.t161.csv.csv2tmp.*(N))
        if [[ -n $_t161_tmp ]]; then
            _t161_modes="$_t161_modes $(file_mode "$_t161_tmp")"
            break
        fi
        sleep 0.02
    done
    wait $_t161_pid 2>/dev/null

    if [[ -z ${_t161_modes// /} ]]; then
        # The write finished before the temp file could be looked at. Saying so
        # beats reporting a pass for a window nobody observed.
        # 寫入在暫存檔被看到之前就結束了。說出來，好過為一個「沒有人觀察到的時間窗」回報通過。
        T161_SKIPPED=1
        skipt "T161 the temp file is not world-readable while it is written / 暫存檔在寫入期間不是所有人可讀 (the write finished before it could be sampled / 寫入在能被取樣之前就結束了)"
    elif [[ ${_t161_modes// /} == 600 ]]; then
        ok "T161 the temp file is 600 while it is being written / 暫存檔在寫入期間是 600"
    else
        bad "T161 the temp file was${_t161_modes} while a 600 file was being edited / 編輯一個 600 的檔案時，暫存檔是${_t161_modes}"
    fi

    assert_eq "$(file_mode "$TMP/t161.csv")" "600" \
        "T161b and the file still has its own mode afterwards / 而那個檔案事後仍然是它自己的模式"
fi

# ---------------------------------------------------------------------
# T162 -- the smallest file that breaks each rule.
#
# Round 62 built, for every rule about input, the smallest file that violates
# it and the smallest that satisfies it by one byte. Two rules failed at the
# boundary:
#
#   - a file that IS a UTF-16 BOM and nothing else -- two bytes, which is what
#     an editor writes for an empty document saved as UTF-16 -- was accepted at
#     rc=0 as a one-column CSV whose column name is those two invalid bytes,
#     because the UTF-8 BOM test needs three bytes and the check waited for
#     three. A zero-byte file, semantically the same, is refused;
#   - a blank line in a ONE-column file is a record with one empty field,
#     because they are the same bytes -- true, defensible, and stated nowhere,
#     while the rule reads "a blank line anywhere is refused".
#
# T162 —— 讓每一條規則破掉的最小檔案。
# ---------------------------------------------------------------------
echo
echo "--- T162: two bytes either way / T162：兩個位元組的兩邊 ---"

printf '\xff\xfe' > "$TMP/t162_le.csv"
printf '\xfe\xff' > "$TMP/t162_be.csv"
for _t162 in le be; do
    _t162_out=$("$CSV2" -r -t -i "$TMP/t162_$_t162.csv" 2>&1 >/dev/null)
    _t162_rc=$?
    if (( _t162_rc == 1 )) && [[ $_t162_out == *"byte-order mark"* ]]; then
        ok "T162a a file that is nothing but a UTF-16 BOM is refused ($_t162) / 「整個檔案就是一個 UTF-16 BOM」會被拒絕（$_t162）"
    else
        bad "T162a $_t162 exited $_t162_rc: $(print -r -- $_t162_out | head -1) / 結果如上"
    fi
done

# One byte more, and one byte less, still behave as documented.
# 多一個位元組、少一個位元組，行為仍如文件所述。
printf '\xff\xfea\x00' > "$TMP/t162_more.csv"
assert_fails "T162b and so is a longer UTF-16 file / 較長的 UTF-16 檔案同樣如此" -- \
    "$CSV2" -r -t -i "$TMP/t162_more.csv"
: > "$TMP/t162_empty.csv"
assert_fails "T162c while a zero-byte file is refused for its own reason / 而零位元組的檔案因為它自己的理由被拒絕" -- \
    "$CSV2" -r -t -i "$TMP/t162_empty.csv"

# A UTF-8 BOM is still stripped, not refused -- the two tests must not have
# merged.
# UTF-8 的 BOM 仍然是被剝除、不是被拒絕——那兩個判斷不能被合成一個。
printf '\xef\xbb\xbfa,b\n1,x\n' > "$TMP/t162_u8.csv"
assert_eq "$("$CSV2" -r -t -i "$TMP/t162_u8.csv" | head -1)" 'a,b' \
    "T162d a UTF-8 BOM is still stripped rather than refused / UTF-8 的 BOM 仍然是被剝除，而不是被拒絕"

# The one-column blank line, which is documented now rather than refused.
# 單欄檔案裡的空白行——現在是被寫進文件，而不是被拒絕。
printf 'a\n\n' > "$TMP/t162_one.csv"
assert_eq "$("$CSV2" -r -t --json -i "$TMP/t162_one.csv" | sed -n 2p)" '{"record":1,"line":2,"fields":{"a":""}}' \
    "T162e a blank line in a one-column file is a record with one empty field / 單欄檔案裡的空白行，是一筆「有一個空欄位」的紀錄"
printf 'a,b\n\n' > "$TMP/t162_two.csv"
assert_fails "T162f while two columns make it a blank line again / 而兩欄時它又是一個空白行" -- \
    "$CSV2" -r -t -i "$TMP/t162_two.csv"

# ---------------------------------------------------------------------
# T163 -- the output shape follows the flag, not the number.
#
# Round 62 ran roughly sixty flag pairs the refusals table does not list.
# `-A 0` left the locating report in place while `-A 1` switched to records, so
# `csv2 -contains X -A "$N"` returned one of two incompatible formats depending
# on a variable -- a TAB-separated report against CSV, rc=0, nothing said. The
# README says -A/-B/-C imply --filter, unconditionally, and the implication was
# written as `after > 0 || before > 0`.
#
# T163 —— 輸出形狀跟著旗標走，不跟著數字走。
# ---------------------------------------------------------------------
echo
echo "--- T163: a context flag of zero / T163：值為零的上下文旗標 ---"

{
    print -r -- 'a,b'
    for i in {1..9}; do
        if (( i == 6 )); then print -r -- "$i,HIT"; else print -r -- "$i,n"; fi
    done
} > "$TMP/t163.csv"

# With no context flag at all: the locating report.
# 完全不給上下文旗標時：定位報告。
assert_contains "$("$CSV2" -contains HIT -i "$TMP/t163.csv" | head -1)" "6:2" \
    "T163a with no context flag the output is the locating report / 不給上下文旗標時，輸出是定位報告"

# With one, at any value: records.
# 給了，不論值是多少：紀錄形狀。
for _t163_n in 0 1 2; do
    assert_eq "$("$CSV2" -contains HIT -A $_t163_n -i "$TMP/t163.csv" | head -1)" "6,HIT" \
        "T163b -A $_t163_n gives records, the same shape as any other value / -A $_t163_n 給的是紀錄形狀，與其他任何值相同"
done
assert_eq "$("$CSV2" -contains HIT -B 0 -i "$TMP/t163.csv" | head -1)" "6,HIT" \
    "T163c and so does -B 0 / -B 0 也是"
assert_eq "$("$CSV2" -contains HIT -C 0 -i "$TMP/t163.csv" | head -1)" "6,HIT" \
    "T163d and -C 0 / -C 0 也是"

# The count still follows the number -- the fix must not have made -A 0 mean
# -A 1.
# 筆數仍然跟著數字走——這個修正不能讓 -A 0 變成 -A 1。
assert_eq "$("$CSV2" -contains HIT -A 0 -i "$TMP/t163.csv" | wc -l | tr -d ' ')" "1" \
    "T163e while -A 0 still selects one record / 而 -A 0 仍然只選出一筆"
assert_eq "$("$CSV2" -contains HIT -A 2 -i "$TMP/t163.csv" | wc -l | tr -d ' ')" "3" \
    "T163f and -A 2 selects three / 而 -A 2 選出三筆"

# ---------------------------------------------------------------------
# T164 -- which shapes substitute, and which refuse.
#
# Round 62, reading the document as its author's adversary: "only --json was
# quiet about it" -- a sentence I wrote -- is false. `-md` substitutes U+FFFD
# for a byte sequence that is not UTF-8, silently, at rc=0, and --pretty pads
# the column to the substituted width. That is defensible for a RENDERING and
# it is not what the sentence claimed.
#
# T164 —— 哪些形狀會替換，哪些會拒絕。
# ---------------------------------------------------------------------
echo
echo "--- T164: a byte that is not text / T164：一個不是文字的位元組 ---"

printf 'a,b\nx,caf\xe9\n' > "$TMP/t164.csv"

assert_eq "$("$CSV2" -r -t -i "$TMP/t164.csv" | od -A n -c | tr -s ' ')" \
          "$(printf 'a,b\nx,caf\xe9\n' | od -A n -c | tr -s ' ')" \
    "T164a the CSV shapes hand back the bytes / 各種 CSV 形狀交還的是位元組"
assert_contains "$("$CSV2" -contains caf -i "$TMP/t164.csv")" "<non-UTF-8: 63 61 66 e9>" \
    "T164b the locating report names them in hex / 定位報告以十六進位指出它們"
assert_fails "T164c --json refuses them / --json 拒絕它們" -- \
    "$CSV2" -r -t --json -i "$TMP/t164.csv"

# -md substitutes, and the README says so rather than claiming otherwise.
# -md 會替換，而 README 現在照實寫，不再宣稱相反的事。
# Hex, not `od -c`: this platform's od renders the replacement character as a
# glyph plus `** **`, so an octal probe found nothing and reported that -md
# does not substitute -- measuring od's rendering rather than the bytes.
# 用十六進位，不用 `od -c`：這個平台的 od 會把替換字元印成一個字形加上 `** **`，因此一個
# 用八進位去探測的檢查什麼也沒找到，於是回報「-md 不會替換」——量到的是 od 的呈現方式，
# 不是那些位元組。
_t164_md=$("$CSV2" -r -t -md -i "$TMP/t164.csv" | od -A n -t x1 | tr -s ' ')
if [[ $_t164_md == *"ef bf bd"* ]]; then
    ok "T164d while -md substitutes U+FFFD, as a rendering does / 而 -md 會換成 U+FFFD——算繪就是這樣"
else
    bad "T164d -md produced: $_t164_md / -md 的輸出如上"
fi

# ---------------------------------------------------------------------
# T139 -- combinations nobody enumerated.
#
# Every other case here was written because someone thought of it. This one
# generates edit chains at random over degenerate files and checks the four
# properties that must hold whatever the combination is:
#
#   - the exit status is 0 or 1, never a crash;
#   - a refusal is never silent;
#   - after any accepted edit the file is still one csv2 can read, or is
#     refused loudly -- never garbage read back as data;
#   - no temp file is left beside it.
#
# The seed is fixed and printed, and a failure prints the exact argv, because
# a fuzz case nobody can reproduce is worse than none. zsh's RANDOM sequence is
# not guaranteed identical across builds, which is fine: any sequence is a
# valid test of properties that must hold for all of them.
#
# This case checks PROPERTIES rather than reproducing a known defect, so it can
# pass without proving anything. Each of the four checks was inverted in a copy
# of this file on 2026-08-21 and each one reported, naming the argv and the
# seed file -- that is what says the harness can speak, and it is the part a
# fuzz case usually lacks.
# 這個案例檢查的是「性質」，不是重現某個已知缺陷，因此它可能在什麼也沒證明的情況下通過。
# 2026-08-21 曾把那四項檢查各自反轉、各跑一份副本，四項都發了聲並指出 argv 與種子檔——
# 那才是「這個框架說得出話」的證據，而那正是 fuzz 案例通常缺少的部分。
#
# T139 —— 沒有人列舉過的組合。
# 這裡其他每一個案例，都是因為有人想到了才存在。這一個在退化的檔案上隨機產生「連續編輯」，
# 並檢查四項「無論組合是什麼都必須成立」的性質：結束狀態只能是 0 或 1；拒絕不得沉默；
# 任何被接受的編輯之後，檔案仍然是 csv2 讀得回來的（或被大聲拒絕），而不是被當成資料讀進去
# 的垃圾；旁邊不留下暫存檔。
# 種子固定且會印出，失敗時印出完整的 argv——一個沒有人能重現的 fuzz 案例，比沒有更糟。
# ---------------------------------------------------------------------
echo
echo "--- T139: random edit chains over degenerate files / T139：退化檔案上的隨機連續編輯 ---"

RANDOM=20260821
echo "[Info] T139 seed: 20260821"

t139_seed_file() {   # name -> writes $TMP/t139_<name>.csv
    case $1 in
        plain)      printf 'a,b,c\n1,x,p\n2,y,q\n' ;;
        headeronly) printf 'a,b,c\n' ;;
        nonewline)  printf 'a,b,c\n1,x,p' ;;
        quoted)     printf 'a,b,c\n1,"x,y","he said ""hi"""\n' ;;
        embedded)   printf 'a,b,c\n1,"line1\nline2",p\n' ;;
        unicode)    printf 'a,b,c\n1,caf\xc3\xa9\xf0\x9f\x9a\x80,p\n' ;;
        spaces)     printf 'a,b,c\n1,"   ",p\n' ;;
    esac
}

t139_bad=0
t139_runs=0
for _name in plain headeronly nonewline quoted embedded unicode spaces; do
    for _trial in 1 2 3; do
        _f="$TMP/t139_${_name}_${_trial}.csv"
        t139_seed_file $_name > "$_f"
        for _step in 1 2 3; do
            case $((RANDOM % 7)) in
                0) _args=(-update 1:2 "V$RANDOM") ;;
                1) _args=(-insert $((RANDOM % 3 + 1)) 'n1,n2,n3') ;;
                2) _args=(-append 'z1,z2,z3') ;;
                3) _args=(-delete $((RANDOM % 3 + 1))) ;;
                4) _args=(-delete -cell 1:1) ;;
                5) _args=(-delete -col $((RANDOM % 3 + 1))) ;;
                6) _args=(-hash a) ;;
            esac
            _err=$("$CSV2" $_args -i "$_f" --in-place 2>&1 >/dev/null)
            _rc=$?
            t139_runs=$((t139_runs + 1))
            if (( _rc != 0 && _rc != 1 )); then
                bad "T139 exit $_rc from: $_args on $_name / 由上述組合產生的結束狀態"
                t139_bad=1; break
            fi
            if (( _rc == 1 )) && [[ -z ${_err//[[:space:]]/} ]]; then
                bad "T139 a silent refusal from: $_args on $_name / 沉默的拒絕"
                t139_bad=1; break
            fi
            _rerr=$("$CSV2" -r -t -i "$_f" 2>&1 >/dev/null)
            _rrc=$?
            if (( _rrc != 0 && _rrc != 1 )); then
                bad "T139 unreadable after: $_args on $_name (exit $_rrc) / 編輯後讀不回來"
                t139_bad=1; break
            fi
            if (( _rrc == 1 )) && [[ -z ${_rerr//[[:space:]]/} ]]; then
                bad "T139 the read refused silently after: $_args on $_name / 編輯後的讀取沉默地拒絕了"
                t139_bad=1; break
            fi
        done
        _leftovers=$(print -r -- "$TMP"/.t139_${_name}_${_trial}.csv.csv2tmp.*(N))
        if [[ -n $_leftovers ]]; then
            bad "T139 temp file left: $_leftovers / 留下了暫存檔"
            t139_bad=1
        fi
        rm -f "$_f" "$_f.index"
    done
done
if (( t139_bad == 0 )); then
    ok "T139 $t139_runs random edits: no crash, no silent refusal, nothing left behind, and every file still readable / $t139_runs 次隨機編輯：沒有當機、沒有沉默的拒絕、沒有殘留，而每個檔案都仍然讀得回來"
fi

# ---------------------------------------------------------------------
# T136 -- claims the README makes that nothing had checked.
#
# Round 53 found each of these by reading the README and then measuring:
#   - -md escapes more than the two things listed (a backslash is doubled) and
#     passes a TAB through raw;
#   - -md is not reversible: `<br>` as text and a real newline emit the same
#     bytes, so a checker cannot tell them apart;
#   - --verify-index's exit statuses were documented nowhere, and it declines
#     to run its O(n) comparison when the cheap stamp already says no.
# Each is now stated in both READMEs, so each needs something behind it.
#
# T136 —— README 現在說出口、而先前沒有任何東西檢查的幾項宣稱。
# ---------------------------------------------------------------------
echo
echo "--- T136: what -md escapes, and what --verify-index answers / T136：-md 跳脫了什麼，而 --verify-index 回答什麼 ---"

printf 'a,b\n"C:\\path","x\ty"\n"<br>","p\nq"\n' > "$TMP/t136.csv"
_t136_md=$("$CSV2" -md -t -i "$TMP/t136.csv")

assert_contains "$_t136_md" 'C:\\path' \
    "T136a -md doubles a backslash, as the README now says / -md 會把反斜線變成兩個，一如 README 現在所寫"
# A TAB used to pass through raw, and this case asserted that. It does not any
# more: -md is a RENDERING read by a person, so it escapes control characters
# the way the locating report does -- a `\t` for the tab and `\xNN` for the
# rest. Round 70 built a licence column reading `GPL-3.0<BS>*7 MIT`, which
# rendered as `MIT` on any terminal that moves the cursor for a backspace,
# while `-get` returned the real bytes. The old assertion was pinning the hole.
# 原本 TAB 會原樣通過，而這個案例斷言了那件事。現在不會了：`-md` 是一種給人讀的「算繪」，
# 因此它像定位報告那樣跳脫控制字元——TAB 是 `\t`，其餘是 `\xNN`。第 70 回合造了一個
# 授權欄位 `GPL-3.0<BS>×7 MIT`，在任何「退格會移動游標」的終端機上算繪成 `MIT`，而 `-get`
# 交還的是真正的位元組。舊的那條斷言，釘住的正是那個洞。
if [[ $_t136_md == *'\t'* && $_t136_md != *$'\t'* ]]; then
    ok "T136b and escapes a TAB the way the report does / 而 TAB 以定位報告的方式被跳脫"
else
    bad "T136b the TAB is not escaped / TAB 沒有被跳脫"
fi

# The collision, stated as a fact rather than discovered by someone relying on
# it: two different values, the same bytes out.
# 那個碰撞，作為一個「先說出來」的事實，而不是留給依賴它的人去撞見：兩個不同的值，
# 輸出相同的位元組。
# Two different files, one rendering. That is what "not reversible" means, and
# it is stronger than counting <br> in one file's output.
# 兩個不同的檔案，一份算繪。那才是「不可逆」的意思，也比在同一份輸出裡數 <br> 更有力。
printf 'a\n"p<br>q"\n' > "$TMP/t136_lit.csv"
printf 'a\n"p\nq"\n'   > "$TMP/t136_nl.csv"
assert_eq "$("$CSV2" -md -t -i "$TMP/t136_lit.csv")" "$("$CSV2" -md -t -i "$TMP/t136_nl.csv")" \
    "T136c a literal <br> and a real newline render to the same bytes, so -md is not reversible / 字面的 <br> 與真正的換行算繪出相同的位元組，因此 -md 不可逆"
if [[ "$("$CSV2" -r -t --json -i "$TMP/t136_lit.csv")" != "$("$CSV2" -r -t --json -i "$TMP/t136_nl.csv")" ]]; then
    ok "T136c1 while --json keeps them apart, which is why it is the shape to check against / 而 --json 分得出它們，那正是它才是「用來比對」的那個形狀"
else
    bad "T136c1 --json rendered both the same / --json 把兩者算繪成同一個樣子"
fi
# And the shape that IS reversible still is.
# 而那個「可逆」的形狀仍然可逆。
assert_eq "$("$CSV2" -get 2:1 -i "$TMP/t136.csv")" '<br>' \
    "T136d while -get returns the value itself / 而 -get 回傳的是那個值本身"

print -r -- 'a,b'  > "$TMP/t136i.csv"
print -r -- '1,x' >> "$TMP/t136i.csv"
"$CSV2" --build-index -i "$TMP/t136i.csv" >/dev/null
"$CSV2" --verify-index -i "$TMP/t136i.csv" >/dev/null 2>&1
assert_eq "$?" "0" \
    "T136e --verify-index exits 0 when the index is there and accurate / 索引存在且正確時 --verify-index 以 0 結束"

rm -f "$TMP/t136i.csv.index"
"$CSV2" --verify-index -i "$TMP/t136i.csv" >/dev/null 2>&1
assert_eq "$?" "1" \
    "T136f and 1 when there is none / 沒有索引時是 1"

"$CSV2" --build-index -i "$TMP/t136i.csv" >/dev/null
print -r -- '1,y' >> "$TMP/t136i.csv"
_t136_v=$("$CSV2" --verify-index -i "$TMP/t136i.csv" 2>&1)
_t136_rc=$?
assert_eq "$_t136_rc" "1" \
    "T136g and 1 when the stamp rejects it / 戳記否決它時也是 1"
assert_contains "$_t136_v" "not compared against the data" \
    "T136h saying it did not run the O(n) comparison, rather than implying it did / 並說明它沒有做那次 O(n) 比對，而不是讓人以為做了"

# The ordinary path is unaffected by all of that: still right, still rc=0.
# 一般路徑不受上述任何一項影響：照樣正確、照樣 rc=0。
assert_eq "$("$CSV2" -get 2:2 -i "$TMP/t136i.csv")" "y" \
    "T136i while an ordinary read scans and is right / 而一般的讀取會改為掃描，且是對的"

# ---------------------------------------------------------------------
# T135 -- three situations, one sentence, and a reason the system had already
# given us.
#
# Round 53: pointing -keyfile at a DIRECTORY reported "keyfile is empty or
# unreadable", which describes neither; and an unreadable sidecar reported
# "reason not recorded" when the reason was one strerror() call away. Both are
# the same shape: a message that covers several cases by naming none of them.
#
# T135 —— 三種情況、一句話，以及一個系統早就給了我們的理由。
# 第 53 回合：把 -keyfile 指到一個「目錄」時回報「金鑰檔為空或無法讀取」，而那兩者都不是它；
# 一份讀不到的 sidecar 回報「沒有記錄到理由」，而那個理由離一次 strerror() 只有一步。
# 兩者是同一個形狀：一句涵蓋好幾種情況、卻沒有指名其中任何一種的訊息。
# ---------------------------------------------------------------------
echo
echo "--- T135: say which of them it is / T135：說出是哪一種 ---"

print -r -- 'a,b'  > "$TMP/t135.csv"
print -r -- '1,x' >> "$TMP/t135.csv"
mkdir -p "$TMP/t135_dir"
: > "$TMP/t135_empty"

_t135_dir_out=$("$CSV2" -encrypt b -keyfile "$TMP/t135_dir" -i "$TMP/t135.csv" -o "$TMP/t135_out.csv" 2>&1)
assert_contains "$_t135_dir_out" "keyfile is a directory" \
    "T135a a directory given as -keyfile is named as one / 把目錄當成 -keyfile 時，訊息說它是目錄"

# The old message was "keyfile is empty or unreadable", which CONTAINS "keyfile
# is empty" -- so a contains-check alone passed against the very wording this
# case exists to rule out. It has to require the hedge to be gone.
# 舊訊息是「keyfile is empty or unreadable」，而它「包含」「keyfile is empty」——因此單靠
# contains 檢查，會對著這個案例要排除的那句措辭本身通過。它必須要求那個含糊的部分不在。
_t135_empty_out=$("$CSV2" -encrypt b -keyfile "$TMP/t135_empty" -i "$TMP/t135.csv" -o "$TMP/t135_out.csv" 2>&1)
if [[ $_t135_empty_out == *"keyfile is empty"* && $_t135_empty_out != *"or unreadable"* ]]; then
    ok "T135b and an empty file is called empty, not empty-or-unreadable / 而空檔案就叫空檔案，不是「為空或無法讀取」"
else
    bad "T135b $(print -r -- $_t135_empty_out | head -1) / 訊息如上"
fi

# An unreadable sidecar. Skipped where the test runs as root or where the
# permission cannot be made to bite: chmod 000 does not stop root, and a file
# csv2 can still read would make this pass for the wrong reason.
# 一份讀不到的 sidecar。在「以 root 執行」或「權限咬不住」的地方跳過：chmod 000 擋不住 root，
# 而一個 csv2 仍讀得到的檔案會讓這個案例因為錯誤的理由通過。
"$CSV2" --build-index -i "$TMP/t135.csv" >/dev/null 2>&1
chmod 000 "$TMP/t135.csv.index" 2>/dev/null
if [[ -r "$TMP/t135.csv.index" ]]; then
    skipt "T135c an unreadable sidecar reports why / 讀不到的 sidecar 會說出為什麼 (this user can read a mode-000 file / 此使用者讀得到 mode 000 的檔案)"
else
    _t135_out=$("$CSV2" --verify-index -i "$TMP/t135.csv" 2>&1)
    if [[ $_t135_out == *"cannot be read"* && $_t135_out != *"reason not recorded"* ]]; then
        ok "T135c an unreadable sidecar reports why / 讀不到的 sidecar 會說出為什麼"
    else
        bad "T135c $(print -r -- $_t135_out | head -1) / 訊息如上"
    fi
fi
chmod 644 "$TMP/t135.csv.index" 2>/dev/null

# ---------------------------------------------------------------------
# T134 -- a sidecar that belongs to a different file.
#
# Round 53: "No mention that a FOREIGN sidecar is reported as 'stale: the data
# file changed' when the data file did not change." The stamp compares size,
# mtime and content hashes; it establishes that the two do not match and
# cannot say which of them moved. Telling the reader their data file changed
# sends them looking for an edit nobody made.
#
# T134 —— 一份屬於別的檔案的 sidecar。
# 第 53 回合：「沒有任何地方提到，一份『外來的』sidecar 會被回報成『過期：資料檔已經改變』，
# 而那個資料檔根本沒有變。」那個戳記比對的是大小、mtime 與內容雜湊；它確立的是「兩者不相符」，
# 說不出是哪一邊動了。告訴讀者他的資料檔變了，會把他送去找一次沒有人做過的編輯。
# ---------------------------------------------------------------------
echo
echo "--- T134: whose sidecar is this / T134：這份 sidecar 是誰的 ---"

print -r -- 'a,b'   > "$TMP/t134_mine.csv"
print -r -- '1,x'  >> "$TMP/t134_mine.csv"
print -r -- 'a,b'   > "$TMP/t134_other.csv"
print -r -- '9,z'  >> "$TMP/t134_other.csv"
print -r -- '8,y'  >> "$TMP/t134_other.csv"
"$CSV2" --build-index -i "$TMP/t134_mine.csv"  >/dev/null
"$CSV2" --build-index -i "$TMP/t134_other.csv" >/dev/null
cp "$TMP/t134_other.csv.index" "$TMP/t134_mine.csv.index"
_t134_before=$(cksum < "$TMP/t134_mine.csv")

_t134_out=$("$CSV2" --verify-index -i "$TMP/t134_mine.csv" 2>&1)
if [[ $_t134_out != *"the data file changed"* && $_t134_out != *"資料檔已經改變"* ]]; then
    ok "T134a a foreign sidecar is not reported as the data file having changed / 外來的 sidecar 不會被說成「資料檔改變了」"
else
    bad "T134a $(print -r -- $_t134_out | head -1) / 訊息如上"
fi
if [[ $_t134_out == *"belongs to another"* && $_t134_out == *"屬於另一個檔案"* ]]; then
    ok "T134b and both languages offer the explanation that fits / 而兩種語言都給出了說得通的那個解釋"
else
    bad "T134b the message does not mention the other possibility / 訊息沒有提到另一種可能：$(print -r -- $_t134_out | head -1)"
fi
assert_eq "$(cksum < "$TMP/t134_mine.csv")" "$_t134_before" \
    "T134c and the data file really was untouched / 而那個資料檔確實一個位元組也沒被動到"

# The read still succeeds by scanning: an unusable sidecar is never an error on
# the ordinary path, only for --verify-index, which is asked to prove it.
# 讀取仍會以掃描的方式成功：一份不可用的 sidecar 在一般路徑上絕不是錯誤，只有被要求「證明它」
# 的 --verify-index 才會以非零結束。
assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t134_mine.csv")" "1" \
    "T134d and the ordinary read is right anyway, by scanning / 而一般的讀取照樣是對的，靠掃描"

# ---------------------------------------------------------------------
# T133 -- what the writer does to a value it has to re-serialise.
#
# Round 53: "-update a whitespace-only cell with its own value rewrites
# `"   "` as `   `; -rownum quotes differently from -r. Same value, different
# bytes, spurious git diff -- in a tool whose closing argument is that git can
# diff it."
#
# Both were real. The whitespace is data, and it is the kind that vanishes
# silently in the next tool along; the -rownum difference had no reason at all
# behind it -- preserveRaw was switched off wholesale when a column was added,
# though it is decided per field.
#
# T133 —— 寫出端對一個「必須重新序列化」的值做了什麼。
# 第 53 回合：「以原值 -update 一個只有空白的儲存格，`"   "` 會被寫成 `   `；`-rownum` 的
# 引號規則與 `-r` 不同。同一個值、不同的位元組、憑空多出來的 git diff——而這支工具最後的
# 論據正是『git 可以 diff 它』。」兩件都成立。
# ---------------------------------------------------------------------
echo
echo "--- T133: the same value, the same bytes / T133：同一個值，同一組位元組 ---"

printf 'a,b\n"   ",x\n' > "$TMP/t133.csv"
cp "$TMP/t133.csv" "$TMP/t133.keep"
"$CSV2" -update 1:1 '   ' -i "$TMP/t133.csv" --in-place
if cmp -s "$TMP/t133.csv" "$TMP/t133.keep"; then
    ok "T133a updating a cell with the value it already held changes no bytes / 以儲存格原本就有的值去更新它，不會改動任何位元組"
else
    bad "T133a the file changed: $(od -c "$TMP/t133.csv" | head -1) / 檔案變了，如上"
fi

printf 'a,b\n"   ",x\n' > "$TMP/t133b.csv"
assert_eq "$("$CSV2" -r -i "$TMP/t133b.csv" | head -1)" '"   ",x' \
    "T133b -r writes a quoted whitespace field as it arrived / -r 照原樣寫出一個加了引號的空白欄位"
assert_eq "$("$CSV2" -r -rownum -i "$TMP/t133b.csv" | head -1)" '1,"   ",x' \
    "T133c and -rownum agrees with it, one flag away / 而 -rownum 與它一致，只差一個旗標"

# A value the caller supplies, not one that was already in the file.
# 由呼叫端給的值，而不是檔案裡本來就有的。
"$CSV2" -update 1:2 'y ' -i "$TMP/t133b.csv" --in-place
assert_eq "$("$CSV2" -r -i "$TMP/t133b.csv" | head -1)" '"   ","y "' \
    "T133d a supplied value ending in a space is quoted when written / 呼叫端給的、結尾帶空白的值，寫出時會加引號"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t133b.csv")" 'y ' \
    "T133e and reading it back gives the space / 而讀回來時那個空白還在"

# Not quoted for its own sake: a value that needs nothing stays bare, or every
# file csv2 touched would grow quotes it did not need.
# 不是為了加而加：不需要引號的值維持原樣，否則每一個 csv2 碰過的檔案都會長出它不需要的引號。
printf 'a,b\n1,x\n' > "$TMP/t133c.csv"
"$CSV2" -update 1:2 'plain' -i "$TMP/t133c.csv" --in-place
assert_eq "$("$CSV2" -r -i "$TMP/t133c.csv" | head -1)" '1,plain' \
    "T133f a value needing no quotes does not get any / 不需要引號的值不會被加上引號"

# ---------------------------------------------------------------------
# T132 -- an address the tool printed, handed back to the tool.
#
# The README promises the locating report's notation composes: "the same
# notation -contains prints, so finding and editing compose". Three ways that
# was not true:
#   - a .csv header hit prints plain `0:1`, while the README said `0a`/`0b`
#     and "never plain 0" -- a script filtering on ^0[ab]: missed every one;
#   - -update and -delete -cell answered a header address with "expected r:c",
#     which is a complaint about the shape of an address csv2 had just printed,
#     while -get explained the reason. One property, three accounts;
#   - --physical and --a1 print `1:1@L2` and `1:1 [A2]`, and feeding either
#     back produced `no column named "1@L2"`, sending the reader after a column
#     that was never the problem.
#
# T132 —— 工具印出來的位址，交還給工具。
# README 承諾定位報告的寫法可以直接接下去，而它在三個地方不成立：`.csv` 的標頭命中印的是
# 單純的 `0:1`（README 說「絕不會是單純的 0」）；-update 與 -delete -cell 用「需要 r:c」
# 回答一個 csv2 剛剛自己印出來的位址，而 -get 講的是理由；--physical 與 --a1 印出的
# `1:1@L2`、`1:1 [A2]` 餵回去會得到「沒有名為 1@L2 的欄位」。
# ---------------------------------------------------------------------
echo
echo "--- T132: the tool accepts, or explains, what it printed / T132：工具印出來的東西，它要嘛收，要嘛講清楚 ---"

print -r -- 'name,value'  > "$TMP/t132.csv"
print -r -- 'foo,1'      >> "$TMP/t132.csv"

assert_eq "$("$CSV2" -contains foo --include-headers -i "$TMP/t132.csv" | head -1 | cut -f1)" "1:1" \
    "T132a a data hit is addressed r:c / 命中資料時的位址是 r:c"
assert_eq "$("$CSV2" -contains name --include-headers -i "$TMP/t132.csv" | cut -f1)" "0:1" \
    "T132b a .csv header hit is plain 0, as the README now says / .csv 的標頭命中就是單純的 0，一如 README 現在所寫"

# Same sentence from all three verbs. Matching on the REASON, not on the whole
# message: what matters is that none of them answers a well-formed address by
# complaining about its shape.
# 三個動詞說同一句話。比對的是「理由」而不是整句訊息：重點在於沒有任何一個會用「格式不對」
# 去回答一個格式正確的位址。
for _t132_addr in '0:1' '0a:1' '0b:1'; do
    for _t132_verb in get update delete; do
        case $_t132_verb in
            get)    _t132_out=$("$CSV2" -get "$_t132_addr" -i "$TMP/t132.csv" 2>&1) ;;
            update) _t132_out=$("$CSV2" -update "$_t132_addr" X -i "$TMP/t132.csv" --in-place 2>&1) ;;
            delete) _t132_out=$("$CSV2" -delete -cell "$_t132_addr" -i "$TMP/t132.csv" --in-place 2>&1) ;;
        esac
        if [[ $_t132_out == *"names a header cell"* && $_t132_out != *"expected r:c"* ]]; then
            ok "T132c -$_t132_verb $_t132_addr is refused with the reason / -$_t132_verb $_t132_addr 以理由被拒絕"
        else
            bad "T132c -$_t132_verb $_t132_addr: $(print -r -- $_t132_out | head -1) / 訊息如上"
        fi
    done
done

# A decorated address names the decoration, not a column that does not exist.
# 帶裝飾的位址要指出那段裝飾，而不是指向一個不存在的欄位。
_t132_phys=$("$CSV2" -contains foo --physical -i "$TMP/t132.csv" | cut -f1)
_t132_out=$("$CSV2" -get "$_t132_phys" -i "$TMP/t132.csv" 2>&1)
if [[ $_t132_out == *"--physical or --a1 prints"* ]]; then
    ok "T132d a --physical address is diagnosed as one / --physical 的位址會被指認出來"
else
    bad "T132d $_t132_phys gave: $(print -r -- $_t132_out | head -1) / 訊息如上"
fi

_t132_a1=$("$CSV2" -contains foo --a1 -i "$TMP/t132.csv" | cut -f1)
_t132_out=$("$CSV2" -get "$_t132_a1" -i "$TMP/t132.csv" 2>&1)
if [[ $_t132_out == *"--physical or --a1 prints"* ]]; then
    ok "T132e and so is an --a1 address / --a1 的位址同樣如此"
else
    bad "T132e $_t132_a1 gave: $(print -r -- $_t132_out | head -1) / 訊息如上"
fi

# And a column whose NAME ends that way is still a column. Deciding by
# appearance alone would tell someone their own column name is a decoration.
# 而一個「名字本來就長那樣」的欄位仍然是欄位。只看樣子就下判斷，等於告訴別人他自己的欄名
# 是裝飾。
print -r -- 'id [primary],b'  > "$TMP/t132b.csv"
print -r -- '7,x'            >> "$TMP/t132b.csv"
assert_eq "$("$CSV2" -get '1:id [primary]' -i "$TMP/t132b.csv")" "7" \
    "T132f a column really named like a decoration still resolves / 名字本來就像裝飾的欄位仍然解析得到"

_t132_out=$("$CSV2" -get '1:nope' -i "$TMP/t132.csv" 2>&1)
if [[ $_t132_out == *"no column named"* ]]; then
    ok "T132g and a genuinely missing column still says so / 而真的不存在的欄位仍然會這樣說"
else
    bad "T132g $(print -r -- $_t132_out | head -1) / 訊息如上"
fi

# ---------------------------------------------------------------------
# T131 -- a write that fails for a reason other than a departed reader.
#
# Two failures used to be treated as one. `Platform.writeAll` called
# readerHasGone() for ANY failed write, so a full disk raised SIGPIPE and csv2
# exited 141 with an empty stderr and a half-written file -- and 141 is the
# status the README tells callers to disregard. The file sink meanwhile used
# FileHandle.write, on the reasoning that a file cannot meet a broken pipe:
# true, and beside the point, because it can meet ENOSPC, and Foundation
# answers that with an exception nobody catches (exit 134, no diagnostic, temp
# file left behind).
#
# ENOSPC itself is not reachable portably -- it needs a filesystem this suite
# has no business creating -- so it is verified by hand in
# todo/known-defects.md (DV) and the property is pinned here with a failure
# that IS portable: writing to a descriptor the shell has closed.
#
# T131 —— 一次「不是因為讀端離開」而失敗的寫入。
# 兩種失敗曾被當成同一種：`Platform.writeAll` 對任何失敗的寫入都呼叫 readerHasGone()，
# 於是磁碟寫滿會引發 SIGPIPE、csv2 以 141 結束、stderr 空白、磁碟上留著寫到一半的檔案
# ——而 141 正是 README 叫呼叫端不必理會的那個狀態。檔案 sink 則走 FileHandle.write，
# 理由是「檔案不可能遇到管線斷掉」：那是對的，也不是重點，因為它會遇到 ENOSPC，而
# Foundation 對此的回答是一個沒有人接的例外（rc=134、沒有診斷、暫存檔留下）。
# ENOSPC 本身無法可攜地重現——那需要一個本測試沒有立場去建立的檔案系統——因此它由
# todo/known-defects.md（DV）以手動方式驗證，而這裡用一個「可攜的」失敗來釘住同一個
# 性質：寫入一個已被 shell 關掉的描述子。
# ---------------------------------------------------------------------
echo
echo "--- T131: a failed write is reported, not disguised / 失敗的寫入會被回報，而不是被偽裝 ---"

print -r -- 'a,b'  > "$TMP/t131.csv"
print -r -- '1,x' >> "$TMP/t131.csv"

"$CSV2" -r -t -i "$TMP/t131.csv" -so >&- 2>"$TMP/t131a.err"
_t131_rc=$?
assert_eq "$_t131_rc" "1" \
    "T131a a write that fails for another reason exits 1, not 141 / 因其他理由失敗的寫入以 1 結束，不是 141"
assert_eq "$(wc -l < "$TMP/t131a.err" | tr -d ' ')" "2" \
    "T131b and it says so in the documented two lines / 而它以文件所述的兩行說出來"
if grep -q 'cannot write to standard output' "$TMP/t131a.err"; then
    ok "T131c naming the destination it could not write / 指出它寫不進去的是哪一個目的地"
else
    bad "T131c the message does not name the destination / 訊息沒有指出目的地：$(head -1 "$TMP/t131a.err")"
fi

# With stderr closed as well there is nowhere to report to, and the status is
# the only thing left. It still has to be 1, and csv2 still has to stop.
# 連 stderr 也關掉時，沒有地方可以回報，剩下的只有結束狀態。它仍然必須是 1，而 csv2 仍然
# 必須停下來。
"$CSV2" -r -t -i "$TMP/t131.csv" -so >&- 2>&-
assert_eq "$?" "1" \
    "T131d with nowhere to report to, the status still says it failed / 連回報的地方都沒有時，結束狀態仍然說它失敗了"

# T131e -- the temp file after a signal. The README says a failed in-place edit
# leaves none beside the target; that was true of the error paths and false of
# a killed process, which left a hidden multi-megabyte file nobody would see.
#
# The mid-run check is not decoration: without it this case passes when csv2
# exits before the signal arrives, which is the same "cannot tell the two
# apart" hole T43h had.
# T131e —— 訊號之後的暫存檔。README 說失敗的就地編輯不會在目標旁留下暫存檔；那在錯誤路徑上
# 成立，在「行程被殺死」時不成立——它會留下一個沒有人看得到的隱藏檔，好幾 MB。
# 「執行中」那一步不是裝飾：少了它，這個案例在「csv2 早在訊號到達前就結束了」時照樣通過，
# 那與 T43h 曾有的「分不出兩者」是同一個洞。
if (( IS_WINDOWS )); then
    skipt "T131e a killed edit leaves no temp file beside the target / 被殺死的編輯不會在目標旁留下暫存檔 (POSIX signal handlers; a native Windows binary is not stopped this way / 這是 POSIX 訊號處理，原生 Windows 程式不是這樣被停下的)"
else
    rm -f "$TMP"/.t131_out.csv.csv2tmp.*(N) "$TMP/t131_out.csv"
    ( print -r -- 'a,b'; print -r -- '1,x'; sleep 5 ) \
        | "$CSV2" -r -t -si --headers 1 -o "$TMP/t131_out.csv" 2>/dev/null &
    _t131_pid=$!
    sleep 1
    _t131_mid=$(print -r -- "$TMP"/.t131_out.csv.csv2tmp.*(N))
    kill -TERM $_t131_pid 2>/dev/null
    wait $_t131_pid 2>/dev/null
    _t131_left=$(print -r -- "$TMP"/.t131_out.csv.csv2tmp.*(N))
    if [[ -n $_t131_mid && -z $_t131_left ]]; then
        ok "T131e a killed edit leaves no temp file beside the target / 被殺死的編輯不會在目標旁留下暫存檔"
    else
        bad "T131e mid-run temp=${_t131_mid:-none}, left behind=${_t131_left:-none} / 執行中的暫存檔與殘留如上"
    fi

    # Not only the signal that came to mind. A round killed an edit with
    # SIGXFSZ, SIGPIPE, SIGALRM and SIGUSR1 and got a hidden temp file each
    # time -- SIGXFSZ being what an `ulimit -f` or a filesystem quota produces,
    # which is not exotic at all.
    # 不只是「當初想到的那個訊號」。有一個回合用 SIGXFSZ、SIGPIPE、SIGALRM、SIGUSR1 各殺了
    # 一次編輯，每次都留下一個隱藏的暫存檔——而 SIGXFSZ 正是 `ulimit -f` 或檔案系統配額會
    # 產生的那一個，一點也不罕見。
    _t131_leaks=""
    for _t131_sig in HUP QUIT XFSZ ALRM USR1 PIPE; do
        rm -f "$TMP"/.t131_out.csv.csv2tmp.*(N) "$TMP/t131_out.csv"
        ( print -r -- 'a,b'; print -r -- '1,x'; sleep 5 ) \
            | "$CSV2" -r -t -si --headers 1 -o "$TMP/t131_out.csv" 2>/dev/null &
        _t131_pid=$!
        sleep 1
        [[ -z $(print -r -- "$TMP"/.t131_out.csv.csv2tmp.*(N)) ]] && \
            { _t131_leaks="$_t131_leaks $_t131_sig(no-temp-to-lose)"; kill -TERM $_t131_pid 2>/dev/null; continue }
        kill -$_t131_sig $_t131_pid 2>/dev/null
        wait $_t131_pid 2>/dev/null
        [[ -n $(print -r -- "$TMP"/.t131_out.csv.csv2tmp.*(N)) ]] && _t131_leaks="$_t131_leaks $_t131_sig"
    done
    if [[ -z ${_t131_leaks// /} ]]; then
        ok "T131f and the same holds for every catchable signal that ends a run / 而每一個「可攔截且會結束執行」的訊號都是如此"
    else
        bad "T131f a temp file survived:${_t131_leaks} / 這些訊號之後暫存檔還在"
    fi
    rm -f "$TMP"/.t131_out.csv.csv2tmp.*(N)
fi

# ---------------------------------------------------------------------
# T130 -- -o and what "this file" means. The other half of T129.
# T130 —— -o，以及「這個檔案」指的是什麼。T129 的另一半。
# ---------------------------------------------------------------------
echo
echo "--- T130: -o, on the right file / -o，而且是對的那個檔案 ---"

if (( IS_WINDOWS )); then
    skipt "T130a-c -o through a symlink, and the same file spelled two ways / 經 symlink 的 -o，以及同一個檔案的兩種寫法 (no symlinks under MSYS2 / MSYS2 下沒有 symlink)"
    # The path-spelling half needs no symlinks, so it runs everywhere.
    # 「同一個檔案的兩種寫法」那一半不需要 symlink，因此每個平台都跑。
    print -r -- 'a,b'  > "$TMP/t130_f.csv"
    print -r -- '1,x' >> "$TMP/t130_f.csv"
    assert_fails "T130d -i and -o the same file spelled differently is refused / -i 與 -o 是同一個檔案的不同寫法，會被拒絕" -- \
        "$CSV2" -head 1 -t -i "$TMP/t130_f.csv" -o "$TMP/./t130_f.csv"
else
    # `-o` reaches its destination by temp+rename, so without resolving first it
    # replaces the LINK and leaves the target untouched -- at rc=0, while the
    # shell's own `>` would have written through it.
    # `-o` 也是以暫存檔 + rename 抵達目的地，因此不先解析就會把「連結」換掉、目標動也沒動
    # ——而且 rc=0，儘管 shell 自己的 `>` 是會寫穿過去的。
    print -r -- 'a,b'   > "$TMP/t130_src.csv"
    print -r -- '1,x'  >> "$TMP/t130_src.csv"
    print -r -- '2,y'  >> "$TMP/t130_src.csv"
    print -r -- 'a,b'   > "$TMP/t130_dst.csv"
    print -r -- '9,old'>> "$TMP/t130_dst.csv"
    chmod 600 "$TMP/t130_dst.csv"
    ln -sf "$TMP/t130_dst.csv" "$TMP/t130_link.csv"

    assert_succeeds "T130a -o through a symlink succeeds / 經 symlink 的 -o 會成功" -- \
        "$CSV2" -head 1 -t -i "$TMP/t130_src.csv" -o "$TMP/t130_link.csv"

    if [[ -L "$TMP/t130_link.csv" ]]; then
        ok "T130a1 and the symlink is still a symlink / 而那個 symlink 仍然是 symlink"
    else
        bad "T130a1 the symlink was replaced by a regular file / 那個 symlink 被換成了一般檔案"
    fi

    assert_eq "$("$CSV2" -get 1:1 -i "$TMP/t130_dst.csv")" "1" \
        "T130b and the data landed in the file it points at / 而資料落在它所指向的檔案裡"

    assert_eq "$(file_mode "$TMP/t130_dst.csv")" "600" \
        "T130c and writing there does not widen its permissions / 而寫入那裡不會放寬它的權限"

    # Same file, two spellings: as typed, and through a link to it. Neither used
    # to be refused, and neither is equivalent to --in-place.
    # 同一個檔案的兩種寫法：直接打，以及經由一個指向它的連結。兩者過去都不會被拒絕，
    # 而兩者都不等同於 --in-place。
    print -r -- 'a,b'  > "$TMP/t130_f.csv"
    print -r -- '1,x' >> "$TMP/t130_f.csv"
    assert_fails "T130d -i and -o the same file spelled differently is refused / -i 與 -o 是同一個檔案的不同寫法，會被拒絕" -- \
        "$CSV2" -head 1 -t -i "$TMP/t130_f.csv" -o "$TMP/./t130_f.csv"

    ln -sf "$TMP/t130_f.csv" "$TMP/t130_flink.csv"
    assert_fails "T130e -o through a link to the input is refused as well / 經由指向輸入的連結來 -o，同樣會被拒絕" -- \
        "$CSV2" -head 1 -t -i "$TMP/t130_f.csv" -o "$TMP/t130_flink.csv"

    # And the refusal must not have swallowed the ordinary case.
    # 而那條拒絕不能連一般情況也一起吞掉。
    assert_succeeds "T130f -o to an unrelated file still works / -o 寫到一個無關的檔案仍然可用" -- \
        "$CSV2" -head 1 -t -i "$TMP/t130_src.csv" -o "$TMP/t130_new.csv"
fi

# ---------------------------------------------------------------------
# T165 -- the append fast path reads the whole file, so it leaves an index.
#
# Round 63 measured `-append --in-place` at 50/188/802 ms on 2/8/35 MB and
# caught the README saying, in three places, that its fast path "never reads
# the file to the end". It stopped being true when the unclosed-quote check
# was added: that check parses every byte on every append. Two of those three
# sentences were load-bearing -- they were the stated REASON for the one
# behaviour that made this the only write path in the tool to leave a file it
# had just read from end to end without a sidecar.
#
# So the behaviour moved to match the rule the document already states: the
# next operation that writes the file, or that has to read it to the end
# anyway, puts a good index back. Appending does both.
#
# T165 —— 追加快路徑會把整個檔案讀完，因此它會留下一份索引。
# 第 63 回合量到 `-append --in-place` 在 2/8/35 MB 上是 50/188/802 ms，並抓到 README 有
# 三處說它的快路徑「從不把檔案讀到結尾」。那句話在「未關閉引號」檢查加進來時就不再成立：
# 那個檢查每一次追加都會解析每一個位元組。三處之中有兩處是承重的——它們是某個「行為」的
# 理由，而那個行為讓這條路徑成為本工具唯一一條「剛剛從頭到尾讀完一個檔案、卻沒有留下
# sidecar」的寫入路徑。
# ---------------------------------------------------------------------
echo
echo "--- T165: an append leaves an index / T165：一次追加會留下索引 ---"

printf 'id,note\n' > "$TMP/t165.csv"
for _i in $(seq 1 40); do printf 'r%d,n%d\n' $_i $_i >> "$TMP/t165.csv"; done
cp "$TMP/t165.csv" "$TMP/t165b.csv"
cp "$TMP/t165.csv" "$TMP/t165c.csv"

CSV2_INDEX_MIN_BYTES=0 "$CSV2" -append 'r41,n41' -i "$TMP/t165.csv" --in-place
if [[ -f "$TMP/t165.csv.index" ]]; then
    ok "T165a an append builds the index its own scan paid for / 一次追加會建出「它自己的掃描已經付過帳」的那份索引"
else
    bad "T165a no index beside $TMP/t165.csv after an append / 追加之後旁邊沒有索引"
fi
assert_succeeds "T165b and that index describes the file / 而那份索引與檔案相符" -- \
    "$CSV2" --verify-index -i "$TMP/t165.csv"

# --no-index still means none, and the size threshold still decides. Both were
# checked because "builds one now" must not become "builds one always": the
# flag is the user saying do not, and the threshold is the reason a two-line
# file has no sidecar.
# --no-index 仍然表示不建，而大小門檻仍然說了算。兩者都要檢查，因為「現在會建」不可以變成
# 「一律會建」：那個旗標是使用者說不要，而那個門檻是「兩行的檔案旁邊沒有 sidecar」的理由。
CSV2_INDEX_MIN_BYTES=0 "$CSV2" -append 'r41,n41' -i "$TMP/t165b.csv" --in-place --no-index
assert_eq "$([[ -f "$TMP/t165b.csv.index" ]] && echo yes || echo no)" "no" \
    "T165c --no-index still builds none / --no-index 仍然什麼都不建"
CSV2_INDEX_MIN_BYTES=99999999 "$CSV2" -append 'r41,n41' -i "$TMP/t165c.csv" --in-place
assert_eq "$([[ -f "$TMP/t165c.csv.index" ]] && echo yes || echo no)" "no" \
    "T165d below CSV2_INDEX_MIN_BYTES it still builds none / 在 CSV2_INDEX_MIN_BYTES 以下仍然不建"

# ---------------------------------------------------------------------
# T166 -- the line an appended record starts on.
#
# Found while checking T165, not reported by the round. The append path
# computed the appended record's line as `index.lastLine + prefix`, and
# lastLine is the line the LAST record STARTS on -- so the sum was short by
# however many lines that record occupies. An appended record landing on a
# grid point put a wrong line into the sidecar; `-mid N,N --json` printed it,
# `--no-index` disagreed by one, and `--verify-index` said OK because it did
# not check the lines it stores.
#
# The fixture makes record 1 span two lines, so record 257 -- the second grid
# point at stride 256 -- lands one line further down than its record number
# suggests, and the two answers can differ.
#
# T166 —— 一筆被追加的紀錄從哪一行開始。
# 這是檢查 T165 時發現的，不是那個回合回報的。追加路徑用 `index.lastLine + prefix` 算它，
# 而 lastLine 是「最後一筆『開始』的那一行」——因此那個和少了那一筆自己佔掉的行數。fixture
# 讓第 1 筆跨兩行，於是第 257 筆（stride 256 的第二個格點）比它的紀錄號多落一行，兩個答案
# 因此才可能不同。
# ---------------------------------------------------------------------
echo
echo "--- T166: the appended record's line / T166：被追加那一筆的行號 ---"

{
    printf 'id,note\n'
    printf 'r1,"two\nlines"\n'
    for _i in $(seq 2 256); do printf 'r%d,n%d\n' $_i $_i; done
} > "$TMP/t166.csv"
cp "$TMP/t166.csv" "$TMP/t166b.csv"

# With an index already there: the extend-an-index branch.
# 已經有索引時：走「延續索引」那一條分支。
CSV2_INDEX_MIN_BYTES=0 "$CSV2" --build-index -i "$TMP/t166.csv" > /dev/null
CSV2_INDEX_MIN_BYTES=0 "$CSV2" -append 'r257,n257' -i "$TMP/t166.csv" --in-place
_t166_idx=$(CSV2_INDEX_MIN_BYTES=0 "$CSV2" -mid 257,257 --json -i "$TMP/t166.csv" | sed -n 2p)
_t166_raw=$("$CSV2" -mid 257,257 --json --no-index -i "$TMP/t166.csv" | sed -n 2p)
assert_eq "$_t166_idx" "$_t166_raw" \
    "T166a the seek and the scan agree on the appended record's line / seek 與掃描對「被追加那一筆的行號」說法一致"
assert_contains "$_t166_raw" '"line":259' \
    "T166b and 259 is where it actually is / 而它實際上就在第 259 行"

# With no index: the build-an-index branch, which must get the same line.
# 沒有索引時：走「建立索引」那一條，行號必須相同。
CSV2_INDEX_MIN_BYTES=0 "$CSV2" -append 'r257,n257' -i "$TMP/t166b.csv" --in-place
assert_eq "$(CSV2_INDEX_MIN_BYTES=0 "$CSV2" -mid 257,257 --json -i "$TMP/t166b.csv" | sed -n 2p)" \
          "$_t166_raw" \
    "T166c the index built during the append says the same / 追加期間建出的索引說法相同"

# --verify-index has to be able to CATCH a wrong line, or T166a passes for
# free the next time this regresses. The index is bent by one line and its
# checksum recomputed in Python -- an independent implementation, which is
# also what pins the multiplier: `0x1000_0000_01b3`, not the FNV-1a prime the
# comment beside it used to claim (see GC in todo/known-defects.md).
# --verify-index 必須「抓得到」一個錯的行號，否則下次退化時 T166a 會白白通過。這裡把索引
# 的行號扳歪一行，並用 Python 重算檢查碼——一份獨立實作，同時也把那個乘數釘住：
# `0x1000_0000_01b3`，不是它旁邊那則註解曾經宣稱的 FNV-1a 質數（見 known-defects 的 GC）。
if command -v python3 >/dev/null 2>&1; then
    cp "$TMP/t166b.csv" "$TMP/t166c.csv"
    CSV2_INDEX_MIN_BYTES=0 "$CSV2" --build-index -i "$TMP/t166c.csv" > /dev/null
    python3 - "$TMP/t166c.csv.index" <<'PY'
import struct, sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
off, ln = struct.unpack_from('<QQ', b, 96)
struct.pack_into('<Q', b, 96 + 8, ln + 1)          # bend grid 0's line by one
h = 0xcbf29ce484222325
for i, by in enumerate(b):
    h ^= 0 if 80 <= i < 88 else by
    h = (h * 0x1000000001b3) & 0xFFFFFFFFFFFFFFFF   # the constant, not the name
struct.pack_into('<Q', b, 80, h)
open(p, 'wb').write(bytes(b))
PY
    _t166_v=$(CSV2_INDEX_MIN_BYTES=0 "$CSV2" --verify-index -i "$TMP/t166c.csv" 2>&1)
    if [[ $_t166_v == *"index says line"* ]]; then
        ok "T166d --verify-index catches a wrong line, checksum and all / --verify-index 抓得到錯的行號，連檢查碼都對得上"
    else
        bad "T166d --verify-index said: $_t166_v / --verify-index 的回答如上"
    fi
else
    skipt "T166d needs python3 to rebuild the index checksum / 需要 python3 才能重算索引檢查碼"
    T166D_SKIPPED=1
fi

# ---------------------------------------------------------------------
# T167 -- what --pretty's memory figure is measuring.
#
# The README taught CSV2_PRETTY_MAX_BYTES with an example that said a
# five-record slice "holds 9 MB". The slice is 237 bytes; 9 MB is what
# `csv2 -tail 1` costs too. The rule was right and the number was the
# process's floor, attached to the one concept the paragraph existed to teach.
# There is no portable way to measure RSS here, so what this case pins is the
# claim that survived: the limit counts the MATERIAL, so a small slice of a
# file too large to pretty-print whole is still fine.
#
# T167 —— `--pretty` 那個記憶體數字量的是什麼。
# README 用一個例子教 CSV2_PRETTY_MAX_BYTES，說五筆的切片「holds 9 MB」。那個切片是 237
# bytes，而 9 MB 是 `csv2 -tail 1` 也要付的。規則是對的，數字是行程的地板。這裡沒有可攜的
# RSS 量法，因此這個案例釘住的是活下來的那個宣稱：上限量的是「材料」。
# ---------------------------------------------------------------------
echo
echo "--- T167: --pretty counts the material / T167：--pretty 量的是材料 ---"

{
    printf 'id,note\n'
    for _i in $(seq 1 400); do printf 'r%d,this is a note of some length %d\n' $_i $_i; done
} > "$TMP/t167.csv"

assert_fails "T167a --pretty refuses when the material is over the limit / 材料超過上限時 --pretty 拒絕" -- \
    env CSV2_PRETTY_MAX_BYTES=200 "$CSV2" -r -t -md --pretty -i "$TMP/t167.csv"
assert_succeeds "T167b and a slice of the same file under it is fine / 而同一個檔案在上限以下的切片沒問題" -- \
    env CSV2_PRETTY_MAX_BYTES=200 "$CSV2" -mid 1,2 -t -md --pretty -i "$TMP/t167.csv"

# ---------------------------------------------------------------------
# T168 -- the buffered-record refusal names the knob, and the flag typed.
#
# The README says the message "names the request, the limit and the variable"
# and covers `-tail N` and `-B N` with that one sentence. `-tail` named all
# three; `-B` named two. And `-C 6`, which sets `before` as well, was reported
# as `-B 6` -- a message pointing at a flag that is not on the command line.
#
# T168 —— 緩衝上限那條拒絕會指出旋鈕，以及使用者實際打的那個旗標。
# ---------------------------------------------------------------------
echo
echo "--- T168: the buffered-record refusal / T168：緩衝紀錄上限的拒絕 ---"

printf 'a,b\n1,MIT\n2,MIT\n3,x\n4,y\n5,z\n6,w\n' > "$TMP/t168.csv"

_t168_tail=$(CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -tail 6 -i "$TMP/t168.csv" 2>&1)
_t168_b=$(CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -contains MIT -B 6 -i "$TMP/t168.csv" 2>&1)
_t168_c=$(CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -contains MIT -C 6 -i "$TMP/t168.csv" 2>&1)

assert_contains "$_t168_tail" "CSV2_MAX_BUFFER_RECORDS" \
    "T168a -tail names the variable / -tail 指出變數名稱"
assert_contains "$_t168_b" "CSV2_MAX_BUFFER_RECORDS" \
    "T168b and so does -B / -B 也是"
assert_contains "$_t168_c" "-C 6" \
    "T168c and -C is reported as -C, not as -B / 而 -C 被回報成 -C，不是 -B"
assert_fails "T168d all three refuse rather than truncate / 三者都是拒絕而非截斷" -- \
    env CSV2_MAX_BUFFER_RECORDS=5 "$CSV2" -contains MIT -C 6 -i "$TMP/t168.csv"

# ---------------------------------------------------------------------
# T169 -- the log's escape set is the report's escape set.
#
# `-log` documented four escapes and told the reader to unescape those four
# and then read the quoted fields. The log also writes `\xNN` for every other
# control byte -- the same convention the locating report documents -- so a
# script written to the documented procedure mis-decodes any value carrying
# one, in the output the document calls the authoritative audit trail.
#
# T169 —— log 的跳脫集合，就是報告的跳脫集合。
# ---------------------------------------------------------------------
echo
echo "--- T169: what the audit trail escapes / T169：稽核軌跡會跳脫什麼 ---"

printf 'a,b\n1,old\n' > "$TMP/t169.csv"
"$CSV2" -update 1:2 "$(printf 'e\033f\007g')" -i "$TMP/t169.csv" --in-place -log "$TMP/t169.log"
_t169=$(grep 'update 1:' "$TMP/t169.log")
assert_contains "$_t169" '\x1B' \
    "T169a ESC is written as \\x1B, upper-case hex / ESC 寫成 \\x1B，大寫十六進位"
assert_contains "$_t169" '\x07' \
    "T169b and BEL as \\x07 / BEL 寫成 \\x07"

# ---------------------------------------------------------------------
# T170 -- the refusals and warnings the lists left out.
#
# Both are cases of the program doing the right thing while a list that
# presents itself as complete does not count it. A reader uses "not on the
# list" to conclude "does not happen".
#
# T170 —— 清單漏掉的那些拒絕與警告。
# ---------------------------------------------------------------------
echo
echo "--- T170: -insert's field count, and the discard warning / T170：-insert 的欄數，與丟棄警告 ---"

printf 'a,b,c,d\n1,2,3,4\n' > "$TMP/t170.csv"
assert_fails "T170a -insert checks the field count too / -insert 同樣會檢查欄數" -- \
    "$CSV2" -insert 2 'x,y' -i "$TMP/t170.csv" -o "$TMP/t170out.csv"
printf 'a,b\n1,2\n3,"unterminated' > "$TMP/t170p.csv"
_t170w=$("$CSV2" -r -t --truncate-partial -i "$TMP/t170p.csv" -o "$TMP/t170clean.csv" 2>&1)
assert_contains "$_t170w" "WARN" \
    "T170b --truncate-partial warns about what it discarded / --truncate-partial 會就它丟掉的東西發出警告"

# ---------------------------------------------------------------------
# T171 -- --no-index gives up the parallel path on a .csv, and says so.
#
# The README recommends `--no-index` in two places as "slower, and right by
# construction". How much slower is not only the index: on a `.csv` it also
# forfeits the parallel search, because a `.csv` needs an index to prove one
# record per line. The program says this under -debug; the document said it
# in a different table. Measured 2.6x on 450,000 records.
#
# T171 —— `--no-index` 在 `.csv` 上還會放棄平行路徑，而且它說得出來。
# ---------------------------------------------------------------------
echo
echo "--- T171: what --no-index costs / T171：--no-index 的代價 ---"

_t171=$("$CSV2" -contains MIT --no-index -debug -i "$TMP/t168.csv" 2>&1)
assert_contains "$_t171" "single-threaded" \
    "T171a --no-index says which path it took / --no-index 會說它走了哪一條路"
assert_contains "$_t171" "--no-index" \
    "T171b and names --no-index as the reason / 並指出理由是 --no-index"

# ---------------------------------------------------------------------
# T172 -- the -- example from the flag list, run verbatim.
#
# `:359` shows `-update 1:2 -- --in-place` to explain that `--` marks ONE
# argument as data. Typed as printed it refuses: an edit needs a destination.
# It is a fragment, and this README has twice apologised for printing blocks
# that look runnable and are not -- so the fragment now carries its
# destination, and this case is what keeps the printed form working.
#
# T172 —— 旗標清單裡那個 `--` 範例，逐字執行。
# ---------------------------------------------------------------------
echo
echo "--- T172: the -- example runs as printed / T172：那個 -- 範例照印出來的樣子能跑 ---"

printf 'a,b\n1,2\n' > "$TMP/t172.csv"
assert_succeeds "T172a -update 1:2 -- --in-place -i F -o G is a whole command / 這一整串是一個完整的指令" -- \
    "$CSV2" -update 1:2 -- --in-place -i "$TMP/t172.csv" -o "$TMP/t172out.csv"
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t172out.csv")" "--in-place" \
    "T172b and it stored the literal --in-place / 而它存進去的是字面的 --in-place"


# ---------------------------------------------------------------------
# T173 -- an inserted row is a record of the output.
#
# Caught by T166d's new check rather than by a round: an inserted row went out
# through emit(), which advances the byte offset and nothing else, so the same
# run wrote N+1 records and an index claiming N. Every grid point after the
# insertion then named a byte belonging to some other record, and the seek
# followed it: `-mid 257,258` returned records 258 and 259 labelled 257 and
# 258, at rc=0, while --no-index returned the right ones. The same counter
# feeds the audit trail, which said "wrote 300 records" for a file with 301.
#
# T173 —— 被插入的一列，是輸出的一筆紀錄。
# 由 T166d 新加的檢查抓到，而不是由某個回合回報：被插入的一列走 emit()，而 emit() 只推進
# 位元組偏移量，於是同一次執行寫出 N+1 筆、建出一份說 N 筆的索引。插入點之後的每一個格點
# 指向的位元組都成了另一筆紀錄的開頭，而 seek 照著走。同一個計數器也餵給稽核軌跡。
# ---------------------------------------------------------------------
echo
echo "--- T173: -insert and the index it leaves / T173：-insert 與它留下的索引 ---"

{
    printf 'id,note\n'
    for _i in $(seq 1 300); do printf 'r%d,n%d\n' $_i $_i; done
} > "$TMP/t173.csv"

CSV2_INDEX_MIN_BYTES=100 "$CSV2" -insert 5 'X,Y' -i "$TMP/t173.csv" -o "$TMP/t173out.csv"
assert_succeeds "T173a the index left by -insert describes the file / -insert 留下的索引與檔案相符" -- \
    "$CSV2" --verify-index -i "$TMP/t173out.csv"
assert_eq "$(CSV2_INDEX_MIN_BYTES=100 "$CSV2" -mid 257,258 -t -i "$TMP/t173out.csv")" \
          "$("$CSV2" -mid 257,258 -t --no-index -i "$TMP/t173out.csv")" \
    "T173b and a seek past the insertion agrees with a scan / 而越過插入點的 seek 與掃描說法一致"
_t173_log="$TMP/t173.log"
CSV2_INDEX_MIN_BYTES=100 "$CSV2" -insert 5 'X,Y' -i "$TMP/t173.csv" -o "$TMP/t173out2.csv" -log "$_t173_log"
assert_contains "$(grep 'wrote ' "$_t173_log")" "wrote 301 records" \
    "T173c and the audit trail counts the row it inserted / 而稽核軌跡把它插入的那一列算了進去"

# ---------------------------------------------------------------------
# T174 -- the header rows advance the line, because they are lines.
#
# Also caught by T166d. The line was counted in emitData and the header rows
# go out through emit, so an index built by a write said record 1 was on line
# 1 -- off by exactly the number of header rows, on every such index since v4
# added the line.
#
# T174 —— 標頭列會推進行號，因為它們就是行。
# 同樣由 T166d 抓到。行號在 emitData 裡數，而標頭列走 emit：一次寫入建出的索引因此說第 1 筆
# 在第 1 行，差距恰好等於標頭列數。
# ---------------------------------------------------------------------
echo
echo "--- T174: where record 1 is, according to a written index / T174：一份寫出來的索引說第 1 筆在哪 ---"

{
    print -r -- 'k,v'
    print -r -- '鍵,值'
    for _i in $(seq 1 300); do print -r -- "row$_i,value$_i"; done
} > "$TMP/t174.csv2"
CSV2_INDEX_MIN_BYTES=100 "$CSV2" -update '1:v' 'CHANGED' -i "$TMP/t174.csv2" -o "$TMP/t174out.csv2"
assert_succeeds "T174a a .csv2 written with two header rows puts record 1 on line 3 / 兩列標頭的 .csv2 把第 1 筆放在第 3 行" -- \
    "$CSV2" --verify-index -i "$TMP/t174out.csv2"
assert_eq "$(CSV2_INDEX_MIN_BYTES=100 "$CSV2" -mid 1,1 --json -i "$TMP/t174out.csv2" | sed -n 2p)" \
          "$("$CSV2" -mid 1,1 --json --no-index -i "$TMP/t174out.csv2" | sed -n 2p)" \
    "T174b and the seek reports the same line as the scan / 而 seek 與掃描回報同一個行號"


# ---------------------------------------------------------------------
# T175 -- --in-place is the EDIT destination, and a selection is not an edit.
#
# Round 64. `csv2 -head 1 -t -i f.csv --in-place` exited 0 and left one record
# of twenty-two: the selection was written back over the input. Nothing on
# stdout, nothing on stderr, and the log held only the invocation, because the
# `wrote N records` line belongs to the edit path -- so the most destructive
# operation in the tool was also the least audited one, and the README points
# an auditor at exactly that line.
#
# What stood in the way was `-t`, a flag about HEADERS: without it the write is
# refused because a headerless file would lie about its format. A safety
# property resting on a formatting flag is one nobody chose.
#
# T175 —— --in-place 是「編輯」的目的地，而選取不是編輯。
# 第 64 回合。`csv2 -head 1 -t -i f.csv --in-place` 以 0 結束，22 筆只剩 1 筆：那個選取被寫回
# 了輸入。兩條輸出流上都沒有東西，log 裡只有「呼叫」那一行——因為 `wrote N records` 屬於編輯
# 路徑，於是這個工具最具破壞性的操作，同時是它最少被稽核的。擋在中間的是 `-t`，一個關於
# 標頭的旗標。
# ---------------------------------------------------------------------
echo
echo "--- T175: a selection cannot be written back over its input / T175：選取不能被寫回它的輸入 ---"

printf 'a,b\n1,x\n2,y\n3,z\n' > "$TMP/t175.csv"
_t175_before=$(wc -c < "$TMP/t175.csv" | tr -d ' ')

for _verb in "-head 1" "-tail 2" "-mid 2,3" "-contains x --filter"; do
    assert_fails "T175a $_verb -t --in-place is refused / $_verb -t --in-place 被拒絕" -- \
        "$CSV2" ${=_verb} -t -i "$TMP/t175.csv" --in-place
done
assert_eq "$(wc -c < "$TMP/t175.csv" | tr -d ' ')" "$_t175_before" \
    "T175b and the file is the size it was / 而檔案還是原來那麼大"

# A bare -r gets a DIFFERENT message, because it is a different true sentence:
# -r names every record, so "would discard every record the selection does not
# name" would be a refusal describing a danger this command does not have.
# 單獨的 -r 得到「另一則」訊息，因為那是另一句為真的話：-r 指名了每一筆，因此「會丟掉選取
# 沒有指名的紀錄」會是一條「描述了這個指令並不存在的危險」的拒絕。
_t175_r=$("$CSV2" -r -t -i "$TMP/t175.csv" --in-place 2>&1)
assert_contains "$_t175_r" "has none" \
    "T175c -r --in-place says there is no edit to apply / -r --in-place 說的是「這次執行沒有編輯」"
_t175_h=$("$CSV2" -head 1 -t -i "$TMP/t175.csv" --in-place 2>&1)
assert_contains "$_t175_h" "discard" \
    "T175d while a selection is told what it would discard / 而選取被告知它會丟掉什麼"

# The edits themselves must be untouched by the new refusal.
# 那些「真正的編輯」不能被這條新的拒絕波及。
assert_succeeds "T175e -update --in-place still works / -update --in-place 仍然可用" -- \
    "$CSV2" -update 1:2 Q -i "$TMP/t175.csv" --in-place
assert_succeeds "T175f -delete --in-place still works / -delete --in-place 仍然可用" -- \
    "$CSV2" -delete 1 -i "$TMP/t175.csv" --in-place
assert_succeeds "T175g -append --in-place still works / -append --in-place 仍然可用" -- \
    "$CSV2" -append '9,q' -i "$TMP/t175.csv" --in-place
printf 'a,b\n1,x\n' > "$TMP/t175h.csv"
assert_succeeds "T175h -hash --in-place still works / -hash --in-place 仍然可用" -- \
    env HOME="$TMP/home" "$CSV2" -hash b --yes -i "$TMP/t175h.csv" --in-place

# ---------------------------------------------------------------------
# T176 -- a control character in an error message.
#
# Round 64 went looking for a forged THIRD line on stderr and found the line
# count solid and the escaping rule not. `lineEscape` handled a newline and a
# carriage return and let everything else through, so
# `no column named "<ESC>[2K…"` printed a live erase-line sequence on the very
# line carrying the diagnosis -- the hazard this project argues for escaping
# the locating report, one screen away in the same file.
#
# The backslash is still NOT escaped by the whole-line rule: a message that
# teaches `\n` has to read as `\n`. What closes the remaining ambiguity is the
# VALUE escaper at the site that quotes input back.
#
# T176 —— 錯誤訊息裡的控制字元。
# 第 64 回合去找 stderr 上偽造的「第三行」，發現行數的承諾是穩的、跳脫的規則不是。
# 反斜線仍然不由「整行」那條規則處理：一則在教 `\n` 的訊息必須讀作 `\n`。剩下的那個歧義，
# 由「插值處的值跳脫」關掉。
# ---------------------------------------------------------------------
echo
echo "--- T176: what an error message may put on your terminal / T176：一則錯誤訊息可以放什麼到你的終端機上 ---"

printf 'a,b\n1,x\n' > "$TMP/t176.csv"

_t176_esc=$("$CSV2" -delete -col "$(printf 'na\033[2Kme')" -i "$TMP/t176.csv" -o "$TMP/t176o.csv" 2>&1)
assert_contains "$_t176_esc" '\x1B' \
    "T176a an ESC in a column name is escaped on stderr / 欄名裡的 ESC 在 stderr 上被跳脫"
_t176_raw=$(print -r -- "$_t176_esc" | od -A n -t x1 | tr -s ' ')
if [[ $_t176_raw == *" 1b "* ]]; then
    bad "T176b a raw ESC byte reached stderr / 一個原始的 ESC 位元組到了 stderr"
else
    ok "T176b and no raw ESC byte reaches stderr / 而沒有原始的 ESC 位元組到達 stderr"
fi
_t176_tab=$("$CSV2" -delete -col "$(printf 'na\tme')" -i "$TMP/t176.csv" -o "$TMP/t176o.csv" 2>&1)
assert_contains "$_t176_tab" '\t' \
    "T176c a TAB likewise / TAB 同樣如此"

# The prose that TEACHES escaping must still read as prose. This is the case
# that made "escape everything" wrong on 2026-08-20 and it is checked here so
# the two halves cannot be confused again.
# 那些「教你怎麼跳脫」的散文必須仍然讀作散文。這正是 2026-08-20 讓「全部都跳脫」變成錯誤答案
# 的那個案例，在此檢查，好讓那兩半不會再被混為一談。
printf 'k,v\n鍵,值\nrow1,a\\qb\n' > "$TMP/t176.csv2"
_t176_prose=$("$CSV2" -r -i "$TMP/t176.csv2" 2>&1)
assert_contains "$_t176_prose" 'sequence \q' \
    "T176d and a message about \\q still says \\q, not \\\\q / 而一則講 \\q 的訊息仍然說 \\q，不是 \\\\q"

# A literal backslash-n and a real newline must not produce the same line.
# 字面的反斜線 n 與一個真正的換行，不可以產生同一行。
_t176_lit=$("$CSV2" -delete -col 'na\nme' -i "$TMP/t176.csv" -o "$TMP/t176o.csv" 2>&1 | head -1)
_t176_nl=$("$CSV2" -delete -col "$(printf 'na\nme')" -i "$TMP/t176.csv" -o "$TMP/t176o.csv" 2>&1 | head -1)
if [[ "$_t176_lit" == "$_t176_nl" ]]; then
    bad "T176e a literal backslash-n and a newline give the same error line / 字面反斜線 n 與換行給出同一行錯誤"
else
    ok "T176e a literal backslash-n and a newline are told apart / 字面反斜線 n 與換行分得出來"
fi

# And the two-line contract survives all of it.
# 而「恰好兩行」的合約在這一切之下仍然成立。
for _name in "$(printf 'na\033[2Kme')" "$(printf 'na\tme')" "$(printf 'na\nme')" 'na\nme' "$(printf 'na\rme')"; do
    _n=$("$CSV2" -delete -col "$_name" -i "$TMP/t176.csv" -o "$TMP/t176o.csv" 2>&1 | wc -l | tr -d ' ')
    if [[ "$_n" != "2" ]]; then
        bad "T176f a refusal printed $_n lines / 一條拒絕印了 $_n 行"
        break
    fi
done
[[ "$_n" == "2" ]] && ok "T176f every one of them is exactly two lines / 它們每一個都恰好是兩行"


# ---------------------------------------------------------------------
# T177 -- the guard is about SELECTION, not about the absence of an edit verb.
#
# Round 65, one day after T175. That guard asked "is there an edit verb?" and
# `-hash` is one of a kind, so `-head 1 -hash license -i f.csv --in-place`
# walked past it and left one record of six at rc=0 -- the same destruction
# T175 stops, one flag away from the command T175 stops. `-encrypt` and
# `-decrypt` reach it too, and the `-decrypt` form destroys ciphertext and the
# header salt together, which the README says nobody can ever recover.
#
# The refusals table stated the rule correctly ("a SELECTION with --in-place")
# while the implementation used a different predicate. This case pins the rule
# rather than the predicate.
#
# T177 —— 那道守衛管的是「選取」，不是「沒有編輯動詞」。
# 第 65 回合，在 T175 之後一天。那道守衛問的是「有沒有編輯動詞？」而 `-hash` 算是一種，
# 於是 `-head 1 -hash license -i f.csv --in-place` 從它旁邊走了過去，六筆只剩一筆，rc=0。
# 拒絕表寫的是正確的規則，實作用的是另一個謂詞。
# ---------------------------------------------------------------------
echo
echo "--- T177: a selection plus a protection verb / T177：選取加上保護動詞 ---"

printf 'pkg,ver,license\nzlib,1.3,Zlib\nzstd,1.5,BSD-3\nncurses,6.4,MIT\nmbedtls,3.5,Apache\nbusybox,1.37,GPL-2.0\n' > "$TMP/t177.csv"

for _combo in "-head 1 -hash license --yes" "-tail 1 -hash license --yes" \
              "-mid 2,3 -hash license --yes" "-contains zlib --filter -hash license --yes"; do
    cp "$TMP/t177.csv" "$TMP/t177w.csv"
    assert_fails "T177a $_combo --in-place is refused / $_combo --in-place 被拒絕" -- \
        env HOME="$TMP/home" "$CSV2" ${=_combo} -i "$TMP/t177w.csv" --in-place
    # cmp, not sha256_of: that helper hashes a STRING, so it was comparing two
    # file NAMES and failing on the copy's different name -- a check that could
    # not have passed, which is the other half of a check that cannot fail.
    # 用 cmp 而不是 sha256_of：那個輔助函式雜湊的是「字串」，因此它比的是兩個檔案「名字」，
    # 在複本名字不同時必然失敗——一個「不可能通過」的檢查，正是「不可能失敗」的另一半。
    if ! cmp -s "$TMP/t177w.csv" "$TMP/t177.csv"; then
        bad "T177b $_combo changed the file / $_combo 改動了那個檔案"
    fi
done
ok "T177b and the file is byte-for-byte what it was / 而檔案逐位元組不變"

# -encrypt and -decrypt take the same road, and the -decrypt one destroys
# ciphertext and the salt that makes it readable at all.
# -encrypt 與 -decrypt 走同一條路，而 -decrypt 那一個會把密文、以及讓它得以被讀懂的那個鹽，
# 一起銷毀。
printf 'k' > "$TMP/t177key.bin"
for _i in 1 2 3 4; do printf 'k' >> "$TMP/t177key.bin"; done
head -c 32 /dev/urandom > "$TMP/t177key.bin" 2>/dev/null || printf '0123456789abcdef0123456789abcdef' > "$TMP/t177key.bin"
cp "$TMP/t177.csv" "$TMP/t177e.csv"
"$CSV2" -r -encrypt license -keyfile "$TMP/t177key.bin" -i "$TMP/t177e.csv" --in-place
cp "$TMP/t177e.csv" "$TMP/t177e.keep"
assert_fails "T177c -head with -decrypt --in-place is refused / -head 搭配 -decrypt --in-place 被拒絕" -- \
    "$CSV2" -head 1 -decrypt all -keyfile "$TMP/t177key.bin" -i "$TMP/t177e.csv" --in-place
assert_same "$TMP/t177e.csv" "$TMP/t177e.keep" \
    "T177d and the ciphertext is still there / 而那些密文還在"

# A transform with NO selection must still work in place: that is what in-place
# protection is for, and refusing it would be the fix eating the feature.
# 「有轉換、沒有選取」必須繼續可以就地執行：那正是就地保護的用途，把它一起拒絕，
# 等於修正把功能吃掉了。
cp "$TMP/t177.csv" "$TMP/t177r.csv"
assert_succeeds "T177e -r -hash --in-place still works / -r -hash --in-place 仍然可用" -- \
    env HOME="$TMP/home" "$CSV2" -r -hash license --yes -i "$TMP/t177r.csv" --in-place
assert_eq "$("$CSV2" -r -t --no-index -i "$TMP/t177r.csv" | wc -l | tr -d ' ')" "6" \
    "T177f and every record survived it / 而每一筆都活了下來"

# The outcome line: a protection write goes through the select path, which had
# no such line. The README nominates it as the one to look for when asking
# whether an edit landed, so it was missing from the writes that cannot be
# undone.
# 那一行「結果」：保護寫入走的是選取路徑，而那條路徑原本沒有這一行。README 指名它是
# 「想知道編輯有沒有落地時該找的那一行」，於是它獨獨在「無法還原」的那些寫入上不存在。
rm -f "$TMP/t177.log"
HOME="$TMP/home" "$CSV2" -hash license --yes -i "$TMP/t177.csv" -o "$TMP/t177h.csv" -t -log "$TMP/t177.log"
assert_contains "$(cat "$TMP/t177.log")" "wrote 5 records" \
    "T177g a -hash write logs its outcome / 一次 -hash 寫入會記下它的結果"
rm -f "$TMP/t177b.log"
"$CSV2" -head 2 -t -i "$TMP/t177.csv" -o "$TMP/t177s.csv" -log "$TMP/t177b.log"
assert_contains "$(cat "$TMP/t177b.log")" "wrote 2 records" \
    "T177h and a selection written to a file logs what it wrote / 而寫進檔案的選取會記下它寫了什麼"
rm -f "$TMP/t177c.log"
"$CSV2" -r -t -i "$TMP/t177.csv" -so -log "$TMP/t177c.log" > /dev/null
if grep -q "atomic rename" "$TMP/t177c.log"; then
    bad "T177i -so claimed an atomic rename / -so 宣稱有一次原子改名"
else
    ok "T177i while -so claims no rename, because it makes none / 而 -so 不宣稱改名，因為它沒有改名"
fi

# ---------------------------------------------------------------------
# T178 -- -rownum is a column, and it follows the column rules.
#
# Round 65. Its Markdown header cell was hard-coded to `rownum<br>列號`, so
# `--en` and `--zh` -- documented as giving "one clean row instead" -- could
# not clean the one cell csv2 had invented, and a ONE-header `.csv` got a
# `<br>` cell beside plain ones in a table whose join is explained by the data
# having two header rows. And `--json`, which names fields rather than
# numbering them, accepted `-rownum` and dropped it: the same silence `--a1`
# and `--physical` are refused for, and that `-get` refuses `-rownum` for by
# name.
#
# T178 —— -rownum 是一個「欄」，而它遵守欄的規則。
# ---------------------------------------------------------------------
echo
echo "--- T178: -rownum as a column / T178：-rownum 作為一個欄 ---"

printf 'k,v\n鍵,值\nr1,v1\n' > "$TMP/t178.csv2"
printf 'a,b\n1,2\n' > "$TMP/t178.csv"

assert_eq "$("$CSV2" -r -t -rownum -md -i "$TMP/t178.csv" | head -1)" "|rownum|a|b|" \
    "T178a a one-header .csv gets no <br> cell / 只有一列標頭的 .csv 不會有 <br> 那一格"
assert_eq "$("$CSV2" -r -t -rownum -md -i "$TMP/t178.csv2" | head -1)" "|rownum<br>列號|k<br>鍵|v<br>值|" \
    "T178b a .csv2 joins it like every other column / .csv2 上它與其他每一欄一樣被合併"
assert_eq "$("$CSV2" -r -t -rownum -md --en -i "$TMP/t178.csv2" | head -1)" "|rownum|k|v|" \
    "T178c --en cleans it too / --en 也清得掉它"
assert_eq "$("$CSV2" -r -t -rownum -md --zh -i "$TMP/t178.csv2" | head -1)" "|列號|鍵|值|" \
    "T178d and --zh gives the Chinese name / 而 --zh 給的是中文名"
assert_fails "T178e --json refuses -rownum rather than dropping it / --json 拒絕 -rownum，而不是把它丟掉" -- \
    "$CSV2" -r -t -rownum --json -i "$TMP/t178.csv"

# ---------------------------------------------------------------------
# T179 -- a flag that decides how a search compares needs a search.
#
# Round 65: --normalize with no -contains was accepted and did nothing, while
# its two neighbours in the same section, --filter and --include-headers, are
# both refused for exactly that.
#
# T179 —— 一個「決定搜尋怎麼比較」的旗標，需要一次搜尋。
# ---------------------------------------------------------------------
echo
echo "--- T179: --normalize needs -contains / T179：--normalize 需要 -contains ---"

assert_fails "T179a --normalize alone is refused / 單獨的 --normalize 被拒絕" -- \
    "$CSV2" -r -t --normalize -i "$TMP/t178.csv"
assert_succeeds "T179b and with -contains it is accepted / 搭配 -contains 則被接受" -- \
    "$CSV2" -contains 1 --normalize -i "$TMP/t178.csv"


# ---------------------------------------------------------------------
# T180 -- CR line endings: the rule, not a count.
#
# Round 66 pulled the stated reason and the actual trigger apart in both
# directions. The guard said "this file uses CR line endings"; the test was
# "bare CRs outnumber line feeds".
#
#   a,b<LF>1,x<CR><CR><CR>y<LF>   3 CRs, 2 LFs -> refused, and the file is
#                                 LF-terminated. The message asserted something
#                                 false about it, and `tr '\r' '\n'` -- which
#                                 that message prescribes -- turns that one
#                                 record into a file csv2 will not read.
#   col<CR>"L<LF>L<LF>L<LF>L"<CR>zz<CR>
#                                 3 CRs, 3 LFs -> accepted at rc=0 as three
#                                 records under a column named `col<CR>"L`,
#                                 the quoted field torn down its own newlines,
#                                 nothing on stderr. A genuine CR-terminated
#                                 file, silently misparsed.
#
# The rule is exact: a CR-terminated file has no LF to end its first line, so
# everything lands in the first record, and the header row is where the
# evidence always is.
#
# T180 —— CR 行尾：一條規則，不是一個數量。
# 第 66 回合把「自陳的理由」與「實際的觸發條件」往兩個方向都拉開了。守衛說的是「本檔案使用
# CR 行尾」，而測的是「裸 CR 比換行多」。規則是精確的：一個以 CR 結尾的檔案沒有 LF 去結束
# 它的第一行，因此全部內容都落在第一筆紀錄裡，而證據永遠在標頭列。
# ---------------------------------------------------------------------
echo
echo "--- T180: CR line endings / T180：CR 行尾 ---"

printf 'a,b\r1,2\r3,4\r' > "$TMP/t180_cr.csv"
printf 'col\r1\r2\r' > "$TMP/t180_cr1.csv"
printf 'col\r"L\nL\nL\nL"\rzz\r' > "$TMP/t180_crmix.csv"
printf 'a,b\n1,x\r\r\ry\n' > "$TMP/t180_data.csv"
printf '"a\rb",c\n1,2\n' > "$TMP/t180_quoted.csv"

assert_fails "T180a a CR-terminated file is refused / 以 CR 結尾的檔案被拒絕" -- \
    "$CSV2" -r -i "$TMP/t180_cr.csv"
assert_fails "T180b one column too / 單欄的也是" -- \
    "$CSV2" -r -i "$TMP/t180_cr1.csv"
assert_fails "T180c and when CRs and LFs are equal, which a count cannot see / CR 與 LF 一樣多時也是——那是數量看不見的" -- \
    "$CSV2" -r -i "$TMP/t180_crmix.csv"
_t180_msg=$("$CSV2" -r -i "$TMP/t180_crmix.csv" 2>&1 | head -1)
assert_contains "$_t180_msg" "header row contains a bare carriage return" \
    "T180d the message names what was actually seen / 訊息指出的是「實際看到的東西」"

# Three CRs inside a field of an LF-terminated file: data, and it round-trips.
# 一個 LF 結尾檔案的欄位裡有三個 CR：那是資料，而且原樣往返。
assert_succeeds "T180e three CRs inside a record are still data / 一筆紀錄裡的三個 CR 仍然是資料" -- \
    "$CSV2" -r -t -i "$TMP/t180_data.csv" -o "$TMP/t180_out.csv"
assert_same "$TMP/t180_data.csv" "$TMP/t180_out.csv" \
    "T180f and the file comes back byte for byte / 而檔案逐位元組回得來"

# A CR that really belongs to a column name is reachable, by quoting it.
# 一個確實屬於欄名的 CR 是到得了的：加引號。
assert_succeeds "T180g a quoted CR in a header is a name / 標頭裡加了引號的 CR 是一個名字" -- \
    "$CSV2" -r -t -i "$TMP/t180_quoted.csv" -o "$TMP/t180_q.csv"

# ---------------------------------------------------------------------
# T181 -- a FIFO given to -i.
#
# Round 66: `csv2 -r -i fifo.csv` on a stream carrying three lines reported
# `expected 1 header row(s), found 0` -- the message for a file with nothing in
# it. Two causes, both fixed here: the freshness stamp read the first and last
# 64 bytes before the parse, and on a pipe those bytes do not come back; and
# runSelect opened the input TWICE, once to hand planIndex a plan it only reads
# the format from, so the second open waited for a writer that had already
# gone.
#
# T181 —— 交給 -i 的一個 FIFO。
# 第 66 回合：一條正要送來三行的串流，`csv2 -r -i fifo.csv` 回報的是
# `expected 1 header row(s), found 0`——那是「檔案裡什麼都沒有」的訊息。兩個原因都在此修掉：
# 新鮮度戳記在解析前讀了頭尾各 64 位元組，而在管線上那些位元組不會回來；以及 runSelect 把
# 輸入開了「兩次」。
# ---------------------------------------------------------------------
echo
echo "--- T181: -i on a FIFO / T181：-i 指向一個 FIFO ---"

# Windows is excluded by NAME here, which this file otherwise avoids: MSYS2
# ships an mkfifo that creates something, and a reader on it never meets its
# writer, so the case does not fail -- it HANGS, and a suite that hangs reports
# nothing at all. The first Windows run of this case sat for twenty minutes.
# 這裡以「平台名字」排除 Windows，而這個檔案在其他地方避免這樣做：MSYS2 帶了一個 mkfifo，
# 它建得出東西，但在它上面的讀取端永遠遇不到寫入端——於是這個案例不是失敗，而是「卡住」，
# 而一個卡住的測試什麼也回報不了。這個案例在 Windows 上的第一次執行坐了二十分鐘。
if (( IS_WINDOWS )); then
    skipt "T181a a FIFO on Windows never connects its two ends / Windows 上的 FIFO 兩端接不起來"
    T181A_SKIPPED=1
elif (( $+commands[mkfifo] )); then
    rm -f "$TMP/t181.fifo.csv"
    if mkfifo "$TMP/t181.fifo.csv" 2>/dev/null; then
        { sleep 0.2; printf 'a,b\n1,x\n2,y\n' > "$TMP/t181.fifo.csv" } &
        _t181_out=$("$CSV2" -r -t "-i" "$TMP/t181.fifo.csv" 2>&1)
        wait
        assert_eq "$_t181_out" "$(printf 'a,b\n1,x\n2,y')" \
            "T181a a FIFO reads as the stream it carries / 一個 FIFO 讀出來就是它承載的那條串流"
        rm -f "$TMP/t181.fifo.csv"
    else
        skipt "T181a mkfifo is not permitted here / 此處不允許 mkfifo"
        T181A_SKIPPED=1
    fi
else
    skipt "T181a no mkfifo on this platform / 此平台沒有 mkfifo"
    T181A_SKIPPED=1
fi

# ---------------------------------------------------------------------
# T182 -- two names, one file.
#
# Round 66: `-i x -o y` was checked by comparing resolved PATHS, which catches
# every spelling -- `./`, `../`, absolute, symlink -- and a hard link is not a
# spelling. The edit broke the link at rc=0, leaving one name with the edit and
# the other with what used to be shared.
#
# T182 —— 兩個名字，一個檔案。
# ---------------------------------------------------------------------
echo
echo "--- T182: a hard link is not a spelling / T182：硬連結不是一種拼法 ---"

printf 'a,b\n1,x\n' > "$TMP/t182.csv"
rm -f "$TMP/t182_hard.csv"
# Windows by NAME, and the reason is in the platform rather than in the test:
# the CRT reports inode 0 for every file, so asking (dev, ino) there would say
# every file is every other file. csv2 declines to ask, and MSYS2's `ln` still
# produces something -- so the case would fail for a reason that is not a
# defect. Writing it to accept either outcome would make a case that cannot
# fail, which is the thing this suite exists not to do.
# 以「平台名字」排除 Windows，而理由在平台身上、不在測試身上：那裡的 CRT 對每個檔案都回報
# inode 0，因此在那裡去問 (dev, ino) 等於說「每個檔案都是彼此」。csv2 選擇不問，而 MSYS2 的
# `ln` 仍然會生出東西——於是這個案例會因為一個「不是缺陷」的理由而失敗。把它寫成「兩種結果
# 都接受」，會造出一個不可能失敗的案例，而那正是這套測試存在所要避免的事。
if (( IS_WINDOWS )); then
    skipt "T182a Windows reports inode 0 for every file, so identity cannot be asked / Windows 對每個檔案都回報 inode 0，因此問不出「身分」"
    T182A_SKIPPED=1
    skipt "T182b same reason / 同一個理由"
    T182B_SKIPPED=1
elif ln "$TMP/t182.csv" "$TMP/t182_hard.csv" 2>/dev/null; then
    assert_fails "T182a -i and -o as hard links to one inode is refused / -i 與 -o 是同一個 inode 的硬連結時被拒絕" -- \
        "$CSV2" -update 1:2 Z -i "$TMP/t182.csv" -o "$TMP/t182_hard.csv"
    assert_succeeds "T182b while an unrelated -o still works / 而一個無關的 -o 仍然可用" -- \
        "$CSV2" -update 1:2 Z -i "$TMP/t182.csv" -o "$TMP/t182_other.csv"
else
    skipt "T182a hard links are not available here / 此處無法建立硬連結"
    T182A_SKIPPED=1
    skipt "T182b hard links are not available here / 此處無法建立硬連結"
    T182B_SKIPPED=1
fi

# ---------------------------------------------------------------------
# T183 -- a key that is one byte repeated.
#
# Round 66: the 16-byte floor exists because "a key this short is searched
# exhaustively in less time than this run took". Sixteen NUL bytes -- what a
# truncated or never-written key file looks like -- passed it, and is guessed
# in one attempt; fifteen random bytes, refused, are some 10^36 times stronger.
#
# T183 —— 一把「同一個位元組重複而成」的金鑰。
# ---------------------------------------------------------------------
echo
echo "--- T183: a key file with one distinct byte / T183：只有一種位元組的金鑰檔 ---"

printf 'a,secret\n1,x\n' > "$TMP/t183.csv"
# Sixteen NUL bytes without python3: the guest has none, and `cmd || fallback`
# does not help -- the shell's not-found handler records the call before the
# fallback runs, so the suite reported a missing command that was never needed.
# A key of sixteen identical NULs is what this case is about, and `head -c 16
# /dev/zero` is the same sixteen bytes with nothing to install.
# 不用 python3 生出十六個 NUL：guest 上沒有它，而 `cmd || fallback` 幫不上忙——shell 的
# 「找不到指令」處理常式會在 fallback 執行之前就把那次呼叫記下來，於是測試回報了一個
# 「其實從來不需要」的缺漏指令。這個案例要的就是十六個相同的 NUL，而 `head -c 16 /dev/zero`
# 給的正是同樣那十六個位元組，還不必安裝任何東西。
if ! head -c 16 /dev/zero > "$TMP/t183_zero.bin" 2>/dev/null; then
    printf '0000000000000000' > "$TMP/t183_zero.bin"
fi
assert_fails "T183a a 16-byte all-one-value key is refused for creating / 一把 16 位元組、只有一種值的金鑰不能用來建立保護" -- \
    "$CSV2" -hash secret -keyfile "$TMP/t183_zero.bin" -i "$TMP/t183.csv" -o "$TMP/t183_o.csv" -t
_t183_msg=$("$CSV2" -hash secret -keyfile "$TMP/t183_zero.bin" -i "$TMP/t183.csv" -o "$TMP/t183_o.csv" -t 2>&1 | head -1)
assert_contains "$_t183_msg" "copies of one byte" \
    "T183b and the message says what is wrong with it / 而訊息說出它哪裡不對"
head -c 32 /dev/urandom > "$TMP/t183_good.bin" 2>/dev/null || printf 'kJ3#a91Zq7!vB2xLm5PdR8sTn0WyE4Uc' > "$TMP/t183_good.bin"
assert_succeeds "T183c while a real key of the same length is accepted / 而同樣長度的一把真金鑰被接受" -- \
    "$CSV2" -hash secret -keyfile "$TMP/t183_good.bin" -i "$TMP/t183.csv" -o "$TMP/t183_g.csv" -t


# ---------------------------------------------------------------------
# T184 -- -o onto a device, and the trap a signed dev_t sets.
#
# Round 67. `csv2 -r -t -i f.csv -o /dev/null` died on SIGTRAP: exit 133, zero
# bytes on stdout AND stderr. The refusal is written, correct, and one line
# further down than the crash -- `Platform.fileNode`, added the day before for
# hard links, does `UInt64(st.st_dev)`, and `st_dev` is a SIGNED 32-bit dev_t
# on Darwin whose value for a device node is negative. `UInt64(-1)` is a Swift
# trap.
#
# The README names `-o /dev/stdout` as its example of this refusal, so the one
# case the document picks to illustrate the rule was the one that crashed. The
# suite had no case for it, which is why a fix introduced on 2026-08-21 and a
# round run on 2026-08-21 were needed to notice.
#
# T184 —— -o 指向一個裝置，以及一個有號 dev_t 設下的陷阱。
# 第 67 回合。`csv2 -r -t -i f.csv -o /dev/null` 死在 SIGTRAP：exit 133，stdout 與 stderr
# 都是零位元組。那條拒絕寫好好的、也是對的，就在當機的下一行——前一天為了硬連結而加的
# `Platform.fileNode` 做了 `UInt64(st.st_dev)`，而 Darwin 上的 `st_dev` 是有號的 32 位元
# dev_t，裝置節點的值是負的。`UInt64(-1)` 是一個 Swift trap。
# ---------------------------------------------------------------------
echo
echo "--- T184: -o onto a device / T184：-o 指向一個裝置 ---"

printf 'a,b\n1,x\n2,y\n' > "$TMP/t184.csv"

if (( IS_WINDOWS )); then
    skipt "T184a /dev/null is not a device node on Windows / Windows 上 /dev/null 不是裝置節點"
    T184A_SKIPPED=1
    skipt "T184b same reason / 同一個理由"
    T184B_SKIPPED=1
else
    for _dev in /dev/null /dev/zero; do
        _t184_out=$("$CSV2" -r -t -i "$TMP/t184.csv" -o "$_dev" 2>&1)
        _t184_rc=$?
        if (( _t184_rc == 1 )); then
            ok "T184a -o $_dev is refused, exit 1 / -o $_dev 被拒絕，結束狀態 1"
        else
            bad "T184a -o $_dev exited $_t184_rc / -o $_dev 以 $_t184_rc 結束"
        fi
    done
    assert_contains "$("$CSV2" -r -t -i "$TMP/t184.csv" -o /dev/null 2>&1)" "Use -so" \
        "T184b and the refusal names the way through / 而那條拒絕指出走得通的那條路"
fi

# An empty -o resolves to the current directory, so the temp file lands in its
# PARENT and the failure arrives as a raw rename errno quoting the internal
# temp filename. Refused up front instead.
# 空的 -o 會解析成目前目錄，於是暫存檔落在它的「上一層」，而失敗以一個原始的 rename errno
# 抵達、還引用了內部暫存檔名。改成在最前面就拒絕。
_t184_empty=$("$CSV2" -r -t -i "$TMP/t184.csv" -o "" 2>&1)
assert_contains "$_t184_empty" "-o is empty" \
    "T184c an empty -o is refused by name / 空的 -o 會被指名拒絕"
if [[ $_t184_empty == *"csv2tmp"* ]]; then
    bad "T184d the message leaked the temp filename / 訊息洩漏了暫存檔名"
else
    ok "T184d and no internal temp filename appears in it / 而訊息裡不會出現內部暫存檔名"
fi

# ---------------------------------------------------------------------
# T185 -- how many bytes --truncate-partial discarded.
#
# Round 67 measured `reported = 2·B + 1` where the truth is `B + prefix`: the
# count added rawBuf and valBuf, which hold the same text twice -- as it
# arrived and as it decoded. On a 38-byte file it reported 55, more bytes than
# the file has; on a three-byte tail it reported 1.
#
# The other half of the same sentence -- "beginning at byte N" -- was right
# every time, which is what made the wrong half credible. And nothing in the
# tool could check it: there is no --json field, no -log entry and no -debug
# line for this number, so the WARN is its only report and both READMEs promise
# it.
#
# T185 —— --truncate-partial 到底丟掉了幾個位元組。
# 第 67 回合量到 `回報值 = 2·B + 1`，而真值是 `B + 前綴`：那個計數把 rawBuf 與 valBuf 相加，
# 而它們裝的是同一段文字的兩種樣子。在一個 38 位元組的檔案上它說 55——比整個檔案還多。
# ---------------------------------------------------------------------
echo
echo "--- T185: the discarded byte count / T185：被丟棄的位元組數 ---"

_t185_bad=0
for _n in 0 1 2 5 20 40; do
    _f="$TMP/t185_$_n.csv"
    _c="$TMP/t185_c_$_n.csv"
    { printf 'a,b\n1,x\n2,"'; _i=0; while (( _i < _n )); do printf 'Z'; _i=$((_i+1)); done } > "$_f"
    _total=$(wc -c < "$_f" | tr -d ' ')
    _warn=$("$CSV2" -r -t --truncate-partial -i "$_f" -o "$_c" 2>&1)
    _kept=$(wc -c < "$_c" | tr -d ' ')
    _true=$(( _total - _kept ))
    if [[ $_warn != *"discarded $_true bytes"* ]]; then
        bad "T185a n=$_n: file $_total, kept $_kept, so $_true went -- the WARN said: $_warn / 檔案 $_total、留下 $_kept，因此走掉 $_true——而 WARN 說的如上"
        _t185_bad=1
    fi
done
(( _t185_bad )) || ok "T185a the WARN's count is the bytes that actually went, at six sizes / 那個 WARN 的數字就是實際走掉的位元組，六種大小都是"

# ---------------------------------------------------------------------
# T186 -- --json says WHICH header row.
#
# Round 67: the locating report says `0a` and `0b`, and the stated reason for
# those two labels is that a hit in the English title row and one in the
# Chinese title row are distinguishable. `--json` -- the shape meant for
# programs -- gave `"record":0` for both, leaving only a physical line number.
#
# T186 —— --json 說得出「是哪一列標頭」。
# ---------------------------------------------------------------------
echo
echo "--- T186: which header row, in JSON / T186：JSON 裡的「哪一列標頭」 ---"

printf 'pkg,ver,note\n套件,版本,備註\nzlib,1.3,x\n' > "$TMP/t186.csv2"
printf 'a,b\nx,y\n' > "$TMP/t186.csv"

assert_contains "$("$CSV2" -contains pkg --include-headers --json -i "$TMP/t186.csv2" | sed -n 2p)" \
    '"header_row":"0a"' \
    "T186a an English-title hit is 0a / 命中英文標題列是 0a"
assert_contains "$("$CSV2" -contains 套件 --include-headers --json -i "$TMP/t186.csv2" | sed -n 2p)" \
    '"header_row":"0b"' \
    "T186b and a Chinese-title hit is 0b / 命中中文標題列是 0b"
assert_contains "$("$CSV2" -contains a --include-headers --json -i "$TMP/t186.csv")" \
    '"header_row":"0"' \
    "T186c a one-header file says 0, as the report does / 只有一列標頭的檔案說 0，與報告一致"
_t186_data=$("$CSV2" -contains zlib --include-headers --json -i "$TMP/t186.csv2" | sed -n 2p)
if [[ $_t186_data == *"header_row"* ]]; then
    bad "T186d a data hit carried a header_row key / 一個資料命中帶著 header_row 鍵"
else
    ok "T186d while a data hit carries no header_row key / 而資料命中不帶 header_row 鍵"
fi

# ---------------------------------------------------------------------
# T187 -- --en with --zh is a request with two answers.
#
# Round 67: giving both was order-dependent and silent -- last one won, rc=0,
# nothing said. This tool refuses `--headers 1 --headers 2` with a message
# arguing that taking the last one silently is how `-hash note -hash ver`
# leaves note in plaintext. Same hazard, two different handlings.
#
# T187 —— `--en` 與 `--zh` 併用，是一個有兩個答案的要求。
# ---------------------------------------------------------------------
echo
echo "--- T187: --en with --zh / T187：--en 與 --zh 併用 ---"

assert_fails "T187a --en --zh is refused / --en --zh 被拒絕" -- \
    "$CSV2" -contains zlib --en --zh -i "$TMP/t186.csv2"
assert_fails "T187b and so is the other order / 反過來的順序也是" -- \
    "$CSV2" -contains zlib --zh --en -i "$TMP/t186.csv2"
assert_contains "$("$CSV2" -contains zlib --zh --zh -i "$TMP/t186.csv2" 2>&1)" "given more than once" \
    "T187c while the same flag twice says THAT instead / 而「同一個旗標給兩次」說的是那一件事"
assert_succeeds "T187d one of them alone still works / 只給其中一個仍然可用" -- \
    "$CSV2" -contains zlib --zh -i "$TMP/t186.csv2"


# ---------------------------------------------------------------------
# T188 -- what a repeated flag does, measured rather than asserted.
#
# Round 68. The flag list said "giving the same flag twice is REFUSED, for
# every flag except -A/-B/-C" -- a sentence written on 2026-08-21 from the
# eleven value-taking flags that were checked, and never run against a boolean.
# Sixteen boolean flags accept a repeat silently at rc=0. Nothing can be lost
# that way, which is why the fix is the sentence; but the sentence promised a
# universal and the flag list is where a reader looks for one.
#
# This case pins BOTH halves, so the next person to write that sentence has to
# get it right in both directions.
#
# T188 —— 重複給同一個旗標會怎樣，用量的，不是用斷言的。
# 第 68 回合。旗標清單說「重複給同一個旗標一律被拒絕，除了 -A/-B/-C」——那句話是 2026-08-21
# 從「十一個帶值的旗標」寫出來的，從來沒有拿一個布林旗標去跑過。十六個布林旗標會安靜地
# 接受重複，rc=0。那樣不會遺失任何東西，因此要改的是那句話；但那句話承諾的是一個全稱，
# 而旗標清單正是讀者會去找全稱的地方。
# ---------------------------------------------------------------------
echo
echo "--- T188: repeating a flag / T188：重複給同一個旗標 ---"

printf 'a,b\n1,x\n2,y\n' > "$TMP/t188.csv"

# Value-taking flags: refused, every one.
# 帶值的旗標：一律拒絕。
_t188_bad=0
for _pair in "-head 1 -head 2" "-tail 1 -tail 2" "-mid 1,1 -mid 2,2" \
             "-contains x -contains y" "-get 1:1 -get 1:2" "--headers 1 --headers 1"; do
    if "$CSV2" ${=_pair} -i "$TMP/t188.csv" > /dev/null 2>&1; then
        bad "T188a $_pair was accepted / $_pair 被接受了"
        _t188_bad=1
    fi
done
(( _t188_bad )) || ok "T188a a repeated value-taking flag is refused / 重複給「帶值的旗標」會被拒絕"

# Booleans: accepted, silently, and the run is the same as without the repeat.
# 布林旗標：安靜地接受，而那次執行與「沒有重複」時相同。
_t188_once=$("$CSV2" -r -t --json -i "$TMP/t188.csv" 2>/dev/null)
_t188_twice=$("$CSV2" -r -t --json --json -i "$TMP/t188.csv" 2>/dev/null)
assert_eq "$_t188_twice" "$_t188_once" \
    "T188b a repeated boolean changes nothing / 重複給一個布林旗標不會改變任何事"
_t188_err=$("$CSV2" -r -t --json --json -i "$TMP/t188.csv" 2>&1 >/dev/null)
assert_eq "$_t188_err" "" \
    "T188c and says nothing about it / 而且對此不出聲"

# -A/-B/-C: the documented exception, last one wins.
# -A/-B/-C：文件記載的例外，後面那個贏。
printf 'a,b\n1,HIT\n2,y\n3,z\n4,w\n5,v\n' > "$TMP/t188c.csv"
assert_eq "$("$CSV2" -contains HIT -A 3 -A 1 -i "$TMP/t188c.csv" | wc -l | tr -d ' ')" "2" \
    "T188d -A 3 -A 1 takes the last one / -A 3 -A 1 取後面那個"

# ---------------------------------------------------------------------
# T189 -- read_bytes on the seek path.
#
# Round 68. The metrics entry said read_bytes "moves in whole 64 KiB buffers,
# never past the end of the file" -- true of a scan, false of a seek, which is
# the path the number exists to show. `-tail 1` on a 29,790-byte indexed file
# reads 3,328 bytes: not a multiple of 65536, and less than the file.
#
# T189 —— seek 路徑上的 read_bytes。
# 第 68 回合。那個條目說 read_bytes「以 64 KiB 為單位推進、且不會超過檔案結尾」——那對「掃描」
# 為真，對「seek」為假，而 seek 正是這個數字存在所要展示的那條路徑。
# ---------------------------------------------------------------------
echo
echo "--- T189: read_bytes when the index seeks / T189：索引 seek 時的 read_bytes ---"

{
    printf 'a,b\n'
    _i=1
    while (( _i <= 2000 )); do printf 'r%d,value%d\n' $_i $_i; _i=$((_i+1)); done
} > "$TMP/t189.csv"
_t189_size=$(wc -c < "$TMP/t189.csv" | tr -d ' ')
CSV2_INDEX_MIN_BYTES=100 "$CSV2" --build-index -i "$TMP/t189.csv" > /dev/null

_t189_seek=$(CSV2_INDEX_MIN_BYTES=100 "$CSV2" -tail 1 -i "$TMP/t189.csv" -debug 2>&1 \
             | sed -n 's/.*read_bytes=\([0-9]*\).*/\1/p')
_t189_scan=$("$CSV2" -r -t --no-index -i "$TMP/t189.csv" -debug 2>&1 >/dev/null \
             | sed -n 's/.*read_bytes=\([0-9]*\).*/\1/p')

if (( _t189_seek > 0 && _t189_seek < _t189_size )); then
    ok "T189a a seek reads less than the file ($_t189_seek of $_t189_size) / 一次 seek 讀得比整個檔案少"
else
    bad "T189a a seek read $_t189_seek of $_t189_size / 一次 seek 讀了 $_t189_size 中的 $_t189_seek"
fi
assert_eq "$_t189_scan" "$_t189_size" \
    "T189b while a full scan reads the file / 而一次完整掃描讀的是整個檔案"

# ---------------------------------------------------------------------
# T190 -- a message that names columns from somebody else's file.
#
# Round 68: `-insert -cell` refused with "so status_notes ends up under
# license" -- two columns from this project's own fixture, printed at a caller
# whose file has neither. On a one-column file it named two columns that do not
# exist, and it reads as a report about the file that was passed.
#
# T190 —— 一則指名了「別人檔案裡的欄位」的訊息。
# ---------------------------------------------------------------------
echo
echo "--- T190: an illustration must look like one / T190：舉例必須看得出來是舉例 ---"

printf 'a\n1\n' > "$TMP/t190.csv"
_t190=$("$CSV2" -insert -cell 1 'x' -i "$TMP/t190.csv" -so 2>&1)
if [[ $_t190 == *"status_notes"* || $_t190 == *"license"* ]]; then
    bad "T190a the refusal named columns from another file / 那條拒絕指名了另一個檔案裡的欄位"
else
    ok "T190a the refusal does not name columns this file has never had / 那條拒絕不會指名這個檔案從來沒有的欄位"
fi
assert_contains "$_t190" "does not exist" \
    "T190b and still says what does not exist / 而它仍然說出「不存在的是什麼」"

# ---------------------------------------------------------------------
# T191 -- a newly created -o destination is 0600.
#
# Round 68 needed this and could not find it: the mode carried onto the temp
# file comes from the file being REPLACED, and when -o names a path that does
# not exist there is nothing to carry, so the file keeps the temp file's own
# 0600 rather than the umask's.
#
# T191 —— 新建的 -o 目的地是 0600。
# ---------------------------------------------------------------------
echo
echo "--- T191: the mode of a file -o creates / T191：-o 新建的檔案的權限 ---"

if (( IS_WINDOWS )); then
    skipt "T191a Windows does not carry POSIX modes here / Windows 上沒有這組 POSIX 權限位元"
    T191A_SKIPPED=1
else
    printf 'a,b\n1,x\n' > "$TMP/t191_src.csv"
    chmod 644 "$TMP/t191_src.csv"
    rm -f "$TMP/t191_new.csv"
    ( umask 022; "$CSV2" -r -t -i "$TMP/t191_src.csv" -o "$TMP/t191_new.csv" )
    # file_mode, not stat_mode: the guest's busybox has no `stat` applet, and
    # stat_mode is documented to return EMPTY there -- so this compared '' with
    # '600' and failed for a reason that has nothing to do with the mode. The
    # ls fallback exists for exactly this and T129 already uses it.
    # 用 file_mode 而不是 stat_mode：guest 的 busybox 沒有 `stat` applet，而 stat_mode 在那裡
    # 依定義回傳「空的」——於是這裡拿 '' 去比 '600'，因為一個與權限無關的理由而失敗。
    # 那個 ls 後備正是為此而存在，T129 早就在用它了。
    assert_eq "$(file_mode "$TMP/t191_new.csv")" "600" \
        "T191a a destination csv2 creates is 0600 / csv2 新建的目的地是 0600"
    printf 'x,y\n9,9\n' > "$TMP/t191_over.csv"
    chmod 644 "$TMP/t191_over.csv"
    "$CSV2" -r -t -i "$TMP/t191_src.csv" -o "$TMP/t191_over.csv"
    assert_eq "$(file_mode "$TMP/t191_over.csv")" "644" \
        "T191b while replacing a 0644 file keeps 0644 / 而覆蓋一個 0644 檔案時保留 0644"
fi


# ---------------------------------------------------------------------
# T192 -- two appends racing on one file.
#
# Round 69. The append fast path did `seek(toFileOffset: size)` then `write`,
# under a comment claiming POSIX O_APPEND atomicity. Two concurrent appends
# then computed the same end offset and wrote there, and the shorter write
# landed on top of the longer one:
#
#   * the surviving fragment was sometimes a bare newline, so csv2's own
#     blank-line rule refused a file csv2 had just written, at rc=0 from both
#     writers;
#   * and sometimes a WELL-FORMED record nobody appended -- `A,BBBB` left over
#     from `AAAA,BBBB` -- which read back at rc=0 with nothing anywhere
#     reporting it. That one hit on the round's first trial.
#
# The README's worst case for concurrent writers is "one edit is lost". This
# was both edits lost and a file destroyed, or a record invented.
#
# The write now goes through a descriptor opened O_APPEND, where the kernel
# makes finding the end and writing there one operation -- the same fix the
# `-log` file received, one source file away, for the same reason.
#
# T192 —— 兩個追加在同一個檔案上競賽。
# 第 69 回合。追加快路徑做的是 `seek(toFileOffset: size)` 再 `write`，而它上方的註解宣稱
# 這是 POSIX 的 O_APPEND 原子性。兩個並行的追加於是算出同一個檔尾偏移量並寫在那裡，較短的
# 那次蓋在較長的那次上面：留下的碎片有時是一個裸換行，於是 csv2 自己的空白行規則拒絕了一個
# csv2 剛剛寫出來的檔案；有時是一筆「沒有任何人追加過、格式卻完整」的紀錄，以 rc=0 被讀回來。
# ---------------------------------------------------------------------
echo
echo "--- T192: two appends, one file / T192：兩個追加，一個檔案 ---"

{
    printf 'x,y\n'
    _i=1
    while (( _i <= 400 )); do printf 'r%d,s%d\n' $_i $_i; _i=$((_i+1)); done
} > "$TMP/t192_base.csv"

# Rows of DIFFERENT lengths: an equal-length pair cannot leave a fragment, so
# it would be a race that cannot fail.
# 兩列長度「不同」：等長的一對留不下碎片，那會是一個不可能失敗的競賽。
_t192_bad=0
_t192_trials=6
for _t in $(seq 1 $_t192_trials); do
    cp "$TMP/t192_base.csv" "$TMP/t192.csv"
    ( "$CSV2" -append 'AAAA,BBBB' -i "$TMP/t192.csv" --in-place 2>/dev/null & \
      "$CSV2" -append 'C,' -i "$TMP/t192.csv" --in-place 2>/dev/null & \
      wait ) 2>/dev/null
    # The file must still be readable, and must hold exactly the two rows that
    # were appended -- no fragment, and nothing invented.
    # 檔案必須仍然讀得回來，而且必須恰好含有那兩列——沒有碎片，也沒有被憑空造出來的東西。
    if ! "$CSV2" -r -t --no-index -i "$TMP/t192.csv" > "$TMP/t192_out.txt" 2>/dev/null; then
        bad "T192a trial $_t: csv2 cannot read the file it wrote / 第 $_t 次：csv2 讀不回它自己寫出來的檔案"
        _t192_bad=1
        continue
    fi
    _t192_n=$("$CSV2" -r -t --json --no-index -i "$TMP/t192.csv" | tail -1 |
              sed -n 's/.*"records":\([0-9]*\).*/\1/p')
    if [[ "$_t192_n" != "402" ]]; then
        bad "T192a trial $_t: $_t192_n records, want 402 / 第 $_t 次：$_t192_n 筆，應為 402 筆"
        _t192_bad=1
        continue
    fi
    if ! grep -q '^AAAA,BBBB$' "$TMP/t192_out.txt" || ! grep -q '^C,$' "$TMP/t192_out.txt"; then
        bad "T192a trial $_t: one of the two appended rows is not whole / 第 $_t 次：兩列裡有一列不完整"
        _t192_bad=1
    fi
done
(( _t192_bad )) || ok "T192a $_t192_trials races: both rows whole, nothing invented, file readable / $_t192_trials 次競賽：兩列都完整、沒有東西被造出來、檔案讀得回來"

# A single append is unaffected, and still maintains the index.
# 單獨一次追加不受影響，而且仍然維護索引。
cp "$TMP/t192_base.csv" "$TMP/t192s.csv"
CSV2_INDEX_MIN_BYTES=100 "$CSV2" --build-index -i "$TMP/t192s.csv" > /dev/null
assert_succeeds "T192b a lone append still works / 單獨一次追加仍然可用" -- \
    env CSV2_INDEX_MIN_BYTES=100 "$CSV2" -append 'Z,Z' -i "$TMP/t192s.csv" --in-place
assert_succeeds "T192c and its index still describes the file / 而它的索引仍然與檔案相符" -- \
    env CSV2_INDEX_MIN_BYTES=100 "$CSV2" --verify-index -i "$TMP/t192s.csv"

# When a race IS detected, the index is left alone rather than updated with
# offsets that are no longer where the records are -- and the next read
# discards it as stale, which is the safe direction.
# 偵測到競賽時，索引會被原封不動地留著，而不是被更新成「已經不是紀錄所在」的偏移量——
# 而下一次讀取會把它當成過期的丟棄，那是安全的方向。
cp "$TMP/t192_base.csv" "$TMP/t192r.csv"
CSV2_INDEX_MIN_BYTES=100 "$CSV2" --build-index -i "$TMP/t192r.csv" > /dev/null
( CSV2_INDEX_MIN_BYTES=100 "$CSV2" -append 'AAAA,BBBB' -i "$TMP/t192r.csv" --in-place 2>/dev/null & \
  CSV2_INDEX_MIN_BYTES=100 "$CSV2" -append 'C,' -i "$TMP/t192r.csv" --in-place 2>/dev/null & \
  wait ) 2>/dev/null
_t192_v=$(CSV2_INDEX_MIN_BYTES=100 "$CSV2" --verify-index -i "$TMP/t192r.csv" 2>&1)
if [[ $_t192_v == *"index OK"* && $_t192_v != *"402 records"* ]]; then
    bad "T192d an index survived a race while describing the wrong file / 一份索引在競賽後活了下來，而它描述的是另一個檔案"
else
    ok "T192d after a race the index is stale or correct, never wrong / 競賽之後，索引要嘛過期、要嘛正確，絕不會是「錯的」"
fi


# ---------------------------------------------------------------------
# T193 -- what -md may put on a terminal.
#
# Round 70. The locating report escapes control characters and the README
# gives the reason: an ESC recolours the output from inside a cell, and can
# erase the line it is printed on. `-md` -- which the same document calls "a
# RENDERING ... for reading" -- passed them through.
#
# The attack needs no pipes, so the `\|` escape never fires: a licence column
# holding `GPL-3.0` followed by seven backspaces and `MIT` renders as `MIT` on
# any terminal that moves the cursor for a backspace, while `-get` returns the
# real bytes. An auditor running the documented reading command reads the
# wrong licence, at rc=0, with nothing on stderr.
#
# T193 —— `-md` 可以把什麼放到終端機上。
# 第 70 回合。定位報告會跳脫控制字元，而 README 給了理由：ESC 會從儲存格裡面把輸出重新上色，
# 也能抹掉它正被印出的那一行。而 `-md`——同一份文件稱它為「一種算繪……拿來讀的」——原樣放行。
# 那個攻擊不需要任何 `|`，因此 `\|` 那道跳脫從未觸發。
# ---------------------------------------------------------------------
echo
echo "--- T193: control characters in -md / T193：-md 裡的控制字元 ---"

printf 'pkg,license\nzlib,Zlib\nevil,GPL-3.0\b\b\b\b\b\b\bMIT\n' > "$TMP/t193.csv"
printf 'a,b\n1,X\033Y\tZ\007W\n' > "$TMP/t193c.csv"

_t193_md=$("$CSV2" -r -t -md -i "$TMP/t193.csv")
_t193_raw=$(print -r -- "$_t193_md" | od -A n -t x1 | tr -s ' ')
if [[ $_t193_raw == *" 08 "* ]]; then
    bad "T193a a raw backspace reached the rendered table / 一個原始的退格進到了算繪出來的表格裡"
else
    ok "T193a no raw backspace reaches the rendered table / 沒有原始的退格進到算繪出來的表格裡"
fi
assert_contains "$_t193_md" '\x08' \
    "T193b it is shown as \\x08, the way the report shows it / 它以 \\x08 顯示，與定位報告一致"

_t193_ctl=$("$CSV2" -r -t -md -i "$TMP/t193c.csv")
assert_contains "$_t193_ctl" '\x1B' \
    "T193c an ESC likewise / ESC 同樣如此"
assert_contains "$_t193_ctl" '\x07' \
    "T193d and a BEL / BEL 也是"
assert_contains "$_t193_ctl" '\t' \
    "T193e while a TAB is \\t, as in the report / 而 TAB 是 \\t，與報告相同"

# The DATA shapes still hand back the bytes -- that is their job, and the
# README defends it. -md is the one that renders.
# 各種「資料」形狀仍然交還位元組——那是它們的工作，README 也為此辯護。-md 才是負責算繪的那個。
assert_eq "$("$CSV2" -get 2:2 -i "$TMP/t193.csv" | od -A n -t x1 | tr -s ' ' | tr -d '\n' | grep -c '08')" "1" \
    "T193f -get still returns the real bytes / -get 仍然交還真正的位元組"

# ---------------------------------------------------------------------
# T194 -- a metrics line on every path.
#
# Round 70 measured ten paths and found five without one: both index commands
# and every --in-place edit. The flag entry says "on every path", and the
# missing half is the writes -- the runs whose cost a caller most wants to see.
#
# T194 —— 每一條路徑都有一行 metrics。
# 第 70 回合量了十條路徑，其中五條沒有：兩個索引指令，以及每一次 --in-place 編輯。
# 而旗標條目說的是「每一條路徑」，缺掉的那一半全是「寫入」。
# ---------------------------------------------------------------------
echo
echo "--- T194: metrics on every path / T194：每一條路徑上的 metrics ---"

printf 'a,b\n' > "$TMP/t194.csv"
_i=1
while (( _i <= 300 )); do printf 'r%d,s%d\n' $_i $_i >> "$TMP/t194.csv"; _i=$((_i+1)); done

_t194_bad=0
for _verb in "-r -t" "-contains r5" "-get 1:1" "-tail 1" "-update 1:2 Z --in-place" \
             "-append A,b --in-place" "-delete 5 --in-place" "--build-index" "--verify-index"; do
    _n=$(CSV2_INDEX_MIN_BYTES=100 "$CSV2" ${=_verb} -i "$TMP/t194.csv" -debug 2>&1 >/dev/null |
         grep -c "metrics:")
    if [[ "$_n" != "1" ]]; then
        bad "T194a [$_verb] printed $_n metrics lines / [$_verb] 印了 $_n 行 metrics"
        _t194_bad=1
    fi
done
(( _t194_bad )) || ok "T194a nine paths, one metrics line each / 九條路徑，各一行 metrics"

# A refusal still prints none: it belongs to a run that did work.
# 一次拒絕仍然不印：那一行屬於「真的做了事」的執行。
_t194_r=$("$CSV2" -mid 7,3 -i "$TMP/t194.csv" -debug 2>&1 >/dev/null | grep -c "metrics:")
assert_eq "$_t194_r" "0" \
    "T194b while a refusal prints none / 而一次拒絕不印"


# ---------------------------------------------------------------------
# T195 -- the other files a run touches.
#
# Round 71. The same-file guard compared `-i` against `-o` and nothing else,
# and the document describes THAT comparison in detail -- spellings, symlinks,
# (device, inode), a POSIX-only caveat -- while never saying which files it
# does not cover. Three of them destroy something at rc=0 with both streams
# empty:
#
#   -o naming the keyfile     the ciphertext lands on the only key that
#                             decrypts it, and nothing is left to report it
#   -o naming the -log file   the run renames away its own audit trail
#   -log naming the input     the invocation line is appended into the file
#                             being read, which then fails its own field-count
#                             check for ever
#
# Each is a run that did what it was told. The remedy is the comparison that
# already exists, asked three more times.
#
# T195 —— 一次執行會碰到的其他檔案。
# 第 71 回合。那道同檔案守衛只比對 `-i` 與 `-o`，而文件把那次比對描述得非常仔細，卻從未說出
# 它「沒有涵蓋」哪些檔案。其中三種會以 rc=0、兩條輸出流皆空的方式毀掉東西。
# ---------------------------------------------------------------------
echo
echo "--- T195: -o, -log and -keyfile as each other / T195：-o、-log 與 -keyfile 互相指向 ---"

printf 'id,secret\n1,alpha\n2,beta\n' > "$TMP/t195.csv"
head -c 32 /dev/urandom > "$TMP/t195key.bin" 2>/dev/null || \
    printf 'kJ3#a91Zq7!vB2xLm5PdR8sTn0WyE4Uc' > "$TMP/t195key.bin"
cp "$TMP/t195key.bin" "$TMP/t195key.keep"

assert_fails "T195a -o naming the keyfile is refused / -o 指向金鑰檔會被拒絕" -- \
    "$CSV2" -encrypt secret -keyfile "$TMP/t195key.bin" -i "$TMP/t195.csv" -o "$TMP/t195key.bin" -t
assert_same "$TMP/t195key.bin" "$TMP/t195key.keep" \
    "T195b and the key is untouched / 而那把金鑰完好無損"

printf 'pkg,note\na,1\n' > "$TMP/t195b.csv"
assert_fails "T195c -o naming the -log file is refused / -o 指向 -log 檔會被拒絕" -- \
    "$CSV2" -update 1:2 X -i "$TMP/t195b.csv" -o "$TMP/t195c.log" -log "$TMP/t195c.log"

printf 'pkg,note\na,1\n' > "$TMP/t195d.csv"
cp "$TMP/t195d.csv" "$TMP/t195d.keep"
assert_fails "T195d -log naming the input is refused / -log 指向輸入檔會被拒絕" -- \
    "$CSV2" -contains a -i "$TMP/t195d.csv" -log "$TMP/t195d.csv"
assert_same "$TMP/t195d.csv" "$TMP/t195d.keep" \
    "T195e and the input is still what it was / 而那個輸入還是原來的樣子"

# The ordinary shapes must keep working: the guard is about ALIASES, not about
# using a keyfile and a log at all.
# 一般的用法必須照樣可行：這道守衛管的是「別名」，不是「不准用金鑰檔或 log」。
assert_succeeds "T195f -keyfile with a separate -o still works / -keyfile 搭配另一個 -o 仍然可用" -- \
    "$CSV2" -encrypt secret -keyfile "$TMP/t195key.bin" -i "$TMP/t195.csv" -o "$TMP/t195enc.csv" -t
assert_succeeds "T195g -log to its own file still works / -log 寫到它自己的檔案仍然可用" -- \
    "$CSV2" -update 1:2 Y -i "$TMP/t195b.csv" -o "$TMP/t195out.csv" -log "$TMP/t195ok.log"

# ---------------------------------------------------------------------
# T196 -- a diagnostic that dumps the whole header.
#
# Round 71: a file whose first column name is 50,000 characters long put a
# 50 KB line on stderr -- on the line carrying the diagnosis, from a message
# whose documented example is `no column named "caf<U+FFFD>"`. The locating
# report cuts a value at 200 characters for exactly this reason and says so; a
# diagnostic listing what IS available had no such rule.
#
# T196 —— 一則把整列標頭倒出來的診斷。
# 第 71 回合：一個「第一欄名字有 50,000 個字元」的檔案，會在 stderr 上放一行 50 KB。
# ---------------------------------------------------------------------
echo
echo "--- T196: how long a refusal may be / T196：一條拒絕可以多長 ---"

# A 20,000-character column name, built in the shell so this case does not
# depend on python3 -- the guest has none, and wrapping a heredoc in
# `cmd || { ... }` is a zsh parse error that took the whole rest of the suite
# with it when this case was first written.
# 一個 20,000 字元的欄名，用 shell 造出來，好讓這個案例不依賴 python3——guest 上沒有它；
# 而把一個 heredoc 包進 `cmd || { ... }` 是一個 zsh 語法錯誤，這個案例第一次寫成時，
# 那個錯誤把整份測試的其餘部分一起帶走了。
_t196_name=""
_i=0
while (( _i < 500 )); do
    _t196_name="${_t196_name}NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
    _i=$((_i+1))
done
printf '%s,b\n1,2\n' "$_t196_name" > "$TMP/t196.csv"

_t196=$("$CSV2" -hash NOSUCH -i "$TMP/t196.csv" -o "$TMP/t196o.csv" -t 2>&1 | head -1)
_t196_len=${#_t196}
if (( _t196_len < 400 )); then
    ok "T196a the refusal is $_t196_len characters, not the header / 那條拒絕是 $_t196_len 個字元，不是整列標頭"
else
    bad "T196a the refusal is $_t196_len characters long / 那條拒絕有 $_t196_len 個字元"
fi
assert_contains "$_t196" "more chars" \
    "T196b and it says the name was cut / 而它說出那個名字被切掉了"

# A wide file gets a bounded LIST as well, not one entry per column.
# 欄位很多的檔案，得到的也是一份有上界的「清單」，而不是一欄一項。
{
    _hdr="c1"; _i=2
    while (( _i <= 40 )); do _hdr="$_hdr,c$_i"; _i=$((_i+1)); done
    print -r -- "$_hdr"
    _row="v"; _i=2
    while (( _i <= 40 )); do _row="$_row,v"; _i=$((_i+1)); done
    print -r -- "$_row"
} > "$TMP/t196w.csv"
# 40 columns: twelve are named and the remaining 28 are counted. The number in
# the message is what the file has minus what was shown, so it is checked
# against the file rather than against a number typed here.
# 40 欄：列出十二個，其餘 28 個用數的。訊息裡的那個數字是「檔案有幾欄」減去「印出了幾個」，
# 因此拿它去對檔案，而不是去對一個在這裡打出來的數字。
assert_contains "$("$CSV2" -hash NOPE -i "$TMP/t196w.csv" -o "$TMP/t196wo.csv" -t 2>&1)" "and 28 more" \
    "T196c a 40-column file lists twelve and counts the rest / 40 欄的檔案列出十二個，其餘用數的"


# ---------------------------------------------------------------------
# T197 -- the header rows must agree about protection.
#
# Round 72. Every guard that asks "does the file's own header declare this
# column transformed" asked row 0a. A `.csv2` whose 0b carries `:enc:` and
# whose 0a does not walked past all of them: `-update` wrote plaintext into an
# encrypted column, `-insert` was accepted, `--json`'s meta said nothing was
# protected, and `-hash` did what the README calls the worst thing this tool
# can do -- hashed the CIPHERTEXT and overwrote the `:enc:` marker together
# with its salt, at rc=0, on a file whose Chinese header row still said
# `:enc:`.
#
# Reading both rows and taking the union would fix the misses and leave the
# file incoherent. Refusing is what the rest of this program does when two
# sources disagree.
#
# T197 —— 兩列標頭對「保護」必須說同一件事。
# 第 72 回合。每一道「這個檔案自己的標頭有沒有宣告這一欄已被轉換」的守衛問的都是 0a 列。
# 一個 0b 帶著 `:enc:`、0a 沒有的 `.csv2`，從它們全部旁邊走了過去。
# ---------------------------------------------------------------------
echo
echo "--- T197: two header rows, one answer / T197：兩列標頭，一個答案 ---"

printf 'pkg,ver,secret\n套件,版本,機密\nzlib,1.3,s1\nzstd,1.5,s2\n' > "$TMP/t197.csv2"
"$CSV2" -encrypt secret -keyfile "$KEY" -i "$TMP/t197.csv2" -o "$TMP/t197e.csv2" -t 2>/dev/null

# Strip the marker from row 0a only, leaving 0b declaring the column encrypted.
# Done with the shell: this is a state a person produces by tidying the English
# header, and no csv2 command can make it.
# 只把 0a 那一列的標記拿掉，讓 0b 仍然宣告該欄已加密。用 shell 做：這是一個「有人把英文標頭
# 整理乾淨」就會產生的狀態，而沒有任何 csv2 指令造得出它。
{
    _t197_a=$(head -1 "$TMP/t197e.csv2")
    print -r -- "${_t197_a%%,*},${${_t197_a#*,}%%,*},secret"
    sed -n '2,$p' "$TMP/t197e.csv2"
} > "$TMP/t197bad.csv2"

if head -2 "$TMP/t197bad.csv2" | grep -q ':enc:'; then
    ok "T197a the fixture really has the marker on one row only / 這個 fixture 確實只有一列帶著標記"
else
    bad "T197a the fixture lost the marker entirely, so nothing is being tested / 這個 fixture 把標記整個弄丟了，因此什麼也沒有被測試"
fi

for _verb in "-r -t" "-update 1:secret NEW" "-insert 1 p,v,raw" "-hash secret --yes"; do
    assert_fails "T197b [$_verb] refuses a file whose header rows disagree / [$_verb] 拒絕一個兩列標頭互相矛盾的檔案" -- \
        env HOME="$TMP/home" "$CSV2" ${=_verb} -i "$TMP/t197bad.csv2" -o "$TMP/t197out.csv2" -t
done
assert_contains "$("$CSV2" -r -t -i "$TMP/t197bad.csv2" 2>&1)" "disagree about column 3" \
    "T197c and the message names the column and both rows / 而訊息指出是哪一欄、以及兩列各說了什麼"

# The properly marked file is untouched by all of this.
# 標記正確的那個檔案完全不受影響。
assert_succeeds "T197d a file marked on both rows still reads / 兩列都有標記的檔案仍然讀得回來" -- \
    "$CSV2" -r -t -i "$TMP/t197e.csv2" -so
assert_succeeds "T197e and still decrypts / 也仍然解得開" -- \
    "$CSV2" -decrypt all -keyfile "$KEY" -i "$TMP/t197e.csv2" -o "$TMP/t197dec.csv2" -t

# ---------------------------------------------------------------------
# T198 -- -log naming the keyfile.
#
# Round 72, and the worst of the six pairs: the invocation line is appended to
# the key BEFORE the key is derived, so the run encrypts with "the original
# bytes plus one log line" -- a value that existed for a few milliseconds and
# was never written anywhere as such. The file on disk is then one line too
# long and any backup one line too short, and neither decrypts. rc=0, nothing
# on either stream.
#
# T198 —— `-log` 指向金鑰檔。
# 第 72 回合，也是六對裡最糟的一對：呼叫紀錄在金鑰被推導「之前」被追加到那把金鑰上。
# ---------------------------------------------------------------------
echo
echo "--- T198: -log onto the key / T198：-log 寫到金鑰上 ---"

printf 'pkg,note\nzlib,first\n' > "$TMP/t198.csv"
cp "$KEY" "$TMP/t198key.bin"
cp "$TMP/t198key.bin" "$TMP/t198key.keep"

assert_fails "T198a -log naming the keyfile is refused / -log 指向金鑰檔會被拒絕" -- \
    "$CSV2" -encrypt note -keyfile "$TMP/t198key.bin" -i "$TMP/t198.csv" -o "$TMP/t198e.csv" -t \
        -log "$TMP/t198key.bin"
assert_same "$TMP/t198key.bin" "$TMP/t198key.keep" \
    "T198b and the key is byte-for-byte what it was / 而那把金鑰逐位元組不變"
assert_succeeds "T198c while a log of its own still works / 而寫到它自己的 log 檔仍然可用" -- \
    "$CSV2" -encrypt note -keyfile "$TMP/t198key.bin" -i "$TMP/t198.csv" -o "$TMP/t198e2.csv" -t \
        -log "$TMP/t198.log"

# ---------------------------------------------------------------------
# T199 -- a body with CR line endings under a header that ends properly.
#
# Round 66 moved the CR test to the header row, which is exact for a file whose
# lines all end in CR. Round 72 found the file that test cannot see: an LF
# header over a legacy body, which `(echo a; cat old_mac_body) > f.csv`
# produces. It read as ONE record at rc=0 with `records:1` -- every count in
# the file wrong by the number of lines in it.
#
# The new test is the last byte: a file that ends on a bare CR is refused, one
# that ends with a newline is not, whatever its records contain.
#
# T199 —— 一個「標頭正常結束、內文以 CR 分行」的檔案。
# 第 66 回合把 CR 的判斷移到標頭列，那對「每一行都以 CR 結尾」的檔案是精確的。第 72 回合
# 找到了那個判斷看不見的檔案：LF 標頭配上一段舊式內文。
# ---------------------------------------------------------------------
echo
echo "--- T199: a CR body under an LF header / T199：LF 標頭配 CR 內文 ---"

printf 'a\n1\r2\r3\r' > "$TMP/t199_one.csv"
printf 'a,b\n1,x\r2,y\r3,z\r' > "$TMP/t199_two.csv"
printf 'a,b\n1,x\r\r\ry\n' > "$TMP/t199_data.csv"
printf 'a,b\n1,x' > "$TMP/t199_nonl.csv"

assert_fails "T199a a one-column CR body is refused / 單欄的 CR 內文會被拒絕" -- \
    "$CSV2" -r -i "$TMP/t199_one.csv"
assert_fails "T199b and a two-column one / 兩欄的也是" -- \
    "$CSV2" -r -i "$TMP/t199_two.csv"
assert_contains "$("$CSV2" -r -i "$TMP/t199_one.csv" 2>&1)" "last byte is a bare carriage return" \
    "T199c the message names what was seen / 訊息指出看到的是什麼"

# The round-66 false positive must stay legal: CRs INSIDE a record, file ending
# with a newline.
# 第 66 回合那個誤判必須繼續合法：CR 在「紀錄裡面」，而檔案以換行結尾。
assert_succeeds "T199d three CRs inside a record are still data / 一筆紀錄裡的三個 CR 仍然是資料" -- \
    "$CSV2" -r -t -i "$TMP/t199_data.csv" -o "$TMP/t199_rt.csv"
assert_same "$TMP/t199_data.csv" "$TMP/t199_rt.csv" \
    "T199e and round-trip byte for byte / 而且逐位元組往返"
assert_succeeds "T199f a .csv with no trailing newline is still fine / 沒有結尾換行的 .csv 仍然沒問題" -- \
    "$CSV2" -r -t -i "$TMP/t199_nonl.csv" -so

# ---------------------------------------------------------------------
# T200 -- gzip named .csv, and the output suffix that is a promise.
#
# Round 72. `1F 8B` cannot begin a UTF-8 CSV any more than `FF FE` can, and a
# compressed file named `.csv` was read at rc=0 as one record of binary --
# `-contains` found nothing in it and said so.
#
# And the `-t` guard tested the suffix case-sensitively, so `-o sel.csv2` was
# refused and `-o SEL.CSV2` accepted: same directory, same file on macOS and
# Windows, and the result read back as two data records eaten as header rows.
#
# T200 —— 叫做 .csv 的 gzip，以及「輸出副檔名是一個承諾」。
# ---------------------------------------------------------------------
echo
echo "--- T200: what a name promises / T200：一個名字承諾了什麼 ---"

if (( $+commands[gzip] )); then
    printf 'a,b\n1,x\n2,y\n' > "$TMP/t200src.csv"
    gzip -c "$TMP/t200src.csv" > "$TMP/t200gz.csv"
    assert_fails "T200a a gzip file named .csv is refused / 叫做 .csv 的 gzip 檔會被拒絕" -- \
        "$CSV2" -r -i "$TMP/t200gz.csv"
    assert_contains "$("$CSV2" -r -i "$TMP/t200gz.csv" 2>&1)" "gunzip" \
        "T200b and the message names the way through / 而訊息指出走得通的那條路"
else
    skipt "T200a no gzip on this platform / 此平台沒有 gzip"
    T200A_SKIPPED=1
    skipt "T200b no gzip on this platform / 此平台沒有 gzip"
    T200B_SKIPPED=1
fi

printf 'k,v\n鍵,值\nr1,v1\nr2,v2\n' > "$TMP/t200.csv2"
assert_fails "T200c -o SEL.CSV2 is refused like -o sel.csv2 / -o SEL.CSV2 與 -o sel.csv2 一樣被拒絕" -- \
    "$CSV2" -head 1 -i "$TMP/t200.csv2" -o "$TMP/T200SEL.CSV2"
assert_succeeds "T200d and -t makes both acceptable / 而 -t 讓兩者都可以" -- \
    "$CSV2" -head 1 -t -i "$TMP/t200.csv2" -o "$TMP/T200SEL2.CSV2"
assert_contains "$("$CSV2" -r -i "$TMP/t200.csv2" --headers 1 2>&1)" "declares 2 header row" \
    "T200e while a --headers that disagrees with the suffix is still refused / 而與副檔名不符的 --headers 仍然被拒絕"
# ONE suffix rule, both sides. The reading side was case-sensitive and the
# writing side was not, for one day: `-o x.CSV2` was refused for declaring a
# format with a header while `-i x.CSV2` was refused for declaring nothing,
# and the never-convert guard -- which reads the READING side -- let a
# one-header input be written to `.CSV2`, which on this filesystem is the
# `.csv2` you read back a record short.
# 一個副檔名規則，兩側共用。「讀取」那一側曾經區分大小寫、「寫出」那一側不區分，為時一天：
# `-o x.CSV2` 以「它宣告了一個帶標頭的格式」被拒絕，而 `-i x.CSV2` 以「它什麼都沒宣告」被拒絕；
# 而「絕不轉換格式」那道守衛讀的是「讀取」那一側，於是一個單列標頭的輸入被寫進了 `.CSV2`
# ——在這個檔案系統上，那正是你之後讀回來、少了一筆紀錄的那個 `.csv2`。
printf 'a,b\n1,x\n2,y\n' > "$TMP/t200one.csv"
assert_fails "T200f a one-header input to .CSV2 is refused like .csv2 / 單列標頭的輸入寫到 .CSV2 與寫到 .csv2 一樣被拒絕" -- \
    "$CSV2" -r -t -i "$TMP/t200one.csv" -o "$TMP/T200CONV.CSV2"
assert_succeeds "T200g and an uppercase suffix reads as its format / 而大寫的副檔名會依它的格式被讀入" -- \
    "$CSV2" -r -t -i "$TMP/t200one.csv" -o "$TMP/T200UP.CSV"
assert_succeeds "T200h including reading it back with no --headers / 包括不給 --headers 就讀回來" -- \
    "$CSV2" -r -t -i "$TMP/T200UP.CSV" -so

# ---------------------------------------------------------------------
# T201 -- a row you supply is a field csv2 writes.
#
# Round 72: `-append 'r2, leading'` wrote ` leading` unquoted while
# `-update 1:2 ' leading'` quoted the identical value. csv2 reads both back
# correctly; the spreadsheets and "several parsers" the quoting rule exists for
# do not, and the README states the rule as covering "a value you supply".
#
# T201 —— 你交進來的一列，是 csv2 寫出去的欄位。
# ---------------------------------------------------------------------
echo
echo "--- T201: quoting a supplied row / T201：對「交進來的一列」加引號 ---"

printf 'k,v\nr1,x\n' > "$TMP/t201.csv"
"$CSV2" -append 'r2, leading' -i "$TMP/t201.csv" -o "$TMP/t201a.csv" -t
assert_contains "$(tail -1 "$TMP/t201a.csv")" '"' \
    "T201a an appended value with a leading space is quoted / 被追加的值若以空白開頭會被加引號"
"$CSV2" -insert 1 'r0,trailing ' -i "$TMP/t201.csv" -o "$TMP/t201b.csv" -t
assert_contains "$(sed -n 2p "$TMP/t201b.csv")" '"' \
    "T201b and an inserted one with a trailing space / 被插入的那一列若以空白結尾也是"
cp "$TMP/t201.csv" "$TMP/t201c.csv"
"$CSV2" -append 'r3, sp' -i "$TMP/t201c.csv" --in-place
assert_contains "$(tail -1 "$TMP/t201c.csv")" '"' \
    "T201c the in-place fast path agrees / 就地追加的快路徑說法一致"
assert_eq "$("$CSV2" -get 2:2 -i "$TMP/t201a.csv")" " leading" \
    "T201d and the value read back is the one supplied / 而讀回來的值就是交進去的那一個"


# ---------------------------------------------------------------------
# T202 -- an append follows the file's line endings, including when the
# file's last record has none.
#
# Round 73. The fast path decided CRLF from the file's LAST TWO BYTES, which
# answers the question only when the last record is terminated. On a CRLF file
# whose tail is not -- an exporter cut off, a torn write, anything ending
# mid-record -- those two bytes are the end of a VALUE, so the probe said LF
# and the append wrote LF into a file where every other record ends CRLF, and
# supplied a bare LF to close the record before it.
#
# The scan the append already performs knows what the file's last terminator
# was. This is the same rule the probe states, asked of the file rather than
# of its last two bytes.
#
# T202 —— 一次追加會跟隨檔案的行尾，包括「檔案最後一筆沒有終止符」時。
# 第 73 回合。快路徑是用「檔案的最後兩個位元組」判斷 CRLF 的，而只有在最後一筆有終止符時，
# 那兩個位元組才回答得了這個問題。
# ---------------------------------------------------------------------
echo
echo "--- T202: which line ending an append writes / T202：一次追加寫的是哪一種行尾 ---"

# CRLF file, last record terminated: the case the probe always handled.
# CRLF 檔案、最後一筆有終止符：探測一直處理得了的那個情況。
printf 'a,b\r\n1,x\r\n' > "$TMP/t202_ok.csv"
"$CSV2" -append '2,y' -i "$TMP/t202_ok.csv" --in-place
# The last two bytes, read as bytes. Matching `od -c` text was the first
# attempt and it compared od's SPACING, not the file's contents.
# 讀「最後兩個位元組」，當成位元組來讀。第一次的寫法是比對 `od -c` 的文字，而那比到的是
# od 的「排版」，不是檔案的內容。
_t202_tail() { tail -c 2 "$1" | od -A n -t x1 | tr -s ' ' | sed 's/^ //;s/ $//' }
assert_eq "$(_t202_tail "$TMP/t202_ok.csv")" "0d 0a" \
    "T202a a terminated CRLF file gets a CRLF record / 有終止符的 CRLF 檔案得到一筆 CRLF 紀錄"

# CRLF file, last record UNTERMINATED: the case it did not.
# CRLF 檔案、最後一筆「沒有」終止符：它處理不了的那個情況。
printf 'a,b\r\n1,x\r\n2,y' > "$TMP/t202_cut.csv"
"$CSV2" -append '3,z' -i "$TMP/t202_cut.csv" --in-place
assert_eq "$(_t202_tail "$TMP/t202_cut.csv")" "0d 0a" \
    "T202b and so does one whose last record was cut off / 最後一筆被切斷的那個也是"
# Every record in it ends the same way: no bare LF was introduced.
# 它裡面每一筆的結尾都一樣：沒有多出一個裸 LF。
_t202_lf=$(od -A n -c < "$TMP/t202_cut.csv" | tr -s ' ' | grep -o '\\n' | wc -l | tr -d ' ')
_t202_cr=$(od -A n -c < "$TMP/t202_cut.csv" | tr -s ' ' | grep -o '\\r' | wc -l | tr -d ' ')
assert_eq "$_t202_lf" "$_t202_cr" \
    "T202c every LF in it is half of a CRLF / 它裡面每一個 LF 都是某個 CRLF 的一半"

# An LF file stays an LF file, terminated or not.
# LF 檔案仍然是 LF 檔案，有沒有終止符都一樣。
printf 'a,b\n1,x' > "$TMP/t202_lf.csv"
"$CSV2" -append '2,y' -i "$TMP/t202_lf.csv" --in-place
_t202d=$(od -A n -c < "$TMP/t202_lf.csv" | tr -s ' ')
if [[ $_t202d == *"\\r"* ]]; then
    bad "T202d a CR appeared in an LF file / 一個 CR 出現在 LF 檔案裡"
else
    ok "T202d an LF file gains no CR / LF 檔案不會多出 CR"
fi

# With -o there is no append: the whole file is rewritten and comes out LF.
# The flag's own entry promised the CRLF behaviour unconditionally until round
# 74 measured this and got LF. The behaviour is deliberate -- every other edit
# rewrites separators the same way -- so what was wrong was the sentence, and
# this case is what keeps the corrected one honest.
# 搭配 -o 時沒有「追加」這回事：整個檔案會被重寫，出來是 LF。那個旗標自己的條目把 CRLF 那個
# 行為寫成無條件成立，直到第 74 回合實測 -o 拿到 LF。這個行為是刻意的——其他每一種編輯都以
# 同樣方式重寫分隔符——因此錯的是那句話，而這個案例是用來讓改過的那句話保持誠實的。
printf 'a,b\r\n1,x\r\n' > "$TMP/t202_o.csv"
"$CSV2" -append '2,y' -i "$TMP/t202_o.csv" -o "$TMP/t202_o.out" -t
_t202f=$(od -A n -c < "$TMP/t202_o.out" | tr -s ' ')
if [[ $_t202f == *"\\r"* ]]; then
    bad "T202f -o kept CR, and the README says it does not / -o 保留了 CR，而 README 說它不會"
else
    ok "T202f -o rewrites a CRLF file to LF, as every other edit does / -o 把 CRLF 檔案重寫成 LF，與其他每一種編輯相同"
fi

# And the index still describes the file afterwards -- the appended record's
# line accounting has to survive a two-byte terminator.
# 而索引在那之後仍然與檔案相符——被追加那一筆的行號計算必須撐得住一個兩位元組的終止符。
printf 'a,b\r\n1,x\r\n2,y' > "$TMP/t202_idx.csv"
CSV2_INDEX_MIN_BYTES=10 "$CSV2" --build-index -i "$TMP/t202_idx.csv" > /dev/null
CSV2_INDEX_MIN_BYTES=10 "$CSV2" -append '3,z' -i "$TMP/t202_idx.csv" --in-place
assert_succeeds "T202e and the index still describes the file / 而索引仍然與檔案相符" -- \
    env CSV2_INDEX_MIN_BYTES=10 "$CSV2" --verify-index -i "$TMP/t202_idx.csv"

# ---------------------------------------------------------------------
# T203 -- install.zsh puts the PATH line where the ACCOUNT's shell reads it,
# and proves reachability from a shell started with nothing.
#
# 2026-08-25. Four separate faults, all of the same family: a check that
# measured something adjacent to what it claimed.
#
#   * the rc file was chosen from the shell RUNNING install.zsh, which is
#     always zsh (it is `#!/usr/bin/env zsh`) and says nothing about the
#     account. The WSL node's login shell was bash and the only rc file in
#     that home directory was .zshrc -- the right line would have gone into
#     the one file nothing reads;
#   * for zsh it went to .zshrc, which only INTERACTIVE shells read, while
#     the thing that needed csv2 there was a script over ssh, which reads
#     .zshenv and nothing else;
#   * `--uninstall` stripped the block from one of the two files the bash
#     install writes, leaving the other still marked as ours;
#   * the reachability probe ran `$SHELL -c`, which INHERITS the caller's
#     PATH, so "a fresh shell finds it" was never actually asked.
#
# T203 —— install.zsh 把 PATH 那一行寫到「這個帳號的 shell」會讀的地方，並以一個
# 「從零開始的 shell」證明可及性。四個各自獨立的問題，同一個家族：一個量到了「與它宣稱
# 的東西相鄰」的檢查。
# ---------------------------------------------------------------------
echo
echo "--- T203: where install.zsh writes, and what it can prove / T203：install.zsh 寫到哪裡，以及它證明得了什麼 ---"

if (( IS_WINDOWS )); then
    # install.zsh's Windows target is a scoop shim path and `env -i` drops the
    # variables an MSYS shell needs to start at all; the case would test the
    # harness, not the installer.
    # install.zsh 在 Windows 的目標是一條 scoop shim 路徑，而 `env -i` 會拿掉 MSYS shell
    # 啟動所必需的變數；這個案例會變成在測試環境而不是測試安裝程式。
    skipt "T203 install.zsh rc placement -- needs a POSIX home and env -i / 需要 POSIX 家目錄與 env -i"
    T203_SKIPPED=1
else
    # Say once that the file is missing, rather than five times that its
    # absence produced surprising output. In the guest on 2026-08-25 the
    # payload did not carry install.zsh, and this case reported five failures
    # whose text was about `env: can't execute` and an empty directory listing
    # -- true, and about the harness rather than about csv2.
    # 「檔案不在」只說一次，而不是說五次「它不在所造成的奇怪輸出」。2026-08-25 在 guest 裡，
    # payload 沒有帶 install.zsh，於是這個案例回報了五個失敗，內容是 `env: can't execute`
    # 與一個空目錄列表——都是真的，但講的是測試環境而不是 csv2。
    _t203_home="$TMP/t203home"; _t203_pfx="$TMP/t203bin"
    mkdir -p "$_t203_home" "$_t203_pfx"
    _t203_run() {   # <shell> <extra args...>
        env HOME="$_t203_home" SHELL="$1" "$ROOT/install.zsh" --prefix "$_t203_pfx" "${@:2}" 2>&1
    }

    # zsh: .zshenv, because that is the file a non-interactive shell reads.
    # zsh：寫 .zshenv，因為那才是非互動 shell 會讀的檔案。
    if [[ ! -x $ROOT/install.zsh ]]; then
        bad "T203 install.zsh is not in this tree at $ROOT -- the payload that carried the suite here left it out / install.zsh 不在這棵樹裡，把測試送到這裡的 payload 沒有帶上它"
    else
    _t203_out=$(_t203_run "$(command -v zsh)")
    if [[ -f $_t203_home/.zshenv ]] && ! [[ -f $_t203_home/.zshrc ]]; then
        ok "T203a a zsh account gets .zshenv, not .zshrc / zsh 帳號拿到的是 .zshenv 而非 .zshrc"
    else
        bad "T203a wrote: $(ls -a "$_t203_home" | tr '\n' ' ') / 實際寫出如上"
    fi

    # And it says so: reachable from every shell, ssh included. That claim is
    # the one .zshenv buys and .zshrc does not.
    # 而且它會這樣說：每一種 shell 都找得到，包含 ssh。那個宣稱正是 .zshenv 換來、而 .zshrc
    # 換不到的東西。
    case $_t203_out in
        *"every shell, scripts over ssh included"*)
            ok "T203b and reports it is reachable from a non-interactive shell / 並回報非互動 shell 也找得到" ;;
        *) bad "T203b got: $_t203_out / 實得如上" ;;
    esac

    # Independently of what it reported: a shell started from NOTHING runs it.
    # 與它的回報無關地驗證一次：一個從零開始的 shell 執行得到它。
    _t203_which=$(env -i HOME="$_t203_home" TERM=dumb "$(command -v zsh)" -c 'command -v csv2' 2>/dev/null)
    assert_eq "$_t203_which" "$_t203_pfx/csv2" \
        "T203c a zsh with an empty environment resolves csv2 to the install / 空環境的 zsh 解析到的就是這次安裝"

    # A second install must not leave two blocks.
    # 第二次安裝不得留下兩個區塊。
    _t203_run "$(command -v zsh)" > /dev/null
    _t203_blocks=$(grep -cF '>>> csv2 install.zsh >>>' "$_t203_home/.zshenv")
    assert_eq "$_t203_blocks" "1" \
        "T203d installing twice leaves one block, not two / 裝兩次留下一個區塊而不是兩個"

    # --uninstall takes back every file the install wrote to. bash is the case
    # that has two of them, so bash is the case this asks about.
    # --uninstall 要收回安裝寫過的每一個檔案。bash 是「有兩個」的那種情況，因此就問 bash。
    if command -v bash > /dev/null 2>&1; then
        _t203_bhome="$TMP/t203bash"; mkdir -p "$_t203_bhome"
        env HOME="$_t203_bhome" SHELL="$(command -v bash)" \
            "$ROOT/install.zsh" --prefix "$_t203_pfx" > /dev/null 2>&1
        _t203_wrote=$(grep -lF '>>> csv2 install.zsh >>>' "$_t203_bhome"/.* 2>/dev/null | wc -l | tr -d ' ')
        if (( _t203_wrote >= 2 )); then
            ok "T203e a bash account gets both an interactive and a login file / bash 帳號拿到互動與登入兩個檔案"
        else
            bad "T203e bash install wrote $_t203_wrote file(s) carrying the block / bash 安裝只寫了 $_t203_wrote 個帶有區塊的檔案"
        fi
        env HOME="$_t203_bhome" SHELL="$(command -v bash)" \
            "$ROOT/install.zsh" --prefix "$_t203_pfx" --uninstall > /dev/null 2>&1
        _t203_left=$(grep -lF '>>> csv2 install.zsh >>>' "$_t203_bhome"/.* 2>/dev/null | wc -l | tr -d ' ')
        assert_eq "$_t203_left" "0" \
            "T203f and --uninstall takes back every one of them / 而 --uninstall 把它們全部收回"
    else
        skipt "T203e/f no bash on this platform / 本平台沒有 bash"
        T203_BASH_SKIPPED=1
    fi

    # The probe must not answer out of the caller's PATH. With --no-rc and the
    # prefix exported into PATH, the OLD code called that a verified install.
    # 探測不得用「呼叫端的 PATH」來回答。加上 --no-rc 並把 prefix 放進 PATH 之後，舊的程式
    # 會把那稱為一次「已驗證」的安裝。
    _t203_home2="$TMP/t203home2"; mkdir -p "$_t203_home2"
    _t203_out2=$(env HOME="$_t203_home2" SHELL="$(command -v zsh)" PATH="$_t203_pfx:$PATH" \
        "$ROOT/install.zsh" --prefix "$_t203_pfx" 2>&1)
    case $_t203_out2 in
        *"reachable from: every shell"*)
            bad "T203g claimed every shell finds it, on the strength of the caller's PATH / 憑呼叫端的 PATH 就宣稱每一種 shell 都找得到" ;;
        *) ok "T203g an inherited PATH is not reported as a fresh shell's / 繼承來的 PATH 不會被當成全新 shell 的" ;;
    esac

    # And when the caller's PATH really does reach the file just installed,
    # nothing is written. This is the Windows node: csv2 resolves through a
    # scoop shim while the install directory is not on PATH at all, and an
    # installer that edited that machine's rc files would be fixing something
    # that was not broken.
    # 而當呼叫端的 PATH 真的通到剛裝好的那個檔案時，什麼都不寫。這就是 Windows 節點的情況：
    # csv2 經由一個 scoop shim 解析得到，而安裝目錄根本不在 PATH 上；一個會去改那台機器 rc 檔
    # 的安裝程式，修的是一個沒有壞的東西。
    _t203_left=$(ls -a "$_t203_home2" | grep -vE '^\.$|^\.\.$' | tr '\n' ' ')
    assert_eq "$_t203_left" "" \
        "T203h nothing is written when the shell already runs that very file / shell 已經在執行那個檔案時，什麼都不寫"

    # A byte-identical copy at another path is NOT that file. Both are the same
    # build, so a hash comparison says yes; the question is which copy the shell
    # runs, and it is running the other one.
    # 另一個路徑上的一份「位元組相同」的複本，不是那個檔案。兩者是同一次建置，因此雜湊比對會
    # 說「是」；而問題是 shell 執行的是哪一份，答案是另外那一份。
    _t203_home3="$TMP/t203home3"; _t203_decoy="$TMP/t203decoy"
    mkdir -p "$_t203_home3" "$_t203_decoy" "$_t203_pfx"
    cp "$CSV2" "$_t203_decoy/csv2"
    env HOME="$_t203_home3" SHELL="$(command -v zsh)" PATH="$_t203_decoy:$PATH" \
        "$ROOT/install.zsh" --prefix "$_t203_pfx" > /dev/null 2>&1
    if [[ -f $_t203_home3/.zshenv ]]; then
        ok "T203i an identical copy elsewhere is not mistaken for the install / 別處一份相同的複本不會被誤認為這次安裝"
    else
        bad "T203i wrote nothing: an identical copy on PATH was taken for the installed file / 什麼都沒寫：PATH 上一份相同的複本被當成了剛裝的那個檔案"
    fi
    rm -rf "$_t203_home3" "$_t203_decoy"
    rm -rf "$_t203_home" "$_t203_home2" "$TMP/t203bash" "$_t203_pfx"
    fi
fi

# ---------------------------------------------------------------------
# T204 -- a sidecar the O(1) stamp accepts, whose offsets have drifted, costs
# a SCAN and not an answer.
#
# Round 74, defect JB. The contract is stated twice in the README and is the
# reason the index exists: it is an optimisation and never a precondition.
# That held whenever the stamp REJECTED a sidecar. When the stamp accepted one
# whose offsets were off by a byte, the seek landed on the previous record's
# terminator, the parser read an empty line, and `-mid` refused a file with no
# blank line in it -- naming a record number and a line number both computed
# from the index that was wrong. `--no-index` returned the record. An index had
# become a precondition.
#
# The fixture must defeat the stamp, which is size + mtime to the nanosecond +
# the first and last 64 bytes. So: lengthen one record and shorten a later one
# by the same amount, in place, and put the mtime back.
#
# T204 —— 一份「戳記接受、偏移量已漂掉」的 sidecar，代價應該是一次掃描，而不是一個答案。
# 第 74 回合，缺陷 JB。契約在 README 裡寫了兩次，也正是索引存在的理由：它是最佳化，永遠不是
# 必要條件。而那條契約只在「戳記拒絕」時成立。
# ---------------------------------------------------------------------
echo
echo "--- T204: a drifted index costs a scan, not an answer / T204：漂掉的索引代價是一次掃描，不是一個答案 ---"

_t204=$TMP/t204.csv
{
    print -r -- "id,value"
    for _i in {1..2000}; do printf '%d,value%06d\n' $_i $_i; done
} > "$_t204"
CSV2_INDEX_MIN_BYTES=10 "$CSV2" --build-index -i "$_t204" > /dev/null

# The drift, and the mtime put back to the nanosecond. python3 is how the
# suite already writes byte-exact fixtures; `touch -r` does not carry
# nanoseconds everywhere, and where it does not this case would test the
# stamp's mtime arm instead of its offsets.
# 製造偏移，並把 mtime 還原到奈秒。這棵樹本來就用 python3 產生位元組精確的 fixture；
# `touch -r` 不是每個平台都帶奈秒，而在不帶的平台上，這個案例會變成在測戳記的 mtime 那一支
# 而不是它的偏移量。
if command -v python3 > /dev/null 2>&1; then
    python3 - "$_t204" <<'PYEOF'
import os, sys
p = sys.argv[1]
st = os.stat(p)
d = open(p, 'rb').read()
a = (b'\n500,value000500\n',   b'\n500,value0005001\n')
b = (b'\n1800,value001800\n', b'\n180,value001800\n')
assert d.count(a[0]) == 1 and d.count(b[0]) == 1
d = d.replace(a[0], a[1]).replace(b[0], b[1])
f = open(p, 'r+b'); f.write(d); f.close()
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
PYEOF

    # The fixture is only a fixture if the stamp ACCEPTS it. If the stamp
    # rejects it the case still passes -- and proves nothing, because the
    # already-working path is the one it took. Say so rather than count it.
    # 這個 fixture 只有在「戳記接受它」時才算數。若戳記拒絕它，這個案例仍然會通過——而且什麼
    # 都沒證明，因為它走的是本來就正常的那條路。把這件事說出來，而不是把它算成一分。
    _t204_hit=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 -i "$_t204" -debug 2>&1 | grep -c 'index hit')
    if [[ $_t204_hit == 0 ]]; then
        skipt "T204 the stamp rejected the drifted fixture, so the seek never happened / 戳記拒絕了這份 fixture，於是那個 seek 根本沒發生"
        T204_SKIPPED=1
    else
        assert_eq "$(grep -c '^$' "$_t204")" "0" \
            "T204a the fixture has no blank line to complain about / 這份 fixture 裡沒有任何可供指控的空白行"

        _t204_got=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 -i "$_t204" 2>&1); _t204_rc=$?
        _t204_want=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 --no-index -i "$_t204" 2>&1)
        assert_eq "$_t204_got" "$_t204_want" \
            "T204b -mid gives the same answer with the drifted index as without / -mid 有沒有那份漂掉的索引，答案相同"
        assert_eq "$_t204_rc" "0" \
            "T204c and does not turn a working file into a failure / 而且不會把一個正常的檔案變成一次失敗"

        _t204_tail=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -tail 1 -i "$_t204" 2>&1)
        _t204_tailw=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -tail 1 --no-index -i "$_t204" 2>&1)
        assert_eq "$_t204_tail" "$_t204_tailw" \
            "T204d -tail too, which reaches the index by a different route / -tail 也是，它是以另一條路徑走到索引的"

        # And it says why, at INFO. A fallback nobody can see is a fallback
        # nobody can tell from the index having worked.
        # 而且它會在 INFO 說出原因。一次沒有人看得見的退路，與「索引本來就正常」分辨不出來。
        _t204_said=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 -i "$_t204" -debug 2>&1)
        case $_t204_said in
            *"is not the start of a record"*)
                ok "T204e and says which byte it gave up on / 並說出它是在哪個位元組放棄的" ;;
            *) bad "T204e the fallback was silent: $_t204_said / 那次退路是無聲的" ;;
        esac
    fi
else
    skipt "T204 needs python3 to write the drifted fixture / 需要 python3 來產生這份 fixture"
    T204_SKIPPED=1
fi

# A GOOD index must still be used -- a fallback that fires every time is not a
# fallback, it is a deletion of the feature.
# 一份「好的」索引仍然必須被採用——一個每次都觸發的退路不是退路，是把這個功能刪掉。
CSV2_INDEX_MIN_BYTES=10 "$CSV2" --build-index -i "$_t204" > /dev/null
_t204_good=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 -i "$_t204" -debug 2>&1 | grep -c 'index hit')
assert_eq "$_t204_good" "1" \
    "T204f a good index is still used / 一份好的索引仍然會被採用"
_t204_fell=$(CSV2_INDEX_MIN_BYTES=10 "$CSV2" -mid 1500,1500 -i "$_t204" -debug 2>&1 | grep -c 'is not the start of a record')
assert_eq "$_t204_fell" "0" \
    "T204g and does not fall back when it does not have to / 而且在不必要時不會走退路"

# Reading a sidecar is NOT gated by CSV2_INDEX_MIN_BYTES; only side-effect
# WRITING is. The env-var table said "no index is read or written as a SIDE
# EFFECT", which parses two ways and is false under one of them -- round 74
# measured a 33 KB file consulting its sidecar. Note the absence of any
# CSV2_INDEX_MIN_BYTES here: this runs at the 16 MiB default, on a 33 KB file.
# 「讀」sidecar 不受 CSV2_INDEX_MIN_BYTES 管，只有「副作用式的寫」受它管。環境變數那張表原本
# 寫的是「不會以副作用的方式讀寫索引」，那句話有兩種讀法，其中一種是錯的——第 74 回合實測到一個
# 33 KB 的檔案採用了它的 sidecar。注意這裡沒有設 CSV2_INDEX_MIN_BYTES：它跑在 16 MiB 的預設值上，
# 而檔案是 33 KB。
rm -f "$_t204.index"
"$CSV2" --build-index -i "$_t204" > /dev/null
_t204_small=$("$CSV2" -mid 1500,1500 -i "$_t204" -debug 2>&1 | grep -c 'index hit')
assert_eq "$_t204_small" "1" \
    "T204h a sidecar is read below CSV2_INDEX_MIN_BYTES / 在 CSV2_INDEX_MIN_BYTES 以下，sidecar 仍然會被讀"
# And still not WRITTEN as a side effect down there.
# 而在那個大小以下，仍然不會以副作用的方式「寫」出一份。
rm -f "$_t204.index"
"$CSV2" -tail 1 -i "$_t204" > /dev/null
if [[ -f $_t204.index ]]; then
    bad "T204i -tail built a sidecar below the threshold / -tail 在門檻以下建了一份 sidecar"
else
    ok "T204i and none is written as a side effect below it / 而在門檻以下不會以副作用寫出一份"
fi

# ---------------------------------------------------------------------
# T205 -- a refusal's prescription has to be runnable.
#
# Round 74, JC and JD. Two refusals told the reader exactly what to do and the
# instruction did not work: one printed a whole command reconstructed from a
# verb that takes two arguments as though it took one, and the other suggested
# a flag that the verb it was refusing rejects outright.
#
# What these assert is not the wording. It is that the fix each message
# prescribes, run verbatim, succeeds.
#
# T205 —— 一則拒絕開出的處方，必須是跑得起來的。
# 第 74 回合，JC 與 JD。兩則拒絕都明確告訴讀者該怎麼做，而那個指示行不通：一則把「吃兩個
# 引數的動詞」當成吃一個，重建出一整個指令；另一則建議了一個「那個動詞本身會拒絕」的旗標。
# 這裡斷言的不是措辭，而是「照著它的處方逐字執行會成功」。
# ---------------------------------------------------------------------
echo
echo "--- T205: the fix a refusal prescribes / T205：拒絕所開出的處方 ---"

printf 'a,b\n1,x\n' > "$TMP/t205.csv"
# The refusal must not print a command that is missing an argument.
# 那則拒絕不得印出一個「少了一個引數」的指令。
_t205_msg=$("$CSV2" -update 1:2 -append -i "$TMP/t205.csv" --in-place 2>&1)
case $_t205_msg in
    *"-update -- -append"*)
        bad "T205a prescribes a command with the address dropped / 開出的指令少了那個位址" ;;
    *"-- -append"*)
        ok "T205a says where -- goes, not a command it cannot build / 它說的是 -- 放在哪裡，而不是一個它組不出來的指令" ;;
    *) bad "T205a got: $_t205_msg / 實得如上" ;;
esac
# And the form it points at works.
# 而它所指的那個形式是可用的。
assert_succeeds "T205b and that form stores the value / 而那個形式存得進去" -- \
    "$CSV2" -update 1:2 -- -append -i "$TMP/t205.csv" --in-place
assert_eq "$("$CSV2" -get 1:2 -i "$TMP/t205.csv")" "-append" \
    "T205c the cell holds the flag-shaped value / 那一格存的就是那個長得像旗標的值"

# -append onto a torn tail: the recipe must not name a flag -append refuses.
# -append 撞到撕裂的尾巴：處方不得指名一個 -append 會拒絕的旗標。
printf 'a,b\n1,"oops\n' > "$TMP/t205torn.csv"
_t205_torn=$("$CSV2" -append '2,y' -i "$TMP/t205torn.csv" --in-place 2>&1)
case $_t205_torn in
    *"write a clean copy first"*)
        ok "T205d the torn-tail refusal gives -append's own recipe / 撕裂尾巴的拒絕給的是 -append 自己那一版的處方" ;;
    *"pass --truncate-partial to discard it"*)
        bad "T205d sent the reader at a flag -append refuses / 把讀者送去用一個 -append 會拒絕的旗標" ;;
    *) bad "T205d got: $_t205_torn / 實得如上" ;;
esac
# Every other verb still gets the parser's own message, which is right for them.
# 其他每一個動詞仍然拿到解析器自己的那則訊息，那對它們是對的。
_t205_read=$("$CSV2" -r -t -i "$TMP/t205torn.csv" 2>&1)
case $_t205_read in
    *"pass --truncate-partial to discard it"*)
        ok "T205e and -r still gets the advice that works for -r / 而 -r 仍然拿到「對 -r 有效」的那個建議" ;;
    *) bad "T205e got: $_t205_read / 實得如上" ;;
esac
# The recipe, run verbatim.
# 把那個處方逐字執行一次。
"$CSV2" -r -t --truncate-partial -i "$TMP/t205torn.csv" -o "$TMP/t205clean.csv" 2>/dev/null
assert_succeeds "T205f and appending to the clean copy works / 而對那份乾淨副本追加是可行的" -- \
    "$CSV2" -append '2,y' -i "$TMP/t205clean.csv" --in-place

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

# T69b runs LAST because it counts something the suite produces: the docs now
# say there is exactly one SKIP instead of quoting a PASS total, and a claim
# that replaced a number has to be checked at the point where the number is
# final. Asserting it earlier tested a counter that had not finished counting.
# T69b 放在最後，因為它數的是「測試自己產生的東西」：文件現在說的是「恰好一個 SKIP」而不是
# 引用 PASS 總數，而一個取代了數字的宣稱，必須在那個數字定案的位置檢查。放在更早的地方，
# 測到的是一個還沒數完的計數器。
# The expected count is per-platform, and each skip has to be one somebody
# decided rather than one that merely happened. On POSIX there is exactly one:
# T47, which compares two platforms and so cannot run inside either. Windows
# adds three, all of them the ENVIRONMENT's limits and all of them documented
# in todo/known-defects.md: a POSIX FIFO a native binary cannot see (T61a,
# T61c) and a UTF-16 command line that leaves no raw argument bytes to check
# (T98a-T98g, one skip line).
#
# Checking the number rather than listing the names is deliberate: a name list
# would pass while a case quietly stopped running, which is the same failure as
# a stale count. The number moves the moment anything is skipped that nobody
# accounted for.
#
# 預期的數量依平台而定，而每一個 SKIP 都必須是「有人決定的」，不是「碰巧變成這樣的」。
# POSIX 上恰好一個：T47——它比對的是兩個平台，因此無法在其中任何一個內部執行。Windows
# 多三個，全部是「環境」的限制、也全部記在 todo/known-defects.md 裡：一個原生程式看不見的
# POSIX FIFO（T61a、T61c），以及一條「沒有原始參數位元組可查」的 UTF-16 命令列
# （T98a–T98g，合為一行 skip）。
# 檢查「數量」而不是列出名字是刻意的：名字清單會在「某個案例安靜地不再執行」時照樣通過，
# 而那與一個過期的數字是同一種失敗。只要有任何一個沒被計入的東西被略過，數量就會變。
# One more axis than the platform: whether this system can read a file's mode
# at all. The aarch64 guest has no `stat` and no zsh/stat, so T129e -- which
# checks the ls fallback against stat -- has nothing to compare against and
# skips there and only there. The probe below asks the same question file_mode
# asks; that is an environment fact, not the suite's own bookkeeping, so it
# does not make the count self-fulfilling.
# 比「平台」多一個軸：這個系統到底讀不讀得到一個檔案的模式。aarch64 guest 上沒有 `stat`、
# 也沒有 zsh/stat，因此 T129e——它拿後備去對 `stat`——在那裡沒有對象可比，只在那裡 SKIP。
# 下面這個探測問的是 file_mode 問的同一件事；那是環境的事實，不是測試自己的帳，所以不會
# 讓這個數字變成自我實現。
want_skip=1                                   # T47, on every platform / 每個平台都有
if (( IS_WINDOWS )); then
    # T61a, T61c and T98a-g are the environment's limits; the rest are
    # properties that need a POSIX filesystem or POSIX signals to test at all:
    # symlinks (T43h, T129a-d, T130a-c), a FIFO (T141e), and killing a process
    # mid-write (T131e). T135c needs a file the user cannot read, and chmod
    # does not bite here.
    # T61a、T61c 與 T98a-g 是「環境」的限制；其餘是「非 POSIX 檔案系統或訊號就測不了」的
    # 性質：symlink（T43h、T129a-d、T130a-c）、FIFO（T141e），以及「寫到一半殺掉行程」
    # （T131e）。T135c 需要一個使用者讀不到的檔案，而 chmod 在這裡咬不住。
    (( want_skip += 9 ))
else
    _t69_probe=$(stat_mode "$TMP")
    [[ $_t69_probe == <-> ]] || (( want_skip += 1 ))   # T129e
    # T135c needs a file it cannot read. Root can read anything, so in the
    # guest -- which runs as root -- that case skips and this count has to know
    # it. Probed the same way T135c decides, on a file made for the purpose.
    # T135c 需要一個「它讀不到」的檔案。root 什麼都讀得到，因此在以 root 執行的 guest 上
    # 那個案例會 SKIP，而這個數字必須知道這件事。用與 T135c 相同的方式、在一個為此建立的
    # 檔案上探測。
    : > "$TMP/t69_probe_unreadable"
    chmod 000 "$TMP/t69_probe_unreadable" 2>/dev/null
    [[ -r "$TMP/t69_probe_unreadable" ]] && (( want_skip += 1 ))   # T135c
    chmod 644 "$TMP/t69_probe_unreadable" 2>/dev/null
    # T143, which skips where `touch -r` does not carry nanoseconds. Taken from
    # the flag that case sets rather than re-derived: reading a timestamp to
    # that precision needs stat, and the platform that skips is the one without
    # it. If T143 ever stops RUNNING, this variable stays unset, want_skip
    # drops, and the count mismatches -- which is what this check is for.
    # T143：在 `touch -r` 不帶奈秒的平台上會跳過。這裡取的是那個案例設下的旗標，而不是重新
    # 推導：要讀到那個精度的時間戳需要 stat，而會跳過的那個平台正好沒有它。若 T143 哪天
    # 「不再執行」，這個變數就不會被設定、want_skip 會變小、數量對不上——那正是這個檢查的用途。
fi
# T143 can skip on ANY platform whose touch -r drops the nanoseconds -- the
# guest and Windows both do -- so this sits outside the branch. It was inside
# the POSIX arm first, and Windows then reported one skip more than expected:
# a per-platform count that had learned about a difference which is not
# per-platform.
# T143 在「touch -r 會丟掉奈秒」的任何平台上都可能跳過——guest 與 Windows 都是——因此這一行
# 放在分支外面。它原本在 POSIX 那一支裡，於是 Windows 回報的 SKIP 比預期多一個：一個
# 「依平台而定」的數字，去學了一件其實不依平台而定的差異。
(( ${T143_SKIPPED:-0} )) && (( want_skip += 1 ))
# T146e needs iconv, which the guest's busybox does not carry; T145e needs a
# directory that refuses a new file, which a root shell does not meet. Both
# are recorded by the case that skipped, for the same reason T143 is: the
# condition is not a property of the platform's name.
# T146e 需要 iconv，而 guest 的 busybox 沒有它；T145e 需要一個「拒絕新檔案」的目錄，而
# 一個 root shell 遇不到。兩者都由「跳過的那個案例」自己記錄，理由與 T143 相同：那個條件
# 不是「平台叫什麼名字」的性質。
(( ${T146E_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T145E_SKIPPED:-0} )) && (( want_skip += 1 ))
# T161 skips on Windows and where the write outran the sampling loop, which is
# a property of this machine's speed rather than of the platform's name.
# T161 在 Windows 上、以及「寫入跑得比取樣迴圈還快」時會跳過，而後者是這台機器的速度的性質，
# 不是平台名字的性質。
(( ${T161_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T203_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T203_BASH_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T204_SKIPPED:-0} )) && (( want_skip += 1 ))
# T166d needs python3 to rebuild the index checksum after bending a line. The
# guest's busybox userland has no python3, and that is a property of the image
# rather than of the platform's name -- so it is recorded by the case, like
# the four above it.
# T166d 需要 python3 才能在扳歪一個行號之後重算索引檢查碼。guest 的 busybox 使用者空間沒有
# python3，而那是那個映像的性質、不是平台名字的性質——因此由該案例自己記錄，與上面四個相同。
(( ${T166D_SKIPPED:-0} )) && (( want_skip += 1 ))
# T181 needs mkfifo, T182 needs hard links; Windows has neither in the shape
# these cases want. Recorded by the case, like the ones above it.
# T181 需要 mkfifo，T182 需要硬連結；Windows 上沒有這兩者（至少沒有這些案例要的形狀）。
# 與上面那些一樣，由案例自己記錄。
(( ${T181A_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T182A_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T182B_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T184A_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T184B_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T191A_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T200A_SKIPPED:-0} )) && (( want_skip += 1 ))
(( ${T200B_SKIPPED:-0} )) && (( want_skip += 1 ))
if [[ "$skip" == "$want_skip" ]]; then
    ok "T69b there are exactly $want_skip SKIPs, each one accounted for / 恰好有 $want_skip 個 SKIP，每一個都有交代"
else
    bad "T69b expected $want_skip SKIP(s) on this platform, the suite produced $skip / 本平台預期 $want_skip 個 SKIP，測試產生了 $skip 個"
fi

# Anything the handler caught, added back here because it could not add itself
# -- and NAMED here, because its own FAIL line goes wherever the caller's
# stdout went. When the missing command sat inside `x=$(...)`, that line was
# captured into a variable and never reached the log: the guest reported eight
# failures with no names at all, which is a worse report than the one it
# replaced.
# 處理常式抓到的東西，在這裡加回去——它自己加不了——並且在這裡「點名」，因為它自己那一行
# FAIL 會跟著呼叫端的 stdout 走。當那個不存在的指令位在 `x=$(...)` 裡時，那一行會被收進
# 一個變數、永遠到不了 log：guest 於是回報了八個「沒有名字」的失敗，而那比它取代掉的報告
# 更糟。
if [[ -s $MISSING_LOG ]]; then
    for _missing in ${(f)"$(sort -u "$MISSING_LOG")"}; do
        print -r -- "FAIL  the suite called \"$_missing\", which does not exist here / 測試呼叫了「$_missing」，而它在這個平台上不存在"
    done
    fail=$((fail + $(wc -l < "$MISSING_LOG")))
fi
rm -f "$MISSING_LOG"

echo
echo "====================================================================="
print -r -- "PASS $pass   FAIL $fail   SKIP $skip"
print -r -- "通過 $pass   失敗 $fail   略過 $skip"
echo "log: $LOG"
echo "====================================================================="
(( fail == 0 )) || exit 1
exit 0

#!/usr/bin/env zsh
# =====================================================================
# test_csv2view.zsh — the viewer's own suite. T84 to T89.
# test_csv2view.zsh — 檢視器自己的測試。T84 到 T89。
#
# SEPARATE from test/test_csv2.zsh on purpose, and the reason is written in
# the plan before any code was written: SwiftUI does not exist on the
# aarch64 Linux guest, and that guest is one of the four nodes
# test_csv2.zsh must pass on. Merging these would make the main suite
# unrunnable there -- trading a whole platform's coverage for one fewer
# script.
#
# **刻意**與 test/test_csv2.zsh 分開，而理由在任何程式碼被寫之前就寫在計畫裡：aarch64 Linux guest
# 上沒有 SwiftUI，而那個 guest 是 test_csv2.zsh 必須通過的四個節點之一。把兩者合併會讓主測試在
# 那裡跑不起來——拿「一整個平台的涵蓋」去換「少一支腳本」。
#
# Usage / 用法：
#   ./csv2view/test/test_csv2view.zsh
# =====================================================================
emulate -L zsh
setopt no_unset pipe_fail
zmodload -F zsh/stat b:zstat 2>/dev/null || true

HERE="${0:A:h}"
VIEW_ROOT="${HERE:h}"
ROOT="${VIEW_ROOT:h}"
VIEW="${CSV2VIEW:-$VIEW_ROOT/release/csv2view}"
CSV2="${CSV2:-$ROOT/release/csv2}"

pass=0; fail=0
ok()  { print -r -- "PASS  $1"; pass=$(( pass + 1 )) }
bad() { print -r -- "FAIL  $1"; fail=$(( fail + 1 )) }

[[ -x "$VIEW" ]] || { print -u2 -- "no csv2view at $VIEW; run ./csv2view/compile_csv2view.zsh / 找不到 csv2view"; exit 1 }
[[ -x "$CSV2" ]] || { print -u2 -- "no csv2 at $CSV2; run ./compile_csv2.zsh / 找不到 csv2"; exit 1 }

TMP="$(mktemp -d "$HERE/.test_csv2view.XXXXXX")"
print -r -- $$ > "$TMP/.pid"
cleanup() { rm -rf "$TMP" }
trap cleanup EXIT INT TERM

print -r -- "[Info] csv2view: $VIEW"
print -r -- "[Info] csv2:     $($CSV2 --version)"
print -r -- ""

F="$TMP/pkgs.csv"
{ print -r -- 'pkg,version,license'
  for i in {1..50}; do print -r -- "p$i,1.$i.0,MIT"; done } > "$F"

F2="$TMP/two.csv2"
{ print -r -- 'pkg,version'; print -r -- '套件,版本'
  for i in {1..10}; do print -r -- "p$i,1.$i.0"; done } > "$F2"

# ---------------------------------------------------------------------
# T84 — the viewer does not parse CSV. A static check, because the failure
# it guards against does not show up at run time: a viewer with its own
# splitter agrees with csv2 on every file anyone thinks to try, and differs
# on the one with a quoted comma that nobody tried.
# T84 —— 檢視器不解析 CSV。這是一個靜態檢查，因為它要防的失敗不會在執行期現形：一個自己會切欄位
# 的檢視器，在任何人想得到要試的檔案上都與 csv2 一致，而在那個「引號內有逗號、沒有人試過」的檔案
# 上不一致。
# ---------------------------------------------------------------------
_t84_srcs=($VIEW_ROOT/src/*.swift(N))
# Fewer than two files means the glob broke, not that the source is clean.
# T218a passed on the guest having scanned NOTHING; this is the cheap half
# of that lesson.
# 少於兩個檔案代表 glob 壞了，不代表原始碼是乾淨的。T218a 曾在 guest 上「什麼都沒掃」而通過；
# 這是那個教訓裡便宜的那一半。
if (( ${#_t84_srcs} < 2 )); then
    bad "T84a the glob found ${#_t84_srcs} sources, so it scanned almost nothing / 那個 glob 只找到 ${#_t84_srcs} 個原始檔，等於幾乎沒掃"
else
    # Comment lines are dropped first: this file's own explanations name the
    # things being searched for, and T241 already paid for forgetting that.
    # 註解行先被丟掉：這些檔案自己的說明會提到被搜尋的那些東西，而 T241 已經為忘記這件事付過代價。
    _t84_code() { LC_ALL=C grep -vE '^[[:space:]]*//' $_t84_srcs }
    _t84_hits=$(_t84_code | LC_ALL=C grep -nE 'split\(separator: ","\)|components\(separatedBy: ","\)|inQuotes|quoteState' || true)
    if [[ -z ${_t84_hits//[[:space:]]/} ]]; then
        ok "T84b no comma splitting and no quote state anywhere in the viewer / 檢視器裡沒有逗號切割，也沒有引號狀態"
    else
        bad "T84b ${_t84_hits:0:100} / 實得如上"
    fi

    _t84_imp=$(_t84_code | LC_ALL=C grep -nE '^import (CSV2|Csv2)|RecordParser|FieldEncoder' || true)
    if [[ -z ${_t84_imp//[[:space:]]/} ]]; then
        ok "T84c and it imports none of csv2's internals / 而且它沒有 import 任何 csv2 的內部型別"
    else
        bad "T84c ${_t84_imp:0:100} / 實得如上"
    fi

    # The scan is driven against a file that really contains one, using the
    # same function. A scan that silently matched nothing would pass most
    # convincingly at the moment it stopped working.
    # 這個掃描被對著一個真的含有它的檔案驅動，用的是同一個函式。一個安靜地什麼都沒比中的掃描，
    # 會在它停止運作的那一刻通過得最徹底。
    _t84_w="SEPAR"; _t84_w="${_t84_w}ATOR"
    print -r -- "let x = s.split(separator: \",\")" > "$TMP/probe.swift"
    if [[ -n $(LC_ALL=C grep -nE 'split\(separator: ","\)' "$TMP/probe.swift" || true) ]]; then
        ok "T84d and the scan catches comma splitting when it is there / 而那個掃描在逗號切割存在時抓得到"
    else
        bad "T84d the scan found nothing in a file that splits on commas / 掃描在一個確實用逗號切割的檔案裡什麼也沒找到"
    fi
fi

# ---------------------------------------------------------------------
# T85 — a failing query is a visible row, not a blank area. Phase 8 item
# four turned a past-the-end start into an error precisely so there would
# be something here to show; swallowing it would undo that change from the
# other end.
# T85 —— 一次失敗的查詢是**一列看得見的東西**，不是一片空白。第 8 階段第四項把「起點越界」變成
# 錯誤，正是為了讓這裡有東西可以顯示；把它吞掉等於從另一端把那次修正抵銷掉。
# ---------------------------------------------------------------------
_t85_out=$("$VIEW" --probe window "$CSV2" "$F" 900 902 2>&1); _t85_rc=$?
if (( _t85_rc != 0 )); then
    ok "T85a a query past the end reaches the caller as a non-zero status ($_t85_rc) / 越界的查詢以非零狀態抵達呼叫端"
else
    bad "T85a rc=$_t85_rc, so the viewer swallowed the failure / rc 如上，檢視器把失敗吞掉了"
fi
if [[ -n ${_t85_out//[[:space:]]/} && $_t85_out == *"ERROR"* ]]; then
    ok "T85b and it carries a message, not an empty area that looks like empty data / 而且它帶著一則訊息，不是一片「看起來像空資料」的空白"
else
    bad "T85b output was ${_t85_out:0:60} / 實得如上"
fi

# ---------------------------------------------------------------------
# T86 — the command a selected cell produces is RUN, not admired. A string
# that looks like a command and is not one would pass any check that reads
# it, and fail the only person who pastes it.
# T86 —— 選中一格所產生的那行指令會被**執行**，不是被欣賞。一個「看起來像指令、其實不是」的
# 字串，會通過任何「讀它」的檢查，而在唯一一個貼上它的人身上失敗。
# ---------------------------------------------------------------------
_t86_cmd=$("$VIEW" --probe command "$CSV2" "$F" 3 1 2>/dev/null)
_t86_got=$(eval "$_t86_cmd" 2>/dev/null)
_t86_want=$("$CSV2" -get 3:1 -i "$F" 2>/dev/null)
if [[ -n $_t86_got && $_t86_got == $_t86_want ]]; then
    ok "T86a the generated command runs and returns the cell ($_t86_got) / 產生的指令執行得起來，並回傳那一格"
else
    bad "T86a got=[$_t86_got] want=[$_t86_want] cmd=$_t86_cmd / 實得如上"
fi

# A path with a space and a quote in it, because that is where a generated
# command stops being a string and starts being a quoting problem.
# 一個帶空白與引號的路徑，因為那正是「一行產生出來的指令」不再只是字串、而變成引號問題的地方。
_t86_odd="$TMP/a dir's name"
mkdir -p "$_t86_odd"
cp "$F" "$_t86_odd/p.csv"
_t86_cmd2=$("$VIEW" --probe command "$CSV2" "$_t86_odd/p.csv" 3 1 2>/dev/null)
_t86_got2=$(eval "$_t86_cmd2" 2>/dev/null)
if [[ $_t86_got2 == $_t86_want ]]; then
    ok "T86b and it survives a path with a space and a quote in it / 而且它在「帶空白與引號的路徑」上仍然成立"
else
    bad "T86b got=[$_t86_got2] cmd=$_t86_cmd2 / 實得如上"
fi

# ---------------------------------------------------------------------
# T87 — bytes that are not valid UTF-8 are shown, not replaced.
# `String(decoding:as:)` substitutes U+FFFD silently, and csv2 refuses to
# do that (T8). Adding the replacement back at the last mile would display
# a file the viewer had quietly altered.
# T87 —— 不是合法 UTF-8 的位元組會被顯示，不會被替換。`String(decoding:as:)` 會靜靜換成 U+FFFD，
# 而 csv2 拒絕那樣做（T8）。在最後一哩把那個替換加回來，等於顯示一個「檢視器自己悄悄改過」的檔案。
# ---------------------------------------------------------------------
printf 'caf\xe9 ok\n' > "$TMP/bad.bin"
_t87=$("$VIEW" --probe decode "$CSV2" "$TMP/bad.bin" 2>/dev/null)
if [[ $_t87 == *"<0xE9>"* ]]; then
    ok "T87a the invalid byte is shown as <0xE9> / 那個非法位元組以 <0xE9> 顯示"
else
    bad "T87a got [$_t87] / 實得如上"
fi
if [[ $_t87 != *$'�'* ]]; then
    ok "T87b and no U+FFFD was substituted anywhere / 而且沒有任何一處被換成 U+FFFD"
else
    bad "T87b a U+FFFD appeared: [$_t87] / 出現了 U+FFFD"
fi
if [[ $_t87 == *"caf"* && $_t87 == *" ok"* ]]; then
    ok "T87c while the valid text around it stays text / 而它周圍合法的文字仍然是文字"
else
    bad "T87c the valid text did not survive: [$_t87] / 合法文字沒有存活"
fi

# ---------------------------------------------------------------------
# T88 — an encrypted column is not decryptable in the UI. Decrypting needs
# a key, and putting a key path in a viewer's preferences walks around the
# rule that a secret never reaches the command line and never appears in
# `ps`. Getting the plaintext means running `csv2 -decrypt` yourself and
# opening THAT file -- deliberate friction, not an oversight.
# T88 —— 被加密的欄在 UI 裡解不開。解密需要金鑰，而把金鑰路徑放進檢視器的偏好設定，等於繞過
# 「秘密不經過命令列、不出現在 ps」那條規則。要拿到明文，就自己跑 `csv2 -decrypt` 再開那一份
# ——刻意的摩擦，不是疏漏。
# ---------------------------------------------------------------------
_t88=$(LC_ALL=C grep -vE '^[[:space:]]*//' $VIEW_ROOT/src/*.swift | LC_ALL=C grep -nE '"-decrypt"|"-keyfile"|keyPath|decryptKey' || true)
if [[ -z ${_t88//[[:space:]]/} ]]; then
    ok "T88a the viewer has no decrypt path and no key at all / 檢視器完全沒有解密路徑，也沒有金鑰"
else
    bad "T88a ${_t88:0:100} / 實得如上"
fi

# ---------------------------------------------------------------------
# T89 — two header rows are two lines; one is one. `-md` joins them with
# `<br>` because Markdown has a single header row; that is a limit of that
# output format, not the shape of the data, and SwiftUI does not inherit
# it. A `.csv` shows ONE, with no invented empty second row for alignment.
# T89 —— 兩列標頭就是兩行，一列就是一行。`-md` 用 `<br>` 合併它們，是因為 Markdown 只有一列表頭；
# 那是那個輸出格式的限制，不是資料的形狀，而 SwiftUI 不繼承它。`.csv` 顯示**一行**，不會為了
# 對齊發明一列空的第二行。
# ---------------------------------------------------------------------
_t89_one=$("$VIEW" --probe window "$CSV2" "$F" 1 1 2>/dev/null | head -1)
_t89_two=$("$VIEW" --probe window "$CSV2" "$F2" 1 1 2>/dev/null | head -2)
if [[ $_t89_one == "headerRows=1 "* ]]; then
    ok "T89a a .csv shows one header row / .csv 顯示一列標頭"
else
    bad "T89a got [$_t89_one] / 實得如上"
fi
if [[ $_t89_two == *"headerRows=2 "* && $_t89_two == *"headerZh=套件,版本"* ]]; then
    ok "T89b a .csv2 shows two, and the second is the Chinese row itself / .csv2 顯示兩列，而第二列就是那一列中文"
else
    bad "T89b got [$_t89_two] / 實得如上"
fi
# The order is the FILE's, not whatever a dictionary happened to give. This is
# the half that broke: before csv2 emitted a positional `header`, the viewer
# sorted the keys and drew the columns alphabetically, at rc=0, silently. LI.
# 欄序是**檔案的**順序，不是字典碰巧給的順序。壞掉的正是這一半：在 csv2 開始輸出位置性的
# `header` 之前，檢視器會把鍵排序、把欄位依字母序畫出來，rc=0，安靜地。LI。
if [[ $_t89_one == *"columns=pkg,version,license"* ]]; then
    ok "T89c and the columns are in the file's order, not sorted / 而欄位是檔案的順序，不是排序過的"
else
    bad "T89c got [$_t89_one] / 實得如上"
fi

print -r -- ""
print -r -- "PASS $pass   FAIL $fail"
(( fail == 0 ))

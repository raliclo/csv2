#!/usr/bin/env zsh
# =====================================================================
#  gen_width.zsh — generate the width tables inside src/Width.swift from the
#                  pinned Unicode data
#  gen_width.zsh — 從固定版本的 Unicode 資料，產生 src/Width.swift 裡的寬度表
#
#    unicode/gen_width.zsh            rewrite the generated region of src/Width.swift
#    unicode/gen_width.zsh -          print that region to stdout (what T315 compares)
#
#  The tables live INSIDE Width.swift, between a BEGIN GENERATED and an END
#  GENERATED line, rather than in a file of their own. A separate
#  WidthTable.swift was the first version, and T212 refused it: Width.swift is
#  one of the six files a GUI caller builds as a library module
#  (verifications/module_api.zsh), and a seventh file it now depended on would
#  have changed a file list someone else relies on. Each marker must occur
#  exactly once or this refuses -- rewriting part of a file by anchor is the
#  thing mistakes.md entry 6 records going wrong when an anchor occurred six
#  times.
#
#  表格住在 Width.swift **裡面**，夾在 BEGIN GENERATED 與 END GENERATED 兩行之間，而不是自己一個
#  檔案。第一版是一個獨立的 WidthTable.swift，而 T212 拒絕了它：Width.swift 是一個 GUI 呼叫端建成
#  library module 的那六個檔案之一（verifications/module_api.zsh），多一個它所依賴的第七個檔案，
#  就改變了別人依賴的一份檔案清單。兩個標記都必須恰好出現一次，否則拒絕——「依錨點改寫檔案的一部分」
#  正是 mistakes.md 第 6 條記錄的那件事，當時那個錨點在檔案裡出現了六次。
#
#  This runs when the Unicode version is raised, never during a build. The
#  build sees an ordinary committed .swift file, so generating the table adds
#  no build-time dependency -- which was the objection that kept todo section
#  3 open: the honest fix was always "generate the ranges from the Unicode
#  character database", and it was declined only because that seemed to mean a
#  dependency at build time. It does not have to. T315 checks that the
#  committed table is exactly what this script produces from the committed
#  data, so the two cannot drift apart unnoticed.
#
#  這支只在升級 Unicode 版本時執行，絕不在建置時執行。建置看到的是一個普通的、已提交的 .swift
#  檔，所以「產生這張表」不會帶來任何建置期依賴——而那正是 todo 第 3 節一直沒關的理由：誠實的
#  修法一直都是「從 Unicode 字元資料庫產生這些區間」，被擋下只是因為那看起來像是一個建置期依賴。
#  它不必是。T315 檢查已提交的表格正好等於這支腳本從已提交的資料產生出來的結果，所以兩者不可能
#  安靜地漂開。
#
#  To raise the version: put the new EastAsianWidth.txt and
#  extracted/DerivedGeneralCategory.txt under unicode/<version>/, change
#  VERSION below, run this, run the suite, commit all of it together.
#  升級版本：把新的 EastAsianWidth.txt 與 extracted/DerivedGeneralCategory.txt 放進
#  unicode/<版本>/，改下面的 VERSION，跑這支，跑測試，全部一起提交。
#
#  Rules, each a decision written down rather than left implicit:
#  規則——每一條都是寫下來的決定，而不是留在程式裡的隱含假設：
#
#   wide (2)  East_Asian_Width W or F; plus the blocks UAX #11 says default to
#             W when unlisted (CJK Ext A, CJK Unified, CJK Compatibility,
#             planes 2 and 3). A default range that contains a code point
#             listed as something OTHER than W is refused rather than
#             overwritten -- the default applies only to what is not listed.
#             Plus the Regional Indicators 1F1E6..1F1FF, which UAX #11 lists
#             as N but which pair into a flag that terminals draw two columns
#             wide. The plan measured 🇹🇼 as 2 and T48 pins it; generating
#             strictly from the data would have measured every flag as 1.
#             That was found by diffing this table against the hand-written
#             one before switching, not by a test failing afterwards.
#   zero (0)  General_Category Mn, Me, Cf, Zl, Zp; plus Hangul Jamo medial
#             vowels and final consonants (1160..11FF, D7B0..D7FF), which
#             join the syllable before them; minus U+00AD SOFT HYPHEN, which
#             is Cf but is conventionally shown, and was width 1 before.
#   Zero is checked before wide in DisplayWidth.ofScalar, so a mark that is
#   both Mn and W (302A..302D, the ideographic tone marks) is zero.
#
#   寬（2）  East_Asian_Width 為 W 或 F；加上 UAX #11 說「未列出時預設為 W」的區塊（CJK 擴充 A、
#            CJK 統一、CJK 相容、第 2 與第 3 平面）。若某個預設區塊裡有一個被明列為**非 W** 的碼位，
#            就拒絕產生，而不是蓋過它——預設只適用於沒有被列出的碼位。另加區域指示符號
#            1F1E6..1F1FF：UAX #11 把它們列為 N，但兩兩組成國旗時終端機畫成 2 欄。計畫實測 🇹🇼
#            是 2，T48 釘住它；嚴格照資料產生會把每一面國旗都量成 1。這是切換之前拿這張表與手寫的
#            那張做差集時發現的，不是事後靠測試失敗才發現。
#   零（0）  General_Category 為 Mn、Me、Cf、Zl、Zp；加上諺文字母的中聲與終聲（1160..11FF、
#            D7B0..D7FF），它們併入前一個音節；扣掉 U+00AD 軟連字號，它是 Cf，但慣例上會顯示，
#            而且先前就是寬度 1。
#   DisplayWidth.ofScalar 先判斷零再判斷寬，所以同時是 Mn 與 W 的記號（302A..302D 的漢字聲調
#   記號）算 0。
#
#  The output is deterministic -- no timestamp, no hostname -- because T315
#  compares it byte for byte. 輸出是確定性的（沒有時間戳、沒有主機名），因為 T315 逐位元比對它。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail err_return

HERE=${0:A:h}
VERSION=17.0.0
DIR=$HERE/$VERSION
EAW=$DIR/EastAsianWidth.txt
DGC=$DIR/DerivedGeneralCategory.txt

die() { print -ru2 -- "gen_width.zsh: $*"; exit 1 }

MODE=${1:-write}
[[ $MODE == (write|-) ]] || die "usage: gen_width.zsh [-] / 用法：gen_width.zsh [-]"
TARGET=${HERE:h}/src/Width.swift
BEGIN_MARK='    // BEGIN GENERATED by unicode/gen_width.zsh. Do not edit by hand; run it instead.'
END_MARK='    // END GENERATED'
[[ -r $EAW ]] || die "missing / 找不到: $EAW"
[[ -r $DGC ]] || die "missing / 找不到: $DGC"

# The version a file says it is must be the version this script says it reads.
# Copying a new file into an old directory would otherwise produce a table
# labelled with the wrong version, and nothing would say so.
# 檔案自稱的版本必須等於這支腳本說它讀的版本。否則把新檔案放進舊目錄，會產生一張標錯版本的表，
# 而沒有任何東西會說出來。
for f in $EAW $DGC; do
    [[ $(head -1 $f) == "# ${f:t:r}-$VERSION.txt" ]] ||
        die "${f:t} does not say it is $VERSION (first line: $(head -1 $f)) / ${f:t} 沒有自稱是 $VERSION"
done

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | cut -d' ' -f1
    else openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1; fi
}

# parse <file> <pattern> -- every data line whose property matches, as
# "start end" in decimal. Field 0 is a code point or a range a..b; field 1 is
# the property value; everything after # is a comment.
# parse <檔案> <樣式>——每一行屬性符合的資料，以十進位印成「起 迄」。第 0 欄是一個碼位或一個
# a..b 區間；第 1 欄是屬性值；# 之後全是註解。
parse() {
    local file=$1 pat=$2 line cp val lo hi
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line == [0-9A-F]* ]] || continue
        line=${line%%\#*}
        cp=${${line%%;*}//[[:space:]]/}
        val=${${line#*;}//[[:space:]]/}
        [[ $val == ${~pat} ]] || continue
        if [[ $cp == *..* ]]; then lo=${cp%%..*}; hi=${cp##*..}; else lo=$cp; hi=$cp; fi
        print -r -- "$(( 16#$lo )) $(( 16#$hi ))"
    done < $file
}

# merge -- read "start end" lines in any order, print them sorted with every
# overlapping or adjacent pair joined.
# merge——讀入任意順序的「起 迄」，排序後把重疊或相鄰的區間合併印出。
merge() {
    local -a rows
    rows=(${(f)"$(LC_ALL=C sort -n -k1,1 -k2,2)"})
    local -i lo=-1 hi=-1 l h
    local r
    for r in $rows; do
        l=${r% *}; h=${r#* }
        if (( lo < 0 )); then lo=l; hi=h
        elif (( l <= hi + 1 )); then (( h > hi )) && hi=h
        else print -r -- "$lo $hi"; lo=l; hi=h
        fi
    done
    (( lo >= 0 )) && print -r -- "$lo $hi"
    return 0
}

# The default-W blocks, from the header of EastAsianWidth.txt.
# 預設為 W 的區塊，取自 EastAsianWidth.txt 的標頭。
typeset -a DEFAULT_W
DEFAULT_W=("$(( 16#3400 )) $(( 16#4DBF ))" "$(( 16#4E00 )) $(( 16#9FFF ))"
           "$(( 16#F900 )) $(( 16#FAFF ))" "$(( 16#20000 )) $(( 16#2FFFD ))"
           "$(( 16#30000 )) $(( 16#3FFFD ))")

# Refuse rather than overwrite: a code point listed as anything but W inside a
# default-W block means the default does not cover it.
# 拒絕而不是蓋過：預設為 W 的區塊裡若有一個被列為非 W 的碼位，那個預設就不涵蓋它。
nonw=$(parse $EAW '(A|F|H|N|Na)')
for d in $DEFAULT_W; do
    dlo=${d% *}; dhi=${d#* }
    for r in ${(f)nonw}; do
        rlo=${r% *}; rhi=${r#* }
        (( rlo <= dhi && rhi >= dlo )) &&
            die "$(printf '%04X..%04X' $rlo $rhi) is listed as non-W inside default-W block $(printf '%04X..%04X' $dlo $dhi) / 預設為 W 的區塊裡有被列為非 W 的碼位"
    done
done

wide=$( { parse $EAW '(W|F)'; print -rl -- $DEFAULT_W
          print -r -- "$(( 16#1F1E6 )) $(( 16#1F1FF ))"; } | merge )

# Zero: the categories, the Jamo additions, and U+00AD taken back out. The soft
# hyphen is split out of whatever range contains it rather than assumed to sit
# on a line of its own.
# 零：那些類別、諺文字母的補充，再把 U+00AD 拿出來。軟連字號是從包含它的區間裡切出去，而不是
# 假設它自己單獨一行。
zero_raw=$( { parse $DGC '(Mn|Me|Cf|Zl|Zp)'
              print -r -- "$(( 16#1160 )) $(( 16#11FF ))"
              print -r -- "$(( 16#D7B0 )) $(( 16#D7FF ))"; } )
shy=$(( 16#00AD ))
zero=$( for r in ${(f)zero_raw}; do
            l=${r% *}; h=${r#* }
            if (( l <= shy && shy <= h )); then
                (( l < shy )) && print -r -- "$l $(( shy - 1 ))"
                (( shy < h )) && print -r -- "$(( shy + 1 )) $h"
            else
                print -r -- "$l $h"
            fi
        done | merge )

emit() {   # emit <name> <rows>
    local name=$1 rows=$2 r
    local -a cells
    for r in ${(f)rows}; do cells+=("$(printf '(0x%04X, 0x%04X)' ${r% *} ${r#* })"); done
    print -r -- "    private static let $name: [(UInt32, UInt32)] = ["
    local i
    for (( i = 1; i <= $#cells; i += 4 )); do
        print -r -- "        ${(j:, :)cells[i,i+3]},"
    done
    print -r -- "    ]"
}

# The region, markers included. Deterministic: no timestamp, no hostname.
# 那一段，含兩個標記。確定性：沒有時間戳、沒有主機名。
render() {
    print -r -- "$BEGIN_MARK"
    print -r -- "    // 由 unicode/gen_width.zsh 產生。不要手動修改，要改就跑它。"
    print -r -- "    //"
    print -r -- "    //   Unicode $VERSION"
    print -r -- "    //   ${EAW:t}  sha256 $(sha256_of $EAW)"
    print -r -- "    //   ${DGC:t}  sha256 $(sha256_of $DGC)"
    print -r -- "    //"
    print -r -- "    // The rules are written at the top of unicode/gen_width.zsh. T315 checks"
    print -r -- "    // that this region is exactly what that script produces from those files."
    print -r -- "    // 規則寫在 unicode/gen_width.zsh 開頭。T315 檢查這一段正好等於那支腳本從那兩個檔案產生的結果。"
    print -r -- "    static let unicodeVersion = \"$VERSION\""
    print -r -- ""
    print -r -- "    /// East Asian Wide and Fullwidth, the blocks that default to Wide, and"
    print -r -- "    /// the Regional Indicators. Sorted, and searched by bisection."
    print -r -- "    /// East Asian Wide 與 Fullwidth、預設為 Wide 的區塊、以及區域指示符號。已排序，以二分搜尋。"
    emit wideRanges "$wide"
    print -r -- ""
    print -r -- "    /// Marks, format characters and conjoining Jamo: no columns of their own."
    print -r -- "    /// 記號、格式字元與組合用的諺文字母：自己不佔任何欄位。"
    emit zeroRanges "$zero"
    print -r -- "$END_MARK"
}

if [[ $MODE == - ]]; then
    render
    exit 0
fi

# Write: replace the region in Width.swift. Each marker exactly once, BEGIN
# first -- otherwise refuse and touch nothing.
# 寫入：替換 Width.swift 裡的那一段。每個標記恰好一次、BEGIN 在前——否則拒絕，什麼都不動。
[[ -r $TARGET ]] || die "missing / 找不到: $TARGET"
typeset -a lines
lines=()
while IFS= read -r ln || [[ -n $ln ]]; do lines+=("$ln"); done < $TARGET
integer nb=0 ne=0 ib=0 ie=0 i
for (( i = 1; i <= $#lines; i++ )); do
    [[ ${lines[i]} == "$BEGIN_MARK" ]] && { nb+=1; ib=i }
    [[ ${lines[i]} == "$END_MARK" ]] && { ne+=1; ie=i }
done
(( nb == 1 && ne == 1 && ib < ie )) ||
    die "${TARGET:t} must contain the BEGIN and END GENERATED markers exactly once each, BEGIN first (found $nb and $ne) / 兩個標記必須各恰好一次、BEGIN 在前（找到 $nb 與 $ne）"
tmp=$TARGET.gen.$$
{
    (( ib > 1 )) && print -rl -- "${(@)lines[1,ib-1]}"
    render
    (( ie < $#lines )) && print -rl -- "${(@)lines[ie+1,-1]}"
} > $tmp
mv -f -- $tmp $TARGET
print -r -- "rewrote the generated region of ${TARGET:A} -- wide $(print -r -- $wide | grep -c '') ranges, zero $(print -r -- $zero | grep -c '') ranges"

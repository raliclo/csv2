#!/usr/bin/env zsh
# =====================================================================
#  release.zsh — package the built csv2 for THIS platform as .tar.zst
#  release.zsh — 把這個平台上已建置的 csv2 打包成 .tar.zst
#
#  Run it on each node; each produces one archive for the platform it ran
#  on. There is no cross-packaging: an archive is made from a binary that
#  was built and tested where the archive is made, which is the only way
#  the version inside it can be checked by running it.
#  在每個節點上各跑一次；每一次產生「它所在平台」的一份封存。這裡沒有交叉打包：一份封存
#  來自「在打包的地方建置並測試過」的執行檔——那是唯一能以「執行它」來檢查版本的方式。
#
#    ./release.zsh           package release/csv2[.exe] into dist/ / 把 release/csv2[.exe] 打包進 dist/
#    ./release.zsh --help    print this and do nothing / 印出這段說明，什麼都不做
#
#  It takes no other argument, and refuses one rather than ignoring it: an
#  ignored flag would package an untagged build under the release's own name
#  and report it verified. RB.
#  它不收其他引數，而且會拒絕而不是忽略：被忽略的旗標，會讓一份未打 tag 的建置掛著
#  正式封存的名字被打包，並回報已驗證。RB。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail errexit

# Before anything else runs: a wrong flag costs a line of output, not an archive.
# 在任何事情執行之前：打錯一個旗標，代價是一行輸出，不是一份封存。
case ${1:-} in
    '') ;;
    -h|--help) sed -n '3,20p' ${0:A} | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) print -r -u2 -- "release.zsh takes no argument (got: $1); see --help / release.zsh 不收引數（收到：$1），請見 --help"; exit 2 ;;
esac

# A release script that dies quietly leaves a half-written archive with a
# plausible name. Say that it failed.
# 一支安靜死掉的發行腳本，會留下一份名字看起來很合理的半成品封存。要說出它失敗了。
TRAPZERR() {
# No line number: `$LINENO` inside a trap function reports the line within THAT
# FUNCTION, not the line that failed. A message naming the wrong line is worse
# than one naming none -- it sends the reader somewhere and they believe it.
# 不報行號：`$LINENO` 在 trap 函式內回報的是**那個函式**裡的行號，不是失敗的那一行。
# 指名錯行號的訊息比不指名更糟——它把讀者帶到別處，而讀者會相信它。
    print -u2 -- "release.zsh: a command failed; nothing in dist/ should be trusted"
    print -u2 -- "release.zsh：某個命令失敗；dist/ 裡的東西一律不可信"
}

HERE=${0:A:h}
cd -- "$HERE"

# The version comes from the BINARY, not from a constant written here: a
# constant is wrong exactly when the version changes, and then the archive name
# and the binary inside disagree while every other check still passes. QI.
#
# 版本來自**執行檔**，不是寫在這裡的常數：常數恰好在版本改變時出錯，那時封存的名字與
# 裡面的執行檔不一致，而其他每一道檢查仍然通過。QI。
DIST=$HERE/dist

# ---------------------------------------------------------------------
# Which file did this platform build? compile_csv2.zsh's Windows branch
# produces csv2.exe; with only the POSIX name, a node that just built
# successfully would exit "build first". PD.
# 這個平台建出來的是哪一個檔案？compile_csv2.zsh 的 Windows 分支產生 csv2.exe；只寫 POSIX
# 檔名，剛建置成功的節點也會以「build first」結束。PD。
# ---------------------------------------------------------------------
if [[ -x $HERE/release/csv2 ]]; then
    BIN=$HERE/release/csv2
    BIN_NAME=csv2
elif [[ -x $HERE/release/csv2.exe ]]; then
    BIN=$HERE/release/csv2.exe
    BIN_NAME=csv2.exe
else
    print -u2 -- "no built binary; run ./compile_csv2.zsh first"
    print -u2 -- "找不到已建置的執行檔；請先執行 ./compile_csv2.zsh"
    exit 1
fi

case "$(uname -s)" in
    Darwin)                        OS=macos ;;
    Linux)                         OS=linux ;;
    MSYS*|MINGW*|CYGWIN*|Windows*) OS=windows ;;
    *)                             OS=$(uname -s | tr '[:upper:]' '[:lower:]') ;;
esac
# The binary is asked EVERY time, whatever the environment holds. VERSION is a
# common name and CI sets it, so taking an inherited one would package a binary
# under another version's name. RE.
#
# An inherited VERSION that AGREES is harmless; one that disagrees is refused
# rather than silently overridden, because whoever set it expected something
# this run is not going to produce.
# **每一次**都去問執行檔，不管環境裡有什麼。VERSION 是常見的名字，CI 也會設；若採用繼承來的
# 值，執行檔就會被掛上別的版本號打包。RE。
# 繼承來的 VERSION 若**相符**則無害；不相符時拒絕而不是靜默覆蓋，因為設定它的人預期的是
# 這次執行不會產生的東西。
_env_version=${VERSION:-}
_rv=$("$BIN" --version 2>/dev/null)
# `csv2 <version> (<id>)`. Taken as the second field and then REQUIRED to
# look like a version, so a changed format gives a refusal rather than a
# plausible wrong name.
# `csv2 <版本> (<id>)`。取第二個欄位，然後**要求**它長得像一個版本號——這樣一來，格式改變會
# 得到一則拒絕，而不是一個看起來合理的錯名字。
VERSION=${${(z)_rv}[2]}
if [[ $VERSION != <->.<->.<-> ]]; then
    print -u2 -- "cannot read a version out of [$_rv]; refusing to name an archive by guessing"
    print -u2 -- "從 [$_rv] 讀不出版本號；拒絕用猜的方式為封存命名"
    exit 1
fi
if [[ -n $_env_version && $_env_version != "$VERSION" ]]; then
    print -r -u2 -- "VERSION=$_env_version is set in the environment but the binary reports $VERSION; the archive is named from the binary, so unset VERSION or rebuild"
    print -r -u2 -- "環境裡設了 VERSION=$_env_version，而執行檔回報的是 $VERSION；封存以執行檔為準命名，請取消 VERSION 或重新建置"
    exit 1
fi
ARCH=$(uname -m)
STEM=csv2-$VERSION-$OS-$ARCH
ARCHIVE=$DIST/$STEM.tar.zst

# ---------------------------------------------------------------------
# Three refusals, all of them about the archive describing something other
# than what it contains.
#
# 三道拒絕，全部是關於「封存所描述的」與「封存裡實際裝的」不是同一個東西。
# ---------------------------------------------------------------------

# 1. zstd, by name, because the archive extension is a promise about the
#    format and a missing tool must not become a .tar named .tar.zst.
# 1. zstd，指名檢查——因為副檔名是一個關於格式的承諾，而一個缺席的工具不可以變成
#    「一個叫 .tar.zst 的 .tar」。
if ! command -v zstd >/dev/null 2>&1; then
    print -u2 -- "zstd is not on PATH; releases are .tar.zst and this platform cannot make one"
    print -u2 -- "zstd 不在 PATH 上；發行檔是 .tar.zst，而這個平台做不出來"
    exit 1
fi

# 2. A dirty tree means the archive's commit id names a state that is not
#    what was packaged.
# 2. 工作區不乾淨，代表封存上的 commit id 指的是一個「不等於被打包內容」的狀態。
if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 -- "the working tree is not clean; an archive built from it would carry a commit id that describes something else"
    print -u2 -- "工作區不乾淨；由它產生的封存，會帶著一個描述著別的東西的 commit id"
    git status --porcelain >&2
    exit 1
fi

# 3. The binary must report the commit that is checked out. `--version` is
#    asked for by RUNNING it, not by reading the file, because "the file is
#    there" proves nothing about what it reports.
# 3. 執行檔必須回報「目前 checkout 的那個 commit」。`--version` 是靠**執行它**問出來的，
#    不是靠讀檔案——因為「檔案在那裡」證明不了它回報什麼。
REPORTED=$("$BIN" --version)
# Ask the code that PRODUCED the id, do not derive a second answer. Both
# compile scripts take it from csv2_build_id in build_id.zsh, so comparing
# against the same function cannot disagree with them about form. A check that
# enumerates the forms the string can take instead -- `(SHORTHASH`, "the hash
# appears somewhere" -- refuses at a tagged commit, where `describe` answers
# only the tag. QC.
#
# 問「產生那個 id 的程式」，不要自己推導出第二個答案。兩支編譯腳本都從 build_id.zsh 的
# csv2_build_id 取得它，因此拿同一個函式去比，不可能在形式上分歧。改用列舉字串可能形式的
# 檢查（`(SHORTHASH`、「雜湊出現在某處」），會在打了 tag 的 commit 上拒絕——那裡 `describe`
# 只回答 tag。QC。
source "${0:A:h}/build_id.zsh"
EXPECTED_ID=$(csv2_build_id "${0:A:h}")
# ANCHORED, not "contains": at v0.1.0 the expected id is `v0.1.0`, and
# `csv2 0.1.0 (v0.1.0-13-g1750de3)` contains that string, so containment would
# ship a binary built thirteen commits later as the release. Test the refusal
# direction; that is the direction a guard is for.
#
# 用**錨定**，不用「包含」：在 v0.1.0 上預期的 id 是 `v0.1.0`，而
# `csv2 0.1.0 (v0.1.0-13-g1750de3)` **含有**那個字串，比包含就會把晚了十三個 commit 的執行檔
# 當成那次 release 出貨。要測「拒絕」的方向，那才是守衛存在的方向。
if [[ $REPORTED != *"($EXPECTED_ID)" ]]; then
    print -u2 -- "the binary reports [$REPORTED] but this checkout is [$EXPECTED_ID]; rebuild before releasing"
    print -u2 -- "執行檔回報 [$REPORTED]，而這個 checkout 是 [$EXPECTED_ID]；發行前請重新建置"
    exit 1
fi

# ---------------------------------------------------------------------
# Pack. The archive holds one directory so an extraction cannot scatter
# files into the caller's cwd -- the difference between `tar xf` being safe
# and being a mess someone has to clean up by hand.
# 打包。封存裡只有一個目錄，這樣解開時不會把檔案灑進呼叫端的目前目錄——那是
# 「`tar xf` 是安全的」與「有人得手動收拾」之間的差別。
# ---------------------------------------------------------------------
# Refuse to overwrite. Replacing an archive and its .sha256 leaves a
# self-consistent pair that is no longer the file anyone downloaded, and making
# an archive has no reason to overwrite one. QI.
# 拒絕覆寫。取代一份封存與它的 .sha256，會留下一對彼此自洽、卻已不是任何人下載到的檔案；
# 「產生一份封存」沒有任何理由需要覆寫另一份。QI。
if [[ -e $ARCHIVE ]]; then
    print -u2 -- "$ARCHIVE already exists; remove it first if you mean to replace it"
    print -u2 -- "$ARCHIVE 已經存在；若真要取代它，請先自行刪除"
    exit 1
fi
rm -rf -- "$DIST/$STEM"
mkdir -p -- "$DIST/$STEM"
cp -- "$BIN" "$DIST/$STEM/$BIN_NAME"
cp -- "$HERE/LICENSE" "$HERE/README.md" "$HERE/README.zh-TW.md" "$DIST/$STEM/"
chmod 755 "$DIST/$STEM/$BIN_NAME"

# Every tool below is given a RELATIVE name from inside the right directory,
# never an absolute one. `$DIST` comes from `${0:A:h}`, which on Windows is
# MSYS-style `/c/Users/...` because that is what zsh's `pwd` gives there -- and
# zstd and csv2.exe are native Windows programs that cannot open it:
#
#     echo hi | zstd -q -o /c/Users/.../probe.zst   No such file or directory
#     echo hi | zstd -q -o C:/Users/.../probe.zst   ok
#     echo hi | zstd -q -o dist/probe.zst           ok
#
# QO.
#
# 底下每一個工具拿到的都是「從正確目錄裡看出去的相對名稱」，不是絕對路徑。`$DIST` 來自
# `${0:A:h}`，在 Windows 上是 MSYS 風格的 `/c/Users/...`（那是 zsh 的 `pwd` 在那裡給的形狀），
# 而 zstd 與 csv2.exe 是原生 Windows 程式，開不了它——相對路徑與原生路徑都可以，只有絕對的
# MSYS 路徑不行。QO。
( cd -- "$DIST" && tar -cf - "$STEM" | zstd -19 -q -o "$STEM.tar.zst" )

# ---------------------------------------------------------------------
# Verify by EXTRACTING AND RUNNING, not by checking the archive exists.
#
# This is compile_csv2.zsh's rule applied one layer out. An archive that
# unpacks to a binary this machine cannot execute is exactly the failure a
# release makes permanent: whoever finds it did not build it and cannot
# rebuild it.
#
# 以「解開並執行」驗證，而不是檢查封存存在。
#
# 這是 compile_csv2.zsh 那條規則往外推一層。一份「解開後得到一個這台機器執行不了的執行檔」的
# 封存，正是發行會讓它變成永久的那種失敗：發現它的人不是建置者，也無法重建它。
# ---------------------------------------------------------------------
CHECK=$(mktemp -d "$DIST/.verify.XXXXXX")
trap 'rm -rf -- "$CHECK"' EXIT
( cd -- "$DIST" && zstd -dq -c "$STEM.tar.zst" ) | ( cd -- "$CHECK" && tar -xf - )
EXTRACTED=$CHECK/$STEM/$BIN_NAME
[[ -x $EXTRACTED ]] || { print -u2 -- "the archive does not contain an executable $BIN_NAME"; exit 1 }
EXTRACTED_VERSION=$("$EXTRACTED" --version)
if [[ $EXTRACTED_VERSION != "$REPORTED" ]]; then
    print -u2 -- "the extracted binary reports [$EXTRACTED_VERSION], the source one [$REPORTED]"
    print -u2 -- "解開後的執行檔回報 [$EXTRACTED_VERSION]，來源那個回報 [$REPORTED]"
    exit 1
fi

# And it must still be able to READ a file, because a binary that starts and
# prints its version has proved only that it starts.
# 而它還必須真的讀得了一個檔案——因為一個「啟動並印出版本」的執行檔，只證明了它啟動得起來。
printf 'pkg,license\nzlib,MIT\n' > "$CHECK/probe.csv"
# csv2.exe is a native Windows program too, so it is asked from inside $CHECK
# with a bare filename rather than handed the absolute path. QO.
# csv2.exe 同樣是原生 Windows 程式，因此從 $CHECK 裡面以裸檔名問它，不把絕對路徑交給它。QO。
PROBE=$( cd -- "$CHECK" && "./$STEM/$BIN_NAME" -get 1:license -i probe.csv )
[[ $PROBE == MIT ]] || { print -u2 -- "the extracted binary could not read a CSV: got [$PROBE]"; exit 1 }

# ---------------------------------------------------------------------
# sha256, written beside the archive in the shape `shasum -c` accepts. The
# tool is named per platform: this tree does not use `shasum`, which is a
# Perl script and absent from the aarch64 guest.
# sha256，以 `shasum -c` 接受的形狀寫在封存旁邊。工具依平台指名：這棵樹不使用 `shasum`
# ——它是一支 Perl 腳本，而 aarch64 guest 上沒有 Perl。
# ---------------------------------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then
    ( cd -- "$DIST" && sha256sum "$STEM.tar.zst" > "$STEM.tar.zst.sha256" )
elif command -v openssl >/dev/null 2>&1; then
    ( cd -- "$DIST" && printf '%s  %s\n' "$(openssl dgst -sha256 -r "$STEM.tar.zst" | cut -d' ' -f1)" "$STEM.tar.zst" > "$STEM.tar.zst.sha256" )
else
    print -u2 -- "no sha256sum and no openssl; a release without a checksum is not a release"
    print -u2 -- "沒有 sha256sum 也沒有 openssl；一份沒有校驗和的發行檔不算發行檔"
    exit 1
fi

rm -rf -- "$DIST/$STEM"
print -r -- "$ARCHIVE"
print -r -- "$(cat "$DIST/$STEM.tar.zst.sha256")"
print -r -- "verified: extracted, ran, and read a CSV / 已驗證：解開、執行過，而且讀得了一個 CSV"

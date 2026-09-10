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
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail errexit

# A release script that dies quietly leaves a half-written archive with a
# plausible name. Say where it stopped.
# 一支安靜死掉的發行腳本，會留下一份名字看起來很合理的半成品封存。要說出它停在哪裡。
TRAPZERR() {
# No line number: `$LINENO` inside a trap function reports the line within THAT
# FUNCTION, not the line that failed. On 2026-09-10 this printed "stopped at
# line 2" for a failure a hundred lines away. A message naming the wrong line is
# worse than one naming none -- it sends the reader somewhere and they believe it.
# 不報行號：`$LINENO` 在 trap 函式內回報的是**那個函式**裡的行號，不是失敗的那一行。
# 2026-09-10 它為一個相隔上百行的失敗印出「停在第 2 行」。一則指名錯行號的訊息，比不指名
# 更糟——它把讀者送去某個地方，而他們會相信它。
    print -u2 -- "release.zsh: a command failed; nothing in dist/ should be trusted"
    print -u2 -- "release.zsh：某個命令失敗；dist/ 裡的東西一律不可信"
}

HERE=${0:A:h}
cd -- "$HERE"

# The version comes from the BINARY, not from a constant written here. This
# line said `${VERSION:-0.1.0}` until 2026-09-10, and on the day v0.1.1 was cut
# it packaged a binary reporting `csv2 0.1.1` into an archive named
# `csv2-0.1.0-macos-arm64.tar.zst`, said "verified: extracted, ran, and read a
# CSV" -- which was TRUE, every check held and none of them was the name -- and
# overwrote the local copy of the PUBLISHED v0.1.0 archive on the way. QI.
#
# A constant that is only wrong when the version changes is wrong at the one
# moment it matters. Same family as QC and QD: what this script knew about what
# it was releasing came from inside itself rather than from the thing it was
# releasing.
#
# 版本來自**執行檔**，不是來自寫在這裡的一個常數。這一行直到 2026-09-10 為止寫的是
# `${VERSION:-0.1.0}`，而在 v0.1.1 被打出來的那天，它把一個回報 `csv2 0.1.1` 的執行檔打包成一份
# 叫 `csv2-0.1.0-macos-arm64.tar.zst` 的封存，然後說「已驗證：解開、執行過，而且讀得了一個
# CSV」——那是**真的**，它檢查的每一件事都成立，而其中沒有一件是「這個名字對不對」——並且順手
# 覆蓋掉了**已發布**的 v0.1.0 封存的本機複本。QI。
#
# 一個「只有在版本改變時才會錯」的常數，會在它唯一要緊的那一刻出錯。與 QC、QD 同一族：這支腳本
# 對「它正在發行什麼」的認識，來自它自己，而不是來自它正在發行的那個東西。
VERSION=${VERSION:-}
if [[ -z $VERSION ]]; then
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
fi
DIST=$HERE/dist

# ---------------------------------------------------------------------
# Which file did this platform build? compile_csv2.zsh's Windows branch
# produces csv2.exe; naming only the POSIX one is what made measure.zsh
# exit "build first" on a node that had just built successfully (PD).
# 這個平台建出來的是哪一個檔案？compile_csv2.zsh 的 Windows 分支產生 csv2.exe；只指名
# POSIX 那個名字，正是讓 measure.zsh 在一個剛建置成功的節點上印出「build first」的原因（PD）。
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
#    what was packaged. This tree has paid for that once already: a commit
#    string written into a timestamp column, with nothing raising an error.
# 2. 工作區不乾淨，代表封存上的 commit id 指的是一個「不等於被打包的內容」的狀態。這棵樹
#    為此付過一次代價：一個 commit 字串被寫進時間戳欄位，而沒有任何東西報錯。
if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 -- "the working tree is not clean; an archive built from it would carry a commit id that describes something else"
    print -u2 -- "工作區不乾淨；由它產生的封存，會帶著一個描述著別的東西的 commit id"
    git status --porcelain >&2
    exit 1
fi

# 3. The binary must report the commit that is checked out. `--version` is
#    asked for by RUNNING it, not by reading the file, because "the file is
#    there" is the check this project keeps finding to be worthless.
# 3. 執行檔必須回報「目前 checkout 的那個 commit」。`--version` 是靠**執行它**問出來的，
#    不是靠讀檔案——因為「檔案在那裡」正是這個專案一再發現毫無價值的那種檢查。
REPORTED=$("$BIN" --version)
# Ask the expression that PRODUCED the id, do not derive a second answer.
# compile_csv2.zsh and compile_csv2_linux.zsh both embed
# `git describe --always --dirty`, so comparing against the same call cannot
# disagree with them about form.
#
# 問「產生那個 id 的運算式」，不要自己推導出第二個答案。compile_csv2.zsh 與
# compile_csv2_linux.zsh 內嵌的都是 `git describe --always --dirty`，因此拿同一次呼叫去比，
# 不可能與它們在形式上分歧。
#
# This check has now been wrong twice, both times by enumerating the forms that
# string can take instead of asking for it. First it compared for equality
# against `(SHORTHASH`, and v0.1.0 made `describe` answer
# `v0.1.0-4-g3515258` -- it would have refused every build from the first tag
# onwards, which is exactly when a release script starts being used. That was
# corrected to "the hash appears anywhere in the string", which still assumed a
# hash was in there. AT A TAGGED COMMIT `describe` answers `v0.1.0` and nothing
# else, so on 2026-09-10 this refused at v0.1.0 -- the one commit it exists to
# serve -- advising "rebuild before releasing", which produces the identical
# string. QC.
#
# 這道檢查現在已經錯了兩次，兩次都是去**列舉**那個字串可能的形式，而不是去問它。第一次它拿
# `(SHORTHASH` 比相等，而 v0.1.0 讓 `describe` 開始回答 `v0.1.0-4-g3515258`——那會讓它從第一個
# tag 起拒絕每一次建置，而第一個 tag 正好就是一支發行腳本開始被使用的時刻。那次改成了「雜湊
# 出現在字串的任何位置」，而它**仍然假設那裡面有一個雜湊**。在一個 tag 所指的 commit 上，
# `describe` 回答的就只是 `v0.1.0`，因此 2026-09-10 它在 v0.1.0 上拒絕了——那是它存在所要服務的
# 唯一那個 commit——並建議「發行前請重新建置」，而重建產生的是同一個字串。QC。
source "${0:A:h}/build_id.zsh"
EXPECTED_ID=$(csv2_build_id "${0:A:h}")
# ANCHORED, not "contains". The first attempt at this fix compared containment
# and let a WORSE thing through than the bug it replaced: at v0.1.0 the expected
# id is `v0.1.0`, and `csv2 0.1.0 (v0.1.0-13-g1750de3)` contains that string --
# so a binary built thirteen commits later would have shipped as the release.
# Caught by testing the refusal direction, which is the direction a guard is
# for; the passing direction had already looked right.
#
# 用**錨定**，不用「包含」。這個修正的第一版比的是包含，而它放行的東西比它取代的缺陷更糟：
# 在 v0.1.0 上，預期的 id 是 `v0.1.0`，而 `csv2 0.1.0 (v0.1.0-13-g1750de3)` **含有**那個字串
# ——於是一個晚了十三個 commit 的執行檔會被當成那次 release 出貨。它是靠測「拒絕」那個方向
# 抓到的，而那正是一道守衛存在的方向；「通過」那個方向早就看起來是對的。
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
# Refuse to overwrite. `rm -rf` on the archive path is how the local copy of
# the PUBLISHED v0.1.0 macOS archive was destroyed on 2026-09-10, together with
# its .sha256 -- leaving a self-consistent pair that was no longer the file
# anyone had downloaded. Making an archive has no reason to overwrite one.
# 拒絕覆寫。對封存路徑下 `rm -rf`，正是 2026-09-10 那份**已發布**的 v0.1.0 macOS 封存的本機複本
# 連同它的 .sha256 一起被毀掉的方式——留下一對彼此自洽、卻已經不是任何人下載到的那個檔案。
# 「產生一份封存」這件事沒有任何理由需要覆寫另一份。
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

tar -C "$DIST" -cf - "$STEM" | zstd -19 -q -o "$ARCHIVE"

# ---------------------------------------------------------------------
# Verify by EXTRACTING AND RUNNING, not by checking the archive exists.
#
# This is compile_csv2.zsh's rule applied one layer out. An archive that
# unpacks to a binary this machine cannot execute is exactly the failure a
# release makes permanent: the person who finds it is not you, and they
# cannot rebuild it.
#
# 以「解開並執行」驗證，而不是檢查封存存在。
#
# 這是 compile_csv2.zsh 那條規則往外推一層。一份「解開後得到一個這台機器執行不了的執行檔」的
# 封存，正是發行會讓它變成永久的那種失敗：發現它的人不是你，而且他重建不了它。
# ---------------------------------------------------------------------
CHECK=$(mktemp -d "$DIST/.verify.XXXXXX")
trap 'rm -rf -- "$CHECK"' EXIT
zstd -dq -c "$ARCHIVE" | tar -C "$CHECK" -xf -
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
PROBE=$("$EXTRACTED" -get 1:license -i "$CHECK/probe.csv")
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

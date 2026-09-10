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

VERSION=${VERSION:-0.1.0}
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
HEAD_SHORT=$(git rev-parse --short HEAD)
REPORTED=$("$BIN" --version)
# The hash ANYWHERE in the string, not immediately after `(`. Once v0.1.0 was
# tagged, `git describe` started answering `v0.1.0-4-g3515258` instead of a bare
# short hash, so `--version` reports `(v0.1.0-4-g3515258)` and a check looking
# for `(3515258` matches nothing. This script would then have refused EVERY
# build from the first tag onwards -- and the first tag is exactly when a
# release script starts being used. Found by reading the version string after a
# rebuild, not by the script failing, because nothing had run it since.
# 在字串的**任何位置**找那個雜湊，而不是「緊接在 `(` 之後」。v0.1.0 被打上 tag 之後，
# `git describe` 開始回答 `v0.1.0-4-g3515258` 而不是純短雜湊，於是 `--version` 印的是
# `(v0.1.0-4-g3515258)`，而一個去找 `(3515258` 的檢查什麼都匹配不到。那會讓這支腳本從**第一個
# tag 之後**拒絕每一次建置——而第一個 tag 正好就是一支發行腳本開始被使用的時刻。這是重建之後
# 讀版本字串時發現的，不是靠腳本失敗發現的，因為在那之後沒有人再執行過它。
if [[ $REPORTED != *"$HEAD_SHORT"* ]]; then
    print -u2 -- "the binary reports [$REPORTED] but HEAD is $HEAD_SHORT; rebuild before releasing"
    print -u2 -- "執行檔回報 [$REPORTED]，而 HEAD 是 $HEAD_SHORT；發行前請重新建置"
    exit 1
fi

# ---------------------------------------------------------------------
# Pack. The archive holds one directory so an extraction cannot scatter
# files into the caller's cwd -- the difference between `tar xf` being safe
# and being a mess someone has to clean up by hand.
# 打包。封存裡只有一個目錄，這樣解開時不會把檔案灑進呼叫端的目前目錄——那是
# 「`tar xf` 是安全的」與「有人得手動收拾」之間的差別。
# ---------------------------------------------------------------------
rm -rf -- "$DIST/$STEM" "$ARCHIVE" "$ARCHIVE.sha256"
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

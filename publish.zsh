#!/usr/bin/env zsh
# =====================================================================
#  publish.zsh — tag, publish, verify, and rewrite the package files
#  publish.zsh — 打 tag、發布、驗證，並改寫套件檔
#
#    ./publish.zsh 0.1.1              say what would happen, change nothing
#    ./publish.zsh 0.1.1 --publish    do it
#
#  release.zsh makes ONE archive on ONE node and is strict about it. Getting
#  from those archives to a release was seven manual steps for v0.1.0, and the
#  only mistake in that release lived in them. This is those steps.
#
#  release.zsh 在**一個**節點上產生**一份**封存，而且對它很嚴格。從那些封存走到一個 release，
#  在 v0.1.0 時是七個手動步驟——而那次出貨唯一的錯誤就住在裡面。這支腳本就是那七步。
#
#  What it will NOT do: build, test, or collect the archives. Each node runs
#  ./release.zsh itself, because an archive must be made where its binary was
#  built and tested; and collecting them is this machine's multissh setup, not
#  something a script in this repository can know. Put them in dist/ first.
#
#  它**不做**的事：建置、測試、收集封存。每個節點自己跑 ./release.zsh——因為一份封存必須在它的
#  執行檔被建置與測試的地方產生；而收集它們用的是這台機器的 multissh 設定，不是這個 repo 裡的
#  腳本能知道的事。請先把它們放進 dist/。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail errexit

# No line number: `$LINENO` inside a trap function reports the line within THAT
# FUNCTION, not the line that failed. On 2026-09-10 this printed "stopped at
# line 2" for a failure a hundred lines away. A message naming the wrong line is
# worse than one naming none -- it sends the reader somewhere and they believe it.
# 不報行號：`$LINENO` 在 trap 函式內回報的是**那個函式**裡的行號，不是失敗的那一行。
# 2026-09-10 它為一個相隔上百行的失敗印出「停在第 2 行」。一則指名錯行號的訊息，比不指名
# 更糟——它把讀者送去某個地方，而他們會相信它。
TRAPZERR() {
    print -u2 -- "publish.zsh: a command failed and errexit stopped the run; the last line above says how far it got"
    print -u2 -- "publish.zsh：某個命令失敗，errexit 中止了這次執行；上面最後一行說明它走到哪裡"
    print -u2 -- "if the release was already created, its assets and the package files may disagree; check before retrying"
    print -u2 -- "若 release 已經建立，它的 asset 與套件檔可能不一致；重試前請先確認"
}

HERE=${0:A:h}
cd -- "$HERE"

REPO=raliclo/csv2
VERSION=${1:-}
DO_PUBLISH=0
for arg in "${@:2}"; do
    case $arg in
        --publish) DO_PUBLISH=1 ;;
        *) print -u2 -- "unknown argument: $arg"; exit 2 ;;
    esac
done
if [[ -z $VERSION ]]; then
    print -u2 -- "usage: ./publish.zsh <version> [--publish]   e.g. ./publish.zsh 0.1.1"
    print -u2 -- "用法：./publish.zsh <版本> [--publish]        例如 ./publish.zsh 0.1.1"
    exit 2
fi
TAG=v$VERSION
DIST=$HERE/dist

say() { print -r -- "$1" }
would() { if (( DO_PUBLISH )); then print -r -- "  $1"; else print -r -- "  WOULD  $1"; fi }

# ---------------------------------------------------------------------
# 1. Refuse before touching anything outward-facing.
# 1. 在碰任何「對外」的東西之前先拒絕。
# ---------------------------------------------------------------------
[[ -n "$(git status --porcelain)" ]] && {
    print -u2 -- "the working tree is not clean; a tag would name a state that was not published"
    print -u2 -- "工作區不乾淨；那個 tag 會指向一個沒有被發布的狀態"
    git status --porcelain >&2
    exit 1
}
git fetch -q origin
if [[ -n "$(git rev-list @{upstream}..HEAD 2>/dev/null)" ]]; then
    print -u2 -- "HEAD is ahead of origin; push before publishing, or the tag names a commit nobody can fetch"
    print -u2 -- "HEAD 領先 origin；請先推送，否則那個 tag 指向一個沒有人抓得到的 commit"
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    print -u2 -- "$TAG already exists. Re-cutting a published tag disturbs anyone who fetched it; pick the next version"
    print -u2 -- "$TAG 已經存在。重打一個已發布的 tag 會動到任何抓過它的人；請改用下一個版本號"
    exit 1
fi
command -v gh >/dev/null 2>&1 || { print -u2 -- "gh is not on PATH"; exit 1 }
gh auth status >/dev/null 2>&1 || { print -u2 -- "gh is not authenticated"; exit 1 }

# ---------------------------------------------------------------------
# 2. The archives. Their checksums are RECOMPUTED here, never read from the
#    .sha256 files and never copied from a terminal. Steps 6 and 7 of the
#    v0.1.0 release were transcribing a 64-character hex string by hand into
#    two files, which nothing reports getting wrong.
# 2. 那些封存。它們的校驗和在這裡**重新計算**，不從 .sha256 檔讀、也不從終端機複製。v0.1.0
#    那次出貨的第 6、7 步，是把一個 64 字元的十六進位字串**手抄**進兩個檔案——而抄錯了沒有
#    任何東西會回報。
# ---------------------------------------------------------------------
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | cut -d' ' -f1
    else
        openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1
    fi
}

typeset -a ARCHIVES
ARCHIVES=("$DIST"/csv2-$VERSION-*.tar.zst(N))
(( ${#ARCHIVES} > 0 )) || {
    print -u2 -- "no dist/csv2-$VERSION-*.tar.zst; each node runs ./release.zsh and the archives are collected here first"
    print -u2 -- "找不到 dist/csv2-$VERSION-*.tar.zst；請先讓各節點各自跑 ./release.zsh，再把封存收到這裡"
    exit 1
}

say "publish csv2 $VERSION as $TAG / 將 csv2 $VERSION 以 $TAG 發布"
say "  commit  : $(git rev-parse --short HEAD)"
say "  archives:"
typeset -A HASH
for a in $ARCHIVES; do
    base=${a:t}
    h=$(sha256_of "$a")
    HASH[$base]=$h
    # The .sha256 beside it was written by release.zsh on the node that built
    # the archive. If it disagrees with what this machine computes, the file
    # changed in transit and no amount of publishing will fix it.
    # 它旁邊那個 .sha256 是由「建置該封存的節點」上的 release.zsh 寫的。如果它與這台機器算出來的
    # 不一致，那個檔案在傳輸中變了，而再怎麼發布都補不回來。
    if [[ -r $a.sha256 ]]; then
        claimed=$(awk '{print $1}' "$a.sha256")
        if [[ $claimed != $h ]]; then
            print -u2 -- "$base: the .sha256 from the building node says $claimed, this machine computes $h"
            print -u2 -- "$base：建置節點寫下的 .sha256 是 $claimed，而這台機器算出來是 $h"
            exit 1
        fi
    else
        print -u2 -- "$base has no .sha256 beside it; release.zsh writes one, so this archive did not come from it"
        print -u2 -- "$base 旁邊沒有 .sha256；release.zsh 會寫一個，所以這份封存不是它產生的"
        exit 1
    fi
    # It must also still be an archive that unpacks to the binary it claims.
    # 它也必須仍然是一份「解得開、而且裡面有它所宣稱的執行檔」的封存。
    stem=${base%.tar.zst}
    # `|| true`: with errexit and pipe_fail, a grep that finds nothing returns 1,
    # the command substitution inherits it, and the assignment kills the script
    # BEFORE the refusal below can say what was wrong. That is PE exactly --
    # already recorded, already fixed once in measure_parallel_rss.zsh, and
    # written again here from memory.
    # `|| true`：在 errexit 與 pipe_fail 之下，一個找不到東西的 grep 回傳 1，命令替換繼承它，
    # 而那個賦值會在底下那道拒絕來得及說明之前就殺掉腳本。那正是 PE——已經記錄過、已經在
    # measure_parallel_rss.zsh 修過一次，而我在這裡又憑記憶寫了一遍。
    inner=$(zstd -dq -c -- "$a" | tar -tf - | grep -E "^$stem/csv2(\.exe)?$" | head -1 || true)
    [[ -n $inner ]] || {
        print -u2 -- "$base does not contain $stem/csv2 or $stem/csv2.exe"
        print -u2 -- "$base 裡面沒有 $stem/csv2 或 $stem/csv2.exe"
        exit 1
    }
    say "    $base  $h"
done

# ---------------------------------------------------------------------
# 3. Tag.
# ---------------------------------------------------------------------
say ""
say "steps / 步驟："
would "git tag -a $TAG && git push origin $TAG"
if (( DO_PUBLISH )); then
    git tag -a "$TAG" -m "csv2 $VERSION"
    git push -q origin "$TAG"
fi

# ---------------------------------------------------------------------
# 4. Release, with every archive and every .sha256 attached.
# ---------------------------------------------------------------------
typeset -a ASSETS
for a in $ARCHIVES; do ASSETS+=("$a" "$a.sha256"); done
would "gh release create $TAG -R $REPO with ${#ASSETS} assets"
if (( DO_PUBLISH )); then
    gh release create "$TAG" -R "$REPO" --verify-tag \
        --title "csv2 $VERSION" \
        --notes "csv2 $VERSION. Archives are .tar.zst, one per platform, each packed on the machine that built its binary. Verify with the .sha256 beside it. Release notes are edited after publishing; see README.md for what is in this version." \
        "${ASSETS[@]}" >/dev/null
fi

# ---------------------------------------------------------------------
# 5. Re-download from the PUBLIC url and compare. Not a good habit -- a step.
#    "gh release create exited 0" says the upload was accepted, which is a
#    different claim from "what a stranger downloads is what I built".
# 5. 從**公開** URL 重新下載並比對。這不是好習慣，是一個步驟。「gh release create 以 0 結束」
#    說的是「上傳被接受了」，而那與「一個陌生人下載到的，就是我建出來的那個」是兩件事。
# ---------------------------------------------------------------------
would "re-download each asset from the public URL and compare against the local file"
if (( DO_PUBLISH )); then
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    for a in $ARCHIVES; do
        base=${a:t}
        url=https://github.com/$REPO/releases/download/$TAG/$base
        curl -sfL "$url" -o "$tmp/$base" || {
            print -u2 -- "$base is not downloadable at $url"
            print -u2 -- "$base 在 $url 下載不到"
            exit 1
        }
        got=$(sha256_of "$tmp/$base")
        [[ $got == ${HASH[$base]} ]] || {
            print -u2 -- "$base downloaded as $got, was published as ${HASH[$base]}"
            print -u2 -- "$base 下載回來是 $got，發布的是 ${HASH[$base]}"
            exit 1
        }
        say "    verified from the public URL: $base"
    done
fi

# ---------------------------------------------------------------------
# 6/7. The package files, GENERATED from the archives rather than typed.
#      Each url and hash is rewritten from ${HASH[...]}, and the result is
#      read back and compared. This is the step that carried the v0.1.0
#      mistake, and it is the one a person is least able to check by eye:
#      two hex strings differ in one character and look identical.
# 6/7. 套件檔，由封存**產生**而不是打進去。每一個 url 與 hash 都從 ${HASH[...]} 改寫，
#      而結果會被讀回來比對。這正是 v0.1.0 那次錯誤所在的步驟，也是最不可能靠肉眼檢查的一步：
#      兩個十六進位字串差一個字元，看起來一模一樣。
# ---------------------------------------------------------------------
base_url=https://github.com/$REPO/releases/download/$TAG

# In zsh, not python3. T249c refuses an unguarded python3 anywhere in this
# tree: this repository has no Python dependency, and a script that quietly
# acquires one works here and fails on a node that has no python3 -- with an
# error about an interpreter, at the step that publishes.
# 用 zsh，不用 python3。T249c 會拒絕這棵樹裡任何未加保護的 python3：本 repo 沒有 Python
# 依賴，而一支悄悄取得該依賴的腳本會「在這裡能跑、在沒有 python3 的節點上失敗」——訊息講的是
# 直譯器，而失敗的時機是正在發布的那一步。
#
# The python3 version this replaced also had a defect that had never run: it
# counted every url containing the platform suffix, and scoop/csv2.json has a
# SECOND one in its autoupdate block -- a template carrying a literal $version.
# It would have found two and refused. Lines carrying $version are templates
# and are deliberately left alone.
# 被它取代的那個 python3 版本還帶著一個從來沒有執行過的缺陷：它會數「每一個含有該平台後綴的
# url」，而 scoop/csv2.json 的 autoupdate 區塊裡有**第二個**——一個帶著字面 $version 的模板。
# 它會數到兩個然後拒絕。含有 $version 的行是模板，這裡刻意不動它們。
# The url and the hash are not the only things carrying a version. scoop's
# extract_dir must equal the directory inside the archive or the install puts
# the binary nowhere; the Formula's `version` and its `assert_match "csv2 X"`
# are two more. Rewriting only the pair leaves four stale sites in two files --
# found on 2026-09-10 by rewriting a copy and grepping it for the old number,
# which is the check the read-back at the end now also performs.
# 帶著版本號的不只 url 與 hash。scoop 的 extract_dir 必須等於封存內的目錄名，否則安裝會把
# 執行檔放到不存在的地方；Formula 的 `version` 與它的 `assert_match "csv2 X"` 是另外兩個。
# 只改 url/hash 那一對，會在兩個檔案裡留下四個過期的位置——2026-09-10 是靠「改寫一份複本、
# 再 grep 舊版本號」發現的，而那正是結尾的讀回來檢查現在也會做的事。
rewrite_version() {   # $1 = file
    setopt local_options extended_glob
    local file=$1 line old=""
    # The version this file currently declares, taken as the first X.Y.Z token
    # on a line that mentions "version". An earlier attempt read "the first
    # quoted word after the first quote", which on scoop's `"version": "0.1.0",`
    # yielded `: ` -- and then replaced `: ` throughout, mangling 22 of the
    # file's 38 lines. It was caught because the rewrite was tried on a COPY
    # first; on the real file it would have run during a publish.
    # 這個檔案目前宣告的版本，取自「提到 version 的那一行上的第一個 X.Y.Z token」。先前的寫法是
    # 「第一個引號之後的第一個帶引號字詞」，而它在 scoop 的 `"version": "0.1.0",` 上得到的是
    # `: `——接著把整個檔案裡的 `: ` 都替換掉，38 行裡弄爛了 22 行。它被抓到，是因為改寫先在
    # **一份複本**上試過；在真的檔案上，它會發生在一次發布的當中。
    while IFS= read -r line; do
        [[ $line == *version* ]] || continue
        [[ $line == (#b)*([0-9]##.[0-9]##.[0-9]##)* ]] || continue
        old=$match[1]
        break
    done < $file
    [[ -n $old ]] || {
        print -u2 -- "${file:t}: no version line, so a stale one could not be found either"
        print -u2 -- "${file:t}：找不到版本行，因此也無從發現過期的版本號"
        return 1
    }
    [[ $old == $VERSION ]] && return 0
    local tmpf=$file.rewriting.$$
    integer n=0
    : > $tmpf
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == *$old* ]]; then
            line=${line//$old/$VERSION}
            n+=1
        fi
        print -r -- "$line" >> $tmpf
    done < $file
    # Check the RESULT before adopting it. The mangling described above left a
    # file that was still readable and still contained the new version; only a
    # look at the whole product showed it. `|| true` because a grep that finds
    # nothing returns 1 and would kill the script under errexit -- PE.
    # 在採用之前先檢查**產物**。上面那次破壞留下的檔案仍然讀得動、也仍然含有新版本號；只有看
    # 整份產物才看得出來。`|| true` 是因為找不到東西的 grep 回傳 1，在 errexit 之下會殺掉腳本——PE。
    local left
    left=$(LC_ALL=C grep -oE '[0-9]+\.[0-9]+\.[0-9]+' $tmpf | LC_ALL=C sort -u \
           | LC_ALL=C grep -vxF -- "$VERSION" || true)
    if (( n == 0 )) || [[ -n $left ]]; then
        rm -f $tmpf
        print -u2 -- "${file:t}: rewriting $old -> $VERSION changed $n line(s) and left ${left//$'\n'/ }; not adopted"
        print -u2 -- "${file:t}：把 $old 改成 $VERSION 動了 $n 行，卻留下 ${left//$'\n'/ }；不採用"
        return 1
    fi
    mv -- $tmpf $file
    say "    ${file:t}: $old -> $VERSION on $n line(s)"
}

rewrite_pair() {   # $1 = file, $2 = archive basename, $3 = its sha256
    setopt local_options extended_glob
    local file=$1 base=$2 h=$3
    local url=$base_url/$base
    local plat=${${base#csv2-$VERSION-}%.tar.zst}
    [[ -n $plat && $plat != $base ]] || {
        print -u2 -- "cannot read a platform out of $base"
        print -u2 -- "無法從 $base 讀出平台名稱"
        return 1
    }
    local tmpf=$file.rewriting.$$
    local line pre post
    integer n_url=0 n_hash=0 pending=0
    : > $tmpf
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == *https://github.com/*${plat}.tar.zst* && $line != *'$version'* ]]; then
            # Exactly one url per line in both files, so cutting at the first
            # https:// and the first .tar.zst rebuilds it without a regex.
            # 兩個檔案裡每一行都只有一個 url，因此在第一個 https:// 與第一個 .tar.zst 處切開
            # 就能重建它，不需要正規式。
            pre=${line%%https://*}
            post=${line#*.tar.zst}
            line=$pre$url$post
            n_url+=1
            pending=1
        elif (( pending )) && [[ $line == *\"[0-9a-f](#c64)\"* ]]; then
            # The hash is quoted in both formats, and requiring the quotes is
            # what stops a longer hex run from being partly overwritten.
            # 兩種格式裡 hash 都帶引號，而「要求引號」正是避免一段更長的十六進位字串被改掉
            # 前 64 個字元的那道限制。
            line=${line/\"[0-9a-f](#c64)\"/\"$h\"}
            n_hash+=1
            pending=0
        fi
        print -r -- "$line" >> $tmpf
    done < $file
    if (( n_url != 1 || n_hash != 1 )); then
        rm -f $tmpf
        print -u2 -- "${file:t}: expected one url and one sha256 for $plat, rewrote $n_url and $n_hash"
        print -u2 -- "${file:t}：$plat 應該只有一個 url 與一個 sha256，實際改寫了 $n_url 與 $n_hash"
        return 1
    fi
    mv -- $tmpf $file
}

for a in $ARCHIVES; do
    base=${a:t}
    case $base in
        *-macos-*|*-linux-*) target=$HERE/Formula/csv2.rb ;;
        *-windows-*)         target=$HERE/scoop/csv2.json ;;
        *) continue ;;
    esac
    [[ -r $target ]] || continue
    grep -q -- "${base##csv2-$VERSION-}" "$target" 2>/dev/null || {
        # The platform is not listed in that file. That is a decision, not an
        # oversight -- v0.1.0 deliberately omitted platforms whose archive
        # could not be verified where it was made -- so say so and move on.
        # 那個平台沒有列在那個檔案裡。那是一個決定而不是疏漏——v0.1.0 刻意略過了「封存無法在
        # 產生它的地方被驗證」的平台——所以說出來就好，不要自作主張加進去。
        say "    $base: no entry in ${target:t}, leaving it alone"
        continue
    }
    would "rewrite ${target:t} for $base"
    if (( DO_PUBLISH )); then
        rewrite_version "$target"
        rewrite_pair "$target" "$base" "${HASH[$base]}"
    fi
done

if (( DO_PUBLISH )); then
    # Read back. A rewrite that silently did nothing looks exactly like one
    # that worked.
    # 讀回來。一次「靜默地什麼都沒做」的改寫，看起來與一次成功的改寫一模一樣。
    for a in $ARCHIVES; do
        base=${a:t}
        for f in $HERE/Formula/csv2.rb $HERE/scoop/csv2.json; do
            [[ -r $f ]] || continue
            grep -q -- "$base" "$f" || continue
            grep -q -- "${HASH[$base]}" "$f" || {
                print -u2 -- "${f:t} names $base but not its sha256 ${HASH[$base]}"
                print -u2 -- "${f:t} 提到了 $base，卻沒有它的 sha256 ${HASH[$base]}"
                exit 1
            }
            say "    ${f:t}: $base and its hash agree"
        done
    done
    # And no OTHER version may remain anywhere in either file. This is what
    # would have caught extract_dir and assert_match; the pair check above
    # cannot, because both were already correct about the pair.
    # 而兩個檔案裡的任何地方都不可以再留著**別的**版本號。這正是會抓到 extract_dir 與
    # assert_match 的那道檢查；上面那個「成對」的檢查抓不到，因為它們兩個對「那一對」而言
    # 本來就是正確的。
    for f in $HERE/Formula/csv2.rb $HERE/scoop/csv2.json; do
        [[ -r $f ]] || continue
        # Every distinct X.Y.Z token in the file, minus the one being
        # published. Comparing tokens rather than lines is what makes a line
        # carrying BOTH the new version and a stale one still fail.
        # 檔案裡每一個相異的 X.Y.Z token，扣掉正在發布的那一個。比對 token 而不是比對「行」，
        # 是「一行同時含有新版本與一個過期版本」時仍然會失敗的原因。
        _stale=$(LC_ALL=C grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$f" \
                 | LC_ALL=C sort -u | LC_ALL=C grep -vxF -- "$VERSION" || true)
        [[ -z $_stale ]] || {
            print -u2 -- "${f:t} still carries version(s) other than $VERSION: ${_stale//$'\n'/ }"
            print -u2 -- "${f:t} 裡還留著不是 $VERSION 的版本號：${_stale//$'\n'/ }"
            exit 1
        }
        say "    ${f:t}: no version other than $VERSION remains"
    done
fi

say ""
if (( DO_PUBLISH )); then
    say "published: https://github.com/$REPO/releases/tag/$TAG"
    say "next, by hand and on purpose: the release notes, and the version in"
    say "Formula/csv2.rb and scoop/csv2.json if this is a new minor version"
    say "接下來是刻意留給人做的：release notes，以及（若這是新的次版本）Formula/csv2.rb 與"
    say "scoop/csv2.json 裡的版本號"
    say "then run ./test/test_csv2.zsh -- the package files are checked by it"
    say "然後跑 ./test/test_csv2.zsh——那些套件檔由它檢查"
else
    say "nothing was changed. Re-run with --publish to do the above."
    say "什麼都沒有改動。加上 --publish 才會真的執行。"
fi

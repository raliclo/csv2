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

TRAPZERR() {
    print -u2 -- "publish.zsh stopped at line $LINENO"
    print -u2 -- "publish.zsh 停在第 $LINENO 行"
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
    inner=$(zstd -dq -c -- "$a" | tar -tf - | grep -E "^$stem/csv2(\.exe)?$" | head -1)
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

rewrite_pair() {   # $1 = file, $2 = archive basename, $3 = its sha256
    local file=$1 base=$2 h=$3
    local url=$base_url/$base
    python3 - "$file" "$url" "$h" "$base" <<'PY'
import io, re, sys
path, url, h, base = sys.argv[1:5]
s = io.open(path, encoding='utf-8').read()
# The archive's platform suffix identifies which url/sha256 pair to replace:
# csv2-0.1.1-macos-arm64.tar.zst -> macos-arm64
plat = re.sub(r'^csv2-[^-]+-', '', base).removesuffix('.tar.zst')
n_url = len(re.findall(r'https://github\.com/\S*' + re.escape(plat) + r'\.tar\.zst', s))
if n_url != 1:
    sys.exit(f"{path}: expected exactly one url for {plat}, found {n_url}")
s = re.sub(r'https://github\.com/\S*' + re.escape(plat) + r'\.tar\.zst', url, s)
# The hash is the 64-hex string nearest after that url, whatever quotes it wears.
i = s.index(url)
m = re.compile(r'\b[0-9a-f]{64}\b').search(s, i)
if not m:
    sys.exit(f"{path}: no sha256 after the {plat} url")
s = s[:m.start()] + h + s[m.end():]
io.open(path, 'w', encoding='utf-8').write(s)
PY
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
    (( DO_PUBLISH )) && rewrite_pair "$target" "$base" "${HASH[$base]}"
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

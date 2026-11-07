#!/usr/bin/env zsh
# =====================================================================
#  publish_matrix.zsh — publish every platform from CI, through publish.zsh
#  publish_matrix.zsh — 從 CI 發布所有平台，經由 publish.zsh
#
#    ./publish_matrix.zsh 0.1.9              say what would happen, change nothing
#    ./publish_matrix.zsh 0.1.9 --fetch      tag, wait for CI, download into dist/; no release
#    ./publish_matrix.zsh 0.1.9 --publish    the same, then ./publish.zsh 0.1.9 --publish
#    ./publish_matrix.zsh --help             print this and do nothing / 印出這段說明，什麼都不做
#
#  Platforms: linux-{x86_64,aarch64}-glibc, linux-{x86_64,aarch64}-musl
#  (static), macos-{x86_64,arm64}, windows-{x86_64,arm64}.
#  Each is built, tested and packaged by .github/workflows/release.yml on a
#  runner of that platform.
#  平台：linux-{x86_64,aarch64}-glibc、linux-{x86_64,aarch64}-musl（靜態）、
#  macos-{x86_64,arm64}、windows-{x86_64,arm64}。每一個都由 .github/workflows/release.yml
#  在該平台的 runner 上建置、測試與打包。
#
#  This replaces only the COLLECTING step (nodes -> dist/). Everything after it
#  stays in publish.zsh, which checks each binary's build id against the commit,
#  creates the release and rewrites Formula/ and scoop/.
#  這只取代「收集」那一步（各節點 -> dist/）。之後的一切仍在 publish.zsh：它拿每個執行檔的
#  build id 與 commit 比對、建立 release、改寫 Formula/ 與 scoop/。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail errexit

TRAPZERR() {
    print -u2 -- "publish_matrix.zsh: a command failed; the last line above says how far it got"
    print -u2 -- "publish_matrix.zsh：某個命令失敗；上面最後一行說明它走到哪裡"
}

HERE=${0:A:h}
cd -- "$HERE"

REPO=raliclo/csv2
WORKFLOW=release.yml
PLATFORMS=(linux-x86_64-glibc linux-aarch64-glibc linux-x86_64-musl linux-aarch64-musl
           macos-x86_64 macos-arm64 windows-x86_64 windows-arm64)
DIST=$HERE/dist

# --help before the version, for the same reason as publish.zsh (RB).
# --help 在版本之前回答，理由與 publish.zsh 相同（RB）。
case ${1:-} in
    -h|--help) sed -n '3,23p' ${0:A} | sed 's/^# \{0,2\}//'; exit 0 ;;
    -*) print -r -u2 -- "the first argument is the version, not an option (got: $1); see --help / 第一個引數是版本，不是選項（收到：$1），請見 --help"; exit 2 ;;
esac
VERSION=${1:-}
MODE=dry
for arg in "${@:2}"; do
    case $arg in
        --fetch)   MODE=fetch ;;
        --publish) MODE=publish ;;
        *) print -r -u2 -- "unknown argument: $arg / 未知的引數：$arg"; exit 2 ;;
    esac
done
[[ $VERSION == <->.<->.<-> ]] || {
    print -u2 -- "usage: ./publish_matrix.zsh <X.Y.Z> [--fetch|--publish]"
    print -u2 -- "用法：./publish_matrix.zsh <X.Y.Z> [--fetch|--publish]"
    exit 2
}
TAG=v$VERSION
say() { print -r -- "$1" }

# ---------------------------------------------------------------------
# 1. The same refusals publish.zsh makes, made BEFORE a tag is pushed: pushing
#    the tag starts eight runners, and finding out afterwards that the tree was
#    dirty wastes all of them.
# 1. 與 publish.zsh 相同的拒絕，但在推送 tag **之前**做：推送 tag 會啟動八台 runner，事後才發現
#    工作樹不乾淨，就白跑了全部。
# ---------------------------------------------------------------------
command -v gh >/dev/null 2>&1 || { print -u2 -- "gh is not on PATH / PATH 上沒有 gh"; exit 1 }
# REST only, as in publish.zsh: `gh auth status` and `gh release` need
# GraphQL, which a Claude Code session cannot reach. `gh run` is REST.
# 只用 REST，與 publish.zsh 相同：`gh auth status` 與 `gh release` 需要 GraphQL，Claude Code session
# 碰不到。`gh run` 走的是 REST。
gh api "repos/$REPO" >/dev/null 2>&1 || { print -u2 -- "gh cannot reach $REPO through the GitHub REST API / gh 無法透過 GitHub REST API 存取 $REPO"; exit 1 }
[[ -z "$(git status --porcelain)" ]] || {
    print -u2 -- "the working tree is not clean; a tag would name a state that was not published"
    print -u2 -- "工作區不乾淨；那個 tag 會指向一個沒有被發布的狀態"
    git status --porcelain >&2
    exit 1
}
git fetch -q --tags origin
[[ -z "$(git rev-list @{upstream}..HEAD 2>/dev/null)" ]] || {
    print -u2 -- "HEAD is ahead of origin; push before publishing, or the tag names a commit nobody can fetch"
    print -u2 -- "HEAD 領先 origin；請先推送，否則那個 tag 指向一個沒有人抓得到的 commit"
    exit 1
}
# Drafts included, and a failed question is a refusal, not "no release".
# 草稿也算；問不到 GitHub 時拒絕，而不是當成「沒有 release」。
_rel=$(gh api --paginate "repos/$REPO/releases?per_page=100" --jq ".[] | select(.tag_name == \"$TAG\") | .draft") || {
    print -u2 -- "cannot list the releases of $REPO / 無法列出 $REPO 的 release"
    exit 1
}
if [[ -n $_rel ]]; then
    print -u2 -- "$TAG already has a release (draft: $_rel); pick the next version, or delete a leftover draft first"
    print -u2 -- "$TAG 已經有 release（草稿：$_rel）；請改用下一個版本號，或先刪除殘留的草稿"
    exit 1
fi
HEAD_SHA=$(git rev-parse HEAD)
TAG_SHA=""
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    TAG_SHA=$(git rev-parse "$TAG^{commit}")
    [[ $TAG_SHA == $HEAD_SHA ]] || {
        print -u2 -- "$TAG exists but points at ${TAG_SHA[1,8]}, not HEAD ${HEAD_SHA[1,8]}"
        print -u2 -- "$TAG 存在，但它指向 ${TAG_SHA[1,8]}，不是 HEAD ${HEAD_SHA[1,8]}"
        exit 1
    }
fi
# Archives already in dist/ for this version are refused, not merged: a mix of
# a node's archive and CI's for the same platform is two binaries under one
# name, and release.zsh refuses to overwrite for the same reason (QI).
# dist/ 裡已經有這個版本的封存就拒絕，不合併：同一個平台混著節點的封存與 CI 的封存，就是一個名字
# 底下兩個執行檔；release.zsh 拒絕覆寫也是同一個理由（QI）。
existing=("$DIST"/csv2-$VERSION-*(N))
if (( ${#existing} )) && [[ $MODE != dry ]]; then
    print -u2 -- "dist/ already holds archives for $VERSION; move them away first:"
    print -u2 -- "dist/ 裡已經有 $VERSION 的封存；請先移開："
    print -l -u2 -- ${existing:t}
    exit 1
fi

say "csv2 $VERSION as $TAG from $WORKFLOW / 以 $WORKFLOW 將 csv2 $VERSION 發布為 $TAG"
say "  HEAD     : ${HEAD_SHA[1,8]}"
if [[ -n $TAG_SHA ]]; then say "  tag      : ${TAG_SHA[1,8]}"; else say "  tag      : (none yet / 尚未建立)"; fi
say "  platforms: ${PLATFORMS[*]}"

if [[ $MODE == dry ]]; then
    say ""
    say "would / 將會："
    [[ -n $TAG_SHA ]] || say "  git tag -a $TAG && git push origin $TAG   (starts $WORKFLOW / 啟動 $WORKFLOW)"
    say "  wait for the $WORKFLOW run on $TAG, then download its ${#PLATFORMS} archives into dist/"
    say "  等待 $TAG 上的 $WORKFLOW 執行完成，再把它的 ${#PLATFORMS} 份封存下載到 dist/"
    say "  ./publish.zsh $VERSION --publish   (--publish only / 僅限 --publish)"
    (( ${#existing} )) && say "Note: dist/ already holds ${#existing} file(s) for $VERSION, so --fetch would refuse. / 注意：dist/ 已有 $VERSION 的檔案，--fetch 會拒絕。"
    say "Nothing was changed. / 什麼都沒有改動。"
    exit 0
fi

# ---------------------------------------------------------------------
# 2. Tag, then find the run that tag push started and wait for it.
# 2. 打 tag，再找到那次 tag 推送啟動的執行並等它完成。
# ---------------------------------------------------------------------
if [[ -z $TAG_SHA ]]; then
    git tag -a "$TAG" -m "csv2 $VERSION"
    TAG_SHA=$HEAD_SHA
fi
git push -q origin "$TAG"
say "  pushed / 已推送：$TAG"

run_id=""
for i in {1..30}; do
    run_id=$(gh run list -R "$REPO" --workflow "$WORKFLOW" --event push --branch "$TAG" --limit 1 \
             --json databaseId,headSha -q ".[] | select(.headSha == \"$TAG_SHA\") | .databaseId" 2>/dev/null || true)
    [[ -n $run_id ]] && break
    sleep 5
done
[[ -n $run_id ]] || {
    print -u2 -- "no $WORKFLOW run for $TAG after 150 s; see https://github.com/$REPO/actions"
    print -u2 -- "150 秒後仍沒有 $TAG 的 $WORKFLOW 執行；請看 https://github.com/$REPO/actions"
    exit 1
}
say "  waiting for CI / 等待 CI：https://github.com/$REPO/actions/runs/$run_id"
gh run watch "$run_id" -R "$REPO" --exit-status --interval 30 >/dev/null || {
    print -u2 -- "CI failed: https://github.com/$REPO/actions/runs/$run_id -- nothing was downloaded or published"
    print -u2 -- "CI 失敗：https://github.com/$REPO/actions/runs/$run_id——沒有下載也沒有發布任何東西"
    exit 1
}

# ---------------------------------------------------------------------
# 3. Download into a scratch directory, require exactly the expected set, and
#    only then move it into dist/. A partial set in dist/ would be published by
#    publish.zsh as if it were the whole release.
# 3. 下載到暫存目錄，要求恰好是預期的那一組，然後才搬進 dist/。dist/ 裡若只有部分封存，
#    publish.zsh 會把它當成整個 release 發布。
# ---------------------------------------------------------------------
tmp=$(mktemp -d "${TMPDIR:-/tmp}/csv2-matrix.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
gh run download "$run_id" -R "$REPO" -D "$tmp"
mkdir -p -- "$DIST"
typeset -a want
for plat in $PLATFORMS; do
    base=csv2-$VERSION-$plat.tar.zst
    found=("$tmp"/*/$base(N))
    (( ${#found} == 1 )) || {
        print -u2 -- "the run has ${#found} copies of $base, expected 1 / 這次執行有 ${#found} 份 $base，預期 1 份"
        exit 1
    }
    [[ -r $found[1].sha256 ]] || { print -u2 -- "$base has no .sha256 beside it / $base 旁邊沒有 .sha256"; exit 1 }
    want+=("$found[1]" "$found[1].sha256")
done
extra=$(cd -- "$tmp" && find . -type f -name '*.tar.zst' | sed 's|.*/||' | sort | grep -vxF -f <(for p in $PLATFORMS; do print -r -- csv2-$VERSION-$p.tar.zst; done) || true)
[[ -z $extra ]] || {
    print -u2 -- "the run produced archives this script does not expect: ${extra//$'\n'/ }"
    print -u2 -- "這次執行產生了這支腳本沒有預期的封存：${extra//$'\n'/ }"
    exit 1
}
# The build-and-suites line for the release notes, generated from this run's
# job logs; see release_build_notes.zsh.
# release notes 的「建置與測試結果」那一行，由這次執行的 job log 產生；見 release_build_notes.zsh。
zsh ./release_build_notes.zsh "$VERSION" "$run_id" "$TAG_SHA" "$tmp/csv2-$VERSION-build.md" $PLATFORMS
want+=("$tmp/csv2-$VERSION-build.md")
cp -- $want "$DIST/"
say "  downloaded into dist/ / 已下載到 dist/："
for plat in $PLATFORMS; do say "    csv2-$VERSION-$plat.tar.zst"; done

if [[ $MODE == fetch ]]; then
    say ""
    say "next / 下一步：./publish.zsh $VERSION            (dry run / 試跑)"
    say "               ./publish.zsh $VERSION --publish"
    exit 0
fi

# ---------------------------------------------------------------------
# 4. publish.zsh does the rest, with every check it already makes.
# 4. 其餘交給 publish.zsh，連同它既有的每一道檢查。
# ---------------------------------------------------------------------
# Not `exec`: exec replaces this shell, so the EXIT trap that removes $tmp never ran
# and every publish left ~64M behind (ST).
# 不用 `exec`：exec 會取代這個 shell，清掉 $tmp 的 EXIT trap 因此從未執行，每次發布都留下約 64M（ST）。
say ""
./publish.zsh "$VERSION" --publish
exit $?

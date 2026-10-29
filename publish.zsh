#!/usr/bin/env zsh
# =====================================================================
#  publish.zsh — tag, publish, verify, and rewrite the package files
#  publish.zsh — 打 tag、發布、驗證，並改寫套件檔
#
#    ./publish.zsh 0.1.1              say what would happen, change nothing
#    ./publish.zsh 0.1.1 --publish    do it
#    ./publish.zsh --help             print this and do nothing / 印出這段說明，什麼都不做
#
#  release.zsh makes ONE archive on ONE node and is strict about it. This
#  script does the steps between those archives and a release, which by hand
#  are where a release goes wrong.
#
#  release.zsh 在**一個**節點上產生**一份**封存，而且對它很嚴格。這支腳本做的是從那些封存
#  走到 release 之間的步驟——那些步驟若靠手做，正是出貨出錯的地方。
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
# FUNCTION, not the line that failed. A message naming the wrong line is worse
# than one naming none -- it sends the reader somewhere and they believe it.
# 不報行號：`$LINENO` 在 trap 函式內回報的是**那個函式**裡的行號，不是失敗的那一行。
# 指名錯行號的訊息比不指名更糟——它把讀者帶到別處，而讀者會相信它。
TRAPZERR() {
    print -u2 -- "publish.zsh: a command failed and errexit stopped the run; the last line above says how far it got"
    print -u2 -- "publish.zsh：某個命令失敗，errexit 中止了這次執行；上面最後一行說明它走到哪裡"
    print -u2 -- "if the release was already created, its assets and the package files may disagree; check before retrying"
    print -u2 -- "若 release 已經建立，它的 asset 與套件檔可能不一致；重試前請先確認"
}

HERE=${0:A:h}
cd -- "$HERE"

REPO=raliclo/csv2
# --help answers before the version is read; otherwise it would be taken as
# the version and the run would look for dist/csv2---help-*.tar.zst. RB.
# --help 在讀取版本之前就回答；否則它會被當成版本，這次執行就會去找
# dist/csv2---help-*.tar.zst。RB。
case ${1:-} in
    -h|--help) sed -n '3,24p' ${0:A} | sed 's/^# \{0,2\}//'; exit 0 ;;
    -*) print -r -u2 -- "the first argument is the version, not an option (got: $1); see --help / 第一個引數是版本，不是選項（收到：$1），請見 --help"; exit 2 ;;
esac
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
# The thing worth refusing is a PUBLISHED RELEASE, not the tag on its own.
#
# An archive has to be built AT the tag or its build id cannot say the version
# -- that is QD -- so the working order is: tag, build on each node, collect,
# publish. A blanket refusal on an existing tag makes that order impossible and
# forces building before tagging, which is the defect it would protect against.
#
# 值得拒絕的是一個**已發布的 release**，不是 tag 本身。
#
# 一份封存必須**在 tag 上**建置，否則它的 build id 說不出版本號——那就是 QD——所以可行的順序是：
# 先打 tag、各節點建置、收集、發布。對「tag 已存在」一律拒絕，會讓這個順序無法成立，逼人
# 「在打 tag 之前建置」——那正是它想防的缺陷。
TAG_EXISTED=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
        print -u2 -- "$TAG is already published. Re-cutting it disturbs anyone who fetched it; pick the next version"
        print -u2 -- "$TAG 已經發布過了。重打它會動到任何抓過它的人；請改用下一個版本號"
        exit 1
    fi
    # It exists but nothing was published from it. It must point at the commit
    # being released, or the archives were built from something else.
    # 它存在，但還沒有從它發布過任何東西。它必須指向「正在發布的那個 commit」，否則那些封存是
    # 從別的東西建出來的。
    if [[ $(git rev-parse "$TAG^{commit}") != $(git rev-parse HEAD) ]]; then
        print -u2 -- "$TAG exists but points at $(git rev-parse --short "$TAG^{commit}"), not HEAD $(git rev-parse --short HEAD)"
        print -u2 -- "$TAG 存在，但它指向 $(git rev-parse --short "$TAG^{commit}")，不是 HEAD $(git rev-parse --short HEAD)"
        exit 1
    fi
    TAG_EXISTED=1
fi
command -v gh >/dev/null 2>&1 || { print -u2 -- "gh is not on PATH"; exit 1 }
gh auth status >/dev/null 2>&1 || { print -u2 -- "gh is not authenticated"; exit 1 }

# ---------------------------------------------------------------------
# 2. The archives. Their checksums are RECOMPUTED here, never read from the
#    .sha256 files and never copied from a terminal: a 64-character hex string
#    transcribed by hand into two files can be wrong and nothing reports it.
# 2. 那些封存。它們的校驗和在這裡**重新計算**，不從 .sha256 檔讀、也不從終端機複製：手抄進
#    兩個檔案的 64 字元十六進位字串可能抄錯，而沒有任何東西會回報。
# ---------------------------------------------------------------------
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1" | cut -d' ' -f1
    else
        openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1
    fi
}

# The full sha of the commit being published, so each archive's embedded build
# id can be checked against it below rather than against anything a node said.
# 正在發布的那個 commit 的完整 sha，讓底下每一份封存內嵌的 build id 與它比對，而不是與任何一個節點
# 說過的話比對。
HEAD_SHA=$(git rev-parse HEAD)

# The binary inside an archive must carry THIS commit.
#
# Nothing else here can tell. The two checksums agree, the archive unpacks, the
# name says the right version -- and every one of those is equally true of an
# archive built from the PREVIOUS commit, because the node that built it also
# wrote the .sha256 beside it. release.zsh cannot catch it either: it compares
# the binary against the node's CHECKOUT, and a checkout left behind by a
# failed fetch is consistently one commit behind with its binary. So this
# checks the build id inside the binary against the commit actually being
# published, not against anything a node said.
#
# 封存裡的那個執行檔必須帶著**這一個** commit。
#
# 這裡沒有別的東西看得出來：兩份校驗和相符、封存解得開、名字寫著正確的版本——而這每一項對「用**上一個**
# commit 建出來的封存」同樣成立，因為那份 `.sha256` 正是建置它的節點自己寫的。release.zsh 也抓不到：
# 它比對的是執行檔與節點的 **checkout**，而一次失敗的 fetch 留下的 checkout，與它的執行檔一致地停在
# 舊 commit。所以這裡拿執行檔裡的 build id 去比「真正正在發布的那個 commit」，不比任何節點說過的話。
ARCHIVE_BUILD_ID=""
archive_commit_ok() {   # archive_commit_ok <archive> <inner path>
    local a=$1 inner=$2 base=${1:t} bx ids id sha bad=""
    local -a idlist
    ARCHIVE_BUILD_ID=""
    bx=$(mktemp -d "${TMPDIR:-/tmp}/csv2-bid.XXXXXX") || return 1
    zstd -dq -c -- "$a" | ( cd -- "$bx" && tar -xf - "$inner" )
    # `grep -a`: these are binaries, and without it grep replaces every match
    # with a single "Binary file matches" line -- which reads as a count of one
    # and, in a check shaped like this, as a pass. T307.
    # `grep -a`：這些是二進位檔，少了它，grep 會用一行「Binary file matches」取代所有比對結果——那讀起來
    # 像是「命中一次」，而在這種形狀的檢查裡就像是通過。T307。
    # The pattern is the BUILD ID alone, `vX.Y.Z / <commit>`, not the whole
    # `--version` line: swift builds that line from pieces at run time, so
    # `0.1.2 (v0.1.2 / 3a472bb)` is nowhere in the file. Searching for the
    # assembled form matches nothing and rejects every archive -- a check that
    # is always red, which gets worked around rather than read.
    #
    # Matching `v$VERSION / …` asserts two things at once: the tag the binary
    # was built at, and its commit. It does NOT separately verify CSV2_VERSION
    # inside the binary -- `0.1.2` alone is too common a string to locate
    # reliably -- and that is left to release.zsh on the node, which ran the
    # binary, and to the archive name checked above.
    #
    # 這個樣式是 **build id 本身**（`vX.Y.Z / <commit>`），不是整行 `--version`：那一行是 swift 在執行時
    # 組出來的，`0.1.2 (v0.1.2 / 3a472bb)` 根本不在檔案裡。找組好的形式會一個都比不到，把每一份封存
    # 都拒絕——**一個永遠是紅燈的檢查，會被繞過而不是被讀。**
    #
    # 比對 `v$VERSION / …` 同時斷言兩件事：執行檔建置時所在的 tag，以及它的 commit。它**不**另外驗證
    # 執行檔裡的 CSV2_VERSION——單獨的 `0.1.2` 太常見，定位不可靠——那件事交給節點上跑過該執行檔的
    # release.zsh，以及上面檢查過的封存名稱。
    ids=$(LC_ALL=C grep -a -o -E "v$VERSION / [0-9a-f]{7,40}" "$bx/$inner" | sort -u || true)
    rm -rf -- "$bx"
    if [[ -z $ids ]]; then
        print -u2 -- "$base: the binary carries no build id of the form \"v$VERSION / <commit>\""
        print -u2 -- "$base：執行檔裡沒有「v$VERSION / <commit>」形狀的 build id"
        return 1
    fi
    # Into an ARRAY, not a subscript on the expansion. `${${(f)ids}[1]}` looks
    # like "the first line" and is the first CHARACTER, so the passing path
    # would report a build id of `v`.
    # 存進**陣列**，不要對展開式直接下標。`${${(f)ids}[1]}` 看起來像「第一行」，實際上是第一個**字元**，
    # 通過那一路回報的 build id 會變成 `v`。
    idlist=(${(f)ids})
    for id in $idlist; do
        sha=${id##* / }
        # The short hash length is not guaranteed (git lengthens it when 8
        # would be ambiguous, and older builds used git's default), so this
        # asks whether it is a PREFIX of the commit, not whether it equals some
        # length this script picked. QT.
        # 短雜湊的長度沒有保證（8 碼有歧義時 git 會加長，較舊的建置用的是 git 預設值），所以這裡問的是
        # 「它是不是那個 commit 的前綴」，不是「它等不等於本腳本挑的某個長度」。QT。
        [[ $HEAD_SHA == $sha* ]] || bad="$bad $id"
    done
    if [[ -n $bad ]]; then
        print -u2 -- "$base was built from another commit: its binary says$bad, this release is ${HEAD_SHA[1,7]}"
        print -u2 -- "$base 是從別的 commit 建出來的：它的執行檔說$bad，而這次發布的是 ${HEAD_SHA[1,7]}"
        return 1
    fi
    ARCHIVE_BUILD_ID=$idlist[1]
    return 0
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
    # BEFORE the refusal below can say what was wrong. PE.
    # `|| true`：在 errexit 與 pipe_fail 之下，一個找不到東西的 grep 回傳 1，命令替換繼承它，
    # 而那個賦值會在底下那道拒絕來得及說明之前就殺掉腳本。PE。
    inner=$(zstd -dq -c -- "$a" | tar -tf - | grep -E "^$stem/csv2(\.exe)?$" | head -1 || true)
    [[ -n $inner ]] || {
        print -u2 -- "$base does not contain $stem/csv2 or $stem/csv2.exe"
        print -u2 -- "$base 裡面沒有 $stem/csv2 或 $stem/csv2.exe"
        exit 1
    }
    archive_commit_ok "$a" "$inner" || exit 1
    say "    $base  $h  $ARCHIVE_BUILD_ID"
done

# ---------------------------------------------------------------------
# 3. Tag.
# ---------------------------------------------------------------------
say ""
say "steps / 步驟："
if (( TAG_EXISTED )); then
    say "  $TAG already points at HEAD and nothing is published from it; reusing it"
    if (( DO_PUBLISH )); then git push -q origin "$TAG" 2>/dev/null || true; fi
else
    would "git tag -a $TAG && git push origin $TAG"
    if (( DO_PUBLISH )); then
        git tag -a "$TAG" -m "csv2 $VERSION"
        git push -q origin "$TAG"
    fi
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
#    different claim from "what a stranger downloads is what was built".
# 5. 從**公開** URL 重新下載並比對。這不是好習慣，是一個步驟。「gh release create 以 0 結束」
#    說的是「上傳被接受了」，而那與「陌生人下載到的，就是建出來的那一份」是兩件事。
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
#      read back and compared. This is the step a person is least able to
#      check by eye: two hex strings differ in one character and look identical.
# 6/7. 套件檔，由封存**產生**而不是打進去。每一個 url 與 hash 都從 ${HASH[...]} 改寫，
#      而結果會被讀回來比對。這是最不可能靠肉眼檢查的一步：兩個十六進位字串差一個字元，
#      看起來一模一樣。
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
# scoop/csv2.json has a SECOND url per platform in its autoupdate block -- a
# template carrying a literal $version -- so counting every url with the
# platform suffix finds two and refuses. Lines carrying $version are templates
# and are deliberately left alone.
# scoop/csv2.json 的 autoupdate 區塊裡，每個平台有**第二個** url——一個帶著字面 $version 的模板——
# 所以數「每一個含有該平台後綴的 url」會數到兩個然後拒絕。含有 $version 的行是模板，這裡刻意不動。
# The url and the hash are not the only things carrying a version. scoop's
# extract_dir must equal the directory inside the archive or the install puts
# the binary nowhere; the Formula's `version` and its `assert_match "csv2 X"`
# are two more. Rewriting only the pair leaves four stale sites in two files;
# the read-back at the end greps for any old number.
# 帶著版本號的不只 url 與 hash。scoop 的 extract_dir 必須等於封存內的目錄名，否則安裝會把
# 執行檔放到不存在的地方；Formula 的 `version` 與它的 `assert_match "csv2 X"` 是另外兩個。
# 只改 url/hash 那一對，會在兩個檔案裡留下四個過期的位置；結尾的讀回檢查會 grep 任何舊版本號。
# Which lines carry the version as DATA, and which merely TALK ABOUT it.
#
# Both rewritten files contain prose that names a version as history, and
# history does not move with a new release. Rewriting it turns a sentence like
# "aarch64 arrives in v0.1.1. It was absent from v0.1.0" into one that
# contradicts itself, and makes a dated verification record claim a version
# that did not exist that day. A record that says it was verified is the one a
# reader has least reason to doubt. QM.
#
# ONE definition, used by the rewrite AND by the read-back that demands no
# stale version remains. If they disagreed, prose left correct by one would be
# failed by the other, and the only way to satisfy both would be to corrupt
# it: the check would make the damage a PASSING condition.
#
# 哪些行「帶著版本號這個資料」，哪些只是「在談論那個版本號」。
#
# 兩個被改寫的檔案裡都有把版本號當成**歷史**來記的散文，而歷史不隨新版本前進。改寫它，會把
# 「aarch64 arrives in v0.1.1. It was absent from v0.1.0」這類句子改成自相矛盾，也會讓一筆帶日期的
# 查證紀錄宣稱一個當天還不存在的版本。一則說自己「已被驗證」的紀錄，是讀者最沒有理由懷疑的那一種。QM。
#
# **一份定義**，同時給改寫與「不得殘留舊版本號」那道讀回檢查用。兩者若各有一份，被其中一個
# 正確留下的散文會被另一個判定失敗，而唯一能同時滿足它們的做法就是把散文改壞——那道檢查會把
# 「破壞」變成**通過條件**。
# The KIND is passed explicitly rather than taken from the name, because the
# leftover check runs against `$file.rewriting.$$`, whose extension is a process
# id. Deriving it there would classify nothing as prose and quietly restore the
# old behaviour for the one check that matters most.
# **種類**是明白傳進來的，不是從檔名推的：殘留檢查跑的對象是 `$file.rewriting.$$`，它的副檔名是
# 一個 process id。在那裡用推的會把「沒有任何一行是散文」當成結論，於是最重要的那道檢查會安靜地
# 退回不分散文的行為。
prose_lines() {   # prose_lines <file> <kind> — prints the prose line numbers, one per line
    setopt local_options extended_glob
    local file=$1 kind=$2 line trimmed
    integer n=0 in_notes=0
    while IFS= read -r line || [[ -n $line ]]; do
        n+=1
        trimmed=${line##[[:space:]]#}
        case $kind in
            rb)
                # A Ruby comment is never read by brew.
                # Ruby 註解不會被 brew 讀到。
                [[ $trimmed == '#'* ]] && print -r -- $n
                ;;
            json)
                # scoop's "notes" are shown to the person installing. They are
                # prose, and one of them records a dated verification.
                # scoop 的 "notes" 會顯示給安裝的人看。它們是散文，而其中一筆記的是一次帶日期的查證。
                if (( in_notes )); then
                    print -r -- $n
                    [[ $trimmed == ']'* ]] && in_notes=0
                elif [[ $trimmed == '"notes"'* ]]; then
                    print -r -- $n
                    [[ $line == *']'* ]] || in_notes=1
                fi
                ;;
        esac
    done < $file
}

data_text() {   # data_text <file> <kind> — the file with its prose lines removed
    local file=$1 kind=$2 line ln
    local -A p
    integer n=0
    for ln in ${(f)"$(prose_lines $file $kind)"}; do
        [[ -n $ln ]] && p[$ln]=1
    done
    while IFS= read -r line || [[ -n $line ]]; do
        n+=1
        [[ -n ${p[$n]-} ]] || print -r -- "$line"
    done < $file
}

rewrite_version() {   # $1 = file
    setopt local_options extended_glob
    # `kind` on its own line: zsh expands every word of a `local` BEFORE making
    # any of the assignments, so `local file=$1 kind=${file:e}` reads a `file`
    # that is local-but-unset and dies under `no_unset` -- during a publish.
    # `kind` 另起一行：zsh 會先展開 `local` 的**所有**字詞才做賦值，所以
    # `local file=$1 kind=${file:e}` 讀到的是一個「已宣告為區域、但還沒有值」的 `file`，
    # 在 `no_unset` 之下會死掉——而且是死在發布途中。
    local file=$1 line old="" ln
    local kind=${file:e}
    local -A prose
    integer lineno=0
    for ln in ${(f)"$(prose_lines $file $kind)"}; do
        [[ -n $ln ]] && prose[$ln]=1
    done
    # The version this file currently declares, taken as the first X.Y.Z token
    # on a line that mentions "version". Reading "the first quoted word after
    # the first quote" instead yields `: ` on scoop's `"version": "0.1.0",`, and
    # replacing that throughout mangles most of the file.
    # 這個檔案目前宣告的版本，取自「提到 version 的那一行上的第一個 X.Y.Z token」。若改用
    # 「第一個引號之後的第一個帶引號字詞」，在 scoop 的 `"version": "0.1.0",` 上會得到 `: `，
    # 再全檔替換就會弄爛大半個檔案。
    while IFS= read -r line; do
        lineno+=1
        [[ -n ${prose[$lineno]-} ]] && continue
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
    lineno=0
    while IFS= read -r line || [[ -n $line ]]; do
        lineno+=1
        if [[ -z ${prose[$lineno]-} ]] && [[ $line == *$old* ]]; then
            line=${line//$old/$VERSION}
            n+=1
        fi
        print -r -- "$line" >> $tmpf
    done < $file
    # Check the RESULT before adopting it. A mangled file is still readable and
    # still contains the new version; only a look at the whole product shows
    # it. `|| true` because a grep that finds nothing returns 1 and would kill
    # the script under errexit -- PE.
    # 在採用之前先檢查**產物**。被弄爛的檔案仍然讀得動、也仍然含有新版本號；只有看整份產物才
    # 看得出來。`|| true` 是因為找不到東西的 grep 回傳 1，在 errexit 之下會殺掉腳本——PE。
    local left
    left=$(data_text $tmpf $kind | LC_ALL=C grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | LC_ALL=C sort -u \
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
        # oversight -- a platform whose archive could not be verified where it
        # was made is left out on purpose -- so say so and move on.
        # 那個平台沒有列在那個檔案裡。那是一個決定而不是疏漏——「封存無法在產生它的地方被驗證」
        # 的平台是刻意略過的——所以說出來就好，不要自作主張加進去。
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
    # catches a stale extract_dir or assert_match; the pair check above cannot,
    # because they are not part of the pair.
    # 而兩個檔案裡的任何地方都不可以再留著**別的**版本號。過期的 extract_dir 或 assert_match
    # 要靠這道檢查抓；上面那個「成對」的檢查抓不到，因為它們不屬於那一對。
    for f in $HERE/Formula/csv2.rb $HERE/scoop/csv2.json; do
        [[ -r $f ]] || continue
        # Every distinct X.Y.Z token in the file, minus the one being
        # published. Comparing tokens rather than lines is what makes a line
        # carrying BOTH the new version and a stale one still fail.
        # 檔案裡每一個相異的 X.Y.Z token，扣掉正在發布的那一個。比對 token 而不是比對「行」，
        # 是「一行同時含有新版本與一個過期版本」時仍然會失敗的原因。
        # Prose is excluded here by the SAME definition the rewrite used, so a
        # sentence recording history keeps its version and a data line that went
        # stale still fails. QM.
        # 這裡用**與改寫相同的那份定義**排除散文，於是一句記錄歷史的話保住它的版本號，而一行過期的
        # 資料仍然會失敗。QM。
        _stale=$(data_text "$f" "${f:e}" | LC_ALL=C grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
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
    # The version in the package files is NOT left to a person: rewrite_version
    # did it above and the read-back confirmed it, so the hint must not tell
    # the reader to redo it.
    # 套件檔裡的版本號**不是**留給人做的：上面的 rewrite_version 已經改了，而讀回來那一步確認過，
    # 所以提示不可以叫讀者重做。
    say "next, by hand and on purpose: the release notes. The version in the"
    say "package files was rewritten above and read back."
    say "接下來是刻意留給人做的：release notes。套件檔裡的版本號，上面已經改寫並讀回確認過了。"
    say "then run ./test/test_csv2.zsh -- the package files are checked by it"
    say "然後跑 ./test/test_csv2.zsh——那些套件檔由它檢查"
    # The release is not finished until the copy each node RUNS is the new one.
    # A suite passing on a node says nothing about this: it tests release/csv2,
    # not the csv2 on PATH, which can stay several releases behind while the
    # suite keeps passing. brew and scoop keep their nodes current; WSL has no
    # package manager, so it is upgraded on EVERY release. These lines exist so
    # that step is not the one that is skipped.
    # 一次出貨，要到每個節點**實際執行**的那一份換成新版才算結束。某個節點的套件通過，對這件事什麼
    # 也沒說：它測的是 release/csv2，不是 PATH 上的 csv2——後者可能落後好幾個版本，而套件照樣通過。
    # brew 與 scoop 會讓它們的節點跟上；WSL 沒有套件管理員，所以**每次出貨**都要升級它。這幾行存在，
    # 是為了讓那一步不會是被跳過的那一步。
    say "then upgrade the copy each node RUNS, and read its --version on PATH:"
    say "  macOS   brew update && brew upgrade raliclo/csv2/csv2"
    say "  Windows scoop update csv2"
    say "  WSL     every release, in place: /usr/local/bin/csv2 (no package manager there)"
    say "  guest   runs /workspace/csv2/release/csv2, the build made at the tag"
    say "然後升級每個節點**實際執行**的那一份，並讀 PATH 上那一份的 --version："
    say "  macOS 用 brew、Windows 用 scoop、WSL **每次出貨**都在原地取代 /usr/local/bin/csv2、"
    say "  guest 跑的是在 tag 上建的 /workspace/csv2/release/csv2"
    # The mother project does all four and reads each one back; its exit
    # status is the answer (0 = every node's PATH says this version, 3 = some
    # node skipped on purpose, 1 = not finished). It lives there because node
    # and permission knowledge does: the root install on WSL goes through the
    # Windows node's wsl.exe.
    # 母專案那支腳本把四個節點都做掉並一一讀回；它的退出碼就是答案（0 = 每個節點 PATH 上都是這個
    # 版本，3 = 有節點被刻意略過，1 = 還沒結束）。它放在母專案，因為節點與權限的知識在那裡：WSL 上
    # 的 root 安裝是經由 Windows 節點的 wsl.exe 做的。
    say ""
    say "all of the above, with the read-back, from the parent project / 以上全部連同讀回，在母專案執行："
    say "  helper/install_release.zsh csv2 $VERSION            (--verify: read only / 只讀不裝)"
else
    say "nothing was changed. Re-run with --publish to do the above."
    say "什麼都沒有改動。加上 --publish 才會真的執行。"
fi

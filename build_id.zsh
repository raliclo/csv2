#!/usr/bin/env zsh
# =====================================================================
#  build_id.zsh — the one place that decides what --version prints
#  build_id.zsh — 決定 --version 印出什麼的唯一一個地方
#
#  Sourced by compile_csv2.zsh, compile_csv2_linux.zsh and release.zsh, so
#  the thing that STAMPS the binary and the thing that CHECKS the stamp
#  cannot disagree about its shape. A checker that enumerates the shapes
#  `git describe` can answer with, instead of asking for the answer, goes
#  wrong. QC.
#
#  由 compile_csv2.zsh、compile_csv2_linux.zsh 與 release.zsh 共同 source，讓「在執行檔上
#  蓋章的一方」與「檢查章的一方」對它的形狀不可能有歧見。去**列舉** `git describe` 可能
#  回答的形式、而不是直接問答案的檢查，遲早會錯。QC。
#
#  compile_csv2_win.bat carries its own copy in batch, which cannot source
#  this. T303 pins the property both must satisfy, so a drifting copy is
#  reported by the suite.
#  compile_csv2_win.bat 有自己的 batch 版本，因為它無法 source 這個檔案。T303 釘住兩者都必須
#  滿足的性質，副本一旦漂移，測試就會回報。
# =====================================================================

# The build id ALWAYS contains the commit, and says the tag when there is one.
#
# `git describe --always` answers according to whether a tag existed when the
# build ran, not according to the source: the same commit says `(8d5600e)`
# before the tag is cut and `(v0.1.0)` after. Without the hash, the id cannot
# answer "which commit is this". QD.
#
# 這個 build id **永遠含有 commit**，有 tag 時也說出 tag。
#
# `git describe --always` 的答案取決於「**建置當下**有沒有 tag」，而不是原始碼：同一個 commit
# 在打 tag 之前是 `(8d5600e)`，之後是 `(v0.1.0)`。少了雜湊，這個 id 就答不出「這是哪個 commit」。QD。
#
# The hash is ALWAYS 8 characters (`--abbrev=8`, `--short=8`), never git's
# default. That default grows with the clone's object count and follows each
# machine's `core.abbrev`, so one commit would print differently on different
# build machines. git still lengthens it if 8 would be ambiguous, which is the
# one case where a longer hash is right. QT.
#
# 雜湊**一律 8 碼**（`--abbrev=8`、`--short=8`），不用 git 的預設值。預設值會隨 clone 的物件數
# 增長，也受各機器的 `core.abbrev` 影響，同一個 commit 在不同建置機上會印成不同字串。若 8 碼
# 有歧義，git 仍會加長——那是唯一「較長才對」的情況。QT。
# `cd` in a subshell rather than `git -C`, because the shell and git do not
# agree about what a path is on Windows. There, zsh's `pwd` is MSYS-style
# `/c/Users/...` -- so `${0:A:h}` is too -- and git for Windows answers
# `fatal: cannot change to '/c/Users/...'`. The shell can cd there, and git
# asked from inside that directory needs no path at all. QN.
# 在子 shell 裡 `cd`，不用 `git -C`：在 Windows 上 shell 與 git 對路徑的認知不同。
# 那裡 zsh 的 `pwd` 是 MSYS 風格的 `/c/Users/...`（`${0:A:h}` 也是），而 git for Windows 會回答
# `fatal: cannot change to '/c/Users/...'`。shell 進得去那個目錄，在目錄裡問 git 就不需要路徑。QN。
csv2_build_id() {   # csv2_build_id <repo-dir>
    local dir=$1 described short
    described=$(cd "$dir" 2>/dev/null && git describe --always --dirty --abbrev=8 2>/dev/null) || described=""
    short=$(cd "$dir" 2>/dev/null && git rev-parse --short=8 HEAD 2>/dev/null) || short=""
    # No git at all: the guest builds from a tar payload with no .git, and
    # `unknown` is a true thing to say about that build rather than a guess.
    #
    # Where a repository exists, an empty answer means the question was
    # malformed, not that there is no git, so it is reported as a failure
    # rather than printed as `unknown`. QN.
    #
    # 完全沒有 git：guest 是從沒有 .git 的 tar payload 建置的，此時 `unknown` 是實話，不是猜測。
    #
    # 只要有 repository，空的答案就代表提問方式有誤、而不是沒有 git，因此當成失敗回報，
    # 不印成 `unknown`。QN。
    if [[ -z $described && -z $short ]]; then
        if [[ -e $dir/.git ]]; then
            print -u2 -- "csv2_build_id: $dir has a .git but git answered nothing; the question was malformed, not the tree"
            print -u2 -- "csv2_build_id：$dir 有 .git，而 git 什麼都沒回答；問題出在提問方式，不在那棵樹"
            print -u2 -- "$(cd "$dir" 2>/dev/null && git describe --always --dirty --abbrev=8 2>&1 | head -2)"
            return 1
        fi
        print -r -- unknown
        return
    fi
    [[ -n $described ]] || { print -r -- "$short"; return }
    [[ -n $short ]] || { print -r -- "$described"; return }
    # `v0.1.1-5-ga1b2c3d` already carries the hash; printing it twice would say
    # nothing and make the line longer. Only a bare tag needs the hash added.
    # `v0.1.1-5-ga1b2c3d` 本來就帶著雜湊，印兩次不會多說任何事，只會讓那一行更長。只有「純 tag」
    # 的形式需要把雜湊補上。
    if [[ $described == *"$short"* ]]; then
        print -r -- "$described"
    else
        print -r -- "$described / $short"
    fi
}

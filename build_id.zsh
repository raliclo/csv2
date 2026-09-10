#!/usr/bin/env zsh
# =====================================================================
#  build_id.zsh — the one place that decides what --version prints
#  build_id.zsh — 決定 --version 印出什麼的唯一一個地方
#
#  Sourced by compile_csv2.zsh, compile_csv2_linux.zsh and release.zsh, so
#  the thing that STAMPS the binary and the thing that CHECKS the stamp
#  cannot disagree about its shape. release.zsh's version check has been
#  wrong three times, each time by enumerating the shapes `git describe`
#  can answer with instead of asking for the answer. QC.
#
#  由 compile_csv2.zsh、compile_csv2_linux.zsh 與 release.zsh 共同 source，讓「在執行檔上
#  蓋章的那一方」與「檢查那個章的那一方」不可能對它的形狀有不同意見。release.zsh 的版本檢查
#  錯過三次，每一次都是去**列舉** `git describe` 可能回答的形式，而不是去問那個答案。QC。
#
#  compile_csv2_win.bat carries its own copy in batch, which cannot source
#  this. T303 pins the property both must satisfy, so a copy that drifts is
#  reported rather than discovered during a release.
#  compile_csv2_win.bat 帶著它自己的 batch 版本——它 source 不了這個檔案。T303 釘住兩者都必須
#  滿足的那個性質，於是一份漂掉的副本會被回報，而不是在某次出貨當中才被發現。
# =====================================================================

# The build id ALWAYS contains the commit, and says the tag when there is one.
#
# `git describe --always` answers according to whether a tag existed WHEN THE
# BUILD RAN, not according to the source: the three published v0.1.0 archives
# say `(8d5600e)` because they were built before the tag was cut, and the same
# commit built afterwards says `(v0.1.0)`. Same source, two strings, and no
# rebuild changes that -- so the id could not answer the one question it exists
# to answer, "which commit is this". QD.
#
# 這個 build id **永遠含有那個 commit**，而在有 tag 時也說出 tag。
#
# `git describe --always` 的答案取決於「**建置執行的當下**有沒有 tag」，不取決於原始碼：已發布的
# 三份 v0.1.0 封存說的是 `(8d5600e)`，因為它們是在 tag 被打之前建的，而同一個 commit 之後建出來
# 說的是 `(v0.1.0)`。同一份原始碼、兩種字串，而重建改不了——於是那個 id 回答不了它存在所要回答的
# 唯一問題：「這是哪一個 commit」。QD。
csv2_build_id() {   # csv2_build_id <repo-dir>
    local dir=$1 described short
    described=$(git -C "$dir" describe --always --dirty 2>/dev/null) || described=""
    short=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null) || short=""
    # No git at all: the guest builds from a tar payload with no .git, and
    # `unknown` is a true thing to say about that build rather than a guess.
    # 完全沒有 git：guest 是從一個沒有 .git 的 tar payload 建的，而 `unknown` 是關於那次建置的
    # 一句真話，不是猜測。
    if [[ -z $described && -z $short ]]; then
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

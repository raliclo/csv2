#!/usr/bin/env zsh
# =====================================================================
# install.zsh — put the built csv2 where the shell can find it
# install.zsh — 把建好的 csv2 放到 shell 找得到的地方
#
# Usage / 用法:
#   ./install.zsh              install / 安裝
#   ./install.zsh --uninstall  remove it again / 移除
#   ./install.zsh --dry-run    say what would happen, touch nothing / 只說會做什麼，不動任何東西
#   ./install.zsh --prefix DIR install into DIR instead / 改裝到 DIR
#   ./install.zsh --no-rc     do not touch any shell rc file / 不要改動任何 shell rc 檔
#
# THIS IS NOT A HOMEBREW INSTALL. Read the warning it prints.
# 這不是 Homebrew 安裝。請讀它印出的警告。
#
# Not covered here: the guest. csv2 is deliberately NOT shipped in the LinuxCS
# rootfs (plan.md, "目前不進 rootfs") -- the scripts that need it run on the
# macOS host, and the guest carries a fixed 128 MiB rootfs whose budget is not
# spent on a tool nothing in there calls. The guest builds csv2 from source for
# testing and throws it away with the per-run image clone. Installing there is
# phase 7 and is a deliberate deferral, not an oversight.
# 不涵蓋 guest。csv2 刻意不隨 LinuxCS rootfs 出貨（plan.md「目前不進 rootfs」）——
# 需要它的腳本都在 macOS host 上，而 guest 的 rootfs 固定 128 MiB，那份預算不該花在
# 一個 guest 裡沒有東西會呼叫的工具上。guest 是為了測試而從原始碼建置 csv2，並隨著
# 每次執行的 image 複本一起丟棄。在那裡安裝屬於第 7 階段，是刻意暫緩而非疏漏。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail

ROOT=${0:A:h}
BIN=$ROOT/release/csv2
DRY=0
MODE=install
PREFIX=""
RC=1

while (( $# )); do
    case $1 in
        --uninstall) MODE=uninstall ;;
        --dry-run)   DRY=1 ;;
        --no-rc)     RC=0 ;;
        --prefix)    shift; [[ $# -gt 0 ]] || { print -u2 -- "--prefix needs a directory / --prefix 需要一個目錄"; exit 2 }; PREFIX=$1 ;;
        -h|--help)   sed -n '3,21p' ${0:A}; exit 0 ;;
        *) print -u2 -- "unknown option: $1 / 未知選項：$1"; exit 2 ;;
    esac
    shift
done

say()  { print -r -- "$1" }
die()  { print -u2 -- "install.zsh: $1"; exit 1 }
run()  { if (( DRY )); then say "  DRY  $*"; else "$@" || die "failed: $*"; fi }

# ---------------------------------------------------------------------
# Which shell, and therefore which file
#
# ASK the account, never assume the one running this script. install.zsh is
# `#!/usr/bin/env zsh`, so the shell it is running in is always zsh -- and that
# says nothing about the shell the person gets when they open a terminal. On
# the WSL node on 2026-08-25 the login shell was /bin/bash, and the ONLY rc
# file in that home directory was `.zshrc`. Writing the export where this
# script runs would have put the right line into the one file nothing reads,
# and then reported success.
#
# 問這個帳號，絕不假設「執行本腳本的那個 shell」。install.zsh 是 `#!/usr/bin/env zsh`，
# 所以它執行時所在的 shell 永遠是 zsh——而那對「這個人開終端機時拿到的是哪個 shell」
# 毫無說明力。2026-08-25 的 WSL 節點，登入 shell 是 /bin/bash，而那個家目錄裡**唯一**
# 存在的 rc 檔是 `.zshrc`。把 export 寫到「本腳本執行的那個 shell」對應的位置，會把正確
# 的那一行放進一個沒有東西會讀的檔案，然後回報成功。
# ---------------------------------------------------------------------
login_shell() {
    local sh=""
    sh=$(getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $NF}') || sh=""
    [[ -n $sh ]] || sh=${SHELL:-}
    [[ -n $sh ]] || sh=$(command -v zsh 2>/dev/null) || sh=/bin/sh
    print -r -- $sh
}
LOGIN_SHELL=$(login_shell)
LOGIN_SHELL_NAME=${LOGIN_SHELL:t}

# Which files that shell reads, and why more than one for bash.
#
# bash reads the LOGIN files (~/.bash_profile, ~/.bash_login, ~/.profile --
# first one that exists) for a login shell, and ~/.bashrc for an interactive
# non-login one. Neither file alone covers both, which is why Debian ships a
# ~/.profile that sources ~/.bashrc; we reproduce that arrangement rather than
# invent one. zsh reads ~/.zshrc for every interactive shell, so one file does.
#
# bash 在「登入 shell」時讀登入檔（~/.bash_profile、~/.bash_login、~/.profile，取
# 第一個存在的），在「互動非登入」時讀 ~/.bashrc。任何一個檔案單獨都蓋不住兩者，
# 這正是 Debian 的 ~/.profile 會去 source ~/.bashrc 的原因；我們沿用那個安排，而不是
# 自己發明一個。zsh 每個互動 shell 都讀 ~/.zshrc，所以一個檔案就夠。
rc_files() {
    case $LOGIN_SHELL_NAME in
        # .zshenv, not .zshrc. zsh reads .zshrc only for INTERACTIVE shells,
        # and the thing that needed csv2 on the WSL node was record_release.zsh
        # running over multissh -- a non-interactive, non-login shell that
        # reads .zshenv and nothing else. Putting the line in .zshrc would have
        # fixed a person's terminal and left the script that actually failed
        # still failing, while this installer reported success. The node had
        # already learned this: its .zshrc says the Swift toolchain PATH lives
        # in .zshenv "because `zsh -lc` does not read this file".
        # 是 .zshenv 而不是 .zshrc。zsh 只有在**互動** shell 才讀 .zshrc，而在 WSL 節點上
        # 需要 csv2 的是經 multissh 執行的 record_release.zsh——一個非互動、非登入的
        # shell，它只讀 .zshenv。把那一行寫進 .zshrc，會修好某個人的終端機，而讓當初真正
        # 失敗的那支腳本繼續失敗，同時這支安裝程式回報成功。那個節點其實已經學會這件事：
        # 它的 .zshrc 自己寫著，Swift 工具鏈的 PATH 放在 .zshenv，「因為 `zsh -lc` 不讀這個檔案」。
        zsh)  print -r -- $HOME/.zshenv ;;
        # bash has no .zshenv. BASH_ENV would be the equivalent and is not set
        # by default, so .bashrc plus a login file is as far as bash goes.
        # bash 沒有 .zshenv 的對應物。BASH_ENV 是對應的機制但預設沒有設定，因此 bash 能做到
        # 的就是 .bashrc 加上一個登入檔。
        bash) print -r -- $HOME/.bashrc ;;
        *)    print -r -- $HOME/.profile ;;
    esac
}

# Every file this script may ever have written a block into -- which is not
# the same list as the one it writes to TODAY. Uninstall has to ask the wider
# question: the bash install writes to ~/.bashrc AND to a login file, and an
# uninstall that only consulted rc_files() removed one of the two and left the
# other behind, still carrying a marker that says csv2 put it there. Verified
# on 2026-08-25; that is what this list exists to prevent.
# 這支腳本「曾經可能」寫過區塊的每一個檔案——而那不等於它「今天」會寫的那一份清單。
# 移除必須問比較寬的那個問題：bash 的安裝會寫進 ~/.bashrc **以及**一個登入檔，而一個只
# 看 rc_files() 的移除，會拿掉兩者之一、留下另一個，且那一個上面還標著「csv2 放的」。
# 2026-08-25 實測如此，這份清單就是為了擋住它而存在。
rc_candidates() {
    print -l -- $HOME/.zshenv $HOME/.zshrc $HOME/.zprofile $HOME/.bashrc \
                $HOME/.profile $HOME/.bash_profile $HOME/.bash_login
}

RC_BEGIN='# >>> csv2 install.zsh >>>'
RC_END='# <<< csv2 install.zsh <<<'

# Remove any block we previously wrote, so a second install does not leave two.
# 移除我們先前寫過的區塊，讓第二次安裝不會留下兩份。
rc_strip() {
    local f=$1
    [[ -f $f ]] || return 0
    grep -qF "$RC_BEGIN" $f 2>/dev/null || return 0
    local tmp=$f.csv2.$$
    awk -v b="$RC_BEGIN" -v e="$RC_END" \
        '$0==b {skip=1} !skip {print} $0==e {skip=0}' $f > $tmp || return 1
    mv $tmp $f
}

rc_append() {  # <file> <dir>
    local f=$1 d=$2
    rc_strip $f || die "could not rewrite $f / 無法改寫 $f"
    # $HOME rather than its expansion: the same line then works if the home
    # directory is ever reached by another path.
    # 寫 $HOME 而非展開後的值：家目錄日後若由另一條路徑抵達，同一行仍然成立。
    local shown=$d
    [[ $d == $HOME/* ]] && shown='$HOME'${d#$HOME}
    {
        print -r -- ""
        print -r -- "$RC_BEGIN"
        print -r -- "# csv2 is installed in this directory; put it where the shell looks."
        print -r -- "# csv2 裝在這個目錄裡；把它放到 shell 會去找的地方。"
        print -r -- "case \":\$PATH:\" in *\":$shown:\"*) ;; *) export PATH=\"$shown:\$PATH\" ;; esac"
        print -r -- "$RC_END"
    } >> $f || die "could not append to $f / 無法附加到 $f"
}

# Run a command the way the person's own shell would: login AND interactive,
# because that is the only combination that reads every file we may have
# written. `zsh -lc` -- what this script used to verify with -- is login but
# NOT interactive, and zsh reads .zshrc only when interactive. It would have
# missed the very line we just added.
# 以「這個人自己的 shell」的方式執行：同時是登入與互動的，因為只有這個組合會讀到我們
# 可能寫過的每一個檔案。`zsh -lc`——本腳本原本用來驗證的方式——是登入但**不是**互動，
# 而 zsh 只有在互動時才讀 .zshrc。它會漏掉我們剛加上的那一行。
# Non-interactive FIRST, and remember which one answered.
#
# The three cases are not equivalent and the difference is the whole point:
# `-c` is what a script reached over ssh gets, `-lc` a login shell, `-lic` a
# terminal. A directory reachable only from the last of those satisfies a
# person typing `csv2` and still fails record_release.zsh, which is the exact
# failure that made this installer touch rc files at all.
# 先問最嚴格的那一個，並記住是哪一個回答的。
# 三種情況並不等價，而那個差別正是重點：`-c` 是「經 ssh 執行的腳本」拿到的，`-lc` 是登入
# shell，`-lic` 是終端機。一個只有在最後一種情況下才找得到的目錄，滿足了「有人打 csv2」，
# 卻仍然讓 record_release.zsh 失敗——而那正是這支安裝程式會去動 rc 檔的原因。
# The result comes back in globals, not on stdout. A function whose caller
# writes `x=$(f)` runs it in a SUBSHELL, so anything f records about HOW it got
# the answer dies with that subshell -- a check that measured the right thing
# and could not report it.
# 結果以全域變數回傳，而不是走 stdout。呼叫端若寫成 `x=$(f)`，f 會在 **subshell** 裡執行，
# 於是 f 記下的「它是怎麼得到這個答案的」會隨那個 subshell 一起消失——一個量對了、卻報告
# 不出來的檢查。
# A FRESH environment, not this one.
#
# `zsh -c` does not reset PATH -- it inherits the exported PATH of whatever
# called it. So probing with a plain `$LOGIN_SHELL -c` asks "is csv2 on the
# PATH I already have", answers yes, and reports it as "every shell finds it".
# Seen here on 2026-08-25: a --prefix install into a temp directory reported
# success while the shell had resolved csv2 out of /opt/homebrew/bin, which the
# rc file it had just written had nothing to do with. The question is what a
# shell started from nothing can see, so start one from nothing.
#
# 用一個**全新的**環境，不是現在這個。
# `zsh -c` 不會重設 PATH——它繼承呼叫者匯出的 PATH。因此用單純的 `$LOGIN_SHELL -c` 去探測，
# 問的是「csv2 在我已經有的那個 PATH 上嗎」，答案是「在」，然後被回報成「每一種 shell 都
# 找得到」。2026-08-25 在此見到：一次裝進暫存目錄的 --prefix 安裝回報成功，而那個 shell 解析
# 到的是 /opt/homebrew/bin 裡的 csv2，與它剛寫下的那個 rc 檔毫無關係。要問的是「一個從零
# 開始的 shell 看得到什麼」，那就從零開始一個。
probe_env() {
    local -a keep out
    # HOME because rc files are found through it; the rest so that a shell on
    # Windows or a locale-sensitive rc file still behaves.
    # HOME 是因為 rc 檔要靠它才找得到；其餘是為了讓 Windows 上的 shell、以及對 locale 敏感的
    # rc 檔仍然正常。
    keep=(HOME USER LOGNAME LANG LC_ALL TERM SHELL
          SYSTEMROOT WINDIR USERPROFILE LOCALAPPDATA APPDATA MSYSTEM TMP TEMP)
    for v in $keep; do
        [[ -n ${(P)v:-} ]] && out+=("$v=${(P)v}")
    done
    print -r -- ${(j: :)${(q)out}}
}

PROBE_KIND=""
PROBE_OUT=""
in_user_shell() {
    local out
    PROBE_KIND=""; PROBE_OUT=""
    local -a E; E=(env -i ${(z)$(probe_env)})
    if out=$($E $LOGIN_SHELL -c "$1" 2>/dev/null) && [[ -n $out ]]; then
        PROBE_KIND="every shell, scripts over ssh included / 每一種 shell，包含經 ssh 的腳本"
    elif out=$($E $LOGIN_SHELL -lc "$1" 2>/dev/null) && [[ -n $out ]]; then
        PROBE_KIND="login shells only; a script over ssh will NOT find it / 只有登入 shell；經 ssh 的腳本找不到"
    elif out=$($E $LOGIN_SHELL -lic "$1" 2>/dev/null) && [[ -n $out ]]; then
        PROBE_KIND="interactive terminals only; scripts will NOT find it / 只有互動終端機；腳本找不到"
    else
        return 1
    fi
    PROBE_OUT=$out
}

# ---------------------------------------------------------------------
# Where to install / 裝到哪裡
#
# ASK brew, never hardcode. The prefix is /opt/homebrew on Apple Silicon,
# /usr/local on Intel macOS and /home/linuxbrew/.linuxbrew on Linuxbrew --
# three different answers, and hardcoding any one of them silently installs
# into a directory that exists but is not the one brew is using.
# 問 brew，絕不寫死。prefix 在 Apple Silicon 上是 /opt/homebrew、Intel macOS 上是
# /usr/local、Linuxbrew 上是 /home/linuxbrew/.linuxbrew——三個不同的答案，寫死任何
# 一個都會安靜地裝進「存在、但不是 brew 正在使用」的目錄。
# ---------------------------------------------------------------------
target_dir() {
    if [[ -n $PREFIX ]]; then
        print -r -- $PREFIX
        return
    fi
    local p
    if p=$(brew --prefix 2>/dev/null) && [[ -d $p/bin ]]; then
        print -r -- $p/bin
        return
    fi

    # No brew. On the Linux guest there never will be one: /opt/homebrew does
    # not exist there and Homebrew is not installed. The conventional
    # equivalent is /usr/local/bin, and the guest's runtime PATH already
    # contains it -- verified in build_multissh_in_linux_vm.zsh, which exports
    # /workspace/opt/swift/usr/bin:/usr/local/sbin:/usr/local/bin:... -- even
    # though buildroot does not create the directory. So it is the right place
    # when we can write there.
    # 沒有 brew。Linux guest 上永遠不會有：那裡沒有 /opt/homebrew，也沒有安裝
    # Homebrew。慣用的對應位置是 /usr/local/bin，而 guest 的執行期 PATH 已經包含它
    # ——在 build_multissh_in_linux_vm.zsh 中查證過，它 export 的是
    # /workspace/opt/swift/usr/bin:/usr/local/sbin:/usr/local/bin:...——即使
    # buildroot 並未建立該目錄。因此只要我們寫得進去，那就是對的位置。
    # Windows. The first Windows install put the binary in
    # $HOME/.local/bin, which is not on PATH there, and said so -- honestly,
    # but the node upgrade around it then found an OLDER csv2 through a scoop
    # shim and reported success. 2026-08-20, defect MM.
    #
    # The convention on that machine is scoop's: the executable lives under
    # %LOCALAPPDATA%\csv2 and a shim in ~/scoop/shims points at it, with
    # scoop/shims on PATH. Installing to the place the shim ALREADY names means
    # the shell resolves to the new build without this script writing anything
    # into scoop's own directory -- creating shims is scoop's business, not
    # ours.
    #
    # Windows。第一次在 Windows 上安裝時，執行檔被放進 $HOME/.local/bin，而那裡不在 PATH 上；
    # 它誠實地說了，但外圍的節點升級腳本接著透過一個 scoop shim 找到了「更舊的」csv2，
    # 並回報成功。2026-08-20，缺陷 MM。
    # 那台機器上的慣例是 scoop 的：執行檔放在 %LOCALAPPDATA%\csv2 底下，由 ~/scoop/shims
    # 裡的一個 shim 指向它，而 scoop/shims 在 PATH 上。**裝到 shim 本來就指著的那個位置**，
    # 會讓 shell 解析到新的建置，而這支腳本完全不必往 scoop 自己的目錄裡寫東西——建立 shim
    # 是 scoop 的事，不是我們的。
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            local appdata=${LOCALAPPDATA:-$HOME/AppData/Local}
            print -r -- "${appdata//\\//}/csv2"
            return
            ;;
    esac

    if [[ $(uname -s) == Linux ]]; then
        case ":$PATH:" in
            *":/usr/local/bin:"*)
                if [[ -w /usr/local ]] || [[ -w /usr/local/bin ]] || (( EUID == 0 )); then
                    print -r -- /usr/local/bin
                    return
                fi
                ;;
        esac
    fi

    # Last resort: ~/.local/bin needs no privileges, conflicts with no package
    # manager, and is the conventional user-level location.
    # 最後手段：~/.local/bin 不需要權限、不與任何套件管理員衝突，也是慣用的
    # 使用者層級位置。
    print -r -- $HOME/.local/bin
}

DEST_DIR=$(target_dir)
# `.exe` on Windows, because the shell will not run it otherwise and the scoop
# shim names it that way. Everywhere else the extension would be noise.
# Windows 上要 `.exe`，否則 shell 不會執行它，而 scoop 的 shim 指的也是那個名字。
# 在其他平台上，那個副檔名只是雜訊。
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) DEST=$DEST_DIR/csv2.exe ;;
    *)                    DEST=$DEST_DIR/csv2 ;;
esac

# ---------------------------------------------------------------------
# Uninstall / 移除
# ---------------------------------------------------------------------
if [[ $MODE == uninstall ]]; then
    # The rc line goes even when the binary is already gone. An uninstall that
    # removes the file and leaves the PATH entry behind is the reason a later
    # `command not found` points at a directory nobody remembers adding.
    # 就算執行檔已經不在，rc 那一行也要拿掉。一個「刪了檔案卻留下 PATH 項目」的移除，
    # 正是日後某次 command not found 指向一個沒人記得加過的目錄的原因。
    for f in $(rc_candidates); do
        [[ -f $f ]] && grep -qF "$RC_BEGIN" $f 2>/dev/null || continue
        # Say what the removal costs, when it costs something. The block in a
        # login file is what makes a login bash read ~/.bashrc at all, so
        # anything else that file sets goes quiet with it -- silently, and at
        # the next login rather than now.
        # 當移除是有代價的，就把代價說出來。登入檔裡的那個區塊，正是讓「登入的 bash」
        # 去讀 ~/.bashrc 的原因；因此那個檔案設定的其他東西也會跟著失效——而且是安靜地、
        # 在下一次登入時，不是現在。
        local sources_bashrc=0
        grep -qF 'bashrc' $f 2>/dev/null && [[ $f != $HOME/.bashrc ]] && sources_bashrc=1
        if (( DRY )); then
            say "  DRY  remove the csv2 block from $f / 移除 $f 裡的 csv2 區塊"
        else
            rc_strip $f && say "removed the csv2 block from $f / 已移除 $f 裡的 csv2 區塊"
        fi
        if (( sources_bashrc )); then
            say "  that block was what made a login shell read ~/.bashrc."
            say "  If anything else in ~/.bashrc needs to survive login, put it back."
            say "  那個區塊正是讓登入 shell 去讀 ~/.bashrc 的原因。~/.bashrc 裡若還有別的東西"
            say "  需要在登入時生效，請把那一行加回去。"
        fi
    done
    if [[ ! -e $DEST ]]; then
        say "nothing at $DEST / $DEST 沒有東西"
        exit 0
    fi
    run rm -f $DEST
    (( DRY )) || say "removed $DEST / 已移除 $DEST"
    exit 0
fi

[[ -x $BIN ]] || die "no binary at $BIN -- run ./compile_csv2.zsh first / 找不到執行檔，請先執行 ./compile_csv2.zsh"

BUILT_VERSION=$($BIN --version) || die "the built binary does not run / 建好的執行檔無法執行"

say "csv2 install / 安裝"
say "  from    : $BIN ($BUILT_VERSION)"
say "  to      : $DEST"
(( DRY )) && say "  (dry run — nothing will be written / 預演，不會寫入任何東西)"
say ""

[[ -d $DEST_DIR ]] || run mkdir -p $DEST_DIR
[[ -w $DEST_DIR ]] || (( DRY )) || die "$DEST_DIR is not writable / $DEST_DIR 不可寫入"

run cp -f $BIN $DEST
run chmod 755 $DEST

# ---------------------------------------------------------------------
# Say what this is, rather than leaving it to be discovered
#
# Copying a binary into brew's bin puts it in Homebrew's directory without
# Homebrew knowing anything about it. Someone who believes `brew upgrade`
# maintains this will run an old version for a long time without noticing.
# 主動講明，而不是留給日後自行發現
# 把執行檔複製進 brew 的 bin，是放進 Homebrew 的目錄而 Homebrew 對它一無所知。
# 以為 `brew upgrade` 會維護它的人，會在不知情的狀況下用著舊版本很久。
# ---------------------------------------------------------------------
if [[ $DEST_DIR == */homebrew/bin || $DEST_DIR == /usr/local/bin || $DEST_DIR == */linuxbrew/*/bin ]]; then
    say "NOTE: this is NOT a Homebrew install / 注意：這不是 Homebrew 安裝"
    say "  brew list      will not show it / 不會列出它"
    say "  brew upgrade   will never update it / 不會更新它"
    say "  brew doctor    will report it as an unbrewed file / 會回報它是 unbrewed 檔案"
    say "  a future brew operation on that directory may remove it"
    say "  日後對該目錄的 brew 操作可能移除它"
    say "  to remove: ./install.zsh --uninstall  (brew uninstall cannot) / 移除請用本腳本，brew uninstall 無效"
    say ""
fi

# ---------------------------------------------------------------------
# Ask whether the shell can run csv2, not whether a string is in PATH.
#
# `case ":$PATH:" in *":$DEST_DIR:"*` -- what this used to test -- is the wrong
# question in both directions. On the Windows node $DEST_DIR is NOT on PATH and
# `csv2` resolves perfectly well, through a scoop shim in a different
# directory; that test would have had this script edit that machine's
# ~/.profile to fix something that was not broken. And a directory CAN be on
# PATH while the shell still runs a different csv2 out of an earlier one.
#
# 問「shell 能不能執行 csv2」，不要問「某個字串在不在 PATH 裡」。
# `case ":$PATH:" in *":$DEST_DIR:"*`——這裡原本測的東西——在兩個方向上都問錯了。Windows 節點
# 上 $DEST_DIR **不在** PATH 上，而 `csv2` 解析得好好的，靠的是另一個目錄裡的 scoop shim；
# 那個測試會讓這支腳本去改那台機器的 ~/.profile，修一個沒有壞的東西。反過來，一個目錄可以
# 在 PATH 上，而 shell 仍然執行到更前面某個目錄裡的另一支 csv2。
# ---------------------------------------------------------------------
sum_of() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" 2>/dev/null | cut -d' ' -f1 }

# Follow a shim rather than hashing it: its own bytes are not the program's.
# 遇到 shim 要跟著它走，而不是對它算雜湊：shim 自己的位元組不是那支程式的。
resolved_target() {
    local r=$1
    if [[ -f ${r%.exe}.shim ]]; then
        sed -n 's/^path *= *"\(.*\)"/\1/p' "${r%.exe}.shim" | tr '\\' '/'
    else
        print -r -- $r
    fi
}

# Does a shell started from nothing run the file we just installed?
# 一個從零開始的 shell，執行到的是不是我們剛裝上的那個檔案？
RESOLVED=""; REACH=""; TARGET=""
resolves_to_dest() {
    in_user_shell 'command -v csv2' || return 1
    RESOLVED=$PROBE_OUT; REACH=$PROBE_KIND
    TARGET=$(resolved_target $RESOLVED)
    [[ "$(sum_of "$TARGET")" == "$(sum_of "$DEST")" ]]
}

if (( DRY )); then
    say "  DRY  ask a fresh shell whether it runs $DEST, and add a PATH line if not"
    say "  DRY  問一個全新的 shell 它執行到的是不是 $DEST，不是的話補上 PATH 那一行"
    say "dry run complete / 預演結束"
    exit 0
fi

rc_written=""
if resolves_to_dest; then
    say "verified: a fresh $LOGIN_SHELL_NAME runs $TARGET, and it is the file just installed"
    say "已驗證：全新的 $LOGIN_SHELL_NAME 執行到 $TARGET，而它就是剛裝上的那個檔案"
    say "  reachable from: $REACH"
    exit 0
fi

# Nothing from nothing. Before writing anything, ask whether THIS environment
# can already run it -- on Windows the PATH that reaches the scoop shim comes
# from the Windows process environment, not from any rc file, and `env -i`
# cannot reproduce it. Editing an rc file there would change nothing and would
# still leave a block behind.
# 從零開始的那個問法沒有答案。在寫任何東西之前，先問「**這個**環境」能不能執行它——在 Windows
# 上，通往 scoop shim 的那個 PATH 來自 Windows 的行程環境而不是任何 rc 檔，`env -i` 重現不了
# 它。在那裡改 rc 檔不會有任何效果，卻仍然會留下一個區塊。
# Same FILE, not same bytes. A hash comparison here matched
# /opt/homebrew/bin/csv2 against an install into a temp prefix -- a different
# file at a different path with identical contents, because both were the same
# build -- and concluded that this shell already ran the new install, so no rc
# file was written and the temp prefix stayed unreachable. Byte equality is the
# right question for "will the shell run this program" and the wrong one for
# "is this the copy I just placed". 2026-08-25, seen here.
# 是同一個「檔案」，不是同樣的位元組。這裡用雜湊比對時，把 /opt/homebrew/bin/csv2 比中了一次
# 裝進暫存 prefix 的安裝——不同路徑的不同檔案，內容相同，因為兩者是同一次建置——於是結論是
# 「這個 shell 已經在執行新裝的那個」，沒有寫任何 rc 檔，而那個暫存 prefix 仍然叫不出來。
# 位元組相等，是「shell 會不會執行到這支程式」的正確問法，卻是「這是不是我剛放的那個複本」
# 的錯誤問法。2026-08-25 在此見到。
_inherited=$(command -v csv2 2>/dev/null) || _inherited=""
if [[ -n $_inherited ]] && [[ "$(resolved_target $_inherited)" -ef "$DEST" ]]; then
    say "installed to $DEST, and this shell runs it as \`csv2\`."
    say "已裝到 $DEST，而目前這個 shell 以 \`csv2\` 執行到的就是它。"
    say "NOTE: a $LOGIN_SHELL_NAME started from an empty environment does not find it."
    say "  Nothing was written to any rc file, because the PATH that reaches it here"
    say "  does not come from one. A script run over ssh may or may not inherit it."
    say "注意：一個以空環境啟動的 $LOGIN_SHELL_NAME 找不到它。這裡沒有寫任何 rc 檔，因為"
    say "  「在這裡通往它的那個 PATH」不是來自 rc 檔。經 ssh 執行的腳本不一定繼承得到。"
    exit 0
fi

# It is genuinely unreachable by name. Now the rc file is worth writing.
# 它是真的叫不出來。這時候才值得去寫 rc 檔。
say "a fresh $LOGIN_SHELL_NAME cannot run csv2 by name / 全新的 $LOGIN_SHELL_NAME 無法以名稱執行 csv2"
say "  login shell: $LOGIN_SHELL"
if (( ! RC )); then
    say "  --no-rc given; add this yourself / 已指定 --no-rc，請自行加上："
    say "      export PATH=\"$DEST_DIR:\$PATH\""
    $DEST --version >/dev/null || die "the installed copy does not run / 安裝的複本無法執行"
    exit 0
fi

for f in $(rc_files); do
    [[ -f $f ]] || : > $f
    rc_append $f $DEST_DIR
    say "  added the PATH line to $f / 已把 PATH 那一行加進 $f"
    rc_written="$rc_written $f"
done

# bash only: a login shell does not read .bashrc unless a login file says so.
# Debian's own ~/.profile does exactly this; without it the line above is read
# by an interactive `bash` but not by the shell a login hands you.
# 只有 bash 需要：登入 shell 不會讀 .bashrc，除非某個登入檔叫它讀。Debian 自己的 ~/.profile
# 做的就是這件事；少了它，上面那一行互動的 `bash` 讀得到，而登入時拿到的那個 shell 讀不到。
if [[ $LOGIN_SHELL_NAME == bash ]]; then
    login_file=$HOME/.profile
    [[ -f $HOME/.bash_login ]]   && login_file=$HOME/.bash_login
    [[ -f $HOME/.bash_profile ]] && login_file=$HOME/.bash_profile
    if ! grep -q 'bashrc' $login_file 2>/dev/null; then
        {
            print -r -- ""
            print -r -- "$RC_BEGIN"
            print -r -- "# a login bash does not read ~/.bashrc on its own."
            print -r -- "# 登入的 bash 自己不會去讀 ~/.bashrc。"
            print -r -- "[ -f \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\""
            print -r -- "$RC_END"
        } >> $login_file
        say "  made $login_file source ~/.bashrc / 已讓 $login_file 去 source ~/.bashrc"
    fi
fi
say "  this shell is unaffected; a new one will have it / 目前這個 shell 不受影響，新開的會有"
say ""

# And now the same question again. Having written the file is not the same as
# the file working, and only one of those is worth reporting.
# 然後把同一個問題再問一次。「寫過那個檔案」與「那個檔案有效」不是同一件事，而只有其中一件
# 值得回報。
if resolves_to_dest; then
    say "verified: a fresh $LOGIN_SHELL_NAME runs $TARGET, and it is the file just installed"
    say "已驗證：全新的 $LOGIN_SHELL_NAME 執行到 $TARGET，而它就是剛裝上的那個檔案"
    say "  reachable from: $REACH"
    exit 0
fi
if [[ -n $RESOLVED ]]; then
    die "a fresh shell runs a DIFFERENT csv2: $TARGET is not the file just installed at $DEST. Both may report the same version -- that is why this compares the file. Check PATH order. / 全新的 shell 執行到的是另一支 csv2：$TARGET 不是剛裝到 $DEST 的那個檔案。兩者可能回報相同的版本——那正是這裡比對檔案的原因。請檢查 PATH 順序。"
fi
die "wrote the PATH line to$rc_written and a fresh $LOGIN_SHELL_NAME still cannot run csv2 / 已把 PATH 那一行寫進$rc_written，而全新的 $LOGIN_SHELL_NAME 仍然無法執行 csv2"

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

while (( $# )); do
    case $1 in
        --uninstall) MODE=uninstall ;;
        --dry-run)   DRY=1 ;;
        --prefix)    shift; [[ $# -gt 0 ]] || { print -u2 -- "--prefix needs a directory / --prefix 需要一個目錄"; exit 2 }; PREFIX=$1 ;;
        -h|--help)   sed -n '3,20p' ${0:A}; exit 0 ;;
        *) print -u2 -- "unknown option: $1 / 未知選項：$1"; exit 2 ;;
    esac
    shift
done

say()  { print -r -- "$1" }
die()  { print -u2 -- "install.zsh: $1"; exit 1 }
run()  { if (( DRY )); then say "  DRY  $*"; else "$@" || die "failed: $*"; fi }

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
# A binary in a directory that is not on PATH gives "command not found",
# which reads as "the install failed" when in fact it succeeded -- and the
# user then goes looking in the wrong place.
# 裝到不在 PATH 的目錄會得到 command not found，那看起來像「安裝失敗」，實際上
# 安裝是成功的——於是使用者會去查錯的方向。
# ---------------------------------------------------------------------
on_path=0
case ":$PATH:" in *":$DEST_DIR:"*) on_path=1 ;; esac
if (( ! on_path )); then
    say "WARNING: $DEST_DIR is not on your PATH / 警告：$DEST_DIR 不在你的 PATH 上"
    say "  csv2 is installed but the shell will not find it."
    say "  csv2 已安裝，但 shell 找不到它。"
    say "  add to ~/.zshrc:  export PATH=\"$DEST_DIR:\$PATH\""
    say ""
fi

if (( DRY )); then
    say "dry run complete / 預演結束"
    exit 0
fi

# ---------------------------------------------------------------------
# Verify by RUNNING it in a fresh shell, not by checking the file exists.
#
# Whether the file landed proves nothing about which csv2 will actually run:
# PATH order decides that, silently, with no diagnostic. An installer that
# verifies the wrong thing is worse than one that verifies nothing, because it
# reports success.
# 以「在全新 shell 中執行」來驗證，而非檢查檔案存在。
# 檔案有沒有放進去，對「實際會執行到哪一支 csv2」毫無證明力：那由 PATH 順序決定，
# 靜默且沒有任何診斷。一個驗證了錯誤對象的安裝程式，比完全不驗證更糟，因為它會回報成功。
# ---------------------------------------------------------------------
if (( on_path )); then
    RESOLVED=$(zsh -lc 'command -v csv2' 2>/dev/null) || RESOLVED=""
    FOUND_VERSION=$(zsh -lc 'csv2 --version' 2>/dev/null) || FOUND_VERSION=""
    if [[ -z $FOUND_VERSION ]]; then
        die "installed to $DEST but a fresh shell cannot run csv2 / 已裝到 $DEST，但全新的 shell 無法執行 csv2"
    fi
    if [[ $FOUND_VERSION != $BUILT_VERSION ]]; then
        die "a fresh shell runs a DIFFERENT csv2: $RESOLVED reports '$FOUND_VERSION', we installed '$BUILT_VERSION'. Check PATH order. / 全新的 shell 執行到的是另一支 csv2：$RESOLVED 回報 '$FOUND_VERSION'，我們裝的是 '$BUILT_VERSION'。請檢查 PATH 順序。"
    fi
    say "verified: a fresh shell runs $RESOLVED -> $FOUND_VERSION"
    say "已驗證：全新的 shell 執行到 $RESOLVED -> $FOUND_VERSION"
else
    # Cannot verify by name when the directory is not on PATH; verify the copy
    # runs at all, and say plainly that this is the weaker check.
    # 目錄不在 PATH 上時無法以名稱驗證；改為驗證該複本至少能執行，並明說這是較弱的檢查。
    $DEST --version >/dev/null || die "the installed copy does not run / 安裝的複本無法執行"
    say "installed, but NOT verified by name: $DEST_DIR is not on PATH"
    say "已安裝，但未以名稱驗證：$DEST_DIR 不在 PATH 上"
fi

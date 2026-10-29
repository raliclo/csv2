#!/usr/bin/env zsh
# =====================================================================
# install.zsh — put the built csv2 where the shell can find it
# install.zsh — 把建好的 csv2 放到 shell 找得到的地方
#
# Usage / 用法:
#   ./install.zsh              install / 安裝
#   ./install.zsh --uninstall  remove it again / 移除
#   ./install.zsh --dry-run    say what would happen, touch nothing / 只說會做什麼，不動任何東西
#   ./install.zsh --prefix DIR install into DIR/bin / 裝到 DIR/bin
#   ./install.zsh --dir DIR    install into DIR exactly / 就裝到 DIR 這個目錄
#   ./install.zsh --no-rc     do not touch any shell rc file / 不要改動任何 shell rc 檔
#
# THIS IS NOT A HOMEBREW INSTALL. Read the warning it prints.
# 這不是 Homebrew 安裝。請讀它印出的警告。
#
# Not covered here: the guest. csv2 is deliberately NOT in the LinuxCS rootfs
# (plan.md, "目前不進 rootfs"): the scripts that need it run on the macOS host,
# and the guest's fixed 128 MiB rootfs is not spent on a tool nothing there calls.
# 不涵蓋 guest。csv2 刻意不放進 LinuxCS rootfs（plan.md「目前不進 rootfs」）：需要它的腳本都在
# macOS host 上，而 guest 固定 128 MiB 的 rootfs 不該花在一個裡面沒有東西會呼叫的工具上。
# The guest builds csv2 from source for testing and discards it with the
# per-run image clone; installing there is phase 7, deferred on purpose.
# guest 為了測試而從原始碼建置 csv2，並隨每次執行的 image 複本一起丟棄；在那裡安裝屬於
# 第 7 階段，是刻意暫緩。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail

ROOT=${0:A:h}
# The SOURCE needs the same `.exe` the destination has. On Windows `release/`
# can hold BOTH `csv2.exe` from the current build and a stale `csv2` from an
# earlier one, so a source of `csv2` installs the wrong file and the
# verification checks what was copied. The post-install check compares FILES,
# not versions, because both would report the same version. NN.
#
# **來源**需要與目的地相同的 `.exe`。在 Windows 上，`release/` 可能**同時有**這次建置的
# `csv2.exe` 與先前留下的過期 `csv2`，來源若寫成 `csv2`，裝上去的就是錯的檔案，而驗證檢查的
# 也是被複製過去的那一份。安裝後的檢查比對的是**檔案**而不是版本，因為兩者會回報同一個版本。NN。
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) BIN=$ROOT/release/csv2.exe ;;
    *)                    BIN=$ROOT/release/csv2 ;;
esac
DRY=0
MODE=install
# Two ways to name a destination, because "prefix" already means something.
# --prefix DIR installs into DIR/bin, which is what --prefix means everywhere
# else and what target_dir() does with `brew --prefix`. --dir DIR means use
# exactly this directory.
# 兩種指定目的地的方式，因為「prefix」這個詞早就有意思了。--prefix DIR 會裝進 DIR/bin，
# 那是 --prefix 在其他每個地方的意思，也是 target_dir() 處理 `brew --prefix` 的方式。
# --dir DIR 則是「就用這個目錄」。
PREFIX=""
DEST_DIR=""
RC=1

while (( $# )); do
    case $1 in
        --uninstall) MODE=uninstall ;;
        --dry-run)   DRY=1 ;;
        --no-rc)     RC=0 ;;
        --prefix)    shift; [[ $# -gt 0 ]] || { print -u2 -- "--prefix needs a directory / --prefix 需要一個目錄"; exit 2 }; PREFIX=$1 ;;
        --dir)       shift; [[ $# -gt 0 ]] || { print -u2 -- "--dir needs a directory / --dir 需要一個目錄"; exit 2 }; DEST_DIR=$1 ;;
        -h|--help)   sed -n '3,21p' ${0:A}; exit 0 ;;
        *) print -r -u2 -- "unknown option: $1 / 未知選項：$1"; exit 2 ;;
    esac
    shift
done

# `-r` on every print that carries a value from outside. Without it zsh reads
# backslashes as escapes, and a Windows path is nothing but backslashes:
# `C:\Users\...\apps\csv2` prints `C:` NUL `sers...` BEL `pps`, and `\c`
# stops the output there, before a refusal names its ways forward. QL.
# 每一個帶著外來值的 print 都要 `-r`。少了它，zsh 會把反斜線當成跳脫，而一個 Windows 路徑全是反斜線：
# `C:\Users\...\apps\csv2` 會印成 `C:` NUL `sers...` BEL `pps`，而 `\c` 讓輸出停在那裡——拒絕訊息
# 還沒說出可走的路就斷了。QL。
say()  { print -r -- "$1" }
die()  { print -r -u2 -- "install.zsh: $1"; exit 1 }
run()  { if (( DRY )); then say "  DRY  $*"; else "$@" || die "failed: $*"; fi }

# ---------------------------------------------------------------------
# Which shell, and therefore which file
#
# ASK the account, never assume the one running this script. install.zsh is
# `#!/usr/bin/env zsh`, so the shell it is running in is always zsh -- and that
# says nothing about the shell the person gets when they open a terminal. An
# account whose login shell is bash can still have a `.zshrc`; writing the
# export for the shell this script runs in puts the right line into a file
# nothing reads, and then reports success.
#
# 問這個帳號，絕不假設「執行本腳本的那個 shell」。install.zsh 是 `#!/usr/bin/env zsh`，
# 所以它執行時所在的 shell 永遠是 zsh——而那對「這個人開終端機時拿到的是哪個 shell」
# 毫無說明力。登入 shell 是 bash 的帳號，家目錄裡照樣可能有 `.zshrc`；按本腳本所在的 shell
# 寫 export，會把正確的那一行放進一個沒有東西會讀的檔案，然後回報成功。
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

# Which file that shell reads.
#
# zsh gets ~/.zshenv, the one file every zsh invocation reads. Any other shell
# gets ~/.profile, which a login shell reads; the reachability report then says
# "login shells only", which is true.
#
# 那個 shell 會讀哪個檔案。
#
# zsh 拿到 ~/.zshenv——每一種 zsh 呼叫都會讀的那一個檔案。其他 shell 拿到 ~/.profile，由登入
# shell 讀取；可達性報告接著會說「只有登入 shell」，而那是實話。
rc_files() {
    case $LOGIN_SHELL_NAME in
        # .zshenv, not .zshrc. zsh reads .zshrc only for INTERACTIVE shells,
        # and a script run over multissh is a non-interactive, non-login shell
        # that reads .zshenv and nothing else. .zshrc would fix a person's
        # terminal and leave the script failing, while this installer reported
        # success. IW.
        # 是 .zshenv 而不是 .zshrc。zsh 只有在**互動** shell 才讀 .zshrc，而經 multissh 執行的腳本
        # 是一個非互動、非登入的 shell，只讀 .zshenv。寫進 .zshrc 會修好某個人的終端機，卻讓那支
        # 腳本繼續失敗，同時這支安裝程式回報成功。IW。
        zsh)  print -r -- $HOME/.zshenv ;;
        # No bash branch. bash has no .zshenv, and BASH_ENV, the equivalent, is
        # not set by default. A bash account falls to `*)` and gets ~/.profile,
        # which a bash LOGIN shell reads. zsh is the one shell where a single
        # file is read by EVERY invocation, non-interactive and non-login
        # included, and that is the property this tree needs. IW.
        # 沒有 bash 分支。bash 沒有 .zshenv，對應的 BASH_ENV 預設也沒有設定。bash 帳號會落到
        # `*)`、拿到 ~/.profile，由 bash 的**登入** shell 讀取。zsh 是唯一一個「單一檔案會被**每一種**
        # 呼叫讀到」的 shell，非互動與非登入都包含在內，而那正是這棵樹需要的性質。IW。
        *)    print -r -- $HOME/.profile ;;
    esac
}

# Every file this script may ever have written a block into -- which is not
# the same list as the one it writes to TODAY. Uninstall has to ask the wider
# question: an install can leave blocks in more than one file (a bash install
# also writes a login file), and an uninstall that only consulted rc_files()
# would leave one behind, still carrying a marker that says csv2 put it there.
# 這支腳本「曾經可能」寫過區塊的每一個檔案——而那不等於它「今天」會寫的那一份清單。
# 移除必須問比較寬的那個問題：一次安裝可能在不只一個檔案裡留下區塊（bash 的安裝還會寫一個
# 登入檔），只看 rc_files() 的移除會留下其中一個，且上面還標著「csv2 放的」。
rc_candidates() {
    print -l -- $HOME/.zshenv $HOME/.zshrc $HOME/.zprofile $HOME/.bashrc \
                $HOME/.profile $HOME/.bash_profile $HOME/.bash_login
}

RC_BEGIN='# >>> csv2 install.zsh >>>'
RC_END='# <<< csv2 install.zsh <<<'

# Remove any block this script previously wrote, so a second install does not
# leave two.
# 移除本腳本先前寫過的區塊，讓第二次安裝不會留下兩份。
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

# Run a command the way the person's own shell would. `zsh -lc` alone is login
# but NOT interactive, and zsh reads .zshrc only when interactive, so it would
# miss a line there; `-lic` is the combination that reads every rc file.
# 以「這個人自己的 shell」的方式執行。單用 `zsh -lc` 是登入但**不是**互動，而 zsh 只有在互動時
# 才讀 .zshrc，因此會漏掉那裡的一行；`-lic` 才是會讀到每一個 rc 檔的組合。
# Non-interactive FIRST, and remember which one answered.
#
# The three cases are not equivalent and the difference is the whole point:
# `-c` is what a script reached over ssh gets, `-lc` a login shell, `-lic` a
# terminal. A directory reachable only from the last of those satisfies a
# person typing `csv2` and still fails a script run over ssh.
# 先問非互動的那一個，並記住是哪一個回答的。
# 三種情況並不等價，而那個差別正是重點：`-c` 是「經 ssh 執行的腳本」拿到的，`-lc` 是登入
# shell，`-lic` 是終端機。一個只有在最後一種情況下才找得到的目錄，滿足了「有人打 csv2」，
# 卻仍然讓經 ssh 執行的腳本失敗。
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
# PATH I already have", answers yes, and reports it as "every shell finds it"
# -- even when the csv2 it found is an unrelated one elsewhere on that PATH.
# The question is what a shell started from nothing can see, so start one from
# nothing.
#
# 用一個**全新的**環境，不是現在這個。
# `zsh -c` 不會重設 PATH——它繼承呼叫者匯出的 PATH。因此用單純的 `$LOGIN_SHELL -c` 去探測，
# 問的是「csv2 在現有的 PATH 上嗎」，答案是「在」，然後被回報成「每一種 shell 都找得到」——
# 即使它找到的是那個 PATH 上別處一支不相干的 csv2。要問的是「一個從零開始的 shell 看得到
# 什麼」，那就從零開始一個。
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
        # A non-login shell finding it does NOT imply every shell finds THIS
        # one. The ladder below reads as "least-equipped environment first, so
        # anything richer must also succeed" -- true if a login shell only ADDS
        # to PATH. On macOS it does not: `path_helper`, run from /etc/zprofile
        # for login shells, REORDERS it. README.md explains that mechanism.
        #
        # So a second csv2 earlier in the login PATH -- which is what you have
        # the moment you install twice, which is what --prefix and --dir are
        # for -- would make `reachable from: every shell` true about
        # reachability and false about identity, while the line beside it
        # promises identity: "and it is the file just installed". Round 96, OK.
        #
        # 一個非登入 shell 找得到它，**不**蘊涵每一種 shell 都找得到**這一個**。底下那個階梯的讀法是
        # 「先問配備最少的環境，因此更豐富的環境必然也成功」——那在「登入 shell 只會**增加** PATH」時
        # 成立。而 macOS 上不成立：`path_helper` 由 /etc/zprofile 在登入 shell 執行，它會**重排** PATH。
        # README.md 解釋了這個機制。
        #
        # 於是一個排在登入 PATH 更前面的第二個 csv2——那正是「裝第二次」時會有的東西，而
        # --prefix 與 --dir 存在的理由就是讓人裝第二次——會讓 `reachable from: every shell` 對
        # **可達性**為真、對**同一性**為假；而它旁邊那一行承諾的正是同一性：「就是剛剛裝的那個檔案」。
        # 第 96 回合，OK。
        local login_out
        if login_out=$($E $LOGIN_SHELL -lc "$1" 2>/dev/null) && [[ -n $login_out ]] \
           && [[ $login_out != $out ]]; then
            PROBE_KIND="non-login shells; a LOGIN shell finds $login_out first / 非登入 shell；而**登入** shell 會先找到 $login_out"
        else
            PROBE_KIND="every shell, scripts over ssh included / 每一種 shell，包含經 ssh 的腳本"
        fi
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
# Both at once is a refusal, not a precedence rule. They are two ways to name
# one destination, and picking a winner silently would put the binary somewhere
# the caller did not ask for -- while telling them it succeeded.
# 同時給兩個是拒絕，不是「誰優先」的規則。它們是指定「同一個目的地」的兩種方式，而靜默地挑一個
# 贏家，會把執行檔放到呼叫端沒有要求的地方——同時告訴他成功了。
if [[ -n $PREFIX && -n $DEST_DIR ]]; then
    print -u2 -- "--prefix and --dir both name the destination; give one. --prefix DIR installs into DIR/bin, --dir DIR into DIR exactly"
    print -u2 -- "--prefix 與 --dir 都在指定目的地；請只給一個。--prefix DIR 裝進 DIR/bin，--dir DIR 就裝進 DIR"
    exit 2
fi

target_dir() {
    # --dir is taken as given; --prefix gets /bin, exactly as the brew branch
    # below does with the prefix IT is handed. Taking --prefix as given would
    # make `--prefix /usr/local` write /usr/local/csv2 -- a file on no PATH --
    # and then add an rc PATH line to reach it, turning a misreading into
    # configuration. KV.
    # --dir 照給的用；--prefix 會加上 /bin，與底下 brew 那一支對它拿到的 prefix 所做的完全相同。
    # 若 --prefix 也照給的用，`--prefix /usr/local` 會寫出 /usr/local/csv2——一個不在任何 PATH 上
    # 的檔案——再在 rc 檔裡加一行 PATH 去搆到它，把一個誤讀固化成設定。KV。
    if [[ -n $DEST_DIR ]]; then
        print -r -- $DEST_DIR
        return
    fi
    if [[ -n $PREFIX ]]; then
        print -r -- $PREFIX/bin
        return
    fi
    local p
    if p=$(brew --prefix 2>/dev/null) && [[ -d $p/bin ]]; then
        # Refuse when brew already manages csv2. QL is the same refusal on the
        # scoop side, and here it matters more, because the destination IS
        # brew's own bin directory. `cp -f` replaces
        # brew's symlink with a plain file while brew's database still believes
        # it owns that path, and the NOTE printed alongside -- "brew list will
        # not show it", "brew upgrade will never update it" -- is false line by
        # line in exactly this situation, having been written for the case
        # where brew does not manage csv2.
        #
        # `brew list --formula` and NOT `brew --prefix csv2`: the latter returns
        # 0 and a plausible path for a formula that is merely KNOWN, so using it
        # would refuse on every Mac with Homebrew, csv2 installed or not. It
        # answers "where would this go", not "is it installed". QR.
        #
        # brew 已經管理著 csv2 時要拒絕。QL 是 scoop 那一側的同一道拒絕，而這裡更要緊，
        # 因為目的地**就是 brew 自己的 bin 目錄**。`cp -f` 會把 brew 的 symlink 換成
        # 一個普通檔案，而 brew 的資料庫仍認為它擁有那條路徑；同一畫面上那段 NOTE（「brew list
        # 不會列出它」「brew upgrade 不會更新它」）在這個情境下逐行皆假——它是為「brew 沒有管理
        # csv2」寫的。
        #
        # 用 `brew list --formula` 而**不是** `brew --prefix csv2`：後者對一個「只是已知」的 formula
        # 同樣回傳 0 與一個看起來合理的路徑，拿它當偵測會在每一台裝了 Homebrew 的 Mac 上誤擋，
        # 不論有沒有裝過 csv2。它回答的是「若安裝會在哪裡」，不是「它裝了沒有」。QR。
        if command -v brew >/dev/null 2>&1 && brew list --formula csv2 >/dev/null 2>&1; then
            [[ $MODE == uninstall ]] && die "Homebrew manages csv2 here ($p/bin/csv2). Remove it with \`brew uninstall csv2\`; this script did not put it there. / Homebrew 在這裡管理著 csv2（$p/bin/csv2）。請用 \`brew uninstall csv2\` 移除；它不是這支腳本放的。"
            die "Homebrew manages csv2 here ($p/bin/csv2). Writing there replaces brew's symlink with a plain file while brew still believes it owns that path. Use \`brew upgrade csv2\` for a release, or --dir DIR to place a development build somewhere brew does not own. / Homebrew 在這裡管理著 csv2（$p/bin/csv2）。寫進去會把 brew 的 symlink 換成一個普通檔案，而 brew 仍認為它擁有那條路徑。要裝正式版請用 \`brew upgrade csv2\`；要放一份開發建置，請用 --dir DIR 指到一個不屬於 brew 的地方。"
        fi
        print -r -- $p/bin
        return
    fi

    # No brew. On the Linux guest there never will be one: /opt/homebrew does
    # not exist there and Homebrew is not installed. The conventional
    # equivalent is /usr/local/bin, and the guest's runtime PATH already
    # contains it (build_multissh_in_linux_vm.zsh exports
    # /workspace/opt/swift/usr/bin:/usr/local/sbin:/usr/local/bin:...) even
    # though buildroot does not create the directory. So the Linux branch below
    # uses it when it is writable.
    # 沒有 brew。Linux guest 上永遠不會有：那裡沒有 /opt/homebrew，也沒有安裝
    # Homebrew。慣用的對應位置是 /usr/local/bin，而 guest 的執行期 PATH 已經包含它
    # （build_multissh_in_linux_vm.zsh export 的是
    # /workspace/opt/swift/usr/bin:/usr/local/sbin:/usr/local/bin:...），即使
    # buildroot 並未建立該目錄。因此底下的 Linux 分支在寫得進去時就用它。
    # Windows. The convention there is scoop's: the executable lives under
    # %LOCALAPPDATA%\csv2 and a shim in ~/scoop/shims points at it, with
    # scoop/shims on PATH. Installing to the place the shim ALREADY names means
    # the shell resolves to the new build without this script writing anything
    # into scoop's own directory -- creating shims is scoop's business.
    #
    # Windows。那裡的慣例是 scoop 的：執行檔放在 %LOCALAPPDATA%\csv2 底下，由 ~/scoop/shims
    # 裡的一個 shim 指向它，而 scoop/shims 在 PATH 上。**裝到 shim 本來就指著的那個位置**，
    # 會讓 shell 解析到新的建置，而這支腳本完全不必往 scoop 自己的目錄裡寫東西——建立 shim
    # 是 scoop 的事。
    # ASK the shim where it points; do not assume a directory. Which directory a
    # shim names is a fact about one machine, and the macOS branch above does
    # not assume the equivalent either: it runs `brew --prefix`.
    #
    # **問** shim 它指向哪裡，不要假設目錄。shim 指向哪個目錄，是關於**某一台機器**的事實；
    # 上面的 macOS 分支同樣沒有做等價的假設，而是去跑 `brew --prefix`。
    #
    # The shim is the authoritative answer to the only question that matters
    # here: where will the shell find csv2 after this install. Writing anywhere
    # else gives an install that succeeds while the shell goes on resolving an
    # older binary through a shim nobody looked at. MM.
    # shim 是「這次安裝之後，shell 會在哪裡找到 csv2」這個唯一要緊的問題的權威答案。裝到別的地方，
    # 會得到一次成功的安裝，而 shell 仍然透過一個沒有人去看的 shim 解析到更舊的執行檔。MM。
    #
    # A csv2 that scoop itself manages is refused first, below. A fake `scoop`
    # early on PATH produces that condition for testing.
    # 「由 scoop 自己管理的 csv2」會先在底下被拒絕。把一個假的 `scoop` 放在 PATH 前面，就能為測試
    # 製造出那個條件。
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            setopt local_options extended_glob
            # If SCOOP manages csv2, this script must not write into its app
            # directory: scoop verifies hashes there and an upgrade would
            # overwrite whatever was dropped in. Refuse and name the two ways
            # forward, rather than producing an install that works until the
            # next `scoop update`.
            #
            # 如果 csv2 是由 **scoop** 管理的，這支腳本不可以寫進它的 app 目錄：scoop 會在那裡
            # 驗證 hash，而一次升級會覆蓋掉任何被放進去的東西。拒絕，並說出兩條可走的路——而不是
            # 產生一個「能用到下一次 `scoop update` 為止」的安裝。
            #
            # The exit status is USELESS here: `scoop prefix csv2` answers
            # "Could not find app path for 'csv2'." and still exits 0. So the
            # discriminator is the
            # OUTPUT -- it must look like a Windows path AND name a directory
            # that exists -- which is the same shape as reading a version out
            # of `--version`: match something self-validating, never split and
            # hope.
            #
            # 這裡的退出碼**沒有用**：`scoop prefix csv2` 會回答「Could not find app path for
            # 'csv2'.」而且仍然以 0 結束。所以判別式看的是
            # **輸出**——它必須長得像一個 Windows 路徑，而且指向一個存在的目錄——那與「從
            # `--version` 讀出版本號」是同一個形狀：比對一個能自我驗證的東西，不要切了就用。
            if (( $+commands[scoop] )); then
                local _sp
                _sp=$(scoop prefix csv2 2>/dev/null | tr -d '\r' | tail -1)
                if [[ $_sp == [A-Za-z]:[\\/]* ]]; then
                    local _spp
                    _spp=$(cygpath -u -- "$_sp" 2>/dev/null || print -r -- "${_sp//\\//}")
                    if [[ -d $_spp ]]; then
                        # Uninstall is refused too, with its own way forward: the
                        # file here is scoop's, and removing it behind scoop's back
                        # leaves scoop listing an app whose shim runs nothing.
                        # 移除也一樣拒絕，但給它自己的出路：這裡的檔案是 scoop 的，繞過 scoop 刪掉它，
                        # scoop 會繼續列著一個 shim 什麼都執行不了的 app。
                        [[ $MODE == uninstall ]] && die "scoop manages csv2 here ($_sp). Remove it with \`scoop uninstall csv2\`; this script did not put it there. / scoop 在這裡管理著 csv2（$_sp）。請用 \`scoop uninstall csv2\` 移除；它不是這支腳本放的。"
                        die "scoop manages csv2 here ($_sp). Writing into a scoop app directory fights its hash checks and the next \`scoop update csv2\` would overwrite this build. Use \`scoop update csv2\` for a release, or --dir DIR to place a development build somewhere scoop does not own. / scoop 在這裡管理著 csv2（$_sp）。寫進 scoop 的 app 目錄會與它的 hash 驗證相衝，而下一次 \`scoop update csv2\` 會覆蓋掉這次建置。要裝正式版請用 \`scoop update csv2\`；要放一份開發建置，請用 --dir DIR 指到一個不屬於 scoop 的地方。"
                    fi
                fi
            fi
            local shim shim_file line win
            shim=$(command -v csv2 2>/dev/null)
            [[ -n $shim ]] && shim_file=${shim:h}/csv2.shim
            if [[ -n $shim_file && -r $shim_file ]]; then
                # A `key = "value"` line. Matched as a whole rather than cut at
                # a delimiter: if it does not look like a Windows path, nothing
                # is extracted, and the fallback below runs. mistakes entry 6.
                # 一行 `key = "value"`。整段比對而不是在分隔符處切開：如果它看起來不像一個
                # Windows 路徑，就什麼都不會被取出，底下的 fallback 會接手。mistakes 第 6 條。
                while IFS= read -r line; do
                    [[ $line == (#b)*'"'([^\"]##)'"'* ]] || continue
                    [[ $match[1] == [A-Za-z]:[\\/]* ]] || continue
                    win=$match[1]
                    break
                done < $shim_file
            fi
            if [[ -n $win ]]; then
                local posix
                if posix=$(cygpath -u -- "$win" 2>/dev/null) && [[ -n $posix ]]; then
                    print -r -- "${posix:h}"
                else
                    print -r -- "${${win//\\//}:h}"
                fi
                return
            fi
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

# `|| exit`, because target_dir runs in a command substitution: a `die` inside
# it ends that SUBSHELL, not this script. Without this, a refusal prints its
# message and the script goes on with an empty DEST_DIR, planning
# `cp ... /csv2.exe`. The emptiness check behind it is for any branch that
# prints nothing: an install with no destination is never right. QL.
# `|| exit`，因為 target_dir 是在命令替換裡跑的：它裡面的 `die` 結束的是那個**子 shell**，不是這支
# 腳本。少了它，拒絕印完訊息後，腳本會帶著空的 DEST_DIR 繼續，規劃出 `cp ... /csv2.exe`。後面那道
# 「是否為空」的檢查，是給任何什麼都沒印的分支：一次沒有目的地的安裝，絕不會是對的。QL。
DEST_DIR=$(target_dir) || exit $?
[[ -n $DEST_DIR ]] || die "no destination directory was determined; refusing to install to /csv2 / 沒有決定出目的地目錄；拒絕安裝到 /csv2"
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
BUILT_VERSION=${BUILT_VERSION%$'\r'}

say "csv2 install / 安裝"
say "  from    : $BIN ($BUILT_VERSION)"
say "  to      : $DEST"
# What is already there, asked by RUNNING it. Otherwise the gap between an
# installed copy and the tree shows only to someone who compares
# `csv2 --version` against HEAD (todo.md, "Nothing keeps the installed copy
# current"); this is the moment somebody is looking. A copy that will not RUN
# is reported as that, not as absent: a dynamically linked copy whose Swift
# runtime is gone prints nothing and exits 127, and "nothing installed" would
# be the wrong thing to tell its owner. RC.
# 那裡已經有的是什麼，靠**執行它**問出來。否則「已安裝的那一份」與「這棵樹」之間的落差，只會對
# 主動去比對 `csv2 --version` 與 HEAD 的人現身（todo.md，「已安裝的那一份沒有東西讓它跟上」）；
# 而這裡正是有人在看的時刻。一份**跑不起來**的複本要照實說它跑不起來，而不是說它不存在：一份動態
# 連結、Swift runtime 已被移除的複本什麼都不印、以 127 結束，對它的主人說「這裡沒有安裝任何東西」
# 會是錯的。RC。
if [[ -e $DEST ]]; then
    if OLD_VERSION=$($DEST --version 2>/dev/null) && [[ -n $OLD_VERSION ]]; then
        OLD_VERSION=${OLD_VERSION%$'\r'}
        if [[ $OLD_VERSION == "$BUILT_VERSION" ]]; then
            say "  replaces: $OLD_VERSION (the same build / 同一個建置)"
        else
            say "  replaces: $OLD_VERSION"
        fi
    else
        say "  replaces: a csv2 that does not run (--version gave nothing) / 一份跑不起來的 csv2（--version 沒有任何輸出）"
    fi
else
    say "  replaces: nothing; no csv2 at that path yet / 沒有；那個路徑上還沒有 csv2"
fi
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
#
# /usr/local/bin is Homebrew's only where brew SAYS its prefix is /usr/local
# (Intel macOS). On a Linux with no brew, and on Apple silicon where the prefix
# is /opt/homebrew, it is an ordinary directory, and the note would warn about
# a package manager that is not there. So that case asks brew; the two names
# that only Homebrew uses still answer for themselves. RF.
# /usr/local/bin 只有在 brew **自己說**它的 prefix 是 /usr/local 時（Intel macOS）才是 Homebrew 的。
# 在一台沒有 brew 的 Linux、以及 prefix 是 /opt/homebrew 的 Apple silicon 上，它只是普通目錄，這段
# 說明會對一個不存在的套件管理員發出警告。所以那個情況去問 brew；只有 Homebrew 會用的那兩個名字，
# 仍然自己就說明了自己。RF。
_brew_bin=""
if command -v brew >/dev/null 2>&1; then
    _brew_bin=$(brew --prefix 2>/dev/null) && _brew_bin=$_brew_bin/bin || _brew_bin=""
fi
if [[ $DEST_DIR == */homebrew/bin || $DEST_DIR == */linuxbrew/*/bin ||
      ( -n $_brew_bin && $DEST_DIR == $_brew_bin ) ]]; then
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
# `case ":$PATH:" in *":$DEST_DIR:"*` is the wrong question in both
# directions. On Windows $DEST_DIR is NOT on PATH and `csv2` resolves through
# a scoop shim in a different directory, so that test would edit ~/.profile to
# fix something that is not broken. And a directory CAN be on PATH while the
# shell still runs a different csv2 out of an earlier one.
#
# 問「shell 能不能執行 csv2」，不要問「某個字串在不在 PATH 裡」。
# `case ":$PATH:" in *":$DEST_DIR:"*` 在兩個方向上都問錯了。Windows 上 $DEST_DIR **不在** PATH 上，
# 而 `csv2` 透過另一個目錄裡的 scoop shim 解析得好好的，那個測試會去改 ~/.profile，修一個沒有壞的
# 東西。反過來，一個目錄可以在 PATH 上，而 shell 仍然執行到更前面某個目錄裡的另一支 csv2。
# ---------------------------------------------------------------------
# No checksum helper here, and none should be added back. `shasum` is a Perl
# script on macOS, and this project does not depend on Perl (see AGENTS.md);
# the aarch64 guest has neither perl nor python. And a fallback written as
# `shasum ... | cut ... || sha256sum ...` cannot work: the pipeline's status is
# `cut`'s, 0 whether or not `shasum` exists, so the `||` half is unreachable
# and the result is an empty string with nothing said. Files are compared with
# `-ef` below instead.
#
# 這裡沒有校驗和輔助函式，也不要加回來。`shasum` 在 macOS 上是一支 Perl 腳本，而本專案不依賴
# Perl（見 AGENTS.md）；aarch64 guest 上既沒有 perl 也沒有 python。而寫成
# `shasum ... | cut ... || sha256sum ...` 的 fallback 不會運作：管線的退出碼是 `cut` 的，不論
# `shasum` 在不在都是 0，因此 `||` 那一半到不了，結果是一個空字串而且什麼都不說。底下改以 `-ef`
# 比對檔案。

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

# Does a shell started from nothing run the file just installed?
# 一個從零開始的 shell，執行到的是不是剛裝上的那個檔案？
RESOLVED=""; REACH=""; TARGET=""
resolves_to_dest() {
    in_user_shell 'command -v csv2' || return 1
    RESOLVED=$PROBE_OUT; REACH=$PROBE_KIND
    TARGET=$(resolved_target $RESOLVED)
    # `-ef`, not a hash. Two builds of the same commit have identical bytes at
    # different paths, and this question is "is the shell running THE FILE just
    # placed", not "is it running something that looks like it". The check on
    # `_inherited` below makes the same distinction. KW.
    # 用 `-ef`，不是雜湊。同一個 commit 的兩份建置在不同路徑上有相同的位元組，而這裡要問的是
    # 「這個 shell 執行到的是不是剛放下的**那個檔案**」，不是「它執行到的東西看起來像不像」。
    # 底下對 `_inherited` 的檢查做的是同一個區分。KW。
    [[ -n $TARGET && "$TARGET" -ef "$DEST" ]]
}

if (( DRY )); then
    if (( RC )); then
        say "  DRY  ask a fresh shell whether it runs $DEST, and add a PATH line if not"
        say "  DRY  問一個全新的 shell 它執行到的是不是 $DEST，不是的話補上 PATH 那一行"
    else
        say "  DRY  ask a fresh shell whether it runs $DEST; do not change shell rc files"
        say "  DRY  問一個全新的 shell 它執行到的是不是 $DEST；不修改 shell rc 檔"
    fi
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
# Same FILE, not same bytes. A hash comparison would match an older install of
# the same build elsewhere on PATH, conclude this shell already runs the new
# one, write no rc file, and leave the new location unreachable. Byte equality
# answers "will the shell run this program", not "is this the copy just
# placed".
# 是同一個「檔案」，不是同樣的位元組。用雜湊比對，會把 PATH 上別處同一次建置的舊安裝比中，
# 斷定「這個 shell 已經在執行新裝的那個」，不寫任何 rc 檔，而新的位置仍然叫不出來。位元組相等
# 回答的是「shell 會不會執行到這支程式」，不是「這是不是剛放的那個複本」。
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

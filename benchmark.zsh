#!/usr/bin/env zsh
# =====================================================================
#  benchmark.zsh — measure csv2 on YOUR machine
#  benchmark.zsh — 在**你自己的機器上**量測 csv2
#
#  The numbers in README.md were taken on four specific machines. This is how
#  you get your own, and the only honest way to compare against anything.
#  README.md 裡的數字是在四台特定機器上量到的。這支腳本讓你得到你自己的——
#  而那是與任何數字比較時唯一誠實的方式。
#
#    ./benchmark.zsh            read/write timings          about 1 minute
#    ./benchmark.zsh --full     adds parallel search + RSS  about 25 minutes,
#                                                           2.6 GB of scratch
#    ./benchmark.zsh --small    a 20,000-record corpus, for a slow machine
#
#  It is a wrapper. The work is done by verifications/measure.zsh and
#  verifications/measure_parallel_rss.zsh, which is where the method lives:
#  best-of-N per row, and a refusal if a row did not take the code path it is
#  named after.
#  這是一層包裝。實際工作由 verifications/measure.zsh 與
#  verifications/measure_parallel_rss.zsh 完成，方法寫在那裡：每一列取 best-of-N，
#  而且若某一列沒有走它自己命名的那條路徑就拒絕回報。
# =====================================================================

emulate -L zsh
setopt no_unset pipe_fail

TRAPZERR() {
    # This script does NOT set errexit, so it did not stop -- an earlier version
    # of this message said "stopped at line N" and both halves were false: the
    # run carried on, and the line was the trap function's own. TRAPZERR fires on
    # any non-zero return regardless of errexit, so the honest thing to say is
    # that something failed and the numbers may not be comparable.
    # 這支腳本**沒有**設 errexit，所以它並沒有停——這則訊息的前一版寫著「停在第 N 行」，而兩半都是
    # 假的：那次執行繼續跑了，而那個行號是 trap 函式自己的。TRAPZERR 在任何非零返回時都會觸發，
    # 與 errexit 無關，因此誠實的說法是「有東西失敗了，這些數字可能不能拿來比較」。
    print -u2 -- "benchmark.zsh: a command failed; the run continues but the numbers may not be comparable"
    print -u2 -- "benchmark.zsh：某個命令失敗；這次執行會繼續，但這些數字可能不能拿來比較"
}

HERE=${0:A:h}
cd -- "$HERE"

FULL=0
SMALL=0
for arg in "$@"; do
    case $arg in
        --full)  FULL=1 ;;
        --small) SMALL=1 ;;
        -h|--help)
            print -r -- "usage: ./benchmark.zsh [--full] [--small]"
            print -r -- "  --full   also run the parallel-search and RSS measurement (about 25 minutes, 2.6 GB of scratch)"
            print -r -- "  --small  use a 20,000-record corpus instead of 200,000"
            print -r -- "  --full   同時執行平行搜尋與 RSS 量測（約 25 分鐘，需 2.6 GB 暫存空間）"
            print -r -- "  --small  用 20,000 筆的語料，而非 200,000 筆"
            exit 0 ;;
        *)
            print -u2 -- "unknown argument: $arg  (try --help)"
            print -u2 -- "未知的參數：$arg（試試 --help）"
            exit 2 ;;
    esac
done

# The binary is asked for its version by RUNNING it. Naming both spellings
# because compile_csv2.zsh's Windows branch produces csv2.exe, and hard-wiring
# the POSIX name once made a measurement script exit "build first" on a node
# that had just built successfully.
# 執行檔的版本是靠**執行它**問出來的。兩種拼法都指名，因為 compile_csv2.zsh 的 Windows 分支
# 產生的是 csv2.exe——而寫死 POSIX 那個名字，曾讓一支量測腳本在剛建置成功的節點上印出
# 「build first」而結束。
if [[ -x $HERE/release/csv2 ]]; then
    BIN=$HERE/release/csv2
elif [[ -x $HERE/release/csv2.exe ]]; then
    BIN=$HERE/release/csv2.exe
else
    print -u2 -- "no built binary; run ./compile_csv2.zsh first"
    print -u2 -- "找不到已建置的執行檔；請先執行 ./compile_csv2.zsh"
    exit 1
fi

print -r -- "csv2 benchmark / csv2 效能量測"
print -r -- "  binary  : $("$BIN" --version)"
print -r -- "  host    : $(uname -sm)"

# The single most important caveat, printed BEFORE the numbers rather than
# after them. Where the corpus lives moved the write rows by 4.8x on one
# machine -- same binary, same minute, different filesystem -- and a reader who
# meets that fact after the numbers has already drawn a conclusion.
# 最重要的那個但書印在數字**之前**，而不是之後。語料放在哪裡，曾在同一台機器、同一分鐘、
# 同一個執行檔上，讓寫入列相差 4.8 倍——而一個在數字之後才讀到這件事的人，已經下了結論。
print -r -- "  corpus  : built inside $HERE/verifications, so this measures THAT filesystem"
print -r -- "  語料    : 造在 $HERE/verifications 之內，因此量到的是**那個**檔案系統"
if [[ -n "$(git -C "$HERE" status --porcelain 2>/dev/null)" ]]; then
    print -r -- "  note    : the working tree is not clean, so these numbers belong to no commit"
    print -r -- "  注意    : 工作區不乾淨，因此這些數字不屬於任何一個 commit"
fi
print -r -- ""

# ---------------------------------------------------------------------
# 1. Read and write timings.
# ---------------------------------------------------------------------
print -r -- "## 1/$(( 1 + FULL ))  read and write / 讀寫"
if (( SMALL )); then
    RECORDS=20000 ./verifications/measure.zsh
else
    ./verifications/measure.zsh
fi
print -r -- ""

# ---------------------------------------------------------------------
# 2. Parallel search and RSS -- only with --full, because it writes two
#    1.3 GB files and takes about twenty-five minutes. A benchmark that does
#    that without being asked is a benchmark people stop running.
# 2. 平行搜尋與 RSS——只在 --full 時執行，因為它會寫出兩個 1.3 GB 的檔案、花約二十五分鐘。
#    一個未經要求就這樣做的效能量測，是一個人們會停止執行的效能量測。
# ---------------------------------------------------------------------
if (( FULL )); then
    print -r -- "## 2/2  parallel search and RSS / 平行搜尋與 RSS"
    print -r -- "        (two 1.3 GB corpora, about 25 minutes / 兩份 1.3 GB 語料，約 25 分鐘)"
    ./verifications/measure_parallel_rss.zsh
    print -r -- ""
fi

print -r -- "results are in verifications/ ; compare only against runs with the same"
print -r -- "binary, record count, host, storage and search conditions"
print -r -- "結果在 verifications/ 之內；只有在執行檔、筆數、主機、儲存裝置與搜尋條件都相同時"
print -r -- "才適合互相比較"
if (( ! FULL )); then
    print -r -- ""
    print -r -- "run with --full for the parallel-search and RSS numbers"
    print -r -- "要平行搜尋與 RSS 的數字，請加上 --full"
fi

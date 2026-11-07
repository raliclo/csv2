#!/usr/bin/env zsh
# Put the newest installed Swift for Windows on PATH, with its runtime and SDK. Source this.
# 把最新安裝的 Swift for Windows 連同其 runtime 與 SDK 放進 PATH。以 source 引入。
#
#   source ./swift_windows_env.zsh      set PATH/SDKROOT in the caller / 在呼叫者中設定 PATH／SDKROOT
#   zsh swift_windows_env.zsh --help    print this and do nothing / 印出這段說明，什麼都不做
#
# Picks the newest toolchain under %LOCALAPPDATA%\Programs\Swift\Toolchains that
# has a runtime of the same version, removes every other Swift toolchain or
# runtime entry from PATH, puts the chosen two bin directories first, and points
# SDKROOT at that version's Windows SDK. Does nothing off Windows, or when no
# matching toolchain/runtime pair is installed (PATH is then left as the caller
# had it). compile_csv2.zsh sources it before compile_csv2_win.bat, and
# test/test_csv2.zsh sources it at the top.
# 在 %LOCALAPPDATA%\Programs\Swift\Toolchains 底下挑出「有相同版本 runtime」的最新工具鏈，
# 從 PATH 移除其他所有 Swift 工具鏈與 runtime 項目，把選中的兩個 bin 目錄放到最前面，並讓
# SDKROOT 指向該版本的 Windows SDK。不在 Windows 上，或找不到相配的工具鏈與 runtime 時，
# 什麼都不做（PATH 維持呼叫者原樣）。compile_csv2.zsh 在呼叫 compile_csv2_win.bat 之前
# source 它，test/test_csv2.zsh 在開頭 source 它。
#
# Why (SR): on 2026-11-06 the installer moved Swift from 6.4.1 to 6.4.2 and
# deleted the 6.4.1 toolchain, runtime and SDK. A shell opened before then still
# named them, so the build found no swiftc, and T212's SwiftPM build failed on
# an SDKROOT naming the deleted 6.4.1 SDK. The build and the suite used
# whatever Swift the caller's shell happened to hold. Choosing by what is
# installed now, not by what was installed when the shell started, removes both.
# Ported from multissh's helper/swift_windows_env.zsh, which met the same thing
# at the 6.4.0 -> 6.4.1 upgrade on 2026-10-19; two copies so that each tree
# builds on its own.
# 為什麼（SR）：2026-11-06 安裝程式把 Swift 從 6.4.1 升到 6.4.2，並刪掉了 6.4.1 的工具鏈、
# runtime 與 SDK。在那之前開啟的 shell 仍指向它們，於是建置找不到 swiftc，而 T212 的 SwiftPM
# 建置因為 SDKROOT 指向已刪除的 6.4.1 SDK 而失敗。建置與測試用的，是呼叫者的 shell 剛好帶著的
# 那個 Swift。改依「現在裝了什麼」而非「shell 開啟時裝了什麼」來挑選，兩個問題就都消失了。
# 移植自 multissh 的 helper/swift_windows_env.zsh，它在 2026-10-19 的 6.4.0 → 6.4.1 升級遇過
# 同一件事；保留兩份，是為了讓每一棵樹都能各自建置。
#
# Environment / 環境變數:
#   LOCALAPPDATA  where Programs\Swift lives (default C:\Users\%USERNAME%\AppData\Local) / Programs\Swift 所在處
#   PATH, SDKROOT are set on success / 成功時設定 PATH 與 SDKROOT
#   swift_windows_version, swift_windows_runtime_bin are left set for the caller;
#   release.zsh copies the VC++ DLLs from that runtime directory.
#   swift_windows_version、swift_windows_runtime_bin 留給呼叫者使用；release.zsh 從那個
#   runtime 目錄複製 VC++ DLL。

# --help answers before anything else, and only when run, not when sourced.
# --help 在任何事之前回答，而且只在直接執行時，被 source 時略過。
if [[ $ZSH_EVAL_CONTEXT == toplevel && ( ${1:-} == -h || ${1:-} == --help ) ]]; then
    sed -n '2,43p' "${0:A}" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [[ $(uname -s) == (MSYS|MINGW|CYGWIN)* ]]; then
    swift_windows_base="$(cygpath -u "${LOCALAPPDATA:-C:\\Users\\${USERNAME}\\AppData\\Local}")/Programs/Swift"
    # Numeric sort (glob qualifier n), newest last; `6.10.0` sorts after `6.4.1`.
    # 數值排序（glob 限定詞 n），最新的在最後；`6.10.0` 會排在 `6.4.1` 之後。
    typeset -a swift_windows_toolchains
    swift_windows_toolchains=("$swift_windows_base"/Toolchains/*(N/n))
    swift_windows_version=''
    for swift_windows_candidate in "${(Oa)swift_windows_toolchains[@]}"; do
        swift_windows_candidate_version=${${swift_windows_candidate:t}%%+*}
        if [[ -d $swift_windows_base/Runtimes/$swift_windows_candidate_version/usr/bin &&
              -d $swift_windows_candidate/usr/bin ]]; then
            swift_windows_version=$swift_windows_candidate_version
            swift_windows_toolchain_bin=$swift_windows_candidate/usr/bin
            break
        fi
    done
    if [[ -n $swift_windows_version ]]; then
        swift_windows_runtime_bin=$swift_windows_base/Runtimes/$swift_windows_version/usr/bin
        # Drop every other Swift runtime or toolchain entry first, in either
        # path spelling: a deleted 6.4.1 left on PATH is at best dead weight,
        # and an older one still installed would load mismatched DLLs.
        # 先移除其他所有 Swift runtime 或工具鏈的項目（兩種路徑寫法都算）：留在 PATH 上、已被
        # 刪除的 6.4.1 至少是累贅，而仍安裝著的舊版會載入不相符的 DLL。
        path=(${path:#*/Programs/Swift/(Runtimes|Toolchains)/*})
        path=(${path:#*\\Programs\\Swift\\(Runtimes|Toolchains)\\*})
        path=("$swift_windows_runtime_bin" "$swift_windows_toolchain_bin" $path)
        export PATH
        swift_windows_sdk=$swift_windows_base/Platforms/$swift_windows_version/Windows.platform/Developer/SDKs/Windows.sdk
        if [[ -d $swift_windows_sdk ]]; then
            export SDKROOT="$(cygpath -w "$swift_windows_sdk")\\"
        fi
    fi
    unset swift_windows_candidate swift_windows_candidate_version swift_windows_toolchains \
          swift_windows_toolchain_bin swift_windows_sdk swift_windows_base
fi

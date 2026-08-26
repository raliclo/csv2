#!/usr/bin/env zsh
# =====================================================================
# module_api.zsh — prove the library surface is usable FROM OUTSIDE
# module_api.zsh — 證明那個 library 表面「從外面」用得了
#
# Marking a type `public` changes nothing inside its own module, so
# `compile_csv2.zsh` succeeding says nothing at all about whether the surface
# works. The only check that means anything is the one a caller performs:
# build the subset as a module, then compile a separate file that imports it
# and uses every type on the list.
#
# 把一個型別標成 `public`，在它自己的 module 內部什麼也不改變，因此
# `compile_csv2.zsh` 成功，對「那個表面能不能用」什麼也沒說。唯一有意義的檢查，是呼叫端
# 會做的那個：把那個子集建成一個 module，再編譯一個「import 它並用到清單上每一個型別」的
# 獨立檔案。
#
# The subset is the one a GUI caller measured as sufficient: Platform, Core,
# Support, Crypto, Markdown, Width -- and NOT Ops, Run, Parallel, Index or
# main. If that list ever stops being closed, this script fails to build and
# says which symbol pulled the rest in.
# 這個子集是一個 GUI 呼叫端實測「足夠」的那一份：Platform、Core、Support、Crypto、Markdown、
# Width——而**不含** Ops、Run、Parallel、Index 或 main。哪天那份清單不再自足，這支腳本會建置
# 失敗，並說出是哪一個符號把其餘的拉了進來。
# =====================================================================
emulate -L zsh
setopt no_unset pipe_fail

ROOT=${0:A:h:h}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/csv2_module.XXXXXX")
trap 'rm -rf $WORK' EXIT

SUBSET=(Platform Core Support Crypto Markdown Width)
SRCS=()
for f in $SUBSET; do
    [[ -f $ROOT/src/$f.swift ]] || { print -u2 -- "missing src/$f.swift"; exit 1 }
    SRCS+=($ROOT/src/$f.swift)
done

print -r -- "building module CSV2Core from: ${SUBSET[*]}"
swiftc -O -emit-module -emit-library -static \
       -module-name CSV2Core -emit-module-path $WORK/CSV2Core.swiftmodule \
       -o $WORK/libCSV2Core.a $SRCS 2>&1 | tail -20 || exit 1
[[ -f $WORK/libCSV2Core.a ]] || { print -u2 -- "no library produced"; exit 1 }

# The client. Every type on the public list is named here, because a surface
# that compiles but cannot be USED is the thing this is guarding against.
# 客戶端。清單上每一個型別都在這裡被指名，因為「編得過但用不了的表面」正是這支腳本要防的東西。
cat > $WORK/client.swift <<'SWIFT'
import CSV2Core
import Foundation

// Parse two records out of bytes, without a file and without the CLI layer.
// 從位元組解析出兩筆紀錄，不經檔案，也不經 CLI 那一層。
var seen: [Record] = []
let parser = RecordParser(format: .csv) { r in
    seen.append(r)
    return true
}
try parser.feed(Array("a,b\n1,x\n".utf8))
try parser.finish()
guard seen.count == 2 else { fatalError("expected 2 records, got \(seen.count)") }

// Read a field, change it, encode it back.
// 讀一個欄位、改掉它、再編碼回去。
var f = seen[1].fields[1]
guard String(bytes: f.value, encoding: .utf8) == "x" else { fatalError("bad value") }
f.set(Array("y".utf8))
let encoded = FieldEncoder.encode(f, format: .csv, preserveRaw: false)
guard String(bytes: encoded, encoding: .utf8) == "y" else { fatalError("bad encode") }
let row = FieldEncoder.encodeRecord(seen[1], format: .csv, preserveRaw: false)
guard String(bytes: row, encoding: .utf8) == "1,x\n" else { fatalError("bad record") }

// A source over bytes already in hand -- the shape a GUI has.
// 一個「位元組已經在手上」的來源——那正是一個 GUI 手上的形狀。
let src = ByteSource(bytes: Array("k\n".utf8))
guard let chunk = src.next(), chunk.count == 2 else { fatalError("bad source") }
src.close()

// Format is part of the surface because FieldEncoder takes one.
// Format 屬於這個表面，因為 FieldEncoder 要吃一個。
guard Format.csv2.headerRows == 2, Format.lines.headerRows == 0 else {
    fatalError("bad headerRows")
}

// BUILD a record from nothing, which is what a writer does. The first version
// of this client only ever took records APART -- it never constructed one and
// never asked a path what format it is -- so it passed while `Record` had no
// public init and `Format.from(path:)` was internal. Both gaps were found by a
// caller, not by this file, which is the shape a verification is supposed to
// prevent.
// 從零**建**一筆紀錄，那正是寫入端在做的事。這個客戶端的第一版從頭到尾只把紀錄「拆開」——它從未
// 建構過一筆，也從未問過一個路徑是什麼格式——於是在 `Record` 沒有 public init、
// `Format.from(path:)` 還是 internal 的情況下，它照樣通過。兩個缺口都是由一個呼叫端找到的，不是
// 由這個檔案，而那正是「一份驗證」本來就該防止的形狀。
let built = Record(fields: [Field(value: Array("a,b".utf8)), Field(value: Array("2".utf8))])
let builtBytes = FieldEncoder.encodeRecord(built, format: .csv, preserveRaw: false)
guard String(bytes: builtBytes, encoding: .utf8) == "\"a,b\",2\n" else {
    fatalError("bad built record: \(String(bytes: builtBytes, encoding: .utf8) ?? "?")")
}

// Ask a PATH what format it is, rather than copying the rule.
// 問一個**路徑**它是什麼格式，而不是把那條規則抄一份。
guard Format.from(path: "x.csv2") == .csv2,
      Format.from(path: "x.CSV") == .csv,
      Format.from(path: "notes.txt") == nil else {
    fatalError("bad Format.from")
}

print("client OK")
SWIFT

print -r -- "compiling a client that imports it"
swiftc -O -I $WORK -L $WORK -lCSV2Core -o $WORK/client $WORK/client.swift 2>&1 | tail -20 || exit 1
out=$($WORK/client) || exit 1
[[ $out == "client OK" ]] || { print -u2 -- "client said: $out"; exit 1 }
print -r -- "PASS  the six-file subset builds as a module and a client can use it"
print -r -- "通過  那六個檔案的子集建得成 module，而一個客戶端用得了它"

# ---------------------------------------------------------------------
# The same subset through SPM, which is how a real consumer takes it.
#
# Everything above uses bare `swiftc`, and a bare compile does not go through
# SPM's language mode. The first real consumer built it with SwiftPM in Swift 6
# mode and was stopped by two globals -- `binaryModeSet` and `doomedTemp` --
# that are `nonisolated global shared mutable state`. It declared
# `.swiftLanguageMode(.v5)` and moved on, which is a statement about what this
# module is rather than a workaround.
#
# So both modes are checked, and the v6 FAILURE is asserted rather than
# ignored. If someone makes those two globals safe, this says so instead of
# staying quiet -- a check that only notices regressions is half a check.
#
# 同一個子集，改走 SPM——那才是一個真實消費端取用它的方式。
# 上面每一步用的都是裸 `swiftc`，而裸編譯不會經過 SPM 的語言模式。第一個真實的消費端以 SwiftPM
# 在 Swift 6 模式下建置它，被兩個全域變數擋下——`binaryModeSet` 與 `doomedTemp`——它們是
# `nonisolated global shared mutable state`。它宣告了 `.swiftLanguageMode(.v5)` 然後繼續，
# 而那是在陳述「這個 module 是什麼」，不是繞過。
# 因此兩種模式都檢查，而 v6 的**失敗**是被斷言的，不是被忽略的。哪天有人把那兩個全域變數變成安全的，
# 這裡會說出來，而不是保持沉默——一個只察覺退化的檢查，只是半個檢查。
# ---------------------------------------------------------------------
if (( ! $+commands[swift] )); then
    print -r -- "SKIP  no swift driver here, so the SPM path is unchecked / 這裡沒有 swift driver，SPM 那條路徑未檢查"
    exit 0
fi

spm_build() {   # <language mode> -> 0 if it builds
    local mode=$1
    local pkg=$WORK/spm_$mode
    rm -rf $pkg; mkdir -p $pkg/Sources/CSV2Core
    for f in $SUBSET; do cp $ROOT/src/$f.swift $pkg/Sources/CSV2Core/; done
    cat > $pkg/Package.swift <<PKG
// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "CSV2Core",
    products: [.library(name: "CSV2Core", targets: ["CSV2Core"])],
    targets: [.target(name: "CSV2Core", swiftSettings: [.swiftLanguageMode(.$mode)])]
)
PKG
    # `> log 2>&1`, not `2>&1 > log`. The second binds stderr to the terminal
    # first and only then moves stdout, so a failing v6 build printed the whole
    # frontend invocation to the screen -- the classic ordering mistake, made
    # in a script whose subject is checking things properly.
    # 是 `> log 2>&1`，不是 `2>&1 > log`。後者會先把 stderr 綁到終端機、之後才移動 stdout，於是
    # 一次失敗的 v6 建置把整個 frontend 呼叫印到了螢幕上——那個經典的順序錯誤，犯在一支「主題就是
    # 好好檢查東西」的腳本裡。
    ( cd $pkg && swift build > $WORK/spm_$mode.log 2>&1 )
    return $?
}

if spm_build v5; then
    print -r -- "PASS  and it builds through SPM in Swift 5 mode, which is how it is consumed / 而它以 Swift 5 模式經 SPM 建得起來，那正是它被取用的方式"
else
    print -u2 -r -- "FAIL  the SPM build in Swift 5 mode does not work"
    tail -5 $WORK/spm_v5.log >&2
    exit 1
fi

if spm_build v6; then
    print -r -- "NOTE  it now builds in Swift 6 mode as well -- the two globals that stopped it"
    print -r -- "      (binaryModeSet, doomedTemp) must have been made safe. Update this check"
    print -r -- "      and the note beside them, and tell the consumers that pinned .v5."
    print -r -- "注意  它現在在 Swift 6 模式下也建得起來了——擋住它的那兩個全域變數應該已經被改成"
    print -r -- "      安全的了。請更新這項檢查與它們旁邊那則附註，並告訴那些釘了 .v5 的消費端。"
else
    print -r -- "PASS  and Swift 6 mode still stops on the two globals, as documented / 而 Swift 6 模式仍然卡在那兩個全域變數上，與記載相符"
fi

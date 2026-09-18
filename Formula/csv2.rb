# Homebrew formula for csv2.
#
# This repository doubles as its own tap, so no second repository is needed:
#
#   brew tap raliclo/csv2 https://github.com/raliclo/csv2
#   brew trust raliclo/csv2
#   brew install raliclo/csv2/csv2
#
# The `brew trust` line is NOT optional and is not decoration: Homebrew 6
# refuses to load a formula from a third-party tap until the tap is trusted,
# with "Refusing to load formula ... from untrusted tap". This comment said two
# lines until 2026-09-08, when running them produced exactly that refusal.
#
# The archives are .tar.zst. Homebrew unpacks those natively; nothing extra is
# required of the person installing.
#
# csv2 的 Homebrew formula。
#
# 這個 repo 同時就是它自己的 tap，因此不需要第二個 repo：
#
#   brew tap raliclo/csv2 https://github.com/raliclo/csv2
#   brew trust raliclo/csv2
#   brew install raliclo/csv2/csv2
#
# `brew trust` 那一行**不是可省的**，也不是裝飾：Homebrew 6 在第三方 tap 被信任之前，會拒絕
# 載入它的 formula，訊息是「Refusing to load formula … from untrusted tap」。這段註解直到
# 2026-09-08 為止只有兩行——而那天實際跑過它們，得到的正是那則拒絕。
#
# 封存是 .tar.zst，Homebrew 原生解得開，安裝者不必額外準備任何東西。
class Csv2 < Formula
  desc "Fail-loudly CSV parser and editor: names the record and field, never repairs"
  homepage "https://github.com/raliclo/csv2"
  version "0.1.2"
  license "MIT"

  # This url is the macOS arm64 one AND the formula's default, on purpose.
  #
  # Homebrew 7 evaluates a formula once per (OS, arch) it knows about, and a
  # combination with no url at all is a load-time error -- "formula requires at
  # least a URL" -- which fails the whole TAP, so install is never reached.
  # Until 2026-09-18 the only macOS url lived inside `on_macos { on_arm }`, so
  # the macOS x86_64 context had none and `brew tap` refused for every macOS
  # version. It had never been right; it worked under Homebrew 6 anyway, and
  # what changed is brew rather than this file. QP.
  #
  # It is written HERE rather than duplicated into an `on_macos { on_arm }`
  # block because publish.zsh rewrites "exactly one url and one sha256 per
  # platform" and refuses when it finds two. One site per platform is the
  # arrangement both tools need.
  #
  # 這個 url 同時是「macOS arm64 那一筆」與「這份 formula 的預設」，那是刻意的。
  #
  # Homebrew 7 會對它認識的每一種 (OS, 架構) 組合各求值一次，而一個「完全沒有 url」的組合是載入期
  # 錯誤——`formula requires at least a URL`——它會讓整個 **tap** 失敗，於是 install 根本輪不到。
  # 2026-09-18 之前，唯一的 macOS url 住在 `on_macos { on_arm }` 裡面，所以 macOS x86_64 那個情境
  # 一個都沒有，`brew tap` 對每一個 macOS 版本都拒絕。它從來沒有對過；它在 Homebrew 6 之下仍然能用，
  # 而中間變的是 brew，不是這個檔案。QP。
  #
  # 它寫在**這裡**而不是複製一份進 `on_macos { on_arm }`，因為 publish.zsh 改寫時要求「每個平台
  # 恰好一個 url 與一個 sha256」，看到兩個就拒絕。每個平台一個位置，是兩邊都需要的安排。
  url "https://github.com/raliclo/csv2/releases/download/v0.1.2/csv2-0.1.2-macos-arm64.tar.zst"
  sha256 "83f630d0c3b75c36020610ba987af66838b4deeb71dde7554d0cf59c4dd78712"

  # Only the platforms whose archive was built AND verified on that platform.
  # macOS x86_64 is deliberately absent rather than pointed at an archive nobody
  # could run where it was made -- and since the default url above is the arm64
  # one, "absent" has to be said out loud or an Intel Mac would silently fetch a
  # binary it cannot execute. That is what the requirement below is for.
  # 只列出「封存在該平台上被建置**且**被驗證過」的平台。macOS x86_64 是刻意缺席，而不是指向一份
  # 「在產生它的地方沒有人執行得了」的封存——而既然上面那個預設 url 是 arm64 的，「缺席」就必須被
  # **說出來**，否則一台 Intel Mac 會安靜地抓走一個它執行不了的執行檔。底下那道要求就是為了這件事。
  on_macos do
    depends_on arch: :arm64
  end

  on_linux do
    on_intel do
      url "https://github.com/raliclo/csv2/releases/download/v0.1.2/csv2-0.1.2-linux-x86_64.tar.zst"
      sha256 "be4acc1e27f9793818ef62d0d86a78ad5a10cf3c3dad67fb45c57edd27cf79ab"
    end
    # aarch64 arrives in v0.1.1. It was absent from v0.1.0 not because it was
    # untested -- T47 compares twelve invocations byte for byte against macOS
    # on every run -- but because an archive built after the tag was cut would
    # have reported a different version string from its three siblings, which
    # is QD. All four of v0.1.1's archives were built at the tag.
    # aarch64 從 v0.1.1 開始有。它在 v0.1.1 缺席，不是因為沒有測試——T47 每一次執行都拿十二組
    # 呼叫與 macOS 逐位元比對——而是因為一份「在 tag 打完之後才建的」封存，會回報與它三個手足
    # 不同的版本字串，那就是 QD。v0.1.1 的四份封存全部是在 tag 上建的。
    on_arm do
      url "https://github.com/raliclo/csv2/releases/download/v0.1.2/csv2-0.1.2-linux-aarch64.tar.zst"
      sha256 "6ddff3c95f61dd8b00776ba369db1052902ea4eef3cdf24223fb615a32ae0ace"
    end
  end

  def install
    bin.install "csv2"
  end

  # The test reads a cell, rather than only asking for --version. A binary that
  # starts and prints its version has proved only that it starts; this project's
  # own release script makes the same distinction.
  # 這個測試會讀出一個儲存格，而不只是問 --version。一個「啟動並印出版本」的執行檔，只證明了
  # 它啟動得起來；這個專案自己的發行腳本做的是同一個區分。
  test do
    (testpath/"p.csv").write("pkg,license\nzlib,MIT\n")
    assert_equal "MIT", shell_output("#{bin}/csv2 -get 1:license -i #{testpath}/p.csv").strip
    assert_match "csv2 0.1.2", shell_output("#{bin}/csv2 --version")
  end
end

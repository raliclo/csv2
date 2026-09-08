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
  version "0.1.0"
  license "MIT"

  # Only the platforms whose archive was built AND verified on that platform.
  # macOS x86_64 and Linux aarch64 are deliberately absent rather than pointed
  # at an archive nobody could run where it was made -- see the release notes.
  # 只列出「封存在該平台上被建置**且**被驗證過」的平台。macOS x86_64 與 Linux aarch64 是
  # 刻意缺席，而不是指向一份「在產生它的地方沒有人執行得了」的封存——見 release notes。
  on_macos do
    on_arm do
      url "https://github.com/raliclo/csv2/releases/download/v0.1.0/csv2-0.1.0-macos-arm64.tar.zst"
      sha256 "2619221d845cd1f1db01531039b4fef8a1085397a0b8bcfd99a1e647163c586c"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/raliclo/csv2/releases/download/v0.1.0/csv2-0.1.0-linux-x86_64.tar.zst"
      sha256 "b944339433d2092175e6fc1dc2f123cad41b32750ad7a5346c85226010c5f55a"
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
    assert_match "csv2 0.1.0", shell_output("#{bin}/csv2 --version")
  end
end

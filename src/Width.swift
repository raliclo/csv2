// =====================================================================
//  Width.swift — terminal display width, UAX #11
//  Width.swift — 終端機顯示寬度，UAX #11
//
//  Aligning columns needs the DISPLAY WIDTH, which is a fourth number
//  unrelated to the other three. Measured on this project's own samples:
//
//    sample         bytes  code points  grapheme clusters  display width
//    ok                 2            2                  2              2
//    套件名稱          12            4                  4              8
//    family emoji      25            7                  1              2
//    👍🏽                8            2                  1              2
//
//  Swift's String.count gives grapheme clusters: 4 for 套件名稱 which occupies
//  8 columns, and 1 for the family which occupies 2. Aligning with .count gets
//  both wrong -- and the Han case was already broken before emoji existed,
//  because a .csv2 file's second header row is Traditional Chinese. emoji only
//  made it more obvious.
//  Swift 的 String.count 給的是 grapheme cluster 數：套件名稱是 4 但佔 8 欄，
//  家庭 emoji 是 1 但佔 2 欄。用 .count 對齊，兩者都會歪——而且中文那一項在
//  emoji 出現之前就已經是壞的，因為 .csv2 的第二列標頭就是繁體中文；emoji 只是
//  讓它更明顯。
//
//  This is why NOT aligning is the default: the minimal `|a|b|` form renders
//  identically in every renderer and needs to know none of this.
//  這正是「預設不對齊」的理由：最小形式的 `|a|b|` 在任何 renderer 下呈現結果
//  相同，而且完全不需要知道上面這些。
// =====================================================================

import Foundation

enum DisplayWidth {
    /// East Asian Wide and Fullwidth, plus the emoji that render double-width.
    /// Sorted, and searched by bisection.
    /// East Asian Wide 與 Fullwidth，加上以雙倍寬度呈現的 emoji。已排序，以二分搜尋。
    private static let wideRanges: [(UInt32, UInt32)] = [
        (0x1100, 0x115F), (0x231A, 0x231B), (0x2329, 0x232A),
        (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3),
        (0x25FD, 0x25FE), (0x2614, 0x2615), (0x2648, 0x2653),
        (0x267F, 0x267F), (0x2693, 0x2693), (0x26A1, 0x26A1),
        (0x26AA, 0x26AB), (0x26BD, 0x26BE), (0x26C4, 0x26C5),
        (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA),
        (0x26F2, 0x26F3), (0x26F5, 0x26F5), (0x26FA, 0x26FA),
        (0x26FD, 0x26FD), (0x2705, 0x2705), (0x270A, 0x270B),
        (0x2728, 0x2728), (0x274C, 0x274C), (0x274E, 0x274E),
        (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797),
        (0x27B0, 0x27B0), (0x27BF, 0x27BF), (0x2B1B, 0x2B1C),
        (0x2B50, 0x2B50), (0x2B55, 0x2B55),
        (0x2E80, 0x303E), (0x3041, 0x33FF), (0x3400, 0x4DBF),
        (0x4E00, 0x9FFF), (0xA000, 0xA4CF), (0xA960, 0xA97F),
        (0xAC00, 0xD7A3), (0xF900, 0xFAFF), (0xFE10, 0xFE19),
        (0xFE30, 0xFE6F), (0xFF00, 0xFF60), (0xFFE0, 0xFFE6),
        (0x16FE0, 0x16FE4), (0x17000, 0x187F7), (0x18800, 0x18CD5),
        (0x1B000, 0x1B2FB), (0x1F004, 0x1F004), (0x1F0CF, 0x1F0CF),
        (0x1F18E, 0x1F18E), (0x1F191, 0x1F19A), (0x1F1E6, 0x1F1FF),
        (0x1F200, 0x1F320), (0x1F32D, 0x1F335), (0x1F337, 0x1F37C),
        (0x1F37E, 0x1F393), (0x1F3A0, 0x1F3CA), (0x1F3CF, 0x1F3D3),
        (0x1F3E0, 0x1F3F0), (0x1F3F4, 0x1F3F4), (0x1F3F8, 0x1F43E),
        (0x1F440, 0x1F440), (0x1F442, 0x1F4FC), (0x1F4FF, 0x1F53D),
        (0x1F54B, 0x1F54E), (0x1F550, 0x1F567), (0x1F57A, 0x1F57A),
        (0x1F595, 0x1F596), (0x1F5A4, 0x1F5A4), (0x1F5FB, 0x1F64F),
        (0x1F680, 0x1F6C5), (0x1F6CC, 0x1F6CC), (0x1F6D0, 0x1F6D2),
        (0x1F6EB, 0x1F6EC), (0x1F6F4, 0x1F6FC), (0x1F7E0, 0x1F7EB),
        (0x1F90C, 0x1F93A), (0x1F93C, 0x1F945), (0x1F947, 0x1F9FF),
        (0x1FA70, 0x1FAFF), (0x20000, 0x2FFFD), (0x30000, 0x3FFFD),
    ]

    /// Combining marks, joiners and variation selectors: they modify the
    /// character before them and take no columns of their own.
    /// 組合記號、連接符與變體選擇符：它們修飾前一個字元，自己不佔任何欄位。
    private static let zeroRanges: [(UInt32, UInt32)] = [
        (0x0300, 0x036F), (0x0483, 0x0489), (0x0591, 0x05BD),
        (0x0610, 0x061A), (0x064B, 0x065F), (0x0670, 0x0670),
        (0x1160, 0x11FF), (0x1AB0, 0x1AFF), (0x1DC0, 0x1DFF),
        (0x200B, 0x200F), (0x2028, 0x202E), (0x20D0, 0x20F0),
        (0xFE00, 0xFE0F), (0xFE20, 0xFE2F), (0xFEFF, 0xFEFF),
        (0xE0100, 0xE01EF),
    ]

    private static func inRanges(_ v: UInt32, _ r: [(UInt32, UInt32)]) -> Bool {
        var lo = 0
        var hi = r.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if v < r[mid].0 { hi = mid - 1 }
            else if v > r[mid].1 { lo = mid + 1 }
            else { return true }
        }
        return false
    }

    static func ofScalar(_ v: UInt32) -> Int {
        if v < 0x20 { return 0 }
        if inRanges(v, zeroRanges) { return 0 }
        if inRanges(v, wideRanges) { return 2 }
        return 1
    }

    /// A cluster's width is NOT the sum of its scalars'. The ZWJ family is four
    /// wide emoji joined by three zero-width joiners; summed that is 8, but it
    /// occupies 2 columns. The maximum gives 2 and is right for every sample in
    /// the table above -- including 👍🏽, a wide emoji plus a wide skin-tone
    /// modifier, which still occupies 2.
    /// 一個 cluster 的寬度不是其各 scalar 的總和。ZWJ 家庭是四個寬 emoji 以三個
    /// 零寬連接符連起來，加總是 8，但它只佔 2 欄。取最大值會得到 2，對上表中
    /// 每一個樣本都正確——包含 👍🏽，那是一個寬 emoji 加一個寬的膚色修飾符，
    /// 仍然只佔 2 欄。
    ///
    /// Two exceptions: an emoji presentation selector (U+FE0F) or an enclosing
    /// keycap (U+20E3) makes a narrow base wide. `1️⃣` is the digit 1 plus both
    /// and occupies 2, while the maximum over its scalars would say 1.
    /// 兩個例外：emoji presentation selector（U+FE0F）與 enclosing keycap
    /// （U+20E3）會把窄的基底字元變寬。`1️⃣` 是數字 1 加上這兩者，佔 2 欄，
    /// 而取 scalar 最大值會說 1。
    static func ofCluster(_ c: Character) -> Int {
        var maxW = 0
        var forcedWide = false
        for u in c.unicodeScalars {
            if u.value == 0xFE0F || u.value == 0x20E3 { forcedWide = true }
            let w = ofScalar(u.value)
            if w > maxW { maxW = w }
        }
        if forcedWide { return 2 }
        return max(maxW, 1)
    }

    static func of(_ s: String) -> Int {
        var w = 0
        for c in s { w += ofCluster(c) }
        return w
    }

    /// Non-UTF-8 bytes have no display width at all. Falling back to the byte
    /// count keeps the column from collapsing, and is documented rather than
    /// silently wrong.
    /// 非 UTF-8 的位元組根本沒有顯示寬度。退回以位元組數計，可避免欄位塌掉，
    /// 而且是寫明的，不是靜默的錯誤。
    static func of(_ bytes: [UInt8]) -> Int {
        guard let s = String(bytes: bytes, encoding: .utf8) else { return bytes.count }
        return of(s)
    }

    static func pad(_ s: String, to width: Int) -> String {
        let w = of(s)
        return w >= width ? s : s + String(repeating: " ", count: width - w)
    }
}

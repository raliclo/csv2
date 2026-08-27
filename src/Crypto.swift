// =====================================================================
//  Crypto.swift — self-contained crypto primitives for csv2
//  Crypto.swift — csv2 自足密碼學原語
//
//  VENDORED from multissh/swift_tar/crypto.swift (lines 1-453), unmodified
//  except for this banner. The plan says to use swift_tar's crypto.swift
//  rather than write a second implementation: it is already validated
//  against the official test vectors and already exercised in this project.
//  自 multissh/swift_tar/crypto.swift（第 1-453 行）原樣移入，除本段說明外
//  未作修改。計畫指定直接沿用 swift_tar 的 crypto.swift 而非另寫一份：它已
//  用官方測試向量驗證過，也已在本專案內受測。
//
//  Copied rather than referenced because swift_tar lives outside this
//  repository ($HOME/proj/multissh), which is not a submodule here. A build
//  that reaches outside the repo would work on this machine and nowhere
//  else -- and the plan requires csv2 to build on the Linux guest too.
//  之所以複製而非引用：swift_tar 位於本 repo 之外（$HOME/proj/multissh），
//  並非此處的 submodule。一個會伸出 repo 之外去取檔案的建置，只在這台機器上
//  成立——而計畫要求 csv2 同樣要能在 Linux guest 上建置。
//
//  Only Foundation. No CryptoKit (absent on Linux), no OpenSSL.
//  僅依賴 Foundation：不用 CryptoKit（Linux 上沒有），不用 OpenSSL。
//
//  Contents / 內容：
//    - ChaCha20 (RFC 8439 2.3) and Poly1305 (2.5)
//    - ChaCha20-Poly1305 AEAD (2.8)
//    - SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256 (RFC 2898)
//    - Salsa20/8 core and scrypt (RFC 7914)
// =====================================================================

import Foundation

// ---------------------------------------------------------------------
// MARK: - ChaCha20 (RFC 8439 §2.3)
// ---------------------------------------------------------------------

enum ChaCha20 {
    /// The 64-byte keystream block for `counter`. / `counter` 對應的 64-byte keystream 區塊。
    static func block(key: [UInt8], nonce: [UInt8], counter: UInt32) -> [UInt8] {
        precondition(key.count == 32 && nonce.count == 12)
        // "expand 32-byte k" / 常數 "expand 32-byte k"
        var s: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]
        for i in 0..<8 { s.append(le32(key, i * 4)) }
        s.append(counter)
        for i in 0..<3 { s.append(le32(nonce, i * 4)) }

        var w = s
        for _ in 0..<10 {                      // 10 double rounds = 20 rounds
            qr(&w, 0, 4,  8, 12); qr(&w, 1, 5,  9, 13)
            qr(&w, 2, 6, 10, 14); qr(&w, 3, 7, 11, 15)
            qr(&w, 0, 5, 10, 15); qr(&w, 1, 6, 11, 12)
            qr(&w, 2, 7,  8, 13); qr(&w, 3, 4,  9, 14)
        }
        var out = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            let v = w[i] &+ s[i]
            out[i * 4]     = UInt8(v & 0xff)
            out[i * 4 + 1] = UInt8((v >> 8) & 0xff)
            out[i * 4 + 2] = UInt8((v >> 16) & 0xff)
            out[i * 4 + 3] = UInt8((v >> 24) & 0xff)
        }
        return out
    }

    /// XOR `data` with the keystream starting at `counter`. / 以 `counter` 起始的 keystream XOR `data`。
    static func xor(_ data: [UInt8], key: [UInt8], nonce: [UInt8], counter: UInt32) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: data.count)
        var offset = 0
        var block = counter
        while offset < data.count {
            let ks = Self.block(key: key, nonce: nonce, counter: block)
            let n = min(64, data.count - offset)
            for i in 0..<n { out[offset + i] = data[offset + i] ^ ks[i] }
            offset += n
            block &+= 1
        }
        return out
    }

    private static func qr(_ x: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = rotl(x[d], 16)
        x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = rotl(x[b], 12)
        x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = rotl(x[d], 8)
        x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = rotl(x[b], 7)
    }
    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 { (v << n) | (v >> (32 - n)) }
    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}

// ---------------------------------------------------------------------
// MARK: - Poly1305 (RFC 8439 §2.5)
// ---------------------------------------------------------------------

/// One-time authenticator over a 32-byte key (r ‖ s). 130-bit arithmetic is
/// carried in five 26-bit limbs. / 以 32-byte 金鑰（r ‖ s）計算的一次性驗證碼；
/// 130-bit 運算以五個 26-bit limb 承載。
struct Poly1305 {
    private var r = [UInt32](repeating: 0, count: 5)
    private var h = [UInt32](repeating: 0, count: 5)
    private var pad = [UInt32](repeating: 0, count: 4)
    private var leftover: [UInt8] = []

    init(key: [UInt8]) {
        precondition(key.count == 32)
        // clamp r / 依規範遮罩 r
        let t0 = le32(key, 0), t1 = le32(key, 4), t2 = le32(key, 8), t3 = le32(key, 12)
        r[0] = t0 & 0x3ff_ffff
        r[1] = ((t0 >> 26) | (t1 << 6)) & 0x3ff_ff03
        r[2] = ((t1 >> 20) | (t2 << 12)) & 0x3ff_c0ff
        r[3] = ((t2 >> 14) | (t3 << 18)) & 0x3f0_3fff
        r[4] = (t3 >> 8) & 0x00f_ffff
        for i in 0..<4 { pad[i] = le32(key, 16 + i * 4) }
    }

    mutating func update(_ data: [UInt8]) {
        var input = leftover + data
        leftover = []
        let full = (input.count / 16) * 16
        var i = 0
        while i < full { blocks(Array(input[i..<(i + 16)]), final: false); i += 16 }
        if i < input.count { leftover = Array(input[i...]) }
        input = []
    }

    mutating func finish() -> [UInt8] {
        if !leftover.isEmpty {
            var b = leftover
            b.append(1)
            while b.count < 16 { b.append(0) }
            blocks(b, final: true)
        }
        // full carry / 完整進位
        var c: UInt32 = 0
        for i in 1..<5 { h[i] &+= c; c = h[i] >> 26; h[i] &= 0x3ff_ffff }
        h[0] &+= c &* 5; c = h[0] >> 26; h[0] &= 0x3ff_ffff; h[1] &+= c

        // compute h + -p, select if no borrow / 計算 h + -p，無借位則採用
        var g = [UInt32](repeating: 0, count: 5)
        c = 5
        for i in 0..<5 { let s = h[i] &+ c; c = s >> 26; g[i] = s & 0x3ff_ffff }
        g[4] = g[4] &- (1 << 26)
        let mask: UInt32 = (g[4] >> 31) &- 1     // 0xffffffff if h >= p
        for i in 0..<5 { h[i] = (h[i] & ~mask) | (g[i] & mask) }

        // serialize h + pad / 序列化 h + pad
        var f: UInt64 = 0
        var out = [UInt8](repeating: 0, count: 16)
        let words: [UInt32] = [
            (h[0] | (h[1] << 26)) & 0xffff_ffff,
            ((h[1] >> 6) | (h[2] << 20)) & 0xffff_ffff,
            ((h[2] >> 12) | (h[3] << 14)) & 0xffff_ffff,
            ((h[3] >> 18) | (h[4] << 8)) & 0xffff_ffff,
        ]
        for i in 0..<4 {
            f = UInt64(words[i]) &+ UInt64(pad[i]) &+ (f >> 32)
            let v = UInt32(truncatingIfNeeded: f)
            out[i * 4]     = UInt8(v & 0xff)
            out[i * 4 + 1] = UInt8((v >> 8) & 0xff)
            out[i * 4 + 2] = UInt8((v >> 16) & 0xff)
            out[i * 4 + 3] = UInt8((v >> 24) & 0xff)
        }
        return out
    }

    private mutating func blocks(_ b: [UInt8], final: Bool) {
        let hibit: UInt32 = final ? 0 : (1 << 24)
        let t0 = le32(b, 0), t1 = le32(b, 4), t2 = le32(b, 8), t3 = le32(b, 12)
        h[0] &+= t0 & 0x3ff_ffff
        h[1] &+= ((t0 >> 26) | (t1 << 6)) & 0x3ff_ffff
        h[2] &+= ((t1 >> 20) | (t2 << 12)) & 0x3ff_ffff
        h[3] &+= ((t2 >> 14) | (t3 << 18)) & 0x3ff_ffff
        h[4] &+= (t3 >> 8) | hibit

        // h *= r mod 2^130-5. Terms that wrap past limb 4 fold back multiplied
        // by 5, since 2^130 ≡ 5 (mod 2^130-5).
        // h 乘 r 後模 2^130-5：超出 limb 4 的項乘 5 折回，因 2^130 ≡ 5 (mod 2^130-5)。
        let s1 = r[1] &* 5, s2 = r[2] &* 5, s3 = r[3] &* 5, s4 = r[4] &* 5
        let h0 = UInt64(h[0]), h1 = UInt64(h[1]), h2 = UInt64(h[2])
        let h3 = UInt64(h[3]), h4 = UInt64(h[4])
        let d: [UInt64] = [
            h0 &* UInt64(r[0]) &+ h1 &* UInt64(s4) &+ h2 &* UInt64(s3) &+ h3 &* UInt64(s2) &+ h4 &* UInt64(s1),
            h0 &* UInt64(r[1]) &+ h1 &* UInt64(r[0]) &+ h2 &* UInt64(s4) &+ h3 &* UInt64(s3) &+ h4 &* UInt64(s2),
            h0 &* UInt64(r[2]) &+ h1 &* UInt64(r[1]) &+ h2 &* UInt64(r[0]) &+ h3 &* UInt64(s4) &+ h4 &* UInt64(s3),
            h0 &* UInt64(r[3]) &+ h1 &* UInt64(r[2]) &+ h2 &* UInt64(r[1]) &+ h3 &* UInt64(r[0]) &+ h4 &* UInt64(s4),
            h0 &* UInt64(r[4]) &+ h1 &* UInt64(r[3]) &+ h2 &* UInt64(r[2]) &+ h3 &* UInt64(r[1]) &+ h4 &* UInt64(r[0]),
        ]
        var c: UInt64 = 0
        for i in 0..<5 { let v = d[i] &+ c; h[i] = UInt32(v & 0x3ff_ffff); c = v >> 26 }
        h[0] &+= UInt32(c &* 5); c = UInt64(h[0] >> 26); h[0] &= 0x3ff_ffff
        h[1] &+= UInt32(c)
    }

    private func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    /// Constant-time comparison of two tags. / 兩個 tag 的定時比較。
    static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

// ---------------------------------------------------------------------
// MARK: - ChaCha20-Poly1305 AEAD (RFC 8439 §2.8)
// ---------------------------------------------------------------------

enum ChaChaPoly {
    static let keySize = 32, nonceSize = 12, tagSize = 16

    static func seal(plaintext: [UInt8], key: [UInt8], nonce: [UInt8], aad: [UInt8]) -> (ciphertext: [UInt8], tag: [UInt8]) {
        let ciphertext = ChaCha20.xor(plaintext, key: key, nonce: nonce, counter: 1)
        return (ciphertext, tag(ciphertext: ciphertext, key: key, nonce: nonce, aad: aad))
    }

    /// Returns nil when the tag does not verify. / tag 驗證失敗時回傳 nil。
    static func open(ciphertext: [UInt8], tag expected: [UInt8], key: [UInt8], nonce: [UInt8], aad: [UInt8]) -> [UInt8]? {
        let actual = tag(ciphertext: ciphertext, key: key, nonce: nonce, aad: aad)
        guard Poly1305.constantTimeEqual(actual, expected) else { return nil }
        return ChaCha20.xor(ciphertext, key: key, nonce: nonce, counter: 1)
    }

    private static func tag(ciphertext: [UInt8], key: [UInt8], nonce: [UInt8], aad: [UInt8]) -> [UInt8] {
        let polyKey = Array(ChaCha20.block(key: key, nonce: nonce, counter: 0)[0..<32])
        var mac = Poly1305(key: polyKey)
        mac.update(aad)
        mac.update([UInt8](repeating: 0, count: (16 - aad.count % 16) % 16))
        mac.update(ciphertext)
        mac.update([UInt8](repeating: 0, count: (16 - ciphertext.count % 16) % 16))
        mac.update(le64(UInt64(aad.count)) + le64(UInt64(ciphertext.count)))
        return mac.finish()
    }

    private static func le64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) }
    }
}

// ---------------------------------------------------------------------
// MARK: - SHA-256 / HMAC / PBKDF2 (FIPS 180-4, RFC 2104, RFC 2898)
// ---------------------------------------------------------------------

struct SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var m = message
        let bitLen = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in (0..<8).reversed() { m.append(UInt8((bitLen >> (8 * UInt64(i))) & 0xff)) }

        var w = [UInt32](repeating: 0, count: 64)
        var block = 0
        while block < m.count {
            for i in 0..<16 {
                let o = block + i * 4
                w[i] = (UInt32(m[o]) << 24) | (UInt32(m[o + 1]) << 16) | (UInt32(m[o + 2]) << 8) | UInt32(m[o + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            block += 64
        }
        var out = [UInt8]()
        for v in h { for i in (0..<4).reversed() { out.append(UInt8((v >> (8 * UInt32(i))) & 0xff)) } }
        return out
    }

    private static func rotr(_ v: UInt32, _ n: UInt32) -> UInt32 { (v >> n) | (v << (32 - n)) }
}

enum HMACSHA256 {
    static func authenticate(_ message: [UInt8], key: [UInt8]) -> [UInt8] {
        var k = key.count > 64 ? SHA256.hash(key) : key
        while k.count < 64 { k.append(0) }
        let opad = k.map { $0 ^ 0x5c }, ipad = k.map { $0 ^ 0x36 }
        return SHA256.hash(opad + SHA256.hash(ipad + message))
    }
}

enum PBKDF2 {
    /// PBKDF2-HMAC-SHA256. / PBKDF2-HMAC-SHA256。
    static func derive(password: [UInt8], salt: [UInt8], iterations: Int, length: Int) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(length)
        var index: UInt32 = 1
        while out.count < length {
            let idx: [UInt8] = [UInt8((index >> 24) & 0xff), UInt8((index >> 16) & 0xff),
                                UInt8((index >> 8) & 0xff), UInt8(index & 0xff)]
            var u = HMACSHA256.authenticate(salt + idx, key: password)
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = HMACSHA256.authenticate(u, key: password)
                    for i in 0..<t.count { t[i] ^= u[i] }
                }
            }
            out.append(contentsOf: t)
            index &+= 1
        }
        return Array(out[0..<length])
    }
}

// ---------------------------------------------------------------------
// MARK: - scrypt (RFC 7914)
// ---------------------------------------------------------------------

enum Scrypt {
    /// Memory-hard KDF. `n` must be a power of two. / 記憶體硬化 KDF；`n` 須為 2 的冪。
    static func derive(password: [UInt8], salt: [UInt8], n: Int, r: Int, p: Int, length: Int) -> [UInt8] {
        let blockBytes = 128 * r
        var b = PBKDF2.derive(password: password, salt: salt, iterations: 1, length: p * blockBytes)
        for i in 0..<p {
            var block = Array(b[(i * blockBytes)..<((i + 1) * blockBytes)])
            romix(&block, n: n, r: r)
            b.replaceSubrange((i * blockBytes)..<((i + 1) * blockBytes), with: block)
        }
        return PBKDF2.derive(password: password, salt: b, iterations: 1, length: length)
    }

    private static func romix(_ block: inout [UInt8], n: Int, r: Int) {
        let blockBytes = 128 * r
        var v = [[UInt8]](); v.reserveCapacity(n)
        var x = block
        for _ in 0..<n { v.append(x); blockMix(&x, r: r) }
        for _ in 0..<n {
            // j = integerify(x) mod n — the last 64-byte block's first word
            let offset = blockBytes - 64
            let j = Int(UInt32(x[offset]) | (UInt32(x[offset + 1]) << 8)
                        | (UInt32(x[offset + 2]) << 16) | (UInt32(x[offset + 3]) << 24)) & (n - 1)
            for i in 0..<blockBytes { x[i] ^= v[j][i] }
            blockMix(&x, r: r)
        }
        block = x
    }

    private static func blockMix(_ block: inout [UInt8], r: Int) {
        var x = Array(block[(128 * r - 64)..<(128 * r)])
        var out = [UInt8](repeating: 0, count: 128 * r)
        for i in 0..<(2 * r) {
            for j in 0..<64 { x[j] ^= block[i * 64 + j] }
            salsa20_8(&x)
            // even blocks to the first half, odd to the second / 偶數塊放前半、奇數塊放後半
            let dest = (i % 2 == 0) ? (i / 2) * 64 : (r + i / 2) * 64
            out.replaceSubrange(dest..<(dest + 64), with: x)
        }
        block = out
    }

    private static func salsa20_8(_ b: inout [UInt8]) {
        var x = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            x[i] = UInt32(b[i * 4]) | (UInt32(b[i * 4 + 1]) << 8)
                 | (UInt32(b[i * 4 + 2]) << 16) | (UInt32(b[i * 4 + 3]) << 24)
        }
        let input = x
        for _ in 0..<4 {                       // 4 double rounds = 8 rounds
            x[4]  ^= rotl(x[0]  &+ x[12], 7);  x[8]  ^= rotl(x[4]  &+ x[0],  9)
            x[12] ^= rotl(x[8]  &+ x[4], 13);  x[0]  ^= rotl(x[12] &+ x[8], 18)
            x[9]  ^= rotl(x[5]  &+ x[1],  7);  x[13] ^= rotl(x[9]  &+ x[5],  9)
            x[1]  ^= rotl(x[13] &+ x[9], 13);  x[5]  ^= rotl(x[1]  &+ x[13], 18)
            x[14] ^= rotl(x[10] &+ x[6],  7);  x[2]  ^= rotl(x[14] &+ x[10], 9)
            x[6]  ^= rotl(x[2]  &+ x[14], 13); x[10] ^= rotl(x[6]  &+ x[2], 18)
            x[3]  ^= rotl(x[15] &+ x[11], 7);  x[7]  ^= rotl(x[3]  &+ x[15], 9)
            x[11] ^= rotl(x[7]  &+ x[3], 13);  x[15] ^= rotl(x[11] &+ x[7], 18)
            x[1]  ^= rotl(x[0]  &+ x[3],  7);  x[2]  ^= rotl(x[1]  &+ x[0],  9)
            x[3]  ^= rotl(x[2]  &+ x[1], 13);  x[0]  ^= rotl(x[3]  &+ x[2], 18)
            x[6]  ^= rotl(x[5]  &+ x[4],  7);  x[7]  ^= rotl(x[6]  &+ x[5],  9)
            x[4]  ^= rotl(x[7]  &+ x[6], 13);  x[5]  ^= rotl(x[4]  &+ x[7], 18)
            x[11] ^= rotl(x[10] &+ x[9],  7);  x[8]  ^= rotl(x[11] &+ x[10], 9)
            x[9]  ^= rotl(x[8]  &+ x[11], 13); x[10] ^= rotl(x[9]  &+ x[8], 18)
            x[12] ^= rotl(x[15] &+ x[14], 7);  x[13] ^= rotl(x[12] &+ x[15], 9)
            x[14] ^= rotl(x[13] &+ x[12], 13); x[15] ^= rotl(x[14] &+ x[13], 18)
        }
        for i in 0..<16 {
            let v = x[i] &+ input[i]
            b[i * 4]     = UInt8(v & 0xff)
            b[i * 4 + 1] = UInt8((v >> 8) & 0xff)
            b[i * 4 + 2] = UInt8((v >> 16) & 0xff)
            b[i * 4 + 3] = UInt8((v >> 24) & 0xff)
        }
    }

    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 { (v << n) | (v >> (32 - n)) }
}

// ---------------------------------------------------------------------
// MARK: - Random bytes / 亂數位元組
// ---------------------------------------------------------------------

/// Cryptographically secure random bytes from the system CSPRNG.
/// 取自系統 CSPRNG 的密碼學安全亂數。
func cryptoRandomBytes(_ count: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: count)
    var systemRandom = SystemRandomNumberGenerator()
    for i in 0..<count { out[i] = UInt8.random(in: 0...255, using: &systemRandom) }
    return out
}

// ---------------------------------------------------------------------
// MARK: - Encrypted container / 加密容器
//
// The encryption layer sits OUTSIDE the compression codec: swift_tar builds
// the tar stream, the codec compresses it, and this layer encrypts the result.
// On read the magic is detected first, the stream is decrypted, and the plain
// filter chain then runs on the decrypted bytes — so any codec (including
// plain tar) can be encrypted, and `gzip → tar` still auto-detects inside.
// 加密層位於壓縮 codec 之外：swift_tar 產生 tar 串流，codec 壓縮，本層再加密
// 結果。讀取時先偵測 magic、解密，解密後的位元組再走原本的 filter 鏈——因此
// 任何 codec（含純 tar）都能加密，內層的 `gzip → tar` 仍會自動偵測。
//
// Layout / 佈局:
//   header 48B: magic8 | ver1 | kdf1 | logN1 | r1 | p1 | rsv3 | salt16
//               | nonceSeed8 | chunkSize4(BE) | rsv4
//   chunk:      len4(BE) | flags1 | ciphertext[len] | tag16
//   AAD:        header ‖ chunkIndex4(BE) ‖ flags1
//   nonce:      nonceSeed8 ‖ chunkIndex4(BE)
//
// Binding the whole header into every chunk's AAD makes the KDF parameters and
// salt tamper-evident; including the chunk index stops reordering, and the
// trailing final-marker chunk makes truncation detectable.
// 將整個 header 納入每個 chunk 的 AAD，使 KDF 參數與 salt 一經竄改即被發現；
// 納入 chunk 索引可阻止重排；結尾的 final marker chunk 讓截斷可被偵測。
// ---------------------------------------------------------------------

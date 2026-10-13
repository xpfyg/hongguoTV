// 协议专用变换（非标准 AES）。
// Kotlin 移植自 kotlin-tv/core/AesV3.kt（drpys 22261ad, GPL-3.0-only）。
// 注意：这是黑盒实测算法，S-box 分组、con/order 置换、密钥调度均勿改动。

final class AesV3 {
    private let word: Int
    private let box: [UInt32]
    private let con: [Int]
    private let order: [Int]
    private let keys: [[UInt32]]

    init(key: [UInt8], timestamp: Int) {
        word = timestamp & 3
        box = Array(VendorConstants.sbox[(word * 256)..<((word + 1) * 256)]).map { $0.u }
        con = [[1, 0, 2, 3], [2, 0, 3, 1], [0, 1, 3, 2], [1, 0, 2, 3]][word]
        order = [
            [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
            [0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11],
            [0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15],
            [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
        ][word]
        let initial: UInt32 = [0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f][word]
        // mk = (le32(initial) x4) XOR key（16 字节一对一），再拼 32 个零字节
        var expanded32 = xorBytes(le32(initial) + le32(initial) + le32(initial) + le32(initial), key).map { $0.u }
        expanded32 += [UInt32](repeating: 0, count: 32)
        var rounds = 8
        for i in 4..<12 {
            let at = 4 * (i - 1)
            var a = expanded32[at]
            var b = expanded32[at + 1]
            var c = expanded32[at + 2]
            var d = expanded32[at + 3]
            if i & 3 == 0 {
                let t = ((initial >> (rounds & 24)) ^ box[Int(b)]) & 255
                b = box[Int(c)]
                c = box[Int(d)]
                d = box[Int(a)]
                a = t
            }
            rounds += 2
            expanded32[at + 4] = a ^ expanded32[at - 12]
            expanded32[at + 5] = b ^ expanded32[at - 11]
            expanded32[at + 6] = c ^ expanded32[at - 10]
            expanded32[at + 7] = d ^ expanded32[at - 9]
        }
        keys = (0..<12).map { Array(expanded32[($0 * 4)..<($0 * 4 + 4)]) }
    }

    private func block(_ value: [UInt8]) -> [UInt8] {
        var rows = (0..<4).map { i in (0..<4).map { j in value[i * 4 + j].u } }

        func addCon(_ offset: Int) {
            for i in 0..<4 {
                for j in 0..<4 {
                    rows[i][j] = rows[i][j] ^ keys[offset + i][con[j]]
                }
            }
        }

        addCon(0)
        for round in 1...2 {
            for i in 0..<4 {
                for j in 0..<4 {
                    rows[i][j] = box[Int(rows[i][j])]
                }
            }
            let before = rows.map { $0 }
            for i in 0..<4 {
                rows[i] = before[con[i]]
            }
            let flat = rows.flatMap { $0 }
            for i in 0..<16 {
                rows[i / 4][i % 4] = flat[order[i]]
            }
            if round == 1 {
                for i in 0..<4 {
                    let old = rows[i]
                    rows[i] = (0..<4).map { old[con[$0]] }
                }
                func xt(_ x: UInt32) -> UInt32 {
                    ((x << 1) ^ (x & 0x80 != 0 ? 0x1b : 0)) & 255
                }
                for i in 0..<4 {
                    let t = rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i]
                    let u = rows[0][i]
                    rows[0][i] = rows[0][i] ^ t ^ xt(rows[0][i] ^ rows[1][i])
                    rows[1][i] = rows[1][i] ^ t ^ xt(rows[1][i] ^ rows[2][i])
                    rows[2][i] = rows[2][i] ^ t ^ xt(rows[2][i] ^ rows[3][i])
                    rows[3][i] = rows[3][i] ^ t ^ xt(rows[3][i] ^ u)
                }
            }
            addCon(round * 4)
        }
        for i in 0..<4 {
            for j in 0..<4 {
                rows[i][j] = rows[i][j] ^ keys[4 + i][j]
            }
        }
        return rows.flatMap { $0 }.map { UInt8($0 & 0xff) }
    }

    func encrypt(source: [UInt8], iv: [UInt8]) -> [UInt8] {
        precondition(source.count >= 248, "source 至少 248 字节")
        var plaintext = [UInt8](repeating: 0, count: 32)
        for i in 0..<31 {
            let at = i * 8
            let b0 = (source[at].u >> 4) & 2
            let b1 = source[at + 1].u & 64
            let b2 = (source[at + 2].u >> 2) & 1
            let b3 = (source[at + 3].u << 3) & 128
            let b4 = (source[at + 4].u >> 1) & 4
            let b5 = (source[at + 5].u << 3) & 16
            let b6 = (source[at + 6].u << 5) & 32
            let b7 = (source[at + 7].u >> 4) & 8
            plaintext[i] = UInt8((b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7) & 0xff)
        }
        plaintext[31] = 1
        let first = block(xorBytes(Array(plaintext[0..<16]), iv))
        let key = first + block(xorBytes(Array(plaintext[16..<32]), first))
        var out = source
        for i in 0..<31 {
            let at = i * 8
            let k = key[i].u
            out[at] = UInt8((out[at].u & 0xdf) | ((k << 4) & 32))
            out[at + 1] = UInt8((out[at + 1].u & 0xbf) | (k & 64))
            out[at + 2] = UInt8((out[at + 2].u & 0xfb) | ((k << 2) & 4))
            out[at + 3] = UInt8((out[at + 3].u & 0xef) | ((k >> 3) & 16))
            out[at + 4] = UInt8((out[at + 4].u & 0xf7) | ((k &+ k) & 8))
            out[at + 5] = UInt8((out[at + 5].u & 0xfd) | ((k >> 3) & 2))
            out[at + 6] = UInt8((out[at + 6].u & 0xfe) | ((k >> 5) & 1))
            out[at + 7] = UInt8((out[at + 7].u & 0x7f) | ((k << 4) & 128))
        }
        return [key[key.count - 1]] + out
    }
}

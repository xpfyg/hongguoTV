// 字节系 App 接口签名（Gorgon / Medusa / Helios / hashF13）。
// Kotlin 移植自 kotlin-tv/core/Signer.kt（drpys 22261adfa31435e3b3ef5a730b8a2a75bcaf1715, GPL-3.0-only）。
// 与 Kotlin 版一致：只产出 hash branch 0 —— 签名前通过 _rticket 毫秒抖动调整到 branch 0。
import Foundation

struct SignedRequest {
    let url: String
    let headers: [(String, String)]
    let body: [UInt8]?
}

/// 字节系签名。clock 返回毫秒时间戳，random 返回 [0,1)。
/// 测试时可用固定 LCG 注入 random，以复现 signing.json oracle。
final class Signer {
    private let clock: () -> UInt64
    private let random: () -> Double

    init(clock: @escaping () -> UInt64 = { UInt64(Date().timeIntervalSince1970 * 1000) },
         random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.clock = clock
        self.random = random
    }

    // MARK: - 基础

    private func rand() -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(random() * 4294967296.0))
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var n = value
        var out: [UInt8] = []
        while n > 127 {
            out.append(UInt8(n & 127) | 128)
            n >>= 7
        }
        out.append(UInt8(n))
        return out
    }

    enum ProtoValue {
        case sint(Int64)
        case float(Float)
        case string(String)
        case bytes([UInt8])
    }

    private struct Field {
        let tag: Int
        let value: ProtoValue
    }

    private func f(_ tag: Int, _ value: ProtoValue) -> Field { Field(tag: tag, value: value) }

    private func proto(_ fields: [Field]) -> [UInt8] {
        var out: [UInt8] = []
        for field in fields {
            switch field.value {
            case .sint(let n):
                out += varint(UInt64(field.tag) << 3)
                let zigzag: UInt64 = n < 0 ? UInt64(bitPattern: -n &* 2 &- 1) : UInt64(n &* 2)
                out += varint(zigzag)
            case .float(let v):
                out += varint((UInt64(field.tag) << 3) | 5)
                out += le32(v.bitPattern)
            case .string(let s):
                let bytes = [UInt8](s.utf8)
                if !bytes.isEmpty {
                    out += varint((UInt64(field.tag) << 3) | 2)
                    out += varint(UInt64(bytes.count))
                    out += bytes
                }
            case .bytes(let b):
                if !b.isEmpty {
                    out += varint((UInt64(field.tag) << 3) | 2)
                    out += varint(UInt64(b.count))
                    out += b
                }
            }
        }
        return out
    }

    // MARK: - iv / branch / hashF13

    private func getIv(_ initial: UInt32, _ data: [UInt8]) -> UInt32 {
        var value = initial
        for (i, byte) in data.enumerated() {
            let b = byte.u
            value = (i & 1 == 0)
                ? (value >> 4) ^ value ^ (value &<< 6) ^ b
                : ~((value >> 7) ^ value ^ (b | (value &<< 12)))
        }
        return value
    }

    private func iv(_ query: [UInt8], _ body: [UInt8], _ ts: UInt32) -> UInt32 {
        getIv(getIv(getIv(0x20230928, query), body), le32(ts))
    }

    /// hash branch（0/1/2）
    func branch(_ query: String, _ body: [UInt8]?, _ ts: UInt32) -> Int {
        Int(iv(SM3.digest(Data(query.utf8)).map { $0 }, body?.count == nil ? [UInt8](repeating: 0, count: 16) : md5(body!), ts) & 15) % 3
    }

    private func sumMd5(_ data: [UInt8]) -> UInt32 {
        var check: UInt32 = 0x20220420
        for i in 0..<12 {
            let temp = (check >> ((i & 1 == 0) ? 3 : 5)) ^ check
            check = (i & 1 == 0)
                ? data[i].u ^ (check &<< 7)
                : ~(data[i].u | (check &<< 11))
            check = check ^ temp
        }
        return (check | 4) ^ 0x1000000
    }

    private func reverseBits8(_ x: UInt32) -> UInt32 {
        var v = x & 255
        v = ((v >> 1) & 0x55) | ((v & 0x55) << 1)
        v = ((v >> 2) & 0x33) | ((v & 0x33) << 2)
        v = ((v >> 4) & 0x0f) | ((v & 0x0f) << 4)
        return v
    }

    /// hashF13，仅支持 branch 0
    func hashF13(_ query: [UInt8], _ body: [UInt8], _ ts: UInt32) -> [UInt8] {
        let ivValue = iv(query, body, ts)
        precondition((ivValue & 15) % 3 == 0, "Unsupported hash branch")
        let index = Int(ivValue & 15) / 3
        let ivV1: UInt32 = [0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1][index]
        let count = ivV1 &+ ts
        let tt = VendorConstants.hashTable.map { ror($0, Int((count &+ 1) & 255)) }
        let shift = Int((count &+ 2) & 7)
        let pad: [UInt8] = [0xfa, 0x45, 0x61, 0xd7].map { v in
            let n = UInt32(v) | (UInt32(v) << 8)
            return UInt8((n >> shift) & 0xff)
        }
        let data = query + body + le32(ts) + pad + hexBytes("00000000000001a0")
        var di: [UInt32] = stride(from: 0, to: data.count, by: 4).map { data.u32(at: $0) }
        for i in 0..<112 {
            let x = di[i + 1]
            let y = di[i + 14]
            di.append(di[i] &+ di[i + 9] &+ (rol(x, 14) ^ rol(x, 25) ^ (x >> 3)) &+ (rol(y, 13) ^ rol(y, 15) ^ (y >> 10)))
        }
        let initialValues: [UInt32] = [0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f, 984304912, 3005047866, 2874125293, 2152413264]
        let initial = initialValues.map { ror($0, Int(count & 31)) }
        let chosen: [Int] = [
            [101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3],
            [96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4],
            [96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5],
            [99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6],
            [96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4],
            [100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5],
        ][index]
        var d = initial
        for i in 0..<chosen[0] {
            let base = ivV1 &+ UInt32(i)
            let n1 = ((d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]]) ^ d[chosen[3]]
            let n2 = rol(d[chosen[1]], 26) ^ rol(d[chosen[1]], 21) ^ rol(d[chosen[1]], 7)
            let n4 = di[Int(base & 127)] &+ n1 &+ n2 &+ tt[Int(base & 63)] &+ d[chosen[5]]
            let n5 = rol(d[chosen[2]], 30) ^ rol(d[chosen[2]], 19) ^ rol(d[chosen[2]], 10)
            let n6 = (d[chosen[2]] & d[chosen[6]]) | ((d[chosen[2]] | d[chosen[6]]) & d[chosen[7]])
            let old = d[chosen[9]]
            let moved = d.remove(at: 7)
            d.insert(moved, at: 0)
            d[chosen[10]] = n5 &+ n6 &+ n4
            d[chosen[8]] = old &+ n4
        }
        let ret = (0..<8).reduce([UInt8]()) { acc, i in acc + be32(d[i] &+ initial[i]) }
        let folded = xorBytes(Array(ret[0..<16]), Array(ret[16..<32]))
        return folded + le32(sumMd5(folded))
    }

    // MARK: - gorgon

    func gorgon(_ query: String, _ body: [UInt8]?, _ ts: UInt32, _ random: UInt32) -> String {
        var input = md5([UInt8](query.utf8)).prefix(4).map { $0 }
        input += body.map { md5($0).prefix(4).map { $0 } } ?? [UInt8](repeating: 0, count: 4)
        input += [UInt8](repeating: 0, count: 4)
        input += le32(67503104)
        input += be32(ts)
        let key: [UInt8] = [0x4a, 0x40, 0x16, UInt8((random >> 8) & 255), 0x47, 0x6c, 1, UInt8(random & 255)]
        var s = (0..<256).map { UInt32($0) }
        var j: UInt32 = 0
        for i in 0...255 {
            j = (j &+ s[i] &+ UInt32(key[i % 8])) & 255
            s[i] = s[Int(j)]
        }
        j = 0
        var out = [UInt8](repeating: 0, count: input.count)
        for n in 0..<input.count {
            let i = n + 1
            j = j &+ s[i]
            let y = s[Int(j & 255)]
            s[i] = y
            out[n] = UInt8(input[n].u ^ s[Int((y &+ y) & 255)])
        }
        for i in 0..<out.count {
            let value = ((out[i].u >> 4) | (out[i].u << 4)) & 255
            let next = out[(i + 1 < out.count) ? i + 1 : 0].u
            let reversed = reverseBits8((next ^ value) & 255)
            out[i] = UInt8(truncatingIfNeeded: ~(reversed ^ 20))
        }
        return (hexBytes("8404") + [UInt8(random & 255), UInt8((random >> 8) & 255), 0x40, 1] + out).hexStr
    }

    // MARK: - device proto / xmxor

    private func deviceProto(_ dev: [(String, String)]) -> [UInt8] {
        func value(_ key: String) -> String { dev.first { $0.0 == key }!.1 }
        return proto([
            f(1, .sint(1)), f(2, .sint(2)), f(3, .string("8662")),
            f(4, .string(value("device_id"))), f(5, .string("Ai6svO3PyrwDOUSmO6ZcResxu")),
            f(6, .string("!noperm!")), f(7, .sint(-888888)), f(8, .sint(-888888)),
            f(9, .sint(3)), f(10, .sint(-888888)), f(11, .string("!notset!")),
            f(12, .string("Asia/Shanghai,8")), f(13, .string("zh_CN")), f(14, .sint(4)),
            f(16, .float(255.24993896484375)), f(17, .float(35.58599090576172)),
            f(18, .float(3.467449188232422)), f(19, .float(3.467449188232422)),
            f(20, .float(255.1754913330078)), f(21, .float(42.17544174194336)),
            f(22, .string("16")), f(23, .sint(41)), f(24, .sint(36)),
            f(25, .sint(1728388016635)), f(26, .sint(1728388016635)),
            f(27, .sint(1728388016635)), f(28, .sint(1728388016637)),
            f(29, .sint(-1)), f(30, .string("25053RT47C")), f(31, .string("Redmi")),
            f(32, .string("25053RT47C")), f(33, .string("25053RT47C")),
            f(34, .string("Xiaomi")), f(35, .string("Redmi")), f(36, .string("Redmi")),
            f(38, .sint(31)),
        ])
    }

    private func xmxor(_ data: [UInt8], _ key: [UInt8]) -> [UInt8] {
        var encoded = [UInt32](repeating: 0, count: data.count)
        for i in data.indices {
            let at = (i * 4) & 28
            let d0 = key[at].u
            let d1 = key[at + 1].u
            let v = data[i].u
            var d2 = (((v << 4) | (v >> 4)) & 255) &+ d0
            d2 = ~d2 ^ d1
            d2 = (((d2 & 255) << 3) | ((d2 & 255) >> 5)) & 255
            d2 = (d2 &+ d1) & 255
            d2 = (d2 ^ d0) & 255
            encoded[data.count - i - 1] = (~d2) & 255
        }
        let last = encoded[encoded.count - 1] ^ encoded[encoded.count - 2]
        let first = encoded[0]
        encoded[0] = (~last &+ first) & 255
        encoded[1] = ((encoded[0] ^ encoded[encoded.count - 1] ^ 254) &+ encoded[1]) & 255
        encoded[2] = (encoded[2] &+ ((last &- first) ^ (((encoded[1] << 3) | (encoded[1] >> 5)) & 255) ^ 2)) & 255
        for i in 0..<(encoded.count - 4) {
            let temp = (((encoded[i + 2] << 3) | (encoded[i + 2] >> 5)) & 255) ^ encoded[i + 1] ^ UInt32(i + 3)
            encoded[i + 3] = (~temp &+ encoded[i + 3]) & 255
        }
        encoded[encoded.count - 1] = encoded[encoded.count - 1] ^ encoded[encoded.count - 2]
        encoded[0] = ((encoded[0] ^ encoded[1]) &+ encoded.dropFirst().reduce(UInt32(0), &+)) & 255
        return encoded.map { UInt8($0 & 255) }
    }

    // MARK: - medusa / helios

    func medusa(_ url: String, _ body: [UInt8]?, _ ts: UInt32, device: [(String, String)]? = nil) -> String {
        let dev = device ?? VendorConstants.device
        let bodyMd5 = body.map { md5($0) } ?? [UInt8](repeating: 0, count: 16)
        let query = url.split(separator: "?", maxSplits: 1).last.map { [UInt8]($0.utf8) } ?? []
        let querySm3 = SM3.digest(Data(query)).map { $0 }
        let queryBodyTs = hashF13(querySm3, bodyMd5, ts)
        let nested = proto([
            f(1, .sint(111)), f(2, .sint(10)), f(3, .sint(694367)), f(5, .sint(586952199)),
        ])
        let messageRand = UInt64(rand())
        let envLaunch = Int(random() * 21) + 100
        let envPid = Int(random() * 2000) + 10001
        let version = dev.first { $0.0 == "version_name" }!.1
        let env = proto([
            f(1, .sint(Int64(envLaunch))), f(2, .sint(146331399)), f(3, .sint(146331396)),
            f(5, .sint(7)), f(6, .string("v04.06.04.03-bugfix")), f(7, .sint(Int64(envPid))),
            f(12, .bytes(deviceProto(dev))),
            f(13, .bytes(proto([f(1, .sint(Int64(clock() / 1000))), f(2, .sint(-2)), f(4, .sint(200))]))),
            f(14, .string(version)),
        ])
        let queryHash = SM3.digest(Data(query + bodyMd5 + [UInt8]("none".utf8))).map { $0 }
        let message = proto([
            f(1, .bytes(hexBytes("f7e85ffad7d7dc3bd62ac87057cf6118"))), f(2, .sint(3)),
            f(3, .sint(Int64(bitPattern: messageRand))), f(4, .string("8662")),
            f(5, .string(dev.first { $0.0 == "device_id" }!.1)),
            f(6, .string("1588093228")), f(7, .string(version)),
            f(8, .string("v04.06.04-ml-android")), f(9, .sint(67503104)),
            f(10, .bytes(hexBytes("4001000000000000"))), f(12, .sint(Int64(ts))),
            f(13, .bytes(queryBodyTs)), f(14, .bytes(Array(querySm3.prefix(6)))),
            f(15, .bytes(nested)), f(16, .string("AXYQOS6n2m60x1fVZHIrH3iol")),
            f(17, .sint(Int64(ts))), f(19, .bytes(queryHash)), f(20, .string("none")),
            f(21, .sint(312)), f(23, .bytes(env)),
            f(24, .string("{\"cmr\":16777216,\"cmr2\":16777216,\"un_h\":1879194040,\"vpn\":0,\"kd\":0,\"fkd\":3672518972,\"pd\":-1872573247,\"dyn\":\"\",\"do\":0,\"tk\":true}")),
        ])
        let r = rand()
        let signKey = hexBytes("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5")
        let hash = SM3.digest(Data(signKey + le32(r) + signKey)).map { $0 }
        let d1 = (r >> 16) & 255
        let seed = le32(~(((d1 << 11) | (r >> 24)) ^ (d1 >> 5) ^ d1))
        var transformed = Array((hexBytes("4001000000000000") + xmxor(message, hash)).reversed())
        for i in transformed.indices {
            transformed[i] = UInt8(transformed[i].u ^ seed[(~i) & 3].u)
        }
        let check = ((querySm3[0].u & 63) << 14) | 0x18000001 | ((queryBodyTs[0].u & 63) << 8)
        var packed = [UInt8(0x35)] + le32(rand()) + le32(check) + transformed + [UInt8((r >> 16) & 255), UInt8((r >> 24) & 255)]
        packed = AesV3(key: hexBytes("f1593376766ea98d34f31b057a9d5be4"), timestamp: Int(ts)).encrypt(source: packed, iv: hexBytes("1fe109a4125283f418de9e051a969e12"))
        let versionBytes = hexBytes("03000000f7e85ffad7d7dc3bd62ac87057cf6118")
        var prefix: [UInt8] = []
        for i in stride(from: 0, to: 20, by: 4) {
            prefix += le32(versionBytes.u32(at: i, little: true) ^ ts)
        }
        return (prefix + [UInt8(r & 255), UInt8((r >> 8) & 255), 0, 1] + packed).base64Str
    }

    func helios(_ ts: UInt32) -> String {
        let random = rand()
        let ascii = [UInt8](md5(le32(random) + [UInt8]("8662".utf8)).hexStr.utf8)
        var words: [UInt64] = (0..<4).map { ascii.i64(at: $0 * 8, little: true) }
        var table: [UInt64] = [words[0]]
        var b0 = words.removeFirst()
        var b8 = words.removeFirst()
        for i in 0..<34 {
            var x8 = ror64(b8, 8) &+ b0 ^ UInt64(i)
            words.append(x8)
            x8 = x8 ^ ror64(b0, 61)
            table.append(x8)
            b0 = x8
            b8 = words.removeFirst()
        }
        let text = [UInt8]("\(ts)-1588093228-8662".utf8)
        let padding = 16 - text.count % 16
        let data = text + [UInt8](repeating: UInt8(padding), count: padding)
        var output = le32(random)
        var at = 0
        while at < data.count {
            var a = data.i64(at: at, little: true)
            var b = data.i64(at: at + 8, little: true)
            for i in 0..<34 {
                b = table[i] ^ (a &+ ror64(b, 8))
                a = b ^ ror64(a, 61)
            }
            output += le64(a) + le64(b)
            at += 16
        }
        return output.base64Str
    }

    // MARK: - sign

    /// URL 编码（等价 Kotlin encode：URLEncoder + "+"→"%20" + "%7E"→"~"）
    static func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-*~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    /// 对请求签名。base 为接口地址，values 为查询参数（保序），body 为空则视为 GET。
    func sign(base: String, values: [(String, String)], body: [UInt8]? = nil) -> SignedRequest {
        let now = clock()
        let ts = UInt32(now / 1000)
        var ticket = now
        var query = ""
        var signed = false
        for offset in 0..<128 {
            ticket = now &+ UInt64(offset)
            var merged = values
            merged.append(("ts", String(ts)))
            merged.append(("_rticket", String(ticket)))
            query = merged.map { "\(Self.urlEncode($0.0))=\(Self.urlEncode($0.1))" }.joined(separator: "&")
            if branch(query, body, ts) == 0 {
                signed = true
                break
            }
        }
        precondition(signed, "无法生成请求签名")
        let url = "\(base)?\(query)"
        let random = UInt32(random() * 65536)
        var headers: [(String, String)] = [
            ("User-Agent", body != nil ? VendorConstants.videoUA : VendorConstants.appUA),
            ("Accept", "application/json; charset=utf-8,application/x-protobuf"),
            ("x-ss-req-ticket", String(ticket)),
            ("x-tt-request-tag", "t=0;n=0"),
            ("sdk-version", "2"),
            ("passport-sdk-version", "50561"),
            ("x-xs-from-web", "0"),
            ("x-khronos", String(ts)),
            ("x-ladon", be32(ts).base64Str),
            ("x-argus", le32(ts).base64Str),
            ("x-gorgon", gorgon(query, body, ts, random)),
            ("x-helios", helios(ts)),
            ("x-medusa", medusa(url, body, ts, device: values)),
            ("x-tt-dt", ""),
        ]
        if body != nil {
            headers.append(("Content-Type", "application/json; charset=UTF-8"))
            headers.append(("x-vc-bdturing-sdk-version", "3.7.2.cn"))
            headers.append(("x-ss-stub", md5(body!).hexStr.uppercased()))
        }
        return SignedRequest(url: url, headers: headers, body: body)
    }
}

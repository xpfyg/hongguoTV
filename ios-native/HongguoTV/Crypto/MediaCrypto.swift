// 内容密钥派生、spade 播放地址解密、CENC(MP4) 索引解析与分段解密。
// Kotlin 移植自 kotlin-tv/core/MediaCrypto.kt（drpys 22261ad, GPL-3.0-only）。
import Foundation
import CryptoKit

enum MediaCryptoError: Error {
    case invalidContainer(String)
    case invalidFormat(String)
    case aesFailure(Int)
}

enum MediaCrypto {
    struct Sample {
        let start: UInt64
        let end: UInt64
        let iv: [UInt8]
        let encryptedOffset: UInt64
    }

    struct Prepared {
        let header: [UInt8]
        let samples: [Sample]
    }

    // MARK: - 内容密钥

    /// 从 key_seed 派生 AES-128 内容密钥
    static func deriveKey(_ value: String) throws -> [UInt8] {
        let raw = decode64(value)
        guard raw.count >= 3 else { throw MediaCryptoError.invalidFormat("内容密钥格式异常") }
        let length = min(raw.count - Int(raw[0].u ^ raw[1].u ^ raw[2].u) + 47, raw.count - 1)
        guard length >= 33 else { throw MediaCryptoError.invalidFormat("内容密钥长度异常") }
        var work = Array(raw[1..<(1 + length)])
        var a = 85
        var b = 246
        for i in work.indices {
            let old = Int(work[i].u)
            let previous = (i & 1 != 0) ? a : b
            if i & 1 != 0 { a = old } else { b = old }
            work[i] = UInt8(truncatingIfNeeded: -21 - i.nonzeroBitCount + (previous ^ old))
        }
        guard let ascii = String(bytes: work[1..<33], encoding: .ascii) else {
            throw MediaCryptoError.invalidFormat("内容密钥 ASCII 解码失败")
        }
        let key = hexBytes(ascii)
        guard key.count == 16 else { throw MediaCryptoError.invalidFormat("内容密钥长度异常") }
        return key
    }

    /// 解密 spade 播放地址（AES-128-CBC，PKCS7 手工去除 + 尾部零清理）
    static func decryptUrl(_ value: String, seed: [UInt8]) throws -> String {
        let raw = decode64(value)
        guard raw.count >= 20, raw[0] == 0xa8, raw[2] == 1, raw[3] == 0 else {
            throw MediaCryptoError.invalidFormat("播放地址格式异常")
        }
        let constants = hexBytes("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
        let h = [UInt8](SHA512.hash(data: Data([UInt8](SHA512.hash(data: Data(seed))) + constants)))
        let ciphered = Array(raw[4..<(4 + (raw.count - 4) / 16 * 16)])
        var bytes = try aesDecrypt(.cbcNoPadding, key: Array(h[0..<16]), iv: Array(h[16..<32]), data: ciphered)
        var end = bytes.count
        let padding = Int(bytes.last!.u)
        if padding >= 1 && padding <= 16 && padding <= end { end -= padding }
        while end > 0 && bytes[end - 1] == 0 { end -= 1 }
        guard let text = String(bytes: bytes[0..<end], encoding: .utf8) else {
            throw MediaCryptoError.invalidFormat("播放地址 UTF-8 解码失败")
        }
        return text
    }

    // MARK: - MP4 box 解析

    private struct Box {
        let start: Int
        let end: Int
        let body: Int
        let type: String
    }

    private static func box(_ data: [UInt8], _ at: Int, _ limit: Int) -> Box? {
        if at < 0 || at + 8 > limit { return nil }
        var size = data.u32(at: at)
        var header = 8
        if size == 1 {
            if at + 16 > limit { return nil }
            size = UInt32(truncatingIfNeeded: data.i64(at: at + 8))
            header = 16
        }
        if size == 0 { size = UInt32(limit - at) }
        if size < UInt32(header) || Int(size) > limit - at { return nil }
        guard let type = String(bytes: data[(at + 4)..<(at + 8)], encoding: .ascii) else { return nil }
        return Box(start: at, end: at + Int(size), body: at + header, type: type)
    }

    private static func find(_ data: [UInt8], _ type: String, _ start: Int, _ limit: Int) -> Box? {
        guard let first = type.utf8.first else { return nil }
        var at = start
        while at <= limit - 8 {
            if data[at + 4] == first {
                if let b = box(data, at, limit), b.type == type { return b }
            }
            at += 1
        }
        return nil
    }

    /// 校验视频容器并返回 moov 结束位置
    static func headerEnd(_ first: [UInt8], total: UInt64) throws -> Int {
        if first.count < 16 || String(bytes: first[4..<8], encoding: .ascii) != "ftyp" {
            throw MediaCryptoError.invalidContainer("不支持的视频容器")
        }
        let ftyp = first.u32(at: 0)
        if ftyp < 8 || ftyp + 8 > UInt32(first.count) || String(bytes: first[(Int(ftyp) + 4)..<(Int(ftyp) + 8)], encoding: .ascii) != "moov" {
            throw MediaCryptoError.invalidContainer("视频索引不在文件开头")
        }
        let size = first.u32(at: Int(ftyp))
        let end = ftyp &+ size
        if size < 8 || end > total || end > 8 * 1024 * 1024 {
            throw MediaCryptoError.invalidContainer("视频索引大小异常")
        }
        return Int(end)
    }

    // MARK: - CENC 索引

    /// 解析 CENC 加密索引；key 为 nil 时原样返回（未加密流）
    static func prepare(_ data: [UInt8], key: [UInt8]?) throws -> Prepared {
        guard let key = key else { return Prepared(header: data, samples: []) }
        guard let moov = box(data, Int(data.u32(at: 0)), data.count), moov.type == "moov" else {
            throw MediaCryptoError.invalidContainer("视频索引不完整")
        }
        var samples: [Sample] = []
        var header = data
        var cursor = moov.body
        while cursor < moov.end {
            guard let track = box(data, cursor, moov.end) else { throw MediaCryptoError.invalidFormat("视频轨道格式异常") }
            cursor = track.end
            if track.type != "trak" { continue }
            guard let stbl = find(data, "stbl", track.body, track.end) else { continue }
            guard let saiz = find(data, "saiz", stbl.body, stbl.end) else { continue }
            guard let saio = find(data, "saio", stbl.body, stbl.end) else { throw MediaCryptoError.invalidFormat("视频加密索引缺失") }
            guard let stsz = find(data, "stsz", stbl.body, stbl.end) else { throw MediaCryptoError.invalidFormat("样本索引缺失") }
            guard let stsc = find(data, "stsc", stbl.body, stbl.end) else { throw MediaCryptoError.invalidFormat("块索引缺失") }
            guard let chunks = find(data, "stco", stbl.body, stbl.end) ?? find(data, "co64", stbl.body, stbl.end) else {
                throw MediaCryptoError.invalidFormat("块偏移缺失")
            }
            func count(_ at: Int, _ limit: Int) throws -> Int {
                guard at + 4 <= limit else { throw MediaCryptoError.invalidFormat("索引越界") }
                let n = data.u32(at: at)
                guard n <= 200000 else { throw MediaCryptoError.invalidFormat("索引数量过大") }
                return Int(n)
            }
            let n = try count(stsz.body + 8, stsz.end)
            let defaultSize = data.u32(at: stsz.body + 4)
            if defaultSize == 0 && UInt64(stsz.body) + 12 + UInt64(n) * 4 > UInt64(stsz.end) {
                throw MediaCryptoError.invalidFormat("样本索引截断")
            }
            let sizes: [UInt64] = (0..<n).map { i in
                defaultSize > 0 ? UInt64(defaultSize) : UInt64(data.u32(at: stsz.body + 12 + i * 4))
            }
            let chunkCount = try count(chunks.body + 4, chunks.end)
            let width = chunks.type == "co64" ? 8 : 4
            if UInt64(chunks.body) + 8 + UInt64(chunkCount) * UInt64(width) > UInt64(chunks.end) {
                throw MediaCryptoError.invalidFormat("块偏移截断")
            }
            let offsets: [UInt64] = (0..<chunkCount).map { i in
                width == 8 ? data.i64(at: chunks.body + 8 + i * width) : UInt64(data.u32(at: chunks.body + 8 + i * width))
            }
            let entryCount = try count(stsc.body + 4, stsc.end)
            if UInt64(stsc.body) + 8 + UInt64(entryCount) * 12 > UInt64(stsc.end) || entryCount == 0 {
                throw MediaCryptoError.invalidFormat("块索引截断")
            }
            let entries: [(UInt32, UInt32)] = (0..<entryCount).map { i in
                (data.u32(at: stsc.body + 8 + i * 12), data.u32(at: stsc.body + 12 + i * 12))
            }
            // ISO BMFF auxiliary-info flags 可能带 8 字节 type/parameter 对
            let sizeBase = saiz.body + 4 + ((data.u32(at: saiz.body) & 1) != 0 ? 8 : 0)
            guard sizeBase + 5 <= saiz.end else { throw MediaCryptoError.invalidFormat("辅助索引截断") }
            let auxDefault = data[sizeBase].u
            let auxCount = try count(sizeBase + 1, saiz.end)
            if auxCount != n || (auxDefault == 0 && sizeBase + 5 + n > saiz.end) {
                throw MediaCryptoError.invalidFormat("辅助索引数量不一致")
            }
            let auxSizes: [UInt32] = (0..<n).map { i in
                auxDefault > 0 ? auxDefault : data[sizeBase + 5 + i].u
            }
            let offsetBase = saio.body + 4 + ((data.u32(at: saio.body) & 1) != 0 ? 8 : 0)
            let offsetWidth = data[saio.body] == 1 ? 8 : 4
            if try count(offsetBase, saio.end) != 1 || offsetBase + 4 + offsetWidth > saio.end {
                throw MediaCryptoError.invalidFormat("不支持的辅助索引布局")
            }
            var aux: UInt64 = offsetWidth == 8 ? data.i64(at: offsetBase + 4) : UInt64(data.u32(at: offsetBase + 4))
            let auxEnd = aux &+ auxSizes.reduce(UInt64(0)) { $0 &+ UInt64($1) }
            if auxEnd > UInt64(data.count) { throw MediaCryptoError.invalidFormat("辅助数据超出索引范围") }
            var sampleIndex = 0
            var entry = 0
            for chunk in offsets.indices {
                while entry + 1 < entries.count && entries[entry + 1].0 <= UInt32(chunk + 1) { entry += 1 }
                let chunkSampleCount = entries[entry].1
                if chunkSampleCount > UInt32(n - sampleIndex) || entries[entry].0 > UInt32(chunk + 1) {
                    throw MediaCryptoError.invalidFormat("样本与块数量不一致")
                }
                var position = offsets[chunk]
                for _ in 0..<chunkSampleCount {
                    let length = sizes[sampleIndex]
                    let auxSize = auxSizes[sampleIndex]
                    if auxSize < 8 { throw MediaCryptoError.invalidFormat("样本索引异常") }
                    let iv = Array(data[Int(aux)..<(Int(aux) + 8)]) + [UInt8](repeating: 0, count: 8)
                    if auxSize == 8 {
                        samples.append(Sample(start: position, end: position &+ length, iv: iv, encryptedOffset: 0))
                    } else {
                        if auxSize < 10 { throw MediaCryptoError.invalidFormat("不支持的加密样本格式") }
                        let subs = (UInt32(data[Int(aux) + 8]) << 8) | UInt32(data[Int(aux) + 9])
                        if auxSize != 10 + subs * 6 { throw MediaCryptoError.invalidFormat("加密子样本索引异常") }
                        var offset = position
                        var encrypted: UInt64 = 0
                        for sub in 0..<subs {
                            let at = Int(aux) + 10 + Int(sub) * 6
                            let clear = (UInt64(data[at]) << 8) | UInt64(data[at + 1])
                            let size = UInt64(data.u32(at: at + 2))
                            offset &+= clear
                            if offset &+ size > position &+ length { throw MediaCryptoError.invalidFormat("加密子样本越界") }
                            if size > 0 { samples.append(Sample(start: offset, end: offset &+ size, iv: iv, encryptedOffset: encrypted)) }
                            encrypted &+= size
                            offset &+= size
                        }
                        if offset != position &+ length { throw MediaCryptoError.invalidFormat("加密子样本长度异常") }
                    }
                    position &+= length
                    aux &+= UInt64(auxSize)
                    sampleIndex += 1
                }
            }
            if sampleIndex != n { throw MediaCryptoError.invalidFormat("视频样本不完整") }
            // 从 frma 恢复原始编码（AVC/HEVC），替换 encv/enca 类型，抹除 sinf
            var at = stbl.body
            while at + 8 <= stbl.end {
                guard let sinf = find(data, "sinf", at, stbl.end) else { break }
                guard let frma = find(data, "frma", sinf.body, sinf.end) else { throw MediaCryptoError.invalidFormat("原始编码格式缺失") }
                guard frma.body + 4 <= frma.end else { throw MediaCryptoError.invalidFormat("原始编码格式无效") }
                let original = Array(data[frma.body..<(frma.body + 4)])
                var entryAt = sinf.start - 1
                while entryAt >= stbl.body {
                    let type = String(bytes: data[entryAt..<(entryAt + 4)], encoding: .ascii)
                    if type == "encv" || type == "enca" {
                        header.replaceSubrange(entryAt..<(entryAt + 4), with: original)
                        break
                    }
                    entryAt -= 1
                }
                header.replaceSubrange((sinf.start + 4)..<(sinf.start + 8), with: [UInt8]("free".utf8))
                header.replaceSubrange(sinf.body..<sinf.end, with: [UInt8](repeating: 0, count: sinf.end - sinf.body))
                at = sinf.end
            }
        }
        if samples.isEmpty { throw MediaCryptoError.invalidFormat("视频加密索引不可用") }
        let sorted = samples.sorted { $0.start < $1.start }
        for i in 0..<(sorted.count - 1) where sorted[i].end > sorted[i + 1].start {
            throw MediaCryptoError.invalidFormat("视频样本重叠")
        }
        return Prepared(header: header, samples: sorted)
    }

    // MARK: - 分段解密

    /// 128 位大端 counter：iv + blocks（低 64 位加法，进位到高 64 位，等价 Kotlin BigInteger 实现）
    private static func counterIV(_ iv: [UInt8], _ blocks: UInt64) -> [UInt8] {
        var lo = iv.i64(at: 8, little: false)
        var hi = iv.i64(at: 0, little: false)
        let newLo = lo &+ blocks
        hi = hi &+ (newLo < lo ? 1 : 0)
        lo = newLo
        return be64(hi) + be64(lo)
    }

    /// 解密一段数据：start 为全局文件偏移，key 为 nil 时仅还原 header
    static func decrypt(_ data: [UInt8], start: UInt64, key: [UInt8]?, prepared: Prepared) throws -> [UInt8] {
        var result = data
        let end = start &+ UInt64(data.count)
        let headerSize = UInt64(prepared.header.count)
        if start < headerSize {
            let copyEnd = min(end, headerSize)
            result.replaceSubrange(0..<Int(copyEnd - start), with: Array(prepared.header[Int(start)..<Int(copyEnd)]))
        }
        guard let key = key else { return result }
        let samples = prepared.samples
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) >> 1
            if samples[middle].end <= start { low = middle + 1 } else { high = middle }
        }
        for i in low..<samples.count {
            let sample = samples[i]
            if sample.start >= end { break }
            let begin = max(start, sample.start)
            let stop = min(end, sample.end)
            if begin >= stop { continue }
            let relative = begin - sample.start + sample.encryptedOffset
            let skip = Int(relative % 16)
            let counter = counterIV(sample.iv, relative / 16)
            let padded = [UInt8](repeating: 0, count: skip) + result[Int(begin - start)..<Int(stop - start)]
            let decrypted = try aesDecrypt(.ctr, key: key, iv: counter, data: padded)
            result.replaceSubrange(Int(begin - start)..<Int(stop - start), with: decrypted[skip...])
        }
        return result
    }
}

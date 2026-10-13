// 字节工具与基础密码学原语。
// Kotlin 移植自 kotlin-tv/core/Bytes.kt（drpys 22261ad, GPL-3.0）；SM3 见 SM3.swift（GmSSL, Apache-2.0）。
// AES 通过 CommonCrypto 提供：CBC(NoPadding) 与 CTR 两种模式，均为标准 NIST 语义。
import Foundation
import CommonCrypto
import CryptoKit

// MARK: - 字节视图

extension UInt8 {
    /// 无符号 32 位视图（等价 Kotlin `toInt() and 255`）
    var u: UInt32 { UInt32(self) }
}

extension Array where Element == UInt8 {
    /// 十六进制小写字符串（等价 Kotlin `ByteArray.hex()`）
    var hexStr: String { map { String(format: "%02x", $0) }.joined() }

    var base64Str: String { Data(self).base64EncodedString() }

    /// 读取 at 处 4 字节为无符号整数（默认大端）
    func u32(at: Int, little: Bool = false) -> UInt32 {
        var n: UInt32 = 0
        for i in 0..<4 {
            let byte = UInt32(self[at + i])
            n = little ? (n | (byte << (8 * i))) : ((n << 8) | byte)
        }
        return n
    }

    /// 读取 at 处 8 字节为无符号 64 位整数（默认大端）
    func i64(at: Int, little: Bool = false) -> UInt64 {
        var n: UInt64 = 0
        for i in 0..<8 {
            let byte = UInt64(self[at + i])
            n = little ? (n | (byte << (8 * i))) : ((n << 8) | byte)
        }
        return n
    }
}

// MARK: - 编解码

/// 十六进制字符串 → 字节
func hexBytes(_ value: String) -> [UInt8] {
    precondition(value.count % 2 == 0, "hex 长度必须为偶数")
    var out = [UInt8](); out.reserveCapacity(value.count / 2)
    var index = value.startIndex
    while index < value.endIndex {
        let next = value.index(index, offsetBy: 2)
        out.append(UInt8(value[index..<next], radix: 16)!)
        index = next
    }
    return out
}

/// URL-safe base64 → 字节（等价 Kotlin decode64）
func decode64(_ s: String) -> [UInt8] {
    let normalized = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    guard let data = Data(base64Encoded: normalized) else { return [] }
    return [UInt8](data)
}

func le32(_ n: UInt32) -> [UInt8] {
    [UInt8(n & 0xff), UInt8((n >> 8) & 0xff), UInt8((n >> 16) & 0xff), UInt8((n >> 24) & 0xff)]
}

func be32(_ n: UInt32) -> [UInt8] {
    [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
}

func le64(_ n: UInt64) -> [UInt8] {
    (0..<8).map { UInt8((n >> (8 * $0)) & 0xff) }
}

func be64(_ n: UInt64) -> [UInt8] {
    (0..<8).reversed().map { UInt8((n >> (8 * $0)) & 0xff) }
}

// MARK: - 摘要

func md5(_ data: [UInt8]) -> [UInt8] {
    [UInt8](Insecure.MD5.hash(data: Data(data)))
}

func sha512(_ data: [UInt8]) -> [UInt8] {
    [UInt8](SHA512.hash(data: Data(data)))
}

// MARK: - 位运算

func rol(_ v: UInt32, _ n: Int) -> UInt32 {
    let n = n & 31
    return (v << n) | (v >> (32 - n))
}

func ror(_ v: UInt32, _ n: Int) -> UInt32 {
    rol(v, 32 - n)
}

func ror64(_ v: UInt64, _ n: Int) -> UInt64 {
    let n = n & 63
    return (v >> n) | (v << (64 - n))
}

/// 逐字节异或，b 短则循环复用（等价 Kotlin xor）
func xorBytes(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
    guard !b.isEmpty else { return a }
    return a.enumerated().map { $0.element ^ b[$0.offset % b.count] }
}

// MARK: - AES（CommonCrypto）

enum AESMode {
    case cbcNoPadding
    case ctr
}

/// AES-128 解密：CBC(NoPadding) 或 CTR，均 NIST 大端 counter 语义
/// 注意：CTR 模式使用 kCCModeCTR（大端递增），与 Node/Kotlin 的 addCounter 一致。
func aesDecrypt(_ mode: AESMode, key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> [UInt8] {
    precondition(key.count == 16, "AES-128 key 必须为 16 字节")
    precondition(iv.count == 16, "IV 必须为 16 字节")
    let dataLen = data.count
    let outCapacity = dataLen + kCCBlockSizeAES128
    var out = [UInt8](repeating: 0, count: outCapacity)
    var moved = 0

    switch mode {
    case .cbcNoPadding:
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0), // NoPadding
                        keyPtr.baseAddress, key.count,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress, dataLen,
                        &out, outCapacity, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw MediaCryptoError.aesFailure(Int(status)) }
        return Array(out.prefix(moved))

    case .ctr:
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(0), ivPtr.baseAddress, keyPtr.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(0), &cryptor)
            }
        }
        guard status == kCCSuccess, let cryptor = cryptor else {
            throw MediaCryptoError.aesFailure(Int(status))
        }
        defer { CCCryptorRelease(cryptor) }
        var outOffset = 0
        var updateMoved = 0
        let updateStatus = data.withUnsafeBytes { dataPtr in
            CCCryptorUpdate(cryptor, dataPtr.baseAddress, dataLen, &out, outCapacity, &updateMoved)
        }
        outOffset = updateMoved
        guard updateStatus == kCCSuccess else { throw MediaCryptoError.aesFailure(Int(updateStatus)) }
        var finalMoved = 0
        let finalStatus = out.withUnsafeMutableBufferPointer { outBuf in
            CCCryptorFinal(cryptor, outBuf.baseAddress!.advanced(by: outOffset), outCapacity - outOffset, &finalMoved)
        }
        guard finalStatus == kCCSuccess else { throw MediaCryptoError.aesFailure(Int(finalStatus)) }
        outOffset += finalMoved
        return Array(out.prefix(outOffset))
    }
}

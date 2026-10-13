import XCTest
@testable import HongguoTV

/// 解密与 CENC 索引测试：与 Kotlin MediaCryptoTest 对齐
/// （NIST CTR 官方向量 × 全非对齐 Range、子样本偏移、MP4 fixture、失败路径）。
final class MediaCryptoTests: XCTestCase {
    private let key = hexBytes("2b7e151628aed2a6abf7158809cf4f3c")
    private let iv = hexBytes("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    private let plain = hexBytes("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    private let encrypted = hexBytes("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee")

    func testNistCtrVectorsAcrossEveryUnalignedRange() throws {
        let prefix = [UInt8](repeating: 0x66, count: 23)
        let source = prefix + encrypted + [UInt8](repeating: 0x77, count: 12)
        let expected = prefix + plain + [UInt8](repeating: 0x77, count: 12)
        let prepared = MediaCrypto.Prepared(header: [], samples: [.init(start: 23, end: 87, iv: iv, encryptedOffset: 0)])
        for start in source.indices {
            for length in 1...min(29, source.count - start) {
                let result = try MediaCrypto.decrypt(
                    Array(source[start..<(start + length)]),
                    start: UInt64(start), key: key, prepared: prepared)
                XCTAssertEqual(result, Array(expected[start..<(start + length)]), "\(start)+\(length)")
            }
        }
    }

    func testSubsamplesPreserveClearBytesAndContinueCtrOffset() throws {
        let source = [UInt8]([1, 2, 3]) + Array(encrypted[0..<21]) + [UInt8]([4, 5]) + Array(encrypted[21..<64])
        let expected = [UInt8]([1, 2, 3]) + Array(plain[0..<21]) + [UInt8]([4, 5]) + Array(plain[21..<64])
        let prepared = MediaCrypto.Prepared(header: [], samples: [
            .init(start: 3, end: 24, iv: iv, encryptedOffset: 0),
            .init(start: 26, end: 69, iv: iv, encryptedOffset: 21),
        ])
        XCTAssertEqual(try MediaCrypto.decrypt(source, start: 0, key: key, prepared: prepared), expected)
        XCTAssertEqual(
            try MediaCrypto.decrypt(Array(source[22..<47]), start: 22, key: key, prepared: prepared),
            Array(expected[22..<47]))
    }

    // MARK: - MP4 fixture

    private func box(_ type: String, _ body: [UInt8]) -> [UInt8] {
        be32(UInt32(body.count + 8)) + [UInt8](type.utf8) + body
    }

    private func fixture(codec: String = "avc1", auxSize: Int = 8) -> [UInt8] {
        let ftyp = box("ftyp", [UInt8]("isom0000".utf8))
        func moov(offset: Int) -> [UInt8] {
            let entry = box("encv", [UInt8](repeating: 0, count: 78) + box("sinf", box("frma", [UInt8](codec.utf8))))
            let stsd = box("stsd", [UInt8](repeating: 0, count: 4) + be32(1) + entry)
            let stsz = box("stsz", [UInt8](repeating: 0, count: 4) + be32(16) + be32(1))
            let stsc = box("stsc", [UInt8](repeating: 0, count: 4) + be32(1) + be32(1) + be32(1) + be32(1))
            let stco = box("stco", [UInt8](repeating: 0, count: 4) + be32(1) + be32(4096))
            let saiz = box("saiz", [UInt8](repeating: 0, count: 4) + [UInt8(auxSize)] + be32(1))
            let saio = box("saio", [UInt8](repeating: 0, count: 4) + be32(1) + be32(UInt32(offset)))
            return box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd + stsz + stsc + stco + saiz + saio)))) + box("free", Array(iv.prefix(8))))
        }
        let initial = ftyp + moov(offset: 0)
        return ftyp + moov(offset: initial.count - 8)
    }

    func testHeaderRestoresOriginalAvcCodecAndSampleIndex() throws {
        let data = fixture()
        let prepared = try MediaCrypto.prepare(data, key: key)
        let headerText = String(decoding: prepared.header, as: UTF8.self)
        XCTAssertTrue(headerText.contains("avc1"), "header 片段: [\(headerText.prefix(120))]")
        XCTAssertFalse(headerText.contains("encv"))
        XCTAssertFalse(headerText.contains("sinf"))
        XCTAssertEqual(prepared.samples.count, 1)
        XCTAssertEqual(prepared.samples[0].start, 4096)
        XCTAssertEqual(prepared.samples[0].end, 4112)
        XCTAssertEqual(try MediaCrypto.headerEnd(data, total: 5000), data.count)
    }

    func testTruncatedAuxiliaryDataFailsClosed() {
        XCTAssertThrowsError(try MediaCrypto.prepare(fixture(auxSize: 16), key: key))
    }

    func testOversizedMoovRejected() {
        XCTAssertThrowsError(try MediaCrypto.headerEnd(
            box("ftyp", [UInt8]("isom0000".utf8)) + be32(9000000) + [UInt8]("moov".utf8),
            total: 10000000))
    }

    func testRouterParserHandlesEscapedQuotesAndNestedBraces() throws {
        let html = "<script>window._ROUTER_DATA = {\"loaderData\":{\"x\":\"a}\\\"b\",\"list\":[1,2]}};</script>"
        let root = try ContentRepository.extractRouter(html)
        let loader = root["loaderData"] as? [String: Any]
        XCTAssertEqual(loader?["x"] as? String, "a}\"b")
    }
}

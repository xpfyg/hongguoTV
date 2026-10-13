import XCTest
@testable import HongguoTV

final class SM3Tests: XCTestCase {
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// GM/T 0004-2012 附录标准向量：sm3("abc")
    func testStandardVectorABC() {
        XCTAssertEqual(
            hex(SM3.digest(Data("abc".utf8))),
            "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0")
    }

    /// GM/T 0004-2012 附录标准向量：sm3("abcd" x 16)，正好一个 64 字节块
    func testStandardVectorSingleBlock() {
        let input = Data((0..<16).flatMap { _ in Array("abcd".utf8) })
        XCTAssertEqual(
            hex(SM3.digest(input)),
            "debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732")
    }

    /// 空输入
    func testEmptyInput() {
        XCTAssertEqual(
            hex(SM3.digest(Data())),
            "1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b")
    }

    /// 跨 64 字节块边界的输入（2 个块："abcd" x 32 = 128 字节）
    func testTwoBlocks() {
        let input = Data((0..<32).flatMap { _ in Array("abcd".utf8) })
        XCTAssertEqual(
            hex(SM3.digest(input)),
            "90d52a2e85631a8d6035262626941fa11b85ce570cec1e3e991e2dd7ed258148")
    }

    /// 流式 Hasher 与一次性 digest 结果一致（分片随机打散）
    func testStreamingHasherMatchesOneShot() {
        let input = Data((0..<64).flatMap { _ in Array("abcdefgh".utf8) })  // 512 字节
        var hasher = SM3.Hasher()
        let splits = [3, 61, 100, 256, 64, 28]
        var offset = 0
        for len in splits {
            hasher.update(input.subdata(in: offset..<offset + len))
            offset += len
        }
        XCTAssertEqual(hex(hasher.finalize()), hex(SM3.digest(input)))
    }
}

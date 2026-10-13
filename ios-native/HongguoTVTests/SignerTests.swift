import XCTest
@testable import HongguoTV

/// 签名算法对照测试：与 Kotlin SignerTest 完全一致——
/// 每行独立 LCG（seed=17），调用顺序 branch → hashF13 → gorgon(42131) → helios → medusa。
/// 期望值来自 Node 版预生成的 signing.json（oracle）。
final class SignerTests: XCTestCase {
    func testMatchesPinnedJavaScriptOracleAcrossTimestampVariants() throws {
        guard let url = Bundle(for: SignerTests.self).url(forResource: "signing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("signing.json 缺失或无法解析")
            return
        }
        for (i, row) in rows.enumerated() {
            let ts = UInt32(row["ts"] as? Int ?? 0)
            let url = row["url"] as? String ?? ""
            let query = url.split(separator: "?", maxSplits: 1).last.map(String.init) ?? ""
            let body: [UInt8]? = (row["body"] as? String).map { [UInt8]($0.utf8) }

            var seed: UInt64 = 17
            let signer = Signer(
                clock: { UInt64(ts) * 1000 },
                random: {
                    seed = (seed &* 1664525 &+ 1013904223) & 0xffffffff
                    return Double(seed) / 4294967296.0
                }
            )
            XCTAssertEqual(signer.branch(query, body, ts), 0, "branch \(i)")
            XCTAssertEqual(
                signer.hashF13(
                    SM3.digest(Data(query.utf8)).map { $0 },
                    body.map { md5($0) } ?? [UInt8](repeating: 0, count: 16),
                    ts
                ).hexStr,
                row["hash"] as? String ?? "",
                "hash \(i)"
            )
            XCTAssertEqual(signer.gorgon(query, body, ts, 42131), row["gorgon"] as? String ?? "", "gorgon \(i)")
            XCTAssertEqual(signer.helios(ts), row["helios"] as? String ?? "", "helios \(i)")
            XCTAssertEqual(signer.medusa(url, body, ts), row["medusa"] as? String ?? "", "medusa \(i)")
        }
    }
}

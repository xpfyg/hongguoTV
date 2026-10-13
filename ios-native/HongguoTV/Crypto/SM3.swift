// SM3 国密哈希封装。
// 底层实现来自 GmSSL（Apache-2.0），仅抽取 sm3.c / sm3.h / endian.h / error.h，
// 上游 commit 24ae482701a7b124826c382fffc55c19f76d475d，见 gmssl/LICENSE。
// 只暴露 sm3_init / sm3_update / sm3_finish；流式场景可用 SM3.Hasher，单次摘要用 SM3.digest(_:)。
import Foundation

enum SM3 {
    /// SM3 摘要长度（字节），对应 C 头文件的 SM3_DIGEST_SIZE
    static let digestSize = 32

    /// 一次性计算 SM3 摘要（GM/T 0004-2012）
    static func digest(_ data: Data) -> Data {
        var ctx = SM3_CTX()
        sm3_init(&ctx)
        data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            sm3_update(&ctx, base.assumingMemoryBound(to: UInt8.self), data.count)
        }
        var out = [UInt8](repeating: 0, count: digestSize)
        sm3_finish(&ctx, &out)
        return Data(out)
    }

    /// 流式哈希，支持分片喂入，适合大输入
    struct Hasher {
        private var ctx = SM3_CTX()
        private var finished = false

        init() {
            sm3_init(&ctx)
        }

        mutating func update(_ data: Data) {
            precondition(!finished, "SM3.Hasher 已 finalize，不能继续 update")
            data.withUnsafeBytes { buf in
                guard let base = buf.baseAddress else { return }
                sm3_update(&ctx, base.assumingMemoryBound(to: UInt8.self), data.count)
            }
        }

        mutating func finalize() -> Data {
            precondition(!finished, "SM3.Hasher 已 finalize")
            finished = true
            var out = [UInt8](repeating: 0, count: SM3.digestSize)
            sm3_finish(&ctx, &out)
            return Data(out)
        }
    }
}

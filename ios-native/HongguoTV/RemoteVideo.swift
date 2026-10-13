// 单路播放流：Range 拉取 + CENC 分段解密，解密字节直接交给播放器。
// Kotlin 移植自 kotlin-tv/core/RemoteVideo.kt（GPL-3.0-only）。不监听任何端口、不起本地 HTTP 服务。
// 同步接口（信号量桥接 async URLSession），适配 AVAssetResourceLoaderDelegate 的同步回调。
import Foundation

final class RemoteVideo {
    struct RangeResult {
        let bytes: [UInt8]
        let total: UInt64
    }

    private let info: StreamInfo
    private let session: URLSession
    private var closed = false
    private(set) var total: UInt64 = 0
    private var prepared: MediaCrypto.Prepared?
    private var prefix: [UInt8] = []
    private let lock = NSLock()

    init(info: StreamInfo, session: URLSession = .shared) {
        self.info = info
        self.session = session
    }

    // MARK: - 同步 HTTP

    private func syncRequest(_ url: URL, headers: [(String, String)]) throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>?
        let task = session.dataTask(with: request) { data, resp, error in
            if let error {
                result = .failure(error)
            } else if let data, let resp = resp as? HTTPURLResponse {
                result = .success((data, resp))
            } else {
                result = .failure(ContentError.network("播放请求失败"))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        switch result! {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    private func parseContentRange(_ s: String) -> (UInt64, UInt64, UInt64)? {
        guard let start = s.range(of: "bytes "),
              let dash = s[start.upperBound...].range(of: "-"),
              let slash = s[dash.upperBound...].range(of: "/") else { return nil }
        guard let b = UInt64(s[start.upperBound..<dash.lowerBound]),
              let e = UInt64(s[dash.upperBound..<slash.lowerBound]),
              let f = UInt64(s[slash.upperBound...]) else { return nil }
        return (b, e, f)
    }

    private func range(start: UInt64, end: UInt64) throws -> RangeResult {
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed { throw ContentError.network("播放请求已取消") }
        guard start <= end, end - start < 8 * 1024 * 1024 else {
            throw ContentError.format("分段范围异常")
        }
        guard let url = URL(string: info.url) else { throw ContentError.network("播放地址无效") }
        let headers: [(String, String)] = [
            ("User-Agent", VendorConstants.videoUA),
            ("Referer", "https://novel.snssdk.com/"),
            ("Range", "bytes=\(start)-\(end)"),
            ("Accept-Encoding", "identity"),
        ]
        let (data, resp) = try syncRequest(url, headers: headers)
        guard resp.statusCode == 206 else {
            throw ContentError.network("视频服务器不支持分段读取（HTTP \(resp.statusCode)）")
        }
        guard let contentRange = resp.value(forHTTPHeaderField: "Content-Range"),
              let (begin, finish, size) = parseContentRange(contentRange) else {
            throw ContentError.format("视频分段响应异常")
        }
        guard size > 0, begin == start, finish == min(end, size - 1) else {
            throw ContentError.format("视频分段范围不匹配")
        }
        lock.lock()
        let current = total
        lock.unlock()
        if current != 0 && size != current {
            throw ContentError.format("视频资源已变化，请重试")
        }
        return RangeResult(bytes: [UInt8](data), total: size)
    }

    // MARK: - 播放流

    @discardableResult
    func prepare() throws -> RemoteVideo {
        if prepared != nil { return self }
        let first = try range(start: 0, end: 256 * 1024 - 1)
        total = first.total
        prefix = first.bytes
        let end = try MediaCrypto.headerEnd(first.bytes, total: total)
        let header: [UInt8]
        if end > first.bytes.count {
            header = first.bytes + (try range(start: UInt64(first.bytes.count), end: UInt64(end) - 1)).bytes
        } else {
            header = Array(first.bytes.prefix(end))
        }
        let parsed = try MediaCrypto.prepare(header, key: info.key)
        if parsed.samples.contains(where: { $0.end > total }) {
            throw ContentError.format("视频样本超出资源大小")
        }
        prepared = parsed
        return self
    }

    /// 有界预热：保留原始字节，解密仍使用绝对样本偏移
    @discardableResult
    func warm() throws -> RemoteVideo {
        try prepare()
        let size = min(total, 1024 * 1024)
        let current = UInt64(prefix.count)
        if current < size {
            prefix += (try range(start: current, end: size - 1)).bytes
        }
        return self
    }

    func read(start: UInt64, length: Int) throws -> [UInt8] {
        guard length >= 1 && length <= 1024 * 1024 else { throw ContentError.format("读取长度异常") }
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed { throw ContentError.network("播放请求已取消") }
        guard let prepared else { throw ContentError.format("播放流未准备") }
        if start >= total { return [] }
        let end = min(total, start &+ UInt64(length))
        let prefixEnd = min(end, UInt64(prefix.count))
        let available = Int(prefixEnd >= start ? prefixEnd - start : 0)
        let cached = available > 0 ? Array(prefix[Int(start)..<(Int(start) + available)]) : []
        let raw: [UInt8]
        if start &+ UInt64(available) < end {
            raw = cached + (try range(start: start &+ UInt64(available), end: end - 1)).bytes
        } else {
            raw = cached
        }
        return try MediaCrypto.decrypt(raw, start: start, key: info.key, prepared: prepared)
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}

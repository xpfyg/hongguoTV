import AVFoundation
import Foundation

/// cenc:// 自定义 scheme 的资源加载器：Range 拉取源站 + CENC 分段解密，解密字节直接交给 AVPlayer。
/// tvOS 的 AVURLAsset 对自定义 scheme 必须提供 delegate，本 loader 是唯一播放通道。
/// 不监听任何端口、不起本地 HTTP 服务（与 Kotlin 版 "No listening socket" 一致）。
final class CENCResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = CENCResourceLoader()
    static let scheme = "cenc"

    /// StreamInfo 经 UserDefaults JSON 桥接：loader 回调可能在任意队列执行，不直接依赖 @MainActor 状态
    private static let streamKey = "hongguotv.cencStream"

    private let lock = NSLock()
    private var remote: RemoteVideo?

    static func store(_ info: StreamInfo) {
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: streamKey)
        }
    }

    private func takeStream() throws -> StreamInfo {
        guard let data = UserDefaults.standard.data(forKey: Self.streamKey),
              let info = try? JSONDecoder().decode(StreamInfo.self, from: data) else {
            throw ContentError.format("播放流信息缺失")
        }
        return info
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        do {
            let info = try takeStream()
            let video = RemoteVideo(info: info)
            lock.lock()
            remote = video
            lock.unlock()
            try video.prepare()
            handle(loadingRequest, video: video)
        } catch {
            loadingRequest.finishLoading(with: error)
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        do {
            let info = try takeStream()
            let video = RemoteVideo(info: info)
            lock.lock()
            remote = video
            lock.unlock()
            try video.prepare()
            handle(renewalRequest, video: video)
        } catch {
            renewalRequest.finishLoading(with: error)
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock()
        remote?.close()
        remote = nil
        lock.unlock()
    }

    // MARK: - 数据供应

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest, video: RemoteVideo) {
        if let contentInfo = loadingRequest.contentInformationRequest {
            contentInfo.contentLength = Int64(video.total)
            contentInfo.isByteRangeAccessSupported = true
            contentInfo.contentType = AVFileType.mp4.rawValue
        }
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return
        }
        var offset = Int64(dataRequest.requestedOffset)
        if offset < 0 { offset = Int64(video.total) + offset }
        if offset < 0 { offset = 0 }
        var remaining = Int64(dataRequest.requestedLength)
        let allToEnd = dataRequest.requestsAllDataToEndOfResource
        do {
            while loadingRequest.isCancelled == false {
                let toRead: Int
                if allToEnd {
                    toRead = 1024 * 1024
                } else if remaining > 0 {
                    toRead = Int(min(remaining, Int64(1024 * 1024)))
                } else {
                    break
                }
                let bytes = try video.read(start: UInt64(offset), length: toRead)
                if bytes.isEmpty { break }
                dataRequest.respond(with: Data(bytes))
                offset += Int64(bytes.count)
                if !allToEnd { remaining -= Int64(bytes.count) }
            }
            if loadingRequest.isCancelled {
                loadingRequest.finishLoading()
            } else {
                dataRequest.respond(with: Data())
                loadingRequest.finishLoading()
            }
        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }
}

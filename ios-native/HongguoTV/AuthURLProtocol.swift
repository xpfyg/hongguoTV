import Foundation

// MARK: - 鉴权流 URLProtocol
// tvOS 的 AVPlayer 不支持 AVURLAssetHTTPHeaderFieldsKey，无法给流请求注入鉴权头。
// 方案：把 http:// 换成自定义 scheme authstream://，由本 URLProtocol 接管，
// 转发真实请求时注入 Authorization: Bearer <token>，再交给 AVPlayer 播放。

final class AuthURLProtocol: URLProtocol, URLSessionDataDelegate {
    static let scheme = "authstream"

    /// 鉴权口令经 UserDefaults 桥接（URLProtocol 为非隔离上下文，不能直接读 @MainActor 状态）
    private static var token: String? {
        UserDefaults.standard.string(forKey: "hongguotv.authToken")
    }

    private var sessionTask: URLSessionDataTask?
    private var session: URLSession?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == scheme
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /// 把 authstream:// 还原成 http://
    private var realURL: URL? {
        guard var comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "http"
        return comps.url
    }

    override func startLoading() {
        guard let realURL else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var req = URLRequest(url: realURL)
        // 保留 AVPlayer 的原始头（Range、User-Agent 等）
        req.allHTTPHeaderFields = request.allHTTPHeaderFields
        if let token = AuthURLProtocol.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        sessionTask = session.dataTask(with: req)
        sessionTask?.resume()
    }

    override func stopLoading() {
        sessionTask?.cancel()
        sessionTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: URLSessionDataDelegate（流式转发）

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        sessionTask = nil
        self.session = nil
    }
}

import Foundation

/// 直连源站的内容客户端：替代 APIClient（Node bridge）。
/// 内容来自官网页面 + fqnovel App 接口，播放流由 CENCResourceLoader 直供解密字节。
/// 方法签名与旧 APIClient 保持兼容，UI 层只替换构造即可。
struct ContentClient {
    private let repo: ContentRepository

    init(session: URLSession = .shared) {
        repo = ContentRepository(session: session)
    }

    /// 直连自检（替代旧 /health）
    func health() async throws -> String {
        let page = try await repo.home(page: 1)
        guard !page.items.isEmpty else { throw ContentError.format("直连源站无内容") }
        return "直连模式（官网 + fqnovel App 接口）"
    }

    func home(page: Int) async throws -> [Series] {
        try await repo.home(page: page).items
    }

    func category(typeId: String, page: Int) async throws -> (name: String, items: [Series]) {
        try await repo.category(typeId: typeId, page: page)
    }

    func actorSearch(query: String, page: Int) async throws -> (actor: ActorProfile?, items: [Series]) {
        try await repo.actorSearch(keyword: query, page: page)
    }

    func search(query: String, page: Int) async throws -> [Series] {
        try await repo.search(keyword: query, page: page).items
    }

    func detail(id: String) async throws -> Detail {
        try await repo.detail(id: id)
    }

    /// 解析播放流：StreamInfo 经 UserDefaults 桥接给 CENCResourceLoader，返回 cenc:// 播放 URI
    func play(episodeId: String, fresh: Bool = false) async throws -> PlaybackInfo {
        let stream = try await repo.stream(id: episodeId, maxQuality: 1080)
        CENCResourceLoader.store(stream)
        return PlaybackInfo(uri: "cenc://\(episodeId)", headers: [:])
    }
}

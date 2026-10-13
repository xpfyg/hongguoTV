import Foundation

// MARK: - 数据契约（与服务端 Node 接口 /api/home、/api/search、/api/series/:id、/api/episodes/:id/play|stream 对齐）

struct Series: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let cover: String
    let description: String
    let badge: String
    let tags: String
}

struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
}

struct Celebrity: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let avatar: String
}

struct Detail: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let cover: String
    let description: String
    let badge: String
    let tags: String
    // 兼容旧服务端进程不返回该字段
    let celebrities: [Celebrity]?
    let episodes: [Episode]
}

struct Progress: Codable, Hashable {
    var series: Series
    var episodeId: String
    var episodeNumber: Int
    var position: Double
    var duration: Double
    var completed: Bool
    var updatedAt: Double
}

struct Library: Codable {
    var favorites: [Series] = []
    var progress: [String: Progress] = [:]
}

struct Settings: Codable {
    var baseUrl: String = "http://localhost:8787"
    var token: String = ""
}

struct PlaybackInfo: Codable {
    let uri: String
    let headers: [String: String]
}

// MARK: - API 响应包装

struct HealthResponse: Codable {
    let service: String
    let version: String
    let apiVersion: Int
    let upstream: String
}

struct PlayResponse: Codable {
    let path: String
    let contentType: String
}

struct ErrorResponse: Codable {
    let error: String
}

import Foundation

// MARK: - 内容服务 API 客户端（HTTP，Bearer 可选口令）

enum APIError: LocalizedError {
    case badURL
    case transport(Error)
    case http(Int, String)
    case decode(Error)
    case unexpected

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务地址无效"
        case .transport(let e): return "网络错误：\(e.localizedDescription)"
        case .http(let code, let msg): return msg.isEmpty ? "请求失败（HTTP \(code)）" : msg
        case .decode(let e): return "响应解析失败：\(e.localizedDescription)"
        case .unexpected: return "未知错误"
        }
    }
}

struct APIClient {
    var baseUrl: String
    var token: String

    private var session: URLSession { URLSession.shared }

    private var headers: [String: String] {
        var h: [String: String] = [:]
        if !token.isEmpty { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    private func request(path: String) async throws -> Data {
        guard let url = URL(string: baseUrl + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode >= 400 {
                    let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? ""
                    throw APIError.http(http.statusCode, message)
                }
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error)
        }
    }

    func health() async throws -> HealthResponse {
        let data = try await request(path: "/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func home(page: Int) async throws -> [Series] {
        let data = try await request(path: "/api/home?page=\(page)")
        let list = try JSONDecoder().decode(ListResponse.self, from: data)
        return list.items
    }

    /// 大分类内容：/api/category/:typeId?page=N，返回分类名与剧集列表
    func category(typeId: String, page: Int) async throws -> (name: String, items: [Series]) {
        let data = try await request(path: "/api/category/\(typeId)?page=\(page)")
        let resp = try JSONDecoder().decode(CategoryResponse.self, from: data)
        return (resp.typeName, resp.items)
    }

    func search(query: String, page: Int) async throws -> [Series] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let data = try await request(path: "/api/search?q=\(q)&page=\(page)")
        let list = try JSONDecoder().decode(ListResponse.self, from: data)
        return list.items
    }

    func detail(id: String) async throws -> Detail {
        let data = try await request(path: "/api/series/\(id)")
        return try JSONDecoder().decode(Detail.self, from: data)
    }

    /// 解析播放地址：调用 play 接口拿到 stream 路径，拼成完整 URL，并附带鉴权头
    func play(episodeId: String, fresh: Bool = false) async throws -> PlaybackInfo {
        let suffix = fresh ? "?fresh=1" : ""
        let data = try await request(path: "/api/episodes/\(episodeId)/play\(suffix)")
        let play = try JSONDecoder().decode(PlayResponse.self, from: data)
        guard let url = URL(string: baseUrl + play.path) else { throw APIError.badURL }
        return PlaybackInfo(uri: url.absoluteString, headers: headers)
    }

    private struct ListResponse: Codable {
        let items: [Series]
    }

    private struct CategoryResponse: Codable {
        let typeId: String
        let typeName: String
        let items: [Series]
        enum CodingKeys: String, CodingKey {
            case typeId = "type_id"
            case typeName = "type_name"
            case items
        }
    }
}

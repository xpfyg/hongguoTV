// 内容仓库：直连源站（hongguoduanju.com + fqnovel App 接口），替代 Node bridge。
// Kotlin 移植自 kotlin-tv/core/ContentRepository.kt（GPL-3.0-only），榜单/演员逻辑对齐 server/provider.mjs。
import Foundation

// MARK: - 模型

enum ContentType: Int {
    case short = 11
    case human = 12
    case comic = 13
    case ai = 14

    var searchTab: Int { rawValue }
    var label: String {
        switch self {
        case .short: return "短剧"
        case .human: return "真人剧"
        case .comic: return "漫剧"
        case .ai: return "AI剧"
        }
    }
}

struct CatalogPage {
    let items: [Series]
    let hasMore: Bool
}

struct StreamInfo: Codable {
    let url: String
    let key: [UInt8]?
    let quality: String
}

enum ContentError: LocalizedError, Equatable {
    case network(String)
    case format(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .format(let m): return m
        case .sessionExpired: return "搜索结果已过期，请从第 1 页重新搜索"
        }
    }
}

// MARK: - JSON 辅助

private func str(_ d: [String: Any], _ key: String) -> String {
    if let v = d[key] as? String { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let v = d[key] as? NSNumber { return "\(v)" }
    return ""
}

private func optInt(_ d: [String: Any], _ key: String) -> Int {
    (d[key] as? NSNumber)?.intValue ?? 0
}

// MARK: - 内容仓库

final class ContentRepository {
    let site = "https://hongguoduanju.com"
    private let signer = Signer()
    private let session: URLSession
    private let clock: () -> UInt64

    private struct SearchCursor {
        let searchId: String
        let passback: String
        let offset: Int?
        let updatedAt: UInt64
    }
    private var searchCursors: [String: SearchCursor] = [:]
    private let cursorLock = NSLock()

    init(session: URLSession? = nil, clock: @escaping () -> UInt64 = { UInt64(Date().timeIntervalSince1970 * 1000) }) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: config)
        self.clock = clock
    }

    // MARK: - 网络

    private func text(url: String, signed: SignedRequest? = nil) async throws -> String {
        guard let u = URL(string: url) else { throw ContentError.network("服务地址无效") }
        var request = URLRequest(url: u)
        request.setValue(VendorConstants.videoUA, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (k, v) in signed?.headers ?? [] {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let body = signed?.body {
            request.httpMethod = "POST"
            request.httpBody = Data(body)
        }
        let (data, resp) = try await session.data(for: request)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw ContentError.network("内容请求失败（HTTP \(http.statusCode)）")
        }
        guard data.count <= 16 * 1024 * 1024 else { throw ContentError.format("内容响应过大") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func router(_ url: String) async throws -> [String: Any] {
        let html = try await text(url: url)
        let root = try Self.extractRouter(html)
        return (root["loaderData"] as? [String: Any]) ?? [:]
    }

    // MARK: - 卡片与清洗

    private func card(_ item: [String: Any]) -> Series {
        let o = (item["video_data"] as? [String: Any]) ?? item
        let episodeInfo = (o["series_episode_info"] as? [String: Any])?["episode_cnt"] as? NSNumber
        let count = (o["episode_cnt"] as? NSNumber)?.intValue ?? episodeInfo?.intValue ?? 0
        let tags = (o["tags"] as? [Any]) ?? (o["category_list"] as? [Any]) ?? []
        let name = str(o, "series_name")
        let title = name.isEmpty ? (str(o, "series_title").isEmpty ? str(item, "name") : str(o, "series_title")) : name
        let rightText = str(o, "episode_right_text")
        let badge = rightText.isEmpty ? (count > 0 ? "全 \(count) 集" : "") : rightText
        let tagStr = tags.prefix(5).map { tag -> String in
            if let t = tag as? [String: Any] { return str(t, "name") }
            return "\(tag)"
        }.joined(separator: " · ")
        return Series(
            id: str(o, "series_id"),
            title: title,
            cover: Self.cleanUrl(str(o, "series_cover")),
            description: str(o, "series_intro"),
            badge: badge,
            tags: tagStr
        )
    }

    private func valid(_ rows: [Series]) -> [Series] {
        var seen = Set<String>()
        return rows.filter { row in
            guard row.id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil, !row.title.isEmpty else { return false }
            return seen.insert(row.id).inserted
        }
    }

    // MARK: - 首页 / 分类 / 榜单

    func home(page: Int = 1) async throws -> CatalogPage {
        guard page >= 1 && page <= 100 else { throw ContentError.format("页码无效") }
        let data = try await router("\(site)/")
        guard let homeSections = (data["page"] as? [String: Any])?["homeSections"] as? [Any] else {
            throw ContentError.format("首页数据不可用")
        }
        guard let section = homeSections.compactMap({ $0 as? [String: Any] }).first(where: { ($0["tab_type"] as? String) == "all" }),
              let videoList = section["video_list"] as? [Any] else {
            throw ContentError.format("首页分类数据不可用")
        }
        let items = valid(videoList.compactMap { ($0 as? [String: Any]).map(card) })
        return CatalogPage(items: items, hasMore: !items.isEmpty && page < 100)
    }

    private static let categoryConfig: [String: (name: String, kind: String, route: String)] = [
        "short": ("短剧", "home", "all"),
        "human": ("真人剧", "category", "real-drama"),
        "comic": ("漫剧", "category", "comic-drama"),
        "ai": ("AI剧", "category", "ai-drama"),
        "rank_hot": ("红果热播榜", "rank", "hot-drama"),
        "rank_human": ("真人剧热播榜", "rank", "hot-real-drama"),
        "rank_comic": ("漫剧热播榜", "rank", "hot-comic-drama"),
        "rank_ai": ("AI剧热播榜", "rank", "hot-ai-drama"),
    ]

    func category(typeId: String, page: Int = 1) async throws -> (name: String, items: [Series]) {
        guard let config = Self.categoryConfig[typeId] else { throw ContentError.format("不支持的分类") }
        let items: [Series]
        switch config.kind {
        case "home":
            let data = try await router("\(site)/")
            guard let homeSections = (data["page"] as? [String: Any])?["homeSections"] as? [Any],
                  let section = homeSections.compactMap({ $0 as? [String: Any] }).first(where: { ($0["tab_type"] as? String) == config.route }),
                  let videoList = section["video_list"] as? [Any] else {
                throw ContentError.format("首页分类数据不可用")
            }
            items = valid(videoList.compactMap { ($0 as? [String: Any]).map(card) })
        case "category":
            let data = try await router("\(site)/category/\(config.route)\(page > 1 ? "?page=\(page)" : "")")
            let pageData = (data["category_$"] as? [String: Any]) ?? (data["category_page"] as? [String: Any])
            guard let recommendList = pageData?["recommendList"] as? [Any] else { throw ContentError.format("分类数据不可用") }
            items = valid(recommendList.compactMap { ($0 as? [String: Any]).map(card) })
        default:
            items = try await rankPage(route: config.route, page: page)
        }
        return (config.name, items)
    }

    /// 官网榜单：HTML 内嵌 data-fn-args（可能被壳页面降级，最多重试 3 次）
    func rankPage(route: String, page: Int = 1) async throws -> [Series] {
        guard ["hot-drama", "hot-real-drama", "hot-comic-drama", "hot-ai-drama"].contains(route) else {
            throw ContentError.format("不支持的榜单")
        }
        let suffix = page > 1 ? "?page=\(page)" : ""
        var inner: [String: Any]? = nil
        for attempt in 1...3 {
            if attempt > 1 { try await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000) }
            let html = try await text(url: "\(site)/rank/\(route)\(suffix)")
            guard let start = html.range(of: "data-fn-args=\"") else { continue }
            let valueStart = start.upperBound
            guard let valueEnd = html[valueStart...].range(of: "\"") else { continue }
            let encoded = String(html[valueStart..<valueEnd.lowerBound])
            let decoded = Self.decodeHtml(encoded)
            guard let payload = try? JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [Any],
                  payload.count > 1,
                  let block = payload[1] as? [Any], !block.isEmpty,
                  let content = block[0] as? [String: Any],
                  let routerArgs = content["routerDataFnArgs"] as? [Any], !routerArgs.isEmpty,
                  let json = routerArgs[0] as? String,
                  let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                continue
            }
            inner = parsed
            if (parsed["isSuccess"] as? Bool) == true { break }
        }
        guard let inner, (inner["isSuccess"] as? Bool) == true, let rankList = inner["rankList"] as? [Any] else {
            throw ContentError.format("榜单数据格式错误")
        }
        let items = rankList.compactMap { item -> Series? in
            guard let it = item as? [String: Any] else { return nil }
            let mapped: [String: Any] = [
                "series_id": it["seriesId"] ?? it["series_id"] ?? it["id"] ?? "",
                "series_name": it["title"] ?? it["seriesTitle"] ?? it["series_name"] ?? "",
                "series_cover": it["cover"] ?? it["seriesCover"] ?? it["series_cover"] ?? "",
                "series_intro": it["description"] ?? it["intro"] ?? it["seriesIntro"] ?? it["summary"] ?? "",
                "episode_cnt": it["episodeCount"] ?? it["episode_cnt"] ?? 0,
                "tags": it["tags"] ?? [],
            ]
            return card(mapped)
        }
        return valid(items)
    }

    // MARK: - 搜索

    func search(keyword: String, page: Int = 1) async throws -> CatalogPage {
        guard !keyword.isEmpty, keyword.count <= 80, page >= 1 && page <= 100 else {
            throw ContentError.format("搜索参数无效")
        }
        // App 搜索优先（短剧）；官网搜索不约束内容类型，漫剧不可用它
        do {
            let result = try await appSearch(keyword: keyword, page: page, type: .short)
            if !result.items.isEmpty || !result.hasMore { return result }
        } catch let e as ContentError where e == .sessionExpired {
            throw e
        } catch {
            /* 官网回退（仅限短剧） */
        }
        let data = try await router("\(site)/search/\(Signer.urlEncode(keyword))?page=\(page)")
        let pageData = (data["search_(keyword)/page"] as? [String: Any]) ?? (data["search_page"] as? [String: Any])
        guard let rows = pageData?["searchList"] as? [Any] else { throw ContentError.format("搜索数据暂不可用") }
        let items = valid(rows.compactMap { ($0 as? [String: Any]).map(card) })
        return CatalogPage(items: items, hasMore: !items.isEmpty && page < 100)
    }

    /// fqnovel App 搜索（签名请求，分页 cursor 由 search_id/passback/offset 维持）
    private func appSearch(keyword: String, page: Int, type: ContentType) async throws -> CatalogPage {
        var values = VendorConstants.device
        for key in ["version_code", "manifest_version_code", "update_version_code", "pv_player"] {
            if let idx = values.firstIndex(where: { $0.0 == key }) { values[idx] = (key, "72232") }
        }
        if let idx = values.firstIndex(where: { $0.0 == "version_name" }) { values[idx] = ("version_name", "7.2.2.32") }
        values += [
            ("query", keyword), ("count", "20"), ("offset", String((page - 1) * 20)),
            ("tab_type", String(type.searchTab)), ("bookshelf_search_plan", "4"),
            ("use_correct", "true"), ("user_is_login", "0"),
        ]

        let cursorKey = "\(type.rawValue)|\(keyword)|\(page - 1)"
        let cursor: SearchCursor?
        cursorLock.lock()
        let now = clock()
        searchCursors = searchCursors.filter { now - $0.value.updatedAt <= 300_000 }
        if page == 1 {
            searchCursors = searchCursors.filter { !$0.key.hasPrefix("\(type.rawValue)|\(keyword)|") }
        }
        cursor = searchCursors[cursorKey]
        cursorLock.unlock()

        if type == .comic && page > 1 && cursor == nil { throw ContentError.sessionExpired }
        if let c = cursor {
            if !c.searchId.isEmpty { values.append(("search_id", c.searchId)) }
            if !c.passback.isEmpty { values.append(("passback", c.passback)) }
            if let offset = c.offset, offset >= 0 { values.append(("offset", String(offset))) }
        }

        let signed = signer.sign(base: "https://api5-normal-sinfonlinea.fqnovel.com/reading/bookapi/search/tab/v", values: values)
        let html = try await text(url: signed.url, signed: signed)
        let data = (try? JSONSerialization.jsonObject(with: Data(html.utf8)) as? [String: Any]) ?? [:]
        if optInt(data, "code") != 0 { throw ContentError.format("搜索接口暂不可用") }
        let tabs = (data["search_tabs"] as? [Any]) ?? ((data["data"] as? [String: Any])?["search_tabs"] as? [Any]) ?? []
        guard let tab = tabs.compactMap({ $0 as? [String: Any] }).first(where: { optInt($0, "tab_type") == type.searchTab }) else {
            throw ContentError.format("\(type.label)搜索暂不可用")
        }
        var list: [Series] = []
        for cell in (tab["data"] as? [Any]) ?? [] {
            guard var cellDict = cell as? [String: Any] else { continue }
            var cells: [[String: Any]] = [cellDict]
            if let lynx = cellDict["lynx_data"] as? String,
               let lynxData = try? JSONSerialization.jsonObject(with: Data(lynx.utf8)) as? [String: Any],
               let cellData = lynxData["cell_data"] as? [Any] {
                cells += cellData.compactMap { $0 as? [String: Any] }
            }
            for row in cells {
                guard let videos = row["video_data"] as? [Any],
                      let video = videos.compactMap({ $0 as? [String: Any] }).first else { continue }
                let id = str(video, "series_id").isEmpty
                    ? (str(row, "book_id").isEmpty ? str(row, "search_result_id") : str(row, "book_id"))
                    : str(video, "series_id")
                let highlight = (row["search_high_light"] as? [String: Any])?["title"] as? [String: Any]
                let highlightText = highlight.map { str($0, "text") } ?? ""
                let title = highlightText.isEmpty
                    ? (str(video, "title").isEmpty ? str(row, "cell_name") : str(video, "title"))
                    : highlightText
                let count = optInt(video, "episode_cnt")
                let cover = str(video, "cover").isEmpty ? str(video, "cover_url") : str(video, "cover")
                let badge = count > 0 ? "全 \(count) 集" : str(video, "rec_text")
                list.append(Series(id: id, title: title, cover: Self.cleanUrl(cover), description: str(video, "video_desc"), badge: badge, tags: str(video, "sub_title")))
            }
        }
        cursorLock.lock()
        let nextOffset = Int(str(tab, "next_offset"))
        searchCursors["\(type.rawValue)|\(keyword)|\(page)"] = SearchCursor(searchId: str(tab, "search_id"), passback: str(tab, "passback"), offset: nextOffset, updatedAt: clock())
        while searchCursors.count > 100 { searchCursors.removeValue(forKey: searchCursors.keys.first!) }
        cursorLock.unlock()
        let hasMore = (tab["has_more"] as? Bool ?? false) && page < 100
        return CatalogPage(items: valid(list), hasMore: hasMore)
    }

    /// 演职人员搜索：官网搜索页解析演员档案（doc_type=46）与参演剧集
    func actorSearch(keyword: String, page: Int = 1) async throws -> (actor: ActorProfile?, items: [Series]) {
        let data = try await router("\(site)/search/\(Signer.urlEncode(keyword))?page=\(page)")
        let pageData = (data["search_(keyword)/page"] as? [String: Any]) ?? (data["search_page"] as? [String: Any])
        guard let rows = pageData?["searchList"] as? [Any] else { throw ContentError.format("搜索数据不可用") }
        let entries = rows.compactMap { $0 as? [String: Any] }
        let actorEntry = entries.first { (($0["doc_type"] as? NSNumber)?.intValue ?? 0) == 46 }
        let info = (actorEntry?["user_info"] as? [String: Any]) ?? [:]
        let actor: ActorProfile? = actorEntry.map { entry in
            let subtitles = (info["subtitle_list"] as? [Any] ?? []).map { "\($0)" }
            return ActorProfile(
                id: Self.pick(info, ["actor_id", "person_id"], entry, ["keyword"]),
                name: Self.pick(info, ["user_name"], entry, ["name"]),
                avatar: str(info, "user_avatar"),
                description: str(info, "description"),
                subtitle: subtitles.joined(separator: " / ")
            )
        }
        let works = (actorEntry?["video_list"] as? [Any]) ?? []
        let items: [Series]
        if actor != nil && !works.isEmpty {
            items = valid(works.compactMap { ($0 as? [String: Any]).map(card) })
        } else {
            items = valid(entries.map(card))
        }
        return (actor, items)
    }

    // MARK: - 详情

    func detail(id: String) async throws -> Detail {
        guard id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil else {
            throw ContentError.format("剧集编号无效")
        }
        let data = try await router("\(site)/detail?series_id=\(id)")
        guard let page = data["detail_page"] as? [String: Any],
              let series = page["seriesDetail"] as? [String: Any],
              let rawEpisodes = series["vid_list"] as? [Any], !rawEpisodes.isEmpty else {
            throw ContentError.format("剧集详情暂不可用")
        }
        let episodes: [Episode] = rawEpisodes.enumerated().map { i, vid in
            Episode(id: "\(vid)", number: i + 1, title: "第 \(i + 1) 集")
        }
        guard episodes.allSatisfy({ $0.id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil }),
              Set(episodes.map(\.id)).count == episodes.count else {
            throw ContentError.format("分集数据异常")
        }
        let base = card(series)
        return Detail(
            id: id,
            title: base.title,
            cover: base.cover,
            description: base.description,
            badge: base.badge,
            tags: base.tags,
            celebrities: normalizeCelebrities(series["celebrities"]),
            episodes: episodes
        )
    }

    // MARK: - 播放流

    func stream(id: String, maxQuality: Int = 1080) async throws -> StreamInfo {
        guard id.range(of: "^[0-9]{1,30}$", options: .regularExpression) != nil else {
            throw ContentError.format("剧集编号无效")
        }
        let payload = "{\"biz_param\":{\"detail_page_version\":0,\"device_level\":3,\"disable_digg_stat\":false,\"need_all_video_definition\":true,\"need_mp4_align\":false,\"use_os_player\":false,\"use_server_dns\":false,\"video_platform\":1024},\"mixed_video_id_map\":{\"1004\":[\"\(id)\"]}}"
        // 播放接口按设备维度风控：固定 device_id 会被拒（Code 110001），每集请求轮换全新 iid/device_id 绕过。
        let values = VendorConstants.device(iid: VendorConstants.randomDeviceNumber(), deviceID: VendorConstants.randomDeviceNumber())
        let signed = signer.sign(base: "https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/", values: values, body: [UInt8](payload.utf8))
        let html = try await text(url: signed.url, signed: signed)
        let data = (try? JSONSerialization.jsonObject(with: Data(html.utf8)) as? [String: Any]) ?? [:]
        let code = (data["Code"] as? NSNumber)?.intValue ?? optInt(data, "code")
        if code != 0 {
            let message = str(data, "Message").isEmpty ? str(data, "message") : str(data, "Message")
            let detail = message.isEmpty ? "（\(code)）" : "（\(code)：\(message)）"
            // 110001 为字节系设备维度风控：固定 device 被标记时源站直接拒绝
            if code == 110001 {
                throw ContentError.format("播放源临时受限\(detail)，请稍后重试")
            }
            throw ContentError.format("播放接口暂不可用\(detail)")
        }
        guard let map = data["data"] as? [String: Any] else { throw ContentError.format("播放信息为空") }
        let entry: [String: Any]
        if let e = map[id] as? [String: Any] { entry = e }
        else if let first = map.first(where: { $0.value is [String: Any] })?.value as? [String: Any] { entry = first }
        else { throw ContentError.format("播放信息为空") }
        let model: [String: Any]
        if let m = entry["video_model"] as? [String: Any] { model = m }
        else if let ms = entry["video_model"] as? String, let m = try? JSONSerialization.jsonObject(with: Data(ms.utf8)) as? [String: Any] { model = m }
        else { model = [:] }
        var fallback = ""
        if let raw = model["fallback_api"] {
            if let d = raw as? [String: Any] { fallback = str(d, "fallback_api") }
            else if let a = raw as? [Any] { fallback = a.first.map { "\($0)" } ?? "" }
            else {
                let s = "\(raw)"
                if let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] { fallback = str(d, "fallback_api") } else { fallback = s }
            }
        }
        guard fallback.hasPrefix("https://") else { throw ContentError.format("播放地址格式异常") }
        let fb = try await text(url: fallback)
        guard let info = (try? JSONSerialization.jsonObject(with: Data(fb.utf8)) as? [String: Any])?["video_info"] as? [String: Any],
              let videoInfoData = info["data"] as? [String: Any] else {
            throw ContentError.format("没有播放资源")
        }
        guard let videoList = videoInfoData["video_list"] as? [String: Any] else {
            throw ContentError.format("没有可用清晰度")
        }
        // ByteVC2 资源在部分解析器中只有音频轨；缺失旧 codec 标签仍可用，但绝不选已知不兼容变体
        let incompatible = Set(["bytevc2", "bvc2"])
        let rows: [(Int, [String: Any])] = videoList.compactMap { key, value in
            guard let o = value as? [String: Any] else { return nil }
            let mainUrl = str(o, "main_url")
            let codec = str(o, "codec_type").lowercased()
            guard !mainUrl.isEmpty, !incompatible.contains(codec) else { return nil }
            let qualityDesc = str(o, "quality_desc")
            let height = str(o, "height")
            let vheight = str(o, "vheight")
            let quality = str(o, "quality")
            let q = Self.qualityNumber(qualityDesc.isEmpty ? (height.isEmpty ? (vheight.isEmpty ? (quality.isEmpty ? key : quality) : vheight) : height) : qualityDesc)
            return (q, o)
        }.sorted { $0.0 > $1.0 }
        guard let selected = rows.first(where: { $0.0 <= maxQuality }) ?? rows.last else {
            throw ContentError.format("没有电视可播放的清晰度，请稍后再试或选择其他剧集")
        }
        let item = selected.1
        var url = Self.cleanUrl(str(item, "main_url"))
        let seed = str(videoInfoData, "key_seed")
        if !seed.isEmpty { url = try MediaCrypto.decryptUrl(url, seed: decode64(seed)) }
        guard url.hasPrefix("https://") || url.hasPrefix("http://") else { throw ContentError.format("播放地址无效") }
        let spadeA = str(item, "spade_a")
        let key: [UInt8]? = spadeA.isEmpty ? nil : try MediaCrypto.deriveKey(spadeA)
        let quality = selected.0 > 0 ? "\(selected.0)P" + (selected.0 > maxQuality ? "（兼容资源）" : "") : "自动"
        return StreamInfo(url: url, key: key, quality: quality)
    }

    // MARK: - 演职人员规范化

    private func normalizeCelebrities(_ value: Any?) -> [Celebrity] {
        guard let value = value else { return [] }
        let list: [Any]
        if let arr = value as? [Any] { list = arr }
        else if let d = value as? [String: Any] {
            if let arr = d["list"] as? [Any] { list = arr }
            else { list = (d["actors"] ?? d["celebrity_list"] ?? d["celebrities"]) as? [Any] ?? [] }
        } else { list = [] }
        return list.compactMap { item -> Celebrity? in
            let src = (item as? [String: Any]) ?? [:]
            let id = Self.firstNonEmpty(src, ["id", "celebrity_id", "actor_id", "person_id"])
            let name = Self.firstNonEmpty(src, ["name", "nickname", "actor_name", "actorName", "title"])
            let role = Self.cleanRole(Self.firstNonEmpty(src, ["role", "sub_title", "actor_role", "character", "desc"]))
            let avatar = Self.cleanUrl(Self.firstNonEmpty(src, ["avatar", "actor_avatar", "head_url", "portrait"]))
            guard !name.isEmpty || !id.isEmpty else { return nil }
            return Celebrity(id: id, name: name, role: role, avatar: avatar)
        }
    }

    // MARK: - 静态工具

    /// 按顺序返回第一个非空字符串（等价 provider.mjs 的 `a || b || c`）
    static func firstNonEmpty(_ sources: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            let v = str(sources, key)
            if !v.isEmpty { return v }
        }
        return ""
    }

    /// 先在 a 中按 aKeys 取，取不到再到 b 中按 bKeys 取
    static func pick(_ a: [String: Any], _ aKeys: [String], _ b: [String: Any], _ bKeys: [String]) -> String {
        let v = firstNonEmpty(a, aKeys)
        return v.isEmpty ? firstNonEmpty(b, bKeys) : v
    }

    static func cleanRole(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "^(出演|饰演|扮演|饰)\\s*", options: .regularExpression) {
            s.removeSubrange(range)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanUrl(_ s: String) -> String {
        s.replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func decodeHtml(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x2F;", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "&#47;", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "&#x27;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 提取页面内嵌的 _ROUTER_DATA JSON（大括号配对，正确处理转义引号）
    static func extractRouter(_ html: String) throws -> [String: Any] {
        guard let marker = html.range(of: "_ROUTER_DATA") else { throw ContentError.format("页面没有内容数据") }
        guard let first = html[marker.upperBound...].range(of: "{") else { throw ContentError.format("页面数据格式错误") }
        let start = html.distance(from: html.startIndex, to: first.lowerBound)
        let chars = Array(html)
        var depth = 0
        var quoted = false
        var escaped = false
        for i in start..<chars.count {
            let ch = chars[i]
            if quoted {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { quoted = false }
                continue
            }
            switch ch {
            case "\"":
                quoted = true
            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 {
                    let sub = String(chars[start...i])
                    guard let data = sub.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ContentError.format("页面数据格式错误")
                    }
                    return json
                }
            default:
                break
            }
        }
        throw ContentError.format("页面数据不完整")
    }

    /// 清晰度解析：优先匹配高度关键词，其次常见分辨率映射，最后数字兜底
    static func qualityNumber(_ value: String) -> Int {
        if let match = value.range(of: "2160|1440|1080|720|576|540|480|360", options: .regularExpression) {
            return Int(value[match]) ?? 0
        }
        let fallback = ["1920": 1080, "1280": 720, "1024": 576, "854": 480, "640": 360]
        if let mapped = fallback[value] { return mapped }
        return Int(value) ?? 0
    }
}

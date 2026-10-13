// SwiftData 读写层：查询缓存（内存→SwiftData→网络 的门面）+ 收藏 + 观看状态 + 搜索历史 + 本地搜索。
// @MainActor：SwiftData 模型上下文绑定主线程；UI 与 ContentRepository 的 await 调用自动在主线程串行。
import Foundation
import SwiftData

@MainActor
final class CacheStore {
    /// 全局共享实例（UI 与 ContentRepository 共用，保证读写一致）
    static let shared = CacheStore()

    private let context: ModelContext
    /// 列表查询缓存 TTL（秒）：首页/分类/搜索/演员
    private let queriesTTL: TimeInterval
    /// 详情缓存 TTL（秒）：剧集结构变化极低频
    private let detailTTL: TimeInterval

    init(
        context: ModelContext? = nil,
        queriesTTL: TimeInterval = 300,
        detailTTL: TimeInterval = 86400
    ) {
        self.context = context ?? SwiftDataStore.container.mainContext
        self.queriesTTL = queriesTTL
        self.detailTTL = detailTTL
    }

    private var now: Double { Date().timeIntervalSince1970 }

    // MARK: - 列表查询缓存（home/category/search/actor）

    /// 命中且未过期的查询结果；未命中或过期返回 nil（由调用方走网络）
    func cachedList(kind: String, scope: String, page: Int) -> [Series]? {
        guard let query = fetchQuery(key: Self.queryKey(kind: kind, scope: scope, page: page)),
              now - query.createdAt <= queriesTTL else { return nil }
        let items = query.items.sorted { $0.cachedAt <= $1.cachedAt }.map { $0.asSeries }
        return items.isEmpty ? nil : items
    }

    /// 写入一次查询结果：upsert 剧集（含小分类关系）+ 重建查询快照
    func saveList(kind: String, scope: String, page: Int, items: [Series], categoriesBySeriesId: [String: [[String: String]]] = [:]) {
        let seriesList = items.map { upsertSeries($0, categories: categoriesBySeriesId[$0.id]) }
        let key = Self.queryKey(kind: kind, scope: scope, page: page)
        let query: SDQueryCache
        if let existing = fetchQuery(key: key) {
            query = existing
        } else {
            let fresh = SDQueryCache(key: key, kind: kind, scope: scope, page: page)
            context.insert(fresh)
            query = fresh
        }
        query.kind = kind
        query.scope = scope
        query.page = page
        query.createdAt = now
        query.items = seriesList
        saveContext()
    }

    // MARK: - 演员档案（actorSearch 命中缓存时恢复 actor 卡片）

    func saveActorProfile(_ profile: ActorProfile) {
        guard !profile.id.isEmpty, !profile.name.isEmpty else { return }
        let celebrity = (try? context.fetch(FetchDescriptor<SDCelebrity>(predicate: #Predicate { $0.id == profile.id })))?.first
            ?? SDCelebrity(profile)
        celebrity.name = profile.name
        celebrity.avatar = profile.avatar
        celebrity.bio = profile.description
        celebrity.subtitle = profile.subtitle
        saveContext()
    }

    func cachedActorProfile(name: String) -> ActorProfile? {
        guard !name.isEmpty else { return nil }
        let rows = (try? context.fetch(FetchDescriptor<SDCelebrity>(predicate: #Predicate { $0.name == name }))) ?? []
        guard let c = rows.first else { return nil }
        return ActorProfile(id: c.id, name: c.name, avatar: c.avatar, description: c.bio, subtitle: c.subtitle)
    }

    // MARK: - 详情缓存

    /// 命中且未过期的详情（含分集与演职人员）；不完整或过期返回 nil
    func cachedDetail(id: String) -> Detail? {
        guard let series = fetchSeries(id: id),
              now - series.cachedAt <= detailTTL,
              !series.episodes.isEmpty else { return nil }
        let episodes = series.episodes.sorted { $0.number < $1.number }.map { $0.asEpisode }
        let celebrities = series.castings.compactMap { casting -> Celebrity? in
            guard let c = casting.celebrity else { return nil }
            return Celebrity(id: c.id, name: c.name, role: casting.role, avatar: c.avatar)
        }
        return Detail(
            id: series.id, title: series.title, cover: series.cover,
            description: series.summary, badge: series.badge, tags: series.tags,
            celebrities: celebrities, episodes: episodes
        )
    }

    /// 写入详情：upsert 剧集（不覆盖已有小分类，详情接口无该字段）+ 重建分集与演职人员
    func saveDetail(_ detail: Detail) {
        let series = upsertSeries(Series(
            id: detail.id, title: detail.title, cover: detail.cover,
            description: detail.description, badge: detail.badge, tags: detail.tags
        ), categories: nil)

        // 重建分集（旧的分集删除；观看状态在 SDWatchState，不受影响）
        for old in series.episodes { context.delete(old) }
        series.episodes = detail.episodes.map { ep in
            let e = SDEpisode(id: ep.id, number: ep.number, title: ep.title)
            context.insert(e)
            e.series = series
            return e
        }

        // 重建演职人员（upsert 演员 + 重建出演关系）
        for old in series.castings { context.delete(old) }
        series.castings = (detail.celebrities ?? []).compactMap { c in
            guard !c.id.isEmpty else { return nil }
            let celebrity = upsertCelebrity(c)
            let casting = SDCasting(role: c.role)
            context.insert(casting)
            casting.series = series
            casting.celebrity = celebrity
            return casting
        }
        saveContext()
    }

    // MARK: - 收藏（用户数据，独立自包含）

    @discardableResult
    func toggleFavorite(_ s: Series) -> Bool {
        if let fav = fetchFavorite(seriesId: s.id) {
            context.delete(fav)
            saveContext()
            return false
        }
        let fav = SDFavorite(seriesId: s.id, title: s.title, cover: s.cover, badge: s.badge)
        if let series = fetchSeries(id: s.id) { fav.series = series }
        context.insert(fav)
        saveContext()
        return true
    }

    func isFavorite(seriesId: String) -> Bool {
        fetchFavorite(seriesId: seriesId) != nil
    }

    /// 收藏列表（自包含，按收藏时间倒序；剧缓存被清仍可展示）
    func favorites() -> [SDFavorite] {
        (try? context.fetch(FetchDescriptor<SDFavorite>(sortBy: [SortDescriptor(\SDFavorite.favoritedAt, order: .reverse)]))) ?? []
    }

    /// 收藏列表转 Series（UI 展示用：优先取剧缓存完整数据，缺失时用收藏快照）
    func favoriteSeries() -> [Series] {
        favorites().map { fav in
            if let s = fetchSeries(id: fav.seriesId) { return s.asSeries }
            return Series(id: fav.seriesId, title: fav.title, cover: fav.cover, description: "", badge: fav.badge, tags: "")
        }
    }

    // MARK: - 每集观看状态（用户数据，独立自包含）

    /// 记录一次观看：完成(completed)置为已看，否则更新进度；watchedAt 总是刷新
    func markWatched(
        seriesId: String, episodeId: String, episodeNumber: Int,
        seriesTitle: String, episodeTitle: String,
        position: Double, duration: Double, completed: Bool
    ) {
        let state: SDWatchState
        if let existing = fetchWatchState(seriesId: seriesId, episodeId: episodeId) {
            state = existing
        } else {
            let fresh = SDWatchState(seriesId: seriesId, episodeId: episodeId, episodeNumber: episodeNumber, seriesTitle: seriesTitle, episodeTitle: episodeTitle)
            context.insert(fresh)
            state = fresh
        }
        state.seriesTitle = seriesTitle.isEmpty ? state.seriesTitle : seriesTitle
        state.episodeTitle = episodeTitle.isEmpty ? state.episodeTitle : episodeTitle
        state.position = position
        state.duration = duration
        if completed { state.isWatched = true }
        state.watchedAt = now
        saveContext()
    }

    /// 某集观看状态（续播定位用）
    func watchState(seriesId: String, episodeId: String) -> SDWatchState? {
        fetchWatchState(seriesId: seriesId, episodeId: episodeId)
    }

    /// 某剧已观看的分集 id 集合（分集列表打「已看」标）
    func watchedEpisodeIds(seriesId: String) -> Set<String> {
        let states = fetchWatchStates(seriesId: seriesId)
        return Set(states.filter { $0.isWatched }.map { $0.episodeId })
    }

    /// 最近观看（每剧取最新一条，按时间倒序）——「最近观看」列表数据源
    func recentWatches(limit: Int = 30) -> [SDWatchState] {
        let all = (try? context.fetch(FetchDescriptor<SDWatchState>())) ?? []
        var latest: [String: SDWatchState] = [:]
        for s in all where s.watchedAt != nil {
            if let cur = latest[s.seriesId], cur.watchedAt ?? 0 > s.watchedAt ?? 0 { continue }
            latest[s.seriesId] = s
        }
        return latest.values.sorted { ($0.watchedAt ?? 0) > ($1.watchedAt ?? 0) }.prefix(limit).map { $0 }
    }

    /// 最近观看转 Series（UI 展示用：优先剧缓存，缺失时用观看状态快照标题）
    func recentSeries(limit: Int = 30) -> [Series] {
        recentWatches(limit: limit).map { state in
            if let s = fetchSeries(id: state.seriesId) { return s.asSeries }
            return Series(id: state.seriesId, title: state.seriesTitle, cover: "", description: "", badge: "", tags: "")
        }
    }

    /// 续播定位：该剧最近一条「未看完且有进度」的观看记录
    func resume(for seriesId: String) -> (episodeId: String, position: Double)? {
        let states = fetchWatchStates(seriesId: seriesId)
            .filter { $0.watchedAt != nil && !$0.isWatched && $0.position > 0 }
            .sorted { ($0.watchedAt ?? 0) > ($1.watchedAt ?? 0) }
        guard let s = states.first else { return nil }
        return (s.episodeId, s.position)
    }

    // MARK: - 搜索历史（用户数据）

    func searchHistory(limit: Int = 20) -> [String] {
        let rows = (try? context.fetch(FetchDescriptor<SDSearchHistory>(sortBy: [SortDescriptor(\SDSearchHistory.searchedAt, order: .reverse)]))) ?? []
        return rows.prefix(limit).map { $0.keyword }
    }

    func addSearchHistory(_ keyword: String) {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let row = (try? context.fetch(FetchDescriptor<SDSearchHistory>(predicate: #Predicate { $0.keyword == key })))?.first {
            row.searchedAt = now
        } else {
            context.insert(SDSearchHistory(keyword: key))
        }
        saveContext()
    }

    func removeSearchHistory(_ keyword: String) {
        guard let row = (try? context.fetch(FetchDescriptor<SDSearchHistory>(predicate: #Predicate { $0.keyword == keyword })))?.first else { return }
        context.delete(row)
        saveContext()
    }

    func clearSearchHistory() {
        let rows = (try? context.fetch(FetchDescriptor<SDSearchHistory>())) ?? []
        rows.forEach { context.delete($0) }
        saveContext()
    }

    // MARK: - 本地搜索（小分类 / 关键词，支撑离线检索）

    /// 所有小分类词表（分类筛选页数据源）
    func categories() -> [String] {
        let rows = (try? context.fetch(FetchDescriptor<SDCategory>())) ?? []
        return Set(rows.map { $0.name }).sorted()
    }

    /// 本地检索：keyword 匹配标题（SQL 过滤）；category 匹配小分类（内存过滤，兼容 tvOS 17.0，避免 #Predicate 组合 evaluate API）
    func localSearch(keyword: String? = nil, category: String? = nil, limit: Int = 50) -> [Series] {
        var rows: [SDSeries]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !kw.isEmpty {
            let fd = FetchDescriptor<SDSeries>(predicate: #Predicate { $0.title.contains(kw) })
            rows = (try? context.fetch(fd)) ?? []
        } else {
            rows = (try? context.fetch(FetchDescriptor<SDSeries>())) ?? []
        }
        if let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
            rows = rows.filter { $0.categories.contains { $0.name == cat } }
        }
        rows.sort { $0.cachedAt > $1.cachedAt }
        return rows.prefix(limit).map { $0.asSeries }
    }

    // MARK: - 维护

    /// 查询快照数量上限，超限淘汰最旧（剧集/分集/演员缓存保留，供详情与离线）
    func pruneQueries(maxEntries: Int = 200) {
        let rows = (try? context.fetch(FetchDescriptor<SDQueryCache>(sortBy: [SortDescriptor(\SDQueryCache.createdAt, order: .forward)]))) ?? []
        guard rows.count > maxEntries else { return }
        for row in rows.prefix(rows.count - maxEntries) { context.delete(row) }
        saveContext()
    }

    /// 清除内容缓存（查询快照 + 剧集级联分集/出演）；用户数据（收藏/观看/搜索历史）保留
    func clearContentCache() {
        let queries = (try? context.fetch(FetchDescriptor<SDQueryCache>())) ?? []
        queries.forEach { context.delete($0) }
        let series = (try? context.fetch(FetchDescriptor<SDSeries>())) ?? []
        series.forEach { context.delete($0) }
        saveContext()
    }

    /// 磁盘用量（字节）与实体计数，调试/设置页用
    func stats() -> (queries: Int, series: Int, episodes: Int, categories: Int, favorites: Int, watchStates: Int, histories: Int) {
        func count<T: PersistentModel>(_ t: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return (
            count(SDQueryCache.self), count(SDSeries.self), count(SDEpisode.self),
            count(SDCategory.self), count(SDFavorite.self), count(SDWatchState.self),
            count(SDSearchHistory.self)
        )
    }

    // MARK: - 内部

    static func queryKey(kind: String, scope: String, page: Int) -> String {
        "\(kind)|\(scope)|\(page)"
    }

    private func fetchQuery(key: String) -> SDQueryCache? {
        (try? context.fetch(FetchDescriptor<SDQueryCache>(predicate: #Predicate { $0.key == key })))?.first
    }

    private func fetchSeries(id: String) -> SDSeries? {
        (try? context.fetch(FetchDescriptor<SDSeries>(predicate: #Predicate { $0.id == id })))?.first
    }

    private func fetchFavorite(seriesId: String) -> SDFavorite? {
        (try? context.fetch(FetchDescriptor<SDFavorite>(predicate: #Predicate { $0.seriesId == seriesId })))?.first
    }

    private func fetchWatchState(seriesId: String, episodeId: String) -> SDWatchState? {
        (try? context.fetch(FetchDescriptor<SDWatchState>(predicate: #Predicate { $0.key == "\(seriesId):\(episodeId)" })))?.first
    }

    private func fetchWatchStates(seriesId: String) -> [SDWatchState] {
        (try? context.fetch(FetchDescriptor<SDWatchState>(predicate: #Predicate { $0.seriesId == seriesId }))) ?? []
    }

    /// upsert 剧集：唯一 id 命中则刷新展示字段，未命中则插入；附带小分类关系
    @discardableResult
    private func upsertSeries(_ s: Series, categories: [[String: String]]?) -> SDSeries {
        let series: SDSeries
        if let existing = fetchSeries(id: s.id) {
            series = existing
        } else {
            let fresh = SDSeries(s)
            context.insert(fresh)
            series = fresh
        }
        series.title = s.title
        series.cover = s.cover
        series.summary = s.description
        series.badge = s.badge
        series.tags = s.tags
        series.cachedAt = now
        if let cats = categories, !cats.isEmpty {
            series.categories = cats.compactMap { raw in
                let cid = raw["id"] ?? raw["category_id"] ?? ""
                let name = raw["name"] ?? ""
                guard !cid.isEmpty || !name.isEmpty else { return nil }
                let category = fetchCategory(id: cid, name: name)
                return category
            }
        }
        return series
    }

    private func fetchCategory(id: String, name: String) -> SDCategory {
        if !id.isEmpty, let existing = (try? context.fetch(FetchDescriptor<SDCategory>(predicate: #Predicate { $0.id == id })))?.first {
            if !name.isEmpty { existing.name = name }
            return existing
        }
        if let byName = (try? context.fetch(FetchDescriptor<SDCategory>(predicate: #Predicate { $0.name == name })))?.first, !name.isEmpty {
            return byName
        }
        let category = SDCategory(id: id.isEmpty ? name : id, name: name)
        context.insert(category)
        return category
    }

    @discardableResult
    private func upsertCelebrity(_ c: Celebrity) -> SDCelebrity {
        let celebrity: SDCelebrity
        if let existing = (try? context.fetch(FetchDescriptor<SDCelebrity>(predicate: #Predicate { $0.id == c.id })))?.first {
            celebrity = existing
        } else {
            let fresh = SDCelebrity(c)
            context.insert(fresh)
            celebrity = fresh
        }
        celebrity.name = c.name
        celebrity.avatar = c.avatar
        return celebrity
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            NSLog("CacheStore save failed: \(error)")
        }
    }
}

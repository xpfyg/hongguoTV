// SwiftData 持久化模型层：短剧查询缓存 + 收藏 + 观看记录 + 结构化分类（本地搜索）。
// 与 Models.swift 的 Codable 契约结构体对应，通过 SD* 转换方法互转；观看/收藏为本地行为数据，不走 API 转换。
// 注意：本层尚未接入 App（无存量存储文件），结构调整零迁移成本。
import Foundation
import SwiftData

// MARK: - 内容域（剧集及其属性）

/// 剧集（卡片 + 详情公共字段；缓存统一落点）
@Model
final class SDSeries {
    /// series_id，全局唯一，重复写入 upsert
    @Attribute(.unique) var id: String
    var title: String
    /// 封面 URL（byteimg 签名地址会过期，仅缓存字符串）
    var cover: String
    /// 简介（原名 description，避免与 NSObject.description 冲突）
    var summary: String
    /// 角标，如「全 83 集」
    var badge: String
    /// 展示用标签串（如「爱情 · 都市爱情」），由 categories 聚合生成
    var tags: String
    /// 本地写入时间（Unix 秒）
    var cachedAt: Double

    /// 分集，1—N，级联删除（观看状态在独立实体 SDWatchState）
    @Relationship(deleteRule: .cascade, inverse: \SDEpisode.series)
    var episodes: [SDEpisode] = []

    /// 出演关系，1—N（演员 N—M 的中间表）
    @Relationship(deleteRule: .cascade, inverse: \SDCasting.series)
    var castings: [SDCasting] = []

    /// 小分类（如 爱情/古装/甜宠），N—M，本地按分类搜索的入口
    @Relationship(deleteRule: .nullify, inverse: \SDCategory.series)
    var categories: [SDCategory] = []

    /// 查询命中（反向，多对多；由 SDQueryCache.items 的 inverse 维护）
    var cacheEntries: [SDQueryCache] = []

    init(
        id: String, title: String, cover: String, summary: String,
        badge: String, tags: String, cachedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.summary = summary
        self.badge = badge
        self.tags = tags
        self.cachedAt = cachedAt
    }
}

/// 分集（缓存域：仅剧集结构；观看状态在独立实体 SDWatchState，不随缓存淘汰丢失）
@Model
final class SDEpisode {
    /// vid，全局唯一
    @Attribute(.unique) var id: String
    var number: Int
    var title: String
    /// 所属剧集（反向）
    var series: SDSeries?

    init(id: String, number: Int, title: String) {
        self.id = id
        self.number = number
        self.title = title
    }
}

/// 小分类标签（category_list 结构化，替代拼接字符串，支撑本地搜索/筛选）
@Model
final class SDCategory {
    /// category_id（如 "5000"），全局唯一
    @Attribute(.unique) var id: String
    var name: String
    /// 命中该分类的剧（反向，多对多；由 SDSeries.categories 的 inverse 维护）
    var series: [SDSeries] = []

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 演员（对应 API Celebrity / ActorProfile）
@Model
final class SDCelebrity {
    /// actor_id / person_id / celebrity_id，全局唯一
    @Attribute(.unique) var id: String
    var name: String
    /// 头像 URL（签名地址会过期，仅缓存字符串）
    var avatar: String
    /// 演员档案简介（ActorProfile.description）
    var bio: String
    /// 身份标签（如「女演员」）
    var subtitle: String

    /// 出演关系（反向，多对多）
    @Relationship(deleteRule: .cascade, inverse: \SDCasting.celebrity)
    var castings: [SDCasting] = []

    init(id: String, name: String, avatar: String, bio: String = "", subtitle: String = "") {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.bio = bio
        self.subtitle = subtitle
    }
}

/// 出演关系中间表：某演员在某剧中的角色（role 属于「剧内角色」）
@Model
final class SDCasting {
    /// 剧内角色，如「饰 顾娇」
    var role: String
    var series: SDSeries?
    var celebrity: SDCelebrity?

    init(role: String) {
        self.role = role
    }
}

// MARK: - 用户行为域（收藏 / 观看 / 搜索记录；独立自包含，不随缓存淘汰丢失）

/// 收藏记录（用户数据：存标题/封面快照，剧缓存被清仍可展示列表；点进详情时按 seriesId 拉取）
@Model
final class SDFavorite {
    /// series_id，全局唯一，重复收藏自动去重
    @Attribute(.unique) var seriesId: String
    var title: String
    /// 封面 URL（签名地址会过期，仅存字符串；显示失败时用占位）
    var cover: String
    var badge: String
    /// 收藏时间（Unix 秒），列表按此倒序
    var favoritedAt: Double
    /// 关联剧集缓存（可选：命中时可用完整数据）
    var series: SDSeries?

    init(seriesId: String, title: String, cover: String, badge: String, favoritedAt: Double = Date().timeIntervalSince1970) {
        self.seriesId = seriesId
        self.title = title
        self.cover = cover
        self.badge = badge
        self.favoritedAt = favoritedAt
    }
}

/// 每集观看状态（用户数据：看过/进度/时长，独立于剧集缓存；按 seriesId:episodeId 唯一）
@Model
final class SDWatchState {
    /// "\(seriesId):\(episodeId)"，全局唯一
    @Attribute(.unique) var key: String
    var seriesId: String
    var episodeId: String
    var episodeNumber: Int
    /// 剧名快照（剧缓存被清仍可展示「最近观看」列表）
    var seriesTitle: String
    var episodeTitle: String
    /// 是否已观看（看过 = 播完或用户标记）
    var isWatched: Bool
    /// 播放位置（秒），续播用
    var position: Double
    /// 集时长（秒）
    var duration: Double
    /// 最近观看时间（Unix 秒；nil=未看过），定位续播集与最近观看排序
    var watchedAt: Double?

    init(seriesId: String, episodeId: String, episodeNumber: Int, seriesTitle: String, episodeTitle: String) {
        self.key = "\(seriesId):\(episodeId)"
        self.seriesId = seriesId
        self.episodeId = episodeId
        self.episodeNumber = episodeNumber
        self.seriesTitle = seriesTitle
        self.episodeTitle = episodeTitle
        self.isWatched = false
        self.position = 0
        self.duration = 0
    }
}

/// 搜索历史（去重，按最近搜索时间排序）
@Model
final class SDSearchHistory {
    @Attribute(.unique) var keyword: String
    var searchedAt: Double

    init(keyword: String, searchedAt: Double = Date().timeIntervalSince1970) {
        self.keyword = keyword
        self.searchedAt = searchedAt
    }
}

// MARK: - 查询域

/// 查询缓存：一次查询（首页/分类/搜索/演员搜索）的结果快照
@Model
final class SDQueryCache {
    /// 唯一键：`home|1`、`category|human|2`、`search|孟娜|1`、`actor|孟娜|1`
    @Attribute(.unique) var key: String
    /// 查询类型：home / category / search / actor
    var kind: String
    /// 查询作用域：分类 typeId（human/comic/ai/rank_*）或关键词（keyword）
    var scope: String
    var page: Int
    var createdAt: Double

    /// 结果剧集，有序（Array 关系保持顺序，还原查询顺序）
    @Relationship(deleteRule: .nullify, inverse: \SDSeries.cacheEntries)
    var items: [SDSeries] = []

    init(key: String, kind: String, scope: String, page: Int, createdAt: Double = Date().timeIntervalSince1970) {
        self.key = key
        self.kind = kind
        self.scope = scope
        self.page = page
        self.createdAt = createdAt
    }
}

// MARK: - 转换（Codable struct ↔ @Model）

extension SDSeries {
    convenience init(_ s: Series, now: Double = Date().timeIntervalSince1970) {
        self.init(id: s.id, title: s.title, cover: s.cover, summary: s.description, badge: s.badge, tags: s.tags, cachedAt: now)
    }

    var asSeries: Series {
        Series(id: id, title: title, cover: cover, description: summary, badge: badge, tags: tags)
    }
}

extension SDCelebrity {
    convenience init(_ c: Celebrity) {
        self.init(id: c.id, name: c.name, avatar: c.avatar, bio: "", subtitle: "")
    }

    convenience init(_ a: ActorProfile) {
        self.init(id: a.id, name: a.name, avatar: a.avatar, bio: a.description, subtitle: a.subtitle)
    }

    var asCelebrity: Celebrity {
        Celebrity(id: id, name: name, role: "", avatar: avatar)
    }

    var asActorProfile: ActorProfile {
        ActorProfile(id: id, name: name, avatar: avatar, description: bio, subtitle: subtitle)
    }
}

extension SDEpisode {
    var asEpisode: Episode {
        Episode(id: id, number: number, title: title)
    }
}

// MARK: - 容器

enum SwiftDataStore {
    static let container: ModelContainer = {
        let schema = Schema([
            SDSeries.self, SDEpisode.self, SDCategory.self,
            SDCasting.self, SDCelebrity.self, SDFavorite.self,
            SDWatchState.self, SDQueryCache.self, SDSearchHistory.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData 容器创建失败: \(error)")
        }
    }()

    @MainActor
    static var context: ModelContext { container.mainContext }
}

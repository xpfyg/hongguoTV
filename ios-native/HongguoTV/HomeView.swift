import SwiftUI

// MARK: - 首页：电影级 Hero + 内容架（继续观看 / 热门短剧）+ 分类浏览

/// 大分类（对应服务端 /api/category/:typeId 的 CATEGORY_CONFIG）
struct CategoryMeta: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
}

let allCategories: [CategoryMeta] = [
    CategoryMeta(id: "short", name: "短剧", subtitle: "首页推荐", symbol: "play.rectangle.fill"),
    CategoryMeta(id: "human", name: "真人剧", subtitle: "分类", symbol: "person.2.fill"),
    CategoryMeta(id: "comic", name: "漫剧", subtitle: "分类", symbol: "paintbrush.fill"),
    CategoryMeta(id: "ai", name: "AI剧", subtitle: "分类", symbol: "sparkles"),
    CategoryMeta(id: "rank_hot", name: "红果热播榜", subtitle: "榜单", symbol: "trophy.fill"),
    CategoryMeta(id: "rank_human", name: "真人剧热播榜", subtitle: "榜单", symbol: "person.3.fill"),
    CategoryMeta(id: "rank_comic", name: "漫剧热播榜", subtitle: "榜单", symbol: "paintbrush.pointed.fill"),
    CategoryMeta(id: "rank_ai", name: "AI剧热播榜", subtitle: "榜单", symbol: "sparkles.rectangle.stack.fill"),
]

/// 「继续观看」条目：剧集卡片 + 续播集数与进度
struct ResumeItem: Identifiable {
    let id: String
    let series: Series
    let episodeNumber: Int
    let progress: Double // 0...1
}

struct HomeView: View {
    let onOpen: (Series) -> Void

    @State private var items: [Series] = []        // 当前分类网格
    @State private var homeList: [Series] = []     // 首页推荐（热门短剧架）
    @State private var banners: [Banner] = []      // 首页轮播（横版大图）
    @State private var resumeItems: [ResumeItem] = []
    @State private var page = 1
    @State private var busy = false
    @State private var error: String?
    @State private var connected = false
    @State private var selectedCategory = "short"
    @State private var categoryName = "短剧"
    @State private var subCategories: [SubCategory] = []
    @State private var selectedSub: String? = nil // nil = 全部
    @State private var loadSeq = 0
    @FocusState private var focusedCategory: String?
    @FocusState private var subFocus: String? // "all" = 全部小分类

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 40)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !banners.isEmpty {
                    HeroCarousel(banners: banners) { b in
                        onOpen(Series(id: b.seriesId, title: b.title, cover: b.image,
                                      description: "", badge: "", tags: ""))
                    }
                    .padding(.bottom, AppSpacing.shelf)
                } else if let featured {
                    HeroBanner(series: featured) { onOpen(featured) }
                        .padding(.bottom, AppSpacing.shelf)
                }

                if !resumeItems.isEmpty {
                    Shelf(title: "继续观看") {
                        ForEach(resumeItems) { item in
                            ResumeCard(item: item) { onOpen(item.series) }
                        }
                    }
                    .padding(.bottom, AppSpacing.shelf)
                }

                if !homeList.isEmpty {
                    Shelf(title: "热门短剧") {
                        ForEach(homeList.prefix(16)) { series in
                            PosterCard(series: series, width: 230) { onOpen(series) }
                        }
                    }
                     .padding(.horizontal, AppSpacing.edge)
                    .padding(.bottom, 60)
                }

                // 分类浏览（保留全部既有业务能力）
                categoryBar

                if !subCategories.isEmpty {
                    subCategoryBar
                }

                contentState
                    .padding(.top, 28)
            }
        }
        .task { await connectAndLoad() }
    }

    private var featured: Series? {
        homeList.first
    }

    private var subtitle: String {
        if let sub = selectedSub, let name = subCategories.first(where: { $0.slug == sub })?.name {
            return "\(categoryName) · \(name)"
        }
        return categoryName
    }

    // MARK: - 内容区状态

    @ViewBuilder
    private var contentState: some View {
        if error != nil, items.isEmpty {
            errorView
        } else if busy && items.isEmpty {
            ProgressView()
                .scaleEffect(1.4)
                .frame(maxWidth: .infinity, minHeight: 360)
        } else if connected {
            sectionHeader(subtitle)
            posterGrid
        } else {
            ProgressView()
                .scaleEffect(1.4)
                .frame(maxWidth: .infinity, minHeight: 360)
        }
    }

    private var errorView: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(AppColors.textTertiary)
            Text(error ?? "连接失败")
                .font(AppFont.body)
                .foregroundStyle(AppColors.textSecondary)
            Text("请检查网络后重试")
                .font(AppFont.aux)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    // MARK: - 分类胶囊栏

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(allCategories) { cat in
                    categoryBlock(cat)
                }
            }
            .padding(.horizontal, AppSpacing.edge)
        }
    }

    private func categoryBlock(_ cat: CategoryMeta) -> some View {
        let selected = selectedCategory == cat.id
        return Button {
            Task { await selectCategory(cat.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cat.symbol)
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    Text(cat.subtitle)
                        .font(AppFont.tag)
                        .foregroundStyle(selected ? AppColors.background.opacity(0.6) : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(selected ? AppColors.textPrimary : AppColors.surface)
            .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle(scale: 1.04))
        .focused($focusedCategory, equals: cat.id)
    }

    // MARK: - 小分类栏

    private var subCategoryBar: some View {
        let items = [SubCategory(slug: "all", name: "全部")] + subCategories
        let columns = items.count > 15 ? 15 : items.count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(items) { sub in
                subCategoryBlock(
                    sub.name,
                    key: sub.slug,
                    selected: sub.slug == "all" ? selectedSub == nil : selectedSub == sub.slug
                )
            }
        }
        .padding(.horizontal, AppSpacing.edge)
        .padding(.top, 14)
    }

    private func subCategoryBlock(_ name: String, key: String, selected: Bool) -> some View {
        Button {
            Task { await selectSub(key == "all" ? nil : key) }
        } label: {
            Text(name)
                .font(.system(size: 18, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? AppColors.textPrimary : AppColors.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle(scale: 1.04))
        .focused($subFocus, equals: key)
    }

    // MARK: - 分类网格

    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: 48) {
            ForEach(items) { series in
                PosterCard(series: series) {
                    onOpen(series)
                }
                .onAppear {
                    if series.id == items.last?.id { Task { await loadMore() } }
                }
            }
        }
        .padding(.horizontal, AppSpacing.edge)
        .padding(.bottom, 60)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.section)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.leading, AppSpacing.edge)
            .padding(.bottom, 18)
    }

    // MARK: - 数据加载（逻辑与原实现一致，仅新增 Hero / 续看数据源）

    private func loadResume() async {
        let api = ContentClient()
        let watches = api.cache.recentWatches(limit: 14)
        let seriesList = api.cache.recentSeries(limit: 14)
        resumeItems = zip(watches, seriesList).map { state, s in
            let progress = state.duration > 0 ? min(1, max(0, state.position / state.duration)) : 0
            return ResumeItem(id: s.id, series: s, episodeNumber: state.episodeNumber, progress: progress)
        }
    }

    private func loadHomeShelves() async {
        let api = ContentClient()
        async let shelf = api.home(page: 1)
        async let bnr = api.banners()
        homeList = (try? await shelf) ?? []
        banners = (try? await bnr) ?? []
    }

    private func selectCategory(_ id: String) async {
        guard id != selectedCategory else { return }
        selectedCategory = id
        categoryName = allCategories.first(where: { $0.id == id })?.name ?? "内容"
        busy = true
        error = nil
        defer { busy = false }
        // 焦点连续移动会并发触发；只接受最新一次请求的结果
        loadSeq += 1
        let seq = loadSeq
        let api = ContentClient()
        do {
            _ = try await api.health()
            connected = true
            items = []
            page = 1
            let (name, subs, list) = try await api.category(typeId: id, page: 1)
            guard seq == loadSeq else { return }
            categoryName = name
            subCategories = subs
            selectedSub = nil
            items = list
        } catch let caught {
            guard seq == loadSeq else { return }
            items = []
            error = errorMessage(caught)
        }
    }

    private func selectSub(_ slug: String?) async {
        guard slug != selectedSub else { return }
        selectedSub = slug
        busy = true
        error = nil
        defer { busy = false }
        loadSeq += 1
        let seq = loadSeq
        let api = ContentClient()
        do {
            _ = try await api.health()
            connected = true
            items = []
            page = 1
            let (_, _, list) = try await api.category(typeId: selectedCategory, slug: slug, page: 1)
            guard seq == loadSeq else { return }
            items = list
        } catch let caught {
            guard seq == loadSeq else { return }
            items = []
            error = errorMessage(caught)
        }
    }

    private func connectAndLoad() async {
        async let shelves = loadHomeShelves()
        async let resume = loadResume()
        _ = await (shelves, resume)

        let api = ContentClient()
        do {
            _ = try await api.health()
            connected = true
            items = []
            page = 1
            let (name, subs, list) = try await api.category(typeId: "short", page: 1)
            categoryName = name
            subCategories = subs
            items = list
        } catch let caught {
            error = errorMessage(caught)
        }
    }

    private func loadMore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = ContentClient()
        do {
            let next = page + 1
            let (_, _, more) = try await api.category(typeId: selectedCategory, slug: selectedSub, page: next)
            guard !more.isEmpty else { return }
            page = next
            items += more.filter { m in !items.contains { $0.id == m.id } }
        } catch {}
    }

    private func errorMessage(_ e: Error) -> String {
        if let ae = e as? APIError { return ae.errorDescription ?? "连接失败" }
        return "连接失败"
    }
}

// MARK: - 电影级 Hero（全屏海报 + 左下标题/简介/播放）

struct HeroBanner: View {
    let series: Series
    let onPlay: () -> Void
    @FocusState private var playFocused: Bool

    var body: some View {
        AsyncImage(url: URL(string: series.cover)) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                AppColors.surface
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 540)
        .clipped()
        // 底部压暗 → 画布色
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        // 左侧补暗保证文字可读
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)
        }
        // 左下：标题 / 简介 / 播放
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 14) {
                Text(series.title)
                    .font(AppFont.heroTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if !series.description.isEmpty {
                    Text(series.description)
                        .font(AppFont.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                if !meta.isEmpty {
                    Text(meta)
                        .font(AppFont.aux)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Button {
                    onPlay()
                } label: {
                    Label("立即播放", systemImage: "play.fill")
                }
                .heroPlayAction()
                .focused($playFocused)
                .padding(.top, 6)
            }
            .padding(.leading, AppSpacing.edge)
            .padding(.bottom, 52)
        }
    }

    private var meta: String {
        [series.badge, series.tags].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 首页轮播（/api/banners 横版大图，左右切换）

struct HeroCarousel: View {
    let banners: [Banner]
    let onOpen: (Banner) -> Void
    @State private var selection = 0
    @FocusState private var playFocused: Bool

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(banners.enumerated()), id: \.element.id) { idx, b in
                page(banner: b)
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 540)
    }

    private func page(banner: Banner) -> some View {
        AsyncImage(url: URL(string: banner.image)) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                AppColors.surface
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 540)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.78)],
                           startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 14) {
                if !banner.title.isEmpty {
                    Text(banner.title)
                        .font(AppFont.heroTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
                Button {
                    onOpen(banner)
                } label: {
                    Label("立即播放", systemImage: "play.fill")
                }
                .heroPlayAction()
                .focused($playFocused)
            }
            .padding(.leading, AppSpacing.edge)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - 继续观看卡片（16:9 横版 + 标题/集数 + 进度条）

struct ResumeCard: View {
    let item: ResumeItem
    let onSelect: () -> Void

    private let cardWidth: CGFloat = 440
    private let cardHeight: CGFloat = 248

    var body: some View {
        Button {
            onSelect()
        } label: {
            PosterImage(url: item.series.cover, corner: 12)
                .frame(width: cardWidth, height: cardHeight)
                // 底部压暗
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                }
                // 左下：标题 + 集数
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.series.title)
                            .font(AppFont.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Text("第\(item.episodeNumber)集 · 继续观看")
                            .font(AppFont.aux)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(16)
                }
                // 底部细进度条
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(AppColors.accent)
                            .frame(width: geo.size.width * item.progress, height: 3)
                            .clipped()
                    }
                    .frame(height: 3)
                    .allowsHitTesting(false)
                }
        }
        .buttonStyle(ScaleButtonStyle(scale: 1.05))
    }
}

// MARK: - 海报卡片（2:3 竖版 + 标题；焦点 = 柔和放大 + 柔影）

struct PosterCard: View {
    let series: Series
    var width: CGFloat? = nil
    let onSelect: () -> Void
    @State private var favorite = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PosterImage(url: series.cover, corner: 12)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: width)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.accent)
                            .padding(8)
                            .background(AppColors.background.opacity(0.55))
                            .clipShape(Circle())
                            .padding(10)
                    }
                }
                .hoverEffect(.highlight)

                CardTitle(text: series.title, width: width)
            }
        }
        .buttonStyle(PosterCardStyle())
        .onAppear {
            let api = ContentClient()
            favorite = api.cache.isFavorite(seriesId: series.id)
        }
    }
}

/// 剧集名：居中；聚焦高亮，未选中偏灰。长名聚焦时水平滚动。
private struct CardTitle: View {
    let text: String
    let width: CGFloat?
    @Environment(\.isFocused) private var isFocused
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(AppFont.cardTitle)
            .foregroundStyle(isFocused ? AppColors.textPrimary : AppColors.textTertiary)
            .frame(width: width, alignment: .center)
            .clipped()
            .offset(y: isFocused ? 14 : 0)
            .animation(.easeOut(duration: 0.25), value: isFocused)
    }
}

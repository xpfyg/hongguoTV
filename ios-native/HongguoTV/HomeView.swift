import SwiftUI

// MARK: - 推荐页：Infuse 式横版分类块 + 海报墙

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

struct HomeView: View {
    let onOpen: (Series) -> Void

    @State private var items: [Series] = []
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

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 26)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：横版分类块（固定，不随内容滚动）
            categoryBar
            if !subCategories.isEmpty {
                subCategoryBar
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error {
                        VStack(spacing: 18) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 46))
                                .foregroundStyle(Theme.textTertiary)
                            Text(error).font(.system(size: 24)).foregroundStyle(Theme.textSecondary)
                            Text("请在「设置」中检查服务地址")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else if connected {
                        sectionHeader(subtitle)
                        posterGrid
                    } else if busy && items.isEmpty {
                        ProgressView()
                            .scaleEffect(1.4)
                            .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        ProgressView().scaleEffect(1.4).frame(maxWidth: .infinity, minHeight: 400)
                    }
                }
                .padding(.horizontal, 72)
                .padding(.bottom, 60)
            }
        }
        .task { await connectAndLoad() }
        .onChange(of: focusedCategory) { _, newFocus in
            guard let newFocus else { return }
            Task { await selectCategory(newFocus) }
        }
        .onChange(of: subFocus) { _, newFocus in
            guard let newFocus else { return }
            Task { await selectSub(newFocus == "all" ? nil : newFocus) }
        }
    }

    private var subtitle: String {
        if let sub = selectedSub, let name = subCategories.first(where: { $0.slug == sub })?.name {
            return "\(categoryName) · \(name)"
        }
        return categoryName
    }

    // MARK: - 横版分类块

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(allCategories) { cat in
                    categoryBlock(cat)
                }
            }
            .padding(.horizontal, 72)
            .padding(.top, 26)
            .padding(.bottom, 12)
        }
    }

    private func categoryBlock(_ cat: CategoryMeta) -> some View {
        let selected = selectedCategory == cat.id
        return Button {
            Task { await selectCategory(cat.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cat.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cat.name)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(cat.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? Theme.accent.opacity(0.28) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? Theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        // tvOS：焦点移动到分类块即自动切换该分类，无需按确认键
        .focused($focusedCategory, equals: cat.id)
    }

    // MARK: - 小分类栏（大分类为真人/漫剧/AI 剧时显示；两排网格，焦点移动即切换）

    private var subCategoryBar: some View {
        let items = [SubCategory(slug: "all", name: "全部")] + subCategories
        // 超过 15 个才排第二排（第一排固定 15 个，其余换行）；间距 8 保持紧凑
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
        .padding(.horizontal, 72)
        .padding(.bottom, 16)
    }

    private func subCategoryBlock(_ name: String, key: String, selected: Bool) -> some View {
        Button {
            Task { await selectSub(key == "all" ? nil : key) }
        } label: {
            Text(name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? Theme.accent.opacity(0.22) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(selected ? Theme.accent : Color.clear, lineWidth: 1.6)
                )
        }
        .buttonStyle(.plain)
        .focused($subFocus, equals: key)
    }

    // MARK: - 内容

    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: 30) {
            ForEach(items) { series in
                PosterCard(series: series) {
                    onOpen(series)
                }
                .onAppear {
                    if series.id == items.last?.id { Task { await loadMore() } }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 30, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 22)
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

    private func reload() async {
        busy = true
        defer { busy = false }
        let api = ContentClient()
        do {
            _ = try await api.health()
            connected = true
            error = nil
            items = []
            page = 1
            let (name, subs, list) = try await api.category(typeId: selectedCategory, slug: selectedSub, page: 1)
            categoryName = name
            subCategories = subs
            items = list
        } catch let caught {
            connected = false
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

// MARK: - 海报卡片（2:3 竖版 + 标题）

struct PosterCard: View {
    let series: Series
    let onSelect: () -> Void
    @State private var favorite = false

    var body: some View {
        Button {
            onSelect()
        } label: {            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PosterImage(url: series.cover, corner: 14)
                        .aspectRatio(2 / 3, contentMode: .fit)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(10)
                    }
                }
                Text(series.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        // tvOS：显式声明可聚焦；收藏角标在出现时一次性查询（onAppear 不影响焦点）
        .focusable(true)
        .onAppear {
            let api = ContentClient()
            favorite = api.cache.isFavorite(seriesId: series.id)
        }
    }
}

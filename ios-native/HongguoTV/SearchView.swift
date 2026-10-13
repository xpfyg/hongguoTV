import SwiftUI

// MARK: - 搜索页（搜索历史来自 SwiftData CacheStore）

struct SearchView: View {
    let onOpen: (Series) -> Void

    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [Series] = []
    @State private var history: [String] = []
    @State private var localCategories: [String] = []
    @State private var busy = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 26)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("搜索剧名或关键词", text: $query)
                        .font(.system(size: 26))
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .glassPanel(radius: 18)
                .padding(.bottom, 26)

                if busy {
                    ProgressView().scaleEffect(1.3).frame(maxWidth: .infinity, minHeight: 300)
                } else if let error {
                    Text(error).font(.system(size: 22)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if !items.isEmpty {
                    Text("“\(submitted)” 的搜索结果")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.bottom, 22)
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(items) { series in
                            PosterCard(series: series) { onOpen(series) }
                        }
                    }
                } else if !submitted.isEmpty {
                    Text("没有找到相关内容")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    historySection
                    categorySection
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
        .task { await loadHistory() }
    }

    // MARK: - 搜索历史（未输入时展示，点击直接搜索）

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("搜索历史")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !history.isEmpty {
                    Button {
                        clearHistory()
                    } label: {
                        Label("清除", systemImage: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if history.isEmpty {
                Text("暂无搜索历史")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(history, id: \.self) { keyword in
                            Button {
                                query = keyword
                                runSearch()
                            } label: {
                                Text(keyword)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .glassTile(radius: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    // MARK: - 小分类（本地搜索：命中已缓存剧集，无需网络）

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("按分类浏览")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            if localCategories.isEmpty {
                Text("浏览过剧集后自动积累分类标签")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(localCategories, id: \.self) { name in
                            Button {
                                runLocalCategory(name)
                            } label: {
                                Text(name)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .glassTile(selected: true, radius: 16, idleFill: Theme.accent.opacity(0.16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 26)
    }

    private func loadHistory() async {
        let api = ContentClient()
        history = await api.cache.searchHistory()
        localCategories = await api.cache.categories()
    }

    private func runLocalCategory(_ name: String) {
        submitted = name
        busy = true
        error = nil
        Task {
            let api = ContentClient()
            items = await api.cache.localSearch(category: name)
            busy = false
        }
    }

    private func clearHistory() {
        let api = ContentClient()
        api.cache.clearSearchHistory()
        history = []
    }

    private func runSearch() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        submitted = keyword
        busy = true
        error = nil
        Task {
            let api = ContentClient()
            do {
                items = try await api.search(query: keyword, page: 1)
                api.cache.addSearchHistory(keyword)
                history = await api.cache.searchHistory()
            } catch let caught {
                error = errorMessage(caught)
                items = []
            }
            busy = false
        }
    }

    private func errorMessage(_ e: Error) -> String {
        if let ae = e as? APIError { return ae.errorDescription ?? "搜索失败" }
        return "搜索失败"
    }
}

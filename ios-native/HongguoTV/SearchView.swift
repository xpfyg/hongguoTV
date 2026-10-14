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

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 28)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.textTertiary)
                    TextField("搜索剧名或关键词", text: $query)
                        .font(.system(size: 22))
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 30)

                if busy {
                    ProgressView().scaleEffect(1.3).frame(maxWidth: .infinity, minHeight: 300)
                } else if let error {
                    Text(error).font(AppFont.body).foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if !items.isEmpty {
                    Text("“\(submitted)” 的搜索结果")
                        .font(AppFont.section)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.bottom, 20)
                    LazyVGrid(columns: columns, spacing: 34) {
                        ForEach(items) { series in
                            PosterCard(series: series) { onOpen(series) }
                        }
                    }
                } else if !submitted.isEmpty {
                    Text("没有找到相关内容")
                        .font(AppFont.body)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    historySection
                    categorySection
                }
            }
            .padding(.horizontal, AppSpacing.edge)
            .padding(.bottom, 60)
        }
        .task { await loadHistory() }
    }

    // MARK: - 搜索历史（未输入时展示，点击直接搜索）

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("搜索历史")
                    .font(AppFont.section)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if !history.isEmpty {
                    Button {
                        clearHistory()
                    } label: {
                        Label("清除", systemImage: "trash")
                            .font(AppFont.aux)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 1.05))
                }
            }
            if history.isEmpty {
                Text("暂无搜索历史")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColors.textTertiary)
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
                                    .font(AppFont.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(AppColors.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(ScaleButtonStyle(scale: 1.05))
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
                .font(AppFont.section)
                .foregroundStyle(AppColors.textPrimary)
            if localCategories.isEmpty {
                Text("浏览过剧集后自动积累分类标签")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(localCategories, id: \.self) { name in
                            Button {
                                runLocalCategory(name)
                            } label: {
                                Text(name)
                                    .font(AppFont.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(AppColors.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(ScaleButtonStyle(scale: 1.05))
                        }
                    }
                }
            }
        }
        .padding(.top, 30)
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

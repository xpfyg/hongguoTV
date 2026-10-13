import SwiftUI

// MARK: - 搜索页

struct SearchView: View {
    @EnvironmentObject private var store: LocalStore
    let onOpen: (Series) -> Void

    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [Series] = []
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
                    Text("输入关键词后按回车搜索")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
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

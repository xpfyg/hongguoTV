import SwiftUI

// MARK: - 推荐页：Infuse 式海报墙

struct HomeView: View {
    @EnvironmentObject private var store: LocalStore
    let onOpen: (Series) -> Void

    @State private var items: [Series] = []
    @State private var page = 1
    @State private var busy = false
    @State private var error: String?
    @State private var connected = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 26)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if connected {
                    sectionHeader("今日热播")
                    posterGrid
                } else if busy && items.isEmpty {
                    ProgressView()
                        .scaleEffect(1.4)
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else if let error {
                    VStack(spacing: 18) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 46))
                            .foregroundStyle(Theme.textTertiary)
                        Text(error).font(.system(size: 24)).foregroundStyle(Theme.textSecondary)
                        Text("请在「设置」中填写服务地址并连接")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    ProgressView().scaleEffect(1.4).frame(maxWidth: .infinity, minHeight: 400)
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
        .task { await connectAndLoad() }
        .onChange(of: store.settings.baseUrl) { _, _ in Task { await reload() } }
    }

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

    private func connectAndLoad() async {
        let url = store.settings.baseUrl
        let api = APIClient(baseUrl: url, token: store.settings.token)
        do {
            _ = try await api.health()
            connected = true
            items = []
            page = 1
            items = try await api.home(page: 1)
        } catch let caught {
            error = errorMessage(caught)
        }
    }

    private func reload() async {
        busy = true
        defer { busy = false }
        let api = APIClient(baseUrl: store.settings.baseUrl, token: store.settings.token)
        do {
            _ = try await api.health()
            connected = true
            error = nil
            items = []
            page = 1
            items = try await api.home(page: 1)
        } catch let caught {
            connected = false
            error = errorMessage(caught)
        }
    }

    private func loadMore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = APIClient(baseUrl: store.settings.baseUrl, token: store.settings.token)
        do {
            let next = page + 1
            let more = try await api.home(page: next)
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
    @EnvironmentObject private var store: LocalStore

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PosterImage(url: series.cover, corner: 14)
                        .aspectRatio(2 / 3, contentMode: .fit)
                    if store.isFavorite(series.id) {
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
        .focusCard()
    }
}

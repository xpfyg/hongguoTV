import SwiftUI

// MARK: - 收藏 / 最近观看（数据源：SwiftData CacheStore）

struct LibraryView: View {
    enum Mode: String {
        case favorites = "收藏"
        case recent = "最近观看"
    }

    let mode: Mode
    let onOpen: (Series) -> Void

    @State private var items: [Series] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode.rawValue)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 22)

                if items.isEmpty {
                    emptyHint(mode == .favorites
                              ? "还没有收藏，在详情页点「收藏」即可加入"
                              : "还没有观看记录，播放过的内容会出现在这里")
                } else {
                    grid(items)
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
        .task(id: mode) { await load() }
    }

    private func load() async {
        let api = ContentClient()
        items = mode == .favorites
            ? await api.cache.favoriteSeries()
            : await api.cache.recentSeries()
    }

    private func grid(_ list: [Series]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 26)], spacing: 30) {
            ForEach(list) { series in
                PosterCard(series: series) { onOpen(series) }
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: mode == .favorites ? "star" : "clock")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

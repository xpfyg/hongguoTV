import SwiftUI

// MARK: - 收藏 / 最近观看（Infuse 式媒体库行）

struct LibraryView: View {
    enum Mode: String {
        case favorites = "收藏"
        case recent = "最近观看"
    }

    @EnvironmentObject private var store: LocalStore
    let mode: Mode
    let onOpen: (Series) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode.rawValue)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 22)

                switch mode {
                case .favorites:
                    if store.library.favorites.isEmpty {
                        emptyHint("还没有收藏，在详情页点「收藏」即可加入")
                    } else {
                        grid(store.library.favorites)
                    }
                case .recent:
                    let recent = store.recentProgress
                    if recent.isEmpty {
                        emptyHint("还没有观看记录，播放过的内容会出现在这里")
                    } else {
                        grid(recent.map { $0.series })
                    }
                }
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
    }

    private func grid(_ items: [Series]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 26)], spacing: 30) {
            ForEach(items) { series in
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

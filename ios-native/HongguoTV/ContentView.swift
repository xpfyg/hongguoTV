import SwiftUI

// MARK: - 根视图：Infuse 式顶部 Tab 导航

enum AppTab: String, CaseIterable {
    case home = "推荐"
    case search = "搜索"
    case library = "收藏"
    case recent = "最近观看"
    case settings = "设置"

    var icon: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .search: return "magnifyingglass"
        case .library: return "star.fill"
        case .recent: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var tab: AppTab = .home
    @State private var detailSeries: Series? = nil
    @State private var detailPath: AppTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selection: $tab)
                .padding(.horizontal, 72)
                .padding(.top, 40)
                .padding(.bottom, 24)
            content
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .fullScreenCover(item: $detailSeries) { series in
            DetailView(series: series)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView(onOpen: { detailSeries = $0 })
        case .search:
            SearchView(onOpen: { detailSeries = $0 })
        case .library:
            LibraryView(mode: .favorites, onOpen: { detailSeries = $0 })
        case .recent:
            LibraryView(mode: .recent, onOpen: { detailSeries = $0 })
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - 顶部 Tab 栏（居中 + 长方形毛玻璃包裹；聚焦/选中为 tvOS26 毛玻璃块）

struct TabBar: View {
    @Binding var selection: AppTab
    @FocusState private var focusedTab: AppTab?

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("红果 TV")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 6)

            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    selection = t
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon)
                        Text(t.rawValue)
                    }
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selection == t ? Color.white : Theme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .glassTile(selected: selection == t, radius: 18)
                }
                .buttonStyle(TabButtonStyle(selected: selection == t))
                .focused($focusedTab, equals: t)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 16)
        .glassPanel(radius: 30)
        .frame(maxWidth: .infinity) // 整条毛玻璃居中
    }
}

struct TabButtonStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isFocused)
    }
}

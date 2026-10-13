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
        .background(Theme.background.ignoresSafeArea())
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

// MARK: - 顶部 Tab 栏

struct TabBar: View {
    @Binding var selection: AppTab
    @FocusState private var focusedTab: AppTab?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("红果 TV")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 28)

            ForEach(AppTab.allCases, id: \.self) { t in
                Button {
                    selection = t
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon)
                        Text(t.rawValue)
                    }
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selection == t ? Color.black : Theme.textSecondary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(selection == t ? Color.white : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(TabButtonStyle(selected: selection == t))
                // tvOS：焦点移动到顶部 Tab 即自动切换，无需按确认键
                .focused($focusedTab, equals: t)
            }
            Spacer(minLength: 0)
        }
        .onChange(of: focusedTab) { _, newFocus in
            guard let newFocus else { return }
            selection = newFocus
        }
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

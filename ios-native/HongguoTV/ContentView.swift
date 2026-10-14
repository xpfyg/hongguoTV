import SwiftUI

// MARK: - 根视图：电影级深色画布 + 顶部居中菜单（Apple TV+ 式克制导航）

enum AppTab: String, CaseIterable {
    case home = "首页"
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

    var body: some View {
        VStack(spacing: 0) {
            TopBar(selection: $tab)
                .padding(.horizontal, AppSpacing.edge)
                .padding(.top, 36)
                .padding(.bottom, 8)
            content
        }
        .background(AppColors.background.ignoresSafeArea())
        .fullScreenCover(item: $detailSeries) { series in
            DetailView(series: series)
        }
        // TEMP-DEBUG-HOOK: 端到端验证用，验完删除
        .task {
            if ProcessInfo.processInfo.arguments.contains("-AUTOPLAY_TEST") {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let api = ContentClient()
                if let s = api.cache.recentSeries(limit: 1).first { detailSeries = s }
            }
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

// MARK: - 顶部栏：左品牌标识 + 居中菜单胶囊

struct TopBar: View {
    @Binding var selection: AppTab
    @FocusState private var focusedTab: AppTab?

    var body: some View {
        HStack(spacing: 0) {
            // 左：品牌
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("红果短剧")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            // 中：菜单
            HStack(spacing: 6) {
                ForEach(AppTab.allCases, id: \.self) { t in
                    tabPill(t)
                }
            }

            Spacer()
        }
    }

    private func tabPill(_ t: AppTab) -> some View {
        let selected = selection == t
        return Button {
            selection = t
        } label: {
            Text(t.rawValue)
                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppColors.background : AppColors.textSecondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(selected ? AppColors.textPrimary : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(TabPillStyle())
        .focused($focusedTab, equals: t)
    }
}

/// 菜单胶囊焦点：聚焦时高亮表面 + 轻微放大
struct TabPillStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? AppColors.surfaceHigh : Color.clear)
            .clipShape(Capsule())
            .focusEffectDisabled()
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 12, y: 6)
            .animation(AppMotion.focus, value: isFocused)
    }
}

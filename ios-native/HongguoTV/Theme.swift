import SwiftUI

// MARK: - 统一设计系统：克制深色画布 + 电影感排版 + 原生焦点（tvOS 26 公开 SwiftUI）
// 设计语言：近黑画布 #0B0B0B、表面 #1A1A1F、主文字 #F5F5F7、次级 #A1A1AA、点缀 #5E9BFF；
// 焦点 = 1.04–1.08 柔和放大 + 柔影，0.28s easeOut；不使用液态玻璃 / 发光描边 / 夸张渐变。

// MARK: - 颜色

enum AppColors {
    /// 全局画布（近黑，非蓝紫渐变）
    static let background = Color(hex: 0x0B0B0B)
    /// 卡片 / 面板表面
    static let surface = Color(hex: 0x1A1A1F)
    /// 悬浮表面（选中/悬停中性态）
    static let surfaceHigh = Color(hex: 0x26262D)
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0xA1A1AA)
    static let textTertiary = Color.white.opacity(0.38)
    /// 点缀色（续播指示 / 链接）
    static let accent = Color(hex: 0x5E9BFF)
    static let separator = Color.white.opacity(0.10)
}

/// 向后兼容别名（逐步迁移到 AppColors）
enum Theme {
    static let background = AppColors.background
    static let backgroundGradient = AppColors.background
    static let accent = AppColors.accent
    static let textPrimary = AppColors.textPrimary
    static let textSecondary = AppColors.textSecondary
    static let textTertiary = AppColors.textTertiary
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - 字体阶梯

enum AppFont {
    /// Hero 大标题 42–56pt
    static let heroTitle = Font.system(size: 52, weight: .semibold)
    /// 详情页剧名
    static let detailTitle = Font.system(size: 46, weight: .semibold)
    /// 栏目标题 28–34pt
    static let section = Font.system(size: 29, weight: .semibold)
    /// 卡片剧名 24–32pt
    static let cardTitle = Font.system(size: 21, weight: .semibold)
    /// 正文 18–20pt
    static let body = Font.system(size: 20, weight: .regular)
    static let bodySmall = Font.system(size: 17, weight: .regular)
    /// 辅助信息 14–16pt
    static let aux = Font.system(size: 15, weight: .regular)
    /// 标签 / 元数据 12–14pt
    static let tag = Font.system(size: 14, weight: .medium)
}

// MARK: - 间距 / 动效

enum AppSpacing {
    /// 页面左右边距
    static let edge: CGFloat = 64
    /// 内容架之间的纵向间距
    static let shelf: CGFloat = 64
    /// 同排卡片间距
    static let card: CGFloat = 36
}

enum AppMotion {
    /// 焦点切换 0.2–0.35s（系统级动画曲线，不做弹性）
    static let focus = Animation.easeOut(duration: 0.28)
    /// 页面 / 板块淡入 0.3–0.5s
    static let page = Animation.easeOut(duration: 0.4)
}

// MARK: - 焦点修饰器：柔和放大 + 柔影（稳定不抖动，不做发光描边）

private struct FocusLiftStateKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private struct FocusLiftProbe: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Color.clear
            .preference(key: FocusLiftStateKey.self, value: isFocused)
    }
}

struct FocusLift: ViewModifier {
    var scale: CGFloat = 1.06
    @State private var isFocused = false

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .background(FocusLiftProbe())
            .scaleEffect(isFocused ? scale : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? 0.6 : 0.28),
                radius: isFocused ? 26 : 10,
                y: isFocused ? 16 : 6
            )
            .animation(AppMotion.focus, value: isFocused)
            .onPreferenceChange(FocusLiftStateKey.self) { isFocused = $0 }
    }
}

extension View {
    func focusLift(scale: CGFloat = 1.06, brighten: Bool = true) -> some View {
        modifier(FocusLift(scale: scale))
    }
}

// MARK: - 胶囊按钮：主按钮（白底黑字）/ 次按钮（深色表面）

struct CapsuleActionStyle: ButtonStyle {
    var primary: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .semibold))
            .padding(.horizontal, 36)
            .padding(.vertical, 15)
            .background(primary ? AppColors.textPrimary : AppColors.surface)
            .foregroundStyle(primary ? AppColors.background : AppColors.textPrimary)
            .clipShape(Capsule())
            .focusEffectDisabled()
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.3), radius: isFocused ? 18 : 8, y: 8)
            .animation(AppMotion.focus, value: isFocused)
    }
}

extension View {
    func primaryAction() -> some View { buttonStyle(CapsuleActionStyle(primary: true)) }
    func secondaryAction() -> some View { buttonStyle(CapsuleActionStyle(primary: false)) }
}

// MARK: - 海报卡片 ButtonStyle：聚焦放大 + 柔影，无系统描边/玻璃

struct PosterCardStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .hoverEffect(.highlight)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.28),
                    radius: isFocused ? 26 : 10, y: isFocused ? 16 : 6)
            .animation(AppMotion.focus, value: isFocused)
    }
}

// MARK: - Hero 主按钮：常态白底黑字；聚焦时切换为 tvOS 26 液态玻璃

struct HeroPlayStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        BaseBody(label: configuration.label, isFocused: isFocused)
    }

    private struct BaseBody: View {
        let label: ButtonStyleConfiguration.Label
        let isFocused: Bool

        var body: some View {
            label
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 38)
                .padding(.vertical, 16)
                .background(AppColors.textPrimary)
                .foregroundStyle(AppColors.background)
                .clipShape(Capsule())
                .focusEffectDisabled()
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0.35),
                        radius: isFocused ? 22 : 10, y: 10)
                .animation(AppMotion.focus, value: isFocused)
        }
    }
}

extension View {
    func heroPlayAction() -> some View { buttonStyle(HeroPlayStyle()) }
}

// MARK: - 内容架（栏目标题 + 横向滚动卡片行）

struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(AppFont.section)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.leading, AppSpacing.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppSpacing.card) {
                    content
                }
                .padding(.horizontal, AppSpacing.edge)
            }
        }
    }
}

// MARK: - 海报图片（异步加载 + 中性占位）

struct PosterImage: View {
    let url: String
    var corner: CGFloat = 12

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    AppColors.surface
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - 演员头像（圆形 + 姓名首字占位）

struct AvatarImage: View {
    let url: String
    let name: String
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(AppColors.surfaceHigh)
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

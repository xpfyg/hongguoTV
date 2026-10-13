import SwiftUI

// MARK: - Liquid Glass 主题：深色渐变画布（非纯黑）、半透明玻璃面板、聚焦高光选中块

enum Theme {
    /// 深蓝紫渐变画布（Liquid Glass 深色调背景，非纯黑）
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.17, green: 0.19, blue: 0.30), // 顶部偏亮蓝紫
            Color(red: 0.09, green: 0.10, blue: 0.18),
            Color(red: 0.05, green: 0.05, blue: 0.10),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let background = Color(red: 0.07, green: 0.08, blue: 0.14)
    /// 面板底色：透出背景的深蓝紫半透明（不再用黑色）
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.22).opacity(0.45)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.29) // #FF6B4A
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.78)
    static let textTertiary = Color.white.opacity(0.5)
    static let glassStroke = Color.white.opacity(0.18)
}

/// 液态玻璃面板：系统毛玻璃材质 + 顶部高光渐变 + 细描边（模拟 Liquid Glass 反光）
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 24
    var fill: Color = Theme.panel

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.glassStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 24, fill: Color = Theme.panel) -> some View {
        modifier(GlassPanel(radius: radius, fill: fill))
    }
}

/// Liquid Glass 选中块（tvOS 26 原生 glassEffect）：常态为淡玻璃底 + 微光描边；聚焦/选中时原生液态玻璃亮起、白色亮描边 + 顶部高光 + 轻微放大
struct GlassTile: ViewModifier {
    var selected: Bool
    var radius: CGFloat = 20
    var idleFill = Color.white.opacity(0.06)
    @Environment(\.isFocused) private var isFocused

    private var active: Bool { selected || isFocused }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if active {
            content
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.30), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                )
                .overlay(
                    shape.stroke(
                        isFocused ? Color.white.opacity(0.98) : Color.white.opacity(0.88),
                        lineWidth: isFocused ? 2.2 : 1.4
                    )
                )
                .clipShape(shape)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .shadow(color: .black.opacity(isFocused ? 0.65 : 0.22), radius: isFocused ? 20 : 8, y: 10)
                .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isFocused)
        } else {
            content
                .background(shape.fill(idleFill))
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 1.4))
                .clipShape(shape)
        }
    }
}

extension View {
    func glassTile(selected: Bool = false, radius: CGFloat = 20, idleFill: Color = Color.white.opacity(0.05)) -> some View {
        modifier(GlassTile(selected: selected, radius: radius, idleFill: idleFill))
    }
}

/// 主按钮（实心橙）+ 次按钮（玻璃）
struct ActionButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .bold))
            .padding(.horizontal, 36)
            .padding(.vertical, 16)
            .background(primary ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                Capsule()
                    .stroke(Theme.glassStroke, lineWidth: 1)
            )
            .foregroundStyle(primary ? Color.black : Color.white)
            .clipShape(Capsule())
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.8 : 0.4), radius: 16, y: 8)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isFocused)
            .contentShape(Capsule())
    }
}

extension View {
    func primaryAction() -> some View { buttonStyle(ActionButtonStyle(primary: true)) }
    func glassAction() -> some View { buttonStyle(ActionButtonStyle(primary: false)) }
}

// MARK: - 海报图片（异步加载 + 占位）

struct PosterImage: View {
    let url: String
    var corner: CGFloat = 14

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(colors: [Color(white: 0.12), Color(white: 0.06)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.textTertiary)
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
                    Circle().fill(Color(white: 0.16))
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

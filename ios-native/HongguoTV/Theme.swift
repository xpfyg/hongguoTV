import SwiftUI

// MARK: - Infuse 风格主题：纯黑画布、海报主视觉、聚焦放大 + 白描边、玻璃面板

enum Theme {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.03) // #050508
    static let panel = Color.black.opacity(0.55)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.29) // #FF6B4A
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.45)
    static let glassStroke = Color.white.opacity(0.14)
}

/// 玻璃面板：系统毛玻璃材质 + 细描边（Infuse 的半透明面板质感）
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 24
    var fill: Color = Theme.panel

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill.opacity(0.18))
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

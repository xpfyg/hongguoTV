import XCTest
import SwiftUI
import AVKit
@testable import HongguoTV

/// 沉浸播放器布局回归测试：
/// 修复「播放竖屏剧时播放器跑到屏幕最下面」的问题。
/// 直接把生产环境的 ImmersiveRootView 装进全屏宿主控制器，
/// 强制布局后遍历视图树找到 AVPlayerLayer，断言其 frame 在布局空间内居中。
/// 说明：断言基于「布局空间 = window 减去安全区」，兼容测试环境窗口的实际尺寸。
@MainActor
final class ImmersivePlayerLayoutTests: XCTestCase {

    /// 竖屏剧（9:16）：视频层必须按原比例全高、且在布局空间内水平+垂直居中
    func testPortraitVideoLayerIsCentered() {
        let result = playerLayerFrame(videoSize: CGSize(width: 1080, height: 1920))
        XCTAssertNotNil(result, "未找到播放器图层视图")
        guard let (f, layout) = result else { return }
        XCTAssertEqual(f.height, layout.height, accuracy: 1, "竖屏视频层应为全高，实际 height=\(f.height)")
        XCTAssertEqual(f.width, layout.height * (1080.0 / 1920.0), accuracy: 1, "竖屏视频层应按原比例 9:16，实际 width=\(f.width)")
        XCTAssertEqual(f.midX, layout.midX, accuracy: 1, "视频层必须水平居中，实际 midX=\(f.midX)")
        XCTAssertEqual(f.midY, layout.midY, accuracy: 1, "竖屏视频层必须垂直居中，实际 midY=\(f.midY)")
    }

    /// 尺寸未取到时（默认按 9:16）也必须居中，不能掉到屏幕底部
    func testUnknownSizeVideoLayerIsCentered() {
        let result = playerLayerFrame(videoSize: .zero)
        XCTAssertNotNil(result, "未找到播放器图层视图")
        guard let (f, layout) = result else { return }
        XCTAssertEqual(f.height, layout.height, accuracy: 1, "默认态视频层应为全高，实际 height=\(f.height)")
        XCTAssertEqual(f.midX, layout.midX, accuracy: 1, "默认态视频层必须水平居中，实际 midX=\(f.midX)")
        XCTAssertEqual(f.midY, layout.midY, accuracy: 1, "默认态视频层必须垂直居中，实际 midY=\(f.midY)")
    }

    /// 横屏剧铺满布局空间（仍居中）
    func testLandscapeVideoLayerFillsLayoutSpace() {
        let result = playerLayerFrame(videoSize: CGSize(width: 1920, height: 1080))
        XCTAssertNotNil(result, "未找到播放器图层视图")
        guard let (f, layout) = result else { return }
        XCTAssertEqual(f.width, layout.width, accuracy: 1, "横屏视频层应铺满宽度，实际 width=\(f.width)")
        XCTAssertEqual(f.height, layout.height, accuracy: 1, "横屏视频层应铺满高度，实际 height=\(f.height)")
        XCTAssertEqual(f.midX, layout.midX, accuracy: 1, "横屏视频层应水平居中，实际 midX=\(f.midX)")
        XCTAssertEqual(f.midY, layout.midY, accuracy: 1, "横屏视频层应垂直居中，实际 midY=\(f.midY)")
    }

    // MARK: - 辅助

    /// 用指定的 videoSize 构建播放器视图树，返回（播放器图层 frame，布局空间）
    private func playerLayerFrame(videoSize: CGSize) -> (frame: CGRect, layout: CGRect)? {
        let series = Series(id: "layout-test", title: "布局测试剧",
                            cover: "", description: "", badge: "", tags: "")
        let episodes = [Episode(id: "ep-1", number: 1, title: "第 1 集")]
        let model = ImmersivePlayerModel(series: series, episodes: episodes,
                                         initial: episodes[0], watchedIds: [])
        // 直接模拟 presentationSize 回调到达（跳过网络加载）
        model.videoSize = videoSize

        let root = ImmersiveRootView(model: model, onExit: {})
        let host = UIHostingController(rootView: root)
        // 挂到真实 window 上，SwiftUI 才会真正实例化 UIViewRepresentable 的视图树
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        window.rootViewController = host
        window.makeKeyAndVisible()
        // UIHostingController 默认把视图 Hug 成内容理想尺寸，用约束钉满 window，
        // 保证 SwiftUI 拿到的是全屏提案（与真实 fullScreenCover 一致）
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: window.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        window.layoutIfNeeded()
        // 跑一小段 runloop 等布局完成（此时 .task 的网络加载尚未返回，videoSize 仍为注入值）
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let playerView = findPlayerLayerView(host.view) else { return nil }
        // 换算到 window 坐标：playerView.frame 是相对 SwiftUI 中间容器的，不能直接用来断言位置
        let frame = playerView.convert(playerView.bounds, to: window)
        // SwiftUI 的布局空间 = window 减去安全区（tvOS 有上下安全区）
        let layout = window.bounds.inset(by: window.safeAreaInsets)
        // 清理：断开 window 引用，避免影响同进程其他测试
        window.rootViewController = nil
        window.isHidden = true
        return (frame, layout)
    }

    /// 递归查找 layer 为 AVPlayerLayer 的视图（PlayerLayerUIView）
    private func findPlayerLayerView(_ view: UIView) -> UIView? {
        if view.layer is AVPlayerLayer { return view }
        for sub in view.subviews {
            if let found = findPlayerLayerView(sub) { return found }
        }
        return nil
    }
}

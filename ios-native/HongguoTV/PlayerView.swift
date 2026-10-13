import SwiftUI
import AVKit

// MARK: - 播放器（AVPlayerViewController 包装）

struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onSave: (Double, Double, Bool) -> Void   // position, duration, completed
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        context.coordinator.playerViewController = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.attachObserver()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let parent: PlayerView
        weak var playerViewController: AVPlayerViewController?
        private var observer: Any?

        init(_ parent: PlayerView) {
            self.parent = parent
            super.init()
        }

        func attachObserver() {
            guard let player = playerViewController?.player, observer == nil else { return }
            let interval = CMTime(seconds: 5, preferredTimescale: 1)
            observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self, let item = player.currentItem else { return }
                let d = item.duration.seconds
                guard d.isFinite, d > 0 else { return }
                let pos = time.seconds
                let completed = pos > 0 && pos >= d - 3
                self.parent.onSave(pos, d, completed)
            }
        }

        func playerViewControllerDidDismiss(_ playerViewController: AVPlayerViewController) {
            cleanup()
        }

        private func cleanup() {
            if let observer {
                playerViewController?.player?.removeTimeObserver(observer)
                self.observer = nil
            }
            parent.onExit()
        }
    }
}

// MARK: - 测试播放器（Blender Big Buck Bunny 公开样片，不走内容服务）

struct TestPlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

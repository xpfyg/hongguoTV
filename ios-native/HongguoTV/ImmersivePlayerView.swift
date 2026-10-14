import SwiftUI
import AVFoundation
import AVKit
import Combine
import CoreImage
import CoreVideo

// MARK: - 沉浸模式播放器模型（持有 AVPlayer、切集、进度保存、播放状态观察）

@MainActor
final class ImmersivePlayerModel: ObservableObject {
    let series: Series
    let episodes: [Episode]
    @Published var currentEpisode: Episode
    @Published var isPaused = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var watchedIds: Set<String>
    @Published var videoSize: CGSize = .zero   // 0 = 尚未取到，按竖屏默认
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0

    let player = AVPlayer()
    /// 模糊背景帧（从前台 player 抽帧生成，保证跟随同一画面、零竞争）
    @Published var backgroundImage: UIImage?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var frameTimer: Timer?
    private var statusCancellable: AnyCancellable?
    private var timeObserver: Any?
    private var rateCancellable: AnyCancellable?
    private var sizeCancellable: AnyCancellable?
    private var isSeeking = false

    init(series: Series, episodes: [Episode], initial: Episode, watchedIds: Set<String>) {
        self.series = series
        self.episodes = episodes
        self.currentEpisode = initial
        self.watchedIds = watchedIds
    }

    func start() async {
        await load(episode: currentEpisode, fresh: false)
        observePlayer()
    }

    // 加载指定集：拉取播放地址并替换播放器 item
    func load(episode: Episode, fresh: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let api = ContentClient()
            let info = try await api.play(episodeId: episode.id, fresh: fresh)
            await replaceItem(uri: info.uri, episode: episode)
            currentEpisode = episode
        } catch {
            self.error = "播放失败，请重试"
        }
        isLoading = false
    }

    private func replaceItem(uri: String, episode: Episode) async {
        guard let url = URL(string: uri) else { return }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(CENCResourceLoader.shared,
                                         queue: .global(qos: .userInitiated))
        let item = AVPlayerItem(asset: asset)
        // 监听 presentationSize（已应用旋转，是真实显示尺寸）
        sizeCancellable = item.publisher(for: \.presentationSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard size.width > 0 else { return }
                self?.videoSize = size
            }
        player.replaceCurrentItem(with: item)

        // 从前台 item 抽帧做模糊背景
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        startFrameTimer()

        let api = ContentClient()
        let resume = api.cache.resume(for: series.id)
            .flatMap { $0.episodeId == episode.id ? $0.position : nil }
        let startPos = resume ?? 0
        if startPos > 0 {
            item.seek(to: CMTime(seconds: startPos, preferredTimescale: 600),
                      completionHandler: { _ in self.player.play() })
        } else {
            player.play()
        }
        isPaused = false
    }

    /// 每 ~150ms 从前台抽一帧，降采样 + 高斯模糊后作为背景
    private func startFrameTimer() {
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.grabBackgroundFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func grabBackgroundFrame() {
        guard let output = videoOutput,
              let item = player.currentItem else { return }
        let time = item.currentTime()
        guard time.isValid,
              output.hasNewPixelBuffer(forItemTime: time),
              let px = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        DispatchQueue.global(qos: .utility).async {
            let ci = CIImage(cvPixelBuffer: px)
                .transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1))
            let blurred = ci.applyingGaussianBlur(sigma: 24)
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(blurred, from: blurred.extent) else { return }
            let img = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                self.backgroundImage = img
            }
        }
    }

    private func observePlayer() {
        rateCancellable = player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                guard let self, let item = self.player.currentItem,
                      !self.isSeeking else { return }
                if item.status == .readyToPlay {
                    self.isPaused = (rate == 0)
                }
            }
        let interval = CMTime(seconds: 5, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let item = self.player.currentItem else { return }
            let d = item.duration.seconds
            if d.isFinite, d > 0 {
                self.elapsed = time.seconds
                self.duration = d
                let completed = time.seconds > 0 && time.seconds >= d - 3
                self.save(pos: completed ? 0 : time.seconds, dur: d, completed: completed)
            }
        }
    }

    func togglePlayPause() {
        if isPaused { player.play(); isPaused = false }
        else { player.pause(); isPaused = true }
    }

    func play() { player.play(); isPaused = false }

    func selectEpisode(_ ep: Episode) async {
        guard ep.id != currentEpisode.id else { play(); return }
        await load(episode: ep, fresh: false)
    }

    private func save(pos: Double, dur: Double, completed: Bool) {
        let api = ContentClient()
        api.cache.markWatched(
            seriesId: series.id, episodeId: currentEpisode.id,
            episodeNumber: currentEpisode.number, seriesTitle: series.title,
            episodeTitle: currentEpisode.title, position: pos, duration: dur, completed: completed)
        if completed { watchedIds.insert(currentEpisode.id) }
    }

    func cleanup() {
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        rateCancellable?.cancel()
        sizeCancellable?.cancel()
        statusCancellable?.cancel()
        frameTimer?.invalidate()
        frameTimer = nil
        if let item = player.currentItem, let output = videoOutput {
            item.remove(output)
        }
        videoOutput = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - AVPlayerLayer 承载视图（竖屏原比例居中，不拉伸不裁切）

private final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = gravity
        return v
    }
    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }
}

// MARK: - 遥控事件宿主（接收 Siri Remote 播放/暂停键）

final class ImmersiveHostVC: UIViewController {
    var onPlayPause: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses where p.type == .playPause {
            onPlayPause?()
            handled = true
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}

// MARK: - 沉浸模式根视图

struct ImmersivePlayerView: UIViewControllerRepresentable {
    @ObservedObject var model: ImmersivePlayerModel
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> ImmersiveHostVC {
        let vc = ImmersiveHostVC()
        let root = ImmersiveRootView(model: model, onExit: onExit)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        vc.addChild(host)
        vc.view.addSubview(host.view)
        host.view.frame = vc.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: vc)
        vc.onPlayPause = { [weak model] in model?.togglePlayPause() }
        context.coordinator.host = host
        return vc
    }

    func updateUIViewController(_ vc: ImmersiveHostVC, context: Context) {}

    static func dismantleUIViewController(_ vc: ImmersiveHostVC, coordinator: Coordinator) {
        // 退出时由 ImmersiveRootView 的 onDisappear 统一清理
    }

    final class Coordinator: NSObject {
        let parent: ImmersivePlayerView
        weak var host: UIHostingController<ImmersiveRootView>?
        init(_ p: ImmersivePlayerView) { parent = p }
    }
}

struct ImmersiveRootView: View {
    @ObservedObject var model: ImmersivePlayerModel
    let onExit: () -> Void
    @FocusState private var focusedPanel: PanelFocus?

    enum PanelFocus { case resume, episode, exit }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 仅竖屏才用实时模糊背景；横屏剧直接全屏播放
                if isPortrait {
                    ZStack {
                        AsyncImage(url: URL(string: model.series.cover)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                AppColors.background
                            }
                        }
                        if let bg = model.backgroundImage {
                            Image(uiImage: bg)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 40)
                                .clipped()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(model.isPaused ? 0.55 : 0.35))
                    .ignoresSafeArea()
                } else {
                    AppColors.background.ignoresSafeArea()
                }

                // 主视频层：竖屏原比例居中；横屏铺满
                PlayerLayerView(player: model.player,
                                gravity: isPortrait ? .resizeAspect : .resizeAspectFill)
                    .frame(width: videoSize(in: geo).width,
                           height: videoSize(in: geo).height)
                    .animation(.easeInOut(duration: 0.3), value: model.videoSize)

                // 加载态
                if model.isLoading {
                    ProgressView().scaleEffect(1.5).tint(.white)
                }

                // 退出按钮（始终可聚焦）
                VStack {
                    HStack {
                        Button {
                            onExit()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 56, height: 56)
                                .background(AppColors.surface.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .focused($focusedPanel, equals: .exit)
                        .focusLift(scale: 1.1)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(36)

                // 暂停浏览面板
                if model.isPaused && !model.isLoading {
                    pauseOverlay
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .task { await model.start() }
    }

    private var isPortrait: Bool {
        if model.videoSize.width > 0, model.videoSize.height > 0 {
            return model.videoSize.width < model.videoSize.height
        }
        return true // 未知尺寸按竖屏处理
    }

    private func videoSize(in geo: GeometryProxy) -> CGSize {
        let h = geo.size.height
        if model.videoSize.width > 0, model.videoSize.height > 0 {
            let aspect = model.videoSize.width / model.videoSize.height
            if aspect >= 1 { return geo.size }           // 横屏：铺满
            return CGSize(width: h * aspect, height: h)  // 竖屏：按原比例
        }
        // 未知尺寸：默认 9:16 居中
        return CGSize(width: h * 9.0/16.0, height: h)
    }

    // MARK: - 暂停信息 + 选集面板

    private var pauseOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.series.title)
                            .font(AppFont.detailTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("第 \(model.currentEpisode.number) 集\(model.currentEpisode.title.isEmpty ? "" : " · \(model.currentEpisode.title)")")
                            .font(AppFont.body)
                            .foregroundStyle(AppColors.textSecondary)
                        if !model.series.description.isEmpty {
                            Text(model.series.description)
                                .font(AppFont.bodySmall)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(3)
                                .frame(maxWidth: 620, alignment: .leading)
                        }
                        Button {
                            model.play()
                        } label: {
                            Label("继续播放", systemImage: "play.fill")
                        }
                        .primaryAction()
                        .focused($focusedPanel, equals: .resume)
                        .padding(.top, 4)
                    }
                    Spacer()
                }

                episodeStrip
            }
            .padding(36)
            .background(AppColors.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .onAppear { focusedPanel = .resume }
    }

    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选集")
                .font(AppFont.section)
                .foregroundStyle(AppColors.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(model.episodes) { ep in
                        Button {
                            Task { await model.selectEpisode(ep) }
                        } label: {
                            Text("\(ep.number)")
                                .font(AppFont.cardTitle)
                                .foregroundStyle(ep.id == model.currentEpisode.id ? AppColors.textPrimary : AppColors.textSecondary)
                                .frame(width: 72, height: 72)
                                .background(ep.id == model.currentEpisode.id ? AppColors.surfaceHigh : AppColors.surfaceHigh.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .focused($focusedPanel, equals: .episode)
                        .focusLift(scale: 1.1)
                    }
                }
            }
            .frame(height: 100)
        }
    }
}

// MARK: - 桥接：由 DetailView 创建模型并承载退出

struct ImmersivePlayerBridge: View {
    let series: Series
    let episodes: [Episode]
    let initial: Episode
    let watchedIds: Set<String>
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ImmersivePlayerModel

    init(series: Series, episodes: [Episode], initial: Episode, watchedIds: Set<String>) {
        self.series = series
        self.episodes = episodes
        self.initial = initial
        self.watchedIds = watchedIds
        _model = StateObject(wrappedValue: ImmersivePlayerModel(
            series: series, episodes: episodes, initial: initial, watchedIds: watchedIds))
    }

    var body: some View {
        ImmersivePlayerView(model: model) {
            model.cleanup()
            dismiss()
        }
        .ignoresSafeArea()
    }
}

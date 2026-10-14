import SwiftUI
import AVKit

// MARK: - 详情页：背景海报压暗 + 剧名/简介/播放操作突出 + 选集

struct DetailView: View {
    @Environment(\.dismiss) private var dismiss
    let series: Series

    @State private var current: Series
    @State private var detail: Detail?
    @State private var busy = false
    @State private var error: String?
    @State private var playingEpisode: Episode?
    @State private var playback: PlaybackInfo?
    @State private var playbackBusy = false
    @State private var playbackError: String?
    @State private var showEpisodes = false
    @State private var selectedActor: Celebrity?
    // SwiftData 接入：收藏状态 / 续播集 / 已看分集
    @State private var favorite = false
    @State private var resumeEpisodeId: String?
    @State private var watchedIds: Set<String> = []
    @FocusState private var playFocused: Bool
    @AppStorage("immersiveModeEnabled") private var immersiveMode = true

    init(series: Series) {
        self.series = series
        _current = State(initialValue: series)
    }

    var body: some View {
        ZStack {
            // 背景大海报（模糊压暗 → 近黑画布）
            AsyncImage(url: URL(string: current.cover)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                }
            }
            .blur(radius: 44)
            .overlay(
                LinearGradient(colors: [Color.black.opacity(0.62), Color(hex: 0x0B0B0B).opacity(0.92)],
                               startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea()

            // 固定布局：上为「大海报 + 剧名/简介/操作」主视觉区，下为紧凑选集
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 56) {
                    // 左：放大的竖版海报
                    PosterImage(url: current.cover, corner: 14)
                        .frame(width: 280, height: 420)
                        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 12)

                    // 右：名称/简介/操作/演职
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(current.title)
                                .font(AppFont.detailTitle)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(2)
                                .frame(maxWidth: 760, alignment: .leading)
                            HStack(spacing: 12) {
                                if !current.badge.isEmpty {
                                    badge(current.badge)
                                }
                                if !current.tags.isEmpty {
                                    Text(current.tags)
                                        .font(AppFont.bodySmall)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            Text(current.description)
                                .font(AppFont.body)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(5)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: 780, alignment: .leading)

                                HStack(spacing: 18) {
                                    Button {
                                        play(resumeEpisodeId, fresh: false)
                                    } label: {
                                        Label(resumeEpisodeId != nil ? "继续播放" : "播放", systemImage: "play.fill")
                                    }
                                    .primaryAction()
                                    .focused($playFocused)

                                    if resumeEpisodeId != nil {
                                        Button { play(nil, fresh: true) } label: {
                                            Label("从头播放", systemImage: "arrow.counterclockwise")
                                        }
                                        .secondaryAction()
                                    }

                                    Button {
                                        toggleFavorite()
                                    } label: {
                                        Label(favorite ? "已收藏" : "收藏", systemImage: "star.fill")
                                    }
                                    .secondaryAction()
                                }
                                .padding(.top, 8)

                                if playbackBusy {
                                    ProgressView().scaleEffect(1.2).padding(.top, 6)
                                } else if let playbackError {
                                    Text(playbackError)
                                        .font(AppFont.bodySmall)
                                        .foregroundStyle(AppColors.accent)
                                        .padding(.top, 4)
                                }

                                // 演职人员（点击查看相关剧集）
                                if let detail, let celes = detail.celebrities, !celes.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("演职人员")
                                            .font(AppFont.bodySmall)
                                            .foregroundStyle(AppColors.textSecondary)
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 18) {
                                                ForEach(celes) { c in
                                                    Button {
                                                        selectedActor = c
                                                    } label: {
                                                        VStack(spacing: 4) {
                                                            AvatarImage(url: c.avatar, name: c.name, size: 44)
                                                            VStack(spacing: 1) {
                                                                Text(c.name)
                                                                    .font(AppFont.aux)
                                                                    .foregroundStyle(AppColors.textPrimary)
                                                                    .lineLimit(1)
                                                                if !c.role.isEmpty {
                                                                    Text(c.role)
                                                                        .font(AppFont.tag)
                                                                        .foregroundStyle(AppColors.textSecondary)
                                                                        .lineLimit(1)
                                                                }
                                                            }
                                                            .frame(width: 88)
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    .focusLift(scale: 1.05, brighten: false)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                    }
                    .padding(.top, 20)

                    // 下：选集（独立滚动，任意集数可容纳）
                    VStack(alignment: .leading, spacing: 14) {
                        if let detail, showEpisodes {
                            if !detail.episodes.isEmpty {
                                Text("选集")
                                    .font(AppFont.section)
                                    .foregroundStyle(AppColors.textPrimary)
                                ScrollViewReader { proxy in
                                    ScrollView(.vertical, showsIndicators: false) {
                                        episodesGrid(detail.episodes)
                                            .id("ep-top")
                                    }
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("ep-top", anchor: .top)
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                            proxy.scrollTo("ep-top", anchor: .top)
                                        }
                                    }
                                    .frame(height: 300)
                                }
                            }
                        } else if busy {
                            ProgressView().scaleEffect(1.3)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else if let error {
                            Text(error).font(AppFont.body).foregroundStyle(AppColors.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                }
                .padding(.horizontal, AppSpacing.edge)
                .padding(.bottom, 40)
                .opacity(selectedActor == nil ? 1 : 0.12)
                .allowsHitTesting(selectedActor == nil)

                // 演职人员作品页（覆盖在当前详情之上，返回后恢复）
                if let actor = selectedActor {
                    ActorWorksView(
                        actor: actor,
                        onClose: { selectedActor = nil },
                        onOpenSeries: { s in
                            current = s
                            selectedActor = nil
                            detail = nil
                            showEpisodes = false
                        }
                    )
                    .transition(.opacity)
                }
            }
        .task(id: current.id) {
            await loadDetail()
            await loadLocalState()
            // TEMP-DEBUG-HOOK: 端到端验证用，验完删除
            if ProcessInfo.processInfo.arguments.contains("-AUTOPLAY_TEST") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                play(resumeEpisodeId, fresh: false)
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            playFocused = true
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.2)) { showEpisodes = true }
            // 选集网格出现可能抢走焦点，稍后再拉回「播放」按钮
            try? await Task.sleep(nanoseconds: 400_000_000)
            playFocused = true
        }
        .fullScreenCover(item: $playingEpisode) { episode in
            if immersiveMode, let detail {
                ImmersivePlayerBridge(series: current, episodes: detail.episodes,
                                      initial: episode, watchedIds: watchedIds)
            } else if let playback {
                NativePlayer(playback: playback, series: current, episode: episode)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(AppFont.aux)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppColors.surface)
            .clipShape(Capsule())
    }

    private func episodesGrid(_ eps: [Episode]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16)], spacing: 16) {
            ForEach(eps) { ep in
                EpisodeCell(ep: ep,
                            isResume: resumeEpisodeId == ep.id,
                            isWatched: watchedIds.contains(ep.id)) {
                    play(ep.id, fresh: false)
                }
            }
        }
    }

    // MARK: - SwiftData 本地状态

    private func loadLocalState() async {
        let api = ContentClient()
        favorite = await api.cache.isFavorite(seriesId: current.id)
        resumeEpisodeId = await api.cache.resume(for: current.id)?.episodeId
        watchedIds = await api.cache.watchedEpisodeIds(seriesId: current.id)
    }

    private func toggleFavorite() {
        let api = ContentClient()
        favorite = api.cache.toggleFavorite(current)
    }

    private func loadDetail() async {
        busy = true
        defer { busy = false }
        let api = ContentClient()
        do {
            detail = try await api.detail(id: series.id)
        } catch let caught {
            error = errorMessage(caught)
        }
    }

    private func play(_ episodeId: String?, fresh: Bool) {
        guard let detail else { return }
        let target: Episode
        if let episodeId, let ep = detail.episodes.first(where: { $0.id == episodeId }) {
            target = ep
        } else {
            target = detail.episodes[0]
        }
        playbackBusy = true
        playbackError = nil
        Task {
            let api = ContentClient()
            do {
                let info = try await api.play(episodeId: target.id, fresh: fresh)
                playback = info
                playingEpisode = target
            } catch {
                playbackError = errorMessage(error)
            }
            playbackBusy = false
        }
    }

    private func errorMessage(_ e: Error) -> String {
        if let ce = e as? ContentError { return ce.errorDescription ?? "请求失败" }
        if let ae = e as? APIError { return ae.errorDescription ?? "请求失败" }
        return "请求失败"
    }
}

// MARK: - 原生播放器全屏页（带鉴权头 + 进度保存）

struct NativePlayer: View {
    let playback: PlaybackInfo
    let series: Series
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                PlayerView(player: player,
                           onSave: { pos, dur, completed in
                               save(pos, dur, completed)
                           },
                           onExit: { dismiss() })
                    .ignoresSafeArea()
            } else {
                ProgressView().scaleEffect(1.6)
            }
        }
        .onAppear {
            guard player == nil else { return }
            // 直连模式：cenc:// 由 CENCResourceLoader 拉取源站流并分段解密，直接喂给 AVPlayer
            guard let url = URL(string: playback.uri) else { return }
            let asset = AVURLAsset(url: url)
            asset.resourceLoader.setDelegate(CENCResourceLoader.shared, queue: .global(qos: .userInitiated))
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            let api = ContentClient()
            let resumePosition = api.cache.resume(for: series.id).flatMap { $0.episodeId == episode.id ? $0.position : nil }
            if let pos = resumePosition, pos > 0 {
                item.seek(to: CMTime(seconds: pos, preferredTimescale: 600),
                          completionHandler: { _ in p.play() })
            } else {
                p.play()
            }
            player = p
        }
        .onDisappear {
            // 退出播放页时停止播放并释放流资源（防止返回后仍在后台播放）
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }

    private func save(_ pos: Double, _ dur: Double, _ completed: Bool) {
        // 接近结尾视为看完，位置归零便于下次从头播
        let finalPosition = completed ? 0 : pos
        let api = ContentClient()
        api.cache.markWatched(
            seriesId: series.id,
            episodeId: episode.id,
            episodeNumber: episode.number,
            seriesTitle: series.title,
            episodeTitle: episode.title,
            position: finalPosition,
            duration: dur,
            completed: completed
        )
    }
}

// MARK: - 选集单元格（裸内容 + 系统玻璃焦点）
// 设计约定：容器层交给系统（tvOS 26 玻璃板 = 焦点底板），内容层自己做
// （聚焦时数字提亮加粗、标题提亮）；不再垫自己的背景/圆角/缩放——
// 焦点容器只能有一个主人，否则玻璃板只剩一圈边缘，就是之前的"毛玻璃边款"。

struct EpisodeCell: View {
    let ep: Episode
    let isResume: Bool
    let isWatched: Bool
    let onPlay: () -> Void
    @Environment(\.isFocused) private var focused

    var body: some View {
        Button {
            onPlay()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Text("\(ep.number)")
                        .font(.system(size: 22, weight: focused ? .bold : .semibold))
                        .foregroundStyle(numberColor)
                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                            .padding(6)
                    }
                }
                if !ep.title.isEmpty {
                    Text(ep.title)
                        .font(AppFont.aux)
                        .foregroundStyle(focused ? AppColors.textSecondary : AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 104, height: 72)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(AppMotion.focus, value: focused)
        }
        .buttonStyle(.plain)
    }

    /// 常态弱化、聚焦提亮、续播用点缀蓝（不再依赖底色块，避免和玻璃板叠底）
    private var numberColor: Color {
        if focused { return AppColors.textPrimary }
        if isResume { return AppColors.accent }
        return isWatched ? AppColors.textTertiary : AppColors.textSecondary
    }
}

// MARK: - 演职人员作品页（搜索该演员的相关剧集）

struct ActorWorksView: View {
    let actor: Celebrity
    let onClose: () -> Void
    let onOpenSeries: (Series) -> Void

    @State private var profile: ActorProfile?
    @State private var items: [Series] = []
    @State private var page = 1
    @State private var busy = false
    @State private var error: String?
    @State private var noProfile = false
    @FocusState private var returnFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 28)]

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // 返回
                Button {
                    onClose()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .buttonStyle(.plain)
                .focused($returnFocused)
                .focusLift(scale: 1.05)
                .padding(.top, 30)

                // 演员信息
                HStack(alignment: .center, spacing: 32) {
                    AvatarImage(url: profile?.avatar.isEmpty == false ? profile!.avatar : actor.avatar,
                                name: actor.name, size: 128)
                        .frame(width: 128, height: 128)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(actor.name)
                            .font(AppFont.detailTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        if let profile, !profile.subtitle.isEmpty {
                            Text(profile.subtitle)
                                .font(AppFont.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        if let profile, !profile.description.isEmpty {
                            Text(profile.description)
                                .font(AppFont.bodySmall)
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(2)
                                .frame(maxWidth: 760, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 24)

                Text("相关剧集")
                    .font(AppFont.section)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.top, 28)
                    .padding(.bottom, 18)

                if busy && items.isEmpty {
                    ProgressView().scaleEffect(1.4).frame(maxWidth: .infinity, minHeight: 360)
                } else if let error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColors.textTertiary)
                        Text(error).font(AppFont.body).foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else if items.isEmpty {
                    Text("未找到相关剧集")
                        .font(AppFont.body)
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 34) {
                                ForEach(items) { s in
                                    PosterCard(series: s) {
                                        onOpenSeries(s)
                                    }
                                    .onAppear {
                                        if s.id == items.last?.id { Task { await loadMore() } }
                                    }
                                }
                            }
                            .id("works-top")
                            .padding(.bottom, 40)
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                proxy.scrollTo("works-top", anchor: .top)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                proxy.scrollTo("works-top", anchor: .top)
                            }
                        }
                        .frame(height: 560)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.edge)
        }
        .task {
            await load()
            try? await Task.sleep(nanoseconds: 350_000_000)
            returnFocused = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            returnFocused = true
        }
    }

    private func load() async {
        busy = true
        defer { busy = false }
        let api = ContentClient()
        do {
            let (p, list) = try await api.actorSearch(query: actor.name, page: 1)
            profile = p
            noProfile = (p == nil)
            items = list
            page = 1
        } catch let caught {
            error = errorMessage(caught)
        }
    }

    private func loadMore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let api = ContentClient()
        do {
            let next = page + 1
            let (_, more) = try await api.actorSearch(query: actor.name, page: next)
            guard !more.isEmpty else { return }
            page = next
            items += more.filter { m in !items.contains { $0.id == m.id } }
        } catch {}
    }

    private func errorMessage(_ e: Error) -> String {
        if let ce = e as? ContentError { return ce.errorDescription ?? "请求失败" }
        if let ae = e as? APIError { return ae.errorDescription ?? "请求失败" }
        return "请求失败"
    }
}

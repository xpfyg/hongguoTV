import SwiftUI
import AVKit

// MARK: - 详情页（Infuse 风格：背景海报模糊 + 前景信息 + 选集）

struct DetailView: View {
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    let series: Series

    @State private var detail: Detail?
    @State private var busy = false
    @State private var error: String?
    @State private var playingEpisode: Episode?
    @State private var playback: PlaybackInfo?
    @State private var playbackBusy = false
    @State private var playbackError: String?
    @State private var showEpisodes = false
    @FocusState private var playFocused: Bool

    private var resume: Progress? { store.progress(for: series.id) }

    var body: some View {
        ZStack {
            // 背景大海报（模糊压暗）
            AsyncImage(url: URL(string: series.cover)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                }
            }
            .blur(radius: 40)
            .overlay(
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea()

            // 固定布局（当前剧集数 ≤ ~70 集一屏可容纳；超长选集后续改为局部滚动）
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 48) {
                    // 左：竖版海报
                    PosterImage(url: series.cover, corner: 20)
                        .frame(width: 300, height: 450)

                        // 右：上为名称/简介/操作，下为选集
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 18) {
                                Text(series.title)
                                    .font(.system(size: 46, weight: .heavy))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                HStack(spacing: 12) {
                                    badge(series.badge)
                                    Text(series.tags)
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Text(series.description)
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(4)
                                    .frame(maxWidth: 720, alignment: .leading)

                                HStack(spacing: 20) {
                                    Button {
                                        play(resume?.episodeId, fresh: false)
                                    } label: {
                                        Label(resume != nil ? "继续播放" : "播放", systemImage: "play.fill")
                                    }
                                    .primaryAction()
                                    .focused($playFocused)

                                    if resume != nil {
                                        Button { play(nil, fresh: true) } label: {
                                            Label("从头播放", systemImage: "arrow.counterclockwise")
                                        }
                                        .glassAction()
                                    }

                                    Button {
                                        store.toggleFavorite(series)
                                    } label: {
                                        Label(store.isFavorite(series.id) ? "已收藏" : "收藏", systemImage: "star.fill")
                                    }
                                    .glassAction()
                                }

                                if playbackBusy {
                                    ProgressView().scaleEffect(1.2).padding(.top, 6)
                                } else if let playbackError {
                                    Text(playbackError)
                                        .font(.system(size: 20))
                                        .foregroundStyle(Theme.accent)
                                        .padding(.top, 4)
                                }
                            }

                            // 右下：选集（延迟渲染，避免抢初始焦点导致页面自动滚动）
                            VStack(alignment: .leading, spacing: 18) {
                                if let detail, showEpisodes {
                                    if !detail.episodes.isEmpty {
                                        Text("选集")
                                            .font(.system(size: 28, weight: .heavy))
                                            .foregroundStyle(Theme.textPrimary)
                                            .padding(.top, 36)
                                        episodesGrid(detail.episodes)
                                    }
                                } else if busy {
                                    ProgressView().scaleEffect(1.3)
                                        .frame(maxWidth: .infinity, minHeight: 160)
                                } else if let error {
                                    Text(error).font(.system(size: 22)).foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 72)
                .padding(.bottom, 70)
        }
        .task {
            await loadDetail()
            // 焦点先稳定在「播放」按钮，再渲染选集，避免 ScrollView 被选集抢焦点自动滚动
            try? await Task.sleep(nanoseconds: 350_000_000)
            playFocused = true
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.2)) { showEpisodes = true }
            // 选集网格出现可能抢走焦点，稍后再拉回「播放」按钮
            try? await Task.sleep(nanoseconds: 400_000_000)
            playFocused = true
        }
        .fullScreenCover(item: $playingEpisode) { episode in
            if let playback {
                NativePlayer(playback: playback, series: series, episode: episode)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(Color.black)
            .background(Theme.accent)
            .clipShape(Capsule())
    }

    private func episodesGrid(_ eps: [Episode]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 16)], spacing: 16) {
            ForEach(eps) { ep in
                Button {
                    play(ep.id, fresh: false)
                } label: {
                    VStack(spacing: 6) {
                        Text("\(ep.number)")
                            .font(.system(size: 22, weight: .bold))
                        if !ep.title.isEmpty {
                            Text(ep.title)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 104, height: 72)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(resume?.episodeId == ep.id ? Theme.accent : Theme.glassStroke, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .focusCard(radius: 14)
            }
        }
    }

    private func loadDetail() async {
        busy = true
        defer { busy = false }
        let api = APIClient(baseUrl: store.settings.baseUrl, token: store.settings.token)
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
            let api = APIClient(baseUrl: store.settings.baseUrl, token: store.settings.token)
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
        if let ae = e as? APIError { return ae.errorDescription ?? "请求失败" }
        return "请求失败"
    }
}

// MARK: - 原生播放器全屏页（带鉴权头 + 进度保存）

struct NativePlayer: View {
    let playback: PlaybackInfo
    let series: Series
    let episode: Episode
    @EnvironmentObject private var store: LocalStore
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
            // tvOS 不支持 AVURLAssetHTTPHeaderFieldsKey，改用自定义 scheme
            // （AuthURLProtocol）在转发请求时注入 Bearer 鉴权头
            let authUri = playback.uri.replacingOccurrences(of: "http://", with: "authstream://")
            guard let url = URL(string: authUri) else { return }
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            if let resume = store.progress(for: series.id),
               resume.episodeId == episode.id, resume.position > 0, !resume.completed {
                item.seek(to: CMTime(seconds: resume.position, preferredTimescale: 600),
                          completionHandler: { _ in p.play() })
            } else {
                p.play()
            }
            player = p
        }
    }

    private func save(_ pos: Double, _ dur: Double, _ completed: Bool) {
        var p = Progress(series: series,
                         episodeId: episode.id,
                         episodeNumber: episode.number,
                         position: pos,
                         duration: dur,
                         completed: completed,
                         updatedAt: Date().timeIntervalSince1970)
        // 接近结尾视为看完，位置归零便于下次从头播
        if completed { p.position = 0 }
        store.updateProgress(p)
    }
}

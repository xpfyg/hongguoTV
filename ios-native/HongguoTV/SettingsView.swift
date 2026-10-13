import SwiftUI
import AVKit

// MARK: - 设置页（服务地址 / 口令 / 连接测试 / 测试播放器）

struct SettingsView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var urlText = ""
    @State private var tokenText = ""
    @State private var checking = false
    @State private var status: String?
    @State private var statusOk = false
    @State private var showTestPlayer = false
    @FocusState private var urlFocused: Bool
    @FocusState private var tokenFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 6)
                Text("连接你的内容服务")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 10)
                Text("电视和运行服务的电脑/NAS 连接同一网络，填入服务启动后显示的地址。")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 30)

                VStack(spacing: 22) {
                    field(label: "服务地址", icon: "link") {
                        TextField("http://localhost:8787", text: $urlText)
                            .focused($urlFocused)
                            .keyboardType(.URL)
                    }
                    field(label: "访问口令（服务未设置时留空）", icon: "key.fill") {
                        TextField("", text: $tokenText)
                            .focused($tokenFocused)
                    }

                    HStack(spacing: 20) {
                        Button {
                            connect()
                        } label: {
                            Label(checking ? "连接中…" : "连接并保存", systemImage: "bolt.fill")
                        }
                        .primaryAction()

                        Button {
                            showTestPlayer = true
                        } label: {
                            Label("测试播放器", systemImage: "play.rectangle.fill")
                        }
                        .glassAction()
                    }
                    .padding(.top, 8)

                    if let status {
                        HStack(spacing: 10) {
                            Image(systemName: statusOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(statusOk ? .green : Theme.accent)
                            Text(status)
                                .font(.system(size: 20))
                                .foregroundStyle(statusOk ? Theme.textSecondary : Theme.accent)
                        }
                    }
                }
                .padding(34)
                .glassPanel(radius: 24)

                VStack(alignment: .leading, spacing: 12) {
                    note("测试播放器使用 Blender 的 Big Buck Bunny 公开样片，此测试不代表红果内容可用。")
                    note("收藏和观看记录仅保存在当前设备。")
                    note("本应用为个人非官方客户端。")
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 60)
        }
        .onAppear {
            urlText = store.settings.baseUrl
            tokenText = store.settings.token
        }
        .fullScreenCover(isPresented: $showTestPlayer) {
            TestPlayerView().ignoresSafeArea()
        }
    }

    private func field<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
                .font(.system(size: 24))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(urlFocused || tokenFocused ? Color.white : Theme.glassStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 19))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func connect() {
        let base = normalize(urlText)
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        status = nil
        Task {
            do {
                let api = APIClient(baseUrl: base, token: token)
                let health = try await api.health()
                store.settings.baseUrl = base
                store.settings.token = token
                store.connectedBaseUrl = base
                store.save()
                statusOk = true
                status = "连接成功（\(health.service) v\(health.version)，接口 v\(health.apiVersion)）"
            } catch {
                statusOk = false
                status = errorMessage(error)
            }
            checking = false
        }
    }

    private func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://" + s
        }
        return s
    }

    private func errorMessage(_ e: Error) -> String {
        if let ae = e as? APIError { return ae.errorDescription ?? "连接失败" }
        return "连接失败"
    }
}

import SwiftUI
import AVKit

// MARK: - 设置页（直连模式自检 / 测试播放器）

struct SettingsView: View {
    @State private var checking = false
    @State private var status: String?
    @State private var statusOk = false
    @State private var showTestPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 6)
                Text("直连模式")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 10)
                Text("本应用已脱离 Node 服务端：内容来自官网页面与 fqnovel App 接口，播放流在设备内直接解密，无需局域网服务。")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 30)

                VStack(spacing: 22) {
                    HStack(spacing: 20) {
                        Button {
                            connect()
                        } label: {
                            Label(checking ? "检查中…" : "检查直连", systemImage: "bolt.fill")
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
            if status == nil { connect() }
        }
        .fullScreenCover(isPresented: $showTestPlayer) {
            TestPlayerView().ignoresSafeArea()
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
        checking = true
        status = nil
        Task {
            do {
                let api = ContentClient()
                status = try await api.health()
                statusOk = true
            } catch {
                statusOk = false
                status = errorMessage(error)
            }
            checking = false
        }
    }

    private func errorMessage(_ e: Error) -> String {
        if let ce = e as? ContentError { return ce.errorDescription ?? "直连失败" }
        if let ae = e as? APIError { return ae.errorDescription ?? "直连失败" }
        return "直连失败"
    }
}

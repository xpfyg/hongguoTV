import SwiftUI
import AVKit

// MARK: - 设置页（测试播放器 / 诊断反馈）

struct SettingsView: View {
    @State private var showTestPlayer = false
    @State private var notes = ""
    @State private var report: String?
    @State private var savedPath: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 30)

                VStack(spacing: 22) {
                    HStack(spacing: 20) {
                        Button {
                            showTestPlayer = true
                        } label: {
                            Label("测试播放器", systemImage: "play.rectangle.fill")
                        }
                        .glassAction()
                    }
                    .padding(.top, 8)
                }
                .padding(34)
                .glassPanel(radius: 24)

                // MARK: 诊断反馈

                VStack(alignment: .leading, spacing: 16) {
                    Text("诊断反馈")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 34)
                    Text("应用出问题时，可填写问题描述并生成诊断报告。崩溃日志会自动记录在本地并包含在报告中。")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textTertiary)
                    Text("反馈方式：报告会完整显示在屏幕上（可用手机拍屏/录屏），同时保存到设备「诊断文件」目录，可通过 Xcode 设备文件取出后发给开发者。")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textTertiary)

                    TextField("问题描述（可选）：如「打开某剧集闪退」", text: $notes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .glassTile(radius: 16)

                    HStack(spacing: 20) {
                        Button {
                            report = Diagnostics.collectReport(notes: notes)
                            savedPath = nil
                        } label: {
                            Label(report == nil ? "生成诊断报告" : "重新生成", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .primaryAction()

                        if report != nil {
                            Button {
                                if let url = Diagnostics.saveReport(report ?? "") {
                                    savedPath = url.path
                                }
                            } label: {
                                Label(savedPath == nil ? "保存到设备" : "已保存", systemImage: "square.and.arrow.down.fill")
                            }
                            .glassAction()
                        }
                    }

                    if let report {
                        ScrollView(.vertical) {
                            Text(report)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        }
                        .frame(maxHeight: 460)
                        .glassPanel(radius: 16)
                        if let savedPath {
                            Text("已保存：\(savedPath)")
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
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
}

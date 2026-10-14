import SwiftUI
import AVKit

// MARK: - 设置页（测试播放器 / 诊断反馈）

struct SettingsView: View {
    @State private var showTestPlayer = false
    @State private var notes = ""
    @State private var report: String?
    @State private var savedPath: String?
    @AppStorage("immersiveModeEnabled") private var immersiveMode = true
    @State private var cacheSizeText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 22) {
                    immersiveRow
                }
                .padding(30)
                .surfaceCard()

                VStack(spacing: 22) {
                    HStack(spacing: 20) {
                        Button {
                            showTestPlayer = true
                        } label: {
                            Label("测试播放器", systemImage: "play.rectangle.fill")
                        }
                        .secondaryAction()
                    }
                    .padding(.top, 8)
                }
                .padding(30)
                .surfaceCard()
                .padding(.top, 22)

                // MARK: 视频缓存
                VStack(alignment: .leading, spacing: 14) {
                    Text("视频缓存")
                        .font(AppFont.section)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("播放过的剧集自动缓存到本机，二次播放秒开并节省流量。缓存上限约 2GB，超出自动清理。")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColors.textTertiary)
                    HStack(spacing: 20) {
                        Button {
                            VideoDiskCache.shared.clearAll()
                            refreshCacheSize()
                        } label: {
                            Label("清除视频缓存（\(cacheSizeText)）", systemImage: "trash")
                        }
                        .secondaryAction()
                    }
                }
                .padding(30)
                .surfaceCard()
                .padding(.top, 22)
                .onAppear { refreshCacheSize() }

                // MARK: 诊断反馈

                VStack(alignment: .leading, spacing: 16) {
                    Text("诊断反馈")
                        .font(AppFont.section)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("应用出问题时，可填写问题描述并生成诊断报告。崩溃日志会自动记录在本地并包含在报告中。")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColors.textTertiary)
                    Text("反馈方式：报告会完整显示在屏幕上（可用手机拍屏/录屏），同时保存到设备「诊断文件」目录，可通过 Xcode 设备文件取出后发给开发者。")
                        .font(AppFont.aux)
                        .foregroundStyle(AppColors.textTertiary)

                    TextField("问题描述（可选）：如「打开某剧集闪退」", text: $notes)
                        .textFieldStyle(.plain)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(AppColors.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                            .secondaryAction()
                        }
                    }

                    if let report {
                        ScrollView(.vertical) {
                            Text(report)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        }
                        .frame(maxHeight: 460)
                        .background(AppColors.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if let savedPath {
                            Text("已保存：\(savedPath)")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
                .padding(30)
                .surfaceCard()
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 12) {
                    note("测试播放器使用 Blender 的 Big Buck Bunny 公开样片，此测试不代表红果内容可用。")
                    note("收藏和观看记录仅保存在当前设备。")
                    note("本应用为个人非官方客户端。")
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, AppSpacing.edge)
            .padding(.bottom, 60)
        }
        .fullScreenCover(isPresented: $showTestPlayer) {
            TestPlayerView().ignoresSafeArea()
        }
    }

    // MARK: - 沉浸模式开关

    private func refreshCacheSize() {
        let bytes = VideoDiskCache.shared.totalCachedBytes()
        if bytes < 1024 * 1024 {
            cacheSizeText = String(format: "%.0f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            cacheSizeText = String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            cacheSizeText = String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
        if bytes == 0 { cacheSizeText = "0" }
    }

    private var immersiveRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $immersiveMode) {
                Label("沉浸模式", systemImage: "sparkles.tv")
                    .font(AppFont.section)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .tint(AppColors.accent)
            .focusEffectDisabled()
            Text("播放竖屏短剧时使用同源模糊背景填充屏幕，减少黑边；暂停时展示剧集信息与选集。关闭后回退到系统播放器。")
                .font(AppFont.bodySmall)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textTertiary)
            Text(text)
                .font(AppFont.aux)
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}
private extension View {
    func surfaceCard() -> some View {
        background(AppColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

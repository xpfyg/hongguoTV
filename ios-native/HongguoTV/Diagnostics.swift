import Foundation
import SwiftData
import UIKit
import Darwin

// MARK: - 诊断与反馈：崩溃日志本地捕获 + 一键生成诊断报告

/// 用户反馈方案：
/// 1. 崩溃自动落盘（uncaught exception + 致命信号），下次打开诊断页可见；
/// 2. 诊断页一键生成报告（版本 / 系统 / 设备 / 缓存统计 / 数据库大小 / 崩溃日志 / 用户描述），
///    支持复制到剪贴板或系统分享（邮件 / 信息 / 微信等），由用户发给开发者；
/// 3. 开发者侧可后续接入远程上报（把报告 POST 到自己的服务端），无需改动 UI。
enum Diagnostics {
    /// 崩溃日志路径（沙盒 Documents/diagnostics/crash.log）
    static var crashLogURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("diagnostics/crash.log")
    }

    private static var captureInstalled = false

    /// 安装崩溃捕获（App 启动时调用一次）
    static func setupCrashCapture() {
        guard !captureInstalled else { return }
        captureInstalled = true

        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(40).joined(separator: "\n")
            let reason = exception.reason ?? "无"
            Diagnostics.appendCrash("NSException [\(exception.name.rawValue)]: \(reason)\n\(stack)")
        }

        func installSignal(_ signal: Int32) {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { sig in
                Diagnostics.appendCrash("Fatal signal: \(sig)")
            }
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(signal, &action, nil)
        }
        [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE].forEach(installSignal)
    }

    static func appendCrash(_ text: String) {
        let url = crashLogURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\n===== \(stamp) =====\n\(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// 收集完整诊断报告（含用户描述与本地崩溃日志，截取最近 8KB）
    @MainActor
    static func collectReport(notes: String) -> String {
        var lines: [String] = []
        lines.append("红果 TV 诊断报告")
        lines.append("生成时间：\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        lines.append("应用版本：\(version) (\(build))")
        lines.append("系统版本：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        lines.append("设备型号：\(hardwareModel)")
        lines.append("")

        let ctx = SwiftDataStore.context
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
        }
        lines.append("本地数据量：")
        lines.append("  剧集缓存 \(count(SDSeries.self)) / 分集 \(count(SDEpisode.self)) / 演员 \(count(SDCelebrity.self))")
        lines.append("  收藏 \(count(SDFavorite.self)) / 观看记录 \(count(SDWatchState.self)) / 搜索历史 \(count(SDSearchHistory.self)) / 查询缓存 \(count(SDQueryCache.self))")
        if let dbURL = SwiftDataStore.container.configurations.first?.url,
           let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
           let size = attrs[.size] as? Int64 {
            lines.append("  数据库占用：\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        }
        lines.append("")

        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("用户描述：（未填写）")
        } else {
            lines.append("用户描述：")
            lines.append(notes)
        }
        lines.append("")

        let crash = (try? String(contentsOf: crashLogURL, encoding: .utf8)) ?? ""
        if crash.isEmpty {
            lines.append("崩溃日志：无记录")
        } else {
            lines.append("崩溃日志（最近记录）：")
            lines.append(String(crash.suffix(8192)))
        }
        lines.append("")
        lines.append("反馈渠道：请将本报告通过邮件 / 信息 / 飞书等方式发送给开发者。")

        return lines.joined(separator: "\n")
    }

    /// 保存报告到本地文件（Documents/diagnostics/report-时间戳.txt），返回文件路径
    @MainActor
    static func saveReport(_ report: String) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("diagnostics")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("report-\(stamp).txt")
        do {
            try Data(report.utf8).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 设备硬件型号（如 AppleTV14,1）；获取失败时回退 "Apple TV"
    private static var hardwareModel: String {
        var mib: [Int32] = [CTL_HW, HW_MACHINE]
        var len = 0
        guard sysctl(&mib, 2, nil, &len, nil, 0) == 0, len > 0 else { return "Apple TV" }
        var machine = [CChar](repeating: 0, count: len)
        guard sysctl(&mib, 2, &machine, &len, nil, 0) == 0 else { return "Apple TV" }
        let name = String(cString: machine)
        return name.isEmpty ? "Apple TV" : name
    }
}

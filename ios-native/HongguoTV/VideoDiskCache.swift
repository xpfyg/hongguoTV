import Foundation

/// 视频 Range 磁盘缓存：按集一个稀疏文件，存"已解密"的字节。
/// 命中后直接返回，不再走网络、不再解密。二次播放/双 player 共享此缓存。
final class VideoDiskCache {
    static let shared = VideoDiskCache()

    private let dir: URL
    private let blockSize: Int64 = 64 * 1024
    private let maxBytes: Int64 = 2 * 1024 * 1024 * 1024  // 2GB 上限
    private let lock = NSLock()
    // 内存中的位图：episodeId -> [UInt8]，每字节对应一个 block 是否存在
    private var bitmaps: [String: Data] = [:]

    private init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hongguo_video_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - 查询

    /// 尝试从磁盘读 [offset, offset+length) 的解密字节；未命中返回 nil。
    func read(episodeId: String, offset: Int64, length: Int) -> Data? {
        guard length > 0 else { return nil }
        let startBlock = offset / blockSize
        let endBlock = (offset + Int64(length) - 1) / blockSize
        lock.lock()
        defer { lock.unlock() }
        let bitmap = bitmap(episodeId)
        guard Int(endBlock) < bitmap.count else { return nil }
        for b in startBlock...endBlock {
            if bitmap[Int(b)] == 0 { return nil }
        }
        let file = dir.appendingPathComponent("\(episodeId).dat")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length)
        } catch {
            return nil
        }
    }

    // MARK: - 写入

    /// 写入一段已解密字节并标记位图。调用方在写完网络+解密后调用。
    func write(episodeId: String, offset: Int64, data: Data) {
        guard !data.isEmpty else { return }
        let file = dir.appendingPathComponent("\(episodeId).dat")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
        } catch { return }

        lock.lock()
        let startBlock = offset / blockSize
        let endBlock = (offset + Int64(data.count) - 1) / blockSize
        var bitmap = bitmap(episodeId)
        let need = Int(endBlock) + 1
        if bitmap.count < need {
            bitmap.append(Data(count: need - bitmap.count))
        }
        for b in startBlock...endBlock { bitmap[Int(b)] = 1 }
        bitmaps[episodeId] = bitmap
        persistBitmap(episodeId, bitmap: bitmap)
        lock.unlock()

        evictIfNeeded()
    }

    // MARK: - 位图持久化

    private func bitmap(_ episodeId: String) -> Data {
        if let b = bitmaps[episodeId] { return b }
        let idx = dir.appendingPathComponent("\(episodeId).idx")
        let b = (try? Data(contentsOf: idx)) ?? Data()
        bitmaps[episodeId] = b
        return b
    }

    private func persistBitmap(_ episodeId: String, bitmap: Data) {
        let idx = dir.appendingPathComponent("\(episodeId).idx")
        try? bitmap.write(to: idx, options: .atomic)
    }

    // MARK: - LRU 淘汰

    private func evictIfNeeded() {
        lock.lock()
        let keys = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        lock.unlock()
        // 计算 .dat 总大小
        var total: Int64 = 0
        var files: [(name: String, size: Int64, mtime: Date)] = []
        for name in keys where name.hasSuffix(".dat") {
            let p = dir.appendingPathComponent(name)
            if let attr = try? FileManager.default.attributesOfItem(atPath: p.path),
               let size = attr[.size] as? Int64,
               let mtime = attr[.modificationDate] as? Date {
                total += size
                files.append((name, size, mtime))
            }
        }
        guard total > maxBytes else { return }
        files.sort { $0.mtime < $1.mtime }
        for f in files {
            if total <= maxBytes { break }
            let base = String(f.name.dropLast(4)) // 去掉 .dat
            for ext in ["dat", "idx"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base).\(ext)"))
            }
            total -= f.size
            lock.lock()
            bitmaps.removeValue(forKey: base)
            lock.unlock()
        }
    }

    // MARK: - 设置页用

    /// 当前缓存总大小（字节）
    func totalCachedBytes() -> Int64 {
        let keys = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var total: Int64 = 0
        for name in keys where name.hasSuffix(".dat") {
            let p = dir.appendingPathComponent(name)
            if let attr = try? FileManager.default.attributesOfItem(atPath: p.path),
               let size = attr[.size] as? Int64 { total += size }
        }
        return total
    }

    /// 清空全部视频缓存
    func clearAll() {
        lock.lock()
        bitmaps.removeAll()
        lock.unlock()
        let keys = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in keys {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}

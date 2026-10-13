import Foundation
import Combine

// MARK: - 本地状态（设置 + 收藏 + 观看进度），JSON 持久化到 Documents

@MainActor
final class LocalStore: ObservableObject {
    @Published var settings = Settings()
    @Published var library = Library()
    @Published var connectedBaseUrl: String? = nil

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("hongguotv-state.json")
    }()

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(SavedState.self, from: data) {
            settings = decoded.settings
            library = decoded.library
        }
        syncTokenToUserDefaults()
    }

    func save() {
        let state = SavedState(settings: settings, library: library)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("LocalStore save failed: \(error)")
        }
        syncTokenToUserDefaults()
    }

    /// 把鉴权口令桥接给 AuthURLProtocol（URLProtocol 是非隔离上下文，不能直接读 @MainActor 状态）
    private func syncTokenToUserDefaults() {
        UserDefaults.standard.set(settings.token, forKey: "hongguotv.authToken")
    }

    func toggleFavorite(_ series: Series) {
        if let idx = library.favorites.firstIndex(where: { $0.id == series.id }) {
            library.favorites.remove(at: idx)
        } else {
            library.favorites.insert(series, at: 0)
        }
        save()
    }

    func isFavorite(_ id: String) -> Bool {
        library.favorites.contains { $0.id == id }
    }

    func updateProgress(_ p: Progress) {
        library.progress[p.series.id] = p
        save()
    }

    func progress(for seriesId: String) -> Progress? {
        library.progress[seriesId]
    }

    var recentProgress: [Progress] {
        library.progress.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct SavedState: Codable {
    var settings: Settings
    var library: Library
}

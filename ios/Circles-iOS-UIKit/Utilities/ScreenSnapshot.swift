import Foundation

/// The last thing a screen showed, per account, on this phone, so it can
/// open on it at once and refresh behind it (Wes, 2026-11-05: My Network
/// started blank every visit). Stale-while-revalidate only: a screen always
/// refreshes after showing its copy. Caches folder: the system may clear it,
/// and a missing copy just means a normal load. Cleared on sign-out.
enum ScreenSnapshot {
    private static var folder: URL? {
        guard let userId = AuthService.shared.getUserId(),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent("ScreenSnapshots", isDirectory: true).appendingPathComponent(userId, isDirectory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let url = folder?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let folder, let data = try? JSONEncoder().encode(value) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appendingPathComponent("\(key).json"), options: .atomic)
        }
    }

    static func clearAll() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("ScreenSnapshots", isDirectory: true))
    }
}

import Foundation

/// Cross-launch disk cache for the user's complete saved-places set.
///
/// Purpose: on a cold start the home map paints pins from the last session's
/// places in ~100ms instead of sitting empty behind a network fetch chain.
///
/// Invariants (these are what made the old in-memory cache safe to re-enable
/// after it was disabled for serving incomplete sets):
/// - `save` is ONLY called with a COMPLETE successful result of the batch
///   places fetch — never with a partially accumulated per-circle set.
/// - Readers treat the cache as stale-while-revalidate: paint it, then let the
///   in-flight network refresh REPLACE the set wholesale (never merge), so
///   deletions and edits disappear after one refresh.
final class PlacesDiskCache {
    static let shared = PlacesDiskCache()

    /// Bump when the cached payload shape changes; old versions are discarded.
    private static let cacheVersion = 1
    /// Stale cache still paints (revalidation is always in flight); beyond
    /// this age it's more likely misleading than helpful.
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private struct Payload: Codable {
        let version: Int
        let userId: String
        let savedAt: Date
        let places: [Place]
    }

    private let ioQueue = DispatchQueue(label: "com.circles.placesDiskCache", qos: .utility)

    private init() {}

    // Matched encoder/decoder pair — the cache only ever reads what it wrote,
    // so the strategy just has to agree with itself (not with the API).
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func cacheFileURL(for userId: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDir = dir.appendingPathComponent("PlacesCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        // userId is a Firebase UID / numeric id — safe as a filename component
        let safeId = userId.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("places-\(safeId).json")
    }

    /// Persist a COMPLETE place set. Callers must never pass a partial fetch.
    func save(places: [Place], userId: String) {
        guard !userId.isEmpty else { return }
        ioQueue.async {
            guard let url = self.cacheFileURL(for: userId) else { return }
            let payload = Payload(
                version: Self.cacheVersion,
                userId: userId,
                savedAt: Date(),
                places: places
            )
            do {
                let data = try self.makeEncoder().encode(payload)
                try data.write(to: url, options: .atomic)
                Logger.debug("💾 PlacesDiskCache: saved \(places.count) places (\(data.count) bytes)")
            } catch {
                Logger.debug("💾 PlacesDiskCache: save failed — \(error.localizedDescription)")
            }
        }
    }

    /// Load the cached set for instant paint. Completion fires on the main
    /// queue with nil when there is no usable cache.
    func load(userId: String, completion: @escaping ([Place]?) -> Void) {
        guard !userId.isEmpty else {
            completion(nil)
            return
        }
        ioQueue.async {
            var result: [Place]? = nil
            if let url = self.cacheFileURL(for: userId),
               let data = try? Data(contentsOf: url),
               let payload = try? self.makeDecoder().decode(Payload.self, from: data),
               payload.version == Self.cacheVersion,
               payload.userId == userId,
               Date().timeIntervalSince(payload.savedAt) < Self.maxAge,
               !payload.places.isEmpty {
                result = payload.places
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Drop the cache (logout, account switch).
    func clear(userId: String) {
        ioQueue.async {
            guard let url = self.cacheFileURL(for: userId) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

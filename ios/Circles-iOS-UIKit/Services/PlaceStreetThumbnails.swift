import UIKit
import MapKit

/// Small Apple Look Around pictures of found places for list rows (free and
/// rendered on the phone). Cached for the session, nil remembered for places
/// Apple has no street imagery for, so each place is asked once.
final class PlaceStreetThumbnails {
    static let shared = PlaceStreetThumbnails()

    private var cache: [String: UIImage] = [:]
    private var missing: Set<String> = []
    private var waiting: [String: [(UIImage?) -> Void]] = [:]
    private static let size = CGSize(width: 120, height: 120)

    private static func key(_ item: MKMapItem) -> String {
        let c = item.placemark.coordinate
        return String(format: "%.5f,%.5f|%@", c.latitude, c.longitude, item.name ?? "")
    }

    /// Completion on main; nil when Apple has no street picture there.
    func thumbnail(for item: MKMapItem, completion: @escaping (UIImage?) -> Void) {
        let key = Self.key(item)
        if let image = cache[key] { return completion(image) }
        if missing.contains(key) { return completion(nil) }
        if waiting[key] != nil { waiting[key]?.append(completion); return }
        waiting[key] = [completion]
        Task { @MainActor in
            var image: UIImage?
            if let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene {
                let options = MKLookAroundSnapshotter.Options()
                options.size = Self.size
                image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
            }
            if let image { self.cache[key] = image } else { self.missing.insert(key) }
            let callbacks = self.waiting.removeValue(forKey: key) ?? []
            callbacks.forEach { $0(image) }
        }
    }
}

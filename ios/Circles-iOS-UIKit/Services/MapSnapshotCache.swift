import MapKit
import UIKit

/// Map pictures for the Activity feed's check-in cards (2026-11-16): the
/// block around the place, no pin baked in (the card drops its own), kept in
/// memory per coordinate and size so a scroll back never redraws. Every
/// draw goes through `MapSnapshotRenderer` (one at a time, held to the end).
@MainActor
final class MapSnapshotCache {
    static let shared = MapSnapshotCache()

    struct Snapshot {
        let image: UIImage
        /// Where the place sits in the image
        let pinPoint: CGPoint
    }

    private final class Box { let value: Snapshot; init(_ value: Snapshot) { self.value = value } }
    private let cache = NSCache<NSString, Box>()
    private var inFlight: [String: Task<Snapshot?, Never>] = [:]

    private init() { cache.countLimit = 120 }

    private static func key(_ coordinate: CLLocationCoordinate2D, _ size: CGSize) -> String {
        String(format: "%.5f,%.5f,%.0fx%.0f", coordinate.latitude, coordinate.longitude, size.width, size.height)
    }

    /// The picture if it is already drawn
    func cached(at coordinate: CLLocationCoordinate2D, size: CGSize) -> Snapshot? {
        cache.object(forKey: Self.key(coordinate, size) as NSString)?.value
    }

    /// Draws (or waits for the draw already running) and keeps it. nil offline.
    func snapshot(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> Snapshot? {
        let key = Self.key(coordinate, size)
        if let hit = cache.object(forKey: key as NSString) { return hit.value }
        if let running = inFlight[key] { return await running.value }
        let task = Task<Snapshot?, Never> { @MainActor in
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 420, longitudinalMeters: 420)
            options.size = size
            options.mapType = .standard
            options.pointOfInterestFilter = .includingAll
            options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
            guard let drawn = await MapSnapshotRenderer.shared.map(options) else { return nil }
            return Snapshot(image: drawn.image, pinPoint: drawn.point(for: coordinate))
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache.setObject(Box(result), forKey: key as NSString) }
        return result
    }
}

import Foundation
import MapKit

/// Camera math for the full-screen map: the region or map rect that frames a
/// set of places, and the radius that shows a user's nearby favorites. Pure,
/// so the controller only decides WHEN to move the camera.
enum MapRegionFitter {
    /// A lone place is framed at this many meters across.
    static let singlePlaceMeters: CLLocationDistance = 2_000
    /// Bounding boxes grow by this factor so pins sit clear of the edges.
    static let spanPadding = 1.3
    /// The nearby-favorites radius: 2 miles at least, 25 miles at most.
    static let minFocusRadius: CLLocationDistance = 3_218.7
    static let maxFocusRadius: CLLocationDistance = 40_233.6

    /// The map rect enclosing every coordinate (nil when there are none). One
    /// coordinate yields a null rect: callers frame that with `singleRegion`.
    static func enclosingRect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var union = MKMapRect.null
        for coordinate in coordinates {
            union = union.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        return union
    }

    static func singleRegion(_ coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: singlePlaceMeters, longitudinalMeters: singlePlaceMeters)
    }

    /// The padded bounding-box region around the coordinates. `clampSpan`
    /// keeps the span inside MapKit's valid limits (and never below 0.01°)
    /// so `setRegion` never silently rejects it.
    static func boundingRegion(_ coordinates: [CLLocationCoordinate2D], clampSpan: Bool) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        var latDelta = (maxLat - minLat) * spanPadding
        var lonDelta = (maxLon - minLon) * spanPadding
        if clampSpan {
            latDelta = min(max(latDelta, 0.01), 180)
            lonDelta = min(max(lonDelta, 0.01), 360)
        }
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    /// Radius around the user that shows their nearby favorites. With three
    /// or more within 25 miles, fit the closest ten; otherwise zoom out just
    /// enough to reach the nearest few. `distances` may be in any order.
    static func focusRadius(distances: [CLLocationDistance]) -> CLLocationDistance {
        let sorted = distances.sorted()
        guard !sorted.isEmpty else { return maxFocusRadius }
        let withinMax = sorted.filter { $0 <= maxFocusRadius }.count
        if withinMax >= 3 {
            let targetIndex = min(9, withinMax - 1)
            return min(max(sorted[targetIndex] * 1.2, minFocusRadius), maxFocusRadius)
        }
        let targetIndex = min(2, sorted.count - 1)
        return max(sorted[targetIndex] * 1.2, minFocusRadius)
    }
}

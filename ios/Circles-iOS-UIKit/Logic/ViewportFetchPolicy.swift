import Foundation

/// Whether a map movement should load places for the new viewport.
///
/// Idle: any viewport not already covered by an earlier complete fetch loads
/// (the map is the way to browse). Searching: the list is the answer and a
/// fetch re-renders the map and the sheet under the person's finger, so only
/// a big change loads — the map zoomed out to at least twice the widest area
/// already fetched, or moved somewhere that overlaps nothing fetched (Wes,
/// 2026-09-25: "only if they expand the map some very large amount").
struct ViewportFetchPolicy {
    /// The viewport's radius must reach this multiple of the widest fetched
    /// radius to count as "expanded a lot" while searching.
    static let searchingExpansionFactor: Double = 2

    struct Viewport: Equatable {
        var latitude: Double
        var longitude: Double
        var radiusM: Double
    }

    static func shouldFetch(searching: Bool, viewport: Viewport, fetched: [Viewport]) -> Bool {
        if fetched.contains(where: { covers(viewport, by: $0) }) { return false }
        guard searching, !fetched.isEmpty else { return true }
        let widest = fetched.map(\.radiusM).max() ?? 0
        if viewport.radiusM >= widest * searchingExpansionFactor { return true }
        return !fetched.contains(where: { overlaps(viewport, $0) })
    }

    /// `fetched` fully contains `viewport`.
    static func covers(_ viewport: Viewport, by fetched: Viewport) -> Bool {
        distanceM(viewport, fetched) + viewport.radiusM <= fetched.radiusM
    }

    static func overlaps(_ a: Viewport, _ b: Viewport) -> Bool {
        distanceM(a, b) < a.radiusM + b.radiusM
    }

    /// Great-circle distance between the two centres.
    static func distanceM(_ a: Viewport, _ b: Viewport) -> Double {
        let earth = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earth * asin(min(1, h.squareRoot()))
    }
}

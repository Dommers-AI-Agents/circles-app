import CoreGraphics
import Foundation

/// Decides which map places keep a full category pin and which collapse to a
/// small dot (Google-style tiering, never clustering).
///
/// Pure screen-space logic, extracted from `FullScreenMapViewController` so it
/// can be unit tested: the controller projects each annotation to a point and
/// a priority distance, and this planner returns the ids that earn a full pin.
///
/// Greedy pass in priority order (nearest to the anchor first): a candidate
/// keeps its full pin if its pin rect doesn't collide with an already-accepted
/// pin, up to `maxFullPins`. Everything else renders as a dot. Zooming in frees
/// space, so dots promote automatically on the next recompute.
struct PinTierPlanner {
    struct Candidate: Equatable {
        let id: String
        /// Screen point of the place's coordinate. The marker balloon is
        /// bottom-anchored here, so its rect extends upward from this point.
        let point: CGPoint
        /// Priority: distance from the anchor (the user's location when it's
        /// on screen, else the map center). Smaller wins.
        let distance: Double
    }

    /// Hard cap on full pins; beyond it everything is a dot.
    var maxFullPins = 45
    /// Approximate on-screen footprint of a full MKMarkerAnnotationView.
    var pinSize = CGSize(width: 34, height: 42)
    /// Pins just off the visible edge still take part, so a pan doesn't make
    /// pins at the border pop in and out.
    var overscan = CGSize(width: 40, height: 50)

    /// - Parameters:
    ///   - candidates: every place annotation currently on the map.
    ///   - bounds: the map view's bounds (screen space).
    ///   - pinned: ids that keep a full pin no matter what (the selected
    ///     annotation — demoting it would yank its callout away).
    /// - Returns: the ids that render as full pins.
    func fullPinIds(for candidates: [Candidate], in bounds: CGRect, pinned: Set<String> = []) -> Set<String> {
        guard !candidates.isEmpty else { return [] }

        let visible = bounds.insetBy(dx: -overscan.width, dy: -overscan.height)
        var acceptedRects: [CGRect] = []
        var promoted = Set<String>()

        for candidate in candidates.sorted(by: { $0.distance < $1.distance }) {
            if promoted.count >= maxFullPins { break }
            guard visible.contains(candidate.point) else { continue }
            let rect = pinRect(at: candidate.point)
            if acceptedRects.contains(where: { $0.intersects(rect) }) { continue }
            acceptedRects.append(rect)
            promoted.insert(candidate.id)
        }
        promoted.formUnion(pinned)
        return promoted
    }

    func pinRect(at point: CGPoint) -> CGRect {
        CGRect(
            x: point.x - pinSize.width / 2,
            y: point.y - pinSize.height,
            width: pinSize.width,
            height: pinSize.height
        )
    }
}

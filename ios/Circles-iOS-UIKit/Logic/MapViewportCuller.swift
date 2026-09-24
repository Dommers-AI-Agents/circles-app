import Foundation
import MapKit

/// Which places get an annotation view right now.
///
/// MapKit makes a UIView for every annotation it is given, and our pins
/// carry `displayPriority = .required` so MapKit never hides one for us
/// (tiering is ours — see PinTierPlanner). With a home map that has a few
/// hundred saved places plus every viewport fetch merged in, that is a
/// thousand views to move on every pan, and the map — and the search sheet
/// over it — stutter. Only the places in and around the screen need a view;
/// the rest come back the moment the map reaches them.
///
/// The rect is padded so a normal pan lands inside it and nothing pops in at
/// the edge; a pan past the padding re-culls (debounced with the pin-tier
/// pass). A hard cap keeps a fully zoomed-out map honest too: nearest to the
/// centre win.
struct MapViewportCuller {
    /// The visible rect grown by this factor in each dimension (1.5 = a
    /// quarter-screen margin on every side).
    static let paddingFactor: Double = 1.5
    /// Never more annotation views than this, however far out the zoom.
    static let maxAnnotations = 400

    /// The places that should carry an annotation for `visibleRect`.
    /// A null or empty rect (map not laid out yet) keeps every place.
    static func placesToShow(_ places: [Place],
                             visibleRect: MKMapRect,
                             paddingFactor: Double = paddingFactor,
                             cap: Int = maxAnnotations) -> [Place] {
        guard !visibleRect.isNull, visibleRect.size.width > 0, visibleRect.size.height > 0 else { return places }
        let padded = paddedRect(visibleRect, factor: paddingFactor)
        let inside = places.filter { place in
            guard let c = place.location?.clLocation?.coordinate else { return false }
            return padded.contains(MKMapPoint(c))
        }
        guard inside.count > cap else { return inside }
        let centre = MKMapPoint(x: visibleRect.midX, y: visibleRect.midY)
        return inside
            .map { place -> (Place, Double) in
                let p = MKMapPoint(place.location!.clLocation!.coordinate)
                return (place, (p.x - centre.x) * (p.x - centre.x) + (p.y - centre.y) * (p.y - centre.y))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(cap)
            .map(\.0)
    }

    /// Whether the map has moved far enough from the last cull that the set
    /// must be recomputed: the visible rect left the padded rect, or the zoom
    /// changed by more than a quarter.
    static func needsRecull(previousVisibleRect: MKMapRect?, currentVisibleRect: MKMapRect,
                            paddingFactor: Double = paddingFactor) -> Bool {
        guard let previous = previousVisibleRect, !previous.isNull else { return true }
        let padded = paddedRect(previous, factor: paddingFactor)
        guard padded.contains(currentVisibleRect) else { return true }
        let zoomRatio = currentVisibleRect.size.width / max(previous.size.width, 1)
        return zoomRatio < 0.75 || zoomRatio > 1.25
    }

    static func paddedRect(_ rect: MKMapRect, factor: Double) -> MKMapRect {
        let extraW = rect.size.width * (factor - 1) / 2
        let extraH = rect.size.height * (factor - 1) / 2
        return rect.insetBy(dx: -extraW, dy: -extraH)
    }
}


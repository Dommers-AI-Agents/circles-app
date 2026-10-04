import MapKit
import UIKit

/// A picture of where a place is: an Apple map of the block with a pin.
/// The last resort for a saved place with no photo and no Look Around
/// coverage, so no place is left without one. Free and on-device (map
/// tiles need a connection; nil without one, and the caller retries later).
enum PlaceMapSnapshot {
    static func render(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350)
        options.size = size
        options.mapType = .standard
        options.pointOfInterestFilter = .includingAll
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        return withPin(snapshot, at: coordinate)
    }

    private static func withPin(_ snapshot: MKMapSnapshotter.Snapshot, at coordinate: CLLocationCoordinate2D) -> UIImage {
        let image = snapshot.image
        return UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
            let pin = UIImage(systemName: "mappin.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 44, weight: .bold))
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            guard let pin else { return }
            let point = snapshot.point(for: coordinate)
            let rect = CGRect(x: point.x - pin.size.width / 2, y: point.y - pin.size.height / 2,
                              width: pin.size.width, height: pin.size.height)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            pin.draw(in: rect)
        }
    }
}

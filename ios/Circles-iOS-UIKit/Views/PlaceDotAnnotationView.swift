import UIKit
import MapKit

/// Google Maps-style "minor place" marker: a small category-colored dot with a
/// white ring, sitting at the place's TRUE location.
///
/// Dots are the demoted tier of the map's decluttering: when the viewport is
/// zoomed out and full pins would overlap, the places nearest the user keep
/// their full category pins and the rest render as these dots — every saved
/// place stays individually visible and tappable, and dots promote back to
/// full pins as the user zooms in. Nothing ever collapses into a numbered
/// cluster bubble.
class PlaceDotAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PlaceDotAnnotation"

    private static let dotSize: CGFloat = 14
    // Dots are visually small but fingers aren't — extend the tap target
    private static let tapTargetSize: CGFloat = 26

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
        centerOffset = .zero
        canShowCallout = true
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        // We do our own decluttering — MapKit must never hide a dot on top of it
        displayPriority = .required
        collisionMode = .circle
        // Dots always layer BENEATH full pins (pins keep default zPriority) —
        // part of the Google look: minor places never draw over major ones
        zPriority = .min

        layer.cornerRadius = Self.dotSize / 2
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5
        layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
        ).cgPath
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCategoryColor(_ color: UIColor) {
        backgroundColor = color
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let inset = (Self.tapTargetSize - Self.dotSize) / 2
        return bounds.insetBy(dx: -inset, dy: -inset).contains(point)
    }
}

import UIKit

/// The Activity feed's motion (2026-11-16): rows arrive, a check-in's pin
/// drops and ripples, a saved place settles, a photo stack fans. Every move
/// collapses to a fade when Reduce Motion is on. UIKit and Core Animation
/// only.
enum ActivityChoreography {

    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A row scrolling in: a short rise from 18pt below, staggered per row
    static func entrance(_ view: UIView, delay: TimeInterval) {
        view.alpha = 0
        view.transform = reduced ? .identity : CGAffineTransform(translationX: 0, y: 18)
        UIView.animate(withDuration: reduced ? 0.25 : 0.35, delay: delay, options: [.curveEaseOut, .allowUserInteraction]) {
            view.alpha = 1
            view.transform = .identity
        }
    }

    /// A new row arriving live at the top: a longer rise, a little bounce
    static func arrival(_ view: UIView) {
        view.alpha = 0
        view.transform = reduced ? .identity : CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.97, y: 0.97)
        UIView.animate(withDuration: reduced ? 0.25 : 0.55, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction]) {
            view.alpha = 1
            view.transform = .identity
        }
    }

    /// A check-in: the pin drops in from above and two rings ripple out
    /// from where it lands. The rings are layers on `host`, removed when done.
    static func pinDrop(_ pin: UIView, ripplesIn host: UIView, at point: CGPoint) {
        pin.alpha = 1
        guard !reduced else { return }
        pin.transform = CGAffineTransform(translationX: 0, y: -44)
        pin.alpha = 0
        UIView.animate(withDuration: 0.6, delay: 0.05, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: [.allowUserInteraction]) {
            pin.transform = .identity
            pin.alpha = 1
        }
        for (index, radius) in [36.0, 58.0].enumerated() {
            let ring = CAShapeLayer()
            ring.name = "ripple"
            ring.path = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).cgPath
            ring.fillColor = nil
            ring.strokeColor = Constants.Colors.primary.withAlphaComponent(0.9).cgColor
            ring.lineWidth = 2
            ring.opacity = 0
            host.layer.addSublayer(ring)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.3
            scale.toValue = 1.0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0]
            fade.keyTimes = [0, 0.25, 1]
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.1
            group.beginTime = CACurrentMediaTime() + 0.45 + Double(index) * 0.18
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = true
            ring.bounds = host.bounds
            ring.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
            ring.anchorPoint = CGPoint(x: point.x / max(host.bounds.width, 1), y: point.y / max(host.bounds.height, 1))
            ring.position = point
            ring.add(group, forKey: "ripple")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { ring.removeFromSuperlayer() }
        }
    }

    /// Rings a previous card left behind (cell reuse)
    static func clearRipples(in host: UIView) {
        host.layer.sublayers?.filter { $0.name == "ripple" }.forEach { $0.removeFromSuperlayer() }
    }

    /// A saved place: the photo starts a touch small and faint and settles
    static func settle(_ view: UIView) {
        guard !reduced else { view.alpha = 1; return }
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
            view.alpha = 1
            view.transform = .identity
        }
    }

    /// A chip ("Saved to Brunch") slides in from the left after the photo lands
    static func slideInChip(_ chip: UIView, delay: TimeInterval = 0.15) {
        chip.alpha = 0
        chip.transform = reduced ? .identity : CGAffineTransform(translationX: -24, y: 0)
        UIView.animate(withDuration: reduced ? 0.2 : 0.35, delay: delay, options: [.curveEaseOut, .allowUserInteraction]) {
            chip.alpha = 1
            chip.transform = .identity
        }
    }
}

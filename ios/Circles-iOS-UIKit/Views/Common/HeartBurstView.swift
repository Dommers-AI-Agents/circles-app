import UIKit

/// The double-tap heart: pops up at the tap, swells, then shrinks away.
/// Shared by the Moments reel and the Activity feed's hero cards (2026-11-16).
enum HeartBurstView {
    static func show(at point: CGPoint, in view: UIView, size: CGFloat = 80) {
        let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
        heart.tintColor = .systemRed
        heart.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        heart.alpha = 0
        heart.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        view.addSubview(heart)
        let reduced = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduced ? 0.15 : 0.3, delay: 0, options: .curveEaseOut, animations: {
            heart.transform = reduced ? .identity : CGAffineTransform(scaleX: 1.3, y: 1.3)
            heart.alpha = 0.85
        }) { _ in
            UIView.animate(withDuration: reduced ? 0.15 : 0.25, delay: reduced ? 0.2 : 0.05, animations: {
                heart.transform = reduced ? .identity : CGAffineTransform(scaleX: 0.8, y: 0.8)
                heart.alpha = 0
            }) { _ in
                heart.removeFromSuperview()
            }
        }
    }
}

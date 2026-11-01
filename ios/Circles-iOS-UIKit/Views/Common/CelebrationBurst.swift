import UIKit

/// Confetti from the top of a view plus a short banner ("Saved to your map ·
/// +25 points"), for moments worth a celebration that don't need a screen of
/// their own: the store the App Clip saved, on the app's first launch
/// (Wes, 2026-11-01).
enum CelebrationBurst {

    static func show(_ text: String, over view: UIView) {
        rainConfetti(over: view)
        showBanner(text, over: view)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func rainConfetti(over view: UIView) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -20)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        let colors: [UIColor] = [Constants.Colors.primary, .systemYellow, .systemRed, .systemGreen, .systemOrange, .white]
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = piece(color).cgImage
            cell.birthRate = 7
            cell.lifetime = 6
            cell.velocity = 190
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 5
            cell.spin = 3.2
            cell.spinRange = 4
            cell.scale = 0.7
            cell.scaleRange = 0.35
            cell.yAcceleration = 90
            return cell
        }
        view.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { emitter.removeFromSuperlayer() }
    }

    private static func showBanner(_ text: String, over view: UIView) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        let pill = UIView()
        pill.backgroundColor = UIColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 0.92)
        pill.layer.cornerRadius = 22
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -20),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            pill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
        pill.alpha = 0
        pill.transform = CGAffineTransform(translationX: 0, y: -30)
        UIView.animate(withDuration: 0.35, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            pill.alpha = 1
            pill.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 3.2, options: []) {
            pill.alpha = 0
        } completion: { _ in pill.removeFromSuperview() }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private static func piece(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 14)).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 10, height: 14))
        }
    }
}

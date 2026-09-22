import UIKit

/// The thin strip under the status bar that says the app is showing saved
/// data because the phone has no connection. Shown and hidden by the tab
/// bar controller from `NetworkMonitor`; slides in and out so a flapping
/// connection doesn't flash.
final class OfflineBannerView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.text = "You're offline — showing saved data"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var shownConstraint: NSLayoutConstraint?
    private var hiddenConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemGray
        isAccessibilityElement = true
        accessibilityLabel = label.text
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Pins the banner just below `guide`'s top (the safe area) in `container`,
    /// starting hidden above it.
    func install(in container: UIView, below guide: UILayoutGuide) {
        container.addSubview(self)
        let shown = topAnchor.constraint(equalTo: guide.topAnchor)
        let hidden = bottomAnchor.constraint(equalTo: container.topAnchor)
        shownConstraint = shown
        hiddenConstraint = hidden
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hidden
        ])
        isHidden = true
    }

    func setOffline(_ offline: Bool, animated: Bool) {
        guard let superview, let shownConstraint, let hiddenConstraint else { return }
        guard offline != (shownConstraint.isActive) else { return }
        if offline { isHidden = false }
        hiddenConstraint.isActive = !offline
        shownConstraint.isActive = offline
        superview.bringSubviewToFront(self)
        let finish = { if !offline { self.isHidden = true } }
        guard animated else { superview.layoutIfNeeded(); finish(); return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
            superview.layoutIfNeeded()
        } completion: { _ in finish() }
    }
}

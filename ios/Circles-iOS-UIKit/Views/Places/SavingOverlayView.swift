import UIKit

/// Full-screen working overlay for a multi-step save. The staged alerts
/// ("Checking...", "Creating Place") block while presented, but the
/// transitions between them leave brief windows where taps land on the
/// form — this covers the whole host (nav bar included, when the host is
/// the window) with a spinner so it reads as "working".
final class SavingOverlayView: UIView {
    private let spinner = UIActivityIndicatorView(style: .large)

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Covers `host` entirely; added before any alert is presented so the
    /// alerts still land on top.
    func show(in host: UIView) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        spinner.startAnimating()
        host.addSubview(self)
    }

    func hide() {
        spinner.stopAnimating()
        removeFromSuperview()
    }
}

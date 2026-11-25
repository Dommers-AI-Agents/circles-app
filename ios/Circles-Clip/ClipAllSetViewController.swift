import StoreKit
import UIKit

/// The last screen (2026-11-24): what they did here, what the app adds, and
/// the way in — the gold button and Apple's install banner, which only shows
/// now, after the steps, for a new account.
final class ClipAllSetViewController: ClipStepViewController, SKOverlayDelegate {
    private var overlayPresented = false

    init(flow: ClipOnboardingFlow) {
        super.init(flow: flow, step: nil, primary: "Get the FavCircles app")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        hookLabel.attributedText = ClipTheme.hookText("You're set up.", "Get the app.", size: 44)
        detailLabel.text = "Everything you just did is waiting in the app, signed in."

        let summary = flow.summary
        let done = UIStackView()
        done.axis = .vertical
        done.spacing = 8
        done.addArrangedSubview(caption("DONE HERE"))
        var lines: [String] = []
        if let store = flow.store {
            if store.saved {
                lines.append(store.awardedPoints > 0 ? "\(store.name) saved · +\(store.awardedPoints) points" : "\(store.name) saved")
            } else {
                // The scan couldn't save it just now; the app's own flow finishes it
                lines.append("\(store.name) goes on your map when the app opens")
            }
        }
        if summary.zipcodeSet {
            lines.append(summary.city.map { "Map centered on \($0)" } ?? "Your zip is on your profile")
        }
        if summary.favoritesSaved > 0 {
            lines.append("\(summary.favoritesSaved) \(flow.store == nil ? "" : "more ")place\(summary.favoritesSaved == 1 ? "" : "s") on your map")
        }
        if summary.followed > 0 { lines.append("Following \(summary.followed) local\(summary.followed == 1 ? "" : "s")") }
        if summary.requested > 0 { lines.append("\(summary.requested) follow request\(summary.requested == 1 ? "" : "s") sent") }
        if lines.isEmpty { lines.append("Your account is ready") }
        lines.forEach { done.addArrangedSubview(line("checkmark.circle.fill", $0, tint: ClipTheme.gold)) }
        done.setCustomSpacing(16, after: done.arrangedSubviews.last!)
        done.addArrangedSubview(caption("THE APP ADDS"))
        ["Your whole map, circles and friends' picks",
         "Friends from your contacts, visit points nearby",
         "Store cards in Apple Wallet, widgets and more"].forEach { done.addArrangedSubview(line("plus.circle", $0, tint: UIColor.white.withAlphaComponent(0.85))) }
        let box = panel(done)
        stack.addArrangedSubview(box)
        ClipTheme.animateIn([stepLabel, hookLabel, detailLabel, box, primaryButton])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flow.finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.presentInstallOverlay() }
        #if DEBUG
        ClipAutopilot.shared?.ready(self)
        #endif
    }

    private func line(_ symbol: String, _ text: String, tint: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        icon.tintColor = tint
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium))
        label.text = text
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 10
        row.alignment = .center
        return row
    }

    /// Straight to the App Store page (the banner can't be shown twice and
    /// shows nothing for a clip that didn't come from the App Store)
    override func primaryTapped() {
        if let url = URL(string: "https://apps.apple.com/us/app/favcircles/id6746807095") {
            UIApplication.shared.open(url)
        }
    }

    private func presentInstallOverlay() {
        guard !overlayPresented, let scene = view.window?.windowScene else { return }
        overlayPresented = true
        let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
        overlay.delegate = self
        overlay.present(in: scene)
    }

    // Apple's banner slides up over the bottom: keep the button above it
    nonisolated func storeOverlayWillStartPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let end = transitionContext.endFrame
        Task { @MainActor in
            guard let window = self.view.window else { return }
            self.lift(aboveBannerIn: window, frame: end)
        }
    }
}

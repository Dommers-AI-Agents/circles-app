import UIKit
import StoreKit

// Final clip screen: persist the credential mailbox, redeem the sticker code,
// celebrate the points (confetti + count-up), and push the full-app install
// via SKOverlay.
final class ClipSuccessViewController: UIViewController {

    private let authResponse: ClipAuthResponse
    private let provider: String
    private let code: String
    private let preview: VenuePreview

    private var gradient: CAGradientLayer?
    private let stack = UIStackView()
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var overlayPresented = false
    private var countUpTimer: Timer?

    init(authResponse: ClipAuthResponse, provider: String, code: String, preview: VenuePreview) {
        self.authResponse = authResponse
        self.provider = provider
        self.code = code
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        gradient = ClipTheme.installGradient(on: view)
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()

        // Hand the session to the full app FIRST — even if the scan call fails,
        // the install lands logged in.
        ClipHandoff.storeAuthHandoff(response: authResponse, provider: provider)

        if preview.isGeneric {
            // Generic join: nothing to redeem — the welcome gifts are claimed in
            // the full app. Mark the code handled so the full app's first launch
            // doesn't re-run the sticker flow on it.
            ClipHandoff.markStickerHandled(code)
            showGenericWelcome()
        } else {
            redeem()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient?.frame = view.bounds
    }

    deinit {
        countUpTimer?.invalidate()
    }

    private func setupUI() {
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        emojiLabel.font = .systemFont(ofSize: 76)
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        detailLabel.font = .systemFont(ofSize: 17)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        spinner.color = .white
        spinner.startAnimating()

        [emojiLabel, titleLabel, detailLabel, spinner].forEach { stack.addArrangedSubview($0) }
        emojiLabel.isHidden = true

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -50),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30)
        ])

        titleLabel.text = "Creating your rewards…"
    }

    private func redeem() {
        Task { @MainActor in
            do {
                let result = try await ClipAPIClient.shared.redeemSticker(code: code, token: authResponse.token)
                // Scan handled in-clip — tell the full app not to redeem it again
                ClipHandoff.markStickerHandled(code)
                showAwarded(result)
            } catch {
                // Let the full app's existing pending-sticker flow finish the award
                ClipHandoff.markStickerPending(code)
                showPending()
            }
        }
    }

    private func showAwarded(_ result: ScanResult) {
        spinner.stopAnimating()
        spinner.isHidden = true
        emojiLabel.isHidden = false
        emojiLabel.text = "🎉"

        if let award = result.awarded {
            detailLabel.text = "Spend them at \(preview.venueName). Get the full FavCircles app to browse offers, save places, and keep earning."
            celebrate(points: award.points)
        } else {
            // Idempotent replay or outside the signup window — still a win state
            titleLabel.text = "You're in!"
            let balance = result.venueBalance ?? 0
            detailLabel.text = balance > 0
                ? "You have \(balance) points at \(preview.venueName). Get the full app to spend them."
                : "Welcome to FavCircles! Get the full app to start earning at \(preview.venueName)."
            popEmoji()
            presentInstallOverlay(afterDelay: 1.2)
        }
    }

    private func showGenericWelcome() {
        spinner.stopAnimating()
        spinner.isHidden = true
        emojiLabel.isHidden = false
        emojiLabel.text = "🎉"
        titleLabel.text = "You earned \(preview.favCoinBonus) FavCoins!"
        detailLabel.text = "Add your first place for 25 more. Get the full FavCircles app to claim them and start earning at partner stores."
        popEmoji()
        rainConfetti()
        presentInstallOverlay(afterDelay: 1.6)
    }

    private func showPending() {
        spinner.stopAnimating()
        spinner.isHidden = true
        emojiLabel.isHidden = false
        emojiLabel.text = "✅"
        titleLabel.text = "Account created!"
        detailLabel.text = "Your \(preview.signupBonusPoints) points at \(preview.venueName) are on the way — open the full app to collect them."
        popEmoji()
        presentInstallOverlay(afterDelay: 1.2)
    }

    // MARK: - Celebration

    private func celebrate(points: Int) {
        popEmoji()
        rainConfetti()

        // Count up 0 → points in sync with the confetti
        var shown = 0
        let stepDuration = 0.9 / Double(max(points, 1))
        titleLabel.text = "You earned 0 points!"
        countUpTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            shown += max(1, points / 60)
            if shown >= points {
                shown = points
                timer.invalidate()
                // Little bounce on landing
                UIView.animate(withDuration: 0.12, animations: {
                    self.titleLabel.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
                }) { _ in
                    UIView.animate(withDuration: 0.2) { self.titleLabel.transform = .identity }
                }
            }
            self.titleLabel.text = "You earned \(shown) points!"
        }

        presentInstallOverlay(afterDelay: 1.6)
    }

    private func popEmoji() {
        emojiLabel.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        emojiLabel.alpha = 0
        UIView.animate(withDuration: 0.6,
                       delay: 0,
                       usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.8) {
            self.emojiLabel.transform = .identity
            self.emojiLabel.alpha = 1
        }
    }

    private func rainConfetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -20)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)

        let colors: [UIColor] = [
            UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1),  // gold
            .white,
            UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1), // teal accent
            UIColor(red: 1.0, green: 0.45, blue: 0.55, alpha: 1),  // pink
            UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1)   // light blue
        ]

        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = Self.confettiImage(color: color).cgImage
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

        // Burst, then let the last pieces fall and clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            emitter.removeFromSuperlayer()
        }
    }

    private static func confettiImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 10, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func presentInstallOverlay(afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.overlayPresented,
                  let scene = self.view.window?.windowScene else { return }
            self.overlayPresented = true
            let config = SKOverlay.AppClipConfiguration(position: .bottom)
            SKOverlay(configuration: config).present(in: scene)
        }
    }
}

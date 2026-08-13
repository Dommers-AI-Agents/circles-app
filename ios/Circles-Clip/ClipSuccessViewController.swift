import UIKit
import StoreKit

// Final clip screen: persist the credential mailbox, redeem the sticker code,
// celebrate the points, and push the full-app install via SKOverlay.
final class ClipSuccessViewController: UIViewController {

    private let authResponse: ClipAuthResponse
    private let provider: String
    private let code: String
    private let preview: VenuePreview

    private let stack = UIStackView()
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var overlayPresented = false

    init(authResponse: ClipAuthResponse, provider: String, code: String, preview: VenuePreview) {
        self.authResponse = authResponse
        self.provider = provider
        self.code = code
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()

        // Hand the session to the full app FIRST — even if the scan call fails,
        // the install lands logged in.
        ClipHandoff.storeAuthHandoff(response: authResponse, provider: provider)
        redeem()
    }

    private func setupUI() {
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        emojiLabel.font = .systemFont(ofSize: 64)
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        detailLabel.font = .systemFont(ofSize: 17)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        spinner.startAnimating()

        [emojiLabel, titleLabel, detailLabel, spinner].forEach { stack.addArrangedSubview($0) }
        emojiLabel.isHidden = true

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
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
            presentInstallOverlay()
        }
    }

    private func showAwarded(_ result: ScanResult) {
        spinner.stopAnimating()
        emojiLabel.isHidden = false
        emojiLabel.text = "🎉"
        if let award = result.awarded {
            titleLabel.text = "You earned \(award.points) points!"
            detailLabel.text = "Spend them at \(preview.venueName). Get the full FavCircles app to browse offers, save places, and keep earning."
        } else {
            // Idempotent replay or outside the signup window — still a win state
            titleLabel.text = "You're in!"
            let balance = result.venueBalance ?? 0
            detailLabel.text = balance > 0
                ? "You have \(balance) points at \(preview.venueName). Get the full app to spend them."
                : "Welcome to FavCircles! Get the full app to start earning at \(preview.venueName)."
        }
    }

    private func showPending() {
        spinner.stopAnimating()
        emojiLabel.isHidden = false
        emojiLabel.text = "✅"
        titleLabel.text = "Account created!"
        detailLabel.text = "Your \(preview.signupBonusPoints) points at \(preview.venueName) are on the way — open the full app to collect them."
    }

    private func presentInstallOverlay() {
        guard !overlayPresented, let scene = view.window?.windowScene else { return }
        overlayPresented = true
        let config = SKOverlay.AppClipConfiguration(position: .bottom)
        SKOverlay(configuration: config).present(in: scene)
    }
}

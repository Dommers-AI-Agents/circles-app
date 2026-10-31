import UIKit
import AuthenticationServices

// The first screen: the store's photo full screen with the card's hook
// ("Love it here? / Save us." or "Earn 25 points / every visit."), the
// store's name, and Continue with Apple or email. A customer the clip
// already knows skips straight to their points (ClipSuccessViewController).
final class ClipOfferViewController: UIViewController {

    private let invocation: ClipInvocation
    private var code: String? { invocation.code }
    private var preview: VenuePreview?
    private let appleSignIn = ClipAppleSignIn()

    private let backdrop = ClipBackdropView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let contentStack = UIStackView()
    private let brandMark = ClipTheme.brandMarkView(side: 40)
    private let hookLabel = ClipTheme.label(ClipTheme.serif(46))
    private let nameLabel = ClipTheme.label(.systemFont(ofSize: 22, weight: .semibold))
    private let subtitleLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.88))
    private let rewardLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .semibold), color: ClipTheme.gold)
    private let appleButton = ASAuthorizationAppleIDButton(type: .continue, style: .white)
    private let emailButton = ClipTheme.glassButton("Continue with email")
    private let statusLabel = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.7))

    init(invocation: ClipInvocation) {
        self.invocation = invocation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.ink
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()

        if let code = code {
            loadPreview(code: code)
        } else {
            showNoCodeState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func setupUI() {
        view.addSubview(backdrop)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        brandMark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brandMark)

        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7
        [hookLabel, nameLabel, subtitleLabel, rewardLabel, statusLabel].forEach(ClipTheme.lift)
        statusLabel.textAlignment = .center

        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        appleButton.cornerRadius = 14
        emailButton.addTarget(self, action: #selector(emailTapped), for: .touchUpInside)

        [hookLabel, nameLabel, subtitleLabel, rewardLabel, appleButton, emailButton, statusLabel].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(14, after: hookLabel)
        contentStack.setCustomSpacing(6, after: nameLabel)
        contentStack.setCustomSpacing(12, after: subtitleLabel)
        contentStack.setCustomSpacing(26, after: rewardLabel)
        contentStack.setCustomSpacing(12, after: appleButton)
        contentStack.setCustomSpacing(14, after: emailButton)
        contentStack.isHidden = true
        brandMark.isHidden = true

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brandMark.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            brandMark.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: brandMark.bottomAnchor, constant: 16),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Data

    private func loadPreview(code: String) {
        Task { @MainActor in
            do {
                let preview = try await ClipAPIClient.shared.venuePreview(code: code)
                self.preview = preview
                self.backdrop.loadPhoto(from: preview.coverUrl.flatMap(URL.init(string:)))
                // Someone the clip already knows: straight to their points
                #if DEBUG
                // Screenshots without tapping: CLIP_PREVIEW=signup opens the email step
                if ProcessInfo.processInfo.environment["CLIP_PREVIEW"] == "signup" {
                    self.showOffer(preview)
                    self.emailTapped()
                    return
                }
                #endif
                if let session = ClipSession.current {
                    self.showSuccess(session: session, isNewSignIn: false, animated: false)
                } else {
                    self.showOffer(preview)
                }
            } catch {
                self.showLoadError(error, code: code)
            }
        }
    }

    private func showOffer(_ preview: VenuePreview) {
        spinner.stopAnimating()
        contentStack.isHidden = false
        brandMark.isHidden = false
        // The card's hook, then the store's name (said once each)
        let earnsHere = preview.kind == "register" && preview.loyaltyLive == true
        if earnsHere, let rate = preview.earnRate {
            hookLabel.attributedText = ClipTheme.hookText("Earn \(rate) points", "every visit.", size: 46)
        } else {
            hookLabel.attributedText = ClipTheme.hookText("Love it here?", preview.isGeneric ? "Save it." : "Save us.", size: 46)
        }

        if preview.isGeneric {
            // Generic "Join FavCircles" code: no store, FavCoins instead of store points
            nameLabel.isHidden = true
            subtitleLabel.text = "Keep your favorite places on your map and earn rewards wherever you go."
            rewardLabel.text = "\(preview.favCoinBonus) FavCoins to get you started"
            statusLabel.text = "Free to join"
        } else {
            nameLabel.text = preview.venueName
            if earnsHere {
                subtitleLabel.text = "Join FavCircles and collect your points for this visit."
                rewardLabel.text = preview.firstReward.map { "\($0.pointsCost) points = \($0.title)" }
                rewardLabel.isHidden = preview.firstReward == nil
            } else {
                subtitleLabel.text = "Join FavCircles to keep \(preview.venueName) on your map and earn rewards."
                rewardLabel.isHidden = true
            }
            statusLabel.text = "Free to join"
        }
        ClipTheme.animateIn([brandMark, hookLabel, nameLabel, subtitleLabel, rewardLabel, appleButton, emailButton, statusLabel])
    }

    private func showNoCodeState() {
        spinner.stopAnimating()
        contentStack.isHidden = false
        brandMark.isHidden = false
        hookLabel.attributedText = ClipTheme.hookText("Love it here?", "Save it.", size: 46)
        nameLabel.isHidden = true
        rewardLabel.isHidden = true
        subtitleLabel.text = "Scan a FavCircles code at a participating store to join and earn rewards."
        appleButton.isHidden = true
        emailButton.configuration?.attributedTitle = AttributedString("Get the full app", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
        emailButton.removeTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        emailButton.addTarget(self, action: #selector(appStoreTapped), for: .touchUpInside)
        statusLabel.text = nil
        ClipTheme.animateIn([brandMark, hookLabel, subtitleLabel, emailButton])
    }

    private func showLoadError(_ error: Error, code: String) {
        spinner.stopAnimating()
        let alert = UIAlertController(title: "Couldn't load this store",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.spinner.startAnimating()
            self?.loadPreview(code: code)
        })
        alert.addAction(UIAlertAction(title: "Get the App", style: .cancel) { [weak self] _ in
            self?.openAppStore()
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func appleTapped() {
        setButtons(enabled: false)
        appleSignIn.signIn(from: view.window) { [weak self] result in
            guard let self = self else { return }
            self.setButtons(enabled: true)
            switch result {
            case .success(let credential):
                self.completeAppleSignIn(credential)
            case .failure(let error):
                // Closing Apple's sheet isn't an error worth an alert
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                self.showAuthError(error)
            }
        }
    }

    @objc private func emailTapped() {
        guard let preview = preview else { return }
        let signupVC = ClipSignupViewController(code: code, preview: preview) { [weak self] response in
            self?.signedIn(response, provider: "email")
        }
        navigationController?.pushViewController(signupVC, animated: true)
    }

    @objc private func appStoreTapped() {
        openAppStore()
    }

    private func completeAppleSignIn(_ credential: ClipAppleSignIn.Credential) {
        setButtons(enabled: false)
        Task { @MainActor in
            do {
                let response = try await ClipAPIClient.shared.loginWithApple(
                    idToken: credential.idToken,
                    name: credential.displayName,
                    email: credential.email,
                    stickerCode: code
                )
                self.signedIn(response, provider: "apple")
            } catch {
                self.setButtons(enabled: true)
                self.showAuthError(error)
            }
        }
    }

    /// Remember them in the clip, then on to their points
    func signedIn(_ response: ClipAuthResponse, provider: String) {
        let session = ClipSession(response: response, provider: provider)
        session.save()
        showSuccess(session: session, isNewSignIn: true, animated: true)
    }

    private func showSuccess(session: ClipSession, isNewSignIn: Bool, animated: Bool) {
        guard let preview = preview, let code = code else { return }
        let successVC = ClipSuccessViewController(session: session,
                                                 isNewSignIn: isNewSignIn,
                                                 invocation: invocation,
                                                 code: code,
                                                 preview: preview)
        navigationController?.setViewControllers([successVC], animated: animated)
    }

    private func showAuthError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't sign you in",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func setButtons(enabled: Bool) {
        appleButton.isEnabled = enabled
        emailButton.isEnabled = enabled
        emailButton.alpha = enabled ? 1.0 : 0.5
    }

    private func openAppStore() {
        // Same product page ShareLinks.appStore points at
        if let url = URL(string: "https://apps.apple.com/us/app/favcircles/id6746807095") {
            UIApplication.shared.open(url)
        }
    }
}

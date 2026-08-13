import UIKit
import AuthenticationServices

// First screen of the clip: "Sign up and get 100 points at <Store>".
// Duplicated (not shared) brand colors — see Constants.Colors.primary in the app.
enum ClipTheme {
    static let primary = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.39, green: 0.7, blue: 0.93, alpha: 1.0)
            : UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1.0) // #3182CE
    }
}

final class ClipOfferViewController: UIViewController {

    private let code: String?
    private var preview: VenuePreview?
    private let appleSignIn = ClipAppleSignIn()

    private let spinner = UIActivityIndicatorView(style: .large)
    private let contentStack = UIStackView()
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let appleButton = ASAuthorizationAppleIDButton(type: .signUp, style: .whiteOutline)
    private let emailButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(code: String?) {
        self.code = code
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()

        if let code = code {
            loadPreview(code: code)
        } else {
            showNoCodeState()
        }
    }

    private func setupUI() {
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        emojiLabel.text = "📍"
        emojiLabel.font = .systemFont(ofSize: 56)
        emojiLabel.textAlignment = .center

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        appleButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        emailButton.setTitle("Sign up with email", for: .normal)
        emailButton.setTitleColor(.white, for: .normal)
        emailButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        emailButton.backgroundColor = ClipTheme.primary
        emailButton.layer.cornerRadius = 8
        emailButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        emailButton.addTarget(self, action: #selector(emailTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Free to join · Points you can spend at the counter"

        [emojiLabel, titleLabel, subtitleLabel, appleButton, emailButton, statusLabel].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(28, after: subtitleLabel)
        contentStack.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
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
                self.showOffer(preview)
            } catch {
                self.showLoadError(error, code: code)
            }
        }
    }

    private func showOffer(_ preview: VenuePreview) {
        spinner.stopAnimating()
        contentStack.isHidden = false
        titleLabel.text = preview.venueName
        subtitleLabel.text = "Sign up and get \(preview.signupBonusPoints) points to spend at \(preview.venueName)."
    }

    private func showNoCodeState() {
        spinner.stopAnimating()
        contentStack.isHidden = false
        titleLabel.text = "FavCircles"
        subtitleLabel.text = "Scan a FavCircles sticker at a participating store to sign up and earn rewards."
        appleButton.isHidden = true
        emailButton.setTitle("Get the full app", for: .normal)
        emailButton.removeTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        emailButton.addTarget(self, action: #selector(appStoreTapped), for: .touchUpInside)
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
                self.completeAppleSignup(credential)
            case .failure(let error):
                self.showAuthError(error)
            }
        }
    }

    @objc private func emailTapped() {
        guard let preview = preview else { return }
        let signupVC = ClipSignupViewController(code: code, preview: preview)
        navigationController?.pushViewController(signupVC, animated: true)
    }

    @objc private func appStoreTapped() {
        openAppStore()
    }

    private func completeAppleSignup(_ credential: ClipAppleSignIn.Credential) {
        setButtons(enabled: false)
        Task { @MainActor in
            do {
                let response = try await ClipAPIClient.shared.loginWithApple(
                    idToken: credential.idToken,
                    name: credential.displayName,
                    email: credential.email,
                    stickerCode: code
                )
                self.advanceToSuccess(response: response, provider: "apple")
            } catch {
                self.setButtons(enabled: true)
                self.showAuthError(error)
            }
        }
    }

    func advanceToSuccess(response: ClipAuthResponse, provider: String) {
        guard let preview = preview, let code = code else { return }
        let successVC = ClipSuccessViewController(authResponse: response,
                                                 provider: provider,
                                                 code: code,
                                                 preview: preview)
        navigationController?.setViewControllers([successVC], animated: true)
    }

    private func showAuthError(_ error: Error) {
        let alert = UIAlertController(title: "Sign-up failed",
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

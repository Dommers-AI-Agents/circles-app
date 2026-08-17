import UIKit
import AuthenticationServices

// Brand look shared by the clip screens. Deliberately commits to one design
// (blue gradient, white text) in both light and dark mode — matching the /s/
// web landing page — instead of following the system theme.
enum ClipTheme {
    static let brandBlue = UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1.0)   // #3182CE
    static let brandDeep = UIColor(red: 0.09, green: 0.23, blue: 0.42, alpha: 1.0)  // deep navy

    static func installGradient(on view: UIView) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.colors = [brandDeep.cgColor, brandBlue.cgColor]
        gradient.startPoint = CGPoint(x: 0.1, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
        gradient.frame = view.bounds
        view.layer.insertSublayer(gradient, at: 0)
        return gradient
    }

    static func brandMarkView(side: CGFloat) -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: "BrandMark"))
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = side * 0.22 // app-icon curvature
        imageView.layer.masksToBounds = true
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: side).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: side).isActive = true
        return imageView
    }

    // Staggered entrance: fade + rise, one element after another
    static func animateIn(_ views: [UIView], baseDelay: TimeInterval = 0.05) {
        for (index, view) in views.enumerated() {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 18)
            UIView.animate(withDuration: 0.55,
                           delay: baseDelay + Double(index) * 0.09,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0.4,
                           options: [.curveEaseOut]) {
                view.alpha = 1
                view.transform = .identity
            }
        }
    }
}

final class ClipOfferViewController: UIViewController {

    private let code: String?
    private var preview: VenuePreview?
    private let appleSignIn = ClipAppleSignIn()

    private var gradient: CAGradientLayer?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let contentStack = UIStackView()
    private let brandMark = ClipTheme.brandMarkView(side: 84)
    private let titleLabel = UILabel()
    private let pointsPill = UILabel()
    private let subtitleLabel = UILabel()
    private let appleButton = ASAuthorizationAppleIDButton(type: .signUp, style: .white)
    private let emailButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    init(code: String?) {
        self.code = code
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        gradient = ClipTheme.installGradient(on: view)
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()

        if let code = code {
            loadPreview(code: code)
        } else {
            showNoCodeState()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient?.frame = view.bounds
    }

    private func setupUI() {
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        pointsPill.font = .systemFont(ofSize: 17, weight: .semibold)
        pointsPill.textColor = ClipTheme.brandDeep
        pointsPill.backgroundColor = UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1.0) // gold
        pointsPill.textAlignment = .center
        pointsPill.layer.cornerRadius = 19
        pointsPill.layer.masksToBounds = true
        pointsPill.translatesAutoresizingMaskIntoConstraints = false
        pointsPill.heightAnchor.constraint(equalToConstant: 38).isActive = true

        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        appleButton.layer.cornerRadius = 12

        emailButton.setTitle("Sign up with email", for: .normal)
        emailButton.setTitleColor(ClipTheme.brandDeep, for: .normal)
        emailButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        emailButton.backgroundColor = .white
        emailButton.layer.cornerRadius = 12
        emailButton.translatesAutoresizingMaskIntoConstraints = false
        emailButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        emailButton.addTarget(self, action: #selector(emailTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Free to join · Points you can spend at the counter"

        [brandMark, titleLabel, pointsPill, subtitleLabel, appleButton, emailButton, statusLabel].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(22, after: brandMark)
        contentStack.setCustomSpacing(18, after: pointsPill)
        contentStack.setCustomSpacing(30, after: subtitleLabel)
        contentStack.setCustomSpacing(14, after: appleButton)
        contentStack.setCustomSpacing(18, after: emailButton)
        contentStack.isHidden = true

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            appleButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            emailButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            pointsPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
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
        if preview.isGeneric {
            // Generic "Join FavCircles" sticker — no store attached, welcome
            // gifts instead of a store bonus
            titleLabel.text = "Join FavCircles"
            pointsPill.text = "  🎁  Welcome gifts inside  "
            subtitleLabel.text = "Save your favorite places and earn rewards at partner stores."
            statusLabel.text = "Free to join · 25 FavCoins + 100 store points waiting"
        } else {
            titleLabel.text = preview.venueName
            pointsPill.text = "  🎁  \(preview.signupBonusPoints) free points  "
            subtitleLabel.text = "Join FavCircles right here and your points are waiting at the counter."
        }
        ClipTheme.animateIn([brandMark, titleLabel, pointsPill, subtitleLabel, appleButton, emailButton, statusLabel])
    }

    private func showNoCodeState() {
        spinner.stopAnimating()
        contentStack.isHidden = false
        titleLabel.text = "FavCircles"
        pointsPill.isHidden = true
        subtitleLabel.text = "Scan a FavCircles sticker at a participating store to sign up and earn rewards."
        appleButton.isHidden = true
        emailButton.setTitle("Get the full app", for: .normal)
        emailButton.removeTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        emailButton.addTarget(self, action: #selector(appStoreTapped), for: .touchUpInside)
        ClipTheme.animateIn([brandMark, titleLabel, subtitleLabel, emailButton, statusLabel])
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

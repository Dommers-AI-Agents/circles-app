import UIKit
import AuthenticationServices

// The first screen: the store's photo full screen and one way in. A store's
// window code doesn't ask again (Wes, 2026-11-01): they said yes on the
// card's "Love it here? Save us.", so this screen only signs them in and the
// store is saved as it does. Apple, or their email right here (a known email
// goes on to its code). A customer the clip already knows skips straight to
// the result (ClipSuccessViewController).
final class ClipOfferViewController: UIViewController, UITextFieldDelegate {

    private let invocation: ClipInvocation
    private var code: String? { invocation.code }
    private var preview: VenuePreview?
    private let appleSignIn = ClipAppleSignIn()

    private let backdrop = ClipBackdropView()
    private let brandMark = ClipTheme.brandMarkView(side: 40)
    private lazy var brandHeader = ClipTheme.brandHeader(mark: brandMark)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()
    private let contentStack = UIStackView()
    private let hookLabel = ClipTheme.label(ClipTheme.serif(46))
    private let nameLabel = ClipTheme.label(.systemFont(ofSize: 22, weight: .semibold))
    private let subtitleLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.88))
    private let rewardLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .semibold), color: ClipTheme.gold)
    private let appleButton = ASAuthorizationAppleIDButton(type: .continue, style: .white)
    private let emailButton = ClipTheme.glassButton("Continue with email")  // under the field
    private let emailField = ClipTheme.field(placeholder: "Your email", contentType: .emailAddress)
    private let errorLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium), color: UIColor(red: 1, green: 0.62, blue: 0.58, alpha: 1))
    private var contentBottom: NSLayoutConstraint?
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
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)

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

                view.addSubview(brandHeader)

        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7
        [hookLabel, nameLabel, subtitleLabel, rewardLabel, statusLabel].forEach(ClipTheme.lift)
        statusLabel.textAlignment = .center

        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        appleButton.cornerRadius = 14
        emailButton.addTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .go
        emailField.delegate = self
        emailField.accessibilityIdentifier = "clipEmail"
        errorLabel.isHidden = true

        [hookLabel, nameLabel, subtitleLabel, rewardLabel, appleButton, emailField, emailButton, errorLabel, statusLabel].forEach {
            contentStack.addArrangedSubview($0)
        }
        contentStack.setCustomSpacing(14, after: hookLabel)
        contentStack.setCustomSpacing(6, after: nameLabel)
        contentStack.setCustomSpacing(12, after: subtitleLabel)
        contentStack.setCustomSpacing(26, after: rewardLabel)
        contentStack.setCustomSpacing(16, after: appleButton)
        contentStack.setCustomSpacing(8, after: emailField)
        contentStack.setCustomSpacing(14, after: emailButton)
        contentStack.isHidden = true
        brandHeader.isHidden = true

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        // What this scan is for, under the spinner, before the store loads
        // (Wes, 2026-11-12: not "checking rewards" — a window card saves the
        // store, the join card joins). The store's name replaces it once known.
        loadingLabel.text = code == ClipSceneDelegate.genericJoinCode ? "Setting you up to join\u{2026}" : "Setting you up to save this store\u{2026}"
        loadingLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 2
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)

        let bottom = contentStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        contentBottom = bottom
        bottom.isActive = true
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            brandHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            brandHeader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            brandHeader.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: brandHeader.bottomAnchor, constant: 16),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            loadingLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            loadingLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - Data

    private func loadPreview(code: String) {
        Task { @MainActor in
            do {
                let preview = try await ClipAPIClient.shared.venuePreview(code: code, tag: self.invocation.tag)
                self.preview = preview
                // Photo and words arrive together: wait for the photo, but
                // never more than 2.5 s (a slow photo fades in afterwards)
                let photo = Task { await self.backdrop.loadPhoto(from: preview.coverUrl.flatMap(URL.init(string:))) }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { _ = await photo.value }
                    group.addTask { try? await Task.sleep(nanoseconds: 2_500_000_000) }
                    await group.next()
                    group.cancelAll()
                }
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
        spinner.stopAnimating(); loadingLabel.isHidden = true
        contentStack.isHidden = false
        brandHeader.isHidden = false
        // The card's hook, then the store's name (said once each)
        let earnsHere = preview.kind == "register" && preview.loyaltyLive == true
        if earnsHere, let rate = preview.earnRate {
            hookLabel.attributedText = ClipTheme.hookText("Earn \(rate) points", "every visit.", size: 46)
        } else if preview.isStoreWindow {
            // They already said yes on the card: sign in and it's saved
            hookLabel.attributedText = ClipTheme.hookText("Almost saved.", "Just sign in.", size: 46)
        } else {
            // The generic card asks "What's your favorite spot?" — the clip answers it (2026-11-09)
            hookLabel.attributedText = preview.isGeneric
                ? ClipTheme.hookText("What's your favorite spot?", "Save it.", size: 40)
                : ClipTheme.hookText("Love it here?", "Save us.", size: 46)
        }

        if preview.isGeneric {
            // Generic "Join FavCircles" code: no store, FavCoins instead of store points
            nameLabel.isHidden = true
            subtitleLabel.text = "Keep your favorite places on your map and earn rewards wherever you go."
            rewardLabel.text = "\(preview.favCoinBonus) FavCoins to get you started"
            statusLabel.text = "Free to join"
        } else if preview.isStoreWindow {
            nameLabel.text = preview.venueName
            subtitleLabel.isHidden = true
            rewardLabel.text = preview.pointsHere > 0 ? "+\(preview.pointsHere) points when it's saved" : nil
            rewardLabel.isHidden = preview.pointsHere == 0
            statusLabel.text = "Free · no password"
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
        ClipTheme.animateIn([brandHeader, hookLabel, nameLabel, subtitleLabel, rewardLabel, appleButton, emailField, emailButton, statusLabel])
    }

    private func showNoCodeState() {
        spinner.stopAnimating(); loadingLabel.isHidden = true
        contentStack.isHidden = false
        brandHeader.isHidden = false
        hookLabel.attributedText = ClipTheme.hookText("Love it here?", "Save it.", size: 46)
        nameLabel.isHidden = true
        rewardLabel.isHidden = true
        subtitleLabel.text = "Scan a FavCircles code at a participating store to join and earn rewards."
        appleButton.isHidden = true
        emailField.isHidden = true
        emailButton.configuration?.attributedTitle = AttributedString("Get the full app", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
        emailButton.removeTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        emailButton.addTarget(self, action: #selector(appStoreTapped), for: .touchUpInside)
        statusLabel.text = nil
        ClipTheme.animateIn([brandHeader, hookLabel, subtitleLabel, emailButton])
    }

    private func showLoadError(_ error: Error, code: String) {
        spinner.stopAnimating(); loadingLabel.isHidden = true
        let alert = UIAlertController(title: "Couldn't load this store",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.spinner.startAnimating(); self?.loadingLabel.isHidden = false
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

    /// The email typed right here: a new email is in at once; one that
    /// already has an account goes on to the code we email it
    @objc private func emailTapped() {
        guard let preview = preview else { return }
        let typed = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            showInlineError(typed.isEmpty ? "Type your email to continue." : "Please enter a valid email address.")
            emailField.becomeFirstResponder()
            return
        }
        errorLabel.isHidden = true
        setButtons(enabled: false)
        emailButton.configuration?.showsActivityIndicator = true
        Task { @MainActor in
            defer {
                self.setButtons(enabled: true)
                self.emailButton.configuration?.showsActivityIndicator = false
            }
            do {
                let response = try await ClipAPIClient.shared.emailInstant(email: typed, stickerCode: code)
                view.endEditing(true)
                signedIn(response, provider: "email")
            } catch ClipAPIError.coded("VERIFY_REQUIRED", _) {
                // They already have an account: the code is on its way
                view.endEditing(true)
                let codeStep = ClipSignupViewController(code: code, preview: preview, knownEmail: typed) { [weak self] response in
                    self?.signedIn(response, provider: "email")
                }
                navigationController?.pushViewController(codeStep, animated: true)
            } catch {
                showInlineError(error.localizedDescription)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        emailTapped()
        return true
    }

    private func showInlineError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Keeps the email field above the keyboard
    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        contentBottom?.constant = -18 - overlap
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
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

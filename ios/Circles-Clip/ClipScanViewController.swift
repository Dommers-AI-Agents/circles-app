import UIKit
import StoreKit
import AuthenticationServices

// A Scan Action QR opened without the app (Wes, 2026-11-11, at brunch): the
// place a friend is showing them, full screen, and one way in. Signing in
// saves it (or the whole list) to their Want to Try, then the full app opens
// on it. Guides and a store's setup need the full app: the clip says so and
// leaves the code for the app to pick up (handoff, or the pasteboard).
final class ClipScanViewController: UIViewController, UITextFieldDelegate, SKOverlayDelegate {

    private let code: String
    private var action: ClipScanAction?
    private let appleSignIn = ClipAppleSignIn()
    /// One per tap of Save: a resend on a weak signal never saves twice
    private let requestId = UUID().uuidString

    private let backdrop = ClipBackdropView()
    private let brandMark = ClipTheme.brandMarkView(side: 40)
    private lazy var brandHeader = ClipTheme.brandHeader(mark: brandMark)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let contentStack = UIStackView()
    private let hookLabel = ClipTheme.label(ClipTheme.serif(42))
    private let nameLabel = ClipTheme.label(.systemFont(ofSize: 22, weight: .semibold))
    private let subtitleLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.88))
    private let noteLabel = ClipTheme.label(.italicSystemFont(ofSize: 17), color: ClipTheme.gold)
    private let appleButton = ASAuthorizationAppleIDButton(type: .continue, style: .white)
    private let emailField = ClipTheme.field(placeholder: "Your email", contentType: .emailAddress)
    private let emailButton = ClipTheme.glassButton("Continue with email")
    private let primaryButton = ClipTheme.primaryButton("Save to my FavCircles")
    private let errorLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium), color: UIColor(red: 1, green: 0.62, blue: 0.58, alpha: 1))
    private let statusLabel = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.7))
    private var contentBottom: NSLayoutConstraint?
    private var overlayPresented = false

    init(code: String) {
        self.code = code
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
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func setupUI() {
        view.addSubview(backdrop)
        view.addSubview(brandHeader)
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7
        [hookLabel, nameLabel, subtitleLabel, noteLabel, statusLabel].forEach(ClipTheme.lift)
        statusLabel.textAlignment = .center

        appleButton.addTarget(self, action: #selector(appleTapped), for: .touchUpInside)
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.heightAnchor.constraint(equalToConstant: 54).isActive = true
        appleButton.cornerRadius = 14
        emailButton.addTarget(self, action: #selector(emailTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .go
        emailField.delegate = self
        errorLabel.isHidden = true

        [hookLabel, nameLabel, subtitleLabel, noteLabel, primaryButton, appleButton, emailField, emailButton, errorLabel, statusLabel]
            .forEach { contentStack.addArrangedSubview($0) }
        contentStack.setCustomSpacing(14, after: hookLabel)
        contentStack.setCustomSpacing(6, after: nameLabel)
        contentStack.setCustomSpacing(12, after: subtitleLabel)
        contentStack.setCustomSpacing(22, after: noteLabel)
        contentStack.setCustomSpacing(16, after: appleButton)
        contentStack.setCustomSpacing(8, after: emailField)
        contentStack.isHidden = true
        brandHeader.isHidden = true

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

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
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Loading

    private func load() {
        Task { @MainActor in
            do {
                let action = try await ClipAPIClient.shared.scanAction(code: code, bearer: ClipSession.current?.token)
                self.action = action
                let photo = action.places?.first(where: { $0.photoUrl != nil })?.photoUrl.flatMap(URL.init(string:))
                let photoTask = Task { await self.backdrop.loadPhoto(from: photo) }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { _ = await photoTask.value }
                    group.addTask { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                    await group.next()
                    group.cancelAll()
                }
                self.show(action)
            } catch {
                self.spinner.stopAnimating()
                self.showMessage(hook: ("This code", "isn't working."), subtitle: error.localizedDescription, button: "Get FavCircles")
            }
        }
    }

    private var places: [ClipScanAction.Place] { action?.places ?? [] }

    private func show(_ action: ClipScanAction) {
        spinner.stopAnimating()
        contentStack.isHidden = false
        brandHeader.isHidden = false
        let from = action.creator?.displayName

        guard action.isSaveable else {
            // A guide or a store's setup: the full app walks them through it
            let title = action.guide?.title ?? action.store?.name.map { "Set up \($0)" } ?? "FavCircles"
            showMessage(hook: (title, "in the app."),
                        subtitle: (action.guide?.blurb ?? "Claim your store, set your points and post your first reward.")
                            + " Get FavCircles and it walks you through it, step by step.",
                        button: "Get FavCircles")
            leaveCodeForTheApp()
            return
        }
        if action.expired == true {
            showMessage(hook: ("This QR", "has expired."), subtitle: from.map { "Ask \($0) to show you a new one." } ?? "Ask for a new one.",
                        button: "Get FavCircles")
            return
        }
        guard !places.isEmpty else {
            showMessage(hook: ("Nothing here", "anymore."), subtitle: "The places in this QR aren't available.", button: "Get FavCircles")
            return
        }

        if places.count == 1 {
            hookLabel.attributedText = ClipTheme.hookText(from.map { "From \($0):" } ?? "Love it?", "Save it.", size: 42)
            nameLabel.text = places[0].name
            subtitleLabel.text = places[0].address
        } else {
            hookLabel.attributedText = ClipTheme.hookText(from.map { "From \($0):" } ?? "\(places.count) places.", "Save them.", size: 42)
            nameLabel.text = action.title ?? "\(places.count) places"
            let names = places.prefix(3).map(\.name).joined(separator: ", ")
            subtitleLabel.text = places.count > 3 ? "\(names) and \(places.count - 3) more" : names
        }
        subtitleLabel.isHidden = subtitleLabel.text == nil
        noteLabel.text = action.note.map { "“\($0)”" }
        noteLabel.isHidden = action.note == nil

        let signedIn = ClipSession.current != nil
        primaryButton.isHidden = !signedIn
        appleButton.isHidden = signedIn
        emailField.isHidden = signedIn
        emailButton.isHidden = signedIn
        statusLabel.text = signedIn ? "Goes in your Want to Try" : "Free · no password · saved to your Want to Try"
        ClipTheme.animateIn([brandHeader, hookLabel, nameLabel, subtitleLabel, noteLabel, primaryButton, appleButton, emailField, emailButton, statusLabel])
    }

    /// One message and the App Store button (guides, expired, errors)
    private func showMessage(hook: (String, String), subtitle: String, button: String) {
        contentStack.isHidden = false
        brandHeader.isHidden = false
        hookLabel.attributedText = ClipTheme.hookText(hook.0, hook.1, size: 42)
        nameLabel.isHidden = true
        noteLabel.isHidden = true
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = false
        appleButton.isHidden = true
        emailField.isHidden = true
        emailButton.isHidden = true
        primaryButton.isHidden = false
        primaryButton.setTitle(button, for: .normal)
        primaryButton.removeTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(getAppTapped), for: .touchUpInside)
        statusLabel.text = nil
        ClipTheme.animateIn([brandHeader, hookLabel, subtitleLabel, primaryButton])
        presentInstallOverlay(afterDelay: 1.2)
    }

    /// The full app picks the code up on its first launch
    private func leaveCodeForTheApp() {
        guard let session = ClipSession.current else { return }
        if ClipHandoff.read() == nil { ClipHandoff.storeAuthHandoff(session: session) }
        ClipHandoff.markScanPending(code)
    }

    // MARK: - Signing in

    @objc private func appleTapped() {
        setButtons(enabled: false)
        appleSignIn.signIn(from: view.window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let credential):
                Task { @MainActor in
                    do {
                        let response = try await ClipAPIClient.shared.loginWithApple(idToken: credential.idToken, name: credential.displayName,
                                                                                    email: credential.email, stickerCode: nil)
                        self.signedIn(response, provider: "apple")
                    } catch {
                        self.setButtons(enabled: true)
                        self.showInlineError(error.localizedDescription)
                    }
                }
            case .failure(let error):
                self.setButtons(enabled: true)
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                self.showInlineError(error.localizedDescription)
            }
        }
    }

    @objc private func emailTapped() {
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
                let response = try await ClipAPIClient.shared.emailInstant(email: typed, stickerCode: nil)
                view.endEditing(true)
                signedIn(response, provider: "email")
            } catch ClipAPIError.coded("VERIFY_REQUIRED", _) {
                // They already have an account: the code is on its way
                view.endEditing(true)
                let hook = ClipTheme.hookText("Welcome back.", places.count == 1 ? "Save \(places[0].name)." : "Save them.", size: 40)
                let codeStep = ClipSignupViewController(hook: hook, knownEmail: typed) { [weak scan = self] response in
                    scan?.navigationController?.popToRootViewController(animated: true)
                    scan?.signedIn(response, provider: "email")
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

    private func signedIn(_ response: ClipAuthResponse, provider: String) {
        let session = ClipSession(response: response, provider: provider)
        session.save()
        ClipHandoff.storeAuthHandoff(session: session, isNewSignIn: true)
        save(session: session)
    }

    // MARK: - Saving

    @objc private func primaryTapped() {
        guard let session = ClipSession.current else { return }
        save(session: session)
    }

    private func save(session: ClipSession) {
        setButtons(enabled: false)
        primaryButton.configuration?.showsActivityIndicator = true
        statusLabel.text = "Saving…"
        Task { @MainActor in
            do {
                let result = try await ClipAPIClient.shared.saveScanAction(code: code, requestId: requestId, bearer: session.token)
                // The app opens on what was saved
                leaveCodeForTheApp()
                showSaved(result)
            } catch ClipAPIError.coded("no_circle", _) {
                // A brand-new account's circles weren't ready: the app finishes it
                leaveCodeForTheApp()
                showMessage(hook: ("Almost saved.", "Open the app."), subtitle: "Get FavCircles and it finishes saving.", button: "Get FavCircles")
            } catch {
                primaryButton.configuration?.showsActivityIndicator = false
                setButtons(enabled: true)
                primaryButton.isHidden = false
                appleButton.isHidden = true
                emailField.isHidden = true
                emailButton.isHidden = true
                statusLabel.text = nil
                showInlineError(error.localizedDescription)
            }
        }
    }

    private func showSaved(_ result: ClipScanSaveResult) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let count = result.saved.count
        let had = result.alreadySaved.count
        let hook: (String, String)
        if count == 0 && had > 0 {
            hook = ("Already", "on your map.")
        } else if count == 1 {
            hook = ("Saved.", result.saved[0].name.map { "\($0) is yours." } ?? "It's yours.")
        } else {
            hook = ("Saved.", "\(count) places are yours.")
        }
        var subtitle = "It's in your Want to Try. Get FavCircles to see it on your map, sort it into circles and share your own."
        if had > 0 && count > 0 { subtitle = "\(had) you already had. " + subtitle }
        if !result.failed.isEmpty { subtitle = "\(result.failed.count) couldn't be saved. " + subtitle }
        showMessage(hook: hook, subtitle: subtitle, button: "Get FavCircles")
    }

    // MARK: - Helpers

    @objc private func getAppTapped() {
        // No clip session to hand over: the app reads the code off the
        // pasteboard on its first launch (the web page does the same)
        if ClipSession.current == nil { UIPasteboard.general.string = "favcircles-scan:\(code)" }
        if let url = URL(string: "https://apps.apple.com/us/app/favcircles/id6746807095") {
            UIApplication.shared.open(url)
        }
    }

    private func showInlineError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func setButtons(enabled: Bool) {
        [appleButton, emailButton, primaryButton].forEach {
            $0.isEnabled = enabled
            $0.alpha = enabled ? 1 : 0.5
        }
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        contentBottom?.constant = -18 - overlap
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func presentInstallOverlay(afterDelay delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.overlayPresented, let scene = self.view.window?.windowScene else { return }
            self.overlayPresented = true
            let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
            overlay.delegate = self
            overlay.present(in: scene)
        }
    }

    nonisolated func storeOverlayWillStartPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let end = transitionContext.endFrame
        Task { @MainActor in self.liftContent(above: end) }
    }

    nonisolated func storeOverlayWillStartDismissal(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        Task { @MainActor in self.liftContent(above: nil) }
    }

    private func liftContent(above overlayFrame: CGRect?) {
        var lift: CGFloat = 0
        if let overlayFrame, let window = view.window {
            let inView = view.convert(overlayFrame, from: window)
            lift = max(0, view.bounds.maxY - view.safeAreaInsets.bottom - inView.minY)
        }
        contentBottom?.constant = -18 - lift
        UIView.animate(withDuration: 0.3) { self.view.layoutIfNeeded() }
    }
}

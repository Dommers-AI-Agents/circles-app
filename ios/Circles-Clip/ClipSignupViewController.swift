import UIKit

// Email sign-in without a password (Wes, 2026-10-31): the email, then the
// 6-digit code we email them. The same two steps sign in an existing account
// or create a new one (then we also ask their name). The look is the App
// Store header's: charcoal, a faint street map, the route through three pins.
final class ClipSignupViewController: UIViewController, UITextFieldDelegate {

    private enum Step { case email, code }

    private let code: String?
    private let preview: VenuePreview
    private let onSignedIn: (ClipAuthResponse) -> Void
    private var step: Step = .email
    private var email = ""
    private var newAccount = false

    private let backdrop = ClipBackdropView()
    private let backButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let hookLabel = ClipTheme.label(ClipTheme.serif(40))
    private let detailLabel = ClipTheme.label(.systemFont(ofSize: 17), color: UIColor.white.withAlphaComponent(0.85))
    private let emailField = ClipTheme.field(placeholder: "Email", contentType: .emailAddress)
    private let nameField = ClipTheme.field(placeholder: "Your name", contentType: .name)
    private let codeField = ClipTheme.field(placeholder: "6-digit code", contentType: .oneTimeCode)
    private let errorLabel = ClipTheme.label(.systemFont(ofSize: 15, weight: .medium), color: UIColor(red: 1, green: 0.62, blue: 0.58, alpha: 1))
    private let submitButton = ClipTheme.primaryButton("Send code")
    private let resendButton = ClipTheme.linkButton("Send a new code")
    private let changeEmailButton = ClipTheme.linkButton("Use a different email")
    private var stackBottom: NSLayoutConstraint?

    init(code: String?, preview: VenuePreview, onSignedIn: @escaping (ClipAuthResponse) -> Void) {
        self.code = code
        self.preview = preview
        self.onSignedIn = onSignedIn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClipTheme.ink
        setupUI()
        showEmailStep(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        emailField.becomeFirstResponder()
    }

    private func setupUI() {
        view.addSubview(backdrop)

        var back = UIButton.Configuration.filled()
        back.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        back.baseBackgroundColor = UIColor.white.withAlphaComponent(0.16)
        back.baseForegroundColor = .white
        back.cornerStyle = .capsule
        backButton.configuration = back
        backButton.accessibilityLabel = "Back"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        view.addSubview(backButton)

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .send
        emailField.delegate = self

        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .next
        nameField.delegate = self

        codeField.keyboardType = .numberPad
        codeField.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        codeField.defaultTextAttributes[.kern] = 8
        codeField.textAlignment = .center
        codeField.delegate = self
        codeField.addTarget(self, action: #selector(codeChanged), for: .editingChanged)

        errorLabel.isHidden = true
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        resendButton.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)
        changeEmailButton.addTarget(self, action: #selector(changeEmailTapped), for: .touchUpInside)

        [hookLabel, detailLabel].forEach(ClipTheme.lift)
        hookLabel.adjustsFontSizeToFitWidth = true
        hookLabel.minimumScaleFactor = 0.7

        let links = UIStackView(arrangedSubviews: [resendButton, changeEmailButton])
        links.axis = .horizontal
        links.distribution = .equalSpacing

        [hookLabel, detailLabel, emailField, nameField, codeField, errorLabel, submitButton, links].forEach {
            stack.addArrangedSubview($0)
        }
        stack.setCustomSpacing(10, after: hookLabel)
        stack.setCustomSpacing(22, after: detailLabel)
        stack.setCustomSpacing(16, after: errorLabel)

        let bottom = stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        stackBottom = bottom
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            bottom,
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(greaterThanOrEqualTo: backButton.bottomAnchor, constant: 12)
        ])
    }

    // MARK: - Steps

    private func showEmailStep(animated: Bool) {
        step = .email
        hookLabel.attributedText = preview.isGeneric
            ? ClipTheme.hookText("The Road less traveled", "is yours. Save it.", size: 40)
            : ClipTheme.hookText("Welcome in.", "Save \(preview.venueName).", size: 40)
        detailLabel.text = "Enter your email and we'll send you a 6-digit code. No password needed."
        emailField.isHidden = false
        nameField.isHidden = true
        codeField.isHidden = true
        resendButton.superview?.isHidden = true
        setSubmitTitle("Send code")
        hideError()
        if animated {
            ClipTheme.animateIn([hookLabel, detailLabel, emailField, submitButton])
            emailField.becomeFirstResponder()
        }
    }

    private func showCodeStep() {
        step = .code
        hookLabel.attributedText = ClipTheme.hookText("Check your email.", "Enter your code.", size: 40)
        detailLabel.text = newAccount
            ? "We sent a code to \(email). Add your name so friends know it's you."
            : "We sent a code to \(email). Welcome back!"
        emailField.isHidden = true
        nameField.isHidden = !newAccount
        codeField.isHidden = false
        codeField.text = nil
        resendButton.superview?.isHidden = false
        setSubmitTitle(newAccount ? "Create my account" : "Sign in")
        hideError()
        ClipTheme.animateIn([hookLabel, detailLabel, nameField, codeField, submitButton])
        (newAccount ? nameField : codeField).becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func backTapped() {
        if step == .code {
            showEmailStep(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func submitTapped() {
        switch step {
        case .email: sendCode()
        case .code: verify()
        }
    }

    @objc private func resendTapped() {
        sendCode()
    }

    @objc private func changeEmailTapped() {
        showEmailStep(animated: true)
    }

    @objc private func codeChanged() {
        let digits = (codeField.text ?? "").filter(\.isNumber)
        if codeField.text != digits { codeField.text = String(digits.prefix(6)) }
        // Filled from Mail (or typed): go, unless their name is still missing
        if digits.count == 6, !newAccount || !(nameField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            verify()
        }
    }

    private func sendCode() {
        let typed = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if step == .email {
            guard typed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
                showError("Please enter a valid email address.")
                return
            }
            email = typed
        }
        setBusy(true)
        Task { @MainActor in
            do {
                let started = try await ClipAPIClient.shared.startEmailCode(email: email)
                setBusy(false)
                newAccount = started.newAccount == true
                if step == .email {
                    showCodeStep()
                } else {
                    detailLabel.text = "We sent a new code to \(email)."
                    hideError()
                }
            } catch {
                setBusy(false)
                showError(error.localizedDescription)
            }
        }
    }

    private func verify() {
        let digits = (codeField.text ?? "").filter(\.isNumber)
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if newAccount, name.count < 2 {
            showError("Please add your name (at least 2 letters).")
            return
        }
        guard digits.count == 6 else {
            showError("Enter the 6-digit code from your email.")
            return
        }
        guard !submitButton.configuration!.showsActivityIndicator else { return }
        setBusy(true)
        Task { @MainActor in
            do {
                let response = try await ClipAPIClient.shared.verifyEmailCode(
                    email: email, code: digits,
                    displayName: newAccount ? name : nil,
                    stickerCode: code
                )
                view.endEditing(true)
                onSignedIn(response)
            } catch {
                setBusy(false)
                codeField.text = nil
                showError(error.localizedDescription)
            }
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField { sendCode() }
        if textField === nameField { codeField.becomeFirstResponder() }
        return true
    }

    // MARK: - Helpers

    private func setSubmitTitle(_ title: String) {
        submitButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]))
    }

    private func setBusy(_ busy: Bool) {
        submitButton.configuration?.showsActivityIndicator = busy
        submitButton.isEnabled = !busy
        resendButton.isEnabled = !busy
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func hideError() {
        errorLabel.isHidden = true
    }

    /// Keeps the form above the keyboard
    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        stackBottom?.constant = -20 - overlap
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }
}

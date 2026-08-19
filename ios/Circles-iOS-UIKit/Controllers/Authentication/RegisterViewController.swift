import UIKit
import AuthenticationServices
import LocalAuthentication

class RegisterViewController: BaseViewController {

    // MARK: - UI Elements

    // Brand-blue full bleed, matching LoginViewController — the two auth
    // screens read as siblings now (register used to inherit the plain
    // systemBackground and looked like a different app)
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        return button
    }()

    // Login-style white pill field. Placeholder color is FIXED — the dynamic
    // .placeholderText color goes light in dark mode, which on our forced-
    // white field rendered the placeholders invisible (Wes, 2026-08-19).
    private static func pillField(placeholder: String) -> UITextField {
        let textField = UITextField()
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.55, alpha: 1.0)]
        )
        textField.borderStyle = .roundedRect
        textField.backgroundColor = .white
        textField.textColor = .black
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Create an Account"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xxlarge, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Save your favorite places — free"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emailTextField: UITextField = {
        let textField = pillField(placeholder: "Enter your Email 🎉")
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .emailAddress
        textField.returnKeyType = .next
        return textField
    }()

    private let passwordTextField: UITextField = {
        let textField = pillField(placeholder: "Password")
        textField.isSecureTextEntry = true
        textField.returnKeyType = .next
        return textField
    }()

    private let confirmPasswordTextField: UITextField = {
        let textField = pillField(placeholder: "Confirm Password")
        textField.isSecureTextEntry = true
        textField.returnKeyType = .next
        return textField
    }()

    private let zipcodeTextField: UITextField = {
        let textField = pillField(placeholder: "Zipcode")
        textField.keyboardType = .numberPad
        textField.returnKeyType = .next
        return textField
    }()

    private let zipcodeLabel: UILabel = {
        let label = UILabel()
        label.text = "Used to show you great places nearby"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // NOTE: no referral-code UI on signup (Wes, 2026-08-19 — keep signup as
    // simple as possible; referral benefits are controlled server-side).
    // Deep-linked codes still apply silently: ReferralService stores the
    // pending code and applyPendingReferralCodeIfNeeded runs post-signup.

    // MARK: Step machine views (passkey-first signup)

    private lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Continue →", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let passkeyInfoLabel: UILabel = {
        let label = UILabel()
        label.text = "No password needed when you use your phone security"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var passkeyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Self.passkeyButtonTitle(), for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.setImage(UIImage(systemName: "faceid", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var usePasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Use a password instead", for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.9), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // All the mutable middle content lives in one vertical stack — arranged
    // subviews collapse when hidden, so each step just toggles isHidden
    private let formStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = Constants.Spacing.medium
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    /// "Face ID" only when the device actually has it — a Touch ID phone
    /// promising Face ID reads as broken.
    private static func passkeyButtonTitle() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Continue with Face ID"
        case .touchID: return "Continue with Touch ID"
        default: return "Continue with Passcode"
        }
    }


    private lazy var togglePasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye.slash.fill"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var toggleConfirmPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye.slash.fill"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let passwordRequirementLabel: UILabel = {
        let label = UILabel()
        label.text = "8+ characters with uppercase, lowercase & number"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Login-style inverted CTA: white fill, brand-colored title
    private lazy var registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Account", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let orContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let orLabel: UILabel = {
        let label = UILabel()
        label.text = "or sign up with"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let leftDivider: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let rightDivider: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let socialStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let appleSignInContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        return container
    }()
    
    private lazy var appleSignInButton = UIButton.appleSignInButton()

    private lazy var googleSignInButton: UIButton = {
        let button = UIButton.googleSignInButton()
        button.setTitle("Google", for: .normal)
        return button
    }()
    
    private lazy var facebookSignInButton: UIButton = {
        let button = UIButton.facebookSignInButton()
        button.setTitle("Facebook", for: .normal)
        return button
    }()
    
    
    // MARK: - Properties

    /// Passkey-first signup: email → passkey offer (Face ID) → optional
    /// password fallback. The password form is the OLD flow, unchanged.
    private enum Step {
        case email
        case passkeyOffer
        case passwordForm
    }

    private var step: Step = .email {
        didSet { applyStep() }
    }

    private var primaryButtonForStep: UIButton {
        switch step {
        case .email: return nextButton
        case .passkeyOffer: return passkeyButton
        case .passwordForm: return registerButton
        }
    }

    private var isRegistering = false {
        didSet {
            let buttons = [registerButton, nextButton, passkeyButton, usePasswordButton,
                           appleSignInButton, googleSignInButton, facebookSignInButton]
            buttons.forEach { $0.isEnabled = !isRegistering }

            let textFields = [emailTextField, passwordTextField, confirmPasswordTextField, zipcodeTextField]
            textFields.forEach { $0.isEnabled = !isRegistering }

            if isRegistering {
                primaryButtonForStep.setLoading(true)
            } else {
                // setLoading restores each button's own captured title
                [registerButton, nextButton, passkeyButton].forEach { $0.setLoading(false) }
            }
        }
    }
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - Lifecycle
    /// Set by the login screen's "no account — create one?" path so the email
    /// carries over instead of making the user retype it.
    var prefillEmail: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        if let prefillEmail = prefillEmail, !prefillEmail.isEmpty {
            emailTextField.text = prefillEmail
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Full-bleed brand screen like Login — the bar's "Register" title
        // duplicated the "Create an Account" heading; the chevron replaces it
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Configure Apple sign-in container
        appleSignInContainerView.addSubview(appleSignInButton)
        
        // Configure social stack view - match LoginViewController order.
        // Facebook Sign-In is intentionally omitted (same as the login screen);
        // re-add by uncommenting if we enable Facebook later.
        socialStackView.addArrangedSubview(googleSignInButton)
        // socialStackView.addArrangedSubview(facebookSignInButton)
        socialStackView.addArrangedSubview(appleSignInContainerView)
        
        // Setup password field right views
        passwordTextField.rightView = togglePasswordButton
        passwordTextField.rightViewMode = .always
        confirmPasswordTextField.rightView = toggleConfirmPasswordButton
        confirmPasswordTextField.rightViewMode = .always
        
        // Add subviews — blue ground first, chevron floats above the scroll
        view.addSubview(backgroundView)
        view.addSubview(scrollView)
        view.addSubview(backButton)
        scrollView.addSubview(contentView)

        // Add dividers to OR container
        orContainerView.addSubview(leftDivider)
        orContainerView.addSubview(orLabel)
        orContainerView.addSubview(rightDivider)

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(formStack)

        // One stack holds every step's views; applyStep() toggles visibility
        [emailTextField,
         nextButton,
         passkeyInfoLabel, passkeyButton, usePasswordButton,
         passwordTextField, confirmPasswordTextField, passwordRequirementLabel,
         zipcodeTextField, zipcodeLabel, registerButton,
         orContainerView, socialStackView].forEach { formStack.addArrangedSubview($0) }

        // Breathing room where the old anchor chain had larger gaps
        formStack.setCustomSpacing(Constants.Spacing.large, after: nextButton)
        formStack.setCustomSpacing(Constants.Spacing.large, after: orContainerView)
        formStack.setCustomSpacing(Constants.Spacing.large, after: passkeyInfoLabel)
        formStack.setCustomSpacing(Constants.Spacing.small, after: passkeyButton)
        formStack.setCustomSpacing(Constants.Spacing.small, after: confirmPasswordTextField)
        formStack.setCustomSpacing(Constants.Spacing.small, after: zipcodeTextField)
        formStack.setCustomSpacing(Constants.Spacing.large, after: zipcodeLabel)

        setupConstraints()
        setupTextFieldDelegates()
        applyStep()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Blue ground fills everything, ignoring safe areas (like Login)
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            // Scroll view — bottom rides the keyboard like Login does
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.Spacing.small),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Form stack — every step's content lives here
            formStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            formStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            formStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            formStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large),

            // Field heights (widths come from the stack)
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 50),
            zipcodeTextField.heightAnchor.constraint(equalToConstant: 50),

            // Password-field eye toggles
            togglePasswordButton.widthAnchor.constraint(equalToConstant: 44),
            toggleConfirmPasswordButton.widthAnchor.constraint(equalToConstant: 44),

            // OR container with dividers
            orContainerView.heightAnchor.constraint(equalToConstant: 20),

            // Left divider
            leftDivider.leadingAnchor.constraint(equalTo: orContainerView.leadingAnchor),
            leftDivider.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            leftDivider.heightAnchor.constraint(equalToConstant: 1),
            leftDivider.trailingAnchor.constraint(equalTo: orLabel.leadingAnchor, constant: -Constants.Spacing.medium),
            
            // OR label — intrinsic width ("or sign up with" is longer than "OR")
            orLabel.centerXAnchor.constraint(equalTo: orContainerView.centerXAnchor),
            orLabel.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            
            // Right divider
            rightDivider.leadingAnchor.constraint(equalTo: orLabel.trailingAnchor, constant: Constants.Spacing.medium),
            rightDivider.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            rightDivider.heightAnchor.constraint(equalToConstant: 1),
            rightDivider.trailingAnchor.constraint(equalTo: orContainerView.trailingAnchor),
            
            // Apple sign-in container constraints
            appleSignInContainerView.heightAnchor.constraint(equalToConstant: 50),
            
            // Apple sign-in button within container
            appleSignInButton.topAnchor.constraint(equalTo: appleSignInContainerView.topAnchor),
            appleSignInButton.leadingAnchor.constraint(equalTo: appleSignInContainerView.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(equalTo: appleSignInContainerView.trailingAnchor),
            appleSignInButton.bottomAnchor.constraint(equalTo: appleSignInContainerView.bottomAnchor)
        ])
    }
    
    private func setupTextFieldDelegates() {
        [emailTextField, passwordTextField, confirmPasswordTextField, zipcodeTextField].forEach {
            $0.delegate = self
        }
    }
    
    private func setupActions() {
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        passkeyButton.addTarget(self, action: #selector(passkeyButtonTapped), for: .touchUpInside)
        usePasswordButton.addTarget(self, action: #selector(usePasswordTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        togglePasswordButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        toggleConfirmPasswordButton.addTarget(self, action: #selector(toggleConfirmPasswordVisibility), for: .touchUpInside)
        
        // Add real-time password validation
        passwordTextField.addTarget(self, action: #selector(passwordTextFieldDidChange), for: .editingChanged)
        
        // Keyboard handling: scrollView bottom is pinned to keyboardLayoutGuide
        // (same mechanism as Login) — no manual inset juggling needed
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func backTapped() {
        // Chevron walks the step machine backward before leaving the screen
        if step != .email {
            advance(to: .email)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Step machine

    private func applyStep() {
        let emailStep = step == .email
        let offerStep = step == .passkeyOffer
        let formStep = step == .passwordForm

        // Only write isHidden when it actually changes. Re-asserting the same
        // value on a UIStackView arranged subview can leave it stuck partially
        // visible — the source of the multi-step-bleed / torn-button rendering.
        setHidden(nextButton, !emailStep)
        setHidden(orContainerView, !emailStep)
        setHidden(socialStackView, !emailStep)

        setHidden(passkeyInfoLabel, !offerStep)
        setHidden(passkeyButton, !offerStep)
        setHidden(usePasswordButton, !offerStep)

        setHidden(passwordTextField, !formStep)
        setHidden(confirmPasswordTextField, !formStep)
        setHidden(passwordRequirementLabel, !formStep)
        setHidden(zipcodeTextField, !formStep)
        setHidden(zipcodeLabel, !formStep)
        setHidden(registerButton, !formStep)

        subtitleLabel.text = offerStep
            ? "One tap and you're in — no password needed"
            : "Save your favorite places — free"
    }

    private func setHidden(_ view: UIView, _ hidden: Bool) {
        if view.isHidden != hidden { view.isHidden = hidden }
    }

    private func advance(to newStep: Step) {
        view.endEditing(true)
        // Settle visibility SYNCHRONOUSLY (outside any animation) — toggling
        // arranged-subview isHidden inside a UIView.animate block is what made
        // hidden steps linger/fade and overlap. Animate only the resulting layout.
        step = newStep
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func nextButtonTapped() {
        guard let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty, isValidEmail(email) else {
            showError("Please enter a valid email address")
            return
        }

        isRegistering = true
        AuthService.shared.checkEmail(email) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRegistering = false

                switch result {
                case .success(let check) where check.exists && check.hasPasskey:
                    // They already have a passkey — take them straight home
                    self.popToLoginAndSignInWithPasskey(email: email)
                case .success(let check) where check.exists:
                    self.showWelcomeBack(email: email)
                default:
                    // New email — or the check failed (bad signal). Advance
                    // either way: register-options re-checks server-side and
                    // 409s on an existing account, so this is always safe.
                    self.advance(to: .passkeyOffer)
                }
            }
        }
    }

    @objc private func passkeyButtonTapped() {
        guard let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty, isValidEmail(email) else {
            showError("Please enter a valid email address")
            return
        }
        view.endEditing(true)

        isRegistering = true
        PasskeyAuthService.shared.registerPasskey(email: email, presentationAnchor: view.window) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRegistering = false

                switch result {
                case .success(let user):
                    Logger.debug("🔑 Passkey signup complete: \(user.displayName)")
                    AnalyticsService.shared.trackSignUp(method: "passkey")
                    // Deep-linked referral codes stashed pre-signup apply here too
                    ReferralService.shared.applyPendingReferralCodeIfNeeded { _ in }
                    // Auth state change swaps the root; the first-session
                    // carousel takes it from here
                case .failure(let error):
                    if case PasskeyAuthService.PasskeyError.canceled = error {
                        return // user dismissed the sheet — stay put, no toast
                    }
                    if case AuthError.accountExists = error {
                        self.showWelcomeBack(email: email)
                        return
                    }
                    // Stay on this step: a fresh tap mints a fresh challenge
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func usePasswordTapped() {
        advance(to: .passwordForm)
        passwordTextField.becomeFirstResponder()
    }

    /// The email already holds a passkey — land on Login prefilled and kick
    /// off the assertion immediately (preferImmediate: a device without the
    /// credential falls back silently instead of showing the QR sheet).
    private func popToLoginAndSignInWithPasskey(email: String) {
        if let loginVC = navigationController?.viewControllers
            .compactMap({ $0 as? LoginViewController }).last {
            loginVC.prefill(email: email)
            loginVC.signInWithPasskeyOnNextAppear()
            navigationController?.popToViewController(loginVC, animated: true)
        } else {
            let loginVC = LoginViewController()
            loginVC.prefill(email: email)
            loginVC.signInWithPasskeyOnNextAppear()
            navigationController?.setViewControllers([loginVC], animated: true)
        }
    }

    @objc private func registerButtonTapped() {
        guard let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty, isValidEmail(email) else {
            showError("Please enter a valid email address")
            return
        }
        
        // Validate password with detailed requirements
        guard let password = passwordTextField.text, !password.isEmpty else {
            showError("Please enter a password")
            return
        }
        
        let passwordValidation = validatePassword(password)
        if !passwordValidation.isValid {
            showError(passwordValidation.errors.joined(separator: "\n"))
            return
        }
        
        guard let confirmPassword = confirmPasswordTextField.text, confirmPassword == password else {
            showError("Passwords do not match")
            return
        }
        
        guard let zipcode = zipcodeTextField.text, !zipcode.isEmpty, isValidZipcode(zipcode) else {
            showError("Please enter a valid 5-digit zipcode")
            return
        }
        
        // (Deep-linked referral codes were already stashed by ReferralService;
        // applyPendingReferralCodeIfNeeded picks them up after signup)

        // Start registration
        isRegistering = true
        
        // Create a default display name from email
        let displayName = email.components(separatedBy: "@").first ?? "User"
        
        // Attempt registration with zipcode
        AuthService.shared.register(email: email, password: password, displayName: displayName, zipcode: zipcode) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    Logger.debug("Successfully registered user: \(user.displayName)")
                    AnalyticsService.shared.trackSignUp(method: "email")
                    
                    // Apply any deep-linked referral code stashed pre-signup
                    ReferralService.shared.applyPendingReferralCodeIfNeeded { success in
                        if success {
                            Logger.debug("Successfully applied referral code")
                        }
                    }
                    
                    // Don't show email verification popup - let auth state change take effect
                    // This allows the user to be logged in and see the onboarding with suggested users
                    // Email verification can be handled later in the app
                    // self?.showEmailVerificationMessage(email: email)
                    
                case .failure(let error):
                    if case AuthError.accountExists = error {
                        self?.showWelcomeBack(email: email)
                    } else {
                        self?.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// The email already has an account — don't dead-end, walk them home.
    private func showWelcomeBack(email: String) {
        let alert = UIAlertController(
            title: "Welcome back! 👋",
            message: "You already have a FavCircles account with \(email). Sign in to pick up right where you left off.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if let loginVC = self.navigationController?.viewControllers
                .compactMap({ $0 as? LoginViewController }).last {
                loginVC.prefill(email: email)
                self.navigationController?.popToViewController(loginVC, animated: true)
            } else {
                let loginVC = LoginViewController()
                loginVC.prefill(email: email)
                self.navigationController?.setViewControllers([loginVC], animated: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Forgot Password", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(PasswordResetViewController(), animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func appleSignInButtonTapped() {
        Logger.debug("🍎 Apple Sign-In button tapped in RegisterViewController - Action triggered successfully!")
        
        // Show informative message about email options
        let alert = UIAlertController(
            title: "Apple Sign-In Options",
            message: "You can choose 'Hide My Email' or 'Share My Email' with Apple Sign-In.\n\nSharing your email enables:\n• Daily activity summaries\n• Important account notifications\n• Better app experience\n\nHide My Email works too, but with limited notifications.\n\nReady to continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.proceedWithAppleSignIn()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func proceedWithAppleSignIn() {
        Logger.debug("🍎 Proceeding with Apple Sign-In after warning")
        isRegistering = true
        
        SocialAuthService.shared.signInWithApple(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    // No alert: they're already logged in — the auth state
                    // change swaps the root; new accounts land in the
                    // first-session carousel
                    Logger.debug("🍎 Successfully registered with Apple: \(user.displayName)")
                case .failure(let error):
                    Logger.debug("🍎 Apple Sign-In Failed with error: \(error.localizedDescription)")

                    self?.showError("Apple Sign-In Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func googleSignInButtonTapped() {
        handleSocialAuth {
            SocialAuthService.shared.signInWithGoogle(from: self, completion: $0)
        }
    }
    
    @objc private func facebookSignInButtonTapped() {
        handleSocialAuth {
            SocialAuthService.shared.signInWithFacebook(from: self, completion: $0)
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        let imageName = passwordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        togglePasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func toggleConfirmPasswordVisibility() {
        confirmPasswordTextField.isSecureTextEntry.toggle()
        let imageName = confirmPasswordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        toggleConfirmPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func passwordTextFieldDidChange() {
        // Colors picked for the blue ground: neutral = soft white,
        // success = solid white ✓, error = yellow (red vanishes on blue)
        guard let password = passwordTextField.text, !password.isEmpty else {
            passwordRequirementLabel.text = "8+ characters with uppercase, lowercase & number"
            passwordRequirementLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            return
        }

        let validation = validatePassword(password)

        if validation.isValid {
            passwordRequirementLabel.text = "✓ Password meets all requirements"
            passwordRequirementLabel.textColor = .white
        } else {
            passwordRequirementLabel.text = validation.errors.joined(separator: "\n")
            passwordRequirementLabel.textColor = .systemYellow
        }
    }
    
    // MARK: - Helper Methods
    private func handleSocialAuth(_ authMethod: @escaping (@escaping (Result<User, Error>) -> Void) -> Void) {
        isRegistering = true
        
        authMethod { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    // No alert — the root swap takes it from here (misleading
                    // "you can now log in" copy removed; they ARE logged in)
                    Logger.debug("Successfully registered with social auth: \(user.displayName)")
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func showEmailVerificationMessage(email: String) {
        AlertPresenter.showSuccess(
            title: "Verify Your Email",
            message: "A verification email has been sent to \(email). Please check your inbox and follow the link to verify your account before logging in.",
            from: self
        ) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidZipcode(_ zipcode: String) -> Bool {
        let zipcodeRegex = "^[0-9]{5}$"
        let zipcodePredicate = NSPredicate(format: "SELF MATCHES %@", zipcodeRegex)
        return zipcodePredicate.evaluate(with: zipcode)
    }
    
    private func validatePassword(_ password: String) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if password.count < 8 {
            errors.append("• At least 8 characters required")
        }
        
        if !password.contains(where: { $0.isUppercase }) {
            errors.append("• Must contain an uppercase letter")
        }
        
        if !password.contains(where: { $0.isLowercase }) {
            errors.append("• Must contain a lowercase letter")
        }
        
        if !password.contains(where: { $0.isNumber }) {
            errors.append("• Must contain a number")
        }
        
        return (errors.isEmpty, errors)
    }
    
    private func findFirstResponder() -> UIView? {
        let responders: [UIView] = [emailTextField, passwordTextField, confirmPasswordTextField, zipcodeTextField]
        return responders.first { $0.isFirstResponder }
    }
    
    // Note: Hide My Email (private relay) sign-ins are supported as of
    // 2026-08-06 — favcircles.com is registered with Apple for relay email
    // forwarding, and the backend no longer rejects relay addresses.

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITextFieldDelegate
extension RegisterViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case emailTextField:
            if step == .email {
                textField.resignFirstResponder()
                nextButtonTapped()
            } else {
                passwordTextField.becomeFirstResponder()
            }
        case passwordTextField:
            confirmPasswordTextField.becomeFirstResponder()
        case confirmPasswordTextField:
            zipcodeTextField.becomeFirstResponder()
        case zipcodeTextField:
            textField.resignFirstResponder()
            registerButtonTapped()
        default:
            textField.resignFirstResponder()
        }
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Limit zipcode to 5 digits
        if textField == zipcodeTextField {
            let currentText = textField.text ?? ""
            let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
            
            // Only allow numbers
            let allowedCharacters = CharacterSet.decimalDigits
            let characterSet = CharacterSet(charactersIn: string)
            if !allowedCharacters.isSuperset(of: characterSet) && !string.isEmpty {
                return false
            }
            
            // Limit to 5 characters
            return newText.count <= 5
        }
        return true
    }
}
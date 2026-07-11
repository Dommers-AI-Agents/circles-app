import UIKit
import AuthenticationServices

class LoginViewController: BaseViewController {

    // MARK: - UI Elements
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.grid.2x2.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "CIRCLES"
        label.font = UIFont.systemFont(ofSize: 40, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let taglineLabel: UILabel = {
        let label = UILabel()
        label.text = "Share your favorite places with friends"
        label.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Email"
        textField.borderStyle = .roundedRect
        textField.backgroundColor = .white
        textField.textColor = .black
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .emailAddress
        textField.returnKeyType = .next
        textField.textContentType = .username // Enable AutoFill
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return textField
    }()

    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Password"
        textField.borderStyle = .roundedRect
        textField.backgroundColor = .white
        textField.textColor = .black
        textField.isSecureTextEntry = true
        textField.returnKeyType = .go
        textField.textContentType = .password // Enable AutoFill
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return textField
    }()

    private lazy var togglePasswordButton: UIButton = {
        let button = UIButton.iconButton(systemName: "eye.slash.fill", pointSize: 17)
        button.tintColor = Constants.Colors.secondaryLabel
        return button
    }()

    private lazy var loginButton: UIButton = {
        // Factory base, inverted for the gradient background: white fill with
        // primary-colored text instead of the standard primary fill
        let button = UIButton.primaryButton(title: "Log In")
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        return button
    }()

    private let forgotPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Forgot password?", for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.9), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let signUpLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let attributedString = NSMutableAttributedString(string: "New to Circles? ", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ])
        attributedString.append(NSAttributedString(string: "Create an account", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: UIColor.white
        ]))
        button.setAttributedTitle(attributedString, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let orDividerLabel: UILabel = {
        let label = UILabel()
        label.text = "— or continue with —"
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var facebookSignInButton = UIButton.facebookSignInButton()
    private lazy var googleSignInButton = UIButton.googleSignInButton()

    private let appleSignInContainerView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        return container
    }()

    private lazy var appleSignInButton = UIButton.appleSignInButton()

    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "By using Circles, you agree to the Terms, Cookie Policy, and Privacy Policy"
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .white.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Properties
    private let savedEmailKey = "savedUserEmail"

    private var isLoggingIn = false {
        didSet {
            updateButtonStates()
        }
    }

    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false } // Custom loading state
    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        loadSavedEmail()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background

        // Add background
        view.addSubview(backgroundView)
        backgroundView.addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Add content
        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(taglineLabel)

        // Setup password field right view
        passwordTextField.rightView = togglePasswordButton
        passwordTextField.rightViewMode = .always
        togglePasswordButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

        // Configure Apple sign-in container
        appleSignInContainerView.addSubview(appleSignInButton)

        // Email/password login first - this is the primary way to sign in
        buttonsStackView.addArrangedSubview(emailTextField)
        buttonsStackView.addArrangedSubview(passwordTextField)
        buttonsStackView.addArrangedSubview(loginButton)
        buttonsStackView.addArrangedSubview(forgotPasswordButton)
        buttonsStackView.addArrangedSubview(signUpLinkButton)

        // Spacer before "or" divider
        let spacerView1 = UIView()
        spacerView1.translatesAutoresizingMaskIntoConstraints = false
        spacerView1.heightAnchor.constraint(equalToConstant: 8).isActive = true
        buttonsStackView.addArrangedSubview(spacerView1)

        buttonsStackView.addArrangedSubview(orDividerLabel)

        // Spacer after "or" divider
        let spacerView2 = UIView()
        spacerView2.translatesAutoresizingMaskIntoConstraints = false
        spacerView2.heightAnchor.constraint(equalToConstant: 8).isActive = true
        buttonsStackView.addArrangedSubview(spacerView2)

        // Social logins demoted below the divider
        buttonsStackView.addArrangedSubview(appleSignInContainerView)
        buttonsStackView.addArrangedSubview(googleSignInButton)
        buttonsStackView.addArrangedSubview(facebookSignInButton)

        orDividerLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true

        contentView.addSubview(buttonsStackView)
        contentView.addSubview(privacyLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Background view
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Scroll view fills the background (keyboard-friendly)
            scrollView.topAnchor.constraint(equalTo: backgroundView.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backgroundView.keyboardLayoutGuide.topAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Logo
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            logoImageView.widthAnchor.constraint(equalToConstant: 64),
            logoImageView.heightAnchor.constraint(equalToConstant: 64),

            // Title
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 12),

            // Tagline
            taglineLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            taglineLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            taglineLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            taglineLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            // Buttons stack view
            buttonsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            buttonsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            buttonsStackView.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 32),

            // Privacy label
            privacyLabel.topAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 24),
            privacyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            privacyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            privacyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            // Apple sign-in container constraints
            appleSignInContainerView.heightAnchor.constraint(equalToConstant: 50),

            // Apple sign-in button within container
            appleSignInButton.topAnchor.constraint(equalTo: appleSignInContainerView.topAnchor),
            appleSignInButton.leadingAnchor.constraint(equalTo: appleSignInContainerView.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(equalTo: appleSignInContainerView.trailingAnchor),
            appleSignInButton.bottomAnchor.constraint(equalTo: appleSignInContainerView.bottomAnchor)
        ])
    }

    private func setupActions() {
        // Email/password login
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        signUpLinkButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        togglePasswordButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)

        emailTextField.delegate = self
        passwordTextField.delegate = self

        // Social login buttons
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)

        // Dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func updateButtonStates() {
        let controls: [UIControl] = [
            loginButton, emailTextField, passwordTextField, forgotPasswordButton,
            signUpLinkButton, appleSignInButton, googleSignInButton, facebookSignInButton
        ]
        controls.forEach { $0.isEnabled = !isLoggingIn }

        // Show/hide loading state
        if isLoggingIn {
            loginButton.setTitle("Logging in…", for: .normal)
            showLoadingState()
        } else {
            loginButton.setTitle("Log In", for: .normal)
            hideLoadingState()
        }
    }

    // MARK: - Actions
    @objc private func loginButtonTapped() {
        guard let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty,
              let password = passwordTextField.text, !password.isEmpty else {
            showError("Please enter both email and password")
            return
        }

        dismissKeyboard()
        isLoggingIn = true

        AuthService.shared.login(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false

                switch result {
                case .success(let user):
                    print("Successfully logged in user: \(user.displayName)")
                    AnalyticsService.shared.trackLogin(method: "email")
                    UserDefaults.standard.set(email, forKey: self?.savedEmailKey ?? "savedUserEmail")

                    // Always remember credentials so the session can be silently
                    // restored later and the user stays logged in
                    KeychainManager.shared.saveCredentials(email: email, password: password)

                    // Authentication state listener in SceneDelegate will handle UI update

                case .failure(let error):
                    if let authError = error as? AuthError, authError == .emailNotVerified {
                        self?.showEmailVerificationAlert(email: email)
                    } else {
                        self?.showError(error)
                    }
                }
            }
        }
    }

    @objc private func forgotPasswordTapped() {
        let passwordResetVC = PasswordResetViewController()
        navigationController?.pushViewController(passwordResetVC, animated: true)
    }

    @objc private func registerButtonTapped() {
        let registerVC = RegisterViewController()
        navigationController?.pushViewController(registerVC, animated: true)
    }

    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        let imageName = passwordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        togglePasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    @objc private func appleSignInButtonTapped() {
        print("🍎 Apple Sign-In button tapped in LoginViewController - Action triggered successfully!")
        proceedWithAppleSignIn()
    }

    private func proceedWithAppleSignIn() {
        print("🍎 Proceeding with Apple Sign-In")
        isLoggingIn = true

        SocialAuthService.shared.signInWithApple(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false

                switch result {
                case .success(let user):
                    print("🍎 Successfully logged in with Apple: \(user.displayName)")
                    AnalyticsService.shared.trackLogin(method: "apple")
                case .failure(let error):
                    print("🍎 Apple Sign-In Failed with error: \(error.localizedDescription)")

                    self?.showError("Apple Sign-In Failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func googleSignInButtonTapped() {
        isLoggingIn = true

        print("🔍 Google Sign-In button tapped in LoginViewController")

        SocialAuthService.shared.signInWithGoogle(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false

                switch result {
                case .success(let user):
                    print("🔍 Successfully logged in with Google: \(user.displayName)")
                    AnalyticsService.shared.trackLogin(method: "google")
                case .failure(let error):
                    print("🔍 Google Sign-In failed with error: \(error.localizedDescription)")
                    self?.showError("Google Sign-In Failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func facebookSignInButtonTapped() {
        isLoggingIn = true

        print("📘 Facebook Sign-In button tapped in LoginViewController")

        SocialAuthService.shared.signInWithFacebook(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false

                switch result {
                case .success(let user):
                    print("📘 Successfully logged in with Facebook: \(user.displayName)")
                    AnalyticsService.shared.trackLogin(method: "facebook")
                case .failure(let error):
                    print("📘 Facebook Sign-In failed with error: \(error.localizedDescription)")
                    self?.showError("Facebook Sign-In Failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Helper Methods
    private func loadSavedEmail() {
        if let credentials = KeychainManager.shared.retrieveCredentials() {
            emailTextField.text = credentials.email
            passwordTextField.text = credentials.password
        } else if let savedEmail = UserDefaults.standard.string(forKey: savedEmailKey) {
            emailTextField.text = savedEmail
        }
    }

    private func showEmailVerificationAlert(email: String) {
        AlertPresenter.showConfirmation(
            title: "Email Not Verified",
            message: "Please verify your email address before logging in. Check your inbox for the verification link sent to \(email).",
            confirmTitle: "Resend Email",
            from: self,
            onConfirm: { [weak self] in
                self?.resendVerificationEmail(email: email)
            }
        )
    }

    private func resendVerificationEmail(email: String) {
        AlertPresenter.showError(
            title: "Check Your Email",
            message: "A verification email was sent when you registered. Please check your inbox and spam folder for the verification link.",
            from: self
        )
    }

    // MARK: - Private Relay Guidance
    private func showPrivateRelayGuidance() {
        let alert = UIAlertController(
            title: "Email Not Accepted",
            message: "You selected 'Hide My Email' which is not supported.\n\nHow to fix this:\n1. Tap 'Try Again' below\n2. When Apple Sign-In appears, tap your name/email at the top\n3. Choose 'Share My Email' instead of 'Hide My Email'\n4. Continue with sign in\n\nWhy we need your real email:\n• Send daily activity summaries\n• Important account notifications\n• Password reset emails",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.proceedWithAppleSignIn()
        })

        alert.addAction(UIAlertAction(title: "Use Email Instead", style: .default) { [weak self] _ in
            // Navigate to email login/registration
            let registerVC = RegisterViewController()
            self?.navigationController?.pushViewController(registerVC, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    private func showAppleSignInGuidance() {
        let alert = UIAlertController(
            title: "Share Your Real Email",
            message: "To use Circles, please sign in with Apple again and choose 'Share My Email' instead of 'Hide My Email'. This ensures you can access your account from all devices.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.proceedWithAppleSignIn()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate
extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailTextField {
            passwordTextField.becomeFirstResponder()
        } else if textField == passwordTextField {
            dismissKeyboard()
            loginButtonTapped()
        }
        return true
    }
}

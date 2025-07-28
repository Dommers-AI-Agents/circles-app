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
        label.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let taglineLabel: UILabel = {
        let label = UILabel()
        label.text = "Organize and share your favorite places and people"
        label.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Ask your circle"
        label.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let appleSignInContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let appleSignInButton: ASAuthorizationAppleIDButton = {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .black)
        button.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = false
        return button
    }()
    
    private lazy var facebookSignInButton = UIButton.facebookSignInButton()
    private lazy var googleSignInButton = UIButton.googleSignInButton()
    private lazy var emailSignUpButton = UIButton.primaryButton(title: "Create Account")
    
    private let loginLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let attributedString = NSMutableAttributedString(string: "Have a Circles account? ")
        attributedString.append(NSAttributedString(string: "Log in", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        button.setAttributedTitle(attributedString, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
        
        // Configure custom button styles
        emailSignUpButton.backgroundColor = Constants.Colors.background
        emailSignUpButton.setTitleColor(Constants.Colors.primary, for: .normal)
        
        // Add background
        view.addSubview(backgroundView)
        
        // Add content
        backgroundView.addSubview(logoImageView)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(taglineLabel)
        backgroundView.addSubview(subtitleLabel)
        
        // Configure Apple Sign In button
        appleSignInContainer.addSubview(appleSignInButton)
        
        // Configure buttons stack
        buttonsStackView.addArrangedSubview(appleSignInContainer)
        buttonsStackView.addArrangedSubview(facebookSignInButton)
        buttonsStackView.addArrangedSubview(googleSignInButton)
        buttonsStackView.addArrangedSubview(emailSignUpButton)
        
        backgroundView.addSubview(buttonsStackView)
        backgroundView.addSubview(loginLinkButton)
        backgroundView.addSubview(privacyLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Background view
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Logo
            logoImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: backgroundView.safeAreaLayoutGuide.topAnchor, constant: 60),
            logoImageView.widthAnchor.constraint(equalToConstant: 80),
            logoImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Title
            titleLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            
            // Tagline
            taglineLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            taglineLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            taglineLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            taglineLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            
            // Subtitle
            subtitleLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            
            // Buttons stack view
            buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            buttonsStackView.bottomAnchor.constraint(equalTo: loginLinkButton.topAnchor, constant: -40),
            buttonsStackView.heightAnchor.constraint(equalToConstant: 248),
            
            // Apple Sign In button
            appleSignInButton.topAnchor.constraint(equalTo: appleSignInContainer.topAnchor),
            appleSignInButton.leadingAnchor.constraint(greaterThanOrEqualTo: appleSignInContainer.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(lessThanOrEqualTo: appleSignInContainer.trailingAnchor),
            appleSignInButton.bottomAnchor.constraint(equalTo: appleSignInContainer.bottomAnchor),
            appleSignInButton.centerXAnchor.constraint(equalTo: appleSignInContainer.centerXAnchor),
            appleSignInButton.widthAnchor.constraint(lessThanOrEqualToConstant: 375),
            appleSignInButton.widthAnchor.constraint(equalTo: appleSignInContainer.widthAnchor, multiplier: 1.0).withPriority(.defaultHigh),
            
            // Button heights
            appleSignInContainer.heightAnchor.constraint(equalToConstant: 50),
            
            // Login link
            loginLinkButton.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            loginLinkButton.bottomAnchor.constraint(equalTo: privacyLabel.topAnchor, constant: -60),
            
            // Privacy label
            privacyLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            privacyLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            privacyLabel.bottomAnchor.constraint(equalTo: backgroundView.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupActions() {
        // Apple Sign In
        let appleTapGesture = UITapGestureRecognizer(target: self, action: #selector(appleSignInButtonTapped))
        appleSignInContainer.addGestureRecognizer(appleTapGesture)
        
        // Social login buttons
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        
        // Email and login buttons
        emailSignUpButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        loginLinkButton.addTarget(self, action: #selector(loginLinkTapped), for: .touchUpInside)
        
        // Dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func updateButtonStates() {
        let buttons = [appleSignInButton, googleSignInButton, facebookSignInButton, emailSignUpButton, loginLinkButton]
        buttons.forEach { $0.isEnabled = !isLoggingIn }
        
        // Show/hide loading state
        if isLoggingIn {
            showLoadingState()
        } else {
            hideLoadingState()
        }
    }
    
    // MARK: - Actions
    @objc private func loginLinkTapped() {
        let loginVC = EmailLoginViewController()
        navigationController?.pushViewController(loginVC, animated: true)
    }
    
    @objc private func registerButtonTapped() {
        let registerVC = RegisterViewController()
        navigationController?.pushViewController(registerVC, animated: true)
    }
    
    @objc private func appleSignInButtonTapped() {
        print("🍎 Apple Sign-In button tapped in LoginViewController")
        isLoggingIn = true
        
        SocialAuthService.shared.signInWithApple(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false
                
                switch result {
                case .success(let user):
                    print("🍎 Successfully logged in with Apple: \(user.displayName)")
                case .failure(let error):
                    print("🍎 Apple Sign-In Failed with error: \(error.localizedDescription)")
                    
                    // Check if it's a private relay error
                    if let authError = error as? AuthError, authError == .privateRelayNotAllowed {
                        self?.showPrivateRelayGuidance()
                    } else {
                        self?.showError("Apple Sign-In Failed: \(error.localizedDescription)")
                    }
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
    
    // MARK: - Private Relay Guidance
    private func showPrivateRelayGuidance() {
        let alert = UIAlertController(
            title: "Private Relay Not Allowed",
            message: "We found you have an existing account with a private relay email. Would you like to sign in with your Gmail account and merge them?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Use Email Instead", style: .default) { [weak self] _ in
            // Navigate to email login/registration
            let registerVC = RegisterViewController()
            self?.navigationController?.pushViewController(registerVC, animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "Try Apple Again", style: .default) { [weak self] _ in
            // Show guidance for sharing real email
            self?.showAppleSignInGuidance()
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
            self?.appleSignInButtonTapped()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
}
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
        label.text = "Share your favorite places with friends"
        label.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Sign in to get started"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        label.text = "— or —"
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
    
    private let appleSignInSubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "For the best experience, we recommend sharing your email"
        label.font = UIFont.systemFont(ofSize: 10)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var emailSignUpButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Account with Email", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .white.withAlphaComponent(0.95)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }()
    
    private let loginLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let attributedString = NSMutableAttributedString(string: "Already have an account? ", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ])
        attributedString.append(NSAttributedString(string: "Sign in", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: UIColor.white
        ]))
        button.setAttributedTitle(attributedString, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
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
        
        // Add background
        view.addSubview(backgroundView)
        
        // Add content
        backgroundView.addSubview(logoImageView)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(taglineLabel)
        // Subtitle removed for cleaner layout
        // backgroundView.addSubview(subtitleLabel)
        
        // Configure Apple sign-in container
        appleSignInContainerView.addSubview(appleSignInButton)
        
        // Configure buttons stack - social login first (Facebook, then Google)
        buttonsStackView.addArrangedSubview(facebookSignInButton)
        buttonsStackView.addArrangedSubview(googleSignInButton)
        
        // Add smaller spacer before "or" divider
        let spacerView1 = UIView()
        spacerView1.translatesAutoresizingMaskIntoConstraints = false
        spacerView1.heightAnchor.constraint(equalToConstant: 8).isActive = true
        buttonsStackView.addArrangedSubview(spacerView1)
        
        buttonsStackView.addArrangedSubview(orDividerLabel)
        
        // Add smaller spacer after "or" divider
        let spacerView2 = UIView()
        spacerView2.translatesAutoresizingMaskIntoConstraints = false
        spacerView2.heightAnchor.constraint(equalToConstant: 8).isActive = true
        buttonsStackView.addArrangedSubview(spacerView2)
        
        buttonsStackView.addArrangedSubview(emailSignUpButton)
        buttonsStackView.addArrangedSubview(appleSignInContainerView)
        
        // Set height constraint for "or" divider to be smaller than buttons
        orDividerLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
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
            
            // Subtitle constraints commented out
            // subtitleLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            // subtitleLabel.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 8),
            // subtitleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            // subtitleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            
            // Buttons stack view - positioned below tagline with proper spacing
            buttonsStackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            buttonsStackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            buttonsStackView.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 60),
            
            // Login link
            loginLinkButton.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            loginLinkButton.topAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 20),
            
            // Privacy label
            privacyLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            privacyLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            privacyLabel.bottomAnchor.constraint(equalTo: backgroundView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
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
        // Social login buttons
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
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
        print("🍎 Apple Sign-In button tapped in LoginViewController - Action triggered successfully!")
        
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
        print("🍎 Proceeding with Apple Sign-In after warning")
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
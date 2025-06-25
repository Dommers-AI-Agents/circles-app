import UIKit
import AuthenticationServices

class LoginViewController: UIViewController {
    
    // MARK: - UI Elements
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary // Blue background
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
    
    // Using a container view for Apple Sign In button to handle tap events properly
    private let appleSignInContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let appleSignInButton: ASAuthorizationAppleIDButton = {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .black)
        button.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isUserInteractionEnabled = false // Let container handle taps
        return button
    }()
    
    private let facebookSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Facebook", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 59/255, green: 89/255, blue: 152/255, alpha: 1.0)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let googleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Google", for: .normal)
        button.setTitleColor(Constants.Colors.label, for: .normal)
        button.backgroundColor = Constants.Colors.background
        button.titleLabel?.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let emailSignUpButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Account", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = Constants.Colors.background
        button.titleLabel?.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Properties
    private var isLoggingIn = false {
        didSet {
            appleSignInButton.isEnabled = !isLoggingIn
            googleSignInButton.isEnabled = !isLoggingIn
            facebookSignInButton.isEnabled = !isLoggingIn
            emailSignUpButton.isEnabled = !isLoggingIn
            loginLinkButton.isEnabled = !isLoggingIn
            
            if isLoggingIn {
                activityIndicator.startAnimating()
                activityIndicator.color = .white
            } else {
                activityIndicator.stopAnimating()
            }
        }
    }
    
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
        
        // Add logo and text
        backgroundView.addSubview(logoImageView)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(taglineLabel)
        backgroundView.addSubview(subtitleLabel)
        
        // Configure Apple Sign In button in container
        appleSignInContainer.addSubview(appleSignInButton)
        
        // Configure buttons stack
        buttonsStackView.addArrangedSubview(appleSignInContainer)
        buttonsStackView.addArrangedSubview(facebookSignInButton)
        buttonsStackView.addArrangedSubview(googleSignInButton)
        buttonsStackView.addArrangedSubview(emailSignUpButton)
        
        backgroundView.addSubview(buttonsStackView)
        backgroundView.addSubview(loginLinkButton)
        backgroundView.addSubview(privacyLabel)
        backgroundView.addSubview(activityIndicator)
        
        // Layout constraints
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
            buttonsStackView.heightAnchor.constraint(equalToConstant: 280), // 5 buttons * 50 height + 4 * 16 spacing
            
            // Apple Sign In button in container
            appleSignInButton.topAnchor.constraint(equalTo: appleSignInContainer.topAnchor),
            appleSignInButton.leadingAnchor.constraint(equalTo: appleSignInContainer.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(equalTo: appleSignInContainer.trailingAnchor),
            appleSignInButton.bottomAnchor.constraint(equalTo: appleSignInContainer.bottomAnchor),
            
            // Button heights
            appleSignInContainer.heightAnchor.constraint(equalToConstant: 50),
            facebookSignInButton.heightAnchor.constraint(equalToConstant: 50),
            googleSignInButton.heightAnchor.constraint(equalToConstant: 50),
            emailSignUpButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Login link
            loginLinkButton.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            loginLinkButton.bottomAnchor.constraint(equalTo: privacyLabel.topAnchor, constant: -60),
            
            // Privacy label
            privacyLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 40),
            privacyLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -40),
            privacyLabel.bottomAnchor.constraint(equalTo: backgroundView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor)
        ])
        
    }
    
    private func setupActions() {
        // Apple Sign In needs a tap gesture on container
        let appleTapGesture = UITapGestureRecognizer(target: self, action: #selector(appleSignInButtonTapped))
        appleSignInContainer.addGestureRecognizer(appleTapGesture)
        
        // Other social login buttons
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        
        // Email and login buttons
        emailSignUpButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        loginLinkButton.addTarget(self, action: #selector(loginLinkTapped), for: .touchUpInside)
        
        // Add tap gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Actions
    @objc private func loginLinkTapped() {
        // Navigate to a separate login screen with email/password fields
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
                    // Authentication state listener in SceneDelegate will handle UI update
                case .failure(let error):
                    print("🍎 Apple Sign-In Failed with error: \(error.localizedDescription)")
                    self?.presentAlert(title: "Apple Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func googleSignInButtonTapped() {
        isLoggingIn = true
        
        // Add detailed logging
        print("🔍 Google Sign-In button tapped in LoginViewController")
        
        SocialAuthService.shared.signInWithGoogle(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false
                
                switch result {
                case .success(let user):
                    print("🔍 Successfully logged in with Google: \(user.displayName)")
                    // Authentication state listener in SceneDelegate will handle UI update
                case .failure(let error):
                    print("🔍 Google Sign-In failed with error: \(error.localizedDescription)")
                    print("🔍 Error details: \(error)")
                    self?.presentAlert(title: "Google Sign-In Failed", message: error.localizedDescription)
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
                    // Authentication state listener in SceneDelegate will handle UI update
                case .failure(let error):
                    print("📘 Facebook Sign-In failed with error: \(error.localizedDescription)")
                    self?.presentAlert(title: "Facebook Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Helper Methods
    private func presentAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
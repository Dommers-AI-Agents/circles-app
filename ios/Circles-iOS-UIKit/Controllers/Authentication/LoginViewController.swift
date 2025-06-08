import UIKit
import AuthenticationServices

class LoginViewController: UIViewController {
    
    // MARK: - UI Elements
    private let logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.grid.2x2.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.huge, weight: .bold)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Share your favorite places with friends"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Email"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .emailAddress
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let loginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Login", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let orLabel: UILabel = {
        let label = UILabel()
        label.text = "OR"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let socialStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = Constants.Spacing.medium
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = true
        return stackView
    }()
    
    private let topSocialStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = Constants.Spacing.medium
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let bottomSocialStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = Constants.Spacing.medium
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let appleSignInButton: ASAuthorizationAppleIDButton = {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .black)
        button.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        // Debug accessibility
        button.isAccessibilityElement = true
        button.accessibilityLabel = "Sign in with Apple"
        button.accessibilityIdentifier = "appleSignInButton"
        button.isUserInteractionEnabled = true
        return button
    }()
    
    private let googleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Google", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 66/255, green: 133/255, blue: 244/255, alpha: 1.0)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let facebookSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Facebook", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 24/255, green: 119/255, blue: 242/255, alpha: 1.0)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let linkedInSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with LinkedIn", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0/255, green: 119/255, blue: 181/255, alpha: 1.0)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let guestModeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Continue as Guest", for: .normal)
        button.setTitleColor(Constants.Colors.secondary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Don't have an account? Register", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Properties
    private let savedEmailKey = "savedUserEmail"
    
    private var isLoggingIn = false {
        didSet {
            loginButton.isEnabled = !isLoggingIn
            appleSignInButton.isEnabled = !isLoggingIn
            googleSignInButton.isEnabled = !isLoggingIn
            facebookSignInButton.isEnabled = !isLoggingIn
            linkedInSignInButton.isEnabled = !isLoggingIn
            guestModeButton.isEnabled = !isLoggingIn
            registerButton.isEnabled = !isLoggingIn
            emailTextField.isEnabled = !isLoggingIn
            passwordTextField.isEnabled = !isLoggingIn
            
            if isLoggingIn {
                activityIndicator.startAnimating()
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
        loadSavedEmail()
        
        // Show the custom button for testing
        
        // For development purposes, pre-fill email
        #if DEBUG
        // Only pre-fill if there's no saved email
        if emailTextField.text?.isEmpty ?? true {
            emailTextField.text = "user@example.com"
            passwordTextField.text = "password"
        }
        #endif
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
        
        // Configure social stack view
        topSocialStackView.addArrangedSubview(appleSignInButton)
        topSocialStackView.addArrangedSubview(googleSignInButton)
        bottomSocialStackView.addArrangedSubview(facebookSignInButton)
        bottomSocialStackView.addArrangedSubview(linkedInSignInButton)
        socialStackView.addArrangedSubview(topSocialStackView)
        socialStackView.addArrangedSubview(bottomSocialStackView)
        
        // Add subviews
        view.addSubview(logoImageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(emailTextField)
        view.addSubview(passwordTextField)
        view.addSubview(loginButton)
        view.addSubview(orLabel)
        view.addSubview(socialStackView)
        view.addSubview(guestModeButton)
        view.addSubview(registerButton)
        view.addSubview(activityIndicator)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Logo
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.xlarge),
            logoImageView.widthAnchor.constraint(equalToConstant: 100),
            logoImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Title
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: Constants.Spacing.medium),
            
            // Subtitle
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.Spacing.small),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Email text field
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            emailTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            emailTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Password text field
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: Constants.Spacing.medium),
            passwordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            passwordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Login button
            loginButton.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: Constants.Spacing.large),
            loginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            loginButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Or label
            orLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: Constants.Spacing.medium),
            orLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Social sign-in stack view
            socialStackView.topAnchor.constraint(equalTo: orLabel.bottomAnchor, constant: Constants.Spacing.medium),
            socialStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            socialStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            socialStackView.heightAnchor.constraint(equalToConstant: 110), // Increased for two rows
            
            
            // Guest mode button
            guestModeButton.topAnchor.constraint(equalTo: socialStackView.bottomAnchor, constant: Constants.Spacing.medium),
            guestModeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Register button
            registerButton.topAnchor.constraint(equalTo: guestModeButton.bottomAnchor, constant: Constants.Spacing.large),
            registerButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: registerButton.bottomAnchor, constant: Constants.Spacing.large)
        ])
        
        // Setup text field delegates
        emailTextField.delegate = self
        passwordTextField.delegate = self
    }
    
    private func setupActions() {
        // Standard login buttons
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        guestModeButton.addTarget(self, action: #selector(guestModeButtonTapped), for: .touchUpInside)
        
        // Social login buttons
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        linkedInSignInButton.addTarget(self, action: #selector(linkedInSignInButtonTapped), for: .touchUpInside)
        
        
        // Add tap gesture recognizer specifically for appleSignInButton to debug
        let appleTapGesture = UITapGestureRecognizer(target: self, action: #selector(appleSignInGestureTapped))
        appleSignInButton.addGestureRecognizer(appleTapGesture)
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
        
        print("🍎 All button actions set up")
    }
    
    @objc private func appleSignInGestureTapped() {
        print("🍎 Apple Sign-In button tapped via gesture recognizer")
        appleSignInButtonTapped()
    }
    
    // MARK: - Actions
    @objc private func loginButtonTapped() {
        guard let email = emailTextField.text, !email.isEmpty,
              let password = passwordTextField.text, !password.isEmpty else {
            presentAlert(title: "Error", message: "Please enter both email and password")
            return
        }
        
        // Start loading state
        isLoggingIn = true
        
        // Attempt login
        AuthService.shared.login(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false
                
                switch result {
                case .success(let user):
                    print("Successfully logged in user: \(user.displayName)")
                    // Save the email for next time
                    self?.saveEmail(email)
                    // Authentication state listener in SceneDelegate will handle UI update
                    
                case .failure(let error):
                    self?.presentAlert(title: "Login Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func registerButtonTapped() {
        let registerVC = RegisterViewController()
        navigationController?.pushViewController(registerVC, animated: true)
    }
    
    @objc private func guestModeButtonTapped() {
        // For demo purposes, we'll create a guest session
        isLoggingIn = true
        
        // Delay to simulate network request
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isLoggingIn = false
            
            // Switch to main interface without authentication
            let mainTabController = CirclesTabBarController()
            UIApplication.shared.windows.first?.rootViewController = mainTabController
            UIApplication.shared.windows.first?.makeKeyAndVisible()
        }
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
        
        // Try basic error handling with a backup implementation
        do {
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
        } catch {
            print("🔍 Exception during Google Sign-In: \(error)")
            self.isLoggingIn = false
            self.presentAlert(title: "Google Sign-In Failed", message: "An unexpected error occurred. Please try again.")
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
    
    @objc private func linkedInSignInButtonTapped() {
        isLoggingIn = true
        
        print("🔗 LinkedIn Sign-In button tapped in LoginViewController")
        
        SocialAuthService.shared.signInWithLinkedIn(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false
                
                switch result {
                case .success(let user):
                    print("🔗 Successfully logged in with LinkedIn: \(user.displayName)")
                    // Authentication state listener in SceneDelegate will handle UI update
                case .failure(let error):
                    print("🔗 LinkedIn Sign-In failed with error: \(error.localizedDescription)")
                    self?.presentAlert(title: "LinkedIn Sign-In Failed", message: error.localizedDescription)
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
    
    private func saveEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: savedEmailKey)
    }
    
    private func loadSavedEmail() {
        if let savedEmail = UserDefaults.standard.string(forKey: savedEmailKey) {
            emailTextField.text = savedEmail
        }
    }
}

// MARK: - UITextFieldDelegate
extension LoginViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Clear the pre-filled debug text when user starts editing
        #if DEBUG
        if textField == emailTextField && textField.text == "user@example.com" {
            textField.text = ""
        } else if textField == passwordTextField && textField.text == "password" {
            textField.text = ""
        }
        #endif
    }
    
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
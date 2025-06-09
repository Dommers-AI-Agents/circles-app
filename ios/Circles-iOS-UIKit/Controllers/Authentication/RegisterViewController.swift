import UIKit
import AuthenticationServices

class RegisterViewController: UIViewController {
    
    // MARK: - UI Elements
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
        label.textColor = Constants.Colors.darkGray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your email to get started"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.textAlignment = .center
        label.numberOfLines = 0
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
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Confirm Password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let passwordRequirementLabel: UILabel = {
        let label = UILabel()
        label.text = "Password must be at least 6 characters"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Account", for: .normal)
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
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signUp, authorizationButtonStyle: .black)
        button.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let googleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign up with Google", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 66/255, green: 133/255, blue: 244/255, alpha: 1.0)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let facebookSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign up with Facebook", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 24/255, green: 119/255, blue: 242/255, alpha: 1.0) // Facebook Blue
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let linkedInSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sign up with LinkedIn", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0/255, green: 119/255, blue: 181/255, alpha: 1.0) // LinkedIn Blue
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.layer.cornerRadius = 8
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
    private var isRegistering = false {
        didSet {
            registerButton.isEnabled = !isRegistering
            appleSignInButton.isEnabled = !isRegistering
            googleSignInButton.isEnabled = !isRegistering
            facebookSignInButton.isEnabled = !isRegistering
            linkedInSignInButton.isEnabled = !isRegistering
            emailTextField.isEnabled = !isRegistering
            passwordTextField.isEnabled = !isRegistering
            confirmPasswordTextField.isEnabled = !isRegistering
            
            if isRegistering {
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        title = "Register"
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Configure social stack views
        topSocialStackView.addArrangedSubview(appleSignInButton)
        topSocialStackView.addArrangedSubview(googleSignInButton)
        
        bottomSocialStackView.addArrangedSubview(facebookSignInButton)
        bottomSocialStackView.addArrangedSubview(linkedInSignInButton)
        
        socialStackView.addArrangedSubview(topSocialStackView)
        socialStackView.addArrangedSubview(bottomSocialStackView)
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(passwordRequirementLabel)
        contentView.addSubview(registerButton)
        contentView.addSubview(orLabel)
        contentView.addSubview(socialStackView)
        contentView.addSubview(activityIndicator)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title label
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Subtitle label
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.Spacing.small),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Email text field
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Password text field
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: Constants.Spacing.medium),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Confirm password text field
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: Constants.Spacing.medium),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Password requirement label
            passwordRequirementLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: Constants.Spacing.small),
            passwordRequirementLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            passwordRequirementLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Register button
            registerButton.topAnchor.constraint(equalTo: passwordRequirementLabel.bottomAnchor, constant: Constants.Spacing.large),
            registerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            registerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            registerButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Or label
            orLabel.topAnchor.constraint(equalTo: registerButton.bottomAnchor, constant: Constants.Spacing.medium),
            orLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Social sign-in stack view
            socialStackView.topAnchor.constraint(equalTo: orLabel.bottomAnchor, constant: Constants.Spacing.medium),
            socialStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            socialStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            socialStackView.heightAnchor.constraint(equalToConstant: 110), // Height for 2 rows of buttons
            
            // Activity indicator
            activityIndicator.topAnchor.constraint(equalTo: socialStackView.bottomAnchor, constant: Constants.Spacing.medium),
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Setup text field delegates
        emailTextField.delegate = self
        passwordTextField.delegate = self
        confirmPasswordTextField.delegate = self
    }
    
    private func setupActions() {
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        
        // Social login buttons
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        linkedInSignInButton.addTarget(self, action: #selector(linkedInSignInButtonTapped), for: .touchUpInside)
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
        
        // Setup keyboard notifications
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Actions
    @objc private func registerButtonTapped() {
        // Validate inputs
        guard let email = emailTextField.text, !email.isEmpty, isValidEmail(email) else {
            presentAlert(title: "Error", message: "Please enter a valid email address")
            return
        }
        
        guard let password = passwordTextField.text, !password.isEmpty, password.count >= 6 else {
            presentAlert(title: "Error", message: "Password must be at least 6 characters")
            return
        }
        
        guard let confirmPassword = confirmPasswordTextField.text, confirmPassword == password else {
            presentAlert(title: "Error", message: "Passwords do not match")
            return
        }
        
        // Start registration
        isRegistering = true
        
        // Create a default display name from email
        let displayName = email.components(separatedBy: "@").first ?? "User"
        
        // Attempt registration
        AuthService.shared.register(email: email, password: password, displayName: displayName) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered user: \(user.displayName)")
                    // Show email verification message
                    self?.showEmailVerificationMessage(email: email)
                    
                case .failure(let error):
                    self?.presentAlert(title: "Registration Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func showEmailVerificationMessage(email: String) {
        let alert = UIAlertController(
            title: "Verify Your Email",
            message: "A verification email has been sent to \(email). Please check your inbox and follow the link to verify your account before logging in.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            // Navigate back to login screen
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    private func showSuccessMessage() {
        let alert = UIAlertController(
            title: "Registration Successful",
            message: "Welcome to Circles! You can now log in with your account.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            // Navigate back to login screen
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func appleSignInButtonTapped() {
        isRegistering = true
        
        SocialAuthService.shared.signInWithApple(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered with Apple: \(user.displayName)")
                    // Show success message and return to login
                    self?.showSuccessMessage()
                case .failure(let error):
                    self?.presentAlert(title: "Apple Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func googleSignInButtonTapped() {
        isRegistering = true
        
        SocialAuthService.shared.signInWithGoogle(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered with Google: \(user.displayName)")
                    // Show success message and return to login
                    self?.showSuccessMessage()
                case .failure(let error):
                    self?.presentAlert(title: "Google Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func facebookSignInButtonTapped() {
        isRegistering = true
        
        SocialAuthService.shared.signInWithFacebook(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered with Facebook: \(user.displayName)")
                    // Show success message and return to login
                    self?.showSuccessMessage()
                case .failure(let error):
                    self?.presentAlert(title: "Facebook Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func linkedInSignInButtonTapped() {
        isRegistering = true
        
        SocialAuthService.shared.signInWithLinkedIn(from: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered with LinkedIn: \(user.displayName)")
                    // Show success message and return to login
                    self?.showSuccessMessage()
                case .failure(let error):
                    self?.presentAlert(title: "LinkedIn Sign-In Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        
        // If active text field is hidden by keyboard, scroll to make it visible
        var aRect = view.frame
        aRect.size.height -= keyboardSize.height
        
        if let activeField = findFirstResponder() {
            if let activeFieldFrame = activeField.superview?.convert(activeField.frame, to: scrollView) {
                if !aRect.contains(activeFieldFrame.origin) {
                    scrollView.scrollRectToVisible(activeFieldFrame, animated: true)
                }
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }
    
    // MARK: - Helper Methods
    private func presentAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        // Basic email validation
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func findFirstResponder() -> UIView? {
        let responders: [UIView] = [emailTextField, passwordTextField, confirmPasswordTextField]
        return responders.first { $0.isFirstResponder }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITextFieldDelegate
extension RegisterViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case emailTextField:
            passwordTextField.becomeFirstResponder()
        case passwordTextField:
            confirmPasswordTextField.becomeFirstResponder()
        case confirmPasswordTextField:
            textField.resignFirstResponder()
            registerButtonTapped()
        default:
            textField.resignFirstResponder()
        }
        return true
    }
}
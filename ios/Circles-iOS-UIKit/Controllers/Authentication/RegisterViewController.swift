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
    
    private let displayNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Display Name"
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
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
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let locationTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Location (optional)"
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let bioTextView: UITextView = {
        let textView = UITextView()
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let bioLabel: UILabel = {
        let label = UILabel()
        label.text = "Bio (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bioPlaceholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Tell us a bit about yourself..."
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.lightGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Register", for: .normal)
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
            displayNameTextField.isEnabled = !isRegistering
            emailTextField.isEnabled = !isRegistering
            passwordTextField.isEnabled = !isRegistering
            confirmPasswordTextField.isEnabled = !isRegistering
            locationTextField.isEnabled = !isRegistering
            bioTextView.isEditable = !isRegistering
            
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
        
        // Configure social stack view
        socialStackView.addArrangedSubview(appleSignInButton)
        socialStackView.addArrangedSubview(googleSignInButton)
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(displayNameTextField)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(locationTextField)
        contentView.addSubview(bioLabel)
        contentView.addSubview(bioTextView)
        contentView.addSubview(bioPlaceholderLabel)
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
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Display name text field
            displayNameTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            displayNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            displayNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            displayNameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Email text field
            emailTextField.topAnchor.constraint(equalTo: displayNameTextField.bottomAnchor, constant: Constants.Spacing.medium),
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
            
            // Location text field
            locationTextField.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: Constants.Spacing.medium),
            locationTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            locationTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            locationTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: locationTextField.bottomAnchor, constant: Constants.Spacing.medium),
            bioLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Bio text view
            bioTextView.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: Constants.Spacing.small),
            bioTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            bioTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            bioTextView.heightAnchor.constraint(equalToConstant: 100),
            
            // Bio placeholder label
            bioPlaceholderLabel.topAnchor.constraint(equalTo: bioTextView.topAnchor, constant: 8),
            bioPlaceholderLabel.leadingAnchor.constraint(equalTo: bioTextView.leadingAnchor, constant: 4),
            
            // Register button
            registerButton.topAnchor.constraint(equalTo: bioTextView.bottomAnchor, constant: Constants.Spacing.large),
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
            socialStackView.heightAnchor.constraint(equalToConstant: 50),
            
            // Activity indicator
            activityIndicator.topAnchor.constraint(equalTo: socialStackView.bottomAnchor, constant: Constants.Spacing.medium),
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Setup text field delegates
        displayNameTextField.delegate = self
        emailTextField.delegate = self
        passwordTextField.delegate = self
        confirmPasswordTextField.delegate = self
        locationTextField.delegate = self
        bioTextView.delegate = self
    }
    
    private func setupActions() {
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        
        // Social login buttons
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        
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
        guard let displayName = displayNameTextField.text, !displayName.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a display name")
            return
        }
        
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
        
        // Optional fields
        let location = locationTextField.text
        let bio = bioTextView.text != "Tell us a bit about yourself..." ? bioTextView.text : nil
        
        // Start registration
        isRegistering = true
        
        // Attempt registration
        AuthService.shared.register(email: email, password: password, displayName: displayName) { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered user: \(user.displayName)")
                    
                    // Update profile with optional info if provided
                    if location != nil && !location!.isEmpty || bio != nil && !bio!.isEmpty {
                        self?.updateProfile(displayName: nil, bio: bio, location: location)
                    } else {
                        // Show success message
                        self?.showSuccessMessage()
                    }
                    
                case .failure(let error):
                    self?.presentAlert(title: "Registration Failed", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func updateProfile(displayName: String?, bio: String?, location: String?) {
        UserService.shared.updateUserProfile(displayName: displayName, bio: bio, location: location) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // Show success message
                    self?.showSuccessMessage()
                case .failure(let error):
                    // Registration succeeded but profile update failed
                    print("Profile update failed: \(error.localizedDescription)")
                    // Still show success for registration
                    self?.showSuccessMessage()
                }
            }
        }
    }
    
    private func showSuccessMessage() {
        let alert = UIAlertController(title: "Registration Successful", message: "Welcome to Circles!", preferredStyle: .alert)
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
        let responders: [UIView] = [displayNameTextField, emailTextField, passwordTextField, confirmPasswordTextField, locationTextField, bioTextView]
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
        case displayNameTextField:
            emailTextField.becomeFirstResponder()
        case emailTextField:
            passwordTextField.becomeFirstResponder()
        case passwordTextField:
            confirmPasswordTextField.becomeFirstResponder()
        case confirmPasswordTextField:
            locationTextField.becomeFirstResponder()
        case locationTextField:
            bioTextView.becomeFirstResponder()
        default:
            textField.resignFirstResponder()
        }
        return true
    }
}

// MARK: - UITextViewDelegate
extension RegisterViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == "Tell us a bit about yourself..." {
            textView.text = ""
            textView.textColor = Constants.Colors.darkGray
            bioPlaceholderLabel.isHidden = true
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = "Tell us a bit about yourself..."
            textView.textColor = Constants.Colors.lightGray
            bioPlaceholderLabel.isHidden = false
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
        bioPlaceholderLabel.isHidden = !textView.text.isEmpty
    }
}
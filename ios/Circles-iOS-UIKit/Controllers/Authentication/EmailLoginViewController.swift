import UIKit

class EmailLoginViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Log in to Circles"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = Constants.Colors.label
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
    
    private lazy var togglePasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye.slash.fill"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var loginButton = UIButton.primaryButton(title: "Log in")
    
    private let rememberMeContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let rememberMeCheckbox: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square"), for: .normal)
        button.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let rememberMeLabel: UILabel = {
        let label = UILabel()
        label.text = "Remember me"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var forgotPasswordButton = UIButton.secondaryButton(title: "Forgot password?")
    
    // MARK: - Properties
    private let savedEmailKey = "savedUserEmail"
    
    private var isLoggingIn = false {
        didSet {
            loginButton.isEnabled = !isLoggingIn
            emailTextField.isEnabled = !isLoggingIn
            passwordTextField.isEnabled = !isLoggingIn
            
            if isLoggingIn {
                loginButton.setLoading(true)
            } else {
                loginButton.setLoading(false)
                loginButton.setTitle("Log in", for: .normal)
            }
        }
    }
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        loadSavedCredentials()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Setup remember me container
        rememberMeContainer.addSubview(rememberMeCheckbox)
        rememberMeContainer.addSubview(rememberMeLabel)
        
        // Setup password field right view
        passwordTextField.rightView = togglePasswordButton
        passwordTextField.rightViewMode = .always
        
        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(emailTextField)
        view.addSubview(passwordTextField)
        view.addSubview(rememberMeContainer)
        view.addSubview(loginButton)
        view.addSubview(forgotPasswordButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            emailTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emailTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            passwordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            togglePasswordButton.widthAnchor.constraint(equalToConstant: 44),
            
            rememberMeContainer.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 16),
            rememberMeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            rememberMeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            rememberMeContainer.heightAnchor.constraint(equalToConstant: 30),
            
            rememberMeCheckbox.leadingAnchor.constraint(equalTo: rememberMeContainer.leadingAnchor),
            rememberMeCheckbox.centerYAnchor.constraint(equalTo: rememberMeContainer.centerYAnchor),
            rememberMeCheckbox.widthAnchor.constraint(equalToConstant: 24),
            rememberMeCheckbox.heightAnchor.constraint(equalToConstant: 24),
            
            rememberMeLabel.leadingAnchor.constraint(equalTo: rememberMeCheckbox.trailingAnchor, constant: 8),
            rememberMeLabel.centerYAnchor.constraint(equalTo: rememberMeContainer.centerYAnchor),
            rememberMeLabel.trailingAnchor.constraint(equalTo: rememberMeContainer.trailingAnchor),
            
            loginButton.topAnchor.constraint(equalTo: rememberMeContainer.bottomAnchor, constant: 24),
            loginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            loginButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            forgotPasswordButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 16),
            forgotPasswordButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            forgotPasswordButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        
        // Setup text field delegates
        emailTextField.delegate = self
        passwordTextField.delegate = self
    }
    
    private func setupActions() {
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        rememberMeCheckbox.addTarget(self, action: #selector(rememberMeToggled), for: .touchUpInside)
        togglePasswordButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        
        // Add tap gesture to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
        
        // Add tap gesture to remember me label
        let rememberMeTap = UITapGestureRecognizer(target: self, action: #selector(rememberMeToggled))
        rememberMeLabel.isUserInteractionEnabled = true
        rememberMeLabel.addGestureRecognizer(rememberMeTap)
    }
    
    // MARK: - Actions
    @objc private func loginButtonTapped() {
        guard let email = emailTextField.text, !email.isEmpty,
              let password = passwordTextField.text, !password.isEmpty else {
            showError("Please enter both email and password")
            return
        }
        
        isLoggingIn = true
        
        AuthService.shared.login(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoggingIn = false
                
                switch result {
                case .success(let user):
                    print("Successfully logged in user: \(user.displayName)")
                    self?.saveEmail(email)
                    
                    // Save credentials if remember me is checked
                    if self?.rememberMeCheckbox.isSelected == true {
                        KeychainManager.shared.saveCredentials(email: email, password: password)
                    } else {
                        KeychainManager.shared.deleteCredentials()
                    }
                    
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
        AlertPresenter.showError(title: "Coming Soon", message: "Password reset functionality will be available soon.", from: self)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func rememberMeToggled() {
        rememberMeCheckbox.isSelected = !rememberMeCheckbox.isSelected
    }
    
    @objc private func togglePasswordVisibility() {
        passwordTextField.isSecureTextEntry.toggle()
        let imageName = passwordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        togglePasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    // MARK: - Helper Methods
    private func saveEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: savedEmailKey)
    }
    
    private func loadSavedCredentials() {
        // First try to load from keychain (if remember me was checked)
        if let credentials = KeychainManager.shared.retrieveCredentials() {
            emailTextField.text = credentials.email
            passwordTextField.text = credentials.password
            rememberMeCheckbox.isSelected = true
        } else {
            // Fall back to just loading saved email
            if let savedEmail = UserDefaults.standard.string(forKey: savedEmailKey) {
                emailTextField.text = savedEmail
            }
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
}

// MARK: - UITextFieldDelegate
extension EmailLoginViewController: UITextFieldDelegate {
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
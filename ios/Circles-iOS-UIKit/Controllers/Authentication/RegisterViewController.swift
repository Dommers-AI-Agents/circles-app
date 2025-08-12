import UIKit
import AuthenticationServices

class RegisterViewController: BaseViewController {
    
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
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your email to get started"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
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
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let zipcodeTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Zipcode"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let zipcodeLabel: UILabel = {
        let label = UILabel()
        label.text = "Your zipcode helps us show you great places nearby and connect you with local members"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let referralCodeTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Referral Code (Optional)"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let referralCodeLabel: UILabel = {
        let label = UILabel()
        label.text = "Have a referral code? Get 1 month free!"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.primary
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
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
        label.text = "Password must be at least 6 characters"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var registerButton = UIButton.primaryButton(title: "Create Account")
    
    private let orContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let orLabel: UILabel = {
        let label = UILabel()
        label.text = "OR"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.backgroundColor = Constants.Colors.background
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let leftDivider: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let rightDivider: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.separator
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
    
    private let appleSignInButton: ASAuthorizationAppleIDButton = {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signUp, authorizationButtonStyle: .black)
        button.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
    private var isRegistering = false {
        didSet {
            let buttons = [registerButton, appleSignInButton, googleSignInButton, facebookSignInButton]
            buttons.forEach { $0.isEnabled = !isRegistering }
            
            let textFields = [emailTextField, passwordTextField, confirmPasswordTextField, referralCodeTextField]
            textFields.forEach { $0.isEnabled = !isRegistering }
            
            if isRegistering {
                registerButton.setLoading(true)
            } else {
                registerButton.setLoading(false)
                registerButton.setTitle("Create Account", for: .normal)
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNavigationBar(title: "Register", largeTitleMode: .automatic)
        
        // Check if we have a pending referral code from deep link
        if let pendingCode = ReferralService.shared.getPendingReferralCode() {
            referralCodeTextField.text = pendingCode
            referralCodeLabel.text = "✅ Referral code applied! You'll get 1 month free."
            referralCodeLabel.textColor = Constants.Colors.success
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Configure social stack view
        socialStackView.addArrangedSubview(appleSignInButton)
        socialStackView.addArrangedSubview(googleSignInButton)
        socialStackView.addArrangedSubview(facebookSignInButton)
        
        // Setup password field right views
        passwordTextField.rightView = togglePasswordButton
        passwordTextField.rightViewMode = .always
        confirmPasswordTextField.rightView = toggleConfirmPasswordButton
        confirmPasswordTextField.rightViewMode = .always
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add dividers to OR container
        orContainerView.addSubview(leftDivider)
        orContainerView.addSubview(orLabel)
        orContainerView.addSubview(rightDivider)
        
        let subviews = [titleLabel, subtitleLabel, emailTextField, passwordTextField, 
                       confirmPasswordTextField, passwordRequirementLabel, zipcodeTextField,
                       zipcodeLabel, referralCodeTextField, referralCodeLabel, registerButton, 
                       orContainerView, socialStackView]
        subviews.forEach { contentView.addSubview($0) }
        
        setupConstraints()
        setupTextFieldDelegates()
    }
    
    private func setupConstraints() {
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
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.Spacing.small),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Email field
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Password field
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: Constants.Spacing.medium),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            passwordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Toggle password button
            togglePasswordButton.widthAnchor.constraint(equalToConstant: 44),
            
            // Confirm password field
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: Constants.Spacing.medium),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Toggle confirm password button
            toggleConfirmPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            
            // Password requirement
            passwordRequirementLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: Constants.Spacing.small),
            passwordRequirementLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            passwordRequirementLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Zipcode field
            zipcodeTextField.topAnchor.constraint(equalTo: passwordRequirementLabel.bottomAnchor, constant: Constants.Spacing.medium),
            zipcodeTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            zipcodeTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            zipcodeTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Zipcode label
            zipcodeLabel.topAnchor.constraint(equalTo: zipcodeTextField.bottomAnchor, constant: Constants.Spacing.small),
            zipcodeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            zipcodeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Referral code field
            referralCodeTextField.topAnchor.constraint(equalTo: zipcodeLabel.bottomAnchor, constant: Constants.Spacing.medium),
            referralCodeTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            referralCodeTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            referralCodeTextField.heightAnchor.constraint(equalToConstant: 50),
            
            // Referral code label
            referralCodeLabel.topAnchor.constraint(equalTo: referralCodeTextField.bottomAnchor, constant: Constants.Spacing.small),
            referralCodeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            referralCodeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Register button
            registerButton.topAnchor.constraint(equalTo: referralCodeLabel.bottomAnchor, constant: Constants.Spacing.large),
            registerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            registerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // OR container with dividers
            orContainerView.topAnchor.constraint(equalTo: registerButton.bottomAnchor, constant: Constants.Spacing.large),
            orContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            orContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            orContainerView.heightAnchor.constraint(equalToConstant: 20),
            
            // Left divider
            leftDivider.leadingAnchor.constraint(equalTo: orContainerView.leadingAnchor),
            leftDivider.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            leftDivider.heightAnchor.constraint(equalToConstant: 1),
            leftDivider.trailingAnchor.constraint(equalTo: orLabel.leadingAnchor, constant: -Constants.Spacing.medium),
            
            // OR label
            orLabel.centerXAnchor.constraint(equalTo: orContainerView.centerXAnchor),
            orLabel.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            orLabel.widthAnchor.constraint(equalToConstant: 40),
            
            // Right divider
            rightDivider.leadingAnchor.constraint(equalTo: orLabel.trailingAnchor, constant: Constants.Spacing.medium),
            rightDivider.centerYAnchor.constraint(equalTo: orContainerView.centerYAnchor),
            rightDivider.heightAnchor.constraint(equalToConstant: 1),
            rightDivider.trailingAnchor.constraint(equalTo: orContainerView.trailingAnchor),
            
            // Social stack view (vertical now, so remove height constraint)
            socialStackView.topAnchor.constraint(equalTo: orContainerView.bottomAnchor, constant: Constants.Spacing.large),
            socialStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            socialStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            socialStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
    }
    
    private func setupTextFieldDelegates() {
        [emailTextField, passwordTextField, confirmPasswordTextField, zipcodeTextField, referralCodeTextField].forEach {
            $0.delegate = self
        }
    }
    
    private func setupActions() {
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        appleSignInButton.addTarget(self, action: #selector(appleSignInButtonTapped), for: .touchUpInside)
        googleSignInButton.addTarget(self, action: #selector(googleSignInButtonTapped), for: .touchUpInside)
        facebookSignInButton.addTarget(self, action: #selector(facebookSignInButtonTapped), for: .touchUpInside)
        togglePasswordButton.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        toggleConfirmPasswordButton.addTarget(self, action: #selector(toggleConfirmPasswordVisibility), for: .touchUpInside)
        
        // Keyboard handling
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Actions
    @objc private func registerButtonTapped() {
        guard let email = emailTextField.text, !email.isEmpty, isValidEmail(email) else {
            showError("Please enter a valid email address")
            return
        }
        
        guard let password = passwordTextField.text, !password.isEmpty, password.count >= 6 else {
            showError("Password must be at least 6 characters")
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
        
        // Get referral code if provided
        let referralCode = referralCodeTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Save referral code if provided (to apply after registration)
        if let code = referralCode, !code.isEmpty {
            ReferralService.shared.savePendingReferralCode(code)
        }
        
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
                    print("Successfully registered user: \(user.displayName)")
                    
                    // Apply referral code if we have one
                    if let _ = referralCode, !referralCode!.isEmpty {
                        ReferralService.shared.applyPendingReferralCodeIfNeeded { success in
                            if success {
                                print("Successfully applied referral code")
                            }
                        }
                    }
                    
                    // Don't show email verification popup - let auth state change take effect
                    // This allows the user to be logged in and see the onboarding with suggested users
                    // Email verification can be handled later in the app
                    // self?.showEmailVerificationMessage(email: email)
                    
                case .failure(let error):
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func appleSignInButtonTapped() {
        handleSocialAuth {
            SocialAuthService.shared.signInWithApple(from: self, completion: $0)
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
    
    // MARK: - Helper Methods
    private func handleSocialAuth(_ authMethod: @escaping (@escaping (Result<User, Error>) -> Void) -> Void) {
        isRegistering = true
        
        authMethod { [weak self] result in
            DispatchQueue.main.async {
                self?.isRegistering = false
                
                switch result {
                case .success(let user):
                    print("Successfully registered with social auth: \(user.displayName)")
                    self?.showSuccessMessage()
                case .failure(let error):
                    // Check if it's a private relay error
                    if let authError = error as? AuthError, authError == .privateRelayNotAllowed {
                        self?.showPrivateRelayGuidance()
                    } else {
                        self?.showError(error)
                    }
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
    
    private func showSuccessMessage() {
        AlertPresenter.showSuccess(
            title: "Registration Successful",
            message: "Welcome to Circles! You can now log in with your account.",
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
    
    private func findFirstResponder() -> UIView? {
        let responders: [UIView] = [emailTextField, passwordTextField, confirmPasswordTextField, zipcodeTextField, referralCodeTextField]
        return responders.first { $0.isFirstResponder }
    }
    
    // MARK: - Private Relay Guidance
    private func showPrivateRelayGuidance() {
        let alert = UIAlertController(
            title: "Private Relay Not Allowed",
            message: "To create an account with Circles, please sign in with Apple again and choose 'Share My Email' instead of 'Hide My Email'. This ensures you can access your account from all devices.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.appleSignInButtonTapped()
        })
        
        alert.addAction(UIAlertAction(title: "Use Email Instead", style: .default) { [weak self] _ in
            // Focus on email field for manual registration
            self?.emailTextField.becomeFirstResponder()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    // MARK: - Keyboard Handling
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        
        // Scroll to active field if hidden
        if let activeField = findFirstResponder(),
           let activeFieldFrame = activeField.superview?.convert(activeField.frame, to: scrollView) {
            var aRect = view.frame
            aRect.size.height -= keyboardSize.height
            if !aRect.contains(activeFieldFrame.origin) {
                scrollView.scrollRectToVisible(activeFieldFrame, animated: true)
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
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
            zipcodeTextField.becomeFirstResponder()
        case zipcodeTextField:
            referralCodeTextField.becomeFirstResponder()
        case referralCodeTextField:
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
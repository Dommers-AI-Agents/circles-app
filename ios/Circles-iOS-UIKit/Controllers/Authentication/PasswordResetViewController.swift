import UIKit

class PasswordResetViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Reset Password"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your email address and we'll send you a link to reset your password."
        label.font = UIFont.systemFont(ofSize: 16)
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
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var sendResetButton = UIButton.primaryButton(title: "Send Reset Email")
    
    private lazy var backToLoginButton = UIButton.secondaryButton(title: "Back to Login")
    
    private let successMessageView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        view.layer.cornerRadius = 8
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let successIconLabel: UILabel = {
        let label = UILabel()
        label.text = "✓"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .systemGreen
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let successTextLabel: UILabel = {
        let label = UILabel()
        label.text = "Password reset email sent! Check your inbox."
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .systemGreen
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Properties
    private var isSendingReset = false {
        didSet {
            sendResetButton.isEnabled = !isSendingReset
            emailTextField.isEnabled = !isSendingReset
            
            if isSendingReset {
                sendResetButton.setLoading(true)
            } else {
                sendResetButton.setLoading(false)
                sendResetButton.setTitle("Send Reset Email", for: .normal)
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
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Setup success message view
        successMessageView.addSubview(successIconLabel)
        successMessageView.addSubview(successTextLabel)
        
        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(emailTextField)
        view.addSubview(sendResetButton)
        view.addSubview(backToLoginButton)
        view.addSubview(successMessageView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            successMessageView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 24),
            successMessageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            successMessageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            successMessageView.heightAnchor.constraint(equalToConstant: 60),
            
            successIconLabel.leadingAnchor.constraint(equalTo: successMessageView.leadingAnchor, constant: 16),
            successIconLabel.centerYAnchor.constraint(equalTo: successMessageView.centerYAnchor),
            successIconLabel.widthAnchor.constraint(equalToConstant: 30),
            
            successTextLabel.leadingAnchor.constraint(equalTo: successIconLabel.trailingAnchor, constant: 12),
            successTextLabel.trailingAnchor.constraint(equalTo: successMessageView.trailingAnchor, constant: -16),
            successTextLabel.centerYAnchor.constraint(equalTo: successMessageView.centerYAnchor),
            
            emailTextField.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 40),
            emailTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emailTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            emailTextField.heightAnchor.constraint(equalToConstant: 50),
            
            sendResetButton.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 24),
            sendResetButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            sendResetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            backToLoginButton.topAnchor.constraint(equalTo: sendResetButton.bottomAnchor, constant: 16),
            backToLoginButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            backToLoginButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        
        // Setup text field delegate
        emailTextField.delegate = self
    }
    
    private func setupActions() {
        sendResetButton.addTarget(self, action: #selector(sendResetButtonTapped), for: .touchUpInside)
        backToLoginButton.addTarget(self, action: #selector(backToLoginTapped), for: .touchUpInside)
        
        // Add tap gesture to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Actions
    @objc private func sendResetButtonTapped() {
        guard let email = emailTextField.text, !email.isEmpty else {
            showError("Please enter your email address")
            return
        }
        
        // Validate email format
        if !isValidEmail(email) {
            showError("Please enter a valid email address")
            return
        }
        
        isSendingReset = true
        successMessageView.isHidden = true
        
        // Send the branded reset email via our backend (own SMTP domain for
        // deliverability) instead of the Firebase default sender
        AuthService.shared.requestPasswordReset(email: email) { [weak self] result in
            DispatchQueue.main.async {
                self?.isSendingReset = false

                switch result {
                case .success:
                    self?.showSuccessMessage()
                    self?.emailTextField.text = ""
                    self?.emailTextField.resignFirstResponder()
                case .failure(let error):
                    self?.showError("Failed to send reset email: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func backToLoginTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Helper Methods
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func showSuccessMessage() {
        successMessageView.alpha = 0
        successMessageView.isHidden = false
        
        UIView.animate(withDuration: 0.3) {
            self.successMessageView.alpha = 1
        }
        
        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UIView.animate(withDuration: 0.3) {
                self.successMessageView.alpha = 0
            } completion: { _ in
                self.successMessageView.isHidden = true
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension PasswordResetViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailTextField {
            sendResetButtonTapped()
        }
        return true
    }
}
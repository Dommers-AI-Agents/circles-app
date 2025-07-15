import UIKit

class ChangePasswordViewController: BaseViewController {
    
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
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter your current password and choose a new password"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let currentPasswordLabel: UILabel = {
        let label = UILabel()
        label.text = "Current Password"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let currentPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter current password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let newPasswordLabel: UILabel = {
        let label = UILabel()
        label.text = "New Password"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let newPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter new password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let confirmPasswordLabel: UILabel = {
        let label = UILabel()
        label.text = "Confirm New Password"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Confirm new password"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let passwordRequirementsLabel: UILabel = {
        let label = UILabel()
        label.text = "Password must be at least 8 characters long"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var changePasswordButton = UIButton.primaryButton(title: "Change Password")
    
    private lazy var toggleCurrentPasswordButton = UIButton.iconButton(systemName: "eye.slash.fill")
    
    private lazy var toggleNewPasswordButton = UIButton.iconButton(systemName: "eye.slash.fill")
    
    private lazy var toggleConfirmPasswordButton = UIButton.iconButton(systemName: "eye.slash.fill")
    
    // MARK: - Properties
    private var isLoading = false
    
    // MARK: - Lifecycle
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var enablesPullToRefresh: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        setupNavigationBar(title: "Change Password", largeTitleMode: .never)
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(instructionLabel)
        contentView.addSubview(currentPasswordLabel)
        contentView.addSubview(currentPasswordTextField)
        contentView.addSubview(toggleCurrentPasswordButton)
        contentView.addSubview(newPasswordLabel)
        contentView.addSubview(newPasswordTextField)
        contentView.addSubview(toggleNewPasswordButton)
        contentView.addSubview(confirmPasswordLabel)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(toggleConfirmPasswordButton)
        contentView.addSubview(passwordRequirementsLabel)
        contentView.addSubview(changePasswordButton)
        
        // Set up right views for text fields
        currentPasswordTextField.rightView = toggleCurrentPasswordButton
        currentPasswordTextField.rightViewMode = .always
        newPasswordTextField.rightView = toggleNewPasswordButton
        newPasswordTextField.rightViewMode = .always
        confirmPasswordTextField.rightView = toggleConfirmPasswordButton
        confirmPasswordTextField.rightViewMode = .always
        
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
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Current password label
            currentPasswordLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            currentPasswordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Current password text field
            currentPasswordTextField.topAnchor.constraint(equalTo: currentPasswordLabel.bottomAnchor, constant: Constants.Spacing.small),
            currentPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            currentPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            currentPasswordTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Toggle buttons
            toggleCurrentPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            toggleNewPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            toggleConfirmPasswordButton.widthAnchor.constraint(equalToConstant: 44),
            
            // New password label
            newPasswordLabel.topAnchor.constraint(equalTo: currentPasswordTextField.bottomAnchor, constant: Constants.Spacing.large),
            newPasswordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // New password text field
            newPasswordTextField.topAnchor.constraint(equalTo: newPasswordLabel.bottomAnchor, constant: Constants.Spacing.small),
            newPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            newPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            newPasswordTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Confirm password label
            confirmPasswordLabel.topAnchor.constraint(equalTo: newPasswordTextField.bottomAnchor, constant: Constants.Spacing.large),
            confirmPasswordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Confirm password text field
            confirmPasswordTextField.topAnchor.constraint(equalTo: confirmPasswordLabel.bottomAnchor, constant: Constants.Spacing.small),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Password requirements label
            passwordRequirementsLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: Constants.Spacing.small),
            passwordRequirementsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            passwordRequirementsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Change password button
            changePasswordButton.topAnchor.constraint(equalTo: passwordRequirementsLabel.bottomAnchor, constant: Constants.Spacing.xlarge),
            changePasswordButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            changePasswordButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            changePasswordButton.heightAnchor.constraint(equalToConstant: 50),
            changePasswordButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Add tap gesture to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupActions() {
        changePasswordButton.addTarget(self, action: #selector(changePasswordButtonTapped), for: .touchUpInside)
        toggleCurrentPasswordButton.addTarget(self, action: #selector(toggleCurrentPasswordVisibility), for: .touchUpInside)
        toggleNewPasswordButton.addTarget(self, action: #selector(toggleNewPasswordVisibility), for: .touchUpInside)
        toggleConfirmPasswordButton.addTarget(self, action: #selector(toggleConfirmPasswordVisibility), for: .touchUpInside)
    }
    
    // MARK: - Actions
    @objc private func changePasswordButtonTapped() {
        // Validate inputs
        guard let currentPassword = currentPasswordTextField.text, !currentPassword.isEmpty else {
            showError("Please enter your current password")
            return
        }
        
        guard let newPassword = newPasswordTextField.text, !newPassword.isEmpty else {
            showError("Please enter a new password")
            return
        }
        
        guard newPassword.count >= 8 else {
            showError("Password must be at least 8 characters long")
            return
        }
        
        guard let confirmPassword = confirmPasswordTextField.text, !confirmPassword.isEmpty else {
            showError("Please confirm your new password")
            return
        }
        
        guard newPassword == confirmPassword else {
            showError("New passwords do not match")
            return
        }
        
        guard currentPassword != newPassword else {
            showError("New password must be different from current password")
            return
        }
        
        // Change password
        changePassword(currentPassword: currentPassword, newPassword: newPassword)
    }
    
    @objc private func toggleCurrentPasswordVisibility() {
        currentPasswordTextField.isSecureTextEntry.toggle()
        let imageName = currentPasswordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        toggleCurrentPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func toggleNewPasswordVisibility() {
        newPasswordTextField.isSecureTextEntry.toggle()
        let imageName = newPasswordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        toggleNewPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func toggleConfirmPasswordVisibility() {
        confirmPasswordTextField.isSecureTextEntry.toggle()
        let imageName = confirmPasswordTextField.isSecureTextEntry ? "eye.slash.fill" : "eye.fill"
        toggleConfirmPasswordButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - API Call
    private func changePassword(currentPassword: String, newPassword: String) {
        guard !isLoading else { return }
        
        isLoading = true
        changePasswordButton.setLoading(true)
        
        UserService.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.changePasswordButton.setLoading(false)
                self?.changePasswordButton.setTitle("Change Password", for: .normal)
                
                switch result {
                case .success:
                    self?.presentAlert(title: "Success", message: "Your password has been changed successfully") {
                        self?.navigationController?.popViewController(animated: true)
                    }
                case .failure(let error):
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func presentAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        if title == "Success" {
            AlertPresenter.showSuccess(title: title, message: message, from: self, completion: completion)
        } else {
            AlertPresenter.showError(title: title, message: message, from: self, completion: completion)
        }
    }
}
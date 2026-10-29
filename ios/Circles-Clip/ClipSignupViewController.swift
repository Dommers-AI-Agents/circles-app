import UIKit

// Email/password signup form. Client-side validation mirrors the backend rules
// in middleware/validation.js: password ≥8 chars with upper+lower+digit,
// display name 2–50 chars.
final class ClipSignupViewController: UIViewController {

    private let code: String?
    private let preview: VenuePreview

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let nameField = UITextField()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let errorLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let submitSpinner = UIActivityIndicatorView(style: .medium)

    init(code: String?, preview: VenuePreview) {
        self.code = code
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(false, animated: false)
        title = "Sign up"
        setupUI()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let headerLabel = UILabel()
        headerLabel.text = preview.isGeneric
            ? "Join FavCircles"
            : "Get \(preview.signupBonusPoints) points at \(preview.venueName)"
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.numberOfLines = 0

        configureField(nameField, placeholder: "Your name", contentType: .name)
        nameField.autocapitalizationType = .words

        configureField(emailField, placeholder: "Email", contentType: .emailAddress)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no

        configureField(passwordField, placeholder: "Password (8+ chars, Aa1)", contentType: .newPassword)
        passwordField.isSecureTextEntry = true

        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        submitButton.setTitle("Create account", for: .normal)
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        submitButton.backgroundColor = ClipTheme.brandBlue
        submitButton.layer.cornerRadius = 8
        submitButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        submitSpinner.hidesWhenStopped = true
        submitSpinner.color = .white
        submitSpinner.translatesAutoresizingMaskIntoConstraints = false
        submitButton.addSubview(submitSpinner)

        [headerLabel, nameField, emailField, passwordField, errorLabel, submitButton].forEach {
            stack.addArrangedSubview($0)
        }
        stack.setCustomSpacing(24, after: headerLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            submitSpinner.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            submitSpinner.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor, constant: -16)
        ])
    }

    private func configureField(_ field: UITextField, placeholder: String, contentType: UITextContentType) {
        field.placeholder = placeholder
        field.textContentType = contentType
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 17)
        field.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    @objc private func submitTapped() {
        view.endEditing(true)
        errorLabel.isHidden = true

        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.text ?? ""

        if let validationError = Self.validate(name: name, email: email, password: password) {
            showError(validationError)
            return
        }

        setSubmitting(true)
        Task { @MainActor in
            do {
                let response = try await ClipAPIClient.shared.register(
                    email: email, password: password, displayName: name, stickerCode: code
                )
                self.finish(response: response)
            } catch {
                self.setSubmitting(false)
                self.showError(error.localizedDescription)
            }
        }
    }

    private func finish(response: ClipAuthResponse) {
        guard let offerVC = navigationController?.viewControllers.first as? ClipOfferViewController else { return }
        offerVC.advanceToSuccess(response: response, provider: "email")
    }

    static func validate(name: String, email: String, password: String) -> String? {
        if name.count < 2 || name.count > 50 {
            return "Please enter your name (2–50 characters)."
        }
        if email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil {
            return "Please enter a valid email address."
        }
        if password.count < 8
            || password.range(of: "[A-Z]", options: .regularExpression) == nil
            || password.range(of: "[a-z]", options: .regularExpression) == nil
            || password.range(of: "\\d", options: .regularExpression) == nil {
            return "Password needs 8+ characters with an uppercase letter, a lowercase letter, and a number."
        }
        return nil
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    private func setSubmitting(_ submitting: Bool) {
        submitButton.isEnabled = !submitting
        submitButton.alpha = submitting ? 0.6 : 1.0
        if submitting { submitSpinner.startAnimating() } else { submitSpinner.stopAnimating() }
    }
}

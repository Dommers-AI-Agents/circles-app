import UIKit
import PhotosUI

/// "What should friends call you?" (new-user audit, 2026-10-09): signup by
/// passkey, Apple or email never asked, so friends saw the start of an email
/// address ("jsmith42"). First step of the first-session chain, only when
/// the name still looks like that. A photo is optional.
final class NameOnboardingViewController: BaseViewController, UITextFieldDelegate, PHPickerViewControllerDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }

    var onCompletion: (() -> Void)?
    private var finished = false
    private var photoData: Data?

    /// The name is missing or is just the email's local part.
    static var isNeeded: Bool {
        guard let me = AuthService.shared.currentUser else { return false }
        let name = me.displayName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.contains("@") { return true }
        guard let local = me.email?.split(separator: "@").first.map(String.init) else { return false }
        return name.caseInsensitiveCompare(local) == .orderedSame
    }

    private let firstField = NameOnboardingViewController.field("First name")
    private let lastField = NameOnboardingViewController.field("Last name (optional)")
    private lazy var continueButton = UIButton.primaryButton(title: "Continue")
    private lazy var skipButton = UIButton.secondaryButton(title: "Skip for now")
    private let photoView: UIImageView = {
        let v = UIImageView(image: UIImage(systemName: "person.crop.circle.fill.badge.plus"))
        v.tintColor = Constants.Colors.primary
        v.contentMode = .scaleAspectFill
        v.layer.cornerRadius = 48
        v.clipsToBounds = true
        v.isUserInteractionEnabled = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private static func field(_ placeholder: String) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.font = .systemFont(ofSize: 18)
        f.borderStyle = .none
        f.backgroundColor = Constants.Colors.secondaryBackground
        f.layer.cornerRadius = 12
        f.autocapitalizationType = .words
        f.autocorrectionType = .no
        f.textContentType = .givenName
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        f.leftViewMode = .always
        f.translatesAutoresizingMaskIntoConstraints = false
        f.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return f
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        lastField.textContentType = .familyName

        let title = UILabel()
        title.text = "What should friends call you?"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0
        let subtitle = UILabel()
        subtitle.text = "It's how you show up on your map and when people find you."
        subtitle.font = .systemFont(ofSize: 16)
        subtitle.textColor = Constants.Colors.secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        let photoHint = UILabel()
        photoHint.text = "Add a photo (optional)"
        photoHint.font = .systemFont(ofSize: 13)
        photoHint.textColor = Constants.Colors.secondaryLabel
        photoHint.textAlignment = .center

        if let me = AuthService.shared.currentUser {
            let first = me.firstName ?? ""
            if !first.isEmpty, !first.contains("@") { firstField.text = first }
            lastField.text = me.lastName
        }
        firstField.delegate = self
        lastField.delegate = self
        firstField.returnKeyType = .next
        lastField.returnKeyType = .done
        firstField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        photoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickPhoto)))
        continueButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, subtitle, photoView, photoHint, firstField, lastField])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.setCustomSpacing(24, after: subtitle)
        stack.setCustomSpacing(6, after: photoView)
        stack.setCustomSpacing(22, after: photoHint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(continueButton)
        view.addSubview(skipButton)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            photoView.widthAnchor.constraint(equalToConstant: 96),
            photoView.heightAnchor.constraint(equalToConstant: 96),
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            continueButton.bottomAnchor.constraint(equalTo: skipButton.topAnchor, constant: -10),
            skipButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            skipButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
        // The photo is a fixed 96 pt circle in the middle of a fill stack
        photoView.setContentHuggingPriority(.required, for: .horizontal)
        stack.setCustomSpacing(6, after: photoView)
        if let photoIndex = stack.arrangedSubviews.firstIndex(of: photoView) {
            stack.removeArrangedSubview(photoView)
            let holder = UIView()
            holder.addSubview(photoView)
            NSLayoutConstraint.activate([
                photoView.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                photoView.topAnchor.constraint(equalTo: holder.topAnchor),
                photoView.bottomAnchor.constraint(equalTo: holder.bottomAnchor)
            ])
            stack.insertArrangedSubview(holder, at: photoIndex)
            stack.setCustomSpacing(6, after: holder)
        }
        textChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (firstField.text ?? "").isEmpty { firstField.becomeFirstResponder() }
    }

    @objc private func textChanged() {
        let ok = !(firstField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        continueButton.isEnabled = ok
        continueButton.alpha = ok ? 1 : 0.5
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === firstField { lastField.becomeFirstResponder() } else { saveTapped() }
        return true
    }

    @objc private func pickPhoto() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            let data = Self.profileJPEG(image)
            DispatchQueue.main.async {
                self?.photoView.image = image
                self?.photoData = data
            }
        }
    }

    /// Profile photos don't need to be big: 800 px on the long side.
    private static func profileJPEG(_ image: UIImage) -> Data? {
        let scale = min(1, 800 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    @objc private func saveTapped() {
        let first = (firstField.text ?? "").trimmingCharacters(in: .whitespaces)
        let last = (lastField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty else { return }
        view.endEditing(true)
        continueButton.isEnabled = false
        let loading = AlertPresenter.showLoading(from: self)
        UserService.shared.updateUserProfile(displayName: [first, last].filter { !$0.isEmpty }.joined(separator: " "),
                                             firstName: first, lastName: last, profilePicture: photoData) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let user):
                        AuthService.shared.updateCurrentUser(user)
                        AnalyticsService.shared.logEvent("onboarding_name_set", parameters: ["photo": self.photoData == nil ? "0" : "1"])
                        self.finish()
                    case .failure(let error):
                        self.continueButton.isEnabled = true
                        self.showError(error)
                    }
                }
            }
        }
    }

    @objc private func skipTapped() {
        AnalyticsService.shared.logEvent("onboarding_name_skipped", parameters: [:])
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onCompletion?()
        dismiss(animated: true)
    }
}

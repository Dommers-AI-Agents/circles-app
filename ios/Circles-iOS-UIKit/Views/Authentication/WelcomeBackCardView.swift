import UIKit

/// Top of the login screen after a logout (Wes, 2026-11-01): who last signed
/// in on this phone, how, and one button that does exactly that again.
/// "Not you?" hands the screen back to the normal sign-in options.
final class WelcomeBackCardView: UIView {
    var onContinue: (() -> Void)?
    var onNotYou: (() -> Void)?

    private let avatarView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
        view.tintColor = .tertiaryLabel
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 26
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(hint: LastSignInHint) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.secondaryBackground
        layer.cornerRadius = 16

        let title = UILabel()
        title.text = hint.firstName.map { "Welcome back, \($0)" } ?? "Welcome back"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0

        let detail = UILabel()
        detail.text = hint.lastTimeLine
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let words = UIStackView(arrangedSubviews: [title, detail])
        words.axis = .vertical
        words.spacing = 2
        let header = UIStackView(arrangedSubviews: [avatarView, words])
        header.spacing = 12
        header.alignment = .center

        let continueButton = Self.continueButton(for: hint.method)
        continueButton.accessibilityIdentifier = "welcomeBackContinue"
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        let notYou = UIButton.captionLinkButton()
        notYou.setTitle(hint.firstName.map { "Not \($0)? Use another account" } ?? "Use another account", for: .normal)
        notYou.contentHorizontalAlignment = .center
        notYou.accessibilityIdentifier = "welcomeBackNotYou"
        notYou.addTarget(self, action: #selector(notYouTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [header, continueButton, notYou])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(6, after: continueButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 52),
            avatarView.heightAnchor.constraint(equalToConstant: 52),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        if let photo = hint.photoURL {
            ImageService.shared.loadImage(from: photo) { [weak self] image in
                guard let image else { return }
                DispatchQueue.main.async { self?.avatarView.image = image }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The same button they'd have tapped last time, worded as "Continue"
    private static func continueButton(for method: LastSignInHint.Method) -> UIButton {
        switch method {
        case .google:
            let button = UIButton.googleSignInButton()
            button.setTitle("Continue with Google", for: .normal)
            return button
        case .apple:
            let button = UIButton.appleSignInButton()
            button.setTitle("Continue with Apple", for: .normal)
            return button
        case .passkey:
            let button = UIButton.primaryButton(title: "Sign in with Face ID")
            button.setImage(UIImage(systemName: "faceid"), for: .normal)
            button.tintColor = .white
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
            return button
        case .password, .other:
            return UIButton.primaryButton(title: "Continue")
        }
    }

    @objc private func continueTapped() { onContinue?() }
    @objc private func notYouTapped() { onNotYou?() }
}

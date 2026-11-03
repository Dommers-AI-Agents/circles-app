import UIKit

/// Before the first reward at a store, a terms-style checkbox (Wes,
/// 2026-11-02): the store may see the name, photo and email already on the
/// customer's FavCircles profile — nothing new to fill in. The card shows
/// exactly what's shared; "Claim reward" turns on once the box is ticked.
final class ShareWithStoreViewController: BaseViewController {

    private let venueName: String
    private let onAgree: () -> Void
    private var agreed = false

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 24
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let profileLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        return label
    }()

    private lazy var checkboxButton = UIButton.iconButton(systemName: "square", pointSize: 24)

    private let agreeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        return label
    }()

    private lazy var claimButton = UIButton.primaryButton(title: "Claim reward")
    private lazy var notNowButton = UIButton.secondaryButton(title: "Not now")

    init(venueName: String, onAgree: @escaping () -> Void) {
        self.venueName = venueName
        self.onAgree = onAgree
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = "Claim rewards by name"
        bodyLabel.text = "Rewards at \(venueName) are claimed by name, so the counter knows whose reward it is. You only do this once here."
        agreeLabel.text = "I agree to share my FavCircles name, photo and email with \(venueName)."

        if let me = AuthService.shared.currentUser {
            avatarView.setUserAvatar(for: me, diameter: 48)
            let text = NSMutableAttributedString(string: me.displayName, attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: Constants.Colors.label])
            if let email = me.email, !email.isEmpty {
                text.append(NSAttributedString(string: "\n\(email)", attributes: [
                    .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel]))
            }
            profileLabel.attributedText = text
        }

        let profileRow = UIStackView(arrangedSubviews: [avatarView, profileLabel])
        profileRow.spacing = 12
        profileRow.alignment = .center
        let profileCard = UIView()
        profileCard.backgroundColor = .secondarySystemBackground
        profileCard.layer.cornerRadius = 12
        profileRow.translatesAutoresizingMaskIntoConstraints = false
        profileCard.addSubview(profileRow)

        let checkRow = UIStackView(arrangedSubviews: [checkboxButton, agreeLabel])
        checkRow.spacing = 10
        checkRow.alignment = .top

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, profileCard, checkRow, claimButton, notNowButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(8, after: claimButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            profileRow.topAnchor.constraint(equalTo: profileCard.topAnchor, constant: 12),
            profileRow.bottomAnchor.constraint(equalTo: profileCard.bottomAnchor, constant: -12),
            profileRow.leadingAnchor.constraint(equalTo: profileCard.leadingAnchor, constant: 12),
            profileRow.trailingAnchor.constraint(lessThanOrEqualTo: profileCard.trailingAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),
            checkboxButton.widthAnchor.constraint(equalToConstant: 30)
        ])

        checkboxButton.accessibilityLabel = agreeLabel.text
        checkboxButton.addTarget(self, action: #selector(toggleAgree), for: .touchUpInside)
        agreeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleAgree)))
        claimButton.addTarget(self, action: #selector(claimTapped), for: .touchUpInside)
        notNowButton.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)
        updateAgree()
    }

    @objc private func toggleAgree() {
        agreed.toggle()
        updateAgree()
    }

    private func updateAgree() {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        checkboxButton.setImage(UIImage(systemName: agreed ? "checkmark.square.fill" : "square", withConfiguration: config), for: .normal)
        checkboxButton.accessibilityValue = agreed ? "Checked" : "Not checked"
        claimButton.isEnabled = agreed
        claimButton.alpha = agreed ? 1 : 0.4
    }

    @objc private func claimTapped() {
        guard agreed else { return }
        dismiss(animated: true) { [onAgree] in onAgree() }
    }

    @objc private func notNowTapped() {
        dismiss(animated: true)
    }
}

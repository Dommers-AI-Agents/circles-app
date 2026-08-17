import UIKit

/// Full-screen post-signup moment: "People are waiting for you."
///
/// New users get welcome connection requests from Wes and Brittany, but at
/// the 2026-08-15 launch night none of the four new signups ever found them
/// (they lived behind the Requests segment and the bell). This screen makes
/// accepting them a step of onboarding itself — faces, names, and one button.
///
/// Presented once per account (device flag keyed by user id), only while the
/// account is young and only when incoming pending requests actually exist —
/// veterans reinstalling never see it.
final class WelcomeConnectionsViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    private let requests: [Connection]
    private var isAccepting = false

    init(requests: [Connection]) {
        self.requests = requests
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presentation gate

    private static func seenKey(for userId: String) -> String { "welcomeConnectionsShown_\(userId)" }

    /// Presents over `presenter` when: incoming pending requests exist, the
    /// account is younger than 48h, and this account hasn't seen it before.
    @discardableResult
    static func presentIfNeeded(from presenter: UIViewController) -> Bool {
        guard let me = AuthService.shared.currentUser,
              let created = me.createdAt,
              Date().timeIntervalSince(created) < 48 * 3600,
              !UserDefaults.standard.bool(forKey: seenKey(for: me.id)) else { return false }

        let currentUserId = AuthService.shared.getUserId()
        let incoming = NetworkManager.shared.pendingConnections.filter {
            $0.status == .pending && $0.connectedUserId == currentUserId
        }
        guard !incoming.isEmpty else { return false }

        UserDefaults.standard.set(true, forKey: seenKey(for: me.id))
        presenter.present(WelcomeConnectionsViewController(requests: incoming), animated: true)
        return true
    }

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "People are waiting for you 🎉"
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Accept their requests and their favorite places show up on your map."
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let requestsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var acceptButton = UIButton.primaryButton(
        title: requests.count == 1 ? "Accept & Continue" : "Accept All & Continue")
    private lazy var laterButton = UIButton.secondaryButton(title: "Maybe Later")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(requestsStack)
        view.addSubview(acceptButton)
        view.addSubview(laterButton)

        for request in requests {
            requestsStack.addArrangedSubview(row(for: request))
        }

        acceptButton.addTarget(self, action: #selector(acceptAllTapped), for: .touchUpInside)
        laterButton.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            requestsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            requestsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            requestsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            laterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            laterButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            laterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            acceptButton.bottomAnchor.constraint(equalTo: laterButton.topAnchor, constant: -10),
            acceptButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            acceptButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func row(for request: Connection) -> UIView {
        let container = UIView()
        container.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14

        let avatar = UIImageView()
        avatar.layer.cornerRadius = 24
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.image = UIImage(systemName: "person.crop.circle.fill")?
            .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        if let user = request.connectedUser, let url = user.profilePicture, !url.isEmpty {
            ImageService.shared.loadProfileImage(for: user.id, from: url) { image in
                DispatchQueue.main.async { if let image = image { avatar.image = image } }
            }
        }

        let name = UILabel()
        name.text = request.connectedUser?.displayName ?? "A FavCircles member"
        name.font = .systemFont(ofSize: 17, weight: .semibold)

        let detail = UILabel()
        detail.text = "wants to connect with you"
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Constants.Colors.secondaryLabel
        detail.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [name, detail])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(avatar)
        container.addSubview(textStack)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            textStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: - Actions

    @objc private func acceptAllTapped() {
        guard !isAccepting else { return }
        isAccepting = true
        acceptButton.isEnabled = false

        let group = DispatchGroup()
        var acceptedCount = 0
        for request in requests {
            group.enter()
            NetworkManager.shared.acceptConnection(request.id) { result in
                if case .success = result { acceptedCount += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isAccepting = false
            NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
            self.dismiss(animated: true) {
                if acceptedCount > 0 {
                    // Confirmation toast rides on whatever is underneath
                    if let top = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first {
                        AlertPresenter.showSuccess(
                            acceptedCount == 1 ? "You're connected!" : "You're connected with \(acceptedCount) people!",
                            from: top
                        )
                    }
                }
            }
        }
    }

    @objc private func laterTapped() {
        dismiss(animated: true)
    }
}

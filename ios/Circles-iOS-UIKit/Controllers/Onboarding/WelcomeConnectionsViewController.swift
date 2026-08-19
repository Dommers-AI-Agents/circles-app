import UIKit

/// "Your first people" — the one onboarding moment for both relationship
/// kinds. Section 1: the welcome connection requests waiting for the new
/// user, each with an inline Accept button ON the row (a bottom "Accept All"
/// read as unrelated to the people above it — Wes, 2026-08-19). Section 2:
/// popular users worth following, each with an inline Follow button.
///
/// Launch-night 2026-08-15 taught us nobody finds requests behind the
/// Requests segment; this sheet is a step in the first-session chain
/// (SceneDelegate-owned) rather than a discoverable surface.
final class WelcomeConnectionsViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    private let requests: [Connection]
    private var recommendations: [User] = []
    private var followedIds = Set<String>()
    private var acceptedRequestIds = Set<String>()

    /// Fired exactly once when the sheet leaves the screen, however it left
    /// (Continue, swipe-down). The first-session chain continues from it.
    var onDismiss: (() -> Void)?
    private var didFireDismiss = false

    init(requests: [Connection]) {
        self.requests = requests
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presentation gate

    private static func seenKey(for userId: String) -> String { "welcomeConnectionsShown_\(userId)" }

    /// Presents over `presenter` when the account is young (<48h), this
    /// account hasn't seen it, and incoming welcome requests exist. Backend
    /// creates the requests synchronously at signup, so in the first-session
    /// chain (after connections load) they're reliably present; if backend
    /// onboarding failed, the zero-relationship overlay covers the gap later.
    @discardableResult
    static func presentIfNeeded(from presenter: UIViewController, onDismiss: (() -> Void)? = nil) -> Bool {
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
        let sheet = WelcomeConnectionsViewController(requests: incoming)
        sheet.onDismiss = onDismiss
        presenter.present(sheet, animated: true)
        return true
    }

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Your first people 🎉"
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Accept the requests waiting for you and follow a few locals — their favorite places fill your map."
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // Continue is the ONLY bottom action — accepting happens on each row
    private lazy var continueButton = UIButton.primaryButton(title: "Continue")

    private static func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background

        view.addSubview(scrollView)
        scrollView.addSubview(titleLabel)
        scrollView.addSubview(subtitleLabel)
        scrollView.addSubview(contentStack)
        view.addSubview(continueButton)

        if !requests.isEmpty {
            contentStack.addArrangedSubview(Self.sectionHeader("Waiting for you"))
            for request in requests {
                contentStack.addArrangedSubview(requestRow(for: request))
            }
        }

        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        let guide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -8),

            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -28),
            titleLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -56),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22),
            contentStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            contentStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),

            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        loadRecommendations()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didFireDismiss {
            didFireDismiss = true
            onDismiss?()
        }
    }

    // MARK: - Rows

    private func avatarView(for user: User?) -> UIImageView {
        let avatar = UIImageView()
        avatar.layer.cornerRadius = 22
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.image = UIImage(systemName: "person.crop.circle.fill")?
            .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        if let user = user, let url = user.profilePicture, !url.isEmpty {
            ImageService.shared.loadProfileImage(for: user.id, from: url) { image in
                DispatchQueue.main.async { if let image = image { avatar.image = image } }
            }
        }
        return avatar
    }

    private func personRow(user: User?, title: String, detail: String, accessory: UIView?) -> UIView {
        let container = UIView()
        container.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14

        let avatar = avatarView(for: user)

        let name = UILabel()
        name.text = title
        name.font = .systemFont(ofSize: 16, weight: .semibold)

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [name, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(avatar)
        container.addSubview(textStack)
        var constraints = [
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            avatar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            textStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ]
        if let accessory = accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(accessory)
            constraints += [
                accessory.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                accessory.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -8)
            ]
        } else {
            constraints.append(textStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func requestRow(for request: Connection) -> UIView {
        personRow(
            user: request.connectedUser,
            title: request.connectedUser?.displayName ?? "A FavCircles member",
            detail: "wants to connect with you",
            accessory: acceptButton(for: request)
        )
    }

    /// The Accept action lives ON the person's row — mirroring the Follow
    /// buttons below, so "who am I saying yes to" is never ambiguous
    private func acceptButton(for request: Connection) -> UIButton {
        let button = UIButton.smallActionButton(title: "Accept", style: .primary)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self = self, let button = button else { return }
            self.accept(request: request, button: button)
        }, for: .touchUpInside)
        return button
    }

    private func followButton(for user: User) -> UIButton {
        let button = UIButton.smallActionButton(title: "Follow", style: .primary)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self = self, let button = button else { return }
            self.follow(user: user, button: button)
        }, for: .touchUpInside)
        return button
    }

    // MARK: - Recommendations

    private func loadRecommendations() {
        APIService.shared.request(
            endpoint: "users/contacts/discover?type=popular&limit=10",
            method: .get
        ) { [weak self] (result: Result<DiscoveryUsersResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self, case .success(let response) = result else { return }
                // People already in section 1 don't repeat below it — and the
                // popular endpoint includes the caller, so never suggest
                // following yourself
                let requestSenderIds = Set(self.requests.map { $0.userId })
                let myId = AuthService.shared.getUserId()
                self.recommendations = response.users
                    .filter { !requestSenderIds.contains($0.id) }
                    .filter { user in
                        guard let me = myId else { return true }
                        return !IDNormalizer.isSameUser(me, user.id)
                    }
                    .prefix(4).map { $0 }
                guard !self.recommendations.isEmpty else { return }

                self.contentStack.addArrangedSubview(Self.sectionHeader("Popular on FavCircles"))
                for user in self.recommendations {
                    let places = user.placesCount ?? 0
                    self.contentStack.addArrangedSubview(self.personRow(
                        user: user,
                        title: user.displayName,
                        detail: places > 0 ? "\(places) favorite place\(places == 1 ? "" : "s") to explore" : "New explorer",
                        accessory: self.followButton(for: user)
                    ))
                }
            }
        }
    }

    // MARK: - Actions

    private struct FollowActionResponse: Decodable {
        let success: Bool
        let piggyBank: PiggyBankCredit?
    }

    private func follow(user: User, button: UIButton) {
        guard !followedIds.contains(user.id) else { return }
        button.isEnabled = false
        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post
        ) { [weak self] (result: Result<FollowActionResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.followedIds.insert(user.id)
                    button.setTitle("Following ✓", for: .normal)
                    PiggyBankDepositView.play(credit: response.piggyBank)
                case .failure:
                    button.isEnabled = true
                }
            }
        }
    }

    private func accept(request: Connection, button: UIButton) {
        guard !acceptedRequestIds.contains(request.id) else { return }
        button.isEnabled = false
        NetworkManager.shared.acceptConnectionWithCredit(request.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let (_, credit)):
                    self.acceptedRequestIds.insert(request.id)
                    button.setTitle("Connected ✓", for: .normal)
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
                    PiggyBankDepositView.play(credit: credit)
                case .failure:
                    button.isEnabled = true
                }
            }
        }
    }

    @objc private func continueTapped() {
        dismiss(animated: true)
    }
}

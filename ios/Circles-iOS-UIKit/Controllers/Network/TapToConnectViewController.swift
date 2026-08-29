import UIKit

/// "Stay in Touch" — hold two phones together, see each other's card, one
/// tap connects both accounts (backend autoAccept path; FavCoins credited
/// to both sides). Discovery via NearbyConnectService (MultipeerConnectivity);
/// the passive phone flips to Connected through the existing
/// "ConnectionsChanged" notification when the backend write lands.
final class TapToConnectViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    private let nearby = NearbyConnectService()
    private var peerCards: [String: PeerCardView] = [:]   // userId → card

    // MARK: UI

    private let headlineLabel: UILabel = {
        let label = UILabel()
        label.text = "Hold your phones together"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "When your friend opens this screen too,\nthey'll appear right here"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 54
        imageView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.2)
        imageView.image = UIImage(systemName: "person.crop.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        return imageView
    }()

    private let pulseLayerContainer = UIView()
    private let cardsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    private let qrFallbackButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Prefer a QR code? Show mine", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14)
        return button
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stay in Touch"
        view.backgroundColor = Constants.Colors.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))

        layoutUI()
        loadOwnAvatar()

        qrFallbackButton.addTarget(self, action: #selector(showQRTapped), for: .touchUpInside)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(connectionsChanged),
                                               name: NSNotification.Name("ConnectionsChanged"),
                                               object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPulse()
        nearby.delegate = self
        nearby.start()   // first call triggers the Local Network permission prompt
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nearby.stop()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func showQRTapped() {
        guard let user = AuthService.shared.currentUser else { return }
        let shareVC = ShareProfileViewController(user: user)
        shareVC.modalPresentationStyle = .overFullScreen
        shareVC.modalTransitionStyle = .crossDissolve
        present(shareVC, animated: true)
    }

    @objc private func connectionsChanged() {
        // The OTHER phone tapped first: our backend connection now exists —
        // flip the matching card without requiring a local tap.
        DispatchQueue.main.async {
            for (userId, card) in self.peerCards where !card.isConnected {
                let connected = NetworkManager.shared.connections.contains {
                    IDNormalizer.isSameUser($0.connectedUserId, userId) || IDNormalizer.isSameUser($0.userId, userId)
                }
                if connected {
                    card.showConnected()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func connect(to peer: NearbyConnectService.NearbyPeer, card: PeerCardView) {
        card.showConnecting()
        NetworkManager.shared.handleConnectionInvite(
            from: peer.userId,
            message: "Connected by holding phones together"
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    card.showConnected()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure(let error):
                    if case ConnectionInviteError.alreadyConnected = error {
                        card.showConnected()
                        return
                    }
                    if case ConnectionInviteError.requestPending = error {
                        // A request already exists between us (e.g. the
                        // welcome request every new user gets). You're
                        // standing together — complete it instead of erroring.
                        self.resolvePending(with: peer, card: card)
                        return
                    }
                    card.showRetry()
                    self.showError(error)
                }
            }
        }
    }

    /// A pending request already links us. Incoming → accept it right here
    /// (one tap finishes what they started). Outgoing → their tap on THEIR
    /// phone accepts it, so tell the user that.
    private func resolvePending(with peer: NearbyConnectService.NearbyPeer, card: PeerCardView) {
        guard let pending = NetworkManager.shared.pendingConnections.first(where: {
            IDNormalizer.isSameUser($0.userId, peer.userId) || IDNormalizer.isSameUser($0.connectedUserId, peer.userId)
        }) else {
            card.showRetry()
            return
        }

        let isIncoming = IDNormalizer.isSameUser(pending.userId, peer.userId)
        if isIncoming {
            NetworkManager.shared.acceptConnection(pending.id) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        card.showConnected()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    case .failure(let error):
                        card.showRetry()
                        self?.showError(error)
                    }
                }
            }
        } else {
            card.showWaiting()
        }
    }

    // MARK: Discovery UI

    private func addOrUpdateCard(for peer: NearbyConnectService.NearbyPeer) {
        if peerCards[peer.userId] != nil { return }

        let card = PeerCardView(name: peer.displayName)
        card.onTap = { [weak self, weak card] in
            guard let self = self, let card = card else { return }
            self.connect(to: peer, card: card)
        }
        peerCards[peer.userId] = card
        cardsStack.insertArrangedSubview(card, at: 0)
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 14)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.3) {
            card.alpha = 1
            card.transform = .identity
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        subtitleLabel.text = "Tap to stay in touch"

        // Fill in the avatar from the profile API
        UserService.shared.fetchUserProfile(userId: peer.userId) { result in
            DispatchQueue.main.async {
                if case .success(let user) = result {
                    card.update(name: user.displayName)
                    if let urlString = user.profilePicture {
                        ImageService.shared.loadImage(from: urlString) { image in
                            DispatchQueue.main.async { card.setAvatar(image) }
                        }
                    }
                    // A connection may already exist — reflect it immediately
                    let connected = NetworkManager.shared.connections.contains {
                        IDNormalizer.isSameUser($0.connectedUserId, peer.userId) || IDNormalizer.isSameUser($0.userId, peer.userId)
                    }
                    if connected { card.showConnected() }
                }
            }
        }
    }

    private func removeCard(for userId: String) {
        guard let card = peerCards[userId], !card.isConnected else { return }
        peerCards.removeValue(forKey: userId)
        UIView.animate(withDuration: 0.25, animations: {
            card.alpha = 0
        }) { _ in
            card.removeFromSuperview()
        }
        if peerCards.isEmpty {
            subtitleLabel.text = "When your friend opens this screen too,\nthey'll appear right here"
        }
    }

    // MARK: Layout + pulse

    private func layoutUI() {
        [pulseLayerContainer, avatarImageView, headlineLabel, subtitleLabel,
         cardsStack, qrFallbackButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 108),
            avatarImageView.heightAnchor.constraint(equalToConstant: 108),

            pulseLayerContainer.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            pulseLayerContainer.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            pulseLayerContainer.widthAnchor.constraint(equalToConstant: 108),
            pulseLayerContainer.heightAnchor.constraint(equalToConstant: 108),

            headlineLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 28),
            headlineLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            headlineLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            cardsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            cardsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            qrFallbackButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            qrFallbackButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func loadOwnAvatar() {
        guard let urlString = AuthService.shared.currentUser?.profilePicture else { return }
        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                if let image = image { self?.avatarImageView.image = image }
            }
        }
    }

    private func startPulse() {
        pulseLayerContainer.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for i in 0..<3 {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 108, height: 108)).cgPath
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = Constants.Colors.primary.withAlphaComponent(0.5).cgColor
            ring.lineWidth = 2
            pulseLayerContainer.layer.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 2.4
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0.0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 2.4
            group.repeatCount = .infinity
            group.timeOffset = Double(i) * 0.8
            ring.add(group, forKey: "pulse")
        }
    }
}

extension TapToConnectViewController: NearbyConnectServiceDelegate {
    func nearbyService(_ service: NearbyConnectService, found peer: NearbyConnectService.NearbyPeer) {
        addOrUpdateCard(for: peer)
    }

    func nearbyService(_ service: NearbyConnectService, lost peerUserId: String) {
        removeCard(for: peerUserId)
    }
}

// MARK: - Peer card

/// One discovered nearby user: avatar, name, and the connect button.
private final class PeerCardView: UIView {

    var onTap: (() -> Void)?
    private(set) var isConnected = false

    private let avatarView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 28
        imageView.image = UIImage(systemName: "person.crop.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var connectButton: UIButton = UIButton.smallActionButton(title: "Tap to stay in touch", style: .primary)

    init(name: String) {
        super.init(frame: .zero)
        nameLabel.text = name
        backgroundColor = Constants.Colors.secondaryBackground
        layer.cornerRadius = 16

        [avatarView, nameLabel, connectButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        connectButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: connectButton.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            connectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            connectButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func buttonTapped() { onTap?() }

    func update(name: String) { nameLabel.text = name }
    func setAvatar(_ image: UIImage?) { if let image = image { avatarView.image = image } }

    func showConnecting() {
        connectButton.setTitle("Connecting…", for: .normal)
        connectButton.isEnabled = false
    }

    func showConnected() {
        isConnected = true
        connectButton.setTitle("Connected ✓", for: .normal)
        connectButton.isEnabled = false
    }

    func showRetry() {
        connectButton.setTitle("Try again", for: .normal)
        connectButton.isEnabled = true
    }

    /// Our request is already waiting on their side — their tap completes it.
    func showWaiting() {
        connectButton.setTitle("Have them tap too", for: .normal)
        connectButton.isEnabled = false
    }
}

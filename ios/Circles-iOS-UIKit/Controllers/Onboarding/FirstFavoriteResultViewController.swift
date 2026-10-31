import UIKit

/// "Your place, your people" — right after a new user saves the one place
/// they love most (Wes, 2026-10-31). The place on a card, the store's
/// rewards when they're live, then the people who also love it to follow
/// (or people mapping their city when nobody has it yet), with any
/// connection requests waiting at the top. Replaces the generic
/// "Explore other people's maps" sheet on this path.
final class FirstFavoriteResultViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    var onContinue: (() -> Void)?

    private let place: Place
    private var followedIds = Set<String>()
    private var acceptedRequestIds = Set<String>()
    private var shownUserIds = Set<String>()
    private var followCount = 0

    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Requests, savers and the fallback land here as they load, in order
    private let peopleStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }()

    private lazy var continueButton: UIButton = {
        let button = UIButton.primaryButton(title: "Keep building my map")
        button.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.hidesBackButton = true

        let title = UILabel()
        title.text = FirstFavoriteCopy.savedTitle(placeName: place.name)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = Constants.Colors.label
        title.numberOfLines = 0

        let sub = UILabel()
        sub.text = "It's the first pin on your map, in Favorite Local Spots."
        sub.font = .systemFont(ofSize: 15)
        sub.textColor = Constants.Colors.secondaryLabel
        sub.numberOfLines = 0

        contentStack.addArrangedSubview(title)
        contentStack.addArrangedSubview(sub)
        contentStack.setCustomSpacing(18, after: sub)
        contentStack.addArrangedSubview(placeCard())
        contentStack.addArrangedSubview(peopleStack)
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews[2])

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(continueButton)
        let guide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -8),
            contentStack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
            contentStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            continueButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            continueButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        addPendingRequests()
        loadRewards()
        loadSavers()
    }

    // MARK: - The place

    private var rewardsLabel: UILabel?

    private func placeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = place.category.color.withAlphaComponent(0.12)
        card.layer.cornerRadius = 16

        let icon = UIImageView(image: UIImage(systemName: place.category.systemIconName))
        icon.tintColor = place.category.color
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)

        let name = UILabel()
        name.text = place.name
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.numberOfLines = 2
        let address = UILabel()
        address.text = place.address
        address.font = .systemFont(ofSize: 13)
        address.textColor = Constants.Colors.secondaryLabel
        address.numberOfLines = 2

        let rewards = UILabel()
        rewards.font = .systemFont(ofSize: 14, weight: .semibold)
        rewards.textColor = Constants.Colors.primary
        rewards.numberOfLines = 0
        rewards.isHidden = true
        rewardsLabel = rewards

        let text = UIStackView(arrangedSubviews: [name, address, rewards])
        text.axis = .vertical
        text.spacing = 3
        text.setCustomSpacing(8, after: address)

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    /// Only when the store's rewards are live for this person
    private func loadRewards() {
        RewardsService.shared.getVenueByPlace(placeId: place.id, googlePlaceId: place.googlePlaceId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let data) = result, data.venue != nil,
                      let line = FirstFavoriteCopy.rewardsLine(placeName: self.place.name,
                                                               rewardsLive: data.rewardsLive == true,
                                                               isOwner: data.isOwner == true) else { return }
                self.rewardsLabel?.text = "🎁 " + line
                UIView.animate(withDuration: 0.25) { self.rewardsLabel?.isHidden = false }
            }
        }
    }

    // MARK: - People

    private static func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }

    private static func sectionNote(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private var myId: String? { AuthService.shared.getUserId() }

    private func isMe(_ userId: String) -> Bool {
        guard let me = myId else { return false }
        return IDNormalizer.isSameUser(me, userId)
    }

    private func addPendingRequests() {
        let requests = NetworkManager.shared.pendingConnections.filter {
            $0.status == .pending && $0.connectedUserId == myId
        }
        guard !requests.isEmpty else { return }
        peopleStack.addArrangedSubview(Self.sectionHeader("Waiting for you"))
        for request in requests {
            shownUserIds.insert(request.userId)
            let button = UIButton.smallActionButton(title: "Accept", style: .primary)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                self.accept(request, button: button)
            }, for: .touchUpInside)
            peopleStack.addArrangedSubview(personRow(user: request.connectedUser,
                                                     title: request.connectedUser?.displayName ?? "A FavCircles member",
                                                     detail: "wants to connect with you", accessory: button))
        }
    }

    private func loadSavers() {
        PlaceService.shared.fetchPlaceSavers(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let savers = ((try? result.get())?.savers ?? []).filter { !self.isMe($0.id) && !self.shownUserIds.contains($0.id) }
                if savers.isEmpty {
                    self.loadFallbackPeople()
                    return
                }
                let total = max((try? result.get())?.totalCount ?? savers.count, savers.count)
                let header = FirstFavoriteCopy.saversLine(count: total, placeName: self.place.name) ?? ""
                self.peopleStack.addArrangedSubview(Self.sectionHeader(header))
                self.peopleStack.addArrangedSubview(Self.sectionNote("Follow them and the places they love show up on your map."))
                for user in savers.prefix(8) { self.addFollowRow(user, detail: self.mapDetail(user)) }
                AnalyticsService.shared.logEvent("first_favorite_savers_shown", parameters: ["count": total])
                // A short list gets company from the city's mappers
                if savers.count < 3 { self.loadFallbackPeople(limit: 4) }
            }
        }
    }

    private func loadFallbackPeople(limit: Int = 6) {
        APIService.shared.request(endpoint: "users/contacts/discover?type=popular&limit=12", method: .get) { [weak self] (result: Result<DiscoveryUsersResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self, case .success(let response) = result else { return }
                let following = Set(AuthService.shared.currentUser?.following ?? [])
                let people = response.users
                    .filter { !self.isMe($0.id) && !self.shownUserIds.contains($0.id) }
                    .filter { user in !following.contains { IDNormalizer.isSameUser($0, user.id) } }
                    .prefix(limit)
                guard !people.isEmpty else { return }
                let city = AuthService.shared.currentUser?.location?.split(separator: ",").first.map(String.init)
                self.peopleStack.addArrangedSubview(Self.sectionHeader(FirstFavoriteCopy.fallbackPeopleHeader(cityName: city)))
                for user in people { self.addFollowRow(user, detail: self.mapDetail(user)) }
            }
        }
    }

    private func mapDetail(_ user: User) -> String {
        let places = user.placesCount ?? 0
        return places > 0 ? "\(places) place\(places == 1 ? "" : "s") on their map" : "Just getting started"
    }

    private func addFollowRow(_ user: User, detail: String) {
        shownUserIds.insert(user.id)
        let following = user.isFollowing == true
            || (AuthService.shared.currentUser?.following ?? []).contains { IDNormalizer.isSameUser($0, user.id) }
        let button = UIButton.smallActionButton(title: following ? "Following ✓" : "Follow", style: .primary)
        button.isEnabled = !following
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }
            self.follow(user, button: button)
        }, for: .touchUpInside)
        peopleStack.addArrangedSubview(personRow(user: user, title: user.displayName, detail: detail, accessory: button))
    }

    private func personRow(user: User?, title: String, detail: String, accessory: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14

        let avatar = UIImageView(image: UIImage(systemName: "person.crop.circle.fill")?
            .withTintColor(Constants.Colors.primary, renderingMode: .alwaysOriginal))
        avatar.layer.cornerRadius = 22
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        if let user, let url = user.profilePicture, !url.isEmpty {
            ImageService.shared.loadProfileImage(for: user.id, from: url) { image in
                DispatchQueue.main.async { if let image { avatar.image = image } }
            }
        }
        let name = UILabel()
        name.text = title
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.numberOfLines = 2
        let text = UIStackView(arrangedSubviews: [name, detailLabel])
        text.axis = .vertical
        text.spacing = 2

        for v in [avatar, text, accessory] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),
            avatar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            avatar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            text.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            text.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -8),
            accessory.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            accessory.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    // MARK: - Actions

    private struct FollowActionResponse: Decodable {
        let success: Bool
        let piggyBank: PiggyBankCredit?
    }

    private func follow(_ user: User, button: UIButton) {
        guard !followedIds.contains(user.id) else { return }
        button.isEnabled = false
        APIService.shared.request(endpoint: "users/\(user.id)/follow", method: .post) { [weak self] (result: Result<FollowActionResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    AuthService.shared.recordFollowChange(userId: user.id, isFollowing: true)
                    self?.followedIds.insert(user.id)
                    self?.followCount += 1
                    button.setTitle("Following ✓", for: .normal)
                    PiggyBankDepositView.play(credit: response.piggyBank)
                case .failure(let error):
                    button.isEnabled = true
                    self?.showError(error)
                }
            }
        }
    }

    private func accept(_ request: Connection, button: UIButton) {
        guard !acceptedRequestIds.contains(request.id) else { return }
        button.isEnabled = false
        NetworkManager.shared.acceptConnectionWithCredit(request.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (_, credit)):
                    self?.acceptedRequestIds.insert(request.id)
                    button.setTitle("Connected ✓", for: .normal)
                    NotificationCenter.default.post(name: .refreshCircles, object: nil)
                    PiggyBankDepositView.play(credit: credit)
                case .failure(let error):
                    button.isEnabled = true
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func continueTapped() {
        AnalyticsService.shared.logEvent("first_favorite_followed", parameters: ["count": followCount])
        onContinue?()
    }
}

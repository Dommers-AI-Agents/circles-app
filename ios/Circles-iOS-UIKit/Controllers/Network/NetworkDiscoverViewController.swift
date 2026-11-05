import UIKit
import CoreLocation

/// My Network → Discover. A small network runs out of strangers fast, so this
/// leads with what your people are doing: places two or more of them love,
/// this month's board among them, then people you might know (one row) and
/// an invite. Cards appear as their data arrives; empty ones stay hidden.
final class NetworkDiscoverViewController: BaseViewController {

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let lovedCard = LovedPlacesCardView()
    private let boardCard = NetworkLeaderboardCardView()
    private let peopleCard = PeopleStripView()
    private let inviteCard = InviteCardView()

    private var loved: [NetworkDiscoverService.LovedPlace] = []
    private var month: MilestoneMonthViewController.Month?
    private var people: [User] = []

    private let locationManager = CLLocationManager()

    override var enablesPullToRefresh: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.refreshControl = refreshControl
        stack.axis = .vertical
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.sendSubviewToBack(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        [lovedCard, boardCard, peopleCard, inviteCard].forEach { stack.addArrangedSubview($0) }

        lovedCard.onSelect = { [weak self] place in self?.openPlace(place.globalPlaceId) }
        lovedCard.onSeeAll = { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(LovedPlacesListViewController(places: self.loved), animated: true)
        }
        boardCard.onTap = { [weak self] in self?.openMonth() }
        peopleCard.onSeeAll = { [weak self] in
            self?.navigationController?.pushViewController(DiscoveryListViewController(mode: .everyone), animated: true)
        }
        peopleCard.onFollow = { [weak self] user in self?.follow(user) }
        peopleCard.onConnect = { [weak self] user in self?.connect(user) }
        peopleCard.onDismiss = { [weak self] user in self?.dismissSuggestion(user) }
        peopleCard.onSelect = { [weak self] user in
            self?.navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
        }
        inviteCard.onInvite = { [weak self] in self?.invite() }
        // Last visit's Discover at once; loadData refreshes it (2026-11-05)
        loved = ScreenSnapshot.load([NetworkDiscoverService.LovedPlace].self, key: "discover.loved") ?? []
        month = ScreenSnapshot.load(MilestoneMonthViewController.Month.self, key: "discover.month")
        people = ScreenSnapshot.load([User].self, key: "discover.people") ?? []
        render()
        // Showing last visit's copy: refresh behind it without a spinner over
        // the content (the base started one for the first load)
        if !loved.isEmpty || month != nil || !people.isEmpty { hideLoadingState() }
    }

    override func loadData(completion: (() -> Void)? = nil) {
        let group = DispatchGroup()
        group.enter()
        NetworkDiscoverService.shared.lovedPlaces { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let places) = result {
                    self?.loved = places
                    ScreenSnapshot.save(places, key: "discover.loved")
                }
                self?.render()
                group.leave()
            }
        }
        group.enter()
        NetworkDiscoverService.shared.month { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let month) = result {
                    self?.month = month
                    ScreenSnapshot.save(month, key: "discover.month")
                }
                self?.render()
                group.leave()
            }
        }
        group.enter()
        NetworkDiscoverService.shared.people(location: currentLocation()) { [weak self] users in
            // An empty answer is kept only when there was nothing before:
            // a failed load mustn't wipe the people already showing
            if !users.isEmpty || (self?.people.isEmpty ?? true) {
                self?.people = users
                ScreenSnapshot.save(users, key: "discover.people")
            }
            self?.render()
            group.leave()
        }
        group.notify(queue: .main) { completion?() }
    }

    /// A fix we already have, without prompting — Near you just drops out without one
    private func currentLocation() -> CLLocation? {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return locationManager.location
        default: return nil
        }
    }

    private func render() {
        let cards = NetworkDiscoverLayout.cards(lovedPlaces: loved.count, boardRows: month?.board.count ?? 0, people: people.count)
        lovedCard.isHidden = !cards.contains(.lovedPlaces)
        boardCard.isHidden = !cards.contains(.leaderboard)
        peopleCard.isHidden = !cards.contains(.people)
        if !lovedCard.isHidden { lovedCard.configure(loved) }
        if let month, !boardCard.isHidden { boardCard.configure(month) }
        peopleCard.configure(people)
    }

    // MARK: - Actions

    private func openPlace(_ globalPlaceId: String) {
        let loading = AlertPresenter.showLoading(message: "Loading...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        self.navigationController?.pushViewController(PlaceDetailViewController(place: response.bestDetailPlace()), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func openMonth() {
        let milestone = PushMilestone(kind: "top_contributor", value: month?.count, position: month?.rank)
        present(UINavigationController(rootViewController: MilestoneMonthViewController(milestone: milestone)), animated: true)
    }

    private func follow(_ user: User) {
        setPerson(user.copy(isFollowing: true))
        APIService.shared.request(endpoint: "users/\(user.id)/follow", method: .post, body: [:]) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    AuthService.shared.recordFollowChange(userId: user.id, isFollowing: true)
                    PiggyBankDepositView.play(credit: response.piggyBank)
                case .failure(let error):
                    self?.setPerson(user.copy(isFollowing: false))
                    self?.showError(error)
                }
            }
        }
    }

    /// Connect — the "I know them" step for someone you already follow. The
    /// card shows Request Sent at once; a refused request puts Connect back.
    private func connect(_ user: User) {
        setPerson(user.copy(connectionStatus: "pending", isFollowing: true))
        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    NotificationCenter.default.post(name: .connectionRequestSent, object: nil)
                case .failure(let error):
                    self?.setPerson(user.copy(connectionStatus: user.connectionStatus ?? "none"))
                    self?.showError(FriendlyError.message(for: error))
                }
            }
        }
    }

    private func setPerson(_ user: User) {
        guard let index = people.firstIndex(where: { $0.id == user.id }) else { return }
        people[index] = user
        render()
    }

    /// Gone for good, like the old list's X
    private func dismissSuggestion(_ user: User) {
        people.removeAll { $0.id == user.id }
        render()
        APIService.shared.request(endpoint: "users/contacts/dismiss-suggestion", method: .post,
                                  body: ["userId": user.id]) { (_: Result<SimpleAPIResponse, APIError>) in }
    }

    private func invite() {
        if let code = ReferralService.shared.myReferralCode {
            ReferralService.shared.shareReferralLink(code: code, from: self)
            return
        }
        ReferralService.shared.generateReferralCode { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let code): ReferralService.shared.shareReferralLink(code: code, from: self)
                case .failure(let error): self.showError(error)
                }
            }
        }
    }
}

/// Every place two or more of your people saved: the carousel's cards in a
/// two-column grid (Wes, 2026-11-05: "an ugly list")
final class LovedPlacesListViewController: BaseViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let places: [NetworkDiscoverService.LovedPlace]
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 14
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.register(LovedPlaceCell.self, forCellWithReuseIdentifier: LovedPlaceCell.reuseId)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(places: [NetworkDiscoverService.LovedPlace]) {
        self.places = places
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Places your people love"
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { places.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LovedPlaceCell.reuseId, for: indexPath)
        (cell as? LovedPlaceCell)?.configure(places[indexPath.item])
        return cell
    }

    /// Two columns on a phone, more on wider screens; the carousel card's height
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let insets: CGFloat = 32, spacing: CGFloat = 12
        let width = collectionView.bounds.width - insets
        let columns = max(2, Int((width + spacing) / (196 + spacing)))
        let itemWidth = floor((width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return CGSize(width: itemWidth, height: 262)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.collectionView.collectionViewLayout.invalidateLayout() })
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let id = places[indexPath.item].globalPlaceId
        let loading = AlertPresenter.showLoading(message: "Loading...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: id) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    if case .success(let response) = result {
                        self.navigationController?.pushViewController(PlaceDetailViewController(place: response.bestDetailPlace()), animated: true)
                    } else if case .failure(let error) = result {
                        self.showError(error)
                    }
                }
            }
        }
    }
}

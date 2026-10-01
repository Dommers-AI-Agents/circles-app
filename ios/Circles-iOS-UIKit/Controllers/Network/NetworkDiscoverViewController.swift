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
        peopleCard.onDismiss = { [weak self] user in self?.dismissSuggestion(user) }
        peopleCard.onSelect = { [weak self] user in
            self?.navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
        }
        inviteCard.onInvite = { [weak self] in self?.invite() }
        render()
    }

    override func loadData(completion: (() -> Void)? = nil) {
        let group = DispatchGroup()
        group.enter()
        NetworkDiscoverService.shared.lovedPlaces { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let places) = result { self?.loved = places }
                self?.render()
                group.leave()
            }
        }
        group.enter()
        NetworkDiscoverService.shared.month { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let month) = result { self?.month = month }
                self?.render()
                group.leave()
            }
        }
        group.enter()
        NetworkDiscoverService.shared.people(location: currentLocation()) { [weak self] users in
            self?.people = users
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

/// Every place two or more of your people saved
final class LovedPlacesListViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {
    private let places: [NetworkDiscoverService.LovedPlace]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

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
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Loved")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { places.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Loved", for: indexPath)
        let place = places[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = place.name + (place.viewerSaved ? "  ✓" : "")
        config.secondaryText = NetworkDiscoverLayout.savedByLine(names: place.savers.map(\.displayName), total: place.saverCount)
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: "heart.fill")
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = places[indexPath.row].globalPlaceId
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

import UIKit

/// Super users: places saved without a Google or Apple Maps match wait here,
/// private, until approved (Wes, 2026-11-06: tapping the "Place to approve"
/// push did nothing). The same queue and decision as the admin dashboard's
/// Approve places tab. A push for one place opens with that place first.
final class PlaceApprovalsViewController: BaseViewController {

    struct PendingPlace: Codable, Equatable {
        let id: String
        let name: String?
        let address: String?
        let category: String?
        let pendingSince: String?
        let mapUrl: String?
        let saves: Int?
        let savedBy: [String]?
    }
    private struct ListResponse: Codable { let places: [PendingPlace] }
    private struct DecisionResponse: Codable { let approvalStatus: String; let restored: Int? }

    /// The place the push was about: listed first
    private let focusId: String?
    private var places: [PendingPlace] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No places waiting.\nPlaces saved without a Google or Apple Maps match show up here." }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        return table
    }()

    init(focusId: String? = nil) {
        self.focusId = focusId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Approve Places"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(endpoint: "admin/dashboard/app/place-approvals", method: .get, requiresAuth: true) {
            [weak self] (result: Result<ListResponse, APIError>) in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let list):
                    self.places = PlaceApprovalCopy.ordered(list.places, focusId: self.focusId)
                    self.tableView.reloadData()
                    self.places.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    // A failed refresh keeps what's showing
                    self.showError(error)
                }
            }
        }
    }

    private func act(on place: PendingPlace, sourceView: UIView) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            (title: "Approve", style: .default, handler: { [weak self] in self?.decide(place, approve: true) }),
            (title: "Reject", style: .destructive, handler: { [weak self] in self?.decide(place, approve: false) })
        ]
        if let mapUrl = place.mapUrl, let url = URL(string: mapUrl) {
            actions.insert((title: "See it on the map", style: .default, handler: { UIApplication.shared.open(url) }), at: 0)
        }
        AlertPresenter.showActionSheet(title: place.name, message: PlaceApprovalCopy.decisionHelp, actions: actions,
                                       from: self, sourceView: sourceView)
    }

    private func decide(_ place: PendingPlace, approve: Bool) {
        APIService.shared.request(endpoint: "admin/dashboard/app/place-approvals/\(place.id)", method: .post,
                                  body: ["decision": approve ? "approve" : "reject"], requiresAuth: true) {
            [weak self] (result: Result<DecisionResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let decision):
                    self.places.removeAll { $0.id == place.id }
                    self.tableView.reloadData()
                    if self.places.isEmpty { self.showEmptyState() }
                    self.showSuccess(PlaceApprovalCopy.done(name: place.name ?? "The place", approved: approve, restored: decision.restored ?? 0))
                case .failure(let error):
                    self.showError(error)
                    self.loadData()
                }
            }
        }
    }
}

extension PlaceApprovalsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { places.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath)
        let place = places[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = place.name ?? "Unnamed"
        config.secondaryText = PlaceApprovalCopy.detail(place)
        config.secondaryTextProperties.numberOfLines = 0
        config.secondaryTextProperties.color = .secondaryLabel
        if place.id == focusId { config.image = UIImage(systemName: "bell.fill") }
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard places.indices.contains(indexPath.row), let cell = tableView.cellForRow(at: indexPath) else { return }
        act(on: places[indexPath.row], sourceView: cell)
    }
}

/// The words on the Approve places screen. Pure.
enum PlaceApprovalCopy {
    static let decisionHelp = "Approve makes it a public place, and its saves go back to the privacy people chose. Reject keeps it private to the people who saved it."

    /// The pushed place first, the rest oldest first (as the server sends them)
    static func ordered(_ places: [PlaceApprovalsViewController.PendingPlace], focusId: String?) -> [PlaceApprovalsViewController.PendingPlace] {
        guard let focusId, let i = places.firstIndex(where: { $0.id == focusId }) else { return places }
        var out = places
        out.insert(out.remove(at: i), at: 0)
        return out
    }

    /// "10960 Winds Crossing Dr · Saved by Wes · 1 save · waiting since Nov 6"
    static func detail(_ place: PlaceApprovalsViewController.PendingPlace) -> String {
        var parts: [String] = []
        if let address = place.address, !address.isEmpty { parts.append(address) }
        if let names = place.savedBy, !names.isEmpty { parts.append("Saved by " + names.prefix(3).joined(separator: ", ")) }
        if let saves = place.saves { parts.append(saves == 1 ? "1 save" : "\(saves) saves") }
        if let since = RewardTicketCopy.date(place.pendingSince) {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            parts.append("waiting since " + f.string(from: since))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func done(name: String, approved: Bool, restored: Int) -> String {
        guard approved else { return "Rejected. \(name) stays private to the people who saved it." }
        return restored > 0 ? "\(name) is public now. \(restored) save\(restored == 1 ? "" : "s") went back to the privacy people chose."
                            : "\(name) is public now."
    }
}

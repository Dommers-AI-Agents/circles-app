import UIKit

/// Store-owner screen: lists the venues linked to this account and opens the
/// self-service management screen for each. Trimmed-down sibling of the
/// super-user VenueAdminViewController (no venue creation or access granting).
class OwnerVenuesViewController: BaseViewController {

    // MARK: - Properties

    private var venues: [AdminVenue] = []
    private var hasAutoPushed = false

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No venues are linked to your account yet.\nContact FavCircles to enroll your business."
    }

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        return table
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My Venues"
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OwnerVenueCell")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    // MARK: - BaseViewController

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getMyVenues { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let venues):
                    self.venues = venues
                    self.tableView.reloadData()
                    if venues.isEmpty {
                        self.showEmptyState()
                    } else {
                        self.hideEmptyState()
                        // Single venue: jump straight to managing it (once)
                        if venues.count == 1 && !self.hasAutoPushed {
                            self.hasAutoPushed = true
                            self.manage(venues[0], animated: false)
                        }
                    }
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func manage(_ venue: AdminVenue, animated: Bool = true) {
        let manageVC = VenueManageViewController(venue: venue)
        navigationController?.pushViewController(manageVC, animated: animated)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension OwnerVenuesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return venues.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OwnerVenueCell", for: indexPath)
        let venue = venues[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = venue.venueName

        let stats = venue.stats
        config.secondaryText = "Purchases \(stats?.visits ?? 0) · Redeemed \(stats?.redemptions ?? 0) · Saves \(stats?.saves ?? 0)"
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        config.image = UIImage(systemName: "storefront")
        config.imageProperties.tintColor = Constants.Colors.primary

        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        manage(venues[indexPath.row])
    }
}

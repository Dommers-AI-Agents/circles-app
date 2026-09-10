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
        "No venues are linked to your account yet.\nAdd & claim your business to get started."
    }

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        return table
    }()

    /// Shown with the empty state — owners whose business was never saved by
    /// any user can add + claim it from scratch
    private lazy var emptyClaimButton = UIButton.primaryButton(title: "Add & claim your business")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My Venues"
        view.backgroundColor = .systemBackground

        // Brand tools: the profile storefront card, and a virtual "online
        // store" venue for businesses with no physical location (never
        // appears on maps — Specials/profile/follows only)
        let storefrontButton = UIBarButtonItem(
            image: UIImage(systemName: "storefront"),
            style: .plain, target: self, action: #selector(editStorefrontTapped))
        storefrontButton.accessibilityLabel = "Edit brand storefront"
        let onlineStoreButton = UIBarButtonItem(
            image: UIImage(systemName: "globe.badge.chevron.backward"),
            style: .plain, target: self, action: #selector(createOnlineStoreTapped))
        onlineStoreButton.accessibilityLabel = "Create online store"
        let guideButton = UIBarButtonItem(
            image: UIImage(systemName: "book"),
            style: .plain, target: self, action: #selector(ownerGuideTapped))
        guideButton.accessibilityLabel = "Store owner guide"
        let claimButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain, target: self, action: #selector(claimBusinessTapped))
        claimButton.accessibilityLabel = "Add and claim your business"
        navigationItem.rightBarButtonItems = [claimButton, storefrontButton, onlineStoreButton, guideButton]

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

        emptyClaimButton.isHidden = true
        emptyClaimButton.addTarget(self, action: #selector(claimBusinessTapped), for: .touchUpInside)
        view.addSubview(emptyClaimButton)
        NSLayoutConstraint.activate([
            emptyClaimButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyClaimButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 90),
            emptyClaimButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyClaimButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
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
                        self.emptyClaimButton.isHidden = false
                    } else {
                        self.hideEmptyState()
                        self.emptyClaimButton.isHidden = true
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

    // MARK: - Add & claim

    @objc private func claimBusinessTapped() {
        navigationController?.pushViewController(ClaimBusinessViewController(), animated: true)
    }

    // MARK: - Brand tools

    @objc private func editStorefrontTapped() {
        // Prefill from the live storefront when one exists
        guard let userId = AuthService.shared.getUserId() else { return }
        RewardsService.shared.getStorefront(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let editor = StorefrontEditViewController()
                if case .success(let data) = result {
                    editor.initialStorefront = data.storefront
                    editor.initialFindUsAtCircleId = nil
                }
                self.navigationController?.pushViewController(editor, animated: true)
            }
        }
    }

    @objc private func createOnlineStoreTapped() {
        if let existing = venues.first(where: { $0.isVirtual == true }) {
            manage(existing)
            return
        }
        let alert = UIAlertController(
            title: "Create Online Store",
            message: "A store with no physical location — offers, announcements, and loyalty codes, discovered through Specials and your profile (never on the map).",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Store name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            RewardsService.shared.createVirtualVenue(name: name) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.hasAutoPushed = true // stay on the refreshed list
                        self?.loadData()
                        self?.showSuccess("Online store created")
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
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
        // Subscriptions are per-store — say which tier each venue is on
        let tier = (venue.ownerPremium == true) ? "Business ✓" : "Free plan"
        let kind = venue.isVirtual == true ? " · Online store" : ""
        config.secondaryText = "\(tier)\(kind) · Visits \(stats?.visits ?? 0) · Redeemed \(stats?.redemptions ?? 0) · Saves \(stats?.saves ?? 0) · Followers \(stats?.followers ?? 0)"
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        config.image = UIImage(systemName: venue.isVirtual == true ? "globe" : "storefront")
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

extension OwnerVenuesViewController {
    @objc func ownerGuideTapped() {
        guard let topic = HelpContentProvider.shared.topic(withId: "store-video-tutorial") else { return }
        navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
    }
}

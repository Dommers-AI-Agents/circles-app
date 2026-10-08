import UIKit

/// Super-user screen: venues enrolled in the sticker program, with their
/// per-sticker stats. Tapping a store opens its full admin page
/// (VenueAdminDetailViewController); from here you can also sign up a new
/// venue and grant super-user access to other users.
class VenueAdminViewController: BaseViewController {

    // MARK: - Properties

    private var venues: [AdminVenue] = []

    private lazy var claimsButton = UIBarButtonItem(
        image: UIImage(systemName: "tray.full"),
        style: .plain,
        target: self,
        action: #selector(claimsTapped)
    )

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No venues yet.\nTap + to sign up your first place." }

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
        title = "Sticker Venues"
        view.backgroundColor = .systemBackground

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addVenueTapped))
        let grantButton = UIBarButtonItem(image: UIImage(systemName: "person.badge.plus"), style: .plain, target: self, action: #selector(grantTapped))
        claimsButton.accessibilityLabel = "Ownership claims"
        let guideButton = UIBarButtonItem(
            image: UIImage(systemName: "book"),
            style: .plain, target: self, action: #selector(ownerGuideTapped))
        guideButton.accessibilityLabel = "Store owner guide"
        // Printed-postcard specials ("$1.99 today only")
        let specialsButton = UIBarButtonItem(
            image: UIImage(systemName: "tag"),
            style: .plain, target: self, action: #selector(postcardSpecialsTapped))
        specialsButton.accessibilityLabel = "Postcard specials"
        navigationItem.rightBarButtonItems = [addButton, grantButton, claimsButton, guideButton, specialsButton]

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "VenueCell")

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
        RewardsService.shared.listVenues { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                switch result {
                case .success(let venues):
                    self?.venues = venues
                    self?.tableView.reloadData()
                    if venues.isEmpty {
                        self?.showEmptyState()
                    } else {
                        self?.hideEmptyState()
                    }
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
        updateClaimsBadge()
    }

    /// Show the pending-claims count on the tray button so new claims are
    /// noticeable without opening the list
    private func updateClaimsBadge() {
        RewardsService.shared.listClaims(status: "pending") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, case .success(let claims) = result else { return }
                if claims.isEmpty {
                    self.claimsButton.image = UIImage(systemName: "tray.full")
                    self.claimsButton.title = nil
                } else {
                    self.claimsButton.image = nil
                    self.claimsButton.title = "Claims (\(claims.count))"
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func claimsTapped() {
        navigationController?.pushViewController(VenueClaimsViewController(), animated: true)
    }

    @objc private func addVenueTapped() {
        // Super-users land here instead of My Venues, so the brand tools
        // (online store, storefront editor) need a home on this screen too
        let sheet = UIAlertController(title: "Add", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "New Physical Venue", style: .default) { [weak self] _ in
            let createVC = CreateVenueViewController()
            createVC.onVenueCreated = { [weak self] in
                self?.loadData()
            }
            self?.navigationController?.pushViewController(createVC, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Create My Online Store", style: .default) { [weak self] _ in
            self?.createOnlineStoreTapped()
        })
        sheet.addAction(UIAlertAction(title: "Edit My Brand Storefront", style: .default) { [weak self] _ in
            self?.editStorefrontTapped()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true)
    }

    private func editStorefrontTapped() {
        guard let userId = AuthService.shared.getUserId() else { return }
        RewardsService.shared.getStorefront(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let editor = StorefrontEditViewController()
                if case .success(let data) = result {
                    editor.initialStorefront = data.storefront
                }
                self.navigationController?.pushViewController(editor, animated: true)
            }
        }
    }

    private func createOnlineStoreTapped() {
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

    @objc private func grantTapped() {
        AlertPresenter.showTextInput(
            title: "Manage Super Users",
            message: "Enter the email of the FavCircles account",
            placeholder: "email@example.com",
            keyboardType: .emailAddress,
            from: self
        ) { [weak self] email in
            guard let self = self,
                  let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else { return }

            AlertPresenter.showActionSheet(
                title: email,
                actions: [
                    (title: "Grant super-user access", style: .default, handler: {
                        self.updateSuperUser(email: email, grant: true)
                    }),
                    (title: "Revoke super-user access", style: .destructive, handler: {
                        self.updateSuperUser(email: email, grant: false)
                    })
                ],
                from: self
            )
        }
    }

    private func updateSuperUser(email: String, grant: Bool) {
        let loading = AlertPresenter.showLoading(message: grant ? "Granting..." : "Revoking...", from: self)
        RewardsService.shared.setSuperUser(email: email, isSuperUser: grant) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let message):
                        AlertPresenter.showSuccess(message, from: self)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension VenueAdminViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return venues.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VenueCell", for: indexPath)
        let venue = venues[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = venue.venueName

        let stats = venue.stats
        var prefix = venue.isVirtual == true ? "Online store · " : ""
        if venue.ownerUserId == nil { prefix += "No owner · " }
        config.secondaryText = "\(prefix)Scans \(stats?.scans ?? 0) · Signups \(stats?.signups ?? 0) · Saves \(stats?.saves ?? 0) · Visits \(stats?.visits ?? 0) · Redeemed \(stats?.redemptions ?? 0)"
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        config.image = UIImage(systemName: venue.isVirtual == true ? "globe" : "storefront")
        config.imageProperties.tintColor = Constants.Colors.primary

        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    @objc private func postcardSpecialsTapped() {
        navigationController?.pushViewController(PostcardSpecialsViewController(), animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let detailVC = VenueAdminDetailViewController(venue: venues[indexPath.row])
        detailVC.onVenueChanged = { [weak self] in
            self?.loadData()
        }
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension VenueAdminViewController {
    @objc func ownerGuideTapped() {
        guard let topic = HelpContentProvider.shared.topic(withId: "store-video-tutorial") else { return }
        navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
    }
}

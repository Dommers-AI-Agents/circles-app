import UIKit

/// Super-user screen: venues enrolled in the sticker program, with their
/// per-sticker stats. Tapping a store opens its full admin page
/// (VenueAdminDetailViewController); from here you can also sign up a new
/// venue and grant super-user access to other users. The QR button picks
/// stores for one sheet of window-code stickers (StoreStickerSheet).
class VenueAdminViewController: BaseViewController {

    // MARK: - Properties

    private var venues: [AdminVenue] = []
    /// Stores picked for the sticker sheet, in the order tapped
    private var stickerPicks: [String] = []
    /// The bar's usual buttons, put back when picking ends
    private var normalRightItems: [UIBarButtonItem] = []

    private lazy var stickersButton: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "qrcode"), style: .plain, target: self, action: #selector(stickersTapped))
        item.accessibilityLabel = "Print window stickers for several stores"
        return item
    }()
    private lazy var printStickersButton = UIBarButtonItem(title: "Print", style: .done, target: self, action: #selector(printStickersTapped))
    private lazy var cancelStickersButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(endStickerPicking))

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
        normalRightItems = [addButton, grantButton, claimsButton, guideButton, specialsButton]
        navigationItem.rightBarButtonItems = normalRightItems
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = stickersButton
        tableView.allowsMultipleSelectionDuringEditing = true

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

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        // Online stores have no window to stick a code on
        if tableView.isEditing, venues[indexPath.row].isVirtual == true { return nil }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard tableView.isEditing else { return }
        stickerPicks.removeAll { $0 == venues[indexPath.row].venueId }
        updateStickerPickTitle()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            stickerPicks = StoreStickerSheet.toggled(stickerPicks, venues[indexPath.row].venueId)
            updateStickerPickTitle()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let detailVC = VenueAdminDetailViewController(venue: venues[indexPath.row])
        detailVC.onVenueChanged = { [weak self] in
            self?.loadData()
        }
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Window stickers for several stores

extension VenueAdminViewController {
    @objc private func stickersTapped() {
        stickerPicks = []
        tableView.setEditing(true, animated: true)
        navigationItem.leftBarButtonItem = cancelStickersButton
        navigationItem.rightBarButtonItems = [printStickersButton]
        updateStickerPickTitle()
    }

    @objc private func endStickerPicking() {
        stickerPicks = []
        tableView.setEditing(false, animated: true)
        title = "Sticker Venues"
        navigationItem.leftBarButtonItem = stickersButton
        navigationItem.rightBarButtonItems = normalRightItems
    }

    private func updateStickerPickTitle() {
        let count = stickerPicks.count
        title = count == 0 ? "Pick Stores" : "\(count) Picked"
        printStickersButton.isEnabled = count > 0 && count <= StoreStickerSheet.maxStores
    }

    @objc private func printStickersTapped() {
        let count = stickerPicks.count
        AlertPresenter.showTextInput(
            title: "Start at sticker #",
            message: "\(count) \(count == 1 ? "sticker" : "stickers"), one per store, on Avery 22805. 1 is the top-left sticker; start later to skip ones already used.",
            initialText: "1",
            keyboardType: .numberPad,
            confirmTitle: "Print",
            from: self
        ) { [weak self] text in
            guard let self, let text else { return }
            guard let start = StoreStickerSheet.startPosition(from: text) else {
                self.showError("Pick a sticker from 1 to \(StoreStickerSheet.perSheet).")
                return
            }
            self.downloadStickers(StoreStickerSheet(venueIds: self.stickerPicks, startAt: start))
        }
    }

    private func downloadStickers(_ sheet: StoreStickerSheet) {
        let loading = AlertPresenter.showLoading(message: "Building your stickers…", from: self)
        RewardsService.shared.downloadStoreStickers(sheet) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .failure(let error):
                        self.showError(error)
                    case .success(let data):
                        self.sharePDF(data, fileName: sheet.fileName)
                    }
                }
            }
        }
    }

    /// A real file with a readable name, so Print and Save to Files show it
    private func sharePDF(_ data: Data, fileName: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showError(error)
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = printStickersButton
        present(activity, animated: true)
    }
}

extension VenueAdminViewController {
    @objc func ownerGuideTapped() {
        guard let topic = HelpContentProvider.shared.topic(withId: "store-video-tutorial") else { return }
        navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
    }
}

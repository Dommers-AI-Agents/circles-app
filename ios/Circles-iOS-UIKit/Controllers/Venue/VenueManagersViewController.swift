import UIKit

/// Team management for a store: the billing owner plus the managers they've
/// invited. Every manager gets the full day-to-day owner surface (dashboard,
/// offers, announcements, QR codes); the Business subscription and ownership
/// itself stay with the single owner account. Owners add managers by the
/// email on the manager's FavCircles account; managers can remove themselves.
class VenueManagersViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    private var owner: VenueManager?
    private var managers: [VenueManager] = []
    private var canManage = false
    private var maxManagers = 10

    /// Lets the manage hub refresh its "Managers" row count on pop
    var onManagersChanged: ((Int) -> Void)?

    override var enablesPullToRefresh: Bool { true }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Managers"
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ManagerCell")

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

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getVenueManagers(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    self.owner = data.owner
                    self.managers = data.managers
                    self.canManage = data.canManage ?? false
                    self.maxManagers = data.maxManagers ?? 10
                    self.onManagersChanged?(self.managers.count)
                    self.navigationItem.rightBarButtonItem = self.canManage
                        ? UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addManagerTapped))
                        : nil
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Add / remove

    @objc private func addManagerTapped() {
        guard managers.count < maxManagers else {
            showError("A store can have at most \(maxManagers) managers")
            return
        }
        AlertPresenter.showTextInput(
            title: "Add a Manager",
            message: "They get the full store dashboard for \(venueName) — offers, announcements, QR codes, and stats. Enter the email on their FavCircles account.",
            placeholder: "manager@example.com",
            keyboardType: .emailAddress,
            from: self
        ) { [weak self] email in
            guard let self = self,
                  let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else { return }
            RewardsService.shared.addVenueManager(venueId: self.venueId, email: email) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let managers):
                        self.applyManagers(managers)
                        self.showSuccess("Manager added")
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func removeManager(_ manager: VenueManager) {
        let isSelf = manager.userId == AuthService.shared.getUserId()
        showConfirmation(
            title: isSelf ? "Leave This Store?" : "Remove Manager?",
            message: isSelf
                ? "You'll lose access to the dashboard for \(venueName)."
                : "\(manager.displayName ?? manager.email ?? "This account") will no longer manage \(venueName).",
            confirmTitle: isSelf ? "Leave" : "Remove",
            isDestructive: true
        ) { [weak self] in
            guard let self = self else { return }
            RewardsService.shared.removeVenueManager(venueId: self.venueId, managerId: manager.userId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let managers):
                        self.applyManagers(managers)
                        if isSelf { self.navigationController?.popToRootViewController(animated: true) }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func applyManagers(_ managers: [VenueManager]) {
        self.managers = managers
        onManagersChanged?(managers.count)
        tableView.reloadData()
    }

    private func canRemove(_ manager: VenueManager) -> Bool {
        canManage || manager.userId == AuthService.shared.getUserId()
    }
}

// MARK: - Table

extension VenueManagersViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Owner" : "Managers"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        if !canManage {
            return "Only the store owner can add or remove managers. You can remove yourself by swiping your row."
        }
        return "Managers get every store tool. Billing and ownership stay with the owner's account."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : max(managers.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ManagerCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            config.text = owner?.displayName ?? owner?.email ?? "Store owner"
            config.secondaryText = owner?.email
            config.image = UIImage(systemName: "crown.fill")
            config.imageProperties.tintColor = .systemOrange
        } else if managers.isEmpty {
            config.text = canManage ? "No managers yet" : "No other managers"
            config.secondaryText = canManage ? "Tap + to invite someone you trust" : nil
            config.textProperties.color = .secondaryLabel
        } else {
            let manager = managers[indexPath.row]
            config.text = manager.displayName ?? manager.email ?? manager.userId
            config.secondaryText = manager.displayName != nil ? manager.email : nil
            config.image = UIImage(systemName: "person.crop.circle")
            config.imageProperties.tintColor = Constants.Colors.primary
        }

        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, indexPath.row < managers.count else { return nil }
        let manager = managers[indexPath.row]
        guard canRemove(manager) else { return nil }
        let isSelf = manager.userId == AuthService.shared.getUserId()
        let remove = UIContextualAction(style: .destructive, title: isSelf ? "Leave" : "Remove") { [weak self] _, _, done in
            self?.removeManager(manager)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

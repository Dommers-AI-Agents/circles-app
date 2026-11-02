import UIKit

/// Manage Store → Customers (Wes, 2026-11-02): everyone earning at the store,
/// latest visit first, with purchases scanned, rewards claimed and points.
/// Email shows for people who shared it when claiming a reward. Rewards run
/// on the honor system; this is where the team acts on what they see —
/// "Remove from rewards" sets the person's points here to 0 and stops them
/// earning, "Restore" undoes it.
final class VenueCustomersViewController: BaseViewController {

    private let venueId: String
    private let venueName: String
    private var customers: [VenueCustomer] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? {
        "No customers yet.\nPeople who scan your register code after buying something show up here."
    }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        return table
    }()

    init(venueId: String, venueName: String) {
        self.venueId = venueId
        self.venueName = venueName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Customers"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CustomerCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchVenueCustomers(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let customers):
                    self.customers = customers
                    self.tableView.reloadData()
                    customers.isEmpty ? self.showEmptyState() : self.hideEmptyState()
                case .failure(let error):
                    // A failed refresh keeps what's showing
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Actions

    private func showActions(for customer: VenueCustomer, from cell: UIView?) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        if let email = customer.email, let url = URL(string: "mailto:\(email)") {
            actions.append((title: "Email \(email)", style: .default, handler: { UIApplication.shared.open(url) }))
        }
        if customer.removed {
            actions.append((title: "Restore to your rewards", style: .default, handler: { [weak self] in
                self?.setRemoved(customer, remove: false)
            }))
        } else {
            actions.append((title: "Remove from rewards", style: .destructive, handler: { [weak self] in
                self?.confirmRemove(customer)
            }))
        }
        actions.append((title: "Cancel", style: .cancel, handler: {}))
        AlertPresenter.showActionSheet(title: customer.user.displayName, message: VenueCustomerCopy.detail(customer),
                                       actions: actions, from: self, sourceView: cell)
    }

    private func confirmRemove(_ customer: VenueCustomer) {
        showConfirmation(
            title: "Remove \(customer.user.displayName) from your rewards?",
            message: "Their \(customer.points) points at \(venueName) go to 0 and their scans stop earning here. They aren't told unless they try to scan or redeem. You can restore them later, points and all.",
            confirmTitle: "Remove",
            isDestructive: true
        ) { [weak self] in
            self?.setRemoved(customer, remove: true)
        }
    }

    private func setRemoved(_ customer: VenueCustomer, remove: Bool) {
        RewardsService.shared.setVenueCustomerRemoved(venueId: venueId, userId: customer.user.id, remove: remove) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.loadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

extension VenueCustomersViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { customers.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        customers.isEmpty ? nil : "Customers share their name, photo and email with you when they claim their first reward here. Tap someone to email them or take them off your rewards."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CustomerCell", for: indexPath)
        let customer = customers[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = customer.user.displayName
        config.secondaryText = VenueCustomerCopy.detail(customer)
        config.secondaryTextProperties.color = customer.removed ? .systemRed : .secondaryLabel
        config.image = UIImage(systemName: customer.removed ? "person.crop.circle.badge.xmark" : "person.crop.circle")
        config.imageProperties.tintColor = customer.removed ? .systemRed : Constants.Colors.primary
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showActions(for: customers[indexPath.row], from: tableView.cellForRow(at: indexPath))
    }
}

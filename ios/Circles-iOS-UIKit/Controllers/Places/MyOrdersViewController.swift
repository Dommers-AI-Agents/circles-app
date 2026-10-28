import UIKit

/// The customer's order-ahead orders (2026-10-28): the open ones first, then
/// what came before. Each row opens the order's status. Before this the
/// status was reachable only right after placing and from the store's push.
final class MyOrdersViewController: BaseViewController {

    override var enablesPullToRefresh: Bool { true }
    override var reloadsDataOnAppear: Bool { true }
    override var emptyStateMessage: String? { "No orders yet. Order ahead from a store's menu and it shows here." }

    private var open: [StoreOrder] = []
    private var past: [StoreOrder] = []

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "My Orders"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "order")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(ordersChanged), name: VenueOrdersViewController.ordersChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    @objc private func ordersChanged() { loadData() }

    override func loadData(completion: (() -> Void)? = nil) {
        OrderService.shared.mine { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let orders):
                    self.open = orders.filter { $0.isOpen }
                    self.past = orders.filter { !$0.isOpen }
                    self.tableView.reloadData()
                    if orders.isEmpty { self.showEmptyState() } else { self.hideEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func orders(in section: Int) -> [StoreOrder] { section == 0 ? open : past }
}

extension MyOrdersViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { orders(in: section).count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !orders(in: section).isEmpty else { return nil }
        return section == 0 ? "Open" : "Earlier"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "order", for: indexPath)
        let o = orders(in: indexPath.section)[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = o.venueName
        config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
        let when = OrderStatusViewController.timeText(o.createdAt) ?? ""
        config.secondaryText = "\(o.statusLine(readyTime: OrderStatusViewController.timeText(o.readyAt)))\n\(o.summary)\(when.isEmpty ? "" : "\n\(when)")"
        config.secondaryTextProperties.numberOfLines = 0
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.image = UIImage(systemName: o.isOpen ? "bag.fill" : "bag")
        config.imageProperties.tintColor = o.isOpen ? Constants.Colors.primary : .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let o = orders(in: indexPath.section)[indexPath.row]
        navigationController?.pushViewController(OrderStatusViewController(order: o), animated: true)
    }
}

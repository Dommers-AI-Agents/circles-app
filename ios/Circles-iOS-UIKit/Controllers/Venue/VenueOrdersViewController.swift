import UIKit

/// The store's order-ahead orders (Business, 2026-10-20): New (accept with a
/// ready time, or decline), Accepted (mark ready), Ready (picked up). Oldest
/// first, refreshed every 20 s and whenever an order push arrives. Paid at
/// the counter, so the estimate is a guide, not a charge.
final class VenueOrdersViewController: BaseViewController {

    override var enablesPullToRefresh: Bool { true }
    override var reloadsDataOnAppear: Bool { true }

    static let ordersChanged = Notification.Name("VenueOrdersChanged")

    private let venueId: String
    private var orders: [StoreOrder] = []
    private var poller: Timer?
    private var observer: NSObjectProtocol?

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        return table
    }()

    init(venueId: String) {
        self.venueId = venueId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Orders"
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "History", primaryAction: UIAction { [weak self] _ in self?.showHistory() })
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
        tableView.refreshControl = refreshControl
        observer = NotificationCenter.default.addObserver(forName: Self.ordersChanged, object: nil, queue: .main) { [weak self] _ in
            self?.loadData()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poller?.invalidate()
        poller = nil
    }

    override func loadData(completion: (() -> Void)? = nil) {
        OrderService.shared.storeOrders(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                switch result {
                case .success(let orders):
                    self.orders = orders
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t load orders.")
                }
                self.poller?.invalidate()
                self.poller = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                    if self?.view.window != nil { self?.loadData() }
                }
                completion?()
            }
        }
    }

    // New · Accepted · Ready
    private static let groups: [(status: String, title: String)] = [("placed", "New"), ("accepted", "Accepted"), ("ready", "Ready for pickup")]
    private func orders(in section: Int) -> [StoreOrder] { orders.filter { $0.status == Self.groups[section].status } }

    // MARK: - Actions

    private func actions(for order: StoreOrder, from view: UIView) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        // A web guest left a phone number; the counter may need to call about the order
        if let phone = order.customer?.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
            actions.append((title: "Call \(phone)", style: .default, handler: { UIApplication.shared.open(url) }))
        }
        switch order.status {
        case "placed":
            actions.append((title: "Accept\u{2026}", style: .default, handler: { [weak self] in self?.chooseReadyTime(order, from: view) }))
            actions.append((title: "Ready now", style: .default, handler: { [weak self] in self?.act(order, .ready) }))
            actions.append((title: "Decline\u{2026}", style: .destructive, handler: { [weak self] in self?.decline(order) }))
        case "accepted":
            actions.append((title: "Mark ready", style: .default, handler: { [weak self] in self?.act(order, .ready) }))
            actions.append((title: "Picked up", style: .default, handler: { [weak self] in self?.act(order, .picked_up) }))
            actions.append((title: "Cancel the order\u{2026}", style: .destructive, handler: { [weak self] in self?.decline(order) }))
        case "ready":
            actions.append((title: "Picked up", style: .default, handler: { [weak self] in self?.act(order, .picked_up) }))
        default:
            return
        }
        AlertPresenter.showActionSheet(title: "\(order.customerName)\u{2019}s order", message: order.summary, actions: actions, from: self, sourceView: view)
    }

    private func chooseReadyTime(_ order: StoreOrder, from view: UIView) {
        let minutes = [10, 15, 20, 30, 45, 60]
        AlertPresenter.showActionSheet(
            title: "Ready in\u{2026}", message: order.pickup.asap ? "They asked for as soon as possible." : "They asked for \(OrderStatusViewController.timeText(order.pickup.at) ?? "a set time").",
            actions: minutes.map { m in (title: "\(m) minutes", style: .default, handler: { [weak self] in self?.act(order, .accept, readyIn: m) }) },
            from: self, sourceView: view)
    }

    private func decline(_ order: StoreOrder) {
        AlertPresenter.showTextInput(title: "Tell \(order.customerName) why", message: "They\u{2019}re told right away.",
                                     placeholder: "Sold out of the special, closing early\u{2026}", confirmTitle: "Decline", from: self) { [weak self] reason in
            self?.act(order, .decline, reason: reason)
        }
    }

    private func act(_ order: StoreOrder, _ action: OrderService.StoreAction, readyIn: Int? = nil, reason: String? = nil) {
        OrderService.shared.act(venueId: venueId, orderId: order.orderId, action: action, readyInMinutes: readyIn, reason: reason) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.loadData()
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t update that order.")
                    self.loadData()
                }
            }
        }
    }

    private func showHistory() {
        OrderService.shared.storeOrders(venueId: venueId, history: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let done = ((try? result.get()) ?? []).filter { !$0.isOpen }.prefix(20)
                let text = done.isEmpty ? "No finished orders yet." : done.map { o in
                    "\(OrderStatusViewController.timeText(o.createdAt) ?? "") \u{00B7} \(o.customerName) \u{00B7} \(o.statusLabel)\n\(o.summary)"
                }.joined(separator: "\n\n")
                AlertPresenter.showInfo(title: "Recent orders", message: text, from: self)
            }
        }
    }
}

extension VenueOrdersViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Self.groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(section == 0 ? 1 : 0, orders(in: section).count)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let count = orders(in: section).count
        return section == 0 || count > 0 ? "\(Self.groups[section].title)\(count > 0 ? " (\(count))" : "")" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 && orders(in: 0).isEmpty == false ? "Answer within 30 minutes or the order expires and the customer is told." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "order", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        let list = orders(in: indexPath.section)
        guard indexPath.row < list.count else {
            config.text = "No new orders"
            config.secondaryText = "New orders show here, with a push and an email to you and your managers."
            config.textProperties.color = Constants.Colors.secondaryLabel
            config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
        let o = list[indexPath.row]
        let pickup = o.pickup.asap ? "ASAP" : "pickup \(OrderStatusViewController.timeText(o.pickup.at) ?? "")"
        let ready = o.status == "accepted" ? OrderStatusViewController.timeText(o.readyAt).map { " \u{00B7} ready by \($0)" } ?? "" : ""
        config.text = "\(o.test == true ? "TEST \u{00B7} " : "")\(o.isWeb ? "Web \u{00B7} " : "")\(o.customerName) \u{00B7} \(pickup)\(ready)"
        config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
        var detail = o.lines.map { line in "\(line.qty)\u{00D7} \(line.name)\(line.note.map { " (\($0))" } ?? "")" }.joined(separator: "\n")
        if let note = o.note { detail += "\nNote: \(note)" }
        if let est = OrderCart.estimateText(total: o.estimate, partial: o.estimateIsPartial) { detail += "\n\(est) at the counter" }
        config.secondaryText = detail
        config.secondaryTextProperties.numberOfLines = 0
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        cell.contentConfiguration = config
        cell.selectionStyle = .default
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let list = orders(in: indexPath.section)
        guard indexPath.row < list.count, let cell = tableView.cellForRow(at: indexPath) else { return }
        actions(for: list[indexPath.row], from: cell)
    }
}

/// Order ahead on/off, the usual prep time and a line for customers (Business)
final class VenueOrderingSettingsViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    var onSaved: ((StoreOrdering) -> Void)?

    private let venueId: String
    private var ordering: StoreOrdering
    private let hasMenu: Bool
    private let menu: StorefrontMenu?
    private let label: String
    private let venueName: String
    private lazy var tryButton = UIButton.secondaryButton(title: "Try it as a customer")
    private lazy var pageButton = UIButton.secondaryButton(title: "Your ordering page")
    private let page: StorefrontOrderingPage?
    private let enabledSwitch = UISwitch()
    private let leadStepper = UIStepper()
    private let leadLabel = UILabel()
    private lazy var noteField = VenueFormLayout.textField(placeholder: "Call if you\u{2019}re running late", text: ordering.note ?? "")
    private lazy var saveButton = UIButton.primaryButton(title: "Save")

    init(venueId: String, venueName: String, storefront: VenueStorefront?) {
        self.venueId = venueId
        self.venueName = venueName
        self.ordering = storefront?.ordering ?? StoreOrdering()
        self.menu = storefront?.menu
        self.label = storefront?.offeringsLabel ?? "Menu"
        self.hasMenu = !(storefront?.menu?.isEmpty ?? true)
        self.page = storefront?.orderingPage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Online ordering"
        view.backgroundColor = Constants.Colors.background
        let stack = VenueFormLayout.install(in: view)
        stack.addArrangedSubview(VenueFormLayout.hintLabel(
            "Customers order from your full menu in the app and pick up at the counter. They pay you there, as usual: FavCircles takes no cut and handles no payments."))
        enabledSwitch.isOn = ordering.enabled
        enabledSwitch.isEnabled = hasMenu || ordering.enabled
        stack.addArrangedSubview(VenueFormLayout.toggleRow("Take orders in the app", enabledSwitch))
        if !hasMenu {
            stack.addArrangedSubview(VenueFormLayout.hintLabel("Add your full menu first (Full menu, in your store\u{2019}s page section); customers order from it."))
        }
        leadStepper.minimumValue = 5
        leadStepper.maximumValue = 120
        leadStepper.stepValue = 5
        leadStepper.value = Double(ordering.leadMinutes)
        leadStepper.addTarget(self, action: #selector(leadChanged), for: .valueChanged)
        leadLabel.font = .systemFont(ofSize: 16)
        let leadRow = UIStackView(arrangedSubviews: [leadLabel, UIView(), leadStepper])
        leadRow.alignment = .center
        stack.addArrangedSubview(VenueFormLayout.field("Usual prep time", leadRow,
            hint: VenueFormLayout.hintLabel("The earliest pickup customers can choose. You set the actual ready time when you accept each order.")))
        stack.addArrangedSubview(VenueFormLayout.field("A line for customers (optional)", noteField))
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)
        if hasMenu {
            stack.addArrangedSubview(VenueFormLayout.hintLabel(
                "See it the way customers do: order from your menu, then accept it in Orders. Test orders are marked TEST and nobody is charged."))
            tryButton.setImage(UIImage(systemName: "bag"), for: .normal)
            tryButton.addTarget(self, action: #selector(tryTapped), for: .touchUpInside)
            stack.addArrangedSubview(tryButton)
        }
        if page != nil {
            stack.addArrangedSubview(VenueFormLayout.hintLabel(
                "Customers without the app order from your web page, with the same menu and the same Orders list. Link it from your website or social pages."))
            pageButton.setImage(UIImage(systemName: "globe"), for: .normal)
            pageButton.addTarget(self, action: #selector(pageTapped), for: .touchUpInside)
            stack.addArrangedSubview(pageButton)
        }
        leadChanged()
    }

    @objc private func pageTapped() {
        let vc = VenueOrderPageViewController(venueId: venueId, venueName: venueName, page: page, orderingOn: enabledSwitch.isOn)
        navigationController?.pushViewController(vc, animated: true)
    }

    /// The owner orders from their own menu (marked TEST), then sees it in Orders
    @objc private func tryTapped() {
        guard let menu, !menu.isEmpty else { return }
        let settings = StoreOrdering(enabled: true, leadMinutes: Int(leadStepper.value), note: ordering.note)
        let menuVC = PlaceMenuViewController(menu: menu, label: label, placeName: venueName,
                                             ordering: settings, venueId: venueId, testOrder: true)
        let nav = UINavigationController(rootViewController: menuVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc private func leadChanged() {
        leadLabel.text = "\(Int(leadStepper.value)) minutes"
    }

    @objc private func saveTapped() {
        let next = StoreOrdering(enabled: enabledSwitch.isOn, leadMinutes: Int(leadStepper.value),
                                 note: (noteField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? nil : noteField.text)
        let loading = AlertPresenter.showLoading(message: "Saving\u{2026}", from: self)
        OrderService.shared.saveOrdering(venueId: venueId, next) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let saved):
                        self.onSaved?(saved)
                        self.navigationController?.popViewController(animated: true)
                    case .failure(let error):
                        self.showError(error.serverMessage ?? "Couldn\u{2019}t save. Try again.")
                    }
                }
            }
        }
    }
}

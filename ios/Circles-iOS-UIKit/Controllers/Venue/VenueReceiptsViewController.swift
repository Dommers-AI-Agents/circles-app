import UIKit

/// Manage Store → Delivery orders (2026-11-06): whether a delivery order's
/// receipt earns points here (Off / I approve each one / Automatic), and the
/// receipts waiting for the team. A `receipt_new` push opens this screen.
final class VenueReceiptsViewController: BaseViewController {

    private let venueId: String
    private var mode: DeliveryReceiptMode
    private var receipts: [VenueReceipt] = []
    /// The mode and how many wait, for Manage Store's row
    var onChanged: ((DeliveryReceiptMode, Int) -> Void)?

    override var enablesPullToRefresh: Bool { true }

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        return table
    }()
    private lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: DeliveryReceiptMode.allCases.map(\.title))
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    init(venueId: String, mode: DeliveryReceiptMode = .off) {
        self.venueId = venueId
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Delivery Orders"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ReceiptCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ModeCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        modeControl.selectedSegmentIndex = DeliveryReceiptMode.allCases.firstIndex(of: mode) ?? 0
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchVenueReceipts(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                switch result {
                case .success(let list):
                    self.receipts = list.receipts
                    self.mode = DeliveryReceiptMode(rawValue: list.mode) ?? .off
                    self.modeControl.selectedSegmentIndex = DeliveryReceiptMode.allCases.firstIndex(of: self.mode) ?? 0
                    self.tableView.reloadData()
                    self.onChanged?(self.mode, self.receipts.count)
                case .failure(let error):
                    // A failed refresh keeps what's showing
                    self.showError(error)
                }
            }
        }
    }

    @objc private func modeChanged() {
        let picked = DeliveryReceiptMode.allCases[modeControl.selectedSegmentIndex]
        let previous = mode
        RewardsService.shared.setDeliveryReceiptMode(venueId: venueId, mode: picked) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.mode = picked
                    self.tableView.reloadData()
                    self.onChanged?(picked, self.receipts.count)
                case .failure(let error):
                    self.modeControl.selectedSegmentIndex = DeliveryReceiptMode.allCases.firstIndex(of: previous) ?? 0
                    self.showError(error)
                }
            }
        }
    }

    private func act(on receipt: VenueReceipt, sourceView: UIView) {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        if let url = receipt.imageUrl {
            actions.append((title: "View receipt", style: .default, handler: { [weak self] in
                self?.present(FullScreenImageViewController(imageURL: url), animated: true)
            }))
        }
        actions.append((title: "Give points", style: .default, handler: { [weak self] in self?.answer(receipt, approve: true) }))
        actions.append((title: "Decline", style: .destructive, handler: { [weak self] in self?.answer(receipt, approve: false) }))
        AlertPresenter.showActionSheet(title: VenueReceiptCopy.headline(receipt), actions: actions, from: self, sourceView: sourceView)
    }

    private func answer(_ receipt: VenueReceipt, approve: Bool) {
        let done: (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.receipts.removeAll { $0.claimId == receipt.claimId }
                    self.tableView.reloadData()
                    self.onChanged?(self.mode, self.receipts.count)
                    self.showSuccess(message)
                case .failure(let error):
                    self.showError(error)
                    self.loadData()
                }
            }
        }
        let name = receipt.user?.displayName ?? "The customer"
        if approve {
            RewardsService.shared.approveReceipt(venueId: venueId, claimId: receipt.claimId) { result in
                done(result.map { r in
                    r.alreadyEarned == true ? "\(name) already earned that day, so no extra points."
                                            : "\(name) got \(r.points ?? 0) points."
                })
            }
        } else {
            RewardsService.shared.declineReceipt(venueId: venueId, claimId: receipt.claimId) { result in
                done(result.map { _ in "Declined. \(name) was told." })
            }
        }
    }
}

extension VenueReceiptsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : max(receipts.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Delivery orders earn points" : "Waiting for you"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? VenueReceiptCopy.modeFooter(mode) : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ModeCell", for: indexPath)
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            modeControl.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(modeControl)
            NSLayoutConstraint.activate([
                modeControl.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
                modeControl.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
                modeControl.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                modeControl.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor)
            ])
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "ReceiptCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if receipts.isEmpty {
            config.text = "No receipts waiting"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let receipt = receipts[indexPath.row]
            config.text = VenueReceiptCopy.headline(receipt)
            config.secondaryText = VenueReceiptCopy.detail(receipt)
            config.secondaryTextProperties.numberOfLines = 0
            config.secondaryTextProperties.color = .secondaryLabel
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, receipts.indices.contains(indexPath.row),
              let cell = tableView.cellForRow(at: indexPath) else { return }
        act(on: receipts[indexPath.row], sourceView: cell)
    }
}

/// The words for the team's receipt rows. Pure.
enum VenueReceiptCopy {
    /// "Ann · DoorDash"
    static func headline(_ receipt: VenueReceipt) -> String {
        [receipt.user?.displayName ?? "A customer", receipt.receipt?.deliveryApp].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// What the phone read, problems first: "✗ Store name not found · Order #A1B2 · Nov 5 · $27.85 · sent today 3:10 PM"
    static func detail(_ receipt: VenueReceipt, calendar: Calendar = .current, now: Date = Date()) -> String {
        var parts: [String] = []
        if receipt.checks?.storeName == false { parts.append("\u{2717} Store name not found") }
        if receipt.checks?.date == false { parts.append("\u{2717} No order date") }
        if receipt.checks?.orderNumber == false { parts.append("\u{2717} No order number") }
        if let number = receipt.receipt?.orderNumber { parts.append("Order #\(number)") }
        if let date = receipt.receipt?.orderDate { parts.append("Ordered \(date)") }
        if let total = receipt.receipt?.total { parts.append(total) }
        if let sent = RewardTicketCopy.date(receipt.createdAt) {
            parts.append("sent " + RewardTicketCopy.dayAndTime(sent, calendar: calendar, now: now))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func modeFooter(_ mode: DeliveryReceiptMode) -> String {
        switch mode {
        case .off:
            return "Customers who order you through DoorDash, Uber Eats or another app can't earn points."
        case .approve:
            return "Customers can send a delivery receipt from your page. You look at each one and tap Give points. Same points as a visit, once a day."
        case .auto:
            return "Points go out right away when the receipt shows your name, an order from the last week and an order number never used here. Anything else waits for you."
        }
    }
}

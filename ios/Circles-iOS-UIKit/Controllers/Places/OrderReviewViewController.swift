import UIKit

/// The customer's order before it's sent (2026-10-20): quantities, a note
/// per item and for the order, pickup as soon as possible or at a time, the
/// estimate, and "pay at the counter". Placing it opens its status.
final class OrderReviewViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    /// The menu screen keeps the cart in step with changes made here
    var onCartChanged: ((OrderCart) -> Void)?

    private let venueId: String
    private let placeName: String
    private let ordering: StoreOrdering
    private var cart: OrderCart { didSet { onCartChanged?(cart); render() } }
    private var orderNote: String?
    private var pickupLater = false

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()
    private let whenControl = UISegmentedControl(items: ["As soon as possible", "Later"])
    private let timePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        return picker
    }()
    private lazy var placeButton = UIButton.primaryButton(title: "Place order \u{00B7} pay at pickup")

    init(venueId: String, placeName: String, ordering: StoreOrdering, cart: OrderCart) {
        self.venueId = venueId
        self.placeName = placeName
        self.ordering = ordering
        self.cart = cart
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your order"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        placeButton.translatesAutoresizingMaskIntoConstraints = false
        placeButton.addTarget(self, action: #selector(placeTapped), for: .touchUpInside)
        view.addSubview(placeButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: placeButton.topAnchor, constant: -8),
            placeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            placeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            placeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        whenControl.selectedSegmentIndex = 0
        whenControl.addTarget(self, action: #selector(whenChanged), for: .valueChanged)
        resetTimeLimits()
        render()
    }

    private var earliestPickup: Date { Date().addingTimeInterval(TimeInterval(ordering.leadMinutes * 60)) }

    private func resetTimeLimits() {
        timePicker.minimumDate = earliestPickup
        timePicker.maximumDate = Date().addingTimeInterval(23.5 * 3600)
        if timePicker.date < earliestPickup { timePicker.date = earliestPickup.addingTimeInterval(15 * 60) }
    }

    @objc private func whenChanged() {
        pickupLater = whenControl.selectedSegmentIndex == 1
        resetTimeLimits()
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }

    private func render() {
        placeButton.isEnabled = !cart.isEmpty
        placeButton.alpha = cart.isEmpty ? 0.5 : 1
        tableView.reloadData()
    }

    // MARK: - Place

    @objc private func placeTapped() {
        guard !cart.isEmpty else { return }
        let pickupAt: Date? = pickupLater ? max(timePicker.date, earliestPickup) : nil
        let loading = AlertPresenter.showLoading(message: "Sending your order\u{2026}", from: self)
        OrderService.shared.place(venueId: venueId, cart: cart, note: orderNote, pickupAt: pickupAt) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let order):
                        AnalyticsService.shared.logEvent("order_placed", parameters: ["items": String(order.itemCount)])
                        self.onCartChanged?(OrderCart())
                        let status = OrderStatusViewController(order: order)
                        guard let nav = self.navigationController else { return }
                        // Back from the status goes to the menu, not this form
                        var stack = nav.viewControllers
                        stack.removeLast()
                        stack.append(status)
                        nav.setViewControllers(stack, animated: true)
                    case .failure(let error):
                        self.showError(error.serverMessage ?? "Your order didn\u{2019}t go through. Try again.")
                    }
                }
            }
        }
    }
}

extension OrderReviewViewController: UITableViewDataSource, UITableViewDelegate {
    // 0 items · 1 pickup · 2 note · 3 estimate
    func numberOfSections(in tableView: UITableView) -> Int { 4 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(1, cart.lines.count)
        case 1: return pickupLater ? 2 : 1
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["\(placeName)", "Pickup", "Note for the store", nil][section]
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1: return "Usually ready in about \(ordering.leadMinutes) minutes. The store confirms your order and gives you a time.\(ordering.note.map { " \($0)" } ?? "")"
        case 3: return "You pay at the counter when you pick it up. The store\u{2019}s prices apply."
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.selectionStyle = .default
        var config = UIListContentConfiguration.subtitleCell()
        switch indexPath.section {
        case 0:
            guard !cart.lines.isEmpty else {
                config.text = "Nothing in your order yet"
                config.textProperties.color = Constants.Colors.secondaryLabel
                cell.selectionStyle = .none
                break
            }
            let line = cart.lines[indexPath.row]
            config.text = "\(line.qty)\u{00D7} \(line.name)"
            config.secondaryText = [line.price, line.note.map { "\u{201C}\($0)\u{201D}" } ?? "Tap to add a note"].compactMap { $0 }.joined(separator: " \u{00B7} ")
            config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            let stepper = UIStepper()
            stepper.minimumValue = 0
            stepper.maximumValue = Double(OrderCart.maxQty)
            stepper.value = Double(line.qty)
            stepper.addAction(UIAction { [weak self, weak stepper] _ in
                guard let self, let stepper else { return }
                self.cart.setQuantity(Int(stepper.value), for: line.itemId)
            }, for: .valueChanged)
            cell.accessoryView = stepper
        case 1:
            if indexPath.row == 0 {
                cell.selectionStyle = .none
                whenControl.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.subviews.forEach { if $0 === whenControl { $0.removeFromSuperview() } }
                cell.contentView.addSubview(whenControl)
                NSLayoutConstraint.activate([
                    whenControl.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                    whenControl.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                    whenControl.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    whenControl.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor)
                ])
                cell.contentConfiguration = nil
                return cell
            }
            config = UIListContentConfiguration.cell()
            config.text = "Pick up at"
            cell.accessoryView = timePicker
            timePicker.sizeToFit()
            cell.selectionStyle = .none
        case 2:
            config = UIListContentConfiguration.cell()
            config.text = orderNote ?? "Allergies, how you\u{2019}d like it\u{2026}"
            config.textProperties.color = orderNote == nil ? Constants.Colors.secondaryLabel : Constants.Colors.label
        default:
            config = UIListContentConfiguration.valueCell()
            config.text = "Estimate"
            let est = cart.estimate
            config.secondaryText = OrderCart.estimateText(total: est.total, partial: est.partial) ?? "\u{2014}"
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0 where !cart.lines.isEmpty:
            let line = cart.lines[indexPath.row]
            AlertPresenter.showTextInput(title: line.name, message: "A note for this item", placeholder: "No onions, extra sauce\u{2026}",
                                         initialText: line.note, confirmTitle: "Save", from: self) { [weak self] text in
                self?.cart.setNote(text, for: line.itemId)
            }
        case 2:
            AlertPresenter.showTextInput(title: "Note for the store", placeholder: "Allergies, how you\u{2019}d like it\u{2026}",
                                         initialText: orderNote, confirmTitle: "Save", from: self) { [weak self] text in
                let clean = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self?.orderNote = clean.isEmpty ? nil : String(clean.prefix(300))
                self?.render()
            }
        default:
            break
        }
    }
}

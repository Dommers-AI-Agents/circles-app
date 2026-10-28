import UIKit

/// One order-ahead order, as its customer sees it (2026-10-20): where it is
/// (sent → accepted with a ready time → ready → picked up, or declined /
/// not answered), what's in it and the estimate. Refreshes while it's open;
/// Cancel until the store accepts. Opened after placing it and from its pushes.
final class OrderStatusViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { order == nil }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var reloadsDataOnAppear: Bool { true }

    private let orderId: String
    private var order: StoreOrder?
    private var poller: Timer?

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = Constants.Colors.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    private let linesLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }()
    private lazy var cancelButton = UIButton.dangerButton(title: "Cancel order")
    /// Ready (or accepted) and in hand: the customer closes it out themselves
    private lazy var pickedUpButton = UIButton.primaryButton(title: "I picked it up")
    private let stack = UIStackView()

    init(order: StoreOrder) {
        self.orderId = order.orderId
        self.order = order
        super.init(nibName: nil, bundle: nil)
    }

    init(orderId: String) {
        self.orderId = orderId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your order"
        // Inside the ordering sheet (just placed, or opened from a push): Done
        // closes the whole sheet and lands back on the place page
        if navigationController?.presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                (self?.navigationController ?? self)?.dismiss(animated: true)
            })
        }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let iconHolder = UIView()
        iconHolder.addSubview(iconView)
        [iconHolder, statusLabel, detailLabel, linesLabel, pickedUpButton, cancelButton].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(24, after: detailLabel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            iconView.centerXAnchor.constraint(equalTo: iconHolder.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: iconHolder.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconHolder.bottomAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            iconView.widthAnchor.constraint(equalToConstant: 64)
        ])
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        pickedUpButton.addTarget(self, action: #selector(pickedUpTapped), for: .touchUpInside)
        render()
        // Seeing the order settles its "ready" / "accepted" notices
        NotificationService.shared.originSeen(kind: "order", id: orderId, userInfoKey: "orderId")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poller?.invalidate()
        poller = nil
    }

    override func loadData(completion: (() -> Void)? = nil) {
        OrderService.shared.order(orderId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                switch result {
                case .success(let order):
                    self.order = order
                    self.render()
                case .failure(let error):
                    if self.order == nil { self.showError(error.serverMessage ?? "Couldn\u{2019}t load your order.") }
                }
                self.schedulePolling()
                completion?()
            }
        }
    }

    /// Every 15 s while the order is still moving (pushes say so too)
    private func schedulePolling() {
        poller?.invalidate()
        guard order?.isOpen == true, view.window != nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.loadData() }
    }

    static func timeText(_ iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter.withFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return f.string(from: date)
    }

    private func render() {
        guard let order, isViewLoaded else { return }
        let ready = Self.timeText(order.readyAt)
        let pickup = order.pickup.asap ? "as soon as possible" : "at \(Self.timeText(order.pickup.at) ?? "your time")"
        let (symbol, headline, detail): (String, String, String) = {
            switch order.status {
            case "placed": return ("paperplane.circle.fill", "Sent to \(order.venueName)", "Waiting for the store to accept it. You asked for pickup \(pickup).")
            case "accepted": return ("checkmark.circle.fill", "Accepted", ready.map { "Ready around \($0). Pay at the counter." } ?? "The store is making it.")
            case "ready": return ("bag.circle.fill", "Ready for pickup", "Head to the counter at \(order.venueName) to pick it up and pay.")
            case "picked_up": return ("hand.thumbsup.circle.fill", "Picked up", "Enjoy!")
            case "declined": return ("xmark.circle.fill", "\(order.venueName) couldn\u{2019}t take it", order.declineReason ?? "They can\u{2019}t make it right now.")
            case "cancelled": return ("xmark.circle", "Cancelled", "The store was told.")
            case "expired": return ("clock.badge.exclamationmark", "Not answered", "The store didn\u{2019}t accept it, so don\u{2019}t head over for it. Try calling them.")
            default: return ("circle", order.statusLabel, "")
            }
        }()
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = ["declined", "expired", "cancelled"].contains(order.status) ? .systemGray : Constants.Colors.primary
        statusLabel.text = order.test == true ? "Test \u{00B7} \(headline)" : headline
        detailLabel.text = detail
        var lines = order.lines.map { line -> String in
            var row = "\(line.qty)\u{00D7} \(line.name)"
            if let price = line.price { row += "  \u{00B7}  \(price)" }
            if let note = line.note { row += "\n     \u{201C}\(note)\u{201D}" }
            return row
        }
        if let note = order.note { lines.append("\nNote: \(note)") }
        if let estimate = OrderCart.estimateText(total: order.estimate, partial: order.estimateIsPartial) {
            lines.append("\n\(estimate), paid at pickup")
        }
        linesLabel.text = lines.joined(separator: "\n")
        cancelButton.isHidden = order.status != "placed"
        pickedUpButton.isHidden = !["accepted", "ready"].contains(order.status)
    }

    @objc private func pickedUpTapped() {
        pickedUpButton.isEnabled = false
        OrderService.shared.pickedUp(orderId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pickedUpButton.isEnabled = true
                switch result {
                case .success(let order):
                    self.order = order
                    self.render()
                    // The banner on the place page and the notices go with it
                    NotificationCenter.default.post(name: VenueOrdersViewController.ordersChanged, object: nil)
                    NotificationService.shared.originSeen(kind: "order", id: self.orderId, userInfoKey: "orderId")
                case .failure(let error):
                    self.showError(error.serverMessage ?? "Couldn\u{2019}t mark it picked up. Try again.")
                }
            }
        }
    }

    @objc private func cancelTapped() {
        AlertPresenter.showConfirmation(title: "Cancel this order?", message: "The store will be told not to make it.",
                                        confirmTitle: "Cancel order", cancelTitle: "Keep it", isDestructive: true, from: self) { [weak self] in
            guard let self else { return }
            OrderService.shared.cancel(self.orderId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let order):
                        self.order = order
                        self.render()
                        NotificationCenter.default.post(name: VenueOrdersViewController.ordersChanged, object: nil)
                    case .failure(let error): self.showError(error.serverMessage ?? "Couldn\u{2019}t cancel it. Call the store.")
                    }
                }
            }
        }
    }
}

extension ISO8601DateFormatter {
    /// "2026-10-20T16:30:00.000Z" (the server's shape)
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

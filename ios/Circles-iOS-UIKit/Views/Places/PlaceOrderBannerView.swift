import UIKit

/// The customer's open order-ahead orders, first thing under the photo on
/// the store's page (Wes, 2026-10-28: tracking belongs at the top, not in
/// small print down the page). One filled, tappable card per open order
/// (two orders never hide each other): the store, the status with the
/// ready time, and a chevron into the status screen.
final class PlaceOrderBannerView: UIStackView {

    var onTap: ((StoreOrder) -> Void)?

    /// Outside a stack view a hidden view keeps its height, so collapse it
    private lazy var collapsed = heightAnchor.constraint(equalToConstant: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 8
        isHidden = true
        collapsed.isActive = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows every open order, or hides itself when there is none
    func configure(orders: [StoreOrder]) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        let open = orders.filter { $0.isOpen }
        guard !open.isEmpty else {
            isHidden = true
            collapsed.isActive = true
            return
        }
        collapsed.isActive = false
        isHidden = false
        for order in open {
            let card = PlaceOrderCard()
            card.configure(order: order)
            card.onTap = { [weak self] in self?.onTap?(order) }
            addArrangedSubview(card)
        }
    }
}

/// One order's card inside the banner
final class PlaceOrderCard: UIControl {

    var onTap: (() -> Void)?

    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "bag.fill"))
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.textColor = .white
        label.numberOfLines = 1
        return label
    }()
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.numberOfLines = 2
        return label
    }()
    private let chevron: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "chevron.right"))
        view.tintColor = UIColor.white.withAlphaComponent(0.9)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.primary
        layer.cornerRadius = 14
        isAccessibilityElement = true
        accessibilityTraits = .button

        let text = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        text.axis = .vertical
        text.spacing = 2
        text.isUserInteractionEnabled = false
        text.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        chevron.isUserInteractionEnabled = false
        addSubview(iconView)
        addSubview(text)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 14).priority(.defaultHigh),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14).priority(.defaultHigh),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.85 : 1 }
    }

    func configure(order: StoreOrder) {
        titleLabel.text = "Your order at \(order.venueName)"
        statusLabel.text = "\(order.statusLine(readyTime: OrderStatusViewController.timeText(order.readyAt))) \u{00B7} \(order.summary)"
        accessibilityLabel = "\(titleLabel.text ?? ""). \(statusLabel.text ?? ""). Opens the order."
    }

    @objc private func tapped() { onTap?() }
}

private extension NSLayoutConstraint {
    func priority(_ value: UILayoutPriority) -> NSLayoutConstraint {
        priority = value
        return self
    }
}

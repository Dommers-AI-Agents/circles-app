import UIKit

/// "Your free drip coffee is ready · Show staff" (2026-11-01): wherever a
/// customer looks for their reward (the store page, Get Rewards, Store
/// Rewards), an open ticket is one tap away.
final class RewardTicketBar: UIControl {

    let ticket: RewardVoucher
    var onTap: ((RewardVoucher) -> Void)?

    init(ticket: RewardVoucher) {
        self.ticket = ticket
        super.init(frame: .zero)
        backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.5).cgColor

        let icon = UIImageView(image: UIImage(systemName: "ticket.fill"))
        icon.tintColor = .systemGreen
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = "Your \(ticket.offerTitle) is ready"
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.numberOfLines = 2
        let detail = UILabel()
        detail.text = "Tap to show staff at \(ticket.venueName)"
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Constants.Colors.secondaryLabel
        detail.numberOfLines = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Constants.Colors.secondaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(title.text ?? ""). \(detail.text ?? "")"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap?(ticket) }

    /// The full-screen ticket, from any screen
    static func present(_ ticket: RewardVoucher, from presenter: UIViewController) {
        let voucherVC = VoucherViewController(voucher: ticket)
        voucherVC.modalPresentationStyle = .fullScreen
        presenter.present(voucherVC, animated: true)
    }
}

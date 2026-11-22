import UIKit

/// One row of a settings-style card: a tinted SF Symbol tile, a title, the
/// current value on the right and a chevron ("Notify people · 2 people ›").
/// A UIButton, so it takes a target or a pull-down `menu` like any other;
/// `value` is the only thing a screen updates after a pick. Check In's
/// share card (Wes, 2026-11-21: "make this prettier").
final class IconRowButton: UIButton {

    private let valueLabel = UILabel()
    private let titleLabelView = UILabel()

    /// The words on the right ("Optional", "Followers", "3 people")
    var value: String = "" {
        didSet { valueLabel.text = value }
    }

    init(systemName: String, tint: UIColor, title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = title

        let icon = UIImageView(image: UIImage(systemName: systemName))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.backgroundColor = tint.withAlphaComponent(0.16)
        icon.layer.cornerRadius = 9
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        titleLabelView.text = title
        titleLabelView.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabelView.textColor = Constants.Colors.label
        titleLabelView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabelView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = Constants.Colors.secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Constants.Colors.tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, titleLabelView, valueLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.setCustomSpacing(8, after: valueLabel)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) { self.alpha = self.isHighlighted ? 0.55 : 1 }
        }
    }
}

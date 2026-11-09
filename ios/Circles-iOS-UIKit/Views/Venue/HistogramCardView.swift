import UIKit

/// A small bar chart in a card: "Busiest hours" / "Busiest days" on the
/// owner's Activity and Insights pages. Bars scale to the largest value;
/// empty slots show a faint stub so the axis reads as a full day or week.
enum HistogramCardView {

    /// Hour labels for a 24-slot chart: 12a, 6a, 12p, 6p
    static let hourLabels: [String] = (0..<24).map {
        $0 % 6 == 0 ? String(format: "%d%@", $0 == 0 ? 12 : ($0 > 12 ? $0 - 12 : $0), $0 < 12 ? "a" : "p") : ""
    }
    static let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    static func make(title: String, values: [Int], labels: [String]) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let barsStack = UIStackView()
        barsStack.axis = .horizontal
        barsStack.distribution = .fillEqually
        barsStack.alignment = .bottom
        barsStack.spacing = 2
        barsStack.translatesAutoresizingMaskIntoConstraints = false

        let labelsStack = UIStackView()
        labelsStack.axis = .horizontal
        labelsStack.distribution = .fillEqually
        labelsStack.spacing = 2
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        let maxValue = max(values.max() ?? 1, 1)
        let barMaxHeight: CGFloat = 48
        for (index, value) in values.enumerated() {
            let barWrapper = UIView()
            let bar = UIView()
            bar.backgroundColor = value > 0 ? Constants.Colors.primary : Constants.Colors.primary.withAlphaComponent(0.15)
            bar.layer.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            barWrapper.addSubview(bar)
            let height = value > 0
                ? max(4, barMaxHeight * CGFloat(value) / CGFloat(maxValue))
                : 3
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: barWrapper.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: barWrapper.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: barWrapper.bottomAnchor),
                bar.heightAnchor.constraint(equalToConstant: height),
                barWrapper.heightAnchor.constraint(equalToConstant: barMaxHeight)
            ])
            barsStack.addArrangedSubview(barWrapper)

            let label = UILabel()
            label.text = index < labels.count ? labels[index] : ""
            label.font = UIFont.systemFont(ofSize: 9)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            labelsStack.addArrangedSubview(label)
        }

        card.addSubview(titleLabel)
        card.addSubview(barsStack)
        card.addSubview(labelsStack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            barsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            barsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            barsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            labelsStack.topAnchor.constraint(equalTo: barsStack.bottomAnchor, constant: 2),
            labelsStack.leadingAnchor.constraint(equalTo: barsStack.leadingAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: barsStack.trailingAnchor),
            labelsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }
}

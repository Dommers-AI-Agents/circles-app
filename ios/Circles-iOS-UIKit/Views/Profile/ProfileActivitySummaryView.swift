import UIKit

/// The month-at-a-glance card at the top of Profile › Activity: four
/// numbers (each a tap into that filter), the streak line, and a share
/// button that renders this card as an image.
final class ProfileActivitySummaryView: UIView {
    var onTapCount: ((ProfileActivityTimeline.Filter) -> Void)?
    var onShare: (() -> Void)?

    private let monthLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        return l
    }()
    private lazy var shareButton: UIButton = {
        let b = UIButton.iconButton(systemName: "square.and.arrow.up")
        b.tintColor = Constants.Colors.accent
        b.accessibilityLabel = "Share this month's recap"
        b.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        return b
    }()
    private let numbersRow = UIStackView()
    private let footnote: UILabel = {
        let l = UILabel()
        l.font = UIFont.systemFont(ofSize: 12)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.numberOfLines = 2
        return l
    }()
    private var countViews: [ProfileActivityTimeline.Filter: (number: UILabel, caption: UILabel)] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.06, green: 0.11, blue: 0.18, alpha: 1) // navy, matching the brand card
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [monthLabel, UIView(), shareButton])
        header.alignment = .center
        numbersRow.distribution = .fillEqually
        numbersRow.spacing = 8
        for filter in [ProfileActivityTimeline.Filter.checkins, .places, .moments, .sent] {
            let number = UILabel()
            number.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            number.textColor = .white
            number.text = "–"
            let caption = UILabel()
            caption.font = UIFont.systemFont(ofSize: 11)
            caption.textColor = UIColor.white.withAlphaComponent(0.7)
            caption.text = filter == .sent ? "postcards" : filter.title.lowercased()
            caption.adjustsFontSizeToFitWidth = true
            let column = UIStackView(arrangedSubviews: [number, caption])
            column.axis = .vertical
            column.spacing = 2
            column.isUserInteractionEnabled = true
            column.tag = ProfileActivityTimeline.Filter.allCases.firstIndex(of: filter) ?? 0
            column.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countTapped(_:))))
            column.isAccessibilityElement = true
            column.accessibilityTraits = .button
            numbersRow.addArrangedSubview(column)
            countViews[filter] = (number, caption)
        }
        let stack = UIStackView(arrangedSubviews: [header, numbersRow, footnote])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            shareButton.widthAnchor.constraint(equalToConstant: 32),
            shareButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with summary: OwnActivitySummary?) {
        guard let summary else {
            monthLabel.text = ProfileActivityTimeline.monthName(Self.currentMonthKey()).uppercased()
            footnote.text = "Loading this month…"
            return
        }
        monthLabel.text = ProfileActivityTimeline.monthName(summary.month).uppercased()
        countViews[.checkins]?.number.text = "\(summary.counts.checkins)"
        countViews[.places]?.number.text = "\(summary.counts.places)"
        countViews[.moments]?.number.text = "\(summary.counts.moments)"
        countViews[.sent]?.number.text = "\(summary.counts.postcards)"
        for (filter, views) in countViews {
            views.number.accessibilityLabel = "\(views.number.text ?? "") \(views.caption.text ?? "")"
            _ = filter
        }
        let onThisDay = summary.onThisDay.first.flatMap { $0.placeName }.map { "A year ago today you were at \($0)." }
        footnote.text = [ProfileActivityTimeline.summaryLine(summary), onThisDay].compactMap { $0 }.joined(separator: "\n")
        if footnote.text?.isEmpty ?? true { footnote.text = "Check in, add a place or post a moment and it lands here." }
    }

    static func currentMonthKey(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// The card as an image, for the share sheet.
    func renderImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in drawHierarchy(in: bounds, afterScreenUpdates: true) }
    }

    @objc private func countTapped(_ recognizer: UITapGestureRecognizer) {
        guard let tag = recognizer.view?.tag, ProfileActivityTimeline.Filter.allCases.indices.contains(tag) else { return }
        onTapCount?(ProfileActivityTimeline.Filter.allCases[tag])
    }

    @objc private func shareTapped() { onShare?() }
}

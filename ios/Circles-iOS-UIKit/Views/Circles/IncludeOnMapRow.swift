import UIKit

/// "Include on my map": a switch with a note that says what each position
/// means. Used where a circle is created and edited.
final class IncludeOnMapRow: UIView {
    var onChange: ((Bool) -> Void)?

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue; refreshNote() }
    }

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let toggle = UISwitch()

    init(isOn: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = CircleMapCopy.title
        titleLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        titleLabel.textColor = .label
        noteLabel.font = .systemFont(ofSize: 13)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
        toggle.isOn = isOn
        toggle.addTarget(self, action: #selector(changed), for: .valueChanged)

        let top = UIStackView(arrangedSubviews: [titleLabel, UIView(), toggle])
        top.alignment = .center
        let column = UIStackView(arrangedSubviews: [top, noteLabel])
        column.axis = .vertical
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refreshNote()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() {
        refreshNote()
        onChange?(toggle.isOn)
    }

    private func refreshNote() { noteLabel.text = CircleMapCopy.note(isOn: toggle.isOn) }
}

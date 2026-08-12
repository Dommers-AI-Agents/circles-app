import UIKit

/// Horizontal, scrollable row of tag filter chips for the circle detail view.
/// Shows an "All" chip followed by the circle's distinct place tags. Chips are
/// matched on the raw tag value but displayed title-cased ("want-to-go" →
/// "Want To Go"). Mirrors the CategoryChipBar pattern used in Browse.
final class TagChipBar: UIView {

    /// Called with the raw tag value, or nil when "All" is selected.
    var onSelect: ((String?) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [(tag: String?, button: UIButton)] = []
    private(set) var selectedTag: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuilds the chip row. `tags` are raw values, already ordered for
    /// display; `selected` is kept only if it still exists in `tags`.
    func setTags(_ tags: [String], selected: String?) {
        if let selected = selected,
           tags.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            selectedTag = selected
        } else {
            selectedTag = nil
        }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = []

        let allButton = makeChip("All")
        allButton.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(allButton)
        buttons.append((nil, allButton))

        for tag in tags {
            let b = makeChip(TagChipBar.displayTitle(for: tag))
            b.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
            buttons.append((tag, b))
        }
        updateSelectionUI()
    }

    /// "want-to-go" → "Want To Go"
    static func displayTitle(for tag: String) -> String {
        return tag
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func makeChip(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.layer.cornerRadius = 16
        b.layer.masksToBounds = true
        b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        return b
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard let match = buttons.first(where: { $0.button === sender }) else { return }
        // Tapping the already-selected tag clears the filter back to All.
        if let tag = match.tag, tag == selectedTag {
            selectedTag = nil
        } else {
            selectedTag = match.tag
        }
        updateSelectionUI()
        onSelect?(selectedTag)
    }

    private func updateSelectionUI() {
        for (tag, button) in buttons {
            let isOn = tag == selectedTag
            button.backgroundColor = isOn ? Constants.Colors.primary : Constants.Colors.primary.withAlphaComponent(0.10)
            button.setTitleColor(isOn ? .white : Constants.Colors.primary, for: .normal)
        }
    }
}

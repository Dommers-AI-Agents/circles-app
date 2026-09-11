import UIKit

/// A mirror of the profile's tab control (+ add-circle button) pinned to
/// the top, revealed once the profile header scrolls past it so the tabs
/// stay reachable while scrolling a long circle/uploads list. Starts hidden
/// and transparent; the profile owns the reveal animation and keeps the
/// controls mirrored to the inline ones.
final class ProfileStickyTabBar: UIView {
    let segmentedControl: UISegmentedControl = {
        let c = UISegmentedControl(items: ["Circles", "Moments", "Uploads"])
        c.selectedSegmentIndex = 0
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }()

    let addButton: UIButton = ProfileViewController.makeNewCircleButton()

    private let separator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = Constants.Colors.background
        isHidden = true
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(segmentedControl)
        addSubview(addButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            segmentedControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            segmentedControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmentedControl.widthAnchor.constraint(equalToConstant: 200),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32),

            addButton.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: segmentedControl.leadingAnchor, constant: -12),
            addButton.widthAnchor.constraint(equalToConstant: 38),
            addButton.heightAnchor.constraint(equalToConstant: 38),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

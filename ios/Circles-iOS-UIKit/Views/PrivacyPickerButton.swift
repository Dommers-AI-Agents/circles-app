import UIKit

/// The privacy control every form uses.
///
/// This replaced a `UISegmentedControl` on each screen. Four tiers with a line
/// of explanation each simply do not fit across an iPhone, and segments have
/// nowhere to put the explanation — which is how one tier came to be labelled
/// "My Network" on one screen and "Friends" on another, with nothing on either
/// screen saying what that meant. A pop-up button shows title and subtitle per
/// option natively, and grows to five options for moments without redesign.
///
/// The caption underneath carries the part a label can't: how many people are
/// actually on the Inner Circle list, and a way to go change it.
final class PrivacyPickerButton: UIView {

    /// Called when the person picks a different option.
    var onChange: ((PrivacyOption) -> Void)?
    /// Called when they tap the "Edit list" caption.
    var onEditInnerCircle: (() -> Void)?

    private(set) var selected: PrivacyOption
    private let options: [PrivacyOption]

    private let button = UIButton(type: .system)
    private let captionButton = UIButton(type: .system)

    /// - Parameter entity: which option set to offer — a circle has four tiers,
    ///   a place adds "same as circle", a moment adds the followers audience.
    init(entity: PrivacyEntity, selected: PrivacyOption) {
        self.options = PrivacyTier.options(for: entity)
        self.selected = options.contains(selected) ? selected : (options.first ?? .tier(.public))
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Point the picker at a stored value. An unrecognised tier leaves the
    /// selection alone and disables the control rather than silently showing —
    /// and then saving — something narrower than what is stored.
    func select(_ option: PrivacyOption?) {
        guard let option = option, options.contains(option) else {
            button.isEnabled = false
            captionButton.isEnabled = false
            captionButton.setTitle("Update the app to change this setting", for: .normal)
            return
        }
        selected = option
        refresh()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.bordered()
        config.baseForegroundColor = Constants.Colors.primary
        config.cornerStyle = .medium
        config.titleAlignment = .leading
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false

        captionButton.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        captionButton.contentHorizontalAlignment = .leading
        captionButton.setTitleColor(Constants.Colors.secondaryLabel, for: .normal)
        captionButton.addTarget(self, action: #selector(captionTapped), for: .touchUpInside)
        captionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)
        addSubview(captionButton)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.heightAnchor.constraint(equalToConstant: 44),

            captionButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 4),
            captionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            captionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // The caption is only live while the list count can change under us.
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: .innerCircleDidChange, object: nil)
        refresh()
    }

    @objc private func refresh() {
        button.menu = UIMenu(children: options.map { option in
            UIAction(title: option.title,
                     subtitle: option.subtitle,
                     image: UIImage(systemName: option.systemIconName),
                     state: option == selected ? .on : .off) { [weak self] _ in
                guard let self = self else { return }
                self.selected = option
                self.refresh()
                self.onChange?(option)
            }
        })

        var config = button.configuration
        config?.title = selected.title
        config?.image = UIImage(systemName: selected.systemIconName)
        config?.imagePadding = 8
        button.configuration = config

        if selected == .tier(.innerCircle) {
            captionButton.isHidden = false
            captionButton.setTitle(InnerCircleManager.shared.pickerCaption, for: .normal)
        } else {
            captionButton.isHidden = true
            captionButton.setTitle(nil, for: .normal)
        }
    }

    /// The circle value for the current selection. Circles can't be set to
    /// "same as circle" or the followers audience, so those fall back to the
    /// most private thing rather than guessing.
    var selectedCirclePrivacy: PrivacyLevel {
        if case .tier(let tier) = selected { return tier.circlePrivacy }
        return .private
    }

    @objc private func captionTapped() {
        guard selected == .tier(.innerCircle) else { return }
        onEditInnerCircle?()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

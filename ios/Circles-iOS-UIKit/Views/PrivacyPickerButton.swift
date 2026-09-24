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
    /// The named Inner Circle list behind the selection, when one was chosen.
    private(set) var selectedListId: String?
    private let entity: PrivacyEntity
    private let options: [PrivacyOption]

    private let button = UIButton.menuFieldButton()
    private let captionButton = UIButton.captionLinkButton()

    /// - Parameter entity: which option set to offer — a circle has four tiers,
    ///   a place adds "same as circle", a moment adds the followers audience.
    init(entity: PrivacyEntity, selected: PrivacyOption) {
        self.entity = entity
        self.options = PrivacyTier.options(for: entity)
        self.selected = options.contains(selected) ? selected : (options.first ?? .tier(.public))
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// True once `select` was handed a tier this build doesn't understand.
    ///
    /// Callers MUST leave the privacy field out of their save body while this
    /// is set. Disabling the control is not enough on its own: `selected` still
    /// holds whatever it was initialised with, so a save would quietly write
    /// that over a tier the app can't even display.
    private(set) var isLocked = false

    /// Point the picker at a stored value. An unrecognised tier locks the
    /// control rather than silently showing — and then saving — something
    /// different from what is stored.
    /// Point the picker at a stored value that named a list.
    func select(_ option: PrivacyOption?, listId: String?) {
        selectedListId = listId
        select(option)
    }

    func select(_ option: PrivacyOption?) {
        guard let option = option, options.contains(option) else {
            isLocked = true
            button.isEnabled = false
            captionButton.isHidden = false
            captionButton.isEnabled = false
            captionButton.setTitle("Update the app to change this setting", for: .normal)
            return
        }
        isLocked = false
        selected = option
        refresh()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        captionButton.addTarget(self, action: #selector(captionTapped), for: .touchUpInside)

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
        // One inline sub-menu per section, so a demoted option sits under its
        // own heading ("Advanced") instead of vanishing from the list.
        let sections = PrivacyTier.menuSections(for: entity)
        button.menu = UIMenu(children: sections.map { section in
            UIMenu(title: section.title ?? "",
                   options: .displayInline,
                   children: section.options.flatMap(entries(for:)))
        })

        var config = button.configuration
        config?.title = currentTitle
        config?.image = UIImage(systemName: selected.systemIconName)
        config?.imagePadding = 8
        button.configuration = config

        if !isLocked && selected == .tier(.innerCircle) {
            captionButton.isHidden = false
            captionButton.setTitle(captionText, for: .normal)
        } else {
            captionButton.isHidden = true
            captionButton.setTitle(nil, for: .normal)
        }
    }

    /// One entry per option, except Inner Circle, which becomes one entry per
    /// named list — "which list" being the only useful form of the question
    /// once there is more than one.
    private func entries(for option: PrivacyOption) -> [UIMenuElement] {
        guard option == .tier(.innerCircle) else { return [action(option, listId: nil, title: option.title, subtitle: option.subtitle)] }
        let lists = InnerCircleManager.shared.usableLists
        guard !lists.isEmpty else { return [action(option, listId: nil, title: option.title, subtitle: option.subtitle)] }
        var children = lists.map { list in
            action(option, listId: list.id, title: list.name,
                   subtitle: list.userIds.count == 1 ? "Inner Circle · 1 person" : "Inner Circle · \(list.userIds.count) people")
        }
        // Only offered when it is what the item already says, so nobody picks
        // a vaguer audience by accident, and nothing silently narrows either.
        if selected == .tier(.innerCircle) && selectedListId == nil {
            children.append(action(option, listId: nil, title: "Anyone on my lists", subtitle: option.subtitle))
        }
        return children
    }

    private func action(_ option: PrivacyOption, listId: String?, title: String, subtitle: String) -> UIAction {
        UIAction(title: title,
                 subtitle: subtitle,
                 image: UIImage(systemName: option.systemIconName),
                 state: option == selected && listId == selectedListId ? .on : .off) { [weak self] _ in
            guard let self = self else { return }
            self.selected = option
            self.selectedListId = listId
            self.refresh()
            self.onChange?(option)
        }
    }

    private var currentList: InnerCircleNamedList? {
        guard let selectedListId else { return nil }
        return InnerCircleManager.shared.usableLists.first { $0.id == selectedListId }
    }

    private var currentTitle: String {
        if selected == .tier(.innerCircle), let name = currentList?.name { return name }
        return selected.title
    }

    private var captionText: String {
        guard let list = currentList else { return InnerCircleManager.shared.pickerCaption }
        let count = list.userIds.count
        return "\(count) \(count == 1 ? "person" : "people") on \(list.name) · Edit lists"
    }

    /// The circle value for the current selection. Circles can't be set to
    /// "same as circle" or the followers audience, so those fall back to the
    /// most private thing rather than guessing.
    var selectedCirclePrivacy: PrivacyLevel? {
        guard !isLocked, case .tier(let tier) = selected else { return nil }
        return tier.circlePrivacy
    }

    /// The place value for the current selection, or nil when locked.
    var selectedPlacePrivacy: PlacePrivacy? {
        isLocked ? nil : selected.placePrivacy
    }

    @objc private func captionTapped() {
        guard selected == .tier(.innerCircle) else { return }
        onEditInnerCircle?()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

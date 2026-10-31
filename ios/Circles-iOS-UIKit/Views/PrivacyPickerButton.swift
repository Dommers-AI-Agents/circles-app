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
    /// The circle's own level, so "same as circle" can say what it is:
    /// "Connections · same as circle" (Wes, 2026-10-31)
    var inheritedTier: PrivacyTier? { didSet { refresh() } }
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
        // The menu names each list, so it needs them loaded — not every form
        // that hosts a picker loads them itself (the circle and place editors
        // didn't, and offered a bare "Inner Circle"). The change notification
        // above rebuilds the menu when they arrive.
        InnerCircleManager.shared.primeIfNeeded()
        refresh()
    }

    @objc private func refresh() {
        button.menu = PrivacyMenu.make(entity: entity, selected: selected, selectedListId: selectedListId) { [weak self] option, listId in
            guard let self = self else { return }
            self.selected = option
            self.selectedListId = listId
            self.refresh()
            self.onChange?(option)
        }

        var config = button.configuration
        config?.title = currentTitle
        config?.image = UIImage(systemName: selected == .inheritCircle ? (inheritedTier?.systemIconName ?? selected.systemIconName) : selected.systemIconName)
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

    private var currentList: InnerCircleNamedList? {
        guard let selectedListId else { return nil }
        return InnerCircleManager.shared.usableLists.first { $0.id == selectedListId }
    }

    private var currentTitle: String {
        if selected == .inheritCircle, let tier = inheritedTier { return "\(tier.title) \u{00B7} same as circle" }
        return PrivacyMenu.title(for: selected, listId: selectedListId)
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

/// The privacy options as a menu, and the name of the current choice. One
/// builder for the form picker above and the circle page's tap-to-change
/// privacy chip, so the two can never offer different options.
enum PrivacyMenu {
    /// One inline sub-menu per section, so a demoted option sits under its own
    /// heading ("Advanced") instead of vanishing from the list.
    static func make(entity: PrivacyEntity, selected: PrivacyOption, selectedListId: String?,
                     onPick: @escaping (PrivacyOption, String?) -> Void) -> UIMenu {
        UIMenu(children: PrivacyTier.menuSections(for: entity).map { section in
            UIMenu(title: section.title ?? "",
                   options: .displayInline,
                   children: section.options.flatMap { entries(for: $0, selected: selected, selectedListId: selectedListId, onPick: onPick) })
        })
    }

    /// "Connections", or the Inner Circle list's own name.
    static func title(for option: PrivacyOption, listId: String?) -> String {
        if option == .tier(.innerCircle) {
            let lists = InnerCircleManager.shared.usableLists
            if let listId, let name = lists.first(where: { $0.id == listId })?.name { return name }
            if !lists.isEmpty { return "Inner Circle · choose a list" }
        }
        return option.title
    }

    /// One entry per option, except Inner Circle, which becomes one entry per
    /// named list — "which list" being the only useful form of the question
    /// once there is more than one.
    private static func entries(for option: PrivacyOption, selected: PrivacyOption, selectedListId: String?,
                                onPick: @escaping (PrivacyOption, String?) -> Void) -> [UIMenuElement] {
        let one = { (listId: String?, title: String, subtitle: String) -> UIAction in
            UIAction(title: title,
                     subtitle: subtitle,
                     image: UIImage(systemName: option.systemIconName),
                     state: option == selected && listId == selectedListId ? .on : .off) { _ in onPick(option, listId) }
        }
        guard option == .tier(.innerCircle) else { return [one(nil, option.title, option.subtitle)] }
        let lists = InnerCircleManager.shared.usableLists
        guard !lists.isEmpty else { return [one(nil, option.title, option.subtitle)] }
        // Only the lists themselves: "anyone on my lists" defeats the point of
        // having lists (Wes, 2026-10-02). An older item still on it shows
        // "choose a list" until one is picked.
        return lists.map { list in
            one(list.id, list.name, list.userIds.count == 1 ? "Inner Circle · 1 person" : "Inner Circle · \(list.userIds.count) people")
        }
    }
}

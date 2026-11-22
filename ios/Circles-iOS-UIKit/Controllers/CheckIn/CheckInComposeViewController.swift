import UIKit

/// The check-in screen once the place is known: one tap on Check In is a
/// complete check-in (connections see it, the server's two-hour window).
/// Every other field is visible and optional — a rating, a note that also
/// lands on the place as a comment, people to notify — and "Who's it for?"
/// decides who sees it, down to "Just me" for a private record.
final class CheckInComposeViewController: BaseViewController {

    private let place: Place
    private var selectedGroups: Set<String> = []
    private var selectedUsers: Set<String> = []
    /// The store's rewards, fetched quietly on open so the confirmation can
    /// say how to collect points here. nil = no rewards or lookup failed.
    private var venueRewards: PlaceVenueData?

    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// The place's photo fading into the brand wash, behind everything
    /// (Wes, 2026-11-21: "make this prettier" — never a flat black page)
    private let backdrop = FirstRunBackdropView()
    private var hasPhoto: Bool { !(place.photos?.first ?? "").isEmpty }

    /// The place, said once at the top with no box around it: its category
    /// in a tinted tile, the name big, the address under a pin
    private lazy var placeHero: UIView = {
        let tile = UIImageView(image: UIImage(systemName: place.category.systemIconName))
        tile.tintColor = place.category.color
        tile.contentMode = .center
        tile.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        tile.backgroundColor = place.category.color.withAlphaComponent(0.18)
        tile.layer.cornerRadius = 14
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: 48).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let name = UILabel()
        name.text = place.name
        name.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        name.textColor = Constants.Colors.label
        name.numberOfLines = 2
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.8

        let pin = UIImageView(image: UIImage(systemName: "mappin.and.ellipse"))
        pin.tintColor = Constants.Colors.secondaryLabel
        pin.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        pin.setContentHuggingPriority(.required, for: .horizontal)
        let address = UILabel()
        address.text = place.address
        address.font = UIFont.systemFont(ofSize: 15)
        address.textColor = Constants.Colors.secondaryLabel
        address.numberOfLines = 2
        let addressRow = UIStackView(arrangedSubviews: [pin, address])
        addressRow.axis = .horizontal
        addressRow.alignment = .firstBaseline
        addressRow.spacing = 5

        let words = UIStackView(arrangedSubviews: [name, addressRow])
        words.axis = .vertical
        words.spacing = 4
        let hero = UIStackView(arrangedSubviews: [tile, words])
        hero.axis = .horizontal
        hero.alignment = .top
        hero.spacing = 14
        return hero
    }()

    // Rating: outlined pill = what they said last time (own save only —
    // someone else's copy carries their score, not ours)
    private lazy var ratingPills = RatingPillsView(currentRating: place.isAddedByCurrentUser ? place.userRating : nil,
                                                   unselectedBackground: .tertiarySystemFill)

    private let notePlaceholder = "Say something about this visit (optional)"
    private lazy var noteTextView: UITextView = {
        let view = UITextView()
        view.font = UIFont.systemFont(ofSize: 16)
        view.textColor = Constants.Colors.secondaryLabel
        view.text = notePlaceholder
        // The card is the box: no fill or border of its own
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 14, left: 11, bottom: 12, right: 11)
        view.delegate = self
        view.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return view
    }()

    /// Off until there is something to post. The comment box is optional, so
    /// defaulting this on offered to publish a comment nobody had written.
    /// Typing turns it on, clearing turns it back off — until the person
    /// touches the switch themselves, after which it is theirs.
    private lazy var postOnPlaceSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = false
        toggle.onTintColor = Constants.Colors.primary
        toggle.addTarget(self, action: #selector(postOnPlaceChanged), for: .valueChanged)
        return toggle
    }()
    private var postOnPlaceSetByHand = false

    private lazy var notifyButton: IconRowButton = {
        let button = IconRowButton(systemName: "bell.badge.fill", tint: Constants.Colors.accent, title: "Notify people")
        button.addTarget(self, action: #selector(notifyTapped), for: .touchUpInside)
        return button
    }()
    /// The line between the two rows of the share card; goes with the notify row
    private let shareDivider = CheckInComposeViewController.hairline()

    /// Who this check-in is for. Connections is the historic default; a named
    /// Inner Circle list narrows it; Followers widens it to all your followers,
    /// past the account's activity grid (Wes, 2026-09-25: "some like being
    /// public"; never past followers since 2026-11-02). Just me is a private record: no feed, no
    /// notifications, no comment. This replaced the separate feed switch and
    /// "Just me" button (Wes, 2026-09-28) — one question, one answer.
    /// Opens on the user's saved default (CheckInAudienceChoice), which they
    /// set from the bottom of the same menu (Wes, 2026-10-08).
    private typealias Audience = CheckInAudienceChoice
    private lazy var selectedAudience: Audience = .initial(
        saved: Self.savedDefault,
        listIds: InnerCircleManager.shared.hasLoaded ? InnerCircleManager.shared.usableLists.map(\.id) : nil)
    private var selectedListId: String? {
        if case .list(let id) = selectedAudience { return id }
        return nil
    }
    private lazy var audienceButton: IconRowButton = {
        let button = IconRowButton(systemName: "person.2.fill", tint: Constants.Colors.primary, title: "Who's it for?")
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private lazy var checkInButton: UIButton = {
        // Same icon as every check-in surface (UIImage.checkInIcon), next to the words
        let button = UIButton.primaryButton(title: "  Check In")
        button.setImage(.checkInIcon?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = .white
        button.layer.shadowColor = Constants.Colors.primary.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        return button
    }()
    private var postOnPlaceRow: UIView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Check In"
        view.backgroundColor = Constants.Colors.background
        // The bar stays out of the way of the photo
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        if hasPhoto {
            // The title sits on the photo: white with a little shadow, in either mode
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            shadow.shadowBlurRadius = 4
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .shadow: shadow]
        }
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        }
        setupUI()
        setupKeyboardHandling(scrollView: scrollView, dismissOnTap: true)
        updateNotifyTitle()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
    }

    private func setupUI() {
        let footer = UIStackView(arrangedSubviews: [checkInButton])
        footer.axis = .vertical
        footer.translatesAutoresizingMaskIntoConstraints = false
        checkInButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        checkInButton.addTarget(self, action: #selector(checkInTapped), for: .touchUpInside)

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        backdrop.showPhoto(from: place.photos?.first)
        view.addSubview(scrollView)
        view.addSubview(footer)
        scrollView.addSubview(contentStack)
        scrollView.delegate = self

        contentStack.addArrangedSubview(placeHero)
        contentStack.setCustomSpacing(24, after: placeHero)
        // Three cards: the rating, the note (with its comment switch), who hears
        contentStack.addArrangedSubview(card(section("How was it?", ratingPills), inset: 16))
        let commentRow = switchRow("Also post as a comment", postOnPlaceSwitch)
        postOnPlaceRow = commentRow
        let noteStack = UIStackView(arrangedSubviews: [noteTextView, Self.hairline(), commentRow])
        noteStack.axis = .vertical
        noteStack.spacing = 0
        noteStack.setCustomSpacing(12, after: noteStack.arrangedSubviews[1])
        noteStack.isLayoutMarginsRelativeArrangement = true
        noteStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0)
        contentStack.addArrangedSubview(card(noteStack, inset: 0, horizontalInset: 14))
        let shareStack = UIStackView(arrangedSubviews: [notifyButton, shareDivider, audienceButton])
        shareStack.axis = .vertical
        contentStack.addArrangedSubview(card(shareStack, inset: 2, horizontalInset: 2))
        // Lists may still be loading when this screen opens; the menu is
        // rebuilt when they arrive.
        refreshAudienceMenu()
        InnerCircleManager.shared.primeIfNeeded { [weak self] in
            DispatchQueue.main.async { self?.refreshAudienceMenu() }
        }
        RewardsService.shared.getVenueByPlace(placeId: place.globalPlaceId ?? place.id,
                                              googlePlaceId: place.googlePlaceId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let data) = result { self?.venueRewards = data }
            }
        }

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            // Under the photo band when there is one, so the place's picture is the opener
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: hasPhoto ? 150 : 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            footer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    /// A card's title with "Optional" at the right, then its content
    private func section(_ title: String, _ content: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = Constants.Colors.label
        let optional = UILabel()
        optional.text = "Optional"
        optional.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        optional.textColor = Constants.Colors.tertiaryLabel
        optional.setContentHuggingPriority(.required, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [label, optional])
        header.axis = .horizontal
        header.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [header, content])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    /// A lifted card on the wash (the first-run screens' idiom): slightly
    /// translucent so the photo and the gradient show through its edges
    private func card(_ content: UIView, inset: CGFloat, horizontalInset: CGFloat? = nil) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.94)
        card.layer.cornerRadius = 18
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 3)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        let side = horizontalInset ?? inset
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: side),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -side)
        ])
        return card
    }

    private static func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = Constants.Colors.separator
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func switchRow(_ title: String, _ toggle: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [toggle, label])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private var noteText: String {
        let text = noteTextView.text ?? ""
        return text == notePlaceholder ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Followers, connections, one per named list, then Just me. A menu
    /// rather than a switch because there is no longer a single Inner
    /// Circle to be "only".
    private func refreshAudienceMenu() {
        let lists = InnerCircleManager.shared.usableLists
        // A list that went away (deleted, or everyone removed) must not stay
        // selected: it would send an audience nobody is on. Only once the
        // lists have loaded — before that a saved Inner Circle default would
        // look "gone".
        if InnerCircleManager.shared.hasLoaded, let id = selectedListId, !lists.contains(where: { $0.id == id }) {
            selectedAudience = .connections
        }
        // Activity reaches only people who follow you (Wes, 2026-11-02)
        let everyone = UIAction(title: "Followers",
                                subtitle: "Your followers and connections",
                                state: selectedAudience == .everyone ? .on : .off) { [weak self] _ in
            self?.selectedAudience = .everyone
            self?.refreshAudienceMenu()
        }
        let connections = UIAction(title: "My connections",
                                   subtitle: "People you're connected with",
                                   state: selectedAudience == .connections ? .on : .off) { [weak self] _ in
            self?.selectedAudience = .connections
            self?.refreshAudienceMenu()
        }
        let justMe = UIAction(title: "Just me",
                              subtitle: "Only you — kept in your own history",
                              image: UIImage(systemName: "lock.fill"),
                              state: selectedAudience == .justMe ? .on : .off) { [weak self] _ in
            self?.selectedAudience = .justMe
            self?.refreshAudienceMenu()
        }
        let listActions = lists.map { list in
            UIAction(title: list.name,
                     subtitle: list.userIds.count == 1 ? "1 person" : "\(list.userIds.count) people",
                     state: selectedListId == list.id ? .on : .off) { [weak self] _ in
                self?.selectedAudience = .list(list.id)
                self?.refreshAudienceMenu()
            }
        }
        let title: String
        switch selectedAudience {
        case .justMe: title = "Just me"
        case .everyone: title = "Followers"
        case .connections: title = "My connections"
        case .list(let id): title = lists.first { $0.id == id }?.name ?? "My connections"
        }
        // No "make this my default" row: the last check-in's choice IS the
        // default (Wes, 2026-10-09: remember the last selection everywhere)
        audienceButton.menu = UIMenu(children: [
            UIMenu(options: .displayInline, children: [everyone, connections] + listActions + [justMe])
        ])
        audienceButton.value = title
        // A private check-in notifies nobody and posts no comment, so those
        // rows would only promise something that won't happen.
        let isPrivate = selectedAudience == .justMe
        notifyButton.isHidden = isPrivate
        shareDivider.isHidden = isPrivate
        postOnPlaceRow?.isHidden = isPrivate
    }

    // MARK: - Default audience

    private static var defaultKey: String { "checkInAudienceDefault.\(AuthService.shared.currentUser?.id ?? "")" }

    /// This device's copy first (written after each check-in), then the
    /// account's, so the last choice made on another phone still applies.
    private static var savedDefault: String? {
        UserDefaults.standard.string(forKey: defaultKey) ?? AuthService.shared.currentUser?.preferences?.checkInAudience
    }

    /// After a successful check-in: its audience opens the next one. Synced
    /// to the account only when it changed, so routine check-ins cost no call.
    private func rememberAudience() {
        let value = selectedAudience.storedValue
        guard value != Self.savedDefault else { return }
        UserDefaults.standard.set(value, forKey: Self.defaultKey)
        UserService.shared.updateUserPreferences(checkInAudience: value) { result in
            if case .success(let user) = result { DispatchQueue.main.async { AuthService.shared.updateCurrentUser(user) } }
        }
    }

    private func updateNotifyTitle() {
        let count = selectedGroups.count + selectedUsers.count
        if count == 0 {
            notifyButton.value = "Optional"
        } else {
            let people = selectedUsers.count
            let groups = selectedGroups.count
            var parts: [String] = []
            if people > 0 { parts.append("\(people) \(people == 1 ? "person" : "people")") }
            if groups > 0 { parts.append("\(groups) \(groups == 1 ? "group" : "groups")") }
            notifyButton.value = parts.joined(separator: " and ")
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        (navigationController ?? self).dismiss(animated: true)
    }

    @objc private func notifyTapped() {
        view.endEditing(true)
        let picker = CheckInRecipientSelectionViewController()
        picker.initialGroups = selectedGroups
        picker.initialUsers = selectedUsers
        picker.onPick = { [weak self] groups, users in
            self?.selectedGroups = groups
            self?.selectedUsers = users
            self?.updateNotifyTitle()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func postOnPlaceChanged() { postOnPlaceSetByHand = true }

    @objc private func checkInTapped() {
        view.endEditing(true)
        let isPrivate = selectedAudience == .justMe
        var data: [String: Any] = [
            "message": noteText,
            "showInActivityFeed": !isPrivate,
            "isPrivate": isPrivate,
            "notifiedGroups": isPrivate ? [] : Array(selectedGroups),
            "notifiedUsers": isPrivate ? [] : Array(selectedUsers),
            // A note on a public check-in is also a comment on the place
            "postComment": isPrivate ? false : postOnPlaceSwitch.isOn
        ]
        if !isPrivate {
            switch selectedAudience {
            case .everyone:
                data["audience"] = "public"
            case .list(let id):
                data["audience"] = "innerCircle"
                data["audienceListId"] = id
            case .connections, .justMe:
                break
            }
        }
        if let rating = ratingPills.selectedRating { data["rating"] = rating }
        // No duration: the server's two-hour default applies

        // Place: a resolved POI that isn't saved yet has an empty circleId —
        // the backend creates the save from name/address/coordinates. A saved
        // place is referenced by id (the backend re-resolves someone else's
        // copy to our own save or check-in circle).
        let isNewPlace = place.circleId?.isEmpty ?? true
        data["placeName"] = place.name
        data["placeAddress"] = place.address
        data["placeCategory"] = place.category.rawValue
        if let location = place.location?.clLocation {
            data["latitude"] = location.coordinate.latitude
            data["longitude"] = location.coordinate.longitude
        }
        if !isNewPlace {
            data["placeId"] = place.id
            if let circleId = place.circleId { data["circleId"] = circleId }
        }

        let loading = showLoading(message: "Checking in...")
        checkInButton.isEnabled = false
        // The rating row above already asked; no second prompt afterwards,
        // even when it was left blank
        CheckInService.shared.createCheckIn(data, offersRatingAfterward: false) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.checkInButton.isEnabled = true
                    switch result {
                    case .success(let created):
                        self.rememberAudience()
                        var message = isPrivate ? "Checked in privately — no one was notified." : "You're checked in!"
                        if let count = created.stats?.count, count > 1 {
                            message = "You're checked in\(isPrivate ? " privately" : ""). That's your \(CheckInHistoryFormatter.ordinal(count)) time here!"
                        }
                        self.confirmCheckIn(message)
                    case .failure(let error):
                        self.showError(FriendlyError.message(for: error))
                    }
                }
            }
        }
    }
}

// MARK: - The photo drifts as the page scrolls
extension CheckInComposeViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        backdrop.follow(scrollOffset: scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
}

// MARK: - Placeholder handling for the note
extension CheckInComposeViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == notePlaceholder {
            textView.text = ""
            textView.textColor = Constants.Colors.label
        }
    }

    /// Writing something is the only reason to post it, so the switch
    /// follows the box — until the person overrides it by hand.
    func textViewDidChange(_ textView: UITextView) {
        guard !postOnPlaceSetByHand else { return }
        let hasText = !noteText.isEmpty
        if postOnPlaceSwitch.isOn != hasText { postOnPlaceSwitch.setOn(hasText, animated: true) }
    }

    /// Matches the server cap; the note doubles as a place comment
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text == notePlaceholder ? "" : (textView.text ?? "")
        guard let swiftRange = Range(range, in: current) else { return true }
        return current.replacingCharacters(in: swiftRange, with: text).count <= 500
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = notePlaceholder
            textView.textColor = Constants.Colors.secondaryLabel
        }
    }
}

// MARK: - Rewards nudge

extension CheckInComposeViewController {
    /// The check-in confirmation. At a store with rewards it also says how to
    /// collect them — the check-in itself earns nothing; the register scan
    /// is the proof of purchase — and offers the Get Rewards page.
    fileprivate func confirmCheckIn(_ message: String) {
        // The store's rewards are fetched when this screen opens; a quick
        // check-in could beat that fetch and skip the reminder (Wes,
        // 2026-10-30: check-ins at a rewards store must say to scan the
        // register code). Ask now if it hasn't answered yet.
        guard venueRewards != nil else {
            RewardsService.shared.getVenueByPlace(placeId: place.globalPlaceId ?? place.id,
                                                  googlePlaceId: place.googlePlaceId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let data) = result { self.venueRewards = data }
                    self.showCheckInConfirmation(message)
                }
            }
            return
        }
        showCheckInConfirmation(message)
    }

    private func showCheckInConfirmation(_ message: String) {
        let host = navigationController ?? self
        guard let details = RewardsAvailability(venueRewards).details,
              let rewards = GetRewardsViewController(place: place, data: venueRewards) else {
            // Never a dead end (2026-11-02): a moment from here, or their check-ins
            let leave = { (then: @escaping () -> Void) in host.dismiss(animated: true, completion: then) }
            AlertPresenter.showDone(
                title: message, message: nil,
                steps: [(.postMoment, { leave { NextStepNavigator.postMoment() } }),
                        (.myCheckIns, { leave { NextStepNavigator.checkIns() } })],
                surface: "check_in", from: self, onDone: { host.dismiss(animated: true) })
            return
        }
        showConfirmation(
            title: message,
            message: RewardsAvailability.checkInNudge(details),
            confirmTitle: "Get Rewards",
            cancelTitle: "Done",
            onConfirm: {
                let presenter = host.presentingViewController
                host.dismiss(animated: true) {
                    presenter?.present(UINavigationController(rootViewController: rewards), animated: true)
                }
            },
            onCancel: { host.dismiss(animated: true) }
        )
    }
}

import UIKit

/// The check-in screen once the place is known: one tap on Check In is a
/// complete check-in (feed on, connections see it, two-hour window). Every
/// other field is visible and optional — a rating, a note that also lands on
/// the place as a comment, people to notify, how long, the feed switch —
/// and "Just me" makes it a private record with one tap.
final class CheckInComposeViewController: BaseViewController {

    private let place: Place
    private var selectedGroups: Set<String> = []
    private var selectedUsers: Set<String> = []

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

    private lazy var placeCard: UIView = {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 12
        let name = UILabel()
        name.text = place.name
        name.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        name.textColor = Constants.Colors.label
        name.numberOfLines = 2
        let address = UILabel()
        address.text = place.address
        address.font = UIFont.systemFont(ofSize: 14)
        address.textColor = Constants.Colors.secondaryLabel
        address.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [name, address])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }()

    // Rating: outlined pill = what they said last time (own save only —
    // someone else's copy carries their score, not ours)
    private lazy var ratingPills = RatingPillsView(currentRating: place.isAddedByCurrentUser ? place.userRating : nil)

    private let notePlaceholder = "Say something about this visit (optional)"
    private lazy var noteTextView: UITextView = {
        let view = UITextView()
        view.font = UIFont.systemFont(ofSize: 16)
        view.textColor = Constants.Colors.secondaryLabel
        view.text = notePlaceholder
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.delegate = self
        view.heightAnchor.constraint(equalToConstant: 96).isActive = true
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

    private lazy var notifyButton: UIButton = {
        let button = UIButton.fieldButton()
        button.addTarget(self, action: #selector(notifyTapped), for: .touchUpInside)
        return button
    }()

    private let durationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["30 min", "1 hour", "2 hours", "Until I leave"])
        control.selectedSegmentIndex = UISegmentedControl.noSegment
        return control
    }()

    private lazy var feedSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.onTintColor = Constants.Colors.primary
        return toggle
    }()

    /// Which audience this check-in is for: everyone you're connected with,
    /// or one of your named Inner Circle lists. A list is a ceiling the
    /// server enforces, so it holds even with "Show in activity feed" on —
    /// that switch decides where it appears, not who may see it.
    private var selectedListId: String?
    private var audienceSection: UIView?
    private lazy var audienceButton: UIButton = {
        let button = UIButton.menuFieldButton()
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return button
    }()

    private lazy var checkInButton: UIButton = {
        // Same icon as every check-in surface (UIImage.checkInIcon), next to the words
        let button = UIButton.primaryButton(title: "  Check In")
        button.setImage(.checkInIcon?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = .white
        return button
    }()
    private lazy var privateButton = UIButton.secondaryButton(title: "Just me — check in privately")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Check In"
        view.backgroundColor = Constants.Colors.background
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
        let footer = UIStackView(arrangedSubviews: [checkInButton, privateButton])
        footer.axis = .vertical
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        checkInButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        checkInButton.addTarget(self, action: #selector(checkInTapped), for: .touchUpInside)
        privateButton.addTarget(self, action: #selector(privateTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        view.addSubview(footer)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(placeCard)
        contentStack.addArrangedSubview(section("How was it? (optional)", ratingPills))
        contentStack.addArrangedSubview(noteTextView)
        contentStack.addArrangedSubview(switchRow("Also post as a comment", postOnPlaceSwitch))
        contentStack.addArrangedSubview(notifyButton)
        contentStack.addArrangedSubview(section("How long? (optional)", durationControl))
        contentStack.addArrangedSubview(switchRow("Show in activity feed", feedSwitch, info: #selector(feedInfoTapped)))
        // Only worth offering once there is a list with someone on it; an
        // empty one is indistinguishable from the private button below. The
        // row is built either way and hidden until the lists arrive, because
        // they may still be loading when this screen opens.
        audienceSection = section("Who's it for?", audienceButton)
        contentStack.addArrangedSubview(audienceSection!)
        refreshAudienceMenu()
        InnerCircleManager.shared.primeIfNeeded { [weak self] in
            DispatchQueue.main.async { self?.refreshAudienceMenu() }
        }
        contentStack.setCustomSpacing(8, after: noteTextView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func section(_ title: String, _ content: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        let stack = UIStackView(arrangedSubviews: [label, content])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    /// A switch and its label, and — when the setting has consequences worth
    /// explaining — an "i" at the end of the row that says what they are.
    private func switchRow(_ title: String, _ toggle: UISwitch, info: Selector? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [toggle, label])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        if let info {
            let button = UIButton.iconButton(systemName: "info.circle", pointSize: 17)
            button.tintColor = Constants.Colors.secondaryLabel
            button.accessibilityLabel = "What does \(title) mean?"
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.addTarget(self, action: info, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private var noteText: String {
        let text = noteTextView.text ?? ""
        return text == notePlaceholder ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One entry for everyone, then one per named list. A menu rather than a
    /// switch because there is no longer a single Inner Circle to be "only".
    private func refreshAudienceMenu() {
        let lists = InnerCircleManager.shared.usableLists
        audienceSection?.isHidden = lists.isEmpty
        // A list that went away (deleted, or everyone removed) must not stay
        // selected: it would send an audience nobody is on.
        if let id = selectedListId, !lists.contains(where: { $0.id == id }) { selectedListId = nil }
        guard !lists.isEmpty else { return }
        let everyone = UIAction(title: "Everyone in my circles",
                                subtitle: "People you're connected with",
                                state: selectedListId == nil ? .on : .off) { [weak self] _ in
            self?.selectedListId = nil
            self?.refreshAudienceMenu()
        }
        let listActions = lists.map { list in
            UIAction(title: list.name,
                     subtitle: list.userIds.count == 1 ? "1 person" : "\(list.userIds.count) people",
                     state: selectedListId == list.id ? .on : .off) { [weak self] _ in
                self?.selectedListId = list.id
                self?.refreshAudienceMenu()
            }
        }
        audienceButton.menu = UIMenu(children: [everyone] + listActions)
        let name = lists.first { $0.id == selectedListId }?.name
        audienceButton.setTitle("\(name ?? "Everyone in my circles")  ›", for: .normal)
        audienceButton.setTitleColor(Constants.Colors.label, for: .normal)
    }

    private func updateNotifyTitle() {
        let count = selectedGroups.count + selectedUsers.count
        let detail: String
        if count == 0 {
            detail = "Notify people (optional)  ›"
        } else {
            let people = selectedUsers.count
            let groups = selectedGroups.count
            var parts: [String] = []
            if people > 0 { parts.append("\(people) \(people == 1 ? "person" : "people")") }
            if groups > 0 { parts.append("\(groups) \(groups == 1 ? "group" : "groups")") }
            detail = "Notifying \(parts.joined(separator: " and "))  ›"
        }
        notifyButton.setTitle(detail, for: .normal)
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

    /// Says exactly who ends up seeing this, because "activity feed" on its
    /// own does not tell anyone whether that means followers, connections or
    /// the world.
    @objc private func feedInfoTapped() {
        view.endEditing(true)
        AlertPresenter.showInfo(
            title: "Who sees this check-in?",
            message: """
            On: people you're connected with see it in their activity feed. Not your followers, and not the public.

            Anyone you choose under "Notify people" sees it either way.

            Pick one of your Inner Circle lists under "Who's it for?" and it stops there — turning this on can't widen it.

            Off, with nobody notified: it's yours alone, kept in your own history here.
            """,
            from: self
        )
    }

    @objc private func checkInTapped() { submit(isPrivate: false) }
    @objc private func privateTapped() { submit(isPrivate: true) }

    private func submit(isPrivate: Bool) {
        view.endEditing(true)
        var data: [String: Any] = [
            "message": noteText,
            "showInActivityFeed": isPrivate ? false : feedSwitch.isOn,
            "isPrivate": isPrivate,
            "notifiedGroups": isPrivate ? [] : Array(selectedGroups),
            "notifiedUsers": isPrivate ? [] : Array(selectedUsers),
            // A note on a public check-in is also a comment on the place
            "postComment": isPrivate ? false : postOnPlaceSwitch.isOn
        ]
        if !isPrivate, let selectedListId {
            data["audience"] = "innerCircle"
            data["audienceListId"] = selectedListId
        }
        if let rating = ratingPills.selectedRating { data["rating"] = rating }
        // Duration is optional: nothing picked = the server's two-hour default
        let durations = ["30", "60", "120", "until_leave"]
        if durationControl.selectedSegmentIndex != UISegmentedControl.noSegment {
            data["duration"] = durations[durationControl.selectedSegmentIndex]
        }

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
        privateButton.isEnabled = false
        APIService.shared.createCheckIn(data) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    self.checkInButton.isEnabled = true
                    self.privateButton.isEnabled = true
                    switch result {
                    case .success(let created):
                        var message = isPrivate ? "Checked in privately — no one was notified." : "You're checked in!"
                        if let count = created.stats?.count, count > 1 {
                            message = "You're checked in\(isPrivate ? " privately" : ""). That's your \(CheckInHistoryFormatter.ordinal(count)) time here!"
                        }
                        self.showSuccess(message) {
                            (self.navigationController ?? self).dismiss(animated: true)
                        }
                    case .failure(let error):
                        self.showError("Failed to check in: \(error.localizedDescription)")
                    }
                }
            }
        }
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

import UIKit

/// My Network → My People → Inner Circles: your inner circles as circles.
///
/// Each list is a ring with its name in the middle and the people on it as
/// faces around it. Everything the Settings screens do is here: start a
/// circle, rename or delete it, add people, take someone off. Both surfaces
/// edit through `InnerCircleEditing`, so the warnings (deleting a list takes
/// back what those people could see) read the same in both.
///
/// The rings are a picture of the lists, not the lists: a long list shows
/// some faces and "+N". Every save is built from the list's whole membership
/// as `InnerCircleManager` holds it, never from the faces on screen.
final class InnerCirclesVisualViewController: BaseViewController {

    /// Only while there is nothing to show yet
    override var showsLoadingIndicator: Bool { !hasLists }
    override var enablesPullToRefresh: Bool { true }

    private let backdrop = FirstRunBackdropView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var lists: [InnerCircleNamedList] = []
    private var maxLists = 20
    private var maxSize = InnerCircleList.empty.maxSize

    /// What is drawn now, so a refresh that changed nothing redraws nothing
    private var drawn: (lists: [InnerCircleNamedList], width: CGFloat, failed: Bool)?
    private var loadFailed = false
    private var hasLists = false
    private var changeObserver: NSObjectProtocol?

    // MARK: - The ⓘ

    /// What inner circles are for, in Wes's words (2026-11-23). Shown from
    /// the ⓘ beside the Connections | Following | Inner Circles tabs.
    static func presentExplainer(from viewController: UIViewController) {
        AlertPresenter.showInfo(
            title: "Inner Circles",
            message: """
            Your network is personal. Treat it that way. FavCircles.

            Who you keep in your inner circle defines you. Define it and stay in control of who influences you. FavCircles.
            """,
            from: viewController
        )
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        // Whatever the app already knows shows first, with no spinner over
        // it (the base class spins only until there is something to show);
        // loadData then refreshes it.
        if InnerCircleManager.shared.hasLoaded {
            let known = InnerCircleManager.shared.list
            lists = known.lists ?? []
            maxLists = known.maxLists ?? maxLists
            maxSize = known.maxSize
            hasLists = true
        }
        super.viewDidLoad()

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.refreshControl = refreshControl
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(backdrop)
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16)
        ])

        // Every write anywhere (the Settings screens, a privacy picker's
        // "Edit list", the member list pushed from a ring) lands in the
        // manager; mirror it here at once.
        changeObserver = NotificationCenter.default.addObserver(forName: .innerCircleDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, InnerCircleManager.shared.hasLoaded else { return }
            self.apply(InnerCircleManager.shared.list)
        }
        render()
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ring size follows the width (rotation, iPad split view)
        if let drawn, abs(drawn.width - view.bounds.width) > 0.5 { render() }
    }

    override func loadData(completion: (() -> Void)? = nil) {
        InnerCircleService.shared.getLists { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let list):
                    self.apply(list)
                case .failure(let error):
                    // A failed refresh never replaces what is showing with
                    // nothing; only a first load with no lists says so.
                    let duplicate = error.localizedDescription.contains("Duplicate request prevented")
                    if !self.hasLists && !duplicate {
                        self.loadFailed = true
                        self.render()
                    }
                }
                completion?()
            }
        }
    }

    private func apply(_ list: InnerCircleList) {
        lists = list.lists ?? []
        maxLists = list.maxLists ?? maxLists
        maxSize = list.maxSize
        hasLists = true
        loadFailed = false
        render()
    }

    /// The list as it stands now — a ring may have been drawn before a write
    /// elsewhere changed it.
    private func current(_ listId: String) -> InnerCircleNamedList? {
        lists.first { $0.id == listId }
    }

    // MARK: - Drawing

    private func render() {
        guard isViewLoaded, hasLists || loadFailed else { return }
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        if let drawn, drawn.lists == lists, drawn.failed == loadFailed, abs(drawn.width - width) <= 0.5 { return }
        drawn = (lists, width, loadFailed)

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if loadFailed {
            stack.addArrangedSubview(makeFailureState())
        } else if lists.isEmpty {
            stack.addArrangedSubview(makeFirstCircleState(width: width))
        } else {
            stack.addArrangedSubview(makeHeader())
            // Card = 16 pt page margin + 14 pt card padding each side
            let diameter = min(max(width - 60, 200), 320)
            for list in lists {
                stack.addArrangedSubview(makeCard(for: list, diameter: diameter))
            }
            if lists.count < maxLists {
                let new = NewInnerCircleControl(diameter: 124, title: "New inner circle")
                new.addTarget(self, action: #selector(newCircleTapped), for: .touchUpInside)
                stack.setCustomSpacing(26, after: stack.arrangedSubviews.last ?? stack)
                stack.addArrangedSubview(new)
            } else {
                stack.addArrangedSubview(makeCaption("You can keep up to \(maxLists) lists."))
            }
        }
    }

    private func makeHeader() -> UIView {
        let title = UILabel()
        title.text = "Your network is personal."
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = Constants.Colors.label
        title.textAlignment = .center
        title.numberOfLines = 0

        let hint = makeCaption("Tap + to add someone. Tap a face to see them or take them off. Tap the middle for everyone.")

        let header = UIStackView(arrangedSubviews: [title, hint])
        header.axis = .vertical
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }

    private func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    /// One circle: the ring on a soft card, with its ••• menu in the corner.
    private func makeCard(for list: InnerCircleNamedList, diameter: CGFloat) -> UIView {
        let card = UIView()
        card.backgroundColor = Constants.Colors.background.withAlphaComponent(0.72)
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        let ring = InnerCircleRingView(list: list, maxSize: maxSize, diameter: diameter)
        ring.delegate = self

        let more = UIButton.iconButton(systemName: "ellipsis.circle", pointSize: 20)
        more.tintColor = Constants.Colors.primary
        more.accessibilityLabel = "More for \(list.name)"
        more.showsMenuAsPrimaryAction = true
        more.menu = makeMenu(for: list)

        card.addSubview(ring)
        card.addSubview(more)
        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            ring.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            ring.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: diameter + 28),

            more.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            more.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            more.widthAnchor.constraint(equalToConstant: 40),
            more.heightAnchor.constraint(equalToConstant: 40)
        ])
        return card
    }

    private func makeMenu(for list: InnerCircleNamedList) -> UIMenu {
        let id = list.id
        let add = UIAction(title: "Add or remove people", image: UIImage(systemName: "person.badge.plus")) { [weak self] _ in
            self?.editPeople(listId: id)
        }
        let everyone = UIAction(title: "See everyone", image: UIImage(systemName: "person.2")) { [weak self] _ in
            self?.showEveryone(listId: id)
        }
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.rename(listId: id)
        }
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.delete(listId: id)
        }
        return UIMenu(children: [add, everyone, rename, delete])
    }

    /// No circles yet: the page is one big empty circle asking to be started.
    private func makeFirstCircleState(width: CGFloat) -> UIView {
        let title = UILabel()
        title.text = "Your network is personal.\nTreat it that way."
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = Constants.Colors.label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = makeCaption("An inner circle is a few of your connections you name — Family, Gym crew, Work. Share a place, a circle, a moment or a check-in with just them.")
        body.font = .systemFont(ofSize: 15)

        let hero = NewInnerCircleControl(diameter: min(max(width - 140, 180), 240), title: "Start your first\ninner circle")
        hero.addTarget(self, action: #selector(newCircleTapped), for: .touchUpInside)

        let button = UIButton.primaryButton(title: "New inner circle")
        button.addTarget(self, action: #selector(newCircleTapped), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: min(width - 64, 320)).isActive = true

        let state = UIStackView(arrangedSubviews: [title, body, hero, button])
        state.axis = .vertical
        state.alignment = .center
        state.spacing = 16
        state.setCustomSpacing(24, after: body)
        state.setCustomSpacing(24, after: hero)
        state.translatesAutoresizingMaskIntoConstraints = false
        return state
    }

    private func makeFailureState() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)))
        icon.tintColor = Constants.Colors.primary

        let title = UILabel()
        title.text = "Couldn't load your inner circles"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = Constants.Colors.label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = makeCaption("Check your connection and try again.")
        body.font = .systemFont(ofSize: 15)

        let retry = UIButton.secondaryButton(title: "Try again")
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retry.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let state = UIStackView(arrangedSubviews: [icon, title, body, retry])
        state.axis = .vertical
        state.alignment = .center
        state.spacing = 12
        state.setCustomSpacing(20, after: body)
        state.translatesAutoresizingMaskIntoConstraints = false
        state.layoutMargins = UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0)
        state.isLayoutMarginsRelativeArrangement = true
        return state
    }

    // MARK: - Editing (the same five things Settings does)

    @objc private func retryTapped() {
        refreshData()
    }

    @objc private func newCircleTapped() {
        InnerCircleEditing.promptNewList(existingCount: lists.count, maxLists: maxLists, from: self) { [weak self] list, created in
            guard let self else { return }
            self.apply(list)
            // Straight into choosing who is in it: an empty circle is the
            // same as Private, and nobody means to make one of those.
            self.editPeople(listId: created.id)
        }
    }

    private func editPeople(listId: String) {
        guard let list = current(listId) else { return }
        InnerCircleEditing.presentPeoplePicker(listName: list.name, currentMembers: list.users, maxSize: maxSize, from: self) { [weak self] userIds in
            guard let self else { return }
            InnerCircleEditing.setMembers(listId: listId, userIds: userIds, from: self) { [weak self] list in
                self?.apply(list)
            }
        }
    }

    private func remove(_ person: User, fromListId listId: String) {
        guard let list = current(listId) else { return }
        InnerCircleEditing.confirmRemove(person, listName: list.name, from: self) { [weak self] in
            // From the list as it stands at the moment of saving, in full
            guard let self, let latest = self.current(listId) else { return }
            let userIds = InnerCircleRingLayout.membersAfterRemoving(person.id, from: latest.userIds)
            InnerCircleEditing.setMembers(listId: listId, userIds: userIds, from: self) { [weak self] list in
                self?.apply(list)
            }
        }
    }

    private func showEveryone(listId: String) {
        guard let list = current(listId) else { return }
        navigationController?.pushViewController(InnerCircleListViewController(list: list), animated: true)
    }

    private func rename(listId: String) {
        guard let list = current(listId) else { return }
        InnerCircleEditing.promptRename(listId: listId, currentName: list.name, from: self) { [weak self] list in
            self?.apply(list)
        }
    }

    private func delete(listId: String) {
        guard let list = current(listId) else { return }
        InnerCircleEditing.confirmDelete(list, from: self) { [weak self] list in
            self?.apply(list)
        }
    }
}

// MARK: - InnerCircleRingViewDelegate

extension InnerCirclesVisualViewController: InnerCircleRingViewDelegate {
    func ringViewDidTapAdd(_ ringView: InnerCircleRingView) {
        editPeople(listId: ringView.list.id)
    }

    func ringViewDidTapSeeEveryone(_ ringView: InnerCircleRingView) {
        showEveryone(listId: ringView.list.id)
    }

    func ringView(_ ringView: InnerCircleRingView, didTap person: User, from sourceView: UIView) {
        let listId = ringView.list.id
        let listName = current(listId)?.name ?? ringView.list.name
        AlertPresenter.showActionSheet(
            title: person.displayName,
            actions: [
                ("View profile", .default, { [weak self] in
                    self?.navigationController?.pushViewController(ProfileViewController(user: person), animated: true)
                }),
                ("Remove from \(listName)", .destructive, { [weak self] in
                    self?.remove(person, fromListId: listId)
                })
            ],
            from: self,
            sourceView: sourceView
        )
    }
}

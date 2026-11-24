import UIKit

/// Who is on one Inner Circle list.
///
/// A list is reused by every circle, place, moment and check-in set to it.
/// Editing it here changes what those people can see everywhere, at once and
/// retroactively — the server judges access against the current list on every
/// read, so taking someone off takes back what they could already see. The
/// screen says so, because that is not obvious from a list of names.
class InnerCircleListViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }

    /// Which list. Nil edits the first one, which is what the screens that
    /// predate naming ask for.
    private let listId: String?
    private var listName: String
    private var members: [User] = []
    private var maxSize: Int = InnerCircleList.empty.maxSize

    /// A list just created: the people picker opens straight away, and
    /// Done (here or in the picker) goes back to the lists (Wes, 2026-10-02).
    private let isNew: Bool
    private var offeredPicker = false

    init(list: InnerCircleNamedList? = nil, isNew: Bool = false) {
        self.listId = list?.id
        self.listName = list?.name ?? "Inner Circle"
        self.isNew = isNew
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = listName
        view.backgroundColor = Constants.Colors.background

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Only a named list can be renamed; the legacy single list has no id.
        if listId != nil {
            let rename = UIBarButtonItem(title: "Rename", style: .plain, target: self, action: #selector(renameTapped))
            navigationItem.rightBarButtonItems = isNew
                ? [UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped)), rename]
                : [rename]
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew && !offeredPicker {
            offeredPicker = true
            addPeopleTapped()
        }
    }

    @objc private func doneTapped() {
        navigationController?.popViewController(animated: true)
    }

    override func loadData(completion: (() -> Void)? = nil) {
        InnerCircleService.shared.getLists { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.members = self.members(in: list)
                    self.maxSize = list.maxSize
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    // MARK: - Editing

    @objc private func renameTapped() {
        guard let listId else { return }
        InnerCircleEditing.promptRename(listId: listId, currentName: listName, from: self) { [weak self] list in
            guard let self else { return }
            self.listName = (list.lists ?? []).first { $0.id == listId }?.name ?? self.listName
            self.title = self.listName
            // Each row's menu says "Remove from <name>"
            self.tableView.reloadData()
        }
    }

    @objc private func addPeopleTapped() {
        InnerCircleEditing.presentPeoplePicker(listName: listName, currentMembers: members, maxSize: maxSize, from: self) { [weak self] userIds in
            self?.replaceList(with: userIds)
        }
    }

    /// The people on the list this screen is showing.
    private func members(in list: InnerCircleList) -> [User] {
        guard let listId else { return list.users }
        return (list.lists ?? []).first { $0.id == listId }?.users ?? []
    }

    private func replaceList(with userIds: [String]) {
        let loading = AlertPresenter.showLoading(message: "Saving…", from: self)
        let save: (@escaping (Result<InnerCircleList, Error>) -> Void) -> Void = { [listId] done in
            if let listId {
                InnerCircleService.shared.updateList(id: listId, userIds: userIds, completion: done)
            } else {
                InnerCircleService.shared.replace(userIds: userIds, completion: done)
            }
        }
        save { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let list):
                        self.members = self.members(in: list)
                        self.maxSize = list.maxSize
                        self.tableView.reloadData()
                        // A new list is finished once its people are chosen
                        if self.isNew { self.doneTapped() }
                    case .failure(let error):
                        // The server explains why (not a connection, over the
                        // cap); showError surfaces its wording verbatim.
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func viewProfile(_ person: User) {
        navigationController?.pushViewController(ProfileViewController(user: person), animated: true)
    }

    private func confirmRemove(_ person: User) {
        InnerCircleEditing.confirmRemove(person, listName: listName, from: self) { [weak self] in
            self?.remove(person)
        }
    }

    private func remove(_ person: User) {
        // Off THIS list. Removing them everywhere is what ending the
        // connection does; here they may well belong on another list.
        if listId != nil {
            replaceList(with: members.map { $0.id }.filter { $0 != person.id })
            return
        }
        InnerCircleService.shared.remove(userId: person.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.members = self.members(in: list)
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

extension InnerCircleListViewController: UITableViewDataSource, UITableViewDelegate {
    // 0: add, with what the tier means under it. 1: the members, each with
    // a ••• button for View profile / Remove (Wes, 2026-11-24: add at the
    // top, actions on the row).
    private enum Section: Int { case add, members }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == Section.members.rawValue ? members.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == Section.members.rawValue, !members.isEmpty else { return nil }
        return "\(members.count) of \(maxSize)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == Section.add.rawValue else { return nil }
        var text = "People here can see anything you set to Inner Circle — circles, places, moments and check-ins. "
            + "Only your connections can be added, and removing someone takes back what they could already see."
        if members.isEmpty {
            text += "\n\nUntil you add someone, Inner Circle shows the same thing Private does: only you."
        }
        return text
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Section.add.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: "add")
                ?? UITableViewCell(style: .default, reuseIdentifier: "add")
            var content = cell.defaultContentConfiguration()
            content.text = "Add people"
            content.image = UIImage(systemName: "plus.circle.fill")
            content.textProperties.color = Constants.Colors.primary
            content.imageProperties.tintColor = Constants.Colors.primary
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "member")
            ?? UITableViewCell(style: .default, reuseIdentifier: "member")
        let person = members[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = person.displayName
        content.image = UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        content.imageProperties.tintColor = Constants.Colors.primary.withAlphaComponent(0.4)
        cell.contentConfiguration = content
        cell.accessoryView = makeActionsButton(for: person)
        if let urlString = person.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak tableView] image in
                guard let image = image,
                      let cell = tableView?.cellForRow(at: indexPath) else { return }
                var updated = cell.defaultContentConfiguration()
                updated.text = person.displayName
                updated.image = image
                updated.imageProperties.maximumSize = CGSize(width: 34, height: 34)
                updated.imageProperties.cornerRadius = 17
                cell.contentConfiguration = updated
            }
        }
        return cell
    }

    /// The ••• on a member's row. Built fresh per row (cells are reused) and
    /// holding the person, not the row, since rows shift after a removal.
    private func makeActionsButton(for person: User) -> UIButton {
        let button = UIButton.iconButton(systemName: "ellipsis.circle", pointSize: 20)
        button.tintColor = Constants.Colors.primary
        // An accessory view is placed by frame, not Auto Layout
        button.translatesAutoresizingMaskIntoConstraints = true
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.accessibilityLabel = "More for \(person.displayName)"
        button.showsMenuAsPrimaryAction = true
        let profile = UIAction(title: "View profile", image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in
            self?.viewProfile(person)
        }
        let remove = UIAction(title: "Remove from \(listName)", image: UIImage(systemName: "person.badge.minus"),
                              attributes: .destructive) { [weak self] _ in
            self?.confirmRemove(person)
        }
        button.menu = UIMenu(children: [profile, remove])
        return button
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.add.rawValue {
            addPeopleTapped()
        } else {
            viewProfile(members[indexPath.row])
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard indexPath.section == Section.members.rawValue else { return nil }
        let person = members[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.confirmRemove(person)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

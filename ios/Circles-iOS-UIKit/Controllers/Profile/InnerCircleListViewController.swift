import UIKit

/// Manage the account-level Inner Circle list.
///
/// One list, reused by every circle, place, moment and check-in set to that
/// tier. Editing it here changes what those people can see everywhere, at once
/// and retroactively — the server judges access against the current list on
/// every read, so taking someone off takes back what they could already see.
/// The screen says so, because that is not obvious from a list of names.
class InnerCircleListViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }

    private var members: [User] = []
    private var maxSize: Int = InnerCircleList.empty.maxSize

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inner Circle"
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
    }

    override func loadData(completion: (() -> Void)? = nil) {
        InnerCircleService.shared.getList { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.members = list.users
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

    @objc private func addPeopleTapped() {
        let picker = TagPeoplePickerViewController()
        picker.title = "Add to Inner Circle"
        // Seeded with the current members so the picker is the whole list, not
        // an append-only box — people expect to be able to uncheck here too.
        picker.initialSelection = members.map {
            TaggedMomentUser(id: $0.id, displayName: $0.displayName, profilePicture: $0.profilePicture)
        }
        picker.selectionLimit = maxSize
        picker.limitMessage = "An Inner Circle can hold up to \(maxSize) people"
        picker.onDone = { [weak self] chosen in
            self?.replaceList(with: chosen.map { $0.id })
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func replaceList(with userIds: [String]) {
        let loading = AlertPresenter.showLoading(message: "Saving…", from: self)
        InnerCircleService.shared.replace(userIds: userIds) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let list):
                        self.members = list.users
                        self.maxSize = list.maxSize
                        self.tableView.reloadData()
                    case .failure(let error):
                        // The server explains why (not a connection, over the
                        // cap); showError surfaces its wording verbatim.
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func confirmRemove(_ person: User) {
        showConfirmation(
            title: "Remove \(person.displayName)?",
            message: "They'll stop seeing anything you've set to Inner Circle, including things they can see now.",
            confirmTitle: "Remove"
        ) { [weak self] in
            self?.remove(person)
        }
    }

    private func remove(_ person: User) {
        InnerCircleService.shared.remove(userId: person.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.members = list.users
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

extension InnerCircleListViewController: UITableViewDataSource, UITableViewDelegate {
    // 0: what the tier means. 1: the members. 2: add.
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 0
        case 1: return members.count
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return members.isEmpty ? nil : "\(members.count) of \(maxSize)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "People here can see anything you set to Inner Circle — circles, places, moments and check-ins. "
                + "Only your connections can be added, and removing someone takes back what they could already see."
        case 2:
            return members.isEmpty
                ? "Until you add someone, Inner Circle shows the same thing Private does: only you."
                : nil
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 2 {
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 { addPeopleTapped() }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let person = members[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.confirmRemove(person)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

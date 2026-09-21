import UIKit

/// The Inner Circle lists: family, the gym people, work.
///
/// One list was the original assumption and it was the wrong one — the people
/// you'd tell about a bar are not the people you'd tell about a hospital. A
/// list is picked wherever privacy is, so what is named here is what the rest
/// of the app offers.
///
/// Deleting a list is not a cosmetic act: anything set to it stops being
/// visible to those people immediately, because access is judged against the
/// lists as they are now, on every read. The confirmation says so.
final class InnerCircleListsViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }

    private var lists: [InnerCircleNamedList] = []
    private var maxLists: Int = 20
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
        InnerCircleService.shared.getLists { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let list):
                    self.apply(list)
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    private func apply(_ list: InnerCircleList) {
        lists = list.lists ?? []
        maxLists = list.maxLists ?? maxLists
        tableView.reloadData()
    }

    // MARK: - Making and unmaking lists

    private func newListTapped() {
        guard lists.count < maxLists else {
            showError("You can keep up to \(maxLists) lists.")
            return
        }
        AlertPresenter.showTextInput(
            title: "New list",
            message: "Name it for the people on it — Family, Gym crew, Work.",
            placeholder: "Name",
            confirmTitle: "Create",
            from: self
        ) { [weak self] name in
            guard let self, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            self.run("Creating…") { done in
                InnerCircleService.shared.createList(name: name, userIds: [], completion: done)
            } then: { [weak self] list in
                // Straight into choosing who is on it: an empty list is the
                // same as Private, and nobody means to make one of those.
                guard let self, let created = (list.lists ?? []).last else { return }
                self.navigationController?.pushViewController(InnerCircleListViewController(list: created), animated: true)
            }
        }
    }

    private func renameTapped(_ list: InnerCircleNamedList) {
        AlertPresenter.showTextInput(
            title: "Rename \(list.name)",
            message: nil,
            placeholder: "Name",
            initialText: list.name,
            confirmTitle: "Save",
            from: self
        ) { [weak self] name in
            guard let self, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            self.run("Saving…") { done in
                InnerCircleService.shared.updateList(id: list.id, name: name, completion: done)
            }
        }
    }

    private func confirmDelete(_ list: InnerCircleNamedList) {
        let people = list.userIds.count == 1 ? "1 person" : "\(list.userIds.count) people"
        showConfirmation(
            title: "Delete \(list.name)?",
            message: "Anything you've set to this list stops being visible to those \(people), including things they can see now. Nobody is removed from your connections.",
            confirmTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            self?.run("Deleting…") { done in
                InnerCircleService.shared.deleteList(id: list.id, completion: done)
            }
        }
    }

    /// Every write here is the same shape: a spinner, then the fresh lists or
    /// the server's own words about why not.
    private func run(_ message: String,
                     _ work: (@escaping (Result<InnerCircleList, Error>) -> Void) -> Void,
                     then next: ((InnerCircleList) -> Void)? = nil) {
        let loading = AlertPresenter.showLoading(message: message, from: self)
        work { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let list):
                        self.apply(list)
                        next?(list)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

extension InnerCircleListsViewController: UITableViewDataSource, UITableViewDelegate {
    // 0: what a list is for. 1: the lists. 2: new list.
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 0
        case 1: return lists.count
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !lists.isEmpty ? "YOUR LISTS" : nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "A list is a set of people you can share with by name. Pick one wherever you choose who can see something, and change who is on it at any time — it applies everywhere, straight away, to things they can already see."
        case 1:
            return lists.isEmpty ? nil : "Tap a list to change who is on it."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 2 {
            var content = cell.defaultContentConfiguration()
            content.text = "New list"
            content.image = UIImage(systemName: "plus.circle.fill")
            content.textProperties.color = Constants.Colors.primary
            content.imageProperties.tintColor = Constants.Colors.primary
            cell.contentConfiguration = content
            return cell
        }
        let list = lists[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = list.name
        let count = list.userIds.count
        content.secondaryText = count == 0
            ? "Nobody yet — the same as Private until you add someone"
            : "\(count) \(count == 1 ? "person" : "people")"
        content.secondaryTextProperties.color = count == 0 ? Constants.Colors.danger : Constants.Colors.secondaryLabel
        content.image = UIImage(systemName: "person.2.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 {
            newListTapped()
        } else {
            navigationController?.pushViewController(InnerCircleListViewController(list: lists[indexPath.row]), animated: true)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let list = lists[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirmDelete(list)
            done(true)
        }
        let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, done in
            self?.renameTapped(list)
            done(true)
        }
        rename.backgroundColor = Constants.Colors.primary
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }
}

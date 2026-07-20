import UIKit

/// Modal checklist of news sources for the home-page News tab. Saving
/// persists the selection to the user's account (syncs across devices) and
/// hands the chosen ids back to the presenter.
class NewsSourcePickerViewController: BaseTableViewController {

    // MARK: - Properties

    private let sources: [NewsSource]
    // Sections grouped by catalog category, preserving catalog order
    private let sections: [(category: String, sources: [NewsSource])]
    private var selectedIds: Set<String>
    var onSave: (([String]) -> Void)?

    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - Init

    init(sources: [NewsSource], enabledIds: [String]?) {
        self.sources = sources
        var grouped: [(category: String, sources: [NewsSource])] = []
        for source in sources {
            let category = source.category ?? "Other"
            if let index = grouped.firstIndex(where: { $0.category == category }) {
                grouped[index].sources.append(source)
            } else {
                grouped.append((category: category, sources: [source]))
            }
        }
        self.sections = grouped
        self.selectedIds = Set(enabledIds ?? [])
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Feeds"
        refreshControl = nil

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SourceCell")
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let ids = sources.map(\.id).filter { selectedIds.contains($0) } // catalog order
        let loading = AlertPresenter.showLoading(message: "Saving...", from: self)

        UserService.shared.updateNewsSourcePreferences(ids) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.dismiss(animated: true) {
                            self.onSave?(ids)
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    // MARK: - Table view

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].sources.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].category
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == sections.count - 1 else { return nil }
        return "Headlines from the feeds you choose appear in your Feeds tab. Articles open on the publisher's site."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SourceCell", for: indexPath)
        let source = sections[indexPath.section].sources[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = source.displayName
        config.image = UIImage(systemName: "newspaper")
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        cell.accessoryType = selectedIds.contains(source.id) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = sections[indexPath.section].sources[indexPath.row].id
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}

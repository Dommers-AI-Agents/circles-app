import UIKit

/// One collision found by background import resolution: a just-located
/// imported place (`placeId`/`placeName` — the newcomer, the delete
/// candidate) that turned out to be the same venue as an older save the
/// user already had (`keeperName` in `keeperCircleName`).
struct ImportDuplicate {
    let placeId: String
    let placeName: String
    let keeperName: String
    let keeperCircleName: String?
}

/// Checkbox review for mass-deleting import duplicates. Presented modally
/// (wrapped in a UINavigationController) by `ImportResolutionQueue` after a
/// background pass locates places that collide with existing saves. Every
/// row starts selected — these are confirmed same-venue duplicates — and
/// "Keep All" is always one tap away.
class DuplicateReviewViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private struct Row {
        let duplicate: ImportDuplicate
        var selected: Bool
    }

    private var rows: [Row]

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.allowsSelection = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "DuplicateCell")
        return table
    }()

    private lazy var deleteButton = UIButton.dangerButton(title: "Delete Selected")

    private lazy var footerContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Constants.Colors.background
        return container
    }()

    init(duplicates: [ImportDuplicate]) {
        // All start selected — the backend confirmed each is the same venue
        // as an existing save
        self.rows = duplicates.map { Row(duplicate: $0, selected: true) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Duplicates Found"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Keep All",
            style: .plain,
            target: self,
            action: #selector(keepAllTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Deselect All",
            style: .plain,
            target: self,
            action: #selector(toggleSelectAllTapped)
        )

        footerContainer.addSubview(deleteButton)
        view.addSubview(tableView)
        view.addSubview(footerContainer)

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor),

            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            deleteButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            deleteButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            deleteButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            deleteButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        tableView.tableHeaderView = makeIntroHeader()
        updateControls()
    }

    // MARK: - Header

    private func makeIntroHeader() -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.text = "While locating your imported places, \(rows.count) turned out to be place\(rows.count == 1 ? "" : "s") you already saved."

        let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 0))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        let size = container.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        )
        container.frame.size.height = size.height
        return container
    }

    // MARK: - State

    private var selectedRows: [Row] { rows.filter { $0.selected } }

    private func updateControls() {
        let count = selectedRows.count
        deleteButton.setTitle("Delete \(count) Selected", for: .normal)
        deleteButton.isEnabled = count > 0
        deleteButton.alpha = count > 0 ? 1.0 : 0.5
        navigationItem.rightBarButtonItem?.title = count == rows.count ? "Deselect All" : "Select All"
    }

    // MARK: - Actions

    @objc private func keepAllTapped() {
        dismiss(animated: true)
    }

    @objc private func toggleSelectAllTapped() {
        let selectAll = selectedRows.count < rows.count
        for index in rows.indices {
            rows[index].selected = selectAll
        }
        tableView.reloadData()
        updateControls()
    }

    @objc private func deleteTapped() {
        let ids = selectedRows.map { $0.duplicate.placeId }
        guard !ids.isEmpty else { return }

        AlertPresenter.showConfirmation(
            title: "Delete \(ids.count) Duplicate\(ids.count == 1 ? "" : "s")?",
            message: "This removes the imported copies. Your original saves stay untouched.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self
        ) { [weak self] in
            self?.deleteSequentially(ids)
        }
    }

    private func deleteSequentially(_ ids: [String]) {
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting duplicates…", from: self)
        var remaining = ids
        var deletedCount = 0

        func deleteNext() {
            guard let id = remaining.first else {
                loadingAlert.dismiss(animated: true) { [weak self] in
                    self?.finishDeletion(deletedCount: deletedCount, requested: ids.count)
                }
                return
            }
            remaining.removeFirst()
            PlaceService.shared.deletePlace(id: id) { result in
                DispatchQueue.main.async {
                    if case .success = result {
                        deletedCount += 1
                    }
                    // A single failure shouldn't strand the rest — keep going
                    deleteNext()
                }
            }
        }

        deleteNext()
    }

    private func finishDeletion(deletedCount: Int, requested: Int) {
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)

        var message = "Removed \(deletedCount) duplicate\(deletedCount == 1 ? "" : "s")."
        if deletedCount < requested {
            message += " \(requested - deletedCount) couldn't be removed — try again from their circles."
        }
        showSuccess(message) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension DuplicateReviewViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DuplicateCell", for: indexPath)
        let row = rows[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = row.duplicate.placeName
        config.secondaryText = "Same place as your save in \(row.duplicate.keeperCircleName ?? "another circle")"
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = config

        cell.accessoryType = row.selected ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].selected.toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
        updateControls()
    }
}

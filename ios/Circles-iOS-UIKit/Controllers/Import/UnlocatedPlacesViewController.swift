import UIKit

/// Checkbox review for imported places the background resolver couldn't
/// locate on Apple Maps (still "Address pending" after 3 failed passes) —
/// usually saved articles or products rather than real venues. Presented
/// modally (wrapped in a UINavigationController) from the circle detail
/// banner. Unlike `DuplicateReviewViewController`, rows start UNSELECTED:
/// deletion here is opt-in, nothing was confirmed as junk. Tapping a row's
/// text pushes the place detail screen so the user can fix it manually;
/// only the leading checkbox marks it for deletion.
class UnlocatedPlacesViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private struct Row {
        let place: Place
        var selected: Bool
    }

    private var rows: [Row]

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.allowsSelection = true
        table.register(UnlocatedPlaceCell.self, forCellReuseIdentifier: "UnlocatedCell")
        return table
    }()

    private lazy var deleteButton = UIButton.dangerButton(title: "Delete Selected")

    private lazy var footerContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Constants.Colors.background
        return container
    }()

    init(places: [Place]) {
        // All start UNSELECTED — deletion is opt-in; some of these may be
        // real places the user wants to open and fix by hand
        self.rows = places.map { Row(place: $0, selected: false) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Couldn't Be Located"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Select All",
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
        label.text = "These imported places couldn't be found on Apple Maps — usually saved articles or products rather than real places. Delete what you don't need, or tap a name to open and fix it."

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

    private func toggleSelection(at row: Int) {
        guard rows.indices.contains(row) else { return }
        rows[row].selected.toggle()
        tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
        updateControls()
    }

    // MARK: - Actions

    @objc private func doneTapped() {
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
        let ids = selectedRows.map { $0.place.id }
        guard !ids.isEmpty else { return }

        AlertPresenter.showConfirmation(
            title: "Delete \(ids.count) Place\(ids.count == 1 ? "" : "s")?",
            message: "This removes the selected imported places. This can't be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self
        ) { [weak self] in
            self?.deleteSequentially(ids)
        }
    }

    private func deleteSequentially(_ ids: [String]) {
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting places…", from: self)
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

        var message = "Removed \(deletedCount) place\(deletedCount == 1 ? "" : "s")."
        if deletedCount < requested {
            message += " \(requested - deletedCount) couldn't be removed — try again from the circle."
        }
        showSuccess(message) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension UnlocatedPlacesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "UnlocatedCell", for: indexPath
        ) as? UnlocatedPlaceCell else {
            return UITableViewCell()
        }
        let row = rows[indexPath.row]

        // Subtitle: the source-list tag from the import (e.g. "want-to-go"),
        // falling back to the unresolved-address placeholder
        let subtitle = row.place.tags?.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? "Address pending"

        cell.configure(name: row.place.name, subtitle: subtitle, selected: row.selected)
        cell.onCheckboxTapped = { [weak self] in
            self?.toggleSelection(at: indexPath.row)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Tapping the text area opens the place so the user can fix it
        // manually — the checkbox alone toggles deletion
        let detailVC = PlaceDetailViewController(place: rows[indexPath.row].place)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Cell

/// Row with a leading checkbox that toggles deletion independently of the
/// row tap (which opens the place detail screen).
private class UnlocatedPlaceCell: UITableViewCell {

    var onCheckboxTapped: (() -> Void)?

    private lazy var checkboxButton: UIButton = {
        let button = UIButton.iconButton(systemName: "circle")
        button.addTarget(self, action: #selector(checkboxTapped), for: .touchUpInside)
        return button
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        contentView.addSubview(checkboxButton)
        contentView.addSubview(nameLabel)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            checkboxButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            checkboxButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkboxButton.widthAnchor.constraint(equalToConstant: 44),
            checkboxButton.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: checkboxButton.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, subtitle: String, selected: Bool) {
        nameLabel.text = name
        subtitleLabel.text = subtitle
        checkboxButton.setImage(
            UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"),
            for: .normal
        )
        checkboxButton.tintColor = selected ? Constants.Colors.primary : .tertiaryLabel
    }

    @objc private func checkboxTapped() {
        onCheckboxTapped?()
    }
}

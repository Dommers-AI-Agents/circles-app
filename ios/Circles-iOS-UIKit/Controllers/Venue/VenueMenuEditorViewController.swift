import UIKit

/// The store's full menu (Business, 2026-10-20). Scan the printed menu and
/// check what was read, or type it in: sections of items with a price as
/// printed and a description. Items the scan wasn't sure about are orange
/// until the owner edits them or says they look right. Saved whole.
final class VenueMenuEditorViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    var onSaved: ((VenueStorefront) -> Void)?

    private let venueId: String
    private let label: String
    private var draft: MenuDraft
    private let original: StorefrontMenu
    private var scanner: VenueScanController?
    private var scanNote: String?

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        table.allowsSelectionDuringEditing = true
        return table
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    private lazy var scanButton = UIButton.primaryButton(title: "Scan your \(label.lowercased())")
    private lazy var addSectionButton = UIButton.secondaryButton(title: "Add a section")

    init(venueId: String, label: String, menu: StorefrontMenu?) {
        self.venueId = venueId
        self.label = label
        self.original = menu ?? StorefrontMenu()
        self.draft = MenuDraft(menu ?? StorefrontMenu())
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isDirty: Bool { draft.forSaving.sections != original.sections }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Full \(label.lowercased())"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped)),
            editButtonItem
        ]
        // Leaving with unsaved changes asks first
        navigationItem.backAction = UIAction { [weak self] _ in self?.leave() }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragInteractionEnabled = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "item")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        addSectionButton.addTarget(self, action: #selector(addSectionTapped), for: .touchUpInside)
        installHeader()
        render()
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    private func installHeader() {
        let stack = UIStackView(arrangedSubviews: [summaryLabel, scanButton, addSectionButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let header = UIView()
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4)
        ])
        tableView.tableHeaderView = header
    }

    private func render() {
        var lines: [String] = []
        if draft.itemCount == 0 {
            lines.append("Photograph your printed \(label.lowercased()) and every item goes on your place page, where customers can browse and search it. Or add items yourself.")
        } else {
            lines.append("\(draft.itemCount) item\(draft.itemCount == 1 ? "" : "s") in \(draft.sections.count) section\(draft.sections.count == 1 ? "" : "s").")
            if draft.unsureCount > 0 {
                lines.append("\(draft.unsureCount) in orange: the photo was hard to read there. Tap to fix, or swipe for \u{201C}Looks right\u{201D}.")
            }
        }
        if let scanNote { lines.append(scanNote) }
        summaryLabel.text = lines.joined(separator: "\n")
        if let header = tableView.tableHeaderView {
            let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width, height: 0),
                                                      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            header.frame.size.height = size.height
            tableView.tableHeaderView = header
        }
        tableView.reloadData()
    }

    // MARK: - Scan

    @objc private func scanTapped() {
        guard draft.itemCount > 0 else { return scan(merge: .replace) }
        AlertPresenter.showActionSheet(
            title: "Scan your \(label.lowercased())",
            message: "Start over from the photos, or add pages to what\u{2019}s here?",
            actions: [
                (title: "Add pages", style: .default, handler: { [weak self] in self?.scan(merge: .add) }),
                (title: "Replace everything", style: .destructive, handler: { [weak self] in self?.scan(merge: .replace) })
            ],
            from: self, sourceView: scanButton)
    }

    private func scan(merge: MenuDraft.ScanMerge) {
        let scanner = VenueScanController(venueId: venueId, kind: .menu, presenter: self)
        self.scanner = scanner
        scanner.start(MenuScanDraft.self, sourceView: scanButton) { [weak self] result in
            guard let self else { return }
            self.scanner = nil
            switch result {
            case .success(let response):
                let found = response.draft.sections
                guard !found.isEmpty else {
                    return self.showError(response.draft.notes ?? "No menu items were found in those photos. Try a sharper, straight-on photo.")
                }
                self.draft.apply(scan: found, merge: merge)
                var note = response.draft.notes
                if response.truncated == true {
                    note = [note, "That was a lot to read at once; check the end of the last page."].compactMap { $0 }.joined(separator: " ")
                }
                self.scanNote = note
                self.render()
                AnalyticsService.shared.logEvent("venue_scan_done", parameters: ["kind": "menu", "items": String(found.reduce(0) { $0 + $1.items.count })])
            case .failure(let error):
                self.showError(VenueScanController.message(for: error))
            }
        }
    }

    // MARK: - Editing

    @objc private func addSectionTapped() {
        AlertPresenter.showTextInput(title: "New section", placeholder: "Starters, Pizza, Drinks\u{2026}", confirmTitle: "Add", from: self) { [weak self] name in
            guard let self, let name, let index = self.draft.addSection(named: name) else { return }
            self.render()
            self.editItem(section: index, row: nil)
        }
    }

    private func editItem(section: Int, row: Int?) {
        let item = row.flatMap { draft.sections[section].items.indices.contains($0) ? draft.sections[section].items[$0] : nil }
        AlertPresenter.showMultiFieldInput(
            title: item == nil ? "Add to \(draft.sections[section].name)" : "Edit item",
            message: item?.unsure == true ? "The photo was hard to read here. Check it against your menu." : nil,
            fields: [
                (placeholder: "Name", keyboardType: .default, initialText: item?.name),
                (placeholder: "Price, as on your menu (e.g. 12 or $12.50)", keyboardType: .default, initialText: item?.price),
                (placeholder: "Description (optional)", keyboardType: .default, initialText: item?.description)
            ],
            confirmTitle: item == nil ? "Add" : "Done",
            from: self
        ) { [weak self] values in
            guard let self else { return }
            let saved = self.draft.setItem(section: section, row: row, name: values[safe: 0].flatMap { $0 } ?? "",
                                           price: values[safe: 1].flatMap { $0 }, description: values[safe: 2].flatMap { $0 })
            if !saved { self.showError("An item needs a name.") }
            self.render()
        }
    }

    private func sectionMenu(_ section: Int, from view: UIView) {
        let name = draft.sections[section].name
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            (title: "Add an item", style: .default, handler: { [weak self] in self?.editItem(section: section, row: nil) }),
            (title: "Rename", style: .default, handler: { [weak self] in
                guard let self else { return }
                AlertPresenter.showTextInput(title: "Rename section", initialText: name, confirmTitle: "Save", from: self) { new in
                    self.draft.renameSection(section, to: new ?? ""); self.render()
                }
            })
        ]
        if section > 0 { actions.append((title: "Move up", style: .default, handler: { [weak self] in self?.draft.moveSection(section, by: -1); self?.render() })) }
        if section < draft.sections.count - 1 { actions.append((title: "Move down", style: .default, handler: { [weak self] in self?.draft.moveSection(section, by: 1); self?.render() })) }
        actions.append((title: "Delete section", style: .destructive, handler: { [weak self] in
            guard let self else { return }
            let count = self.draft.sections[section].items.count
            AlertPresenter.showConfirmation(title: "Delete \u{201C}\(name)\u{201D}?",
                                            message: count == 0 ? "It\u{2019}s empty." : "Its \(count) item\(count == 1 ? "" : "s") go too.",
                                            confirmTitle: "Delete", isDestructive: true, from: self) {
                self.draft.deleteSection(section); self.render()
            }
        }))
        AlertPresenter.showActionSheet(title: name, actions: actions, from: self, sourceView: view)
    }

    // MARK: - Save / leave

    @objc private func saveTapped() {
        let menu = draft.forSaving
        let loading = AlertPresenter.showLoading(message: "Saving\u{2026}", from: self)
        RewardsService.shared.updateStorefrontMenu(venueId: venueId, menu: menu) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let storefront):
                        self.onSaved?(storefront)
                        self.navigationController?.popViewController(animated: true)
                    case .failure(let error):
                        self.showError((error as? APIError)?.serverMessage ?? "Couldn\u{2019}t save. Try again.")
                    }
                }
            }
        }
    }

    private func leave() {
        guard isDirty else { navigationController?.popViewController(animated: true); return }
        AlertPresenter.showConfirmation(title: "Leave without saving?", message: "Your changes to the \(label.lowercased()) will be lost.",
                                        confirmTitle: "Leave", cancelTitle: "Keep editing", isDestructive: true, from: self) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - Table

extension VenueMenuEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { draft.sections.count }

    /// Items, then an "Add an item" row
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        draft.sections[section].items.count + 1
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = UILabel()
        title.text = draft.sections[section].name
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = Constants.Colors.label
        let more = UIButton.iconButton(systemName: "ellipsis.circle")
        more.tag = section
        more.addTarget(self, action: #selector(sectionMoreTapped(_:)), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [title, UIView(), more])
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 16)
        return row
    }

    @objc private func sectionMoreTapped(_ sender: UIButton) { sectionMenu(sender.tag, from: sender) }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        var config = UIListContentConfiguration.subtitleCell()
        let items = draft.sections[indexPath.section].items
        if indexPath.row == items.count {
            config.text = "Add an item"
            config.textProperties.color = Constants.Colors.primary
            config.image = UIImage(systemName: "plus.circle.fill")
            config.imageProperties.tintColor = Constants.Colors.primary
            cell.accessoryView = nil
        } else {
            let item = items[indexPath.row]
            config.text = item.name
            config.secondaryText = [item.description, item.tags.isEmpty ? nil : item.tags.joined(separator: " · ")]
                .compactMap { $0 }.joined(separator: "\n").nilIfEmpty
            config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            config.secondaryTextProperties.numberOfLines = 3
            if item.unsure {
                config.image = UIImage(systemName: "exclamationmark.circle.fill")
                config.imageProperties.tintColor = .systemOrange
                config.textProperties.color = .systemOrange
            }
            let price = UILabel()
            price.text = item.price
            price.font = .systemFont(ofSize: 16, weight: .semibold)
            price.textColor = item.unsure ? .systemOrange : Constants.Colors.label
            price.sizeToFit()
            cell.accessoryView = item.price == nil ? nil : price
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let count = draft.sections[indexPath.section].items.count
        editItem(section: indexPath.section, row: indexPath.row == count ? nil : indexPath.row)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.row < draft.sections[indexPath.section].items.count
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.row < draft.sections[indexPath.section].items.count
    }

    /// Keeps "Add an item" last in every section
    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath,
                   toProposedIndexPath proposed: IndexPath) -> IndexPath {
        let last = draft.sections[proposed.section].items.count - (proposed.section == source.section ? 1 : 0)
        return IndexPath(row: min(proposed.row, max(0, last)), section: proposed.section)
    }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        draft.moveItem(from: (source.section, source.row), to: (destination.section, destination.row))
        DispatchQueue.main.async { self.render() }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < draft.sections[indexPath.section].items.count else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.draft.deleteItem(section: indexPath.section, row: indexPath.row)
            self?.render()
            done(true)
        }
        var actions = [delete]
        if draft.sections[indexPath.section].items[indexPath.row].unsure {
            let ok = UIContextualAction(style: .normal, title: "Looks right") { [weak self] _, _, done in
                self?.draft.confirmItem(section: indexPath.section, row: indexPath.row)
                self?.render()
                done(true)
            }
            ok.backgroundColor = .systemGreen
            actions.append(ok)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        indexPath.row < draft.sections[indexPath.section].items.count ? .delete : .none
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        draft.deleteItem(section: indexPath.section, row: indexPath.row)
        render()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}


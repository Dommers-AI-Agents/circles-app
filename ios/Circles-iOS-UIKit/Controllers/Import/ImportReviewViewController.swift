import UIKit

/// Review screen shown between prepare and execute: one section per proposed
/// circle, with editable names, per-place checkmarks, and duplicate /
/// unresolved badges. Nothing is written until the user confirms.
class ImportReviewViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private struct ReviewPlace {
        let place: ImportPreviewPlace
        var selected: Bool
    }

    private struct ReviewSection {
        var circleName: String
        var existingCircleId: String?
        var places: [ReviewPlace]

        var selectedCount: Int { places.filter { $0.selected }.count }
    }

    private let source: ImportSource
    private var sections: [ReviewSection]

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.allowsSelection = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        return table
    }()

    private lazy var importButton = UIButton.primaryButton(title: "Import")

    private lazy var footerContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Constants.Colors.background
        return container
    }()

    init(source: ImportSource, preview: ImportPreview) {
        self.source = source
        self.sections = preview.lists.map { list in
            ReviewSection(
                circleName: list.proposedCircleName,
                existingCircleId: list.existingCircleId,
                // New places start selected; duplicates and unresolved don't
                places: list.places.map { ReviewPlace(place: $0, selected: $0.isNew) }
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Review Import"

        footerContainer.addSubview(importButton)
        view.addSubview(tableView)
        view.addSubview(footerContainer)

        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor),

            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            importButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            importButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            importButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            importButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        updateImportButton()
    }

    // MARK: - State

    private func updateImportButton() {
        let total = sections.reduce(0) { $0 + $1.selectedCount }
        importButton.setTitle(total == 0 ? "Import" : "Import \(total) Place\(total == 1 ? "" : "s")", for: .normal)
        importButton.isEnabled = total > 0
        importButton.alpha = total > 0 ? 1.0 : 0.5
    }

    // MARK: - Actions

    @objc private func importTapped() {
        let executeLists: [ImportService.ExecuteList] = sections.compactMap { section in
            let selectedPlaces = section.places.filter { $0.selected }.map { $0.place }
            guard !selectedPlaces.isEmpty else { return nil }
            return ImportService.ExecuteList(
                circleName: section.circleName,
                existingCircleId: section.existingCircleId,
                places: selectedPlaces
            )
        }
        guard !executeLists.isEmpty else { return }

        let loadingAlert = AlertPresenter.showLoading(message: "Importing…", from: self)

        ImportService.shared.execute(
            source: source,
            lists: executeLists,
            progress: { message in
                DispatchQueue.main.async {
                    loadingAlert.message = message
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success(let summary):
                            self.showCompletion(summary)
                        case .failure(let error):
                            self.showError(error.localizedDescription)
                        }
                    }
                }
            }
        )
    }

    private func showCompletion(_ summary: ImportRunSummary) {
        var message = "Imported \(summary.created) place\(summary.created == 1 ? "" : "s")"
        if summary.circleNames.count == 1 {
            message += " into \"\(summary.circleNames[0])\""
        } else if summary.circleNames.count > 1 {
            message += " across \(summary.circleNames.count) circles"
        }
        message += "."
        if summary.skippedDuplicates > 0 {
            message += " Skipped \(summary.skippedDuplicates) you already had."
        }
        if !summary.failures.isEmpty {
            message += " \(summary.failures.count) couldn't be imported."
        }

        // Refresh circles home when we land back there
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)

        showSuccess(message) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func renameSection(_ sectionIndex: Int) {
        let section = sections[sectionIndex]
        AlertPresenter.showTextInput(
            title: "Circle Name",
            message: "Places from this list will be added to a circle with this name.",
            placeholder: "Circle name",
            initialText: section.circleName,
            from: self
        ) { [weak self] newName in
            guard let self = self,
                  let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newName.isEmpty else { return }
            self.sections[sectionIndex].circleName = newName
            // Renaming detaches a suggested merge — the import will create a
            // circle with the new name instead
            self.sections[sectionIndex].existingCircleId = nil
            self.tableView.reloadSections(IndexSet(integer: sectionIndex), with: .automatic)
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ImportReviewViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].places.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let reviewSection = sections[section]
        let suffix = reviewSection.existingCircleId != nil ? " (adds to existing circle)" : ""
        return "\(reviewSection.circleName) — \(reviewSection.selectedCount) of \(reviewSection.places.count)\(suffix)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == sections.count - 1 ? "Tap a place to include or exclude it. Tap a section header to rename the circle." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath)
        let reviewPlace = sections[indexPath.section].places[indexPath.row]
        let place = reviewPlace.place

        var config = cell.defaultContentConfiguration()
        config.text = place.name

        var detail = place.address ?? ""
        if place.isDuplicate {
            detail = "Already in your circles" + (detail.isEmpty ? "" : " · \(detail)")
            config.secondaryTextProperties.color = .systemOrange
        } else if place.isUnresolved {
            detail = "Couldn't find this place on the map"
            config.secondaryTextProperties.color = .systemRed
        }
        config.secondaryText = detail
        config.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = config

        if place.isUnresolved {
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            cell.accessoryType = reviewPlace.selected ? .checkmark : .none
            cell.selectionStyle = .default
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let reviewPlace = sections[indexPath.section].places[indexPath.row]
        guard !reviewPlace.place.isUnresolved else { return }

        sections[indexPath.section].places[indexPath.row].selected.toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
        if let header = tableView.headerView(forSection: indexPath.section) {
            header.textLabel?.text = self.tableView(tableView, titleForHeaderInSection: indexPath.section)
        }
        updateImportButton()
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        // Make section headers tappable for renaming
        if view.gestureRecognizers?.isEmpty ?? true {
            let tap = UITapGestureRecognizer(target: self, action: #selector(headerTapped(_:)))
            view.addGestureRecognizer(tap)
            view.tag = section
        } else {
            view.tag = section
        }
    }

    @objc private func headerTapped(_ gesture: UITapGestureRecognizer) {
        guard let sectionIndex = gesture.view?.tag, sectionIndex < sections.count else { return }
        renameSection(sectionIndex)
    }
}

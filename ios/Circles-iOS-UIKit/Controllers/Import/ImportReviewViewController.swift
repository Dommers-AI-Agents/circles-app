import UIKit

/// Review screen shown between prepare and execute: one section per source
/// list, with per-place checkmarks and duplicate/unmapped badges. Everything
/// imports into the single per-source circle ("Google Imports", …) — the
/// backend decides that; list names survive on each place as its source list.
/// Nothing is written until the user confirms.
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
    private let targetCircleName: String

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
        self.targetCircleName = preview.targetCircleName ?? "Imports"
        self.sections = preview.lists.map { list in
            ReviewSection(
                circleName: list.proposedCircleName,
                existingCircleId: list.existingCircleId,
                // New AND unmapped places start selected (unmapped rows import
                // without a pin — nothing is dropped); duplicates don't
                places: list.places.map { ReviewPlace(place: $0, selected: !$0.isDuplicate) }
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

        // Rows past the inline-resolution cap imported unmapped — start
        // locating them quietly now
        ImportResolutionQueue.shared.kick()

        showSuccess(message) { [weak self] in
            self?.dismiss(animated: true)
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
        return "\(reviewSection.circleName) — \(reviewSection.selectedCount) of \(reviewSection.places.count)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == sections.count - 1
            ? "Tap a place to include or exclude it. Everything imports into your \"\(targetCircleName)\" circle and appears on your map — you can hide the circle from the map anytime in its settings. Places without a pin yet will be located automatically after import."
            : nil
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
        } else if place.isUnmapped {
            detail = "Location will be found in the background"
            config.secondaryTextProperties.color = .secondaryLabel
        }
        config.secondaryText = detail
        config.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = config

        cell.accessoryType = reviewPlace.selected ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        sections[indexPath.section].places[indexPath.row].selected.toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
        if let header = tableView.headerView(forSection: indexPath.section) {
            header.textLabel?.text = self.tableView(tableView, titleForHeaderInSection: indexPath.section)
        }
        updateImportButton()
    }

}

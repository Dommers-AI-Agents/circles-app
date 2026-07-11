import UIKit
import UniformTypeIdentifiers

/// Entry screen for importing saved places from other platforms.
/// Presents the supported sources with per-source instructions, then routes
/// into file picking (Mapstr, Google Takeout) or OAuth (Swarm).
class ImportSourceSelectionViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private var pendingSource: ImportSource?

    private struct SourceOption {
        let source: ImportSource
        let icon: String
        let subtitle: String
        let instructions: String
        let actionTitle: String
    }

    private let options: [SourceOption] = [
        SourceOption(
            source: .mapstr,
            icon: "map",
            subtitle: "Import from Mapstr's email export",
            instructions: "In Mapstr:\n\n1. Open your Profile tab\n2. Tap Settings → \"Manage your data\"\n3. Tap \"Export your data\"\n4. Mapstr emails your places to you\n5. Save the .geojson attachment to Files, then pick it here\n\nTip: you can also open the attachment directly with Circles from Mail.",
            actionTitle: "Choose File"
        ),
        SourceOption(
            source: .googleMaps,
            icon: "globe",
            subtitle: "Import from Google Takeout",
            instructions: "In Google Takeout (takeout.google.com):\n\n1. Deselect all, then select only \"Saved\"\n2. Export and download the ZIP\n3. In the Files app, long-press the ZIP → Uncompress\n4. Pick the CSV files inside (one per list) here\n\nEach list becomes its own circle.",
            actionTitle: "Choose Files"
        ),
        SourceOption(
            source: .swarm,
            icon: "checkmark.seal",
            subtitle: "Connect your Swarm account",
            instructions: "Sign in with Foursquare to import your saved places and check-ins from Swarm.\n\nWe only read your places — nothing is posted to your account.",
            actionTitle: "Connect Swarm"
        )
    ]

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SourceCell")
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Import Places"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Source handling

    private func handleSelection(_ option: SourceOption) {
        AlertPresenter.showConfirmation(
            title: "Import from \(option.source.displayName)",
            message: option.instructions,
            confirmTitle: option.actionTitle,
            isDestructive: false,
            from: self,
            onConfirm: { [weak self] in
                switch option.source {
                case .mapstr, .googleMaps:
                    self?.presentDocumentPicker(for: option.source)
                case .swarm:
                    self?.startSwarmImport()
                }
            }
        )
    }

    private func presentDocumentPicker(for source: ImportSource) {
        pendingSource = source

        var types: [UTType]
        switch source {
        case .mapstr:
            types = [.json]
            if let geojson = UTType(filenameExtension: "geojson") {
                types.append(geojson)
            }
        case .googleMaps:
            types = [.commaSeparatedText]
        case .swarm:
            return
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = (source == .googleMaps)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - File parsing

    /// Shared entry point: also used by SceneDelegate when an export file is
    /// opened with Circles from Mail or the Files app.
    func importFiles(at urls: [URL], source: ImportSource) {
        var lists: [ImportList] = []
        var mapstrPlaces: [ImportPlaceCandidate] = []

        for url in urls {
            let filename = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                switch source {
                case .mapstr:
                    let parsed = try ImportParsingService.shared.parseMapstrGeoJSON(data: data, filename: filename)
                    mapstrPlaces.append(contentsOf: parsed.flatMap { $0.places })
                case .googleMaps:
                    lists.append(try ImportParsingService.shared.parseGoogleTakeoutCSV(data: data, filename: filename))
                case .swarm:
                    continue
                }
            } catch {
                showError(error.localizedDescription)
                return
            }
        }

        if !mapstrPlaces.isEmpty {
            lists.append(ImportList(name: "Mapstr Places", places: mapstrPlaces))
        }

        guard !lists.isEmpty else {
            showError("No places found in the selected file(s).")
            return
        }

        prepareAndReview(source: source, lists: lists)
    }

    // MARK: - Prepare + review

    func prepareAndReview(source: ImportSource, lists: [ImportList]) {
        let totalPlaces = lists.reduce(0) { $0 + $1.places.count }
        let loadingAlert = AlertPresenter.showLoading(
            message: "Preparing \(totalPlaces) places…",
            from: self
        )

        ImportService.shared.prepare(
            source: source,
            lists: lists,
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
                        case .success(let preview):
                            let reviewVC = ImportReviewViewController(source: source, preview: preview)
                            self.navigationController?.pushViewController(reviewVC, animated: true)
                        case .failure(let error):
                            self.handlePrepareError(error)
                        }
                    }
                }
            }
        )
    }

    private func handlePrepareError(_ error: Error) {
        // A 403 with upgradeRequired means the subscription lapsed since the
        // gate check — send the user to the paywall instead of a raw error.
        if let apiError = error as? APIError, case .httpError(let statusCode, _) = apiError, statusCode == 403 {
            SubscriptionManager.shared.showPaywall(from: self, reason: .importFeature)
            return
        }
        showError(error.localizedDescription)
    }

    // MARK: - Swarm (Foursquare OAuth)

    private func startSwarmImport() {
        // Wired up with the Swarm backend endpoints (Phase 3)
        SwarmImportCoordinator.shared.start(from: self)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ImportSourceSelectionViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Choose where your places live today"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Your lists are recreated as circles. You'll review everything before anything is imported."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SourceCell", for: indexPath)
        let option = options[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = option.source.displayName
        config.secondaryText = option.subtitle
        config.image = UIImage(systemName: option.icon)
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        handleSelection(options[indexPath.row])
    }
}

// MARK: - UIDocumentPickerDelegate

extension ImportSourceSelectionViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = pendingSource, !urls.isEmpty else { return }
        importFiles(at: urls, source: source)
    }
}

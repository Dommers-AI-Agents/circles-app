import UIKit
import MapKit

/// Every Add-from-photos way ends here (Wes, 2026-10-17): the real places
/// found in the photos, all checked — uncheck what you don't want, hold one
/// to pick a different place at that spot, choose where they go, save. Rows
/// arrive live while Apple Maps is still looking.
final class PhotoPlacesReviewViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let finder: PhotoPlaceFinder
    private let circles: [Circle]
    private var target: PhotoMapService.Target
    /// Name for a new circle (Scan a time period suggests one)
    private var newCircleName: String
    private var uid: String { AuthService.shared.getUserId() ?? "anon" }
    /// The sign-up step: after saving, end the step instead of opening the circle
    var onFinished: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel()
    private lazy var lookButton = UIButton.secondaryButton(title: "Stop")
    private lazy var saveButton = UIButton.primaryButton(title: "Save")
    private let header = UIStackView()
    private let destinationButton = UIButton(type: .system)
    private let nameField = UITextField()
    private let privacyControl = UISegmentedControl(items: ["Public", "Connections", "Private"])
    private let mapRow = IncludeOnMapRow(isOn: true)
    private let freeNote = UILabel()

    init(finder: PhotoPlaceFinder, circles: [Circle], target: PhotoMapService.Target, suggestedName: String? = nil, title: String) {
        self.finder = finder
        self.circles = circles
        self.target = target
        if case .new(let name, _, _) = target { newCircleName = name } else { newCircleName = suggestedName ?? "From my photos" }
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = 64

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = Constants.Colors.secondaryLabel
        statusLabel.numberOfLines = 2
        let buttons = UIStackView(arrangedSubviews: [lookButton, saveButton])
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        let footer = UIStackView(arrangedSubviews: [statusLabel, buttons])
        footer.axis = .vertical
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.isLayoutMarginsRelativeArrangement = true
        footer.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        footer.backgroundColor = Constants.Colors.background

        view.addSubview(tableView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        buildHeader()
        lookButton.addTarget(self, action: #selector(lookTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        finder.onEvent = { [weak self] event in
            guard let self else { return }
            if case .found = event {
                self.tableView.insertRows(at: [IndexPath(row: self.finder.finds.count - 1, section: 0)], with: .automatic)
            }
            self.refreshFooter()
        }
        finder.start()
        refreshFooter()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { finder.stop() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the table header to its stack
        let width = tableView.bounds.width
        let size = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if tableView.tableHeaderView?.frame.height != size.height {
            header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
            tableView.tableHeaderView = header
        }
    }

    // MARK: - Where they go

    private func buildHeader() {
        header.axis = .vertical
        header.spacing = 10
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 20)

        destinationButton.contentHorizontalAlignment = .leading
        destinationButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        destinationButton.showsMenuAsPrimaryAction = true

        nameField.borderStyle = .roundedRect
        nameField.placeholder = "Circle name"
        nameField.text = newCircleName
        nameField.autocapitalizationType = .words
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        privacyControl.selectedSegmentIndex = 1

        freeNote.font = .systemFont(ofSize: 13)
        freeNote.textColor = Constants.Colors.secondaryLabel
        freeNote.numberOfLines = 0
        freeNote.text = SubscriptionManager.shared.isSubscribed ? nil
            : "Your first 25 places from photos are free. Premium adds the rest."
        freeNote.isHidden = freeNote.text == nil

        let hint = UILabel()
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Constants.Colors.secondaryLabel
        hint.numberOfLines = 0
        hint.text = "Only places like caf\u{00E9}s, restaurants, shops, hotels and parks are listed. Uncheck any you don\u{2019}t want; hold one to pick a different place there."

        [destinationButton, nameField, privacyControl, mapRow, freeNote, hint].forEach(header.addArrangedSubview)
        renderDestination()
    }

    private func renderDestination() {
        let label: String
        switch target {
        case .photos: label = "Places from my photos"
        case .circle(_, let name): label = name
        case .new: label = "A new circle"
        }
        destinationButton.setTitle("Save to: \(label) \u{25BE}", for: .normal)
        let isNew: Bool = { if case .new = target { return true } else { return false } }()
        nameField.isHidden = !isNew
        privacyControl.isHidden = !isNew
        mapRow.isHidden = !isNew

        var actions: [UIMenuElement] = [
            UIAction(title: "Places from my photos", image: UIImage(systemName: "photo.stack"),
                     state: target == .photos ? .on : .off) { [weak self] _ in self?.choose(.photos) },
            UIAction(title: "A new circle", image: UIImage(systemName: "plus.circle"), state: isNew ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.choose(.new(name: self.newCircleName, privacy: .myNetwork, showOnMap: true))
            }
        ]
        // Own circles in profile order (never alphabetized)
        let mine = circles.filter { IDNormalizer.isSameUser($0.owner, uid) && $0.name != "Places from my photos" }
        if !mine.isEmpty {
            actions.append(UIMenu(title: "Your circles", options: .displayInline, children: mine.map { circle in
                let on: Bool = { if case .circle(let id, _) = target { return id == circle.id } else { return false } }()
                return UIAction(title: circle.name, state: on ? .on : .off) { [weak self] _ in
                    self?.choose(.circle(id: circle.id, name: circle.name))
                }
            }))
        }
        destinationButton.menu = UIMenu(title: "Save these places to", children: actions)
        view.setNeedsLayout()
    }

    private func choose(_ next: PhotoMapService.Target) {
        target = next
        renderDestination()
    }

    @objc private func nameChanged() {
        newCircleName = nameField.text ?? ""
    }

    private var resolvedTarget: PhotoMapService.Target {
        guard case .new = target else { return target }
        let privacy: PrivacyLevel = privacyControl.selectedSegmentIndex == 0 ? .public
            : privacyControl.selectedSegmentIndex == 2 ? .private : .myNetwork
        return .new(name: newCircleName.trimmingCharacters(in: .whitespaces), privacy: privacy, showOnMap: mapRow.isOn)
    }

    // MARK: - Footer

    private var chosen: [PhotoFind] { finder.finds.filter { $0.include && !$0.saved } }

    private func refreshFooter() {
        let found = finder.finds.count
        if finder.isRunning {
            statusLabel.text = "Looking\u{2026} checked \(finder.checked) of \(finder.spots.count) spots \u{00B7} \(found) place\(found == 1 ? "" : "s") found"
            lookButton.setTitle("Stop", for: .normal)
            lookButton.isHidden = false
        } else if !finder.isDone {
            statusLabel.text = "\(found) place\(found == 1 ? "" : "s") found \u{00B7} \(finder.spots.count - finder.checked) spots not checked yet"
            lookButton.setTitle("Keep looking", for: .normal)
            lookButton.isHidden = false
        } else {
            statusLabel.text = found == 0
                ? "No places found in these photos: no caf\u{00E9}s, restaurants, shops or venues at those spots."
                : "Done \u{00B7} \(found) place\(found == 1 ? "" : "s") found"
            lookButton.isHidden = true
        }
        let count = chosen.count
        saveButton.setTitle(count == 0 ? "Save" : "Save \(count) place\(count == 1 ? "" : "s")", for: .normal)
        saveButton.isEnabled = count > 0
        saveButton.alpha = count > 0 ? 1 : 0.5
    }

    @objc private func lookTapped() {
        if finder.isRunning {
            finder.stop()
        } else {
            if let pause = finder.pauseAfterFinds { finder.pauseAfterFinds = pause + 40 }
            finder.start()
        }
        refreshFooter()
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { finder.finds.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let find = finder.finds[indexPath.row]
        let item = find.item
        cell.textLabel?.text = item.name
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        let when = DateFormatter.localizedString(from: find.spot.start, dateStyle: .medium, timeStyle: .none)
        let photos = "\(find.spot.photoCount) photo\(find.spot.photoCount == 1 ? "" : "s")"
        cell.detailTextLabel?.text = find.saved ? "Saved" : "\(PhotoPlaceKind.label(item)) \u{00B7} \(when) \u{00B7} \(photos)"
        cell.detailTextLabel?.textColor = find.saved ? .systemGreen : .secondaryLabel
        cell.accessoryType = find.include ? .checkmark : .none
        cell.selectionStyle = find.saved ? .none : .default
        cell.imageView?.image = UIImage(systemName: "photo")
        cell.imageView?.layer.cornerRadius = 6
        cell.imageView?.clipsToBounds = true
        switch find.spot.photo {
        case .image(let image):
            cell.imageView?.image = image.preparingThumbnail(of: CGSize(width: 44, height: 44)) ?? image
        case .asset(let id):
            PhotoLibraryIndex.shared.image(for: id, size: CGSize(width: 88, height: 88)) { [weak cell] image in
                guard let cell, let image else { return }
                cell.imageView?.image = image.preparingThumbnail(of: CGSize(width: 44, height: 44)) ?? image
                cell.setNeedsLayout()
            }
        }
        cell.accessibilityHint = find.include ? "Will be saved. Tap to leave it out" : "Left out. Tap to save it"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let find = finder.finds[indexPath.row]
        guard !find.saved else { return }
        find.include.toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshFooter()
    }

    /// Hold a row: the other places Apple Maps found at that spot
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let find = finder.finds[indexPath.row]
        guard find.candidates.count > 1, !find.saved else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(title: "Pick the place", children: find.candidates.enumerated().map { index, item in
                UIAction(title: item.name ?? "Place", subtitle: PhotoPlaceKind.label(item), state: index == find.choice ? .on : .off) { _ in
                    find.choice = index
                    find.include = true
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                    self?.refreshFooter()
                }
            })
        }
    }

    // MARK: - Save

    @objc private func saveTapped() {
        let rows = chosen
        guard !rows.isEmpty else { return }
        if case .new(let name, _, _) = resolvedTarget, name.isEmpty {
            return showError("Give the new circle a name.")
        }
        finder.stop()
        refreshFooter()
        let loading = AlertPresenter.showLoading(message: "Saving \(rows.count) place\(rows.count == 1 ? "" : "s")\u{2026}", from: self)
        save(rows, target: resolvedTarget, savedSoFar: 0, circleId: nil, coins: 0, loading: loading)
    }

    /// Ten at a time: upload their photos, then add them
    private func save(_ rows: [PhotoFind], target: PhotoMapService.Target, savedSoFar: Int, circleId: String?,
                      coins: Double, loading: UIAlertController) {
        let batch = Array(rows.prefix(10))
        guard !batch.isEmpty else {
            return Self.end(loading) { self.finish(saved: savedSoFar, circleId: circleId, coins: coins) }
        }
        loading.message = "Saving \(savedSoFar + 1)\u{2013}\(savedSoFar + batch.count) of \(savedSoFar + rows.count)\u{2026}"
        uploadPhotos(batch) { [weak self] places in
            guard let self else { return }
            PhotoMapService.add(places, to: target) { outcome in
                switch outcome {
                case .added(let result):
                    let accepted = min(batch.count, result.added + (result.skippedDuplicates ?? 0))
                    batch.prefix(accepted).forEach { $0.saved = true }
                    PhotoMapProgressStore.markDone(batch.prefix(accepted).map(\.spot.key), uid: self.uid)
                    self.tableView.reloadData()
                    self.refreshFooter()
                    // A new circle exists now: later batches add to it
                    var next = target
                    if case .new = target, let id = result.circleId {
                        next = .circle(id: id, name: result.circleName ?? self.newCircleName)
                        self.target = next
                        self.renderDestination()
                    }
                    let newCoins = coins + (result.coins ?? 0)
                    if result.upgradeRequired == true {
                        Self.end(loading) {
                            self.reachedLimit(saved: savedSoFar + result.added, circleId: result.circleId ?? circleId, coins: newCoins)
                        }
                    } else {
                        self.save(Array(rows.dropFirst(batch.count)), target: next, savedSoFar: savedSoFar + result.added,
                                  circleId: result.circleId ?? circleId, coins: newCoins, loading: loading)
                    }
                case .limitReached:
                    Self.end(loading) {
                        if case .new = target, savedSoFar == 0 {
                            // The free circle cap, not the photo allowance
                            SubscriptionManager.shared.showPaywall(from: self, reason: .circleLimit)
                        } else {
                            self.reachedLimit(saved: savedSoFar, circleId: circleId, coins: coins)
                        }
                    }
                case .failed(let error):
                    Self.end(loading) {
                        self.refreshFooter()
                        self.showError(savedSoFar > 0
                            ? "Saved \(savedSoFar), then lost the connection. Tap Save to add the rest."
                            : (error as? APIError)?.serverMessage ?? "Couldn\u{2019}t save. Check your connection and try again.")
                    }
                }
            }
        }
    }

    private func uploadPhotos(_ rows: [PhotoFind], completion: @escaping ([PhotoMapPlace]) -> Void) {
        var urls = [String?](repeating: nil, count: rows.count)
        let group = DispatchGroup()
        for (index, find) in rows.enumerated() {
            group.enter()
            let upload: (UIImage?) -> Void = { image in
                guard let data = image?.jpegData(compressionQuality: 0.8) else { return group.leave() }
                PlaceService.shared.uploadImage(data) { result in
                    urls[index] = try? result.get()
                    group.leave()
                }
            }
            switch find.spot.photo {
            case .image(let image): upload(image)
            case .asset(let id): PhotoLibraryIndex.shared.uploadImage(for: id, completion: upload)
            }
        }
        group.notify(queue: .main) {
            completion(rows.enumerated().map { index, find in
                let item = find.item
                let mapping = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: item.name)
                return PhotoMapPlace(name: item.name ?? "Place", address: Self.address(item.placemark),
                                     coordinate: item.placemark.coordinate, category: mapping.category.rawValue,
                                     applePoiCategory: item.pointOfInterestCategory?.rawValue,
                                     photoUrl: urls[index], spotKey: find.spot.key)
            })
        }
    }

    private func reachedLimit(saved: Int, circleId: String?, coins: Double) {
        refreshFooter()
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        AnalyticsService.shared.logEvent("photo_places_limit", parameters: ["saved": String(saved)])
        let left = chosen.count
        AlertPresenter.showConfirmation(
            title: saved > 0 ? "Saved \(saved) place\(saved == 1 ? "" : "s")" : "Your free places are used",
            message: "Your first 25 places from photos are free. Add the other \(left) with Premium.",
            confirmTitle: "Unlock with Premium",
            cancelTitle: "Not now",
            from: self,
            onConfirm: { [weak self] in
                guard let self else { return }
                SubscriptionManager.shared.showPaywall(from: self, reason: .photoPlaces)
            }
        )
    }

    private func finish(saved: Int, circleId: String?, coins: Double) {
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        AnalyticsService.shared.logEvent("photo_places_saved", parameters: ["saved": String(saved)])
        let coinLine = PhotoMapPlanner.coinsLine(coins).map { "\n\($0)" } ?? ""
        if let onFinished {
            AlertPresenter.showBriefMessage("Saved \(saved) place\(saved == 1 ? "" : "s") to your map.\(coinLine)", from: self, duration: 1.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onFinished() }
            return
        }
        guard let circleId else { return showSuccess("Saved \(saved) place\(saved == 1 ? "" : "s").\(coinLine)") }
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let circle) = result else {
                    return self.showSuccess("Saved \(saved) place\(saved == 1 ? "" : "s").\(coinLine)")
                }
                // Back from the circle goes where Add from photos started.
                // Swap screens first: UIKit ignores a navigation change while
                // this screen is presenting the "Saved" message
                guard let nav = self.navigationController else { return }
                var stack = nav.viewControllers
                if let hub = stack.firstIndex(where: { $0 is AddFromPhotosViewController || $0 is PhotoMapBuilderViewController }) {
                    stack.removeSubrange(hub...)
                } else {
                    stack.removeAll { $0 === self }
                }
                let detail = CircleDetailViewController(circle: circle)
                stack.append(detail)
                nav.setViewControllers(stack, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    AlertPresenter.showBriefMessage("Saved \(saved) place\(saved == 1 ? "" : "s") to \(circle.name).\(coinLine)",
                                                    from: detail, duration: 2.0)
                }
            }
        }
    }

    /// Closes the saving box, then continues — even when the box never made it
    /// on screen (a dismiss with nothing presented never calls back)
    private static func end(_ loading: UIAlertController, then: @escaping () -> Void) {
        if loading.presentingViewController != nil {
            loading.dismiss(animated: true, completion: then)
        } else {
            DispatchQueue.main.async(execute: then)
        }
    }

    private static func address(_ p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea, p.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

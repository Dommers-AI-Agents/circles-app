import UIKit
import MapKit

/// What someone sees after scanning a place or set QR (Scan Actions,
/// 2026-11-11): who shared it, the places on a map and in a list, all
/// ticked except the ones they already have, then a circle to save them to.
/// Every save goes through the server's core save (one venue record, the
/// duplicate check, FavCoins), and the sharer gets the credit.
final class ScanPlacesReviewViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate, CreateCircleDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let action: ScanAction
    private let places: [ScanAction.Place]
    private var circles: [Circle]
    private var selected: Set<String>
    private var circle: Circle?
    /// One per tap of Save: a resend on a weak signal never saves twice
    private var requestId = UUID().uuidString
    private var isSaving = false

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let header = UIStackView()
    private let mapView = MKMapView()
    private lazy var saveButton = UIButton.primaryButton(title: "Save")
    private let circleButton = UIButton(type: .system)

    init(action: ScanAction, places: [ScanAction.Place], preselected: Set<String>, circles: [Circle]) {
        self.action = action
        self.places = places
        self.selected = preselected
        self.circles = circles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.groupedBackground
        title = places.count == 1 ? "Save This Place" : "Save These Places"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.largeTitleDisplayMode = .never

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.allowsSelection = places.count > 1

        circleButton.configuration = {
            var config = UIButton.Configuration.gray()
            config.image = UIImage(systemName: "circle.grid.2x2")
            config.imagePadding = 8
            config.cornerStyle = .large
            return config
        }()
        circleButton.addTarget(self, action: #selector(chooseCircleTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [circleButton, saveButton])
        footer.axis = .vertical
        footer.spacing = 10
        footer.isLayoutMarginsRelativeArrangement = true
        footer.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        footer.backgroundColor = Constants.Colors.groupedBackground
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        buildHeader()
        refreshFooter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let size = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if tableView.tableHeaderView?.frame.height != size.height {
            header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
            tableView.tableHeaderView = header
        }
    }

    // MARK: - Header: who shared it, the map

    private func buildHeader() {
        header.axis = .vertical
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 20)

        let from = UILabel()
        from.font = .preferredFont(forTextStyle: .subheadline)
        from.adjustsFontForContentSizeCategory = true
        from.textColor = Constants.Colors.secondaryLabel
        from.numberOfLines = 0
        let who = action.creator?.displayName
        from.text = who.map { places.count == 1 ? "From \($0)" : "\($0) shared \(places.count) places" }
        from.isHidden = from.text == nil

        let heading = UILabel()
        heading.text = places.count == 1 ? places[0].name : (action.title ?? "Places")
        let base = UIFont.systemFont(ofSize: 28, weight: .bold)
        heading.font = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: 28)
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0

        let note = UILabel()
        note.text = action.note.map { "“\($0)”" }
        note.font = .preferredFont(forTextStyle: .body)
        note.adjustsFontForContentSizeCategory = true
        note.numberOfLines = 0
        note.isHidden = action.note == nil

        header.addArrangedSubview(from)
        header.addArrangedSubview(heading)
        header.addArrangedSubview(note)

        let pins = places.compactMap { place -> MKPointAnnotation? in
            guard let spot = place.location else { return nil }
            let pin = MKPointAnnotation()
            pin.coordinate = CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lng)
            pin.title = place.name
            return pin
        }
        if !pins.isEmpty {
            mapView.isUserInteractionEnabled = false
            mapView.layer.cornerRadius = 14
            mapView.layer.cornerCurve = .continuous
            mapView.pointOfInterestFilter = .excludingAll
            mapView.translatesAutoresizingMaskIntoConstraints = false
            mapView.heightAnchor.constraint(equalToConstant: places.count == 1 ? 140 : 180).isActive = true
            mapView.addAnnotations(pins)
            header.setCustomSpacing(14, after: note)
            header.addArrangedSubview(mapView)
            DispatchQueue.main.async { [weak self] in
                self?.mapView.showAnnotations(pins, animated: false)
                if pins.count == 1, let pin = pins.first {
                    self?.mapView.setRegion(MKCoordinateRegion(center: pin.coordinate, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
                }
            }
        }
    }

    // MARK: - Footer

    private func refreshFooter() {
        var config = circleButton.configuration
        config?.title = circle.map { "Save to \($0.name)" } ?? "Choose a Circle"
        config?.subtitle = circle == nil ? nil : "Change"
        circleButton.configuration = config
        let count = selected.count
        saveButton.setTitle(count <= 1 ? "Save" : "Save \(count) Places", for: .normal)
        saveButton.isEnabled = count > 0 && !isSaving
        saveButton.alpha = saveButton.isEnabled ? 1 : 0.5
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { places.count }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        places.count > 1 ? "Tap a place to leave it out." : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let place = places[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = place.name
        let detail = [place.category.map { PlaceCategory(rawValue: $0)?.displayName ?? $0.capitalized }, place.address]
            .compactMap { $0 }.joined(separator: " · ")
        content.secondaryText = place.alreadySaved == true ? "On your map" : detail
        content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.backgroundColor = .secondarySystemGroupedBackground
        if place.alreadySaved == true {
            cell.accessoryView = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
            cell.accessoryView?.tintColor = Constants.Colors.secondaryLabel
            cell.selectionStyle = .none
        } else if places.count > 1 {
            let on = selected.contains(place.globalPlaceId)
            let mark = UIImageView(image: UIImage(systemName: on ? "checkmark.circle.fill" : "circle"))
            mark.tintColor = on ? Constants.Colors.primary : Constants.Colors.secondaryLabel
            cell.accessoryView = mark
            cell.accessibilityTraits = on ? [.button, .selected] : .button
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let place = places[indexPath.row]
        guard place.alreadySaved != true, places.count > 1 else { return }
        if selected.contains(place.globalPlaceId) { selected.remove(place.globalPlaceId) } else { selected.insert(place.globalPlaceId) }
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshFooter()
    }

    // MARK: - Circle

    @objc private func chooseCircleTapped() {
        presentCirclePicker(thenSave: false)
    }

    private func presentCirclePicker(thenSave: Bool) {
        let picker = CirclePickerViewController(circles: circles)
        picker.pickerTitle = "Save to a Circle"
        if places.count == 1 {
            picker.placeName = places[0].name
            picker.placeAddress = places[0].address
        }
        picker.onCircleSelected = { [weak self] circle in
            guard let self else { return }
            self.circle = circle
            self.refreshFooter()
            if thenSave { self.save() }
        }
        picker.onCreateNewCircle = { [weak self] in
            guard let self else { return }
            self.saveAfterCreate = thenSave
            let create = CreateCircleViewController()
            create.delegate = self
            self.present(UINavigationController(rootViewController: create), animated: true)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        nav.sheetPresentationController?.detents = [.medium(), .large()]
        nav.sheetPresentationController?.prefersGrabberVisible = true
        present(nav, animated: true)
    }

    private var saveAfterCreate = false

    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        self.circle = circle
        refreshFooter()
        if saveAfterCreate {
            saveAfterCreate = false
            // After the create sheet is gone
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.save() }
        }
    }

    // MARK: - Save

    @objc private func saveTapped() {
        // Always a circle they chose (never a silent default)
        guard circle != nil else { return presentCirclePicker(thenSave: true) }
        save()
    }

    private func save() {
        guard let circle, !isSaving, !selected.isEmpty else { return }
        isSaving = true
        refreshFooter()
        let ids = places.map(\.globalPlaceId).filter { selected.contains($0) }
        let loading = AlertPresenter.showLoading(message: ids.count == 1 ? "Saving…" : "Saving \(ids.count) places…", from: self)
        ScanActionService.shared.savePlaces(code: action.code, globalPlaceIds: ids, circleId: circle.id, requestId: requestId) { [weak self] result in
            loading.dismiss(animated: true) {
                guard let self else { return }
                self.isSaving = false
                switch result {
                case .success(let done):
                    // A new tap of Save is a new request from here on
                    self.requestId = UUID().uuidString
                    self.finish(done, in: circle)
                case .failure(let error):
                    self.refreshFooter()
                    self.showError((error as? ScanActionService.Refusal)?.message ?? FriendlyError.message(for: error))
                }
            }
        }
    }

    private func finish(_ done: ScanActionSaveResult, in circle: Circle) {
        AnalyticsService.shared.logEvent("scan_action_saved", parameters: ["count": done.saved.count, "kind": action.kind.rawValue])
        if !done.saved.isEmpty {
            NotificationCenter.default.post(name: .refreshCircles, object: nil)
            NotificationCenter.default.post(name: .placeAdded, object: nil)
        }
        let words = ScanActionCopy.saved(done, circleName: circle.name)
        let openCircle = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                if done.saved.count == 1, let placeId = done.saved[0].placeId {
                    NotificationCenter.default.post(name: .navigateToPlace, object: placeId)
                } else {
                    NextStepNavigator.push(CircleDetailViewController(circle: circle))
                }
            }
        }
        if done.failed.contains(where: { $0.upgradeRequired == true }) {
            AlertPresenter.showAlert(title: words.title, message: words.message, actions: [
                ("See Plans", .default, { [weak self] in
                    guard let self else { return }
                    SubscriptionManager.shared.showPaywall(from: self, reason: .placeLimit)
                }),
                ("Done", .cancel, { [weak self] in self?.dismiss(animated: true) })
            ], from: self)
            return
        }
        let close: (title: String, style: UIAlertAction.Style, handler: () -> Void) = ("Done", .cancel, { [weak self] in self?.dismiss(animated: true) })
        let actions = done.saved.isEmpty ? [close]
            : [(done.saved.count == 1 ? "Open It" : "Open \(circle.name)", UIAlertAction.Style.default, openCircle), close]
        AlertPresenter.showAlert(title: words.title, message: words.message.isEmpty ? nil : words.message, actions: actions, from: self)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

import UIKit
import MapKit

/// The stops found in your photos, each matched to the business there:
/// keep the ones you want, name the circle, and it's made — places, a photo
/// on each, on your map unless you say otherwise (Wes, 2026-10-09).
final class PhotoScanReviewViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {

    /// Apple Maps lookups are rate-limited; a long range keeps its busiest stops
    static let maxSpots = 40

    private struct Row {
        let spot: PhotoLibraryMath.Spot
        var candidates: [MKMapItem] = []
        var choice = 0
        var include = false
        var looked = false
        var item: MKMapItem? { candidates.indices.contains(choice) ? candidates[choice] : nil }
    }

    private var rows: [Row]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let nameField = UITextField()
    private let privacyControl = UISegmentedControl(items: ["Public", "Connections", "Private"])
    private let mapRow = IncludeOnMapRow(isOn: true)   // Wes: scanned circles start on the map
    private lazy var createButton = UIButton.primaryButton(title: "Create circle")

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(spots: [PhotoLibraryMath.Spot], suggestedName: String) {
        rows = spots.map { Row(spot: $0) }
        super.init(nibName: nil, bundle: nil)
        nameField.text = suggestedName
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(rows.count) stop\(rows.count == 1 ? "" : "s")"
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableHeaderView = header()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        view.addSubview(tableView)
        view.addSubview(createButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: createButton.topAnchor, constant: -8),
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            createButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        setupKeyboardHandling(dismissOnTap: true)
        refreshButton()
        lookUp(from: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the header to its content once the table has a width
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: 0),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if header.frame.height != size.height {
            header.frame.size.height = size.height
            tableView.tableHeaderView = header
        }
    }

    private func header() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 220))
        nameField.borderStyle = .roundedRect
        nameField.font = .systemFont(ofSize: 18, weight: .semibold)
        nameField.placeholder = "Circle name"
        privacyControl.selectedSegmentIndex = 1
        let nameLabel = UILabel()
        nameLabel.text = "New circle"
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [nameLabel, nameField, privacyControl, mapRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            nameField.heightAnchor.constraint(equalToConstant: 44)
        ])
        return container
    }

    /// One Apple Maps lookup at a time; each stop takes its nearest business
    private func lookUp(from index: Int) {
        guard index < rows.count else { return }
        NearbyPOILookup.pointsOfInterest(near: rows[index].spot.center, radius: PhotoPlaceRanker.poiRadiusMeters) { [weak self] items in
            guard let self, index < self.rows.count else { return }
            let businesses = items.filter { !AppleMapItemFormFill.isResidentialAddress(name: $0.name) }
            self.rows[index].candidates = Array(businesses.prefix(6))
            self.rows[index].include = !businesses.isEmpty
            self.rows[index].looked = true
            self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            self.refreshButton()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.lookUp(from: index + 1) }
        }
    }

    private func refreshButton() {
        let count = rows.filter { $0.include && $0.item != nil }.count
        createButton.setTitle(count == 0 ? "Create circle" : "Create circle with \(count) place\(count == 1 ? "" : "s")", for: .normal)
        createButton.isEnabled = count > 0
        createButton.alpha = count > 0 ? 1 : 0.5
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Tap to include or leave out · hold to pick a different place"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        let time = DateFormatter.localizedString(from: row.spot.start, dateStyle: .medium, timeStyle: .short)
        let photos = "\(row.spot.shots.count) photo\(row.spot.shots.count == 1 ? "" : "s")"
        if !row.looked {
            cell.textLabel?.text = "Looking up…"
        } else if let item = row.item {
            cell.textLabel?.text = item.name
        } else {
            cell.textLabel?.text = "No business found here"
            cell.textLabel?.textColor = .secondaryLabel
        }
        cell.detailTextLabel?.text = "\(time) · \(photos)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = row.include ? .checkmark : .none
        cell.imageView?.image = UIImage(systemName: "photo")
        cell.imageView?.layer.cornerRadius = 6
        cell.imageView?.clipsToBounds = true
        if let first = row.spot.shots.first {
            PhotoLibraryIndex.shared.image(for: first.id, size: CGSize(width: 88, height: 88)) { [weak cell] image in
                guard let cell, let image else { return }
                cell.imageView?.image = image.preparingThumbnail(of: CGSize(width: 44, height: 44)) ?? image
                cell.setNeedsLayout()
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rows[indexPath.row].item != nil else { return }
        rows[indexPath.row].include.toggle()
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshButton()
    }

    /// Hold a stop: the other businesses there ("Pick the place")
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let row = rows[indexPath.row]
        guard row.candidates.count > 1 else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(title: "Pick the place", children: row.candidates.enumerated().map { index, item in
                UIAction(title: item.name ?? "Place", state: index == row.choice ? .on : .off) { _ in
                    self?.rows[indexPath.row].choice = index
                    self?.rows[indexPath.row].include = true
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                    self?.refreshButton()
                }
            })
        }
    }

    // MARK: - Create

    private var privacy: PrivacyLevel {
        switch privacyControl.selectedSegmentIndex {
        case 0: return .public
        case 2: return .private
        default: return .myNetwork
        }
    }

    @objc private func createTapped() {
        let chosen = rows.filter { $0.include && $0.item != nil }
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !chosen.isEmpty else { return }
        guard !name.isEmpty else { return showError("Give the circle a name.") }
        createButton.isEnabled = false
        let loading = AlertPresenter.showLoading(message: "Creating \(name)…", from: self)
        CircleService.shared.createCircle(name: name, description: nil, privacy: privacy, category: .travel,
                                          showOnMap: mapRow.isOn) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let circle):
                    self.save(chosen, into: circle, index: 0, saved: 0, loading: loading)
                case .failure(let error):
                    loading.dismiss(animated: true) { self.createButton.isEnabled = true; self.showError(error) }
                }
            }
        }
    }

    /// One place at a time, each with its first photo (at the circle's privacy)
    private func save(_ chosen: [Row], into circle: Circle, index: Int, saved: Int, loading: UIAlertController) {
        guard index < chosen.count else {
            loading.dismiss(animated: true) { self.finish(circle: circle, saved: saved, of: chosen.count) }
            return
        }
        loading.message = "Saving \(index + 1) of \(chosen.count)…"
        let row = chosen[index]
        guard let item = row.item else { return save(chosen, into: circle, index: index + 1, saved: saved, loading: loading) }
        let mapping = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: item.name)
        let finishOne: (Bool) -> Void = { [weak self] ok in
            self?.save(chosen, into: circle, index: index + 1, saved: saved + (ok ? 1 : 0), loading: loading)
        }
        let create: (Data?) -> Void = { photo in
            PlaceService.shared.createPlace(
                name: item.name ?? "Place", description: nil, address: Self.address(item.placemark),
                category: mapping.category, subcategory: mapping.subcategory, circleId: circle.id,
                phone: item.phoneNumber, photos: photo.map { [$0] },
                location: item.placemark.coordinate, applePoiCategory: item.pointOfInterestCategory?.rawValue
            ) { result in
                DispatchQueue.main.async { if case .success = result { finishOne(true) } else { finishOne(false) } }
            }
        }
        if let first = row.spot.shots.first {
            PhotoLibraryIndex.shared.uploadImage(for: first.id) { image in create(image?.jpegData(compressionQuality: 0.8)) }
        } else {
            create(nil)
        }
    }

    private func finish(circle: Circle, saved: Int, of total: Int) {
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
        let detail = CircleDetailViewController(circle: circle)
        if var stack = navigationController?.viewControllers {
            // Back from the new circle goes where the scan started
            stack.removeAll { $0 is PhotoScanReviewViewController || $0 is PhotoScanViewController || $0 is PhotoScanDatesViewController }
            stack.append(detail)
            navigationController?.setViewControllers(stack, animated: true)
        }
        if saved < total {
            // Said on the new circle's screen (this one has left the stack)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak detail] in
                detail?.showError("\(saved) of \(total) places were saved. Try adding the rest from the circle.")
            }
        }
    }

    private static func address(_ p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea, p.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

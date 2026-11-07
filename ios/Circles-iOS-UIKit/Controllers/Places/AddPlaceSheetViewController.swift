import UIKit
import MapKit

/// Add Place (Wes, 2026-11-07): a sheet built around "where are you?" — the
/// places right around you, each one tap to save, then search by name, pick
/// on the map, or your photos.
final class AddPlaceSheetViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    var onSearch: (() -> Void)?
    var onMap: (() -> Void)?
    var onPhotos: (() -> Void)?
    /// Which circle a one-tap save goes to, and the names already on their map
    private let circles: [Circle]
    private let savedNames: Set<String>

    private var nearby: [(place: Place, item: MKMapItem)] = []
    private var savedHere = Set<String>()
    private let stack = UIStackView()
    private let nearSection = UIStackView()
    private let chipRow = UIStackView()

    init(circles: [Circle], savedNames: Set<String>) {
        self.circles = circles
        self.savedNames = Set(savedNames.map { $0.lowercased() })
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        let title = UILabel()
        title.text = AddPlaceSheetCopy.title
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)

        // You're near: filled in when the search returns; hidden without a location
        nearSection.axis = .vertical
        nearSection.spacing = 8
        nearSection.isHidden = true
        let nearLabel = UILabel()
        nearLabel.text = AddPlaceSheetCopy.nearTitle
        nearLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nearLabel.textColor = .secondaryLabel
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        chipRow.axis = .horizontal
        chipRow.spacing = 8
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(chipRow)
        NSLayoutConstraint.activate([
            chipRow.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            chipRow.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            chipRow.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            chipRow.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            chipRow.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 40)
        ])
        nearSection.addArrangedSubview(nearLabel)
        nearSection.addArrangedSubview(scroll)
        stack.addArrangedSubview(nearSection)

        stack.addArrangedSubview(row(AddPlaceSheetCopy.searchTitle, AddPlaceSheetCopy.searchDetail, "magnifyingglass") { [weak self] in self?.close(then: self?.onSearch) })
        stack.addArrangedSubview(row(AddPlaceSheetCopy.mapTitle, AddPlaceSheetCopy.mapDetail, "map") { [weak self] in self?.close(then: self?.onMap) })
        stack.addArrangedSubview(row(AddPlaceSheetCopy.photosTitle, AddPlaceSheetCopy.photosDetail, "photo.on.rectangle") { [weak self] in self?.close(then: self?.onPhotos) })

        loadNearby()
    }

    private func close(then action: (() -> Void)?) {
        dismiss(animated: true) { action?() }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> UIView {
        let button = UIButton.rowButton(title: title, systemName: symbol)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        let caption = UILabel()
        caption.text = detail
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabel
        let box = UIStackView(arrangedSubviews: [button, caption])
        box.axis = .vertical
        box.spacing = 4
        return box
    }

    // MARK: - You're near

    private func loadNearby() {
        guard let here = LocationService.shared.lastKnownLocation else { return }
        let request = MKLocalPointsOfInterestRequest(center: here.coordinate, radius: AddPlaceSheetCopy.nearbyRadius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: Array(AddPlaceSheetCopy.skipped))
        MKLocalSearch(request: request).start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self, let items = response?.mapItems, !items.isEmpty else { return }
                let measured = items.compactMap { item -> (item: MKMapItem, name: String, distance: CLLocationDistance)? in
                    guard let name = item.name, !name.isEmpty else { return nil }
                    let c = item.placemark.coordinate
                    return (item, name, here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)))
                }
                let names = AddPlaceSheetCopy.nearest(measured.map { ($0.name, $0.distance) })
                self.nearby = names.compactMap { name in
                    measured.first { $0.name == name }.map {
                        (NearbyPlaceSearch.newPlace(from: $0.item, name: $0.name, address: $0.item.placemark.title ?? ""), $0.item)
                    }
                }
                self.showChips()
            }
        }
    }

    private func showChips() {
        chipRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, entry) in nearby.enumerated() {
            let place = entry.place
            let isSaved = savedNames.contains(place.name.lowercased()) || savedHere.contains(place.name)
            let chip = UIButton.smallActionButton(title: isSaved ? "\u{2713} \(place.name)" : place.name,
                                                  style: isSaved ? .secondary : .primary)
            chip.setImage(isSaved ? nil : UIImage(systemName: place.category.systemIconName), for: .normal)
            chip.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            chip.tag = index
            chip.isEnabled = !isSaved
            chip.addAction(UIAction { [weak self] _ in self?.save(index) }, for: .touchUpInside)
            chipRow.addArrangedSubview(chip)
        }
        nearSection.isHidden = nearby.isEmpty
    }

    /// One tap: into the circle they last saved to (else Favorite Local Spots)
    private func save(_ index: Int) {
        guard nearby.indices.contains(index) else { return }
        let (place, item) = nearby[index]
        let lastUsed = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey)
        guard let circle = circles.first(where: { $0.id == lastUsed })
                ?? SystemCircles.first(.favoriteLocal, in: circles) ?? circles.first else {
            close(then: onSearch)
            return
        }
        savedHere.insert(place.name)
        showChips()
        AnalyticsService.shared.logEvent("add_place_sheet_nearby_saved", parameters: ["category": place.category.rawValue])
        // Apple's category, phone and website: a place a map knows, never
        // the approval queue (backend placeApproval)
        PlaceService.shared.createPlace(name: place.name, description: nil, address: place.address, category: place.category,
                                        subcategory: place.subcategory, circleId: circle.id,
                                        website: item.url?.absoluteString, phone: item.phoneNumber,
                                        location: item.placemark.coordinate,
                                        applePoiCategory: item.pointOfInterestCategory?.rawValue,
                                        offersPostSaveNudges: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let saved):
                    NotificationCenter.default.post(name: .placeAdded, object: nil)
                    NotificationCenter.default.post(name: .placeAddedToCircle, object: nil,
                                                    userInfo: ["circleId": circle.id, "place": saved])
                    CelebrationBurst.show(AddPlaceSheetCopy.saved(in: circle.name), over: self.view)
                case .failure(let error):
                    self.savedHere.remove(place.name)
                    self.showChips()
                    self.showError(error)
                }
            }
        }
    }
}

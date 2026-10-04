import UIKit
import MapKit
import PhotosUI

/// "Add Place → From photos": the photos you picked, grouped by where they
/// were taken, one card per spot with the place they were most likely taken
/// at. A spot you've already saved offers to add the photos there; a new one
/// opens the usual Add Place form filled in, and the photos join the place
/// once it's saved (PendingPlacePhotos). Built for days out with no signal
/// (Wes, 2026-10-04): GPS works without one, and the photos remember it.
final class PhotoPlacesViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { true }

    private struct Card {
        let group: PhotoPlaceGrouper.Group
        let images: [UIImage]
        var mapItems: [MKMapItem] = []
        var picks: [PhotoPlaceRanker.Pick] = []
        var choice: Int = 0              // index into picks
        var done: String?                // "Saved to Coffee Spots" etc.
        var busy = false
    }

    private let picked: [PhotoMetadataReader.Picked]
    private let savedPlaces: [Place]
    private let circles: [Circle]
    private let defaultCircleId: String
    private var cards: [Card] = []

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(picked: [PhotoMetadataReader.Picked], savedPlaces: [Place], circles: [Circle], defaultCircleId: String) {
        self.picked = picked
        self.savedPlaces = savedPlaces
        self.circles = circles
        self.defaultCircleId = defaultCircleId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Places from your photos"
        view.backgroundColor = Constants.Colors.background
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()   // a save in the form behind may have finished
    }

    // MARK: - Data

    override func loadData(completion: (() -> Void)? = nil) {
        let groups = PhotoPlaceGrouper.group(picked.enumerated().map {
            PhotoPlaceGrouper.Fix(id: $0.offset, coordinate: $0.element.coordinate, takenAt: $0.element.takenAt)
        })
        cards = groups.map { Card(group: $0, images: $0.photoIds.map { picked[$0].image }) }
        guard NetworkMonitor.shared.isConnected else {
            render()
            showError("You're offline. Connect to look up these places — your photos keep their locations.")
            completion?()
            return
        }
        let lookups = DispatchGroup()
        for i in cards.indices {
            guard let center = cards[i].group.center else { continue }
            lookups.enter()
            NearbyPOILookup.pointsOfInterest(near: center, radius: PhotoPlaceRanker.poiRadiusMeters) { [weak self] items in
                defer { lookups.leave() }
                guard let self else { return }
                self.cards[i].mapItems = items
                self.cards[i].picks = PhotoPlaceRanker.rank(center: center, saved: self.rankableSaves, pois: items.map {
                    PhotoPlaceRanker.POI(name: $0.name ?? "", coordinate: $0.placemark.coordinate,
                                         isResidential: AppleMapItemFormFill.isResidentialAddress(name: $0.name))
                })
            }
        }
        lookups.notify(queue: .main) { [weak self] in
            self?.render()
            completion?()
        }
    }

    private var rankableSaves: [PhotoPlaceRanker.Saved] {
        savedPlaces.compactMap { place in
            guard let c = place.location?.clLocation?.coordinate else { return nil }
            return PhotoPlaceRanker.Saved(id: place.id, name: place.name, coordinate: c)
        }
    }

    // MARK: - Cards

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let intro = UILabel()
        intro.text = cards.count == 1
            ? "Where your photos were taken."
            : "Your photos were taken at \(cards.filter { $0.group.center != nil }.count) spots. Save each one, or skip it."
        intro.font = .systemFont(ofSize: 15)
        intro.textColor = Constants.Colors.secondaryLabel
        intro.numberOfLines = 0
        stack.addArrangedSubview(intro)
        for i in cards.indices { stack.addArrangedSubview(cardView(i)) }
    }

    private func cardView(_ i: Int) -> UIView {
        let card = cards[i]
        let box = UIView()
        box.backgroundColor = Constants.Colors.secondaryBackground
        box.layer.cornerRadius = 14
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            column.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            column.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            column.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14)
        ])

        column.addArrangedSubview(thumbnails(card.images))
        if let taken = card.group.takenAt {
            column.addArrangedSubview(label(Self.whenFormatter.string(from: taken), size: 13, color: Constants.Colors.secondaryLabel))
        }

        if let done = card.done {
            column.addArrangedSubview(label("✓ " + done, size: 16, weight: .semibold, color: .systemGreen))
            return box
        }
        guard card.group.center != nil else {
            column.addArrangedSubview(label("These photos don't say where they were taken.", size: 16, weight: .semibold))
            column.addArrangedSubview(label("Their location may be switched off. Search for the place, and the photos are added when you save it.",
                                            size: 13, color: Constants.Colors.secondaryLabel))
            column.addArrangedSubview(button("Search for the place", primary: true) { [weak self] in self?.search(i) })
            return box
        }
        guard !card.picks.isEmpty else {
            column.addArrangedSubview(label("No business listed where these were taken.", size: 16, weight: .semibold))
            column.addArrangedSubview(button("Search nearby", primary: true) { [weak self] in self?.search(i) })
            return box
        }

        let pick = card.picks[card.choice]
        let (title, detail, action): (String, String, String)
        switch pick {
        case .saved(let id, let meters):
            let place = savedPlaces.first { $0.id == id }
            title = place?.name ?? "Your saved place"
            detail = ["Already saved" + (place?.circleName.map { " in \($0)" } ?? ""), Self.distance(meters)].joined(separator: " · ")
            action = card.images.count == 1 ? "Add the photo" : "Add \(card.images.count) photos"
        case .poi(let index, let meters):
            let item = card.mapItems[index]
            title = item.name ?? "This place"
            detail = [Self.address(item), Self.distance(meters)].filter { !$0.isEmpty }.joined(separator: " · ")
            action = "Save this place"
        }
        column.addArrangedSubview(label(title, size: 20, weight: .bold))
        column.addArrangedSubview(label(detail, size: 14, color: Constants.Colors.secondaryLabel))

        let primary = button(card.busy ? "Adding…" : action, primary: true) { [weak self] in self?.confirm(i) }
        primary.isEnabled = !card.busy
        let other = button("Not this place?", primary: false) { }
        other.menu = alternativesMenu(i)
        other.showsMenuAsPrimaryAction = true
        let row = UIStackView(arrangedSubviews: [primary, other])
        row.spacing = 10
        row.distribution = .fillEqually
        column.addArrangedSubview(row)
        return box
    }

    private func alternativesMenu(_ i: Int) -> UIMenu {
        let card = cards[i]
        var actions: [UIMenuElement] = card.picks.indices.filter { $0 != card.choice }.prefix(8).map { j in
            let name: String
            switch card.picks[j] {
            case .saved(let id, _): name = (savedPlaces.first { $0.id == id }?.name ?? "Saved place") + " (saved)"
            case .poi(let index, let meters): name = "\(card.mapItems[index].name ?? "Place") · \(Self.distance(meters))"
            }
            return UIAction(title: name) { [weak self] _ in
                self?.cards[i].choice = j
                self?.render()
            }
        }
        actions.append(UIAction(title: "Search…", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in self?.search(i) })
        return UIMenu(children: actions)
    }

    // MARK: - Actions

    private func confirm(_ i: Int) {
        switch cards[i].picks[cards[i].choice] {
        case .saved(let id, _):
            guard let place = savedPlaces.first(where: { $0.id == id }) else { return }
            cards[i].busy = true
            render()
            PlacePhotoBatchUploader.upload(cards[i].images, to: place, progress: { _, _ in }) { [weak self] added, failed in
                guard let self else { return }
                self.cards[i].busy = false
                self.cards[i].done = failed == 0
                    ? "Added \(added.count) to \(place.name)"
                    : "Added \(added.count) to \(place.name); \(failed) didn't upload"
                self.render()
            }
        case .poi(let index, _):
            let item = cards[i].mapItems[index]
            openForm(card: i, prefill: item, near: item.placemark.coordinate)
        }
    }

    private func search(_ i: Int) {
        openForm(card: i, prefill: nil, near: cards[i].group.center)
    }

    /// The usual Add Place form; when it saves a place here, the photos go
    /// into it and this card says so.
    private func openForm(card i: Int, prefill: MKMapItem?, near: CLLocationCoordinate2D?) {
        let form = AddPlaceViewController(circleId: defaultCircleId, circles: circles)
        form.prefillMapItem = prefill
        form.returnsToCallerAfterSave = true
        if prefill == nil, let near { form.prefillCenter = near }
        PendingPlacePhotos.shared.expect(cards[i].images, near: near ?? prefill?.placemark.coordinate) { [weak self] attached in
            guard let self, self.cards.indices.contains(i) else { return }
            self.cards[i].done = "Saved \(attached.place.name)" + (attached.added > 0 ? " with \(attached.added) photo\(attached.added == 1 ? "" : "s")" : "")
            self.render()
        }
        navigationController?.pushViewController(form, animated: true)
    }

    // MARK: - Bits

    private func thumbnails(_ images: [UIImage]) -> UIView {
        let row = UIStackView()
        row.spacing = 6
        for image in images.prefix(4) {
            let v = UIImageView(image: image)
            v.contentMode = .scaleAspectFill
            v.clipsToBounds = true
            v.layer.cornerRadius = 8
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 72).isActive = true
            v.heightAnchor.constraint(equalToConstant: 72).isActive = true
            row.addArrangedSubview(v)
        }
        if images.count > 4 {
            row.addArrangedSubview(label("+\(images.count - 4)", size: 15, weight: .semibold, color: Constants.Colors.secondaryLabel))
        }
        row.addArrangedSubview(UIView())
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.numberOfLines = 0
        return l
    }

    private func button(_ title: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
        let b = primary ? UIButton.primaryButton(title: title) : UIButton.secondaryButton(title: title)
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private static let whenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()

    private static func distance(_ meters: Double) -> String {
        let f = MKDistanceFormatter()
        f.unitStyle = .abbreviated
        return f.string(fromDistance: meters) + " from your photos"
    }

    private static func address(_ item: MKMapItem) -> String {
        let p = item.placemark
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

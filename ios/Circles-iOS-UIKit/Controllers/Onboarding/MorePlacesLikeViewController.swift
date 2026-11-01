import UIKit
import CoreLocation

/// First run, after their first favorite (Wes, 2026-11-01): "More places like
/// Sal's". Real places nearby from the FavCircles catalog, as photo cards
/// they tap to pick, plus the usual search for any place, and their photos as
/// one more way in (it used to be photos only, behind a page of reasons).
/// Picked places go into Favorite Local Spots.
final class MorePlacesLikeViewController: BaseViewController, UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    /// Called with how many places they added (0 for Not now)
    var onFinished: ((Int) -> Void)?

    /// One card: a catalog place (with a photo) or a search result
    struct Pick: Hashable {
        let key: String
        let name: String
        let detail: String
        let address: String
        let photoURL: String?
        let category: PlaceCategory
        let coordinate: CLLocationCoordinate2D?
        let googlePlaceId: String?

        static func == (a: Pick, b: Pick) -> Bool { a.key == b.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    private let favorite: Place?
    private let favoriteName: String?
    private var origin: CLLocation
    private var suggestions: [Pick] = []
    private var searchResults: [Pick] = []
    private var isSearching: Bool { !(searchField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var shown: [Pick] { isSearching ? searchResults : suggestions }
    private var picked: [Pick] = []
    private var searchTimer: Timer?
    private let appleSearch = NearbyPlaceSearch()
    private var circles: [Circle] = []
    private var saving = false

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let searchField = UITextField()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusLabel = UILabel()
    private lazy var addButton = UIButton.primaryButton(title: "Not now")
    private lazy var photosButton = UIButton.rowButton(title: "Find them in my photos", systemName: "photo.on.rectangle.angled")

    init(favorite: Place?, favoriteName: String? = nil) {
        self.favorite = favorite
        self.favoriteName = favorite?.name ?? favoriteName
        let cached = LocationService.shared.cachedLocation
        let fav = favorite?.location?.clLocation
        let fallback = CLLocation(latitude: Constants.DefaultLocation.coordinate.latitude,
                                  longitude: Constants.DefaultLocation.coordinate.longitude)
        self.origin = cached ?? fav ?? fallback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.groupedBackground
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()
        loadSuggestions()
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async { if case .success(let circles) = result { self?.circles = circles } }
        }
        AnalyticsService.shared.logEvent("more_places_shown", parameters: ["has_favorite": favorite != nil])
    }

    // MARK: - Layout

    private func setupUI() {
        titleLabel.text = FirstFavoriteCopy.morePlacesTitle(placeName: favoriteName)
        titleLabel.font = Self.serif(32)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        subtitleLabel.text = "Tap the ones you love. They go on your map."
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = Constants.Colors.secondaryLabel
        subtitleLabel.numberOfLines = 0

        searchField.placeholder = "Search for a place you love"
        searchField.backgroundColor = Constants.Colors.secondaryBackground
        searchField.layer.cornerRadius = 14
        searchField.font = .systemFont(ofSize: 17)
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.autocorrectionType = .no
        searchField.delegate = self
        let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        glass.tintColor = Constants.Colors.secondaryLabel
        glass.contentMode = .center
        glass.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        searchField.leftView = glass
        searchField.leftViewMode = .always
        searchField.heightAnchor.constraint(equalToConstant: 48).isActive = true
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = Constants.Colors.secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "Finding places near you\u{2026}"

        photosButton.addTarget(self, action: #selector(photosTapped), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        collectionView.register(PickCell.self, forCellWithReuseIdentifier: PickCell.reuseId)
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: HeaderView.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let footer = UIStackView(arrangedSubviews: [photosButton, addButton])
        footer.axis = .vertical
        footer.spacing = 10
        footer.isLayoutMarginsRelativeArrangement = true
        footer.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 8, right: 20)
        footer.backgroundColor = Constants.Colors.groupedBackground
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(200)),
                                                       subitems: [item, item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 16, trailing: 14)
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(200)),
            elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Data

    /// Places like their favorite, nearest first, from the catalog (real
    /// places other people saved, with photos); a mix when there's no favorite
    private func loadSuggestions() {
        let categories = FirstFavoriteCopy.similarCategories(to: favorite?.category)
        let group = DispatchGroup()
        var found: [GlobalPlace] = []
        for category in categories {
            group.enter()
            GlobalPlaceService.shared.searchGlobalPlaces(category: category,
                                                        location: (origin.coordinate.latitude, origin.coordinate.longitude),
                                                        limit: 12) { result in
                if case .success(let places) = result { found.append(contentsOf: places) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var seen = Set<String>()
            let favoriteName = self.favoriteName?.lowercased()
            self.suggestions = found
                .filter { $0.name.lowercased() != favoriteName }
                .map(self.pick(from:))
                .filter { seen.insert($0.name.lowercased()).inserted }
                .sorted { ($0.photoURL != nil ? 0 : 1, $0.distanceRank(from: self.origin)) < ($1.photoURL != nil ? 0 : 1, $1.distanceRank(from: self.origin)) }
            self.statusLabel.text = self.suggestions.isEmpty
                ? "Search for the places you love, or find them in your photos."
                : "Popular near you"
            self.collectionView.reloadData()
        }
    }

    private func pick(from place: GlobalPlace) -> Pick {
        let photo = place.coverPhotoUrl ?? place.photos?.first?.url
        let coordinate = place.location?.clLocation?.coordinate
        return Pick(key: "g:\(place.id)", name: place.name, detail: distanceText(to: coordinate) ?? place.category.displayName,
                    address: place.address, photoURL: photo, category: place.category,
                    coordinate: coordinate, googlePlaceId: place.googlePlaceId)
    }

    private func pick(from place: Place) -> Pick {
        let coordinate = place.location?.clLocation?.coordinate
        return Pick(key: "a:\(place.name.lowercased())|\(place.address.lowercased())", name: place.name,
                    detail: distanceText(to: coordinate) ?? place.address, address: place.address,
                    photoURL: place.photos?.first, category: place.category, coordinate: coordinate,
                    googlePlaceId: place.googlePlaceId)
    }

    private func distanceText(to coordinate: CLLocationCoordinate2D?) -> String? {
        guard let coordinate else { return nil }
        let miles = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1609.34
        return miles < 0.1 ? "Right here" : String(format: miles < 10 ? "%.1f mi away" : "%.0f mi away", miles)
    }

    @objc private func searchChanged() {
        searchTimer?.invalidate()
        guard isSearching else {
            statusLabel.text = suggestions.isEmpty ? statusLabel.text : "Popular near you"
            collectionView.reloadData()
            return
        }
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.runSearch() }
    }

    /// The catalog first (photos), then Apple Maps for anything else
    private func runSearch() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return }
        statusLabel.text = "Searching\u{2026}"
        let group = DispatchGroup()
        var catalog: [Pick] = []
        var apple: [Pick] = []
        group.enter()
        GlobalPlaceService.shared.searchGlobalPlaces(query: query, location: (origin.coordinate.latitude, origin.coordinate.longitude),
                                                    limit: 12) { [weak self] result in
            if case .success(let places) = result, let self { catalog = places.map(self.pick(from:)) }
            group.leave()
        }
        group.enter()
        appleSearch.searchVenues(query: query, near: origin) { [weak self] result in
            if case .success(let places) = result, let self { apple = places.map(self.pick(from:)) }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, (self.searchField.text ?? "").trimmingCharacters(in: .whitespaces) == query else { return }
            var seen = Set(catalog.map { $0.name.lowercased() })
            self.searchResults = catalog + apple.filter { seen.insert($0.name.lowercased()).inserted }
            self.statusLabel.text = self.searchResults.isEmpty ? "No places found for \u{201C}\(query)\u{201D}" : "Results for \u{201C}\(query)\u{201D}"
            self.collectionView.reloadData()
        }
    }

    // MARK: - Picking

    private func toggle(_ pick: Pick) {
        if let index = picked.firstIndex(of: pick) {
            picked.remove(at: index)
        } else {
            picked.append(pick)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        let count = picked.count
        addButton.setTitle(count == 0 ? "Not now" : "Add \(count) place\(count == 1 ? "" : "s") to my map", for: .normal)
        collectionView.reloadData()
    }

    @objc private func addTapped() {
        guard !saving else { return }
        guard !picked.isEmpty else {
            AnalyticsService.shared.logEvent("more_places_skipped", parameters: [:])
            onFinished?(0)
            return
        }
        guard let circle = SystemCircles.first(.favoriteLocal, in: circles) ?? circles.first else {
            CircleService.shared.fetchUserCircles { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let circles) = result, !circles.isEmpty {
                        self.circles = circles
                        self.addTapped()
                    } else {
                        self.showError("Oops, something went wrong. Please try again.")
                    }
                }
            }
            return
        }
        saving = true
        addButton.isEnabled = false
        addButton.setTitle("Adding\u{2026}", for: .normal)
        let group = DispatchGroup()
        var added = 0
        for pick in picked {
            group.enter()
            PlaceService.shared.createPlace(name: pick.name, description: nil, address: pick.address, category: pick.category,
                                            circleId: circle.id, location: pick.coordinate,
                                            googlePlaceId: pick.googlePlaceId) { result in
                if case .success = result { added += 1 }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.saving = false
            NotificationCenter.default.post(name: .placeAdded, object: nil)
            AnalyticsService.shared.logEvent("more_places_added", parameters: ["count": added])
            CelebrationBurst.show("\(added) more on your map", over: self.view)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.onFinished?(added) }
        }
    }

    @objc private func photosTapped() {
        AnalyticsService.shared.logEvent("more_places_photos", parameters: [:])
        let builder = PhotoMapBuilderViewController(savedPlaces: [], circles: circles, startsImmediately: true)
        builder.onFinished = { [weak self] in self?.onFinished?(0) }
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(builder, animated: true)
    }

    // MARK: - Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PickCell.reuseId, for: indexPath) as! PickCell
        let pick = shown[indexPath.item]
        cell.configure(pick, picked: picked.contains(pick))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeaderView.reuseId,
                                                                     for: indexPath) as! HeaderView
        header.install([titleLabel, subtitleLabel, searchField, statusLabel])
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        toggle(shown[indexPath.item])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Look

    private static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Title, subtitle, search and status above the cards
    private final class HeaderView: UICollectionReusableView {
        static let reuseId = "MorePlacesHeader"
        private let stack = UIStackView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            stack.axis = .vertical
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func install(_ views: [UIView]) {
            guard stack.arrangedSubviews.isEmpty else { return }
            views.forEach(stack.addArrangedSubview)
            stack.setCustomSpacing(6, after: views[0])
            stack.setCustomSpacing(16, after: views[1])
        }
    }

    /// A photo card: the place's picture (or its category's color), name and
    /// distance over a soft shade, a check when picked
    private final class PickCell: UICollectionViewCell {
        static let reuseId = "MorePlacesPick"
        private let imageView = UIImageView()
        private let shade = CAGradientLayer()
        private let nameLabel = UILabel()
        private let detailLabel = UILabel()
        private let symbolView = UIImageView()
        private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        private var loadingURL: String?

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 18
            contentView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            symbolView.tintColor = UIColor.white.withAlphaComponent(0.9)
            symbolView.contentMode = .scaleAspectFit
            symbolView.translatesAutoresizingMaskIntoConstraints = false
            shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]
            shade.locations = [0.35, 1]
            nameLabel.font = .systemFont(ofSize: 16, weight: .bold)
            nameLabel.textColor = .white
            nameLabel.numberOfLines = 2
            detailLabel.font = .systemFont(ofSize: 13, weight: .medium)
            detailLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            let words = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
            words.axis = .vertical
            words.spacing = 2
            words.translatesAutoresizingMaskIntoConstraints = false
            check.tintColor = .white
            check.backgroundColor = Constants.Colors.primary
            check.layer.cornerRadius = 14
            check.clipsToBounds = true
            check.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)
            contentView.addSubview(symbolView)
            contentView.layer.addSublayer(shade)
            contentView.addSubview(words)
            contentView.addSubview(check)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -24),
                symbolView.widthAnchor.constraint(equalToConstant: 44),
                symbolView.heightAnchor.constraint(equalToConstant: 44),
                words.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                words.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                words.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
                check.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                check.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
                check.widthAnchor.constraint(equalToConstant: 28),
                check.heightAnchor.constraint(equalToConstant: 28)
            ])
            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            shade.frame = contentView.bounds
        }

        func configure(_ pick: Pick, picked: Bool) {
            nameLabel.text = pick.name
            detailLabel.text = pick.detail
            contentView.backgroundColor = pick.category.color
            symbolView.image = UIImage(systemName: pick.category.symbolName)
            imageView.image = nil
            symbolView.isHidden = pick.photoURL != nil
            loadingURL = pick.photoURL
            if let url = pick.photoURL {
                ImageService.shared.loadImage(from: url) { [weak self] image in
                    DispatchQueue.main.async {
                        guard let self, self.loadingURL == url else { return }
                        self.imageView.image = image
                        self.symbolView.isHidden = image != nil
                    }
                }
            }
            check.isHidden = !picked
            contentView.layer.borderWidth = picked ? 3 : 0
            contentView.layer.borderColor = Constants.Colors.primary.cgColor
            accessibilityLabel = "\(pick.name), \(pick.detail)"
            accessibilityValue = picked ? "Picked" : nil
        }
    }
}

private extension MorePlacesLikeViewController.Pick {
    /// Distance in meters for ordering (unknown spots last)
    func distanceRank(from origin: CLLocation) -> Double {
        guard let coordinate else { return .greatestFiniteMagnitude }
        return origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

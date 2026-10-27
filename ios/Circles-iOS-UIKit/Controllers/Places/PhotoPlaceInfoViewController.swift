import UIKit
import MapKit

/// Tap a row in "Build my map": what Apple Maps knows about the place found
/// at that spot, with Apple's own street-level picture (Look Around), so it
/// can be recognized without the person's photo (Wes, 2026-10-17). Here they
/// decide whether to save it, whether to add their own photo to it (off by
/// default: the photo is only how the place was found), or pick a different
/// place at the same spot.
final class PhotoPlaceInfoViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let find: PhotoFind
    private let onChange: () -> Void
    private let stack = UIStackView()
    private let lookAroundHolder = UIView()
    private var lookAround: MKLookAroundViewController?

    init(find: PhotoFind, onChange: @escaping () -> Void) {
        self.find = find
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
        lookAroundHolder.heightAnchor.constraint(equalToConstant: 220).isActive = true
        render()
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let item = find.item
        title = item.name

        // Apple's street-level picture of the place, else a map with its pin
        lookAroundHolder.subviews.forEach { $0.removeFromSuperview() }
        lookAroundHolder.layer.cornerRadius = 12
        lookAroundHolder.clipsToBounds = true
        lookAroundHolder.backgroundColor = .secondarySystemBackground
        stack.addArrangedSubview(lookAroundHolder)
        loadPicture(for: item)

        let name = UILabel()
        name.text = item.name
        name.font = .systemFont(ofSize: 22, weight: .bold)
        name.numberOfLines = 0
        stack.addArrangedSubview(name)

        let facts = UILabel()
        let visits = find.visits == 1 ? "1 visit" : "\(find.visits) visits"
        let photos = find.photoCount == 1 ? "1 photo" : "\(find.photoCount) photos"
        facts.text = "\(PhotoPlaceKind.label(item)) \u{00B7} found in \(photos) from \(visits)"
        facts.font = .systemFont(ofSize: 14)
        facts.textColor = Constants.Colors.secondaryLabel
        facts.numberOfLines = 0
        stack.addArrangedSubview(facts)

        if let address = Self.address(item.placemark) {
            stack.addArrangedSubview(infoLine(address, symbol: "mappin.and.ellipse"))
        }
        if let phone = item.phoneNumber, !phone.isEmpty {
            let button = UIButton.rowButton(title: phone, systemName: "phone")
            button.addAction(UIAction { _ in
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") { UIApplication.shared.open(url) }
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        if let url = item.url {
            let button = UIButton.rowButton(title: url.host ?? url.absoluteString, systemName: "safari")
            button.addAction(UIAction { _ in UIApplication.shared.open(url) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let maps = UIButton.secondaryButton(title: "Open in Apple Maps")
        maps.addAction(UIAction { _ in item.openInMaps() }, for: .touchUpInside)
        stack.addArrangedSubview(maps)

        stack.addArrangedSubview(switchRow(title: "Save this place", subtitle: nil, isOn: find.include) { [weak self] on in
            self?.find.include = on
            self?.onChange()
        })

        if !find.photos.isEmpty {
            stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(photoCarousel())
        }

        if find.candidates.count > 1 {
            let header = UILabel()
            header.text = find.isBestGuess ? "Not sure it\u{2019}s this one? Other places here" : "Not this? Other places here"
            header.font = .systemFont(ofSize: 15, weight: .semibold)
            stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(header)
            for (index, other) in find.candidates.enumerated() where index != find.choice {
                let button = UIButton.rowButton(title: "\(other.name ?? "Place") \u{00B7} \(PhotoPlaceKind.label(other))",
                                                systemName: "arrow.triangle.swap")
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.find.choice = index
                    self.find.include = true
                    self.onChange()
                    self.render()
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
    }

    // MARK: - Your photos

    /// Most a carousel shows; a place photographed on dozens of visits says
    /// "+N more" rather than laying out hundreds of thumbnails
    private static let carouselLimit = 30

    /// The photos that led here, from the phone's own library: nothing is
    /// uploaded or downloaded (iCloud-only ones wait for a tap).
    private func photoCarousel() -> UIView {
        let header = UILabel()
        header.text = find.photos.count == 1 ? "Your photo from here" : "Your \(find.photos.count) photos from here"
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        let caption = UILabel()
        caption.text = "Only to help you recognize the place. They stay on your phone and are never added to it."
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = Constants.Colors.secondaryLabel

        let strip = UIStackView()
        strip.axis = .horizontal
        strip.spacing = 8
        strip.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            strip.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            strip.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 96)
        ])
        for (index, photo) in find.photos.prefix(Self.carouselLimit).enumerated() {
            strip.addArrangedSubview(thumbnail(photo, index: index))
        }
        let extra = find.photos.count - Self.carouselLimit
        if extra > 0 {
            let more = UILabel()
            more.text = "+\(extra) more"
            more.font = .systemFont(ofSize: 14, weight: .semibold)
            more.textColor = Constants.Colors.secondaryLabel
            more.textAlignment = .center
            more.widthAnchor.constraint(equalToConstant: 80).isActive = true
            strip.addArrangedSubview(more)
        }
        let column = UIStackView(arrangedSubviews: [header, caption, scroll])
        column.axis = .vertical
        column.spacing = 6
        return column
    }

    private func thumbnail(_ photo: PhotoRef, index: Int) -> UIView {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 96).isActive = true
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.backgroundColor = .secondarySystemBackground
        button.imageView?.contentMode = .scaleAspectFill
        button.setImage(UIImage(systemName: "photo"), for: .normal)
        button.tintColor = Constants.Colors.tertiaryLabel
        button.accessibilityLabel = "Photo \(index + 1)"
        switch photo {
        case .image(let image):
            button.setImage(image.preparingThumbnail(of: CGSize(width: 192, height: 192)) ?? image, for: .normal)
        case .asset(let id):
            // Small, and only if it's already on the phone
            PhotoLibraryIndex.shared.image(for: id, size: CGSize(width: 192, height: 192), fromICloud: false) { [weak button] image in
                guard let button, let image else { return }
                button.setImage(image, for: .normal)
            }
        }
        button.addAction(UIAction { [weak self] _ in self?.showPhoto(at: index) }, for: .touchUpInside)
        return button
    }

    /// Full screen, starting on the tapped photo; swipe through the rest
    private func showPhoto(at index: Int) {
        present(FoundPhotosViewer(photos: Array(find.photos.prefix(Self.carouselLimit)), start: index), animated: true)
    }

    private func loadPicture(for item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene {
                let controller = MKLookAroundViewController(scene: scene)
                controller.isNavigationEnabled = true
                controller.showsRoadLabels = false
                self.embed(controller)
            } else {
                self.showMap(at: coordinate)
            }
        }
    }

    private func embed(_ controller: MKLookAroundViewController) {
        lookAround?.willMove(toParent: nil)
        lookAround?.view.removeFromSuperview()
        lookAround?.removeFromParent()
        addChild(controller)
        controller.view.frame = lookAroundHolder.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lookAroundHolder.addSubview(controller.view)
        controller.didMove(toParent: self)
        lookAround = controller
    }

    private func showMap(at coordinate: CLLocationCoordinate2D) {
        let map = MKMapView(frame: lookAroundHolder.bounds)
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.pointOfInterestFilter = .includingAll
        map.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 300, longitudinalMeters: 300), animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        map.addAnnotation(pin)
        lookAroundHolder.addSubview(map)
    }

    private func infoLine(_ text: String, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 8
        row.alignment = .top
        return row
    }

    private func switchRow(title: String, subtitle: String?, isOn: Bool, onToggle: @escaping (Bool) -> Void) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addAction(UIAction { action in
            guard let toggle = action.sender as? UISwitch else { return }
            onToggle(toggle.isOn)
        }, for: .valueChanged)
        let top = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        top.alignment = .center
        let column = UIStackView(arrangedSubviews: [top])
        column.axis = .vertical
        column.spacing = 4
        if let subtitle {
            let caption = UILabel()
            caption.text = subtitle
            caption.font = .systemFont(ofSize: 13)
            caption.textColor = Constants.Colors.secondaryLabel
            caption.numberOfLines = 0
            column.addArrangedSubview(caption)
        }
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        column.backgroundColor = .secondarySystemBackground
        column.layer.cornerRadius = 12
        return column
    }

    static func address(_ placemark: MKPlacemark) -> String? {
        let parts = [[placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " "),
                     placemark.locality, placemark.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// The photos from "Build my map", full screen on black: swipe between them,
/// tap the X (or swipe down) to close. Each page loads a screen-sized copy
/// only when it's reached (from iCloud only then).
private final class FoundPhotosViewer: BaseViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let photos: [PhotoRef]
    private let start: Int
    private lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.backgroundColor = .black
        view.contentInsetAdjustmentBehavior = .never
        view.register(PhotoPage.self, forCellWithReuseIdentifier: PhotoPage.id)
        view.dataSource = self
        view.delegate = self
        return view
    }()
    private let counter = UILabel()
    private lazy var closeButton = UIButton.iconButton(systemName: "xmark", pointSize: 18)
    private var didScrollToStart = false

    init(photos: [PhotoRef], start: Int) {
        self.photos = photos
        self.start = min(max(0, start), max(0, photos.count - 1))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        collection.frame = view.bounds
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collection)

        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeButton.layer.cornerRadius = 20
        closeButton.accessibilityLabel = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        counter.font = .systemFont(ofSize: 15, weight: .semibold)
        counter.textColor = .white
        counter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        view.addSubview(counter)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            counter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counter.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])
        let down = UISwipeGestureRecognizer(target: self, action: #selector(close))
        down.direction = .down
        view.addGestureRecognizer(down)
        updateCounter(start)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (collection.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = view.bounds.size
        guard !didScrollToStart, view.bounds.width > 0 else { return }
        didScrollToStart = true
        collection.layoutIfNeeded()
        collection.scrollToItem(at: IndexPath(item: start, section: 0), at: .centeredHorizontally, animated: false)
    }

    @objc private func close() { dismiss(animated: true) }

    private func updateCounter(_ index: Int) {
        counter.text = photos.count > 1 ? "\(index + 1) of \(photos.count)" : nil
        counter.accessibilityLabel = counter.text.map { "Photo \($0)" }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        updateCounter(Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded()))
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { photos.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoPage.id, for: indexPath) as! PhotoPage
        let side = max(view.bounds.width, view.bounds.height) * UIScreen.main.scale
        cell.show(photos[indexPath.item], side: side)
        return cell
    }
}

/// One full-screen page; ignores a late image meant for a reused cell.
private final class PhotoPage: UICollectionViewCell {
    static let id = "PhotoPage"
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var token = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ photo: PhotoRef, side: CGFloat) {
        let mine = UUID()
        token = mine
        imageView.image = nil
        switch photo {
        case .image(let image):
            imageView.image = image
        case .asset(let id):
            spinner.startAnimating()
            PhotoLibraryIndex.shared.image(for: id, size: CGSize(width: side, height: side)) { [weak self] image in
                guard let self, self.token == mine else { return }
                self.spinner.stopAnimating()
                self.imageView.image = image
            }
        }
    }
}

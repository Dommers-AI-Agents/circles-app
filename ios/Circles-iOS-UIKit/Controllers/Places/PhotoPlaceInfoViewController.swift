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
        stack.addArrangedSubview(switchRow(
            title: "Also add my photo",
            subtitle: "Your photos stay on your phone. Only where they were taken is used to find the place; a saved place gets its photo from Google Maps, like any place you add.",
            isOn: find.addMyPhoto) { [weak self] on in
                self?.find.addMyPhoto = on
                self?.onChange()
            })

        if !find.photos.isEmpty {
            stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(photoCarousel())
        }

        if find.candidates.count > 1 {
            let header = UILabel()
            header.text = "Not this? Other places here"
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
        caption.text = "On your phone only. Tap one to see it bigger."
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
        button.addAction(UIAction { [weak self] _ in self?.showPhoto(photo) }, for: .touchUpInside)
        return button
    }

    /// One photo, full screen; tap anywhere to close
    private func showPhoto(_ photo: PhotoRef) {
        present(FoundPhotoViewer(photo: photo), animated: true)
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

/// A photo from "Build my map", full screen on black; tap to close. Loads a
/// screen-sized copy (from iCloud only now that the person asked for it).
private final class FoundPhotoViewer: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let photo: PhotoRef
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(photo: PhotoRef) {
        self.photo = photo
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
        spinner.color = .white
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(spinner)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        view.accessibilityHint = "Tap to close"
        switch photo {
        case .image(let image):
            imageView.image = image
        case .asset(let id):
            spinner.startAnimating()
            let side = max(view.bounds.width, view.bounds.height) * UIScreen.main.scale
            PhotoLibraryIndex.shared.image(for: id, size: CGSize(width: side, height: side)) { [weak self] image in
                self?.spinner.stopAnimating()
                self?.imageView.image = image
            }
        }
    }

    @objc private func close() { dismiss(animated: true) }
}

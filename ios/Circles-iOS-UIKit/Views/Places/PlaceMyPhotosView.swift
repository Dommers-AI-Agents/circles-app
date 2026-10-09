import UIKit
import CoreLocation

/// "Your photos from here": the photos in your library taken at this place,
/// to add to it in a tap (Wes, 2026-10-09). Shown on your own saves. Before
/// library access it's one quiet button; with none found it takes no space.
final class PlaceMyPhotosView: UIView {
    /// The chosen photos, full size, ready for the place's uploader
    var onAdd: (([UIImage]) -> Void)?

    private let column = UIStackView()
    private let header = UILabel()
    private let strip = UIStackView()
    private let scroll = UIScrollView()
    private lazy var addButton = UIButton.smallActionButton(title: "Add", style: .primary)
    private lazy var askButton = UIButton.smallActionButton(title: "See your photos from here", style: .secondary)
    private var shots: [PhotoLibraryMath.Shot] = []
    private var selected = Set<String>()
    private var coordinate: CLLocationCoordinate2D?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        strip.axis = .horizontal
        strip.spacing = 8
        strip.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            strip.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            strip.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 84)
        ])
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        askButton.addTarget(self, action: #selector(askTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Looks for your photos taken at `coordinate`.
    func load(near coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        let index = PhotoLibraryIndex.shared
        if index.canRead {
            index.shots(near: coordinate) { [weak self] found in self?.show(found) }
        } else if index.mayAsk {
            showAsk()
        } else {
            clear()
        }
    }

    private func clear() { column.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    private func showAsk() {
        clear()
        column.addArrangedSubview(askButton)
    }

    @objc private func askTapped() {
        PhotoLibraryIndex.shared.requestAccess { [weak self] granted in
            guard let self, let coordinate = self.coordinate else { return }
            if granted { self.load(near: coordinate) } else { self.clear() }
        }
    }

    private func show(_ found: [PhotoLibraryMath.Shot]) {
        clear()
        shots = found
        selected = Set(found.map(\.id))
        guard !found.isEmpty else { return }
        let top = UIStackView(arrangedSubviews: [header, UIView(), addButton])
        top.alignment = .center
        column.addArrangedSubview(top)
        column.addArrangedSubview(scroll)
        strip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for shot in found {
            let thumb = UIButton(type: .custom)
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.widthAnchor.constraint(equalToConstant: 84).isActive = true
            thumb.layer.cornerRadius = 8
            thumb.clipsToBounds = true
            thumb.imageView?.contentMode = .scaleAspectFill
            thumb.backgroundColor = .secondarySystemBackground
            thumb.accessibilityIdentifier = shot.id
            thumb.addTarget(self, action: #selector(thumbTapped(_:)), for: .touchUpInside)
            PhotoLibraryIndex.shared.image(for: shot.id, size: CGSize(width: 168, height: 168)) { image in
                thumb.setImage(image, for: .normal)
            }
            strip.addArrangedSubview(thumb)
        }
        refresh()
    }

    @objc private func thumbTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        refresh()
    }

    private func refresh() {
        header.text = shots.count == 1 ? "1 of your photos is from here" : "\(shots.count) of your photos are from here"
        addButton.setTitle(selected.isEmpty ? "Add" : "Add \(selected.count)", for: .normal)
        addButton.isEnabled = !selected.isEmpty
        for case let thumb as UIButton in strip.arrangedSubviews {
            let on = selected.contains(thumb.accessibilityIdentifier ?? "")
            thumb.alpha = on ? 1 : 0.45
            thumb.layer.borderWidth = on ? 2 : 0
            thumb.layer.borderColor = Constants.Colors.primary.cgColor
        }
    }

    @objc private func addTapped() {
        let ids = shots.map(\.id).filter(selected.contains)
        guard !ids.isEmpty else { return }
        addButton.isEnabled = false
        var images: [UIImage] = []
        let group = DispatchGroup()
        var byId: [String: UIImage] = [:]
        for id in ids {
            group.enter()
            PhotoLibraryIndex.shared.uploadImage(for: id) { image in
                if let image { byId[id] = image }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            images = ids.compactMap { byId[$0] }
            self?.onAdd?(images)
            // Added: they're part of the place now
            self?.clear()
        }
    }
}

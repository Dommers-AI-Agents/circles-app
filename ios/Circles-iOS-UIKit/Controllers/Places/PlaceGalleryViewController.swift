import UIKit

/// Every photo of a place, in the owner's order (the first one is the cover).
///
/// Everyone: tap for full screen, add a photo, delete their own, report
/// someone else's. The venue's owner, its managers and super-users also get
/// Arrange (drag to reorder), Make cover and Remove — one library, one order,
/// for the carousel and everywhere else the place shows a photo.
final class PlaceGalleryViewController: BaseViewController {

    private let placeId: String
    private let placeName: String
    private var photos: [AttributedPhoto] = []
    private var canManage = false
    private var isArranging = false
    private let startArranging: Bool
    /// The library changed (order, cover, a removal) — the place page redraws
    var onChanged: (([AttributedPhoto]) -> Void)?
    /// "Add photo": the place page runs its own camera/library flow
    var onAddPhoto: (() -> Void)?

    override var emptyStateMessage: String? { "No photos yet. Be the first to add one." }

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 24, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = Constants.Colors.background
        cv.dataSource = self
        cv.delegate = self
        cv.dragDelegate = self
        cv.dropDelegate = self
        cv.register(PlaceMediaThumbCell.self, forCellWithReuseIdentifier: PlaceMediaThumbCell.reuseId)
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()
    private let hintLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// `placeId` is the canonical place id (a save id also resolves).
    /// `arranging` opens straight into Arrange (the owner's "Photos" row).
    init(placeId: String, placeName: String, arranging: Bool = false) {
        self.placeId = placeId
        self.placeName = placeName
        self.startArranging = arranging
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Photos"
        view.addSubview(hintLabel)
        view.addSubview(collectionView)
        view.sendSubviewToBack(collectionView)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            collectionView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateChrome()
    }

    override func loadData(completion: (() -> Void)? = nil) {
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                completion?()
                switch result {
                case .success(let response):
                    self.photos = response.globalPlace.photos ?? []
                    self.canManage = response.photoRights?.canManage ?? false
                    if self.startArranging && self.canManage && !self.photos.isEmpty { self.isArranging = true }
                    self.reload()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func reload() {
        collectionView.reloadData()
        collectionView.dragInteractionEnabled = isArranging
        if photos.isEmpty { showEmptyState() } else { hideEmptyState() }
        updateChrome()
    }

    private func updateChrome() {
        var items: [UIBarButtonItem] = []
        if onAddPhoto != nil && !isArranging {
            items.append(UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)))
        }
        if canManage && photos.count > 1 {
            items.append(UIBarButtonItem(title: isArranging ? "Done" : "Arrange", style: isArranging ? .done : .plain,
                                         target: self, action: #selector(arrangeTapped)))
        }
        navigationItem.rightBarButtonItems = items
        if isArranging {
            hintLabel.text = "Drag photos into the order customers see them. The first one is the cover."
        } else if canManage {
            hintLabel.text = "You manage \(placeName)'s photos. Press and hold a photo for more."
        } else {
            hintLabel.text = photos.isEmpty ? nil : "Press and hold a photo for more."
        }
    }

    @objc private func addTapped() {
        onAddPhoto?()
    }

    @objc private func arrangeTapped() {
        isArranging.toggle()
        reload()
    }

    // MARK: - Actions

    private var viewerId: String? { AuthService.shared.getUserId() }

    private func perform(_ action: PlacePhotoActions.Action, on photo: AttributedPhoto) {
        guard let photoId = photo.photoId else { return }
        switch action {
        case .setCover:
            PlacePhotoLibraryService.shared.setCover(placeId: placeId, photoId: photoId) { [weak self] result in
                self?.applyLibrary(result, success: "Cover photo updated")
            }
        case .delete, .remove:
            let isOwn = action == .delete
            showConfirmation(
                title: isOwn ? "Delete your photo?" : "Remove this photo?",
                message: isOwn
                    ? "It's removed from \(placeName) for everyone."
                    : "It disappears from \(placeName) for everyone and can't be added back.",
                confirmTitle: isOwn ? "Delete" : "Remove",
                isDestructive: true
            ) { [weak self] in
                guard let self else { return }
                PlacePhotoLibraryService.shared.remove(placeId: self.placeId, photoId: photoId) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.photos.removeAll { $0.photoId == photoId }
                            self.reload()
                            self.onChanged?(self.photos)
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        case .report:
            presentContentModerationSheet(
                contentType: "place_photo",
                contentId: PlacePhotoActions.reportContentId(placeId: placeId, photoId: photoId),
                ownerId: photo.uploadedBy ?? "",
                ownerName: photo.uploadedByName
            )
        }
    }

    private func applyLibrary(_ result: Result<PlacePhotoLibraryService.LibraryResponse, Error>, success: String?) {
        DispatchQueue.main.async {
            switch result {
            case .success(let response):
                if let updated = response.photos { self.photos = updated }
                self.reload()
                self.onChanged?(self.photos)
                if let success { self.showSuccess(success) }
            case .failure(let error):
                self.showError(error)
                self.loadData()
            }
        }
    }

    private func saveOrder() {
        let ids = photos.compactMap(\.photoId)
        guard !ids.isEmpty else { return }
        PlacePhotoLibraryService.shared.reorder(placeId: placeId, photoIds: ids) { [weak self] result in
            self?.applyLibrary(result, success: nil)
        }
    }

    private func title(for action: PlacePhotoActions.Action) -> (String, String, UIMenuElement.Attributes) {
        switch action {
        case .setCover: return ("Make cover photo", "star", [])
        case .delete: return ("Delete my photo", "trash", .destructive)
        case .remove: return ("Remove photo", "trash", .destructive)
        case .report: return ("Report", "flag", [])
        }
    }
}

// MARK: - Grid

extension PlaceGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PlaceMediaThumbCell.reuseId, for: indexPath) as! PlaceMediaThumbCell
        let photo = photos[indexPath.item]
        let tag: String? = photo.isPrivate == true ? "Only you" : (indexPath.item == 0 ? "Cover" : nil)
        cell.configure(imageUrl: photo.url, tag: tag)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 16 - 8) / 3
        return CGSize(width: floor(width), height: floor(width))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isArranging else { return }
        let viewer = StorefrontPhotoViewerViewController(urls: photos.map(\.url), startingAt: indexPath.item)
        present(viewer, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isArranging, photos.indices.contains(indexPath.item) else { return nil }
        let photo = photos[indexPath.item]
        let actions = PlacePhotoActions.actions(photo: photo, isCover: indexPath.item == 0, viewerId: viewerId, canManage: canManage)
        guard !actions.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let items = actions.map { action -> UIAction in
                let (label, symbol, attributes) = self.title(for: action)
                return UIAction(title: label, image: UIImage(systemName: symbol), attributes: attributes) { [weak self] _ in
                    self?.perform(action, on: photo)
                }
            }
            let credit = photo.uploadedByName.map { "Added by \($0)" }
            return UIMenu(title: credit ?? "", children: items)
        }
    }
}

// MARK: - Arrange (drag to reorder)

extension PlaceGalleryViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard isArranging else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath.item
        return [item]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard isArranging, session.localDragSession != nil else { return UICollectionViewDropProposal(operation: .forbidden) }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first, let source = item.sourceIndexPath,
              let destination = coordinator.destinationIndexPath else { return }
        let target = min(destination.item, photos.count - 1)
        collectionView.performBatchUpdates {
            let moved = photos.remove(at: source.item)
            photos.insert(moved, at: target)
            collectionView.moveItem(at: source, to: IndexPath(item: target, section: 0))
        } completion: { _ in
            // The "Cover" tag follows the first photo
            collectionView.reloadItems(at: Array(Set([IndexPath(item: 0, section: 0), IndexPath(item: target, section: 0), source])))
        }
        coordinator.drop(item.dragItem, toItemAt: IndexPath(item: target, section: 0))
        saveOrder()
    }
}

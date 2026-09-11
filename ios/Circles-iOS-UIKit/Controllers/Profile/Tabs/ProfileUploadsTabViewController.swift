import UIKit

/// The profile's Uploads tab: photos the user added to places, one tile per
/// place. Tap opens the place page (its carousel scrolls through every
/// photo); long-press opens a gallery where individual uploads can be
/// deleted.
final class ProfileUploadsTabViewController: ProfileGridTabViewController {
    private(set) var uploads: [UserUploadedPhoto] = [] {
        didSet { uploadGroups = uploads.groupedByPlace() }
    }
    /// Uploads collapsed to one entry per place (the grid renders these).
    private(set) var uploadGroups: [UploadPlaceGroup] = []
    private var isLoadingUploads = false

    init() {
        super.init(emptyText: "No uploads yet")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func registerCells(in collectionView: UICollectionView) {
        collectionView.register(UploadThumbnailCell.self, forCellWithReuseIdentifier: "UploadThumbnailCell")
    }

    override var itemCount: Int { uploadGroups.count }

    override func cell(for collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UploadThumbnailCell", for: indexPath) as! UploadThumbnailCell
        cell.configure(with: uploadGroups[indexPath.item])
        return cell
    }

    override func didSelectItem(at index: Int) {
        navigateToPlaceDetail(from: uploadGroups[index].cover)
    }

    override func contextMenu(at index: Int) -> UIMenu? {
        let group = uploadGroups[index]
        let manage = UIAction(title: "View / manage photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
            self?.openGallery(for: group)
        }
        return UIMenu(children: [manage])
    }

    override func activate() {
        if uploads.isEmpty && !isLoadingUploads {
            showLoading()
            fetchUploads()
        } else if !uploads.isEmpty {
            showLoaded()
        }
    }

    // MARK: - Loading

    func fetchUploads() {
        guard let userId = resolvedUserId else {
            Logger.debug("⚠️ ProfileUploads: No user ID available for fetching uploads")
            isLoadingUploads = false
            loadingIndicator.stopAnimating()
            return
        }

        Logger.debug("📷 ProfileUploads: Fetching uploads for user: \(userId)")
        isLoadingUploads = true

        GlobalPlaceService.shared.getUserUploads(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingUploads = false

                switch result {
                case .success(let response):
                    Logger.debug("✅ ProfileUploads: Fetched \(response.data.count) uploads")
                    self.uploads = response.data
                    if self.isActiveTab {
                        self.showLoaded()
                    }

                case .failure(let error):
                    Logger.debug("❌ ProfileUploads: Failed to fetch uploads: \(error.localizedDescription)")
                    // Don't show an error to the user, just leave the grid empty
                    self.uploads = []
                    if self.isActiveTab {
                        self.showLoaded()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Expand a place's uploaded photos into a gallery. Deleting a photo there
    /// removes it server-side and keeps both the gallery and the grouped grid
    /// in sync (the `uploads` didSet re-groups automatically).
    private func openGallery(for group: UploadPlaceGroup) {
        weak var galleryRef: PlaceUploadsGalleryViewController?
        let galleryVC = PlaceUploadsGalleryViewController(
            placeName: group.placeName,
            photos: group.photos,
            onDelete: { [weak self] photo in
                guard let self = self, let gallery = galleryRef else { return }
                AlertPresenter.showConfirmation(
                    title: "Delete Photo",
                    message: "Delete this photo from \(photo.placeName)? This can't be undone.",
                    confirmTitle: "Delete",
                    isDestructive: true,
                    from: gallery,
                    onConfirm: {
                        let loading = AlertPresenter.showLoading(message: "Deleting photo...", from: gallery)
                        GlobalPlaceService.shared.deleteUpload(photo) { result in
                            DispatchQueue.main.async {
                                loading.dismiss(animated: true) {
                                    switch result {
                                    case .success:
                                        self.uploads.removeAll { $0.id == photo.id } // didSet re-groups
                                        if self.isActiveTab {
                                            self.showLoaded()
                                        }
                                        gallery.remove(photo)
                                    case .failure(let error):
                                        gallery.showError(error)
                                    }
                                }
                            }
                        }
                    }
                )
            }
        )
        galleryRef = galleryVC
        navigationController?.pushViewController(galleryVC, animated: true)
    }

    private func navigateToPlaceDetail(from upload: UserUploadedPhoto) {
        let loadingAlert = AlertPresenter.showLoading(message: "Loading place details...", from: self)

        // Fetch complete global place data
        GlobalPlaceService.shared.getGlobalPlace(id: upload.placeId) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let globalPlaceResponse):
                        let placeDetailVC = PlaceDetailViewController(place: globalPlaceResponse.bestDetailPlace())
                        self.navigationController?.pushViewController(placeDetailVC, animated: true)

                    case .failure(let error):
                        Logger.debug("❌ ProfileUploads: Failed to load place details: \(error)")
                        // Fallback: a minimal Place built from the upload, and still navigate
                        let tempPlace = Place(
                            id: upload.placeId,
                            name: upload.placeName,
                            description: nil,
                            address: upload.placeAddress ?? "",
                            location: nil,
                            website: nil,
                            phone: nil,
                            googlePlaceId: nil,
                            photos: [upload.imageUrl],
                            videos: nil,
                            category: upload.placeCategory,
                            customCategoryId: nil,
                            subcategory: nil,
                            rating: nil,
                            userRatingsTotal: nil,
                            notes: nil,
                            privateNotes: nil,
                            publicNotes: nil,
                            tags: [],
                            reviews: nil,
                            openingHours: nil,
                            priceLevel: nil,
                            likes: nil,
                            likesCount: nil,
                            commentsCount: nil,
                            circleId: nil,
                            addedBy: "",
                            addedByUser: nil,
                            privacy: .followCirclePrivacy,
                            createdAt: upload.uploadedAt,
                            updatedAt: upload.uploadedAt,
                            isNew: false
                        )
                        let placeDetailVC = PlaceDetailViewController(place: tempPlace)
                        self.navigationController?.pushViewController(placeDetailVC, animated: true)
                        self.showError("Could not load complete place details")
                    }
                }
            }
        }
    }
}

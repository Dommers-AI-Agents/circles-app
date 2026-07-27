import UIKit

/// Expanded view of one place's uploaded photos — reached by tapping a place
/// tile in the profile's grouped Uploads grid. 3-column grid; tap a photo to
/// view it full-screen, long-press to delete (delegated back to the profile).
class PlaceUploadsGalleryViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let placeName: String
    private var photos: [UserUploadedPhoto]
    /// Called when the user confirms deleting a photo; the presenter performs
    /// the delete + refetch and should call `remove(_:)` to update this grid.
    private let onDelete: ((UserUploadedPhoto) -> Void)?

    init(placeName: String, photos: [UserUploadedPhoto], onDelete: ((UserUploadedPhoto) -> Void)? = nil) {
        self.placeName = placeName
        self.photos = photos
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = Constants.Colors.background
        cv.dataSource = self
        cv.delegate = self
        cv.register(UploadThumbnailCell.self, forCellWithReuseIdentifier: "UploadThumbnailCell")
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = placeName
        view.backgroundColor = Constants.Colors.background

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Remove a photo after the presenter deletes it; pops the screen if empty.
    func remove(_ photo: UserUploadedPhoto) {
        photos.removeAll { $0.id == photo.id }
        if photos.isEmpty {
            navigationController?.popViewController(animated: true)
        } else {
            collectionView.reloadData()
        }
    }
}

// MARK: - Collection view

extension PlaceUploadsGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UploadThumbnailCell", for: indexPath) as! UploadThumbnailCell
        cell.configure(with: photos[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let spacing: CGFloat = 2
        let columns: CGFloat = 3
        let width = (collectionView.bounds.width - spacing * (columns - 1)) / columns
        return CGSize(width: floor(width), height: floor(width))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fullScreenVC = FullScreenImageViewController(imageURL: photos[indexPath.item].imageUrl)
        fullScreenVC.modalPresentationStyle = .fullScreen
        present(fullScreenVC, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard onDelete != nil, indexPath.item < photos.count else { return nil }
        let photo = photos[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(title: "Delete Photo", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.onDelete?(photo)
            }
            return UIMenu(children: [delete])
        }
    }
}

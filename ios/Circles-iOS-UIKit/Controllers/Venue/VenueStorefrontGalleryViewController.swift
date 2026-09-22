import UIKit
import PhotosUI

/// The owner's own photos of the place — food, the room, the team. Google's
/// photos are stock; these are theirs, and they feed Postcards and Moments
/// as well as the place page.
final class VenueStorefrontGalleryViewController: BaseViewController {
    private let venueId: String
    private var photos: [StorefrontGalleryPhoto]
    var onSaved: ((VenueStorefront) -> Void)?
    static let maxPhotos = 12

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(GalleryCell.self, forCellWithReuseIdentifier: "GalleryCell")
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    init(venueId: String, photos: [StorefrontGalleryPhoto]) {
        self.venueId = venueId
        self.photos = photos
        super.init(nibName: nil, bundle: nil)
        title = "Photos"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func saveTapped() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        RewardsService.shared.updateStorefrontGallery(venueId: venueId, photos: photos) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                switch result {
                case .success(let storefront):
                    self.photos = storefront.gallery
                    self.onSaved?(storefront)
                    self.showSuccess("Photos saved")
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    private func addPhotos() {
        let room = Self.maxPhotos - photos.count
        guard room > 0 else { showError("Up to \(Self.maxPhotos) photos."); return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = room
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func manage(at index: Int) {
        let photo = photos[index]
        AlertPresenter.showActionSheet(title: photo.caption ?? "Photo", message: nil, actions: [
            (title: "Caption", style: .default, handler: { [weak self] in
                self?.showTextInput(title: "Caption", message: "Optional", initialText: photo.caption) { text in
                    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.photos[index].caption = (t ?? "").isEmpty ? nil : t
                    self?.collectionView.reloadData()
                }
            }),
            (title: "Move to front", style: .default, handler: { [weak self] in
                guard let self else { return }
                let p = self.photos.remove(at: index)
                self.photos.insert(p, at: 0)
                self.collectionView.reloadData()
            }),
            (title: "Remove", style: .destructive, handler: { [weak self] in
                self?.photos.remove(at: index)
                self?.collectionView.reloadData()
            })
        ], from: self)
    }

    /// Uploads one at a time through the app's image pipeline, then appends —
    /// a failed one is reported and the rest still land.
    private func upload(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let loading = showLoading(message: "Uploading \(images.count) photo\(images.count == 1 ? "" : "s")…")
        var remaining = images
        var failures = 0
        func next() {
            guard let image = remaining.first else {
                loading.dismiss(animated: true) { [weak self] in
                    self?.collectionView.reloadData()
                    if failures > 0 { self?.showError("\(failures) photo\(failures == 1 ? "" : "s") didn't upload.") }
                }
                return
            }
            remaining.removeFirst()
            guard let data = image.jpegData(compressionQuality: 0.85) else { failures += 1; next(); return }
            PlaceService.shared.uploadImage(data) { [weak self] result in
                DispatchQueue.main.async {
                    if case .success(let url) = result {
                        self?.photos.append(StorefrontGalleryPhoto(photoId: "photo_\(Int(Date().timeIntervalSince1970 * 1000))_\(self?.photos.count ?? 0)", url: url, caption: nil))
                    } else { failures += 1 }
                    next()
                }
            }
        }
        next()
    }
}

extension VenueStorefrontGalleryViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { photos.count + 1 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GalleryCell", for: indexPath) as! GalleryCell
        if indexPath.item < photos.count { cell.configure(photos[indexPath.item]) } else { cell.configureAsAdd() }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = (collectionView.bounds.width - 32 - 12) / 3
        return CGSize(width: floor(side), height: floor(side))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item < photos.count { manage(at: indexPath.item) } else { addPhotos() }
    }

    final class GalleryCell: UICollectionViewCell {
        private let imageView = UIImageView()
        private let captionLabel = UILabel()
        private let plus = UIImageView(image: UIImage(systemName: "plus"))
        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 8
            contentView.clipsToBounds = true
            contentView.backgroundColor = .secondarySystemBackground
            imageView.contentMode = .scaleAspectFill
            imageView.frame = contentView.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(imageView)
            captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
            captionLabel.textColor = .white
            captionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            captionLabel.textAlignment = .center
            captionLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(captionLabel)
            plus.tintColor = Constants.Colors.primary
            plus.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(plus)
            NSLayoutConstraint.activate([
                captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                captionLabel.heightAnchor.constraint(equalToConstant: 20),
                plus.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                plus.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                plus.widthAnchor.constraint(equalToConstant: 28),
                plus.heightAnchor.constraint(equalToConstant: 28)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ photo: StorefrontGalleryPhoto) {
            plus.isHidden = true
            imageView.isHidden = false
            imageView.image = nil
            captionLabel.text = photo.caption
            captionLabel.isHidden = (photo.caption ?? "").isEmpty
            ImageService.shared.loadImage(from: photo.url) { [weak self] image in
                DispatchQueue.main.async { self?.imageView.image = image }
            }
        }
        func configureAsAdd() {
            plus.isHidden = false
            imageView.isHidden = true
            captionLabel.isHidden = true
        }
    }
}

extension VenueStorefrontGalleryViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let group = DispatchGroup()
        var images: [UIImage] = []
        let lock = NSLock()
        for result in results where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage { lock.lock(); images.append(image); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.upload(images) }
    }
}

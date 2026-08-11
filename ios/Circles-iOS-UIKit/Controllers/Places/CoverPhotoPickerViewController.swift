import UIKit

/// Owner picks which of the place's existing photos leads the page. Curation
/// only — new photos still go through the normal media upload pipeline.
class CoverPhotoPickerViewController: BaseViewController {

    var onSelect: ((String) -> Void)?

    private let photoUrls: [String]
    private let currentCoverUrl: String?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .systemBackground
        return collection
    }()

    override var loadsDataOnViewDidLoad: Bool { false }

    init(photoUrls: [String], currentCoverUrl: String?) {
        self.photoUrls = photoUrls
        self.currentCoverUrl = currentCoverUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Choose Cover Photo"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CoverPhotoCell.self, forCellWithReuseIdentifier: CoverPhotoCell.reuseId)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

extension CoverPhotoPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoUrls.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CoverPhotoCell.reuseId, for: indexPath) as! CoverPhotoCell
        let url = photoUrls[indexPath.item]
        cell.configure(url: url, isCurrentCover: url == currentCoverUrl)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = (collectionView.bounds.width - 8) / 3
        return CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let url = photoUrls[indexPath.item]
        dismiss(animated: true) { [onSelect] in
            onSelect?(url)
        }
    }
}

private class CoverPhotoCell: UICollectionViewCell {
    static let reuseId = "CoverPhotoCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = Constants.Colors.secondaryBackground
        return iv
    }()

    private let coverBadge: UILabel = {
        let label = UILabel()
        label.text = " Cover "
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = Constants.Colors.primary
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(coverBadge)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            coverBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            coverBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        coverBadge.isHidden = true
    }

    func configure(url: String, isCurrentCover: Bool) {
        coverBadge.isHidden = !isCurrentCover
        ImageService.shared.loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }
    }
}

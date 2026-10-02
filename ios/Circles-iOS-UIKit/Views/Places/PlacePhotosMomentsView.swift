import UIKit

/// The place page's "Photos & Moments" section: a scrolling row of the
/// place's photo library (the owner's order, cover first) with See all, and
/// a row of every moment posted at the place. Rows with nothing in them hide;
/// the Photos row always offers "Add photo" so it's the one obvious place to
/// add (the carousel's button does the same).
final class PlacePhotosMomentsView: UIView {

    var onSeeAllPhotos: (() -> Void)?
    /// Passes the tapped button, so the add sheet opens next to it
    var onAddPhoto: ((UIView) -> Void)?
    var onPhotoTapped: ((Int) -> Void)?
    var onMomentTapped: ((Int) -> Void)?

    private var photoUrls: [String] = []
    private var privateFlags: [Bool] = []
    private var moments: [PlaceVideo] = []

    private let photosHeader = PlacePhotosMomentsView.header("Photos")
    private let momentsHeader = PlacePhotosMomentsView.header("Moments")
    private lazy var seeAllButton = UIButton.smallActionButton(title: "See all", style: .secondary)
    private lazy var addButton = UIButton.smallActionButton(title: "Add photo", style: .primary)
    private lazy var photosRow = PlacePhotosMomentsView.row()
    private lazy var momentsRow = PlacePhotosMomentsView.row()
    private let emptyPhotosLabel: UILabel = {
        let label = UILabel()
        label.text = "No photos yet. Add the first one."
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()
    private let stack = UIStackView()
    private lazy var momentsGroup = UIStackView(arrangedSubviews: [momentsHeader, momentsRow])

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        photosRow.dataSource = self
        photosRow.delegate = self
        momentsRow.dataSource = self
        momentsRow.delegate = self
        seeAllButton.addTarget(self, action: #selector(seeAllTapped), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        let photosTitle = UIStackView(arrangedSubviews: [photosHeader, UIView(), addButton, seeAllButton])
        photosTitle.spacing = 8
        photosTitle.alignment = .center
        let photosGroup = UIStackView(arrangedSubviews: [photosTitle, photosRow, emptyPhotosLabel])
        photosGroup.axis = .vertical
        photosGroup.spacing = 8
        momentsGroup.axis = .vertical
        momentsGroup.spacing = 8

        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(photosGroup)
        stack.addArrangedSubview(momentsGroup)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            photosRow.heightAnchor.constraint(equalToConstant: 96),
            momentsRow.heightAnchor.constraint(equalToConstant: 132)
        ])
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The place's photos in library order (as the carousel shows them)
    func setPhotos(urls: [String], privateFlags: [Bool] = []) {
        photoUrls = urls
        self.privateFlags = privateFlags
        photosRow.reloadData()
        render()
    }

    func setMoments(_ moments: [PlaceVideo]) {
        self.moments = moments
        momentsRow.reloadData()
        render()
    }

    private func render() {
        photosRow.isHidden = photoUrls.isEmpty
        emptyPhotosLabel.isHidden = !photoUrls.isEmpty
        seeAllButton.isHidden = photoUrls.isEmpty
        momentsGroup.isHidden = moments.isEmpty
    }

    @objc private func seeAllTapped() { onSeeAllPhotos?() }
    @objc private func addTapped() { onAddPhoto?(addButton) }

    private static func header(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = Constants.Colors.label
        return label
    }

    private static func row() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.register(PlaceMediaThumbCell.self, forCellWithReuseIdentifier: PlaceMediaThumbCell.reuseId)
        return cv
    }
}

extension PlacePhotosMomentsView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === photosRow ? photoUrls.count : moments.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PlaceMediaThumbCell.reuseId, for: indexPath) as! PlaceMediaThumbCell
        if collectionView === photosRow {
            let isPrivate = indexPath.item < privateFlags.count && privateFlags[indexPath.item]
            cell.configure(imageUrl: photoUrls[indexPath.item], tag: isPrivate ? "Only you" : nil)
        } else {
            let moment = moments[indexPath.item]
            let isVideo = (moment.duration ?? 0) > 0
            cell.configure(imageUrl: moment.thumbnailUrl ?? moment.previewUrl, isVideo: isVideo)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView === photosRow ? CGSize(width: 96, height: 96) : CGSize(width: 88, height: 132)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === photosRow { onPhotoTapped?(indexPath.item) } else { onMomentTapped?(indexPath.item) }
    }
}

import UIKit

/// Grid of ready-made avatars for people who'd rather not upload a photo.
///
/// First the illustrated people (women, men, robots — `ProfileAvatarCatalog`,
/// hosted images that show everywhere, bundled here), then the emoji
/// characters drawn on device. `onSelect` hands back the value to store as
/// the profile picture: a catalog URL or a `stock-avatar:` string.
final class StockAvatarPickerViewController: UIViewController {

    var onSelect: ((String) -> Void)?

    private struct Section {
        let title: String
        let values: [String]
        let columns: CGFloat
    }

    private let sections: [Section] =
        ProfileAvatarCatalog.groups.map { group in
            Section(title: group.title, values: group.ids.map(ProfileAvatarCatalog.url(for:)), columns: 3)
        } + [Section(title: "Characters", values: StockAvatar.allValues, columns: 4)]
    private var selectedValue: String?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)
        layout.headerReferenceSize = CGSize(width: 0, height: 34)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.dataSource = self
        view.delegate = self
        view.register(StockAvatarCell.self, forCellWithReuseIdentifier: StockAvatarCell.reuseId)
        view.register(AvatarSectionHeader.self,
                      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: AvatarSectionHeader.reuseId)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Pick one for now — you can swap it for a photo any time."
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Choose an Avatar"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )

        view.addSubview(subtitleLabel)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            subtitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            collectionView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

extension StockAvatarPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].values.count
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: AvatarSectionHeader.reuseId, for: indexPath
        ) as! AvatarSectionHeader
        header.label.text = sections[indexPath.section].title
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: StockAvatarCell.reuseId, for: indexPath
        ) as! StockAvatarCell
        let value = sections[indexPath.section].values[indexPath.item]
        cell.configure(value: value, isSelected: value == selectedValue)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = sections[indexPath.section].columns
        let spacing: CGFloat = 12 * (columns - 1) + 32
        let width = (collectionView.bounds.width - spacing) / columns
        return CGSize(width: width, height: width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let value = sections[indexPath.section].values[indexPath.item]
        selectedValue = value
        collectionView.reloadData()

        // A beat of selection feedback before dismissing, so the choice
        // registers rather than the sheet just vanishing.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.onSelect?(value)
            self?.dismiss(animated: true)
        }
    }
}

private final class StockAvatarCell: UICollectionViewCell {
    static let reuseId = "StockAvatarCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(value: String, isSelected: Bool) {
        imageView.image = StockAvatar.image(from: value, diameter: 140)
        imageView.layer.cornerRadius = bounds.width / 2
        imageView.clipsToBounds = true
        imageView.layer.borderWidth = isSelected ? 3 : 0
        imageView.layer.borderColor = Constants.Colors.primary.cgColor
        transform = isSelected ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
    }
}

private final class AvatarSectionHeader: UICollectionReusableView {
    static let reuseId = "AvatarSectionHeader"

    let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

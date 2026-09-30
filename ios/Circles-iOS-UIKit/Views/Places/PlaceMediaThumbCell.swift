import UIKit

/// A square thumbnail for a place's photo library or one of its moments.
/// Shows a play badge for video moments and a small "Cover" tag on the
/// library's first photo.
final class PlaceMediaThumbCell: UICollectionViewCell {
    static let reuseId = "PlaceMediaThumbCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let playBadge: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "play.circle.fill"))
        view.tintColor = .white
        view.layer.shadowOpacity = 0.4
        view.layer.shadowRadius = 3
        view.layer.shadowOffset = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let tagLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var loadingUrl: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true
        contentView.addSubview(imageView)
        contentView.addSubview(playBadge)
        contentView.addSubview(tagLabel)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            playBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            playBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playBadge.widthAnchor.constraint(equalToConstant: 28),
            playBadge.heightAnchor.constraint(equalToConstant: 28),
            tagLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            tagLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            tagLabel.heightAnchor.constraint(equalToConstant: 16),
            tagLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        loadingUrl = nil
    }

    /// `tag` is a short label over the corner ("Cover", "Only you"), or nil
    func configure(imageUrl: String?, isVideo: Bool = false, tag: String? = nil) {
        playBadge.isHidden = !isVideo
        tagLabel.text = tag.map { " \($0) " }
        tagLabel.isHidden = tag == nil
        imageView.image = nil
        guard let imageUrl, !imageUrl.isEmpty else {
            imageView.image = UIImage(systemName: isVideo ? "video" : "photo")
            imageView.tintColor = .tertiaryLabel
            imageView.contentMode = .center
            return
        }
        imageView.contentMode = .scaleAspectFill
        loadingUrl = imageUrl
        ImageService.shared.loadImage(from: imageUrl) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadingUrl == imageUrl else { return }
                self.imageView.image = image
            }
        }
    }
}

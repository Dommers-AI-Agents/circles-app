import UIKit

/// One headline row in the home-page News tab: thumbnail, title, and
/// "source · time ago" caption. Structure mirrors ActivityFeedCell.
class NewsArticleCell: UITableViewCell {

    static let identifier = "NewsArticleCell"

    // Guards against a recycled cell showing a stale async image
    private var currentImageLoadId: String?

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.05
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let headlineLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(containerView)
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(headlineLabel)
        containerView.addSubview(captionLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            thumbnailImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 72),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 72),
            thumbnailImageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor, constant: 12),

            headlineLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            headlineLabel.leadingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: 12),
            headlineLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            captionLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 4),
            captionLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    func configure(with article: NewsArticle) {
        headlineLabel.text = article.title
        captionLabel.text = "\(article.sourceName) · \(article.timeAgo)"

        currentImageLoadId = nil
        if let thumbnailUrl = article.thumbnailUrl {
            let loadId = UUID().uuidString
            currentImageLoadId = loadId
            thumbnailImageView.contentMode = .scaleAspectFill
            thumbnailImageView.image = nil
            ImageService.shared.loadImageWithKey(from: thumbnailUrl, cacheKey: "news-\(article.id)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, self.currentImageLoadId == loadId else { return }
                    if let image = image {
                        self.thumbnailImageView.image = image
                    } else {
                        self.showPlaceholder()
                    }
                }
            }
        } else {
            showPlaceholder()
        }
    }

    private func showPlaceholder() {
        thumbnailImageView.contentMode = .center
        thumbnailImageView.image = UIImage(systemName: "newspaper")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentImageLoadId = nil
        thumbnailImageView.image = nil
        headlineLabel.text = nil
        captionLabel.text = nil
    }
}

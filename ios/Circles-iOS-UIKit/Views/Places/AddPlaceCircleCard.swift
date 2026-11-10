import UIKit

/// The Circle field on Add Place, drawn like a row of the circle picker:
/// cover, name, "97 places · Connections" and a chevron. Before a choice it
/// asks "Where should this place live?". Tapping opens the picker sheet.
final class AddPlaceCircleCard: UIControl {

    private let coverView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        imageView.tintColor = UIColor.systemBlue
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .black // the form's fields are white in every appearance
        label.numberOfLines = 2
        return label
    }()
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .darkGray
        label.numberOfLines = 2
        return label
    }()
    private let chevron: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.tintColor = .systemGray3
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()
    private var imageURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        // White with the thin blue edge, like the name, category and notes fields around it
        backgroundColor = .white
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        isAccessibilityElement = true
        accessibilityTraits = .button

        let text = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2
        text.alignment = .leading
        let row = UIStackView(arrangedSubviews: [coverView, text, chevron])
        row.spacing = 14
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: 52),
            coverView.heightAnchor.constraint(equalToConstant: 52),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
        configure(circle: nil, remembered: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    /// `remembered`: preselected by the last-used rule, not by the person
    func configure(circle: Circle?, remembered: Bool) {
        let detail = circle.map { CirclePickerRows.detail(placeCount: $0.placesCount ?? $0.places?.count ?? 0, privacy: $0.privacy) }
        nameLabel.text = AddPlaceCircleCopy.title(circleName: circle?.name)
        detailLabel.text = AddPlaceCircleCopy.subtitle(circleDetail: detail, remembered: remembered)
        layer.borderWidth = remembered ? 2 : 1
        layer.borderColor = (remembered ? Constants.Colors.primary : UIColor.systemBlue.withAlphaComponent(0.3)).cgColor
        accessibilityLabel = "\(nameLabel.text ?? ""). \(detailLabel.text ?? "")"

        if let cover = circle?.coverImage, !cover.isEmpty {
            imageURL = cover
            coverView.contentMode = .scaleAspectFill
            ImageService.shared.loadImage(from: cover) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.imageURL == cover else { return }
                    self.coverView.image = image
                }
            }
        } else {
            imageURL = nil
            coverView.contentMode = .center
            coverView.image = UIImage(systemName: circle == nil ? "questionmark.circle" : "circle.grid.2x2.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        }
    }
}

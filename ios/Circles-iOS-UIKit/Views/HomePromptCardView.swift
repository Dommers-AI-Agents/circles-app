import UIKit

/// The inline home "daily card": one line of intrigue, a primary action, and
/// Skip. Sits between the segment bar and the tab content, never modal.
final class HomePromptCardView: UIView {

    var onAct: (() -> Void)?
    var onSkip: (() -> Void)?

    private(set) var card: HomePromptCard?

    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 14
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.withAlphaComponent(0.6).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let thumbnail: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        view.backgroundColor = Constants.Colors.lightGray
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let sparkle: UILabel = {
        let label = UILabel()
        label.text = "✨"
        label.font = .systemFont(ofSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var actionButton = UIButton.smallActionButton(title: "Show me", style: .primary)
    private lazy var skipButton = UIButton.smallActionButton(title: "Skip", style: .secondary)

    private var thumbnailWidth: NSLayoutConstraint!
    private var thumbnailGap: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        [thumbnail, sparkle, titleLabel, bodyLabel, actionButton, skipButton].forEach(container.addSubview)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        skipButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pad = Constants.Spacing.small
        thumbnailWidth = thumbnail.widthAnchor.constraint(equalToConstant: 56)
        thumbnailGap = titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: pad)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.Spacing.medium),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.Spacing.medium),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.Spacing.small),

            thumbnail.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor),
            thumbnailWidth,

            sparkle.centerXAnchor.constraint(equalTo: thumbnail.centerXAnchor),
            sparkle.centerYAnchor.constraint(equalTo: thumbnail.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            thumbnailGap,
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            actionButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: pad),
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: thumbnail.bottomAnchor, constant: Constants.Spacing.xsmall),
            actionButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 32),
            actionButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad),

            skipButton.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            skipButton.leadingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: Constants.Spacing.xsmall),
            skipButton.heightAnchor.constraint(equalTo: actionButton.heightAnchor),
            skipButton.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -pad)
        ])
    }

    func configure(with card: HomePromptCard) {
        self.card = card
        titleLabel.text = card.title
        bodyLabel.text = card.body
        bodyLabel.isHidden = card.body.isEmpty
        actionButton.setTitle(card.actionLabel, for: .normal)
        skipButton.setTitle(card.skipLabel, for: .normal)

        thumbnail.image = nil
        sparkle.isHidden = false
        sparkle.text = Self.glyph(for: card)
        if let url = card.imageUrl ?? card.actorPhoto, !url.isEmpty {
            ImageService.shared.loadImage(from: url) { [weak self] image in
                guard let self, self.card?.key == card.key, let image else { return }
                self.thumbnail.image = image
                self.sparkle.isHidden = true
            }
        }
        accessibilityLabel = "\(card.title). \(card.body)"
    }

    private static func glyph(for card: HomePromptCard) -> String {
        switch card.type {
        case "connection_activity": return "👋"
        case "latest_moment": return "🎬"
        case "add_place": return "📍"
        case "favcoins_balance": return "🐷"
        default: return "✨"
        }
    }

    @objc private func actTapped() { onAct?() }
    @objc private func skipTapped() { onSkip?() }
}

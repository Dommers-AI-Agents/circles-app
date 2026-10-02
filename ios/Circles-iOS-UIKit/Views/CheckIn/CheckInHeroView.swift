import UIKit

/// The top of the Check In screen: a reason to check in (your streak, your
/// people, the FavCoin), your numbers, who's out right now, and the step bar.
/// Words come from CheckInHeaderCopy; data from GET /check-ins/me/summary.
final class CheckInHeroView: UIView {

    private let gradient = CAGradientLayer()
    private let stepPill = UILabel()
    private let headline = UILabel()
    private let reason = UILabel()
    private let tiles = UIStackView()
    private let friendsRow = UIStackView()
    private let faces = UIView()
    private let friendsLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var facesWidth: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        gradient.colors = [Constants.Colors.primary.cgColor, UIColor.systemIndigo.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        stepPill.text = "  Step 1 of 2  "
        stepPill.font = .systemFont(ofSize: 12, weight: .semibold)
        stepPill.textColor = .white
        stepPill.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        stepPill.layer.cornerRadius = 11
        stepPill.clipsToBounds = true
        stepPill.setContentHuggingPriority(.required, for: .horizontal)
        stepPill.setContentCompressionResistancePriority(.required, for: .horizontal)

        headline.font = .systemFont(ofSize: 22, weight: .bold)
        headline.textColor = .white
        headline.numberOfLines = 0
        headline.adjustsFontForContentSizeCategory = true

        reason.font = .systemFont(ofSize: 14)
        reason.textColor = UIColor.white.withAlphaComponent(0.9)
        reason.numberOfLines = 0

        tiles.axis = .horizontal
        tiles.spacing = 8
        tiles.distribution = .fillEqually

        friendsLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        friendsLabel.textColor = .white
        friendsLabel.numberOfLines = 2
        faces.translatesAutoresizingMaskIntoConstraints = false
        faces.heightAnchor.constraint(equalToConstant: 26).isActive = true
        facesWidth = faces.widthAnchor.constraint(equalToConstant: 0)
        facesWidth?.isActive = true
        friendsRow.axis = .horizontal
        friendsRow.spacing = 8
        friendsRow.alignment = .center
        friendsRow.addArrangedSubview(faces)
        friendsRow.addArrangedSubview(friendsLabel)

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 2
        progressFill.backgroundColor = .white
        progressFill.layer.cornerRadius = 2
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        let top = UIStackView(arrangedSubviews: [headline, stepPill])
        top.alignment = .top
        top.spacing = 8
        stepPill.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let column = UIStackView(arrangedSubviews: [top, reason, tiles, friendsRow, progressTrack])
        column.axis = .vertical
        column.spacing = 12
        column.setCustomSpacing(6, after: top)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: 0.5)
        ])
        configure(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        gradient.colors = [Constants.Colors.primary.cgColor, UIColor.systemIndigo.cgColor]
    }

    func configure(_ summary: CheckInSummary?) {
        headline.text = CheckInHeaderCopy.headline(summary)
        reason.text = CheckInHeaderCopy.reason(summary)

        tiles.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tile in CheckInHeaderCopy.tiles(summary) { tiles.addArrangedSubview(makeTile(tile.value, tile.caption)) }
        tiles.isHidden = tiles.arrangedSubviews.isEmpty

        let friends = summary?.friendsOut ?? []
        friendsLabel.text = CheckInHeaderCopy.friendsLine(friends)
        friendsRow.isHidden = friendsLabel.text == nil
        setFaces(Array(friends.prefix(3)))
    }

    private func makeTile(_ value: String, _ caption: String) -> UIView {
        let number = UILabel()
        number.text = value
        number.font = .systemFont(ofSize: 20, weight: .bold)
        number.textColor = .white
        number.textAlignment = .center
        number.adjustsFontSizeToFitWidth = true
        let label = UILabel()
        label.text = caption
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        let column = UIStackView(arrangedSubviews: [number, label])
        column.axis = .vertical
        column.spacing = 1
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        column.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        column.layer.cornerRadius = 12
        column.isAccessibilityElement = true
        column.accessibilityLabel = "\(value) \(caption)"
        return column
    }

    private func setFaces(_ friends: [CheckInSummary.Friend]) {
        faces.subviews.forEach { $0.removeFromSuperview() }
        let size: CGFloat = 26
        for (index, friend) in friends.enumerated() {
            let face = UIImageView(frame: CGRect(x: CGFloat(index) * size * 0.7, y: 0, width: size, height: size))
            face.layer.cornerRadius = size / 2
            face.layer.borderWidth = 2
            face.layer.borderColor = UIColor.white.cgColor
            face.clipsToBounds = true
            face.setUserAvatar(name: friend.displayName, seed: friend.userId, urlString: friend.profilePicture, diameter: size)
            faces.addSubview(face)
        }
        facesWidth?.constant = friends.isEmpty ? 0 : size + CGFloat(friends.count - 1) * size * 0.7
    }
}

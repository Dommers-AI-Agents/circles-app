import UIKit

// The cards on My Network → Discover (NetworkDiscoverViewController).

/// Section title with an optional trailing action ("See all")
final class NetworkCardHeader: UIView {
    private let label = UILabel()
    private lazy var actionButton = UIButton.smallActionButton(title: "See all", style: .secondary)
    var onAction: (() -> Void)?

    init(_ title: String, action: String? = nil) {
        super.init(frame: .zero)
        label.text = title
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [label, UIView()])
        row.alignment = .center
        if let action {
            actionButton.setTitle(action, for: .normal)
            actionButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            row.addArrangedSubview(actionButton)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { onAction?() }
}

/// Overlapping round faces: up to three savers
final class FaceStackView: UIView {
    private let size: CGFloat
    init(size: CGFloat = 26) {
        self.size = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ savers: [NetworkDiscoverService.LovedPlace.Saver]) {
        subviews.forEach { $0.removeFromSuperview() }
        for (index, saver) in savers.prefix(3).enumerated() {
            let face = UIImageView(frame: CGRect(x: CGFloat(index) * size * 0.7, y: 0, width: size, height: size))
            face.layer.cornerRadius = size / 2
            face.layer.borderWidth = 2
            face.layer.borderColor = UIColor.systemBackground.cgColor
            face.setUserAvatar(name: saver.displayName, seed: saver.userId, urlString: saver.profilePicture, diameter: size)
            addSubview(face)
        }
        let width = savers.isEmpty ? 0 : size + CGFloat(min(savers.count, 3) - 1) * size * 0.7
        constraints.filter { $0.firstAttribute == .width }.forEach { $0.isActive = false }
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }
}

// MARK: - Places your people love

final class LovedPlaceCell: UICollectionViewCell {
    static let reuseId = "LovedPlaceCell"
    private let photo = UIImageView()
    private let name = UILabel()
    private let detail = UILabel()
    private let faces = FaceStackView()
    private let savedBy = UILabel()
    private let youToo = UILabel()
    private var loadingUrl: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 14
        contentView.clipsToBounds = true
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.backgroundColor = .tertiarySystemFill
        photo.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        savedBy.font = .systemFont(ofSize: 12, weight: .medium)
        savedBy.textColor = .secondaryLabel
        savedBy.numberOfLines = 2
        youToo.text = " ✓ You too "
        youToo.font = .systemFont(ofSize: 11, weight: .bold)
        youToo.textColor = .white
        youToo.backgroundColor = Constants.Colors.primary
        youToo.layer.cornerRadius = 6
        youToo.clipsToBounds = true
        youToo.translatesAutoresizingMaskIntoConstraints = false

        let text = UIStackView(arrangedSubviews: [name, detail, faces, savedBy])
        text.axis = .vertical
        text.spacing = 4
        text.alignment = .leading
        text.setCustomSpacing(8, after: detail)
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photo)
        contentView.addSubview(text)
        contentView.addSubview(youToo)
        NSLayoutConstraint.activate([
            photo.topAnchor.constraint(equalTo: contentView.topAnchor),
            photo.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photo.heightAnchor.constraint(equalToConstant: 128),
            text.topAnchor.constraint(equalTo: photo.bottomAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            youToo.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            youToo.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            youToo.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        photo.image = nil
        loadingUrl = nil
    }

    func configure(_ place: NetworkDiscoverService.LovedPlace) {
        name.text = place.name
        detail.text = [place.category?.capitalized, PlaceAddressShort.city(place.address)].compactMap { $0 }.joined(separator: " · ")
        faces.configure(place.savers)
        savedBy.text = NetworkDiscoverLayout.savedByLine(names: place.savers.map(\.displayName), total: place.saverCount)
        youToo.isHidden = !place.viewerSaved
        photo.image = UIImage(systemName: "mappin.and.ellipse")
        photo.tintColor = .tertiaryLabel
        photo.contentMode = .center
        guard let url = place.photo else { return }
        loadingUrl = url
        ImageService.shared.loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadingUrl == url, let image else { return }
                self.photo.contentMode = .scaleAspectFill
                self.photo.image = image
            }
        }
    }
}

/// "123 Main St, Charlotte, NC 28202" → "Charlotte": the part just before
/// the state ("NC" or "NC 28202"). Nil when there's no state to anchor on.
enum PlaceAddressShort {
    static func city(_ address: String?) -> String? {
        guard let parts = address?.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }),
              parts.count >= 2 else { return nil }
        let isState = { (part: String) -> Bool in
            guard let code = part.split(separator: " ").first.map(String.init) else { return false }
            return code.count == 2 && code == code.uppercased() && code.rangeOfCharacter(from: .decimalDigits) == nil
        }
        guard let stateIndex = parts.indices.dropFirst().first(where: { isState(parts[$0]) }) else { return nil }
        let city = parts[stateIndex - 1]
        return city.isEmpty || city.rangeOfCharacter(from: .decimalDigits) != nil ? nil : city
    }
}

final class LovedPlacesCardView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onSelect: ((NetworkDiscoverService.LovedPlace) -> Void)?
    var onSeeAll: (() -> Void)?
    private var places: [NetworkDiscoverService.LovedPlace] = []
    private let header = NetworkCardHeader("❤️ Places your people love", action: "See all")
    private let blurb = UILabel()
    private lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 196, height: 262)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.register(LovedPlaceCell.self, forCellWithReuseIdentifier: LovedPlaceCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.onAction = { [weak self] in self?.onSeeAll?() }
        blurb.text = "Saved by two or more of your people."
        blurb.font = .systemFont(ofSize: 14)
        blurb.textColor = .secondaryLabel
        let top = UIStackView(arrangedSubviews: [header, blurb])
        top.axis = .vertical
        top.spacing = 2
        top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)
        addSubview(collection)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            collection.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.heightAnchor.constraint(equalToConstant: 262),
            collection.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ places: [NetworkDiscoverService.LovedPlace]) {
        self.places = Array(places.prefix(10))
        collection.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { places.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LovedPlaceCell.reuseId, for: indexPath) as! LovedPlaceCell
        cell.configure(places[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(places[indexPath.item])
    }
}

// MARK: - This month among your people

final class NetworkLeaderboardCardView: UIView {
    var onTap: (() -> Void)?
    private let rows = UIStackView()
    private let footer = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let header = NetworkCardHeader("🏆 This month among your people")
        rows.axis = .vertical
        rows.spacing = 2
        footer.font = .systemFont(ofSize: 14, weight: .semibold)
        footer.textColor = Constants.Colors.primary
        let box = UIStackView(arrangedSubviews: [rows, footer])
        box.axis = .vertical
        box.spacing = 10
        box.isLayoutMarginsRelativeArrangement = true
        box.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 14, trailing: 12)
        box.backgroundColor = .secondarySystemBackground
        box.layer.cornerRadius = 14
        let column = UIStackView(arrangedSubviews: [header, box])
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        box.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        box.isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { onTap?() }

    func configure(_ month: MilestoneMonthViewController.Month) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in month.board.prefix(5).enumerated() {
            let rank = UILabel()
            rank.text = index < 3 ? ["🥇", "🥈", "🥉"][index] : "\(index + 1)"
            rank.font = .systemFont(ofSize: 16, weight: .semibold)
            rank.textAlignment = .center
            rank.widthAnchor.constraint(equalToConstant: 28).isActive = true
            let face = UIImageView()
            face.translatesAutoresizingMaskIntoConstraints = false
            face.widthAnchor.constraint(equalToConstant: 30).isActive = true
            face.heightAnchor.constraint(equalToConstant: 30).isActive = true
            face.layer.cornerRadius = 15
            face.setUserAvatar(name: row.displayName, seed: row.userId, urlString: row.profilePicture, diameter: 30)
            let name = UILabel()
            name.text = row.isMe ? "\(row.displayName) (you)" : row.displayName
            name.font = .systemFont(ofSize: 15, weight: row.isMe ? .bold : .regular)
            let count = UILabel()
            count.text = row.count == 1 ? "1 place" : "\(row.count) places"
            count.font = .systemFont(ofSize: 14)
            count.textColor = .secondaryLabel
            count.setContentHuggingPriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [rank, face, name, count])
            line.spacing = 10
            line.alignment = .center
            line.isLayoutMarginsRelativeArrangement = true
            line.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            line.backgroundColor = row.isMe ? Constants.Colors.primary.withAlphaComponent(0.10) : .clear
            line.layer.cornerRadius = 8
            rows.addArrangedSubview(line)
        }
        footer.text = (NetworkDiscoverLayout.standingLine(rank: month.rank, contributors: month.contributors, behindFirst: month.behindFirst)
            ?? "Add a place to get on the board") + "  ›"
    }
}

// MARK: - People you might know

final class PersonSuggestionCell: UICollectionViewCell {
    static let reuseId = "PersonSuggestionCell"
    var onFollow: (() -> Void)?
    var onDismiss: (() -> Void)?
    private let face = UIImageView()
    private let name = UILabel()
    private let reason = UILabel()
    private lazy var follow = UIButton.smallActionButton(title: "Follow", style: .primary)
    private lazy var close = UIButton.iconButton(systemName: "xmark", pointSize: 11)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 14
        face.translatesAutoresizingMaskIntoConstraints = false
        face.layer.cornerRadius = 30
        face.clipsToBounds = true
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textAlignment = .center
        reason.font = .systemFont(ofSize: 12)
        reason.textColor = .secondaryLabel
        reason.textAlignment = .center
        reason.numberOfLines = 2
        follow.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        close.tintColor = .tertiaryLabel
        close.accessibilityLabel = "Not interested"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        let column = UIStackView(arrangedSubviews: [face, name, reason, follow])
        column.axis = .vertical
        column.spacing = 6
        column.alignment = .center
        column.setCustomSpacing(10, after: reason)
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)
        contentView.addSubview(close)
        NSLayoutConstraint.activate([
            face.widthAnchor.constraint(equalToConstant: 60),
            face.heightAnchor.constraint(equalToConstant: 60),
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            follow.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -8),
            close.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ user: User) {
        face.setUserAvatar(for: user, diameter: 60)
        name.text = user.displayName
        reason.text = NetworkDiscoverLayout.reason(for: user)
        let following = user.isFollowing == true
        follow.setTitle(following ? "Following" : "Follow", for: .normal)
        follow.isEnabled = !following
        follow.alpha = following ? 0.6 : 1
    }

    @objc private func followTapped() { onFollow?() }
    @objc private func closeTapped() { onDismiss?() }
}

final class PeopleStripView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onFollow: ((User) -> Void)?
    var onDismiss: ((User) -> Void)?
    var onSelect: ((User) -> Void)?
    private(set) var people: [User] = []
    private lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 148, height: 178)
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.register(PersonSuggestionCell.self, forCellWithReuseIdentifier: PersonSuggestionCell.reuseId)
        cv.dataSource = self
        cv.delegate = self
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let header = NetworkCardHeader("👋 People you might know")
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(collection)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            collection.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.heightAnchor.constraint(equalToConstant: 178),
            collection.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ people: [User]) {
        self.people = people
        collection.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { people.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PersonSuggestionCell.reuseId, for: indexPath) as! PersonSuggestionCell
        let user = people[indexPath.item]
        cell.configure(user)
        cell.onFollow = { [weak self] in self?.onFollow?(user) }
        cell.onDismiss = { [weak self] in self?.onDismiss?(user) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(people[indexPath.item])
    }
}

// MARK: - Invite friends

final class InviteCardView: UIView {
    var onInvite: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let title = UILabel()
        title.text = "💌 Invite friends"
        title.font = .systemFont(ofSize: 18, weight: .bold)
        let body = UILabel()
        body.text = "Circles is better with your people. Friends who join with your code get a month of Premium free, and you earn 🌵 FavCoins once they're in."
        body.font = .systemFont(ofSize: 14)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        let button = UIButton.primaryButton(title: "Invite friends")
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let column = UIStackView(arrangedSubviews: [title, body, button])
        column.axis = .vertical
        column.spacing = 10
        column.setCustomSpacing(14, after: body)
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        column.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.10)
        column.layer.cornerRadius = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { onInvite?() }
}

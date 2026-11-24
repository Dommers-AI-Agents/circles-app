import UIKit
import MapKit

/// The lively Activity row (2026-11-16): media first — a check-in's map with
/// a dropped pin, a saved place's photo, a stack of photos, a looping
/// moment — then who did it, the words, and the heart. Rows with nothing to
/// show stay `ActivityFeedCell`. Double-tap the picture to react.
final class ActivityHeroCell: UITableViewCell {
    static let identifier = "ActivityHeroCell"
    weak var delegate: ActivityFeedCellDelegate?

    private(set) var currentActivity: Activity?
    private var currentGroup: [Activity]?
    private var hero: ActivityRowStyle.Hero?
    private var avatarLoadId: String?
    private var photoLoadId: String?
    private var mapTask: Task<Void, Never>?
    /// The actor whose picture the avatar is showing, so swiping between one
    /// person's activities doesn't blink it
    private var shownAvatarKey: String?

    // MARK: Pages (a small burst, one activity per swipe)

    /// The burst this card pages through; empty for a single activity or a
    /// "Show all" stack
    private var pages: [Activity] = []
    private(set) var pageIndex = 0
    /// The page changed by a swipe: the feed remembers it and re-measures the row
    var onPageChange: ((Int) -> Void)?
    private let pageDots: UIPageControl = {
        let dots = UIPageControl()
        dots.hidesForSinglePage = true
        dots.isUserInteractionEnabled = false
        dots.backgroundStyle = .prominent
        dots.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.45)
        dots.currentPageIndicatorTintColor = .white
        dots.translatesAutoresizingMaskIntoConstraints = false
        dots.isHidden = true
        return dots
    }()
    private var pageSwipes: [UISwipeGestureRecognizer] = []

    // MARK: Views

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        view.layer.shadowRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    /// Everything visual sits here, clipped to the card's top corners
    private let mediaContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()
    private let photoView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let mapView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    /// The check-in's pin, dropped by the choreography
    private let pinView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        view.tintColor = Constants.Colors.primary
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        view.backgroundColor = .white
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    /// The place photo inset on a check-in's map
    private let insetPhotoView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 3
        view.layer.borderColor = UIColor.white.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    private let stackView = PhotoStackView()
    private let clipView = ActivityClipView()
    private let posterView = ActivityPosterView()
    /// "Saved to Brunch" / "Checked in"
    private let chip: PaddedPillLabel = {
        let label = PaddedPillLabel()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    private let avatarImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.layer.cornerRadius = 15
        view.clipsToBounds = true
        view.backgroundColor = Constants.Colors.lightGray
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()
    private let activityLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let quoteLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    private let reactionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private let reactionPills: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private var quoteTopConstraint: NSLayoutConstraint!
    /// 24 with chips, 0 without: no empty strip under the name (2026-11-17)
    private var pillsHeightConstraint: NSLayoutConstraint!

    // MARK: Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        contentView.addSubview(containerView)
        containerView.addSubview(mediaContainer)
        for view in [mapView, photoView, clipView, stackView, posterView, insetPhotoView, pinView, chip, pageDots] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            mediaContainer.addSubview(view)
        }
        // The full-bleed media views follow the container by constraint: a
        // manual frame set in layoutSubviews ran before the container had
        // its size (the photo stack came up blank, 2026-11-16)
        for view in [mapView, photoView, clipView, stackView, posterView] as [UIView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: mediaContainer.topAnchor),
                view.leadingAnchor.constraint(equalTo: mediaContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: mediaContainer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: mediaContainer.bottomAnchor)
            ])
        }
        for view in [avatarImageView, activityLabel, timestampLabel, quoteLabel, reactionButton, commentButton, commentCountLabel, reactionPills] as [UIView] {
            containerView.addSubview(view)
        }

        let pad = Constants.Spacing.small
        quoteTopConstraint = quoteLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 6)
        pillsHeightConstraint = reactionPills.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            containerView.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -Constants.Spacing.medium),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            mediaContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mediaContainer.heightAnchor.constraint(equalTo: mediaContainer.widthAnchor, multiplier: 0.625),

            pinView.widthAnchor.constraint(equalToConstant: 40),
            pinView.heightAnchor.constraint(equalToConstant: 40),
            insetPhotoView.leadingAnchor.constraint(equalTo: mediaContainer.leadingAnchor, constant: 12),
            insetPhotoView.bottomAnchor.constraint(equalTo: mediaContainer.bottomAnchor, constant: -12),
            insetPhotoView.widthAnchor.constraint(equalToConstant: 84),
            insetPhotoView.heightAnchor.constraint(equalToConstant: 84),
            chip.leadingAnchor.constraint(equalTo: mediaContainer.leadingAnchor, constant: 12),
            chip.topAnchor.constraint(equalTo: mediaContainer.topAnchor, constant: 12),
            pageDots.centerXAnchor.constraint(equalTo: mediaContainer.centerXAnchor),
            pageDots.bottomAnchor.constraint(equalTo: mediaContainer.bottomAnchor, constant: -8),

            avatarImageView.topAnchor.constraint(equalTo: mediaContainer.bottomAnchor, constant: pad + 2),
            avatarImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: pad + 2),
            avatarImageView.widthAnchor.constraint(equalToConstant: 30),
            avatarImageView.heightAnchor.constraint(equalToConstant: 30),

            activityLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -2),
            activityLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: pad),
            activityLabel.trailingAnchor.constraint(equalTo: reactionButton.leadingAnchor, constant: -pad),
            timestampLabel.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 2),
            timestampLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),

            reactionButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            reactionButton.trailingAnchor.constraint(equalTo: commentButton.leadingAnchor, constant: -10),
            reactionButton.widthAnchor.constraint(equalToConstant: 26),
            reactionButton.heightAnchor.constraint(equalToConstant: 26),
            commentButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            commentButton.trailingAnchor.constraint(equalTo: commentCountLabel.leadingAnchor, constant: -2),
            commentButton.widthAnchor.constraint(equalToConstant: 26),
            commentButton.heightAnchor.constraint(equalToConstant: 26),
            commentCountLabel.centerYAnchor.constraint(equalTo: commentButton.centerYAnchor),
            commentCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -pad - 2),
            commentCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 10),

            quoteTopConstraint,
            quoteLabel.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            quoteLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -pad - 2),
            reactionPills.topAnchor.constraint(equalTo: quoteLabel.bottomAnchor, constant: 4),
            reactionPills.leadingAnchor.constraint(equalTo: activityLabel.leadingAnchor),
            pillsHeightConstraint,
            reactionPills.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -pad - 2)
        ])
        pinView.isHidden = true

        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(mediaTapped))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(mediaDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        mediaContainer.addGestureRecognizer(tap)
        mediaContainer.addGestureRecognizer(doubleTap)
        containerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(contentTapped)))
        reactionButton.addTarget(self, action: #selector(reactionTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(reactionLongPressed(_:)))
        longPress.minimumPressDuration = 0.5
        reactionButton.addGestureRecognizer(longPress)
        reactionPills.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pillsTapped)))
        stackView.onTap = { [weak self] _ in self?.mediaTapped() }
        // A paged burst swipes anywhere on the card, not only on the picture
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(pageSwiped(_:)))
            swipe.direction = direction
            swipe.isEnabled = false
            containerView.addGestureRecognizer(swipe)
            pageSwipes.append(swipe)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.layer.shadowPath = UIBezierPath(roundedRect: containerView.bounds, cornerRadius: 16).cgPath
        placePin()
    }

    // MARK: Configure

    func configure(activity: Activity, hero: ActivityRowStyle.Hero) {
        setPages([], index: 0)
        render(activity: activity, hero: hero)
    }

    /// A small burst by one person as one card: every swipe is a whole
    /// activity — its picture, its words, its own heart and comments — so
    /// nothing opens underneath (Wes, 2026-11-24).
    func configure(pages activities: [Activity], index: Int) {
        guard !activities.isEmpty else { return }
        setPages(activities, index: index)
        renderPage()
        // The other pages' pictures, so a swipe lands on a drawn card
        for (offset, activity) in activities.enumerated() where offset != pageIndex {
            guard let url = ActivityRowStyle.picture(of: activity) else { continue }
            ImageService.shared.loadImageWithKey(from: url, cacheKey: "activity_hero_\(url)") { _ in }
        }
    }

    private func setPages(_ activities: [Activity], index: Int) {
        pages = activities
        pageIndex = ActivityGroupLayout.page(index, count: activities.count)
        let paged = activities.count > 1
        pageDots.numberOfPages = paged ? activities.count : 0
        pageDots.currentPage = pageIndex
        pageDots.isHidden = !paged
        pageSwipes.forEach { $0.isEnabled = paged }
        // The photo stack has its own sideways swipe; on a paged card the swipe turns the page
        stackView.isUserInteractionEnabled = !paged
    }

    private func renderPage() {
        guard pages.indices.contains(pageIndex) else { return }
        let activity = pages[pageIndex]
        let hero: ActivityRowStyle.Hero
        if case .hero(let own) = ActivityRowStyle.style(single: activity) {
            hero = own
        } else {
            hero = .poster(ActivityRowStyle.poster(for: activity))
        }
        render(activity: activity, hero: hero)
        pageDots.currentPage = pageIndex
        mediaContainer.bringSubviewToFront(pageDots)
    }

    /// Turns the page; false at either end. The gesture calls this.
    @discardableResult
    func turnPage(forward: Bool) -> Bool {
        guard let next = ActivityGroupLayout.page(after: pageIndex, count: pages.count, forward: forward) else {
            return false
        }
        pageIndex = next
        if ActivityFeedPreference.animates, window != nil {
            let push = CATransition()
            push.type = .push
            push.subtype = forward ? .fromRight : .fromLeft
            push.duration = 0.28
            push.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mediaContainer.layer.add(push, forKey: "page")
            for view in [activityLabel, timestampLabel, quoteLabel, reactionPills, reactionButton, commentCountLabel] as [UIView] {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.2
                view.layer.add(fade, forKey: "page")
            }
        }
        renderPage()
        UISelectionFeedbackGenerator().selectionChanged()
        onPageChange?(pageIndex)
        return true
    }

    @objc private func pageSwiped(_ gesture: UISwipeGestureRecognizer) {
        // Swiping left brings the next activity in from the right
        turnPage(forward: gesture.direction == .left)
    }

    private func render(activity: Activity, hero: ActivityRowStyle.Hero) {
        currentActivity = activity
        currentGroup = nil
        self.hero = hero
        activityLabel.numberOfLines = 3
        words(for: activity, name: activity.actor?.displayName, description: activity.formattedDescription)
        if activity.type == .checkIn, let message = activity.metadata?.message, !message.isEmpty {
            quoteLabel.text = "\u{201C}\(message)\u{201D}"
            quoteLabel.isHidden = false
        } else if [.placeCommented, .commentAdded, .circleCommented, .commentLiked].contains(activity.type),
                  let comment = activity.metadata?.comment, !comment.isEmpty {
            // The words of the comment, the way the compact row quotes them
            quoteLabel.text = "\u{201C}\(comment)\u{201D}"
            quoteLabel.isHidden = false
        } else {
            quoteLabel.text = nil
            quoteLabel.isHidden = true
        }
        quoteTopConstraint.constant = quoteLabel.isHidden ? 0 : 6
        configureReactions(userReaction: activity.userReaction, summary: activity.reactionSummary ?? [],
                           total: activity.reactionCount ?? 0, comments: activity.commentCount ?? 0)
        showMedia(hero)
    }

    /// A burst by one person: the stack of its pictures, with the same
    /// "Show all N ▾ / Show less ▴" line the compact summary row has
    func configure(group activities: [Activity], hero: ActivityRowStyle.Hero, isExpanded: Bool) {
        guard let first = activities.first else { return }
        setPages([], index: 0)
        currentActivity = first
        currentGroup = activities
        self.hero = hero
        words(for: first, name: first.actor?.displayName, description: activities.groupSummary)
        activityLabel.numberOfLines = 0 // the whole summary plus the Show all line
        let action = isExpanded ? "Show less ▴" : "Show all \(activities.count) activities ▾"
        let text = NSMutableAttributedString(attributedString: activityLabel.attributedText ?? NSAttributedString())
        text.append(NSAttributedString(string: "\n" + action, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: Constants.Colors.primary]))
        activityLabel.attributedText = text
        quoteLabel.text = nil
        quoteLabel.isHidden = true
        quoteTopConstraint.constant = 0
        let mine = ActivityGroupReaction.groupReaction(activities.map(\.userReaction))
        let summary = ActivityGroupReaction.summary(activities.map(\.reactionSummary))
        configureReactions(userReaction: mine, summary: summary, total: summary.reduce(0) { $0 + $1.count }, comments: 0)
        commentButton.isHidden = true
        commentCountLabel.isHidden = true
        showMedia(hero)
    }

    private func words(for activity: Activity, name: String?, description: String) {
        let text = NSMutableAttributedString()
        if let name {
            text.append(NSAttributedString(string: name + " ", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: Constants.Colors.label]))
        }
        text.append(NSAttributedString(string: description, attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: Constants.Colors.label]))
        activityLabel.attributedText = text
        timestampLabel.text = activity.timeAgo
        let avatarKey = activity.actor.flatMap { actor in actor.profilePicture.map { "profile_\(actor.id)_\($0)" } }
        // Same person as the card already shows (the next page of their burst): leave the picture alone
        if let avatarKey, avatarKey == shownAvatarKey { return }
        shownAvatarKey = nil
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.primary
        if let actor = activity.actor, let picture = actor.profilePicture, !picture.isEmpty {
            let loadId = UUID().uuidString
            avatarLoadId = loadId
            ImageService.shared.loadImageWithKey(from: picture, cacheKey: "profile_\(actor.id)_\(picture)") { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.avatarLoadId == loadId, let image else { return }
                    self.avatarImageView.image = image
                    self.shownAvatarKey = avatarKey
                    if !self.posterView.isHidden { self.posterView.setBackdrop(image) }
                }
            }
        }
    }

    private func configureReactions(userReaction: String?, summary: [ReactionSummary], total: Int, comments: Int) {
        commentButton.isHidden = false
        if let userReaction, let style = ReactionStyle(emoji: userReaction) {
            reactionButton.setImage(UIImage(systemName: "heart.fill"), for: .normal)
            reactionButton.tintColor = style.backgroundColor
        } else {
            reactionButton.setImage(UIImage(systemName: "heart"), for: .normal)
            reactionButton.tintColor = Constants.Colors.secondaryLabel
        }
        commentCountLabel.text = comments > 0 ? "\(comments)" : nil
        commentCountLabel.isHidden = comments == 0
        reactionPills.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillsHeightConstraint.constant = summary.isEmpty ? 0 : 24
        let top = summary.prefix(3)
        for reaction in top {
            let pill = ReactionPillView(configuration: ReactionPillConfiguration(emoji: reaction.emoji, count: reaction.count, isUserReaction: reaction.emoji == userReaction))
            pill.translatesAutoresizingMaskIntoConstraints = false
            reactionPills.addArrangedSubview(pill)
        }
        let shown = top.reduce(0) { $0 + $1.count }
        if total > shown {
            let more = UILabel()
            more.text = "+\(total - shown)"
            more.font = .systemFont(ofSize: 11)
            more.textColor = Constants.Colors.secondaryLabel
            reactionPills.addArrangedSubview(more)
        }
    }

    // MARK: Media

    private func showMedia(_ hero: ActivityRowStyle.Hero) {
        mapTask?.cancel()
        mapTask = nil
        ActivityChoreography.clearRipples(in: mediaContainer)
        [mapView, photoView, insetPhotoView, pinView, chip].forEach { $0.isHidden = true }
        stackView.isHidden = true
        clipView.isHidden = true
        posterView.isHidden = true
        clipView.stop()
        stackView.reset()
        posterView.reset()
        mediaContainer.backgroundColor = Constants.Colors.lightGray

        switch hero {
        case .checkIn(let photo, let pin):
            // The place's photo leads (Wes, 2026-11-16: "rather than the
            // pin map image"); the map stands in only when there is no photo
            chip.text = "Checked in"
            chip.isHidden = false
            if let photo {
                photoView.isHidden = false
                load(photo, into: photoView)
            } else if let pin {
                mapView.isHidden = false
                pinView.isHidden = false
                loadMap(at: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude))
            }
        case .placeAdded(let photo, let circleName):
            photoView.isHidden = false
            load(photo, into: photoView)
            chip.text = circleName.map { "Saved to \($0)" } ?? "Saved"
            chip.isHidden = false
        case .photos(let urls):
            stackView.isHidden = false
            mediaContainer.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.08)
            stackView.configure(urls: urls)
        case .moment(let thumb, let clip):
            clipView.isHidden = false
            clipView.configure(thumbnail: thumb, clip: clip)
        case .postcard(let image):
            photoView.isHidden = false
            load(image, into: photoView)
        case .run(let snapshot, let detail):
            // The route map, the way FavRun drew it; the stats as the chip
            photoView.isHidden = false
            mediaContainer.backgroundColor = UIColor(red: 0.87, green: 0.42, blue: 0.13, alpha: 1)
            load(snapshot, into: photoView)
            chip.text = detail.map { "🏃 \($0)" } ?? "🏃 Went for a run"
            chip.isHidden = false
        case .workout(let photo, let poster):
            // The workout's card over the gym's photo, sharp, darkened at
            // the bottom so the name and stats read
            posterView.isHidden = false
            posterView.configure(poster)
            posterView.showPhoto(url: photo)
            chip.text = poster.chip
            chip.isHidden = poster.chip == nil
        case .tagged(let photo, let label):
            // A like, a comment, a circle: the picture, the chip says which
            photoView.isHidden = false
            load(photo, into: photoView)
            chip.text = label
            chip.isHidden = false
        case .placeMap(let pin, let label):
            // No picture yet, but a pin: the block, the way a check-in shows it
            mapView.isHidden = false
            pinView.isHidden = false
            loadMap(at: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude))
            chip.text = label
            chip.isHidden = false
        case .poster(let poster):
            posterView.isHidden = false
            posterView.configure(poster)
            // The actor's photo as the wash: the one already on the avatar,
            // else whatever the avatar load brings
            let avatar = avatarImageView.image
            posterView.setBackdrop(avatar?.isSymbolImage == true ? nil : avatar)
            chip.text = poster.chip
            chip.isHidden = poster.chip == nil
        }
        setNeedsLayout()
    }

    private func load(_ url: String, into view: UIImageView) {
        let loadId = UUID().uuidString
        photoLoadId = loadId
        // Already downloaded (a page of a burst, a row scrolled back to): no blank frame
        if let cached = ImageService.shared.cachedImage(forKey: "activity_hero_\(url)") {
            view.image = cached
            return
        }
        view.image = nil
        ImageService.shared.loadImageWithKey(from: url, cacheKey: "activity_hero_\(url)") { [weak self, weak view] image in
            DispatchQueue.main.async {
                guard let self, self.photoLoadId == loadId, let view else { return }
                view.image = image ?? UIImage(systemName: "photo")
            }
        }
    }

    private var pinPoint: CGPoint?
    private var mapCoordinate: CLLocationCoordinate2D?

    private func loadMap(at coordinate: CLLocationCoordinate2D) {
        mapCoordinate = coordinate
        mapView.image = nil
        pinPoint = nil
        let size = mediaContainer.bounds.width > 0 ? mediaContainer.bounds.size : CGSize(width: UIScreen.main.bounds.width - 32, height: (UIScreen.main.bounds.width - 32) * 0.625)
        if let hit = MapSnapshotCache.shared.cached(at: coordinate, size: size) {
            mapView.image = hit.image
            pinPoint = hit.pinPoint
            placePin()
            return
        }
        // Until the map is drawn, the pin sits in the middle (the place is the region's centre)
        placePin()
        mapTask = Task { @MainActor [weak self] in
            guard let snapshot = await MapSnapshotCache.shared.snapshot(at: coordinate, size: size) else { return }
            guard let self, !Task.isCancelled, self.mapCoordinate?.latitude == coordinate.latitude, self.mapCoordinate?.longitude == coordinate.longitude else { return }
            UIView.transition(with: self.mapView, duration: 0.25, options: .transitionCrossDissolve) { self.mapView.image = snapshot.image }
            self.pinPoint = snapshot.pinPoint
            self.placePin()
        }
    }

    private func placePin() {
        guard !pinView.isHidden else { return }
        let point = pinPoint ?? CGPoint(x: mediaContainer.bounds.midX, y: mediaContainer.bounds.midY)
        pinView.center = CGPoint(x: point.x, y: point.y - 2)
    }

    // MARK: Motion

    /// The row's first appearance: a pin drops, a photo settles, a stack fans
    func runMoment() {
        guard let hero, ActivityFeedPreference.animates else { return }
        switch hero {
        case .checkIn(let photo, let pin):
            if photo != nil {
                ActivityChoreography.settle(photoView)
            } else if pin != nil {
                ActivityChoreography.pinDrop(pinView, ripplesIn: mediaContainer, at: pinView.center)
            }
            ActivityChoreography.slideInChip(chip, delay: 0.3)
        case .placeAdded, .postcard, .run, .tagged:
            ActivityChoreography.settle(photoView)
            ActivityChoreography.slideInChip(chip)
        case .placeMap:
            ActivityChoreography.pinDrop(pinView, ripplesIn: mediaContainer, at: pinView.center)
            ActivityChoreography.slideInChip(chip, delay: 0.3)
        case .poster, .workout:
            ActivityChoreography.settle(posterView)
            ActivityChoreography.slideInChip(chip)
        case .photos:
            stackView.fanOpen()
        case .moment:
            break
        }
    }

    /// The looping clip, if this card has one
    var hasClip: Bool { clipView.clipURL != nil && !clipView.isHidden }
    func playClip() { if hasClip { clipView.play() } }
    func pauseClip() { clipView.pause() }

    // MARK: Actions

    @objc private func avatarTapped() {
        guard let actor = currentActivity?.actor else { return }
        delegate?.didTapUserProfile(user: actor)
    }

    @objc private func mediaTapped() {
        if let group = currentGroup { delegate?.didTapActivityGroup(activities: group); return }
        guard let activity = currentActivity else { return }
        delegate?.didTapPlaceImage(activity: activity)
    }

    @objc private func contentTapped() {
        if let group = currentGroup { delegate?.didTapActivityGroup(activities: group); return }
        guard let activity = currentActivity else { return }
        delegate?.didTapActivityContent(activity: activity)
    }

    @objc private func mediaDoubleTapped(_ gesture: UITapGestureRecognizer) {
        HeartBurstView.show(at: gesture.location(in: mediaContainer), in: mediaContainer)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let group = currentGroup {
            delegate?.didTapGroupReactionButton(activities: group, emoji: "👍")
        } else if let activity = currentActivity, activity.userReaction == nil {
            delegate?.didTapReactionButton(activity: activity, emoji: "👍")
        }
    }

    @objc private func reactionTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let group = currentGroup { delegate?.didTapGroupReactionButton(activities: group, emoji: "👍"); return }
        guard let activity = currentActivity else { return }
        delegate?.didTapReactionButton(activity: activity, emoji: "👍")
    }

    @objc private func reactionLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let group = currentGroup { delegate?.didLongPressGroupReactionButton(activities: group, sourceView: reactionButton); return }
        guard let activity = currentActivity else { return }
        delegate?.didLongPressReactionButton(activity: activity, sourceView: reactionButton)
    }

    @objc private func commentTapped() {
        guard let activity = currentActivity else { return }
        delegate?.didTapComments(activity: activity)
    }

    @objc private func pillsTapped() {
        if let group = currentGroup { delegate?.didTapActivityGroup(activities: group); return }
        guard let activity = currentActivity else { return }
        delegate?.didTapReactions(activity: activity)
    }

    // MARK: Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        mapTask?.cancel()
        mapTask = nil
        avatarLoadId = nil
        photoLoadId = nil
        currentGroup = nil
        setPages([], index: 0)
        onPageChange = nil
        shownAvatarKey = nil
        mediaContainer.layer.removeAnimation(forKey: "page")
        hero = nil
        pinPoint = nil
        mapCoordinate = nil
        clipView.stop()
        stackView.reset()
        posterView.reset()
        ActivityChoreography.clearRipples(in: mediaContainer)
        for view in [mapView, photoView, insetPhotoView] { view.image = nil }
        pinView.transform = .identity
        pinView.alpha = 1
        photoView.transform = .identity
        photoView.alpha = 1
        posterView.transform = .identity
        posterView.alpha = 1
        chip.transform = .identity
        chip.alpha = 1
        containerView.transform = .identity
        containerView.alpha = 1
    }
}

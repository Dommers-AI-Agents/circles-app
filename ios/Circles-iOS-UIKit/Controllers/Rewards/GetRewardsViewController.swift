import UIKit

/// "Get Rewards" for one store. Redesigned 2026-11-02 (Wes: "very bland…
/// you can barely see their balance… use the empty space to add value"):
///
/// - the store's photo across the top, its name over it
/// - the balance, big, on a card over the photo, with the next reward's
///   progress and Redeem right there
/// - an open ticket, then your visits / points earned / rewards used here
/// - how to earn (scan at the register), every reward with Redeem, what's on,
///   your latest moves here, and Add to Apple Wallet
///
/// Opened from the place page's Get Rewards button, the check-in confirmation
/// and the store's Apple Wallet card. Draws from the venue data the caller
/// has, then refetches once with the history and cover photo.
final class GetRewardsViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private static let heroHeight: CGFloat = 300
    /// How far the balance card rides up over the photo
    private static let cardOverlap: CGFloat = 56

    private let place: Place
    private var details: RewardsAvailability.Details
    /// The store's id and offers as the server sent them, so an offer the
    /// customer can afford is redeemed right here (Wes, 2026-11-02: it was
    /// only on the store page's rewards card)
    private var venueId: String?
    private var redeemableOffers: [RewardOffer] = []
    private var history: VenueRewardHistory?
    private var address: String?

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        // The photo runs up under the navigation bar
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let content = UIView()

    // MARK: Header

    private let heroImage: UIImageView = {
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.35)
        return image
    }()
    /// Darkens the photo's bottom so the white name always reads
    private let heroShade = GradientView()
    private let storeNameLabel = GetRewardsViewController.label(size: Constants.FontSize.huge, weight: .bold, color: .white)
    private let addressLabel = GetRewardsViewController.label(size: Constants.FontSize.medium, weight: .medium,
                                                              color: UIColor.white.withAlphaComponent(0.85))

    // MARK: Balance card

    private let balanceCard: UIView = {
        let card = UIView()
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 20
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 16
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        return card
    }()
    private let pointsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 56, weight: .heavy)
        label.textColor = Constants.Colors.primary
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()
    private let pointsCaption = GetRewardsViewController.label(size: Constants.FontSize.large, weight: .semibold)
    private let earnPill: UILabel = {
        let label = PaddedPillLabel()
        label.font = .systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.primary
        label.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.15)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()
    /// Progress toward the next reward (or "no rewards posted yet")
    private let nextRewardStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.small
        return stack
    }()

    // MARK: Below the card

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.large
        return stack
    }()
    /// An open reward ticket here (2026-11-01): one tap to show staff
    private let ticketSlot = GetRewardsViewController.vertical(spacing: 0)
    private let statsSlot = GetRewardsViewController.vertical(spacing: Constants.Spacing.small)
    private let offersStack = GetRewardsViewController.vertical(spacing: Constants.Spacing.xsmall)
    /// The store's current posts
    private let announcementsStack = GetRewardsViewController.vertical(spacing: Constants.Spacing.xsmall)
    private let historyStack = GetRewardsViewController.vertical(spacing: 0)
    private let walletSlot = GetRewardsViewController.vertical(spacing: Constants.Spacing.small)

    private lazy var scanButton: UIButton = {
        let button = UIButton.primaryButton(title: "Scan QR code")
        button.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
        button.tintColor = .white
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        button.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        return button
    }()

    /// - Returns: nil when the data says there are no rewards to get here.
    init?(place: Place, data: PlaceVenueData?) {
        guard let details = RewardsAvailability(data).details else { return nil }
        self.place = place
        self.details = details
        super.init(nibName: nil, bundle: nil)
        absorb(data)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = Constants.Colors.background
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        }
        // See-through bar over the photo; once the page scrolls, a solid
        // bar, so nothing slides under the clock (Wes, 2026-11-02)
        let clear = UINavigationBarAppearance()
        clear.configureWithTransparentBackground()
        let solid = UINavigationBarAppearance()
        solid.configureWithDefaultBackground()
        navigationItem.standardAppearance = solid
        navigationItem.compactAppearance = solid
        navigationItem.scrollEdgeAppearance = clear
        navigationItem.compactScrollEdgeAppearance = clear
        setContentScrollView(scrollView, for: .top)

        layout()
        render()
        showPhoto()

        NotificationCenter.default.addObserver(self, selector: #selector(pointsChanged),
                                               name: .rewardPointsDidChange, object: nil)
        // The history and the cover photo come with one more fetch
        loadData()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Layout

    private func layout() {
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false

        let hero = UIView()
        heroShade.colors = [UIColor.black.withAlphaComponent(0.45), UIColor.black.withAlphaComponent(0.05),
                            UIColor.black.withAlphaComponent(0.75)]
        heroShade.locations = [0, 0.35, 1]
        let heroText = UIStackView(arrangedSubviews: [storeNameLabel, addressLabel])
        heroText.axis = .vertical
        heroText.spacing = Constants.Spacing.tiny
        storeNameLabel.numberOfLines = 2
        storeNameLabel.adjustsFontSizeToFitWidth = true
        storeNameLabel.minimumScaleFactor = 0.7
        // The store's name opens its place page (Wes, 2026-11-05)
        heroText.isUserInteractionEnabled = true
        heroText.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(storeNameTapped)))
        heroText.isAccessibilityElement = true
        heroText.accessibilityTraits = .button
        heroText.accessibilityHint = "Opens the store's page"

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = Constants.Spacing.small
        let pointsRow = UIStackView(arrangedSubviews: [pointsLabel, earnPill])
        pointsRow.alignment = .center
        pointsRow.spacing = Constants.Spacing.small
        cardStack.addArrangedSubview(pointsRow)
        cardStack.setCustomSpacing(0, after: pointsRow)
        cardStack.addArrangedSubview(pointsCaption)
        cardStack.setCustomSpacing(Constants.Spacing.medium, after: pointsCaption)
        cardStack.addArrangedSubview(nextRewardStack)
        balanceCard.addSubview(cardStack)

        stack.addArrangedSubview(ticketSlot)
        stack.addArrangedSubview(statsSlot)
        stack.addArrangedSubview(earnSection())
        stack.addArrangedSubview(offersStack)
        stack.addArrangedSubview(announcementsStack)
        stack.addArrangedSubview(historyStack)
        stack.addArrangedSubview(walletSlot)

        for v in [hero, balanceCard, stack] as [UIView] { content.addSubview(v) }
        for v in [heroImage, heroShade, heroText] as [UIView] { hero.addSubview(v) }
        for v in [hero, heroImage, heroShade, heroText, balanceCard, cardStack, stack] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        let side = Constants.Spacing.medium
        // The photo stretches when pulled down: pinned to the top of the
        // screen, not of the content, and as tall as the pull
        let imageTop = heroImage.topAnchor.constraint(equalTo: view.topAnchor)
        imageTop.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            hero.topAnchor.constraint(equalTo: content.topAnchor),
            hero.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hero.heightAnchor.constraint(equalToConstant: Self.heroHeight),

            imageTop,
            heroImage.topAnchor.constraint(lessThanOrEqualTo: hero.topAnchor),
            heroImage.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            heroImage.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            heroImage.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            heroShade.topAnchor.constraint(equalTo: heroImage.topAnchor),
            heroShade.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            heroShade.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            heroShade.bottomAnchor.constraint(equalTo: hero.bottomAnchor),

            heroText.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: side + 4),
            heroText.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -side),
            heroText.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -(Self.cardOverlap + Constants.Spacing.small)),

            balanceCard.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: -Self.cardOverlap),
            balanceCard.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: side),
            balanceCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -side),
            cardStack.topAnchor.constraint(equalTo: balanceCard.topAnchor, constant: Constants.Spacing.medium),
            cardStack.bottomAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: -Constants.Spacing.medium),
            cardStack.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: 18),
            cardStack.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -18),

            stack.topAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: Constants.Spacing.large),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: side),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -side),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Constants.Spacing.xlarge)
        ])
    }

    /// How to earn: one card, one button
    private func earnSection() -> UIView {
        let body = Self.label(size: Constants.FontSize.large, weight: .regular)
        body.text = "After you buy something, scan the FavCircles QR code by the register. Ask staff if you can't find it. You can earn once a day."
        return Self.sectionCard(title: "Earn at the register", symbol: "qrcode", tint: Constants.Colors.primary,
                                rows: [body, scanButton], dividers: false)
    }

    /// Whether this page is for the store at `placeId` (venue or save id)
    func showsStore(placeId: String) -> Bool {
        placeId == place.id || placeId == place.globalPlaceId
    }

    // MARK: - Content

    private func absorb(_ data: PlaceVenueData?) {
        guard let data else { return }
        venueId = data.venue?.venueId ?? venueId
        redeemableOffers = (data.offers ?? []).filter { $0.active != false }
        if let history = data.myHistory { self.history = history }
        address = data.venue?.placeAddress ?? address
        if let cover = data.venue?.coverPhotoUrl, !cover.isEmpty { coverPhotoUrl = cover }
    }

    private var coverPhotoUrl: String?

    private func showPhoto() {
        guard let url = coverPhotoUrl ?? place.photos?.first, !url.isEmpty, heroImage.image == nil else { return }
        ImageService.shared.loadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, let image else { return }
                self.heroImage.alpha = 0
                self.heroImage.image = image
                UIView.animate(withDuration: 0.3) { self.heroImage.alpha = 1 }
            }
        }
    }

    private func render() {
        storeNameLabel.attributedText = Self.nameWithChevron(details.venueName)
        let line = address ?? place.address
        addressLabel.text = line
        addressLabel.isHidden = (line ?? "").isEmpty
        storeNameLabel.superview?.accessibilityLabel = [details.venueName, line].compactMap { $0 }.joined(separator: ", ")

        pointsLabel.text = details.venueBalance.formatted()
        pointsCaption.text = details.venueBalance == 1 ? "point at \(details.venueName)" : "points at \(details.venueName)"
        if let rate = details.earnRate, rate > 0 {
            earnPill.text = "+\(rate) / visit"
            earnPill.isHidden = false
        } else {
            earnPill.isHidden = true
        }

        renderNextReward()
        renderTicket()
        renderStats()
        renderOffers()
        renderAnnouncements()
        renderHistory()
        renderWallet()
    }

    private func renderTicket() {
        ticketSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let ticket = RewardsService.shared.activeTicket(venueId: venueId, venueName: details.venueName)
        ticketSlot.isHidden = ticket == nil
        guard let ticket else { return }
        let bar = RewardTicketBar(ticket: ticket)
        bar.onTap = { [weak self] ticket in
            guard let self else { return }
            RewardTicketBar.present(ticket, from: self)
        }
        ticketSlot.addArrangedSubview(bar)
    }

    /// Inside the balance card: the bar toward the next reward, and Redeem
    /// once it's affordable. Body text in the full label color: the grey
    /// caption was hard to read (Wes, 2026-11-02).
    private func renderNextReward() {
        nextRewardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let reward = RewardsAvailability.nextReward(details) else {
            let line = Self.label(size: Constants.FontSize.large, weight: .regular)
            line.text = StoreRewardsCopy.noOffersLine(venueName: details.venueName, balance: details.venueBalance)
            nextRewardStack.addArrangedSubview(Self.separator())
            nextRewardStack.addArrangedSubview(line)
            return
        }
        nextRewardStack.addArrangedSubview(Self.separator())
        let header = Self.label(size: Constants.FontSize.small, weight: .bold,
                                color: reward.canRedeem ? Constants.Colors.success : Constants.Colors.secondaryLabel)
        header.text = (reward.canRedeem ? "Ready to redeem" : "Your next reward").uppercased()
        let title = Self.label(size: Constants.FontSize.xxlarge, weight: .bold)
        title.text = reward.title
        let cost = Self.label(size: Constants.FontSize.large, weight: .semibold)
        cost.text = "\(min(details.venueBalance, reward.pointsCost)) / \(reward.pointsCost)"
        cost.setContentHuggingPriority(.required, for: .horizontal)
        cost.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [title, cost])
        top.spacing = Constants.Spacing.small
        top.alignment = .firstBaseline
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = reward.canRedeem ? Constants.Colors.success : Constants.Colors.primary
        bar.trackTintColor = Constants.Colors.primary.withAlphaComponent(0.18)
        bar.progress = reward.fraction
        bar.layer.cornerRadius = 4
        bar.clipsToBounds = true
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let line = Self.label(size: Constants.FontSize.large, weight: .regular)
        line.text = RewardsAvailability.nextRewardLine(reward)
        for v in [header, top, bar, line] { nextRewardStack.addArrangedSubview(v) }
        nextRewardStack.setCustomSpacing(Constants.Spacing.tiny, after: header)
        if reward.canRedeem, let offer = offer(titled: reward.title, cost: reward.pointsCost) {
            let redeem = UIButton.primaryButton(title: "Redeem \(reward.title)")
            redeem.addAction(UIAction { [weak self] _ in self?.redeem(offer) }, for: .touchUpInside)
            nextRewardStack.setCustomSpacing(Constants.Spacing.medium, after: line)
            nextRewardStack.addArrangedSubview(redeem)
        }
    }

    /// Visits · points earned · rewards used here, and when they were last in
    private func renderStats() {
        statsSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let history else {
            statsSlot.isHidden = true
            return
        }
        statsSlot.isHidden = false
        let tiles = UIStackView(arrangedSubviews: [
            Self.statTile(value: history.visits, label: history.visits == 1 ? "Visit" : "Visits", symbol: "figure.walk"),
            Self.statTile(value: history.earned, label: "Points earned", symbol: "star.fill"),
            Self.statTile(value: history.redeemed, label: history.redeemed == 1 ? "Reward used" : "Rewards used", symbol: "gift.fill")
        ])
        tiles.distribution = .fillEqually
        tiles.spacing = Constants.Spacing.xsmall
        let line = Self.label(size: Constants.FontSize.medium, weight: .regular, color: Constants.Colors.secondaryLabel)
        line.text = StoreRewardsCopy.lastVisitLine(history)
        statsSlot.addArrangedSubview(Self.sectionCard(title: "You at \(details.venueName)", symbol: "person.fill",
                                                      tint: Constants.Colors.primary, rows: [tiles, line], dividers: false))
    }

    private func renderOffers() {
        offersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        offersStack.isHidden = details.offers.isEmpty
        guard !details.offers.isEmpty else { return }
        let rows = details.offers.sorted(by: { $0.pointsCost < $1.pointsCost }).map(offerRow)
        offersStack.addArrangedSubview(Self.sectionCard(title: "What your points get you", symbol: "gift.fill",
                                                        tint: Constants.Colors.success, rows: rows))
    }

    /// The customer's latest moves here: visits, rewards, points back
    private func renderHistory() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows = history?.recent ?? []
        historyStack.isHidden = rows.isEmpty
        guard !rows.isEmpty else { return }
        historyStack.addArrangedSubview(Self.sectionCard(title: "Your recent activity", symbol: "clock.fill",
                                                         tint: Constants.Colors.info, rows: rows.map(historyRow)))
    }

    private func historyRow(_ row: VenueRewardHistory.Row) -> UIView {
        let symbol: String
        let tint: UIColor
        switch row.kind {
        case "redeem": symbol = "gift.fill"; tint = Constants.Colors.success
        case "expired": symbol = "clock.arrow.circlepath"; tint = Constants.Colors.secondaryLabel
        case "refund": symbol = "arrow.uturn.backward.circle.fill"; tint = Constants.Colors.primary
        default: symbol = "plus.circle.fill"; tint = Constants.Colors.primary
        }
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let title = Self.label(size: Constants.FontSize.large, weight: .medium)
        title.text = row.title
        let sub = Self.label(size: Constants.FontSize.small, weight: .regular, color: Constants.Colors.secondaryLabel)
        sub.text = [StoreRewardsCopy.when(row.at), StoreRewardsCopy.rowNote(kind: row.kind)].compactMap { $0 }.joined(separator: " · ")
        let text = UIStackView(arrangedSubviews: [title, sub])
        text.axis = .vertical
        text.spacing = 2
        let points = Self.label(size: Constants.FontSize.large, weight: .bold,
                                color: row.points >= 0 ? Constants.Colors.primary : Constants.Colors.label)
        points.text = StoreRewardsCopy.signedPoints(row.points)
        points.setContentHuggingPriority(.required, for: .horizontal)
        points.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = UIStackView(arrangedSubviews: [icon, text, points])
        line.spacing = Constants.Spacing.small
        line.alignment = .center
        line.isLayoutMarginsRelativeArrangement = true
        line.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        return line
    }

    /// The points on the lock screen, kept up to date
    private func renderWallet() {
        walletSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        walletSlot.isHidden = !(WalletCardPresenter.isAvailable && venueId != nil)
        guard let venueId, WalletCardPresenter.isAvailable else { return }
        let caption = Self.label(size: Constants.FontSize.large, weight: .regular)
        caption.text = "Your points at \(details.venueName) on your lock screen when you're nearby. Tap the card to come back here and redeem."
        let button = WalletCardPresenter.makeButton { [weak self] in
            guard let self else { return }
            WalletCardPresenter.present(venueId: venueId, from: self)
        }
        walletSlot.addArrangedSubview(Self.sectionCard(title: "Keep it in Apple Wallet", symbol: "wallet.pass.fill",
                                                       tint: Constants.Colors.gray, rows: [caption, button], dividers: false))
    }

    // MARK: - Redeem

    private func offer(titled title: String, cost: Int) -> RewardOffer? {
        redeemableOffers.first { $0.title == title && $0.pointsCost == cost }
    }

    private func redeem(_ offer: RewardOffer) {
        guard let venueId else { return }
        confirmAndRedeemOffer(offer, venueId: venueId, venueName: details.venueName) { [weak self] _ in
            self?.loadData()
        }
    }

    private func renderAnnouncements() {
        announcementsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let posts = Array(details.announcements.prefix(3))
        announcementsStack.isHidden = posts.isEmpty
        guard !posts.isEmpty else { return }
        let rows: [UIView] = posts.map { post in
            let title = Self.label(size: Constants.FontSize.large, weight: .semibold)
            title.text = post.title
            let message = Self.label(size: Constants.FontSize.medium, weight: .regular)
            message.text = post.message
            let row = UIStackView(arrangedSubviews: [title, message])
            row.axis = .vertical
            row.spacing = Constants.Spacing.tiny
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
            return row
        }
        announcementsStack.addArrangedSubview(Self.sectionCard(title: "What's on at \(details.venueName)", symbol: "megaphone.fill",
                                                               tint: Constants.Colors.brightOrange, rows: rows))
    }

    private func offerRow(_ offer: RewardsAvailability.Offer) -> UIView {
        let title = Self.label(size: Constants.FontSize.large, weight: .medium)
        title.text = offer.title
        let affordable = offer.pointsCost <= details.venueBalance
        let cost = PaddedPillLabel()
        cost.font = .systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        cost.textColor = affordable ? Constants.Colors.success : Constants.Colors.secondaryLabel
        cost.backgroundColor = (affordable ? Constants.Colors.success : Constants.Colors.gray).withAlphaComponent(0.15)
        cost.text = "\(offer.pointsCost) pts"
        cost.setContentHuggingPriority(.required, for: .horizontal)
        cost.setContentCompressionResistancePriority(.required, for: .horizontal)

        var parts: [UIView] = [title, cost]
        // Enough points: Redeem right in the row
        if offer.pointsCost <= details.venueBalance, let match = self.offer(titled: offer.title, cost: offer.pointsCost) {
            let redeem = UIButton.smallActionButton(title: "Redeem", style: .primary)
            redeem.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
            redeem.setContentHuggingPriority(.required, for: .horizontal)
            redeem.setContentCompressionResistancePriority(.required, for: .horizontal)
            redeem.addAction(UIAction { [weak self] _ in self?.redeem(match) }, for: .touchUpInside)
            parts.append(redeem)
        }
        let row = UIStackView(arrangedSubviews: parts)
        row.spacing = Constants.Spacing.small
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        return row
    }

    // MARK: - Refresh

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getVenueByPlace(placeId: place.globalPlaceId ?? place.id,
                                              googlePlaceId: place.googlePlaceId,
                                              includeHistory: true) { [weak self] result in
            DispatchQueue.main.async {
                if let self, case .success(let data) = result, let details = RewardsAvailability(data).details {
                    self.details = details
                    self.absorb(data)
                    self.render()
                    self.showPhoto()
                }
                completion?()
            }
        }
    }

    @objc private func pointsChanged() {
        loadData()
    }

    // MARK: - Actions

    @objc private func scanTapped() {
        let nav = UINavigationController(rootViewController: RewardScannerViewController())
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// The store's place page. Opened from that page (its Get Rewards
    /// button), going back is the way there; from anywhere else it opens.
    @objc private func storeNameTapped() {
        guard let nav = navigationController else { return }
        if let index = nav.viewControllers.firstIndex(of: self), index > 0,
           nav.viewControllers[index - 1] is PlaceDetailViewController {
            nav.popViewController(animated: true)
            return
        }
        nav.pushViewController(PlaceDetailViewController(place: place), animated: true)
    }

    /// "Sal's Bakery ›": the name reads as something to tap
    private static func nameWithChevron(_ name: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name + " ")
        let config = UIImage.SymbolConfiguration(pointSize: Constants.FontSize.large, weight: .bold)
        if let chevron = UIImage(systemName: "chevron.right", withConfiguration: config)?
            .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
            text.append(NSAttributedString(attachment: NSTextAttachment(image: chevron)))
        }
        return text
    }

    @objc private func closeTapped() {
        (navigationController ?? self).dismiss(animated: true)
    }

    // MARK: - Factories

    private static func label(size: CGFloat, weight: UIFont.Weight, color: UIColor = Constants.Colors.label) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// A section of the page: its own card, a colored icon and title on
    /// top, the rows below, divided. Each section reads as its own block
    /// (Wes, 2026-11-02: the rewards and "What's on" blended together).
    private static func sectionCard(title: String, symbol: String, tint: UIColor, rows: [UIView], dividers: Bool = true) -> UIView {
        let chip = UIView()
        chip.backgroundColor = tint.withAlphaComponent(0.18)
        chip.layer.cornerRadius = 10
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(icon)
        chip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 34),
            chip.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18)
        ])
        let titleLabel = label(size: Constants.FontSize.xlarge, weight: .bold)
        titleLabel.text = title
        titleLabel.accessibilityTraits = .header
        let header = UIStackView(arrangedSubviews: [chip, titleLabel])
        header.spacing = Constants.Spacing.small
        header.alignment = .center

        let body = vertical(spacing: dividers ? 0 : Constants.Spacing.small)
        for (index, row) in rows.enumerated() {
            if dividers && index > 0 { body.addArrangedSubview(separator()) }
            body.addArrangedSubview(row)
        }
        let card = card([header, body], margins: UIEdgeInsets(top: 14, left: 16, bottom: dividers ? 6 : 16, right: 16))
        card.spacing = Constants.Spacing.small
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = tint.withAlphaComponent(0.35).cgColor
        return card
    }

    private static func vertical(spacing: CGFloat) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    /// A rounded panel on the page's second background
    private static func card(_ views: [UIView], margins: UIEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)) -> UIStackView {
        let card = UIStackView(arrangedSubviews: views)
        card.axis = .vertical
        card.spacing = Constants.Spacing.small
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = margins
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = 14
        return card
    }

    private static func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = Constants.Colors.separator
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private static func statTile(value: Int, label text: String, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let number = label(size: Constants.FontSize.xxxlarge, weight: .heavy)
        number.text = value.formatted()
        number.textAlignment = .center
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.6
        let caption = label(size: Constants.FontSize.small, weight: .medium, color: Constants.Colors.secondaryLabel)
        caption.text = text
        caption.textAlignment = .center
        let tile = card([icon, number, caption], margins: UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6))
        tile.backgroundColor = Constants.Colors.tertiaryBackground
        tile.spacing = 2
        tile.alignment = .fill
        tile.isAccessibilityElement = true
        tile.accessibilityLabel = "\(value) \(text)"
        return tile
    }
}

/// A label with room around its text and fully rounded ends (the "+25 / visit" pill)
private final class PaddedPillLabel: UILabel {
    private let insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        clipsToBounds = true
    }
}

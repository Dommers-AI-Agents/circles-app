import UIKit

protocol PlaceVenueRewardsViewDelegate: AnyObject {
    func placeVenueView(_ view: PlaceVenueRewardsView, didTapRedeem offer: RewardOffer, venue: PlaceVenue)
    func placeVenueViewDidTapClaim(_ view: PlaceVenueRewardsView)
    func placeVenueViewDidTapManage(_ view: PlaceVenueRewardsView, venue: PlaceVenue)
    func placeVenueViewDidTapUpgrade(_ view: PlaceVenueRewardsView)
    func placeVenueViewDidTapStats(_ view: PlaceVenueRewardsView, venue: PlaceVenue)
    func placeVenueView(_ view: PlaceVenueRewardsView, didTapQuickAction action: PlaceVenueRewardsView.QuickAction, venue: PlaceVenue)
    // Storefront: the owner's buttons, menu, featured items and photos
    func placeVenueView(_ view: PlaceVenueRewardsView, didTapStorefrontLink url: String, title: String)
    func placeVenueView(_ view: PlaceVenueRewardsView, didTapStorefrontPhotos urls: [String], startingAt index: Int)
}

/// The rewards section of a place page: the venue's announcements and offers,
/// plus an ownership footer (claim / pending / manage). Collapses to zero
/// height when the place has no enrolled venue.
class PlaceVenueRewardsView: UIView {

    enum QuickAction {
        case announcement
        case offer
    }

    weak var delegate: PlaceVenueRewardsViewDelegate?

    /// Owner previewing their own page as a customer sees it — suppresses all
    /// owner chrome for this render. Caller re-configures after toggling.
    var viewAsCustomer = false

    private var data: PlaceVenueData?

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Constants.Colors.secondaryBackground
        layer.cornerRadius = 12
        clipsToBounds = true
        isHidden = true

        addSubview(containerStack)
        // Bottom is breakable so an external height==0 (collapsed) constraint
        // wins without conflicts while the section is empty
        let bottomConstraint = containerStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    func configure(with data: PlaceVenueData?) {
        self.data = data
        containerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let data = data else {
            isHidden = true
            return
        }

        guard let venue = data.venue else {
            // No rewards venue — but a business can still be claimed by its
            // owner, so show a slim "Is this your store?" card when relevant
            if let footer = makeClaimOnlyFooter(data.claim) {
                isHidden = false
                containerStack.addArrangedSubview(footer)
            } else {
                isHidden = true
            }
            return
        }
        isHidden = false

        // The owner's own store is visually unmistakable: primary border,
        // "Your Store" header, and a prominent Manage CTA up top
        let isOwner = data.isOwner == true && !viewAsCustomer
        layer.borderWidth = isOwner ? 1.5 : 0
        layer.borderColor = isOwner ? Constants.Colors.primary.withAlphaComponent(0.35).cgColor : nil

        containerStack.addArrangedSubview(makeHeader(venue, isOwner: isOwner))
        // The money buttons sit right under the name — Reserve / Order are
        // the reason most people open a store's page at all.
        if let actions = data.storefront?.actions, let row = makeActionButtonsRow(actions) {
            containerStack.addArrangedSubview(row)
        }
        if isOwner {
            if let stats = data.ownerStats {
                containerStack.addArrangedSubview(makeOwnerStatsStrip(stats, venue: venue))
            }
            containerStack.addArrangedSubview(makeManageStoreButton(venue))
            if let quickActions = makeQuickActionsRow(venue, premium: data.ownerPremium == true) {
                containerStack.addArrangedSubview(quickActions)
            }
        }

        // Server filters expired announcements; re-filter as a stale-cache defense
        let announcements = (data.announcements ?? []).filter { !$0.isExpired }
        announcements.forEach { announcement in
            let row = makeAnnouncementRow(announcement)
            if isOwner { attachManageTap(to: row, venue: venue) }
            containerStack.addArrangedSubview(row)
        }

        // Free-tier owner on their own page: show where announcements would
        // appear and what unlocks them. Only the claimed owner ever sees this.
        if isOwner && data.ownerPremium == false {
            containerStack.addArrangedSubview(makeUpgradeTeaserRow())
        }

        let offers = data.offers ?? []
        if !offers.isEmpty && !announcements.isEmpty {
            containerStack.addArrangedSubview(makeSeparator())
        }
        offers.forEach { offer in
            containerStack.addArrangedSubview(
                // Per-store loyalty: offers here are paid with points earned
                // HERE (venueBalance); the account total is display only.
                makeOfferRow(offer, venue: venue, balance: data.venueBalance ?? data.balance ?? 0, isOwner: isOwner)
            )
        }

        if let storefront = data.storefront {
            let hasLoyaltyRows = !announcements.isEmpty || !offers.isEmpty
            if let offerings = storefront.offerings, !offerings.isEmpty {
                if hasLoyaltyRows { containerStack.addArrangedSubview(makeSeparator()) }
                if !offerings.featured.isEmpty {
                    containerStack.addArrangedSubview(makeFeaturedStrip(offerings.featured, label: storefront.offeringsLabel))
                }
                if let row = makeMenuRow(offerings, label: storefront.offeringsLabel) {
                    containerStack.addArrangedSubview(row)
                }
            }
            if !storefront.gallery.isEmpty {
                containerStack.addArrangedSubview(makeGalleryStrip(storefront.gallery))
            }
        }
        // Claim states are for non-owners only; the owner CTA lives in the header
        if !isOwner, let footer = makeOwnershipFooter(data, venue: venue) {
            containerStack.addArrangedSubview(makeSeparator())
            containerStack.addArrangedSubview(footer)
        }
    }

    // MARK: - Rows

    private func makeHeader(_ venue: PlaceVenue, isOwner: Bool = false) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: isOwner ? "storefront.fill" : "storefront"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = isOwner ? "Your Store · \(venue.venueName)" : "Rewards at \(venue.venueName)"
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = isOwner ? Constants.Colors.primary : .label
        titleLabel.numberOfLines = 1

        let earnLabel = UILabel()
        earnLabel.translatesAutoresizingMaskIntoConstraints = false
        if let earnRate = venue.earnRate {
            earnLabel.text = "Earn \(earnRate) pts per purchase"
        }
        earnLabel.font = UIFont.systemFont(ofSize: 13)
        earnLabel.textColor = .secondaryLabel
        earnLabel.numberOfLines = 1

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(earnLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            earnLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            earnLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            earnLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            earnLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    private func makeAnnouncementRow(_ announcement: VenueAnnouncement) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "megaphone.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemOrange
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = announcement.title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = announcement.message
        messageLabel.font = UIFont.systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        let expiryLabel = UILabel()
        expiryLabel.translatesAutoresizingMaskIntoConstraints = false
        if let expiry = announcement.expiryDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            expiryLabel.text = "Until \(formatter.string(from: expiry))"
        }
        expiryLabel.font = UIFont.systemFont(ofSize: 12)
        expiryLabel.textColor = .tertiaryLabel
        expiryLabel.numberOfLines = 1

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(messageLabel)
        row.addSubview(expiryLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.topAnchor.constraint(equalTo: row.topAnchor, constant: 1),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            expiryLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 2),
            expiryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            expiryLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            expiryLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])

        return row
    }

    /// Inline headline counters on the owner's own page, tapping through to
    /// the full Stats & Insights dashboard
    private func makeOwnerStatsStrip(_ stats: VenueOwnerStats, venue: PlaceVenue) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "\(stats.saves) saves · \(stats.visits) visits · \(stats.scans) scans"
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.adjustsFontSizeToFitWidth = true

        let statsLink = UILabel()
        statsLink.translatesAutoresizingMaskIntoConstraints = false
        statsLink.text = "View stats ›"
        statsLink.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        statsLink.textColor = Constants.Colors.primary
        statsLink.setContentHuggingPriority(.required, for: .horizontal)
        statsLink.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(label)
        row.addSubview(statsLink)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: statsLink.leadingAnchor, constant: -8),
            statsLink.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            statsLink.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        ])

        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(statsStripTapped)))
        return row
    }

    @objc private func statsStripTapped() {
        guard let venue = data?.venue else { return }
        delegate?.placeVenueViewDidTapStats(self, venue: venue)
    }

    /// One-tap compose from the page itself — fields on the page are already
    /// tap-to-edit for owners, so the row is just the paid broadcast actions
    /// (free owners get the upgrade teaser row instead).
    private func makeQuickActionsRow(_ venue: PlaceVenue, premium: Bool) -> UIView? {
        guard premium else { return nil }

        let announceButton = UIButton.smallActionButton(title: "📣 Announcement", style: .secondary)
        announceButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.placeVenueView(self, didTapQuickAction: .announcement, venue: venue)
        }, for: .touchUpInside)

        let offerButton = UIButton.smallActionButton(title: "🎁 New Offer", style: .secondary)
        offerButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.placeVenueView(self, didTapQuickAction: .offer, venue: venue)
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [announceButton, offerButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    /// Full-width owner CTA shown directly under the header
    private func makeManageStoreButton(_ venue: PlaceVenue) -> UIView {
        let button = UIButton.smallActionButton(title: "Manage Store", style: .primary)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.placeVenueViewDidTapManage(self, venue: venue)
        }, for: .touchUpInside)
        return button
    }

    /// Free-tier owner teaser: where announcements would appear, show what
    /// unlocks them. Tapping opens the Business paywall.
    private func makeUpgradeTeaserRow() -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "megaphone"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemGray2
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Post announcements & offers here"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Upgrade to Business to reach your savers and followers"
        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = Constants.Colors.primary
        subtitleLabel.numberOfLines = 0

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(subtitleLabel)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(upgradeTeaserTapped)))
        return row
    }

    @objc private func upgradeTeaserTapped() {
        delegate?.placeVenueViewDidTapUpgrade(self)
    }

    /// Owner shortcut: tapping a content row jumps straight into management
    private func attachManageTap(to row: UIView, venue: PlaceVenue) {
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(manageRowTapped)))
    }

    @objc private func manageRowTapped() {
        guard let venue = data?.venue else { return }
        delegate?.placeVenueViewDidTapManage(self, venue: venue)
    }

    private func makeOfferRow(_ offer: RewardOffer, venue: PlaceVenue, balance: Int, isOwner: Bool = false) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = offer.title
        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let costLabel = UILabel()
        costLabel.translatesAutoresizingMaskIntoConstraints = false
        costLabel.font = UIFont.systemFont(ofSize: 12)
        costLabel.textColor = .secondaryLabel

        // Owners see their offer's cost + a chevron into management, not a
        // Redeem button gated on their own point balance
        let trailingView: UIView
        if isOwner {
            costLabel.text = "\(offer.pointsCost) pts"
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.tintColor = .tertiaryLabel
            chevron.contentMode = .scaleAspectFit
            chevron.widthAnchor.constraint(equalToConstant: 14).isActive = true
            chevron.heightAnchor.constraint(equalToConstant: 14).isActive = true
            trailingView = chevron
            attachManageTap(to: row, venue: venue)
        } else {
            let affordable = balance >= offer.pointsCost
            costLabel.text = affordable
                ? "\(offer.pointsCost) pts"
                : "\(offer.pointsCost) pts · \(offer.pointsCost - balance) more needed"

            let redeemButton = UIButton.smallActionButton(
                title: "Redeem",
                style: affordable ? .primary : .secondary
            )
            redeemButton.isEnabled = affordable
            redeemButton.alpha = affordable ? 1.0 : 0.5
            redeemButton.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.placeVenueView(self, didTapRedeem: offer, venue: venue)
            }, for: .touchUpInside)
            trailingView = redeemButton
        }
        trailingView.setContentHuggingPriority(.required, for: .horizontal)
        trailingView.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(titleLabel)
        row.addSubview(costLabel)
        row.addSubview(trailingView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingView.leadingAnchor, constant: -10),

            costLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            costLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            costLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingView.leadingAnchor, constant: -10),
            costLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            trailingView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            trailingView.trailingAnchor.constraint(equalTo: row.trailingAnchor)
        ])

        return row
    }

    // MARK: - Ownership footer (exactly one state)

    private func makeOwnershipFooter(_ data: PlaceVenueData, venue: PlaceVenue) -> UIView? {
        // Owners never reach here — their CTA is the Manage Store button in
        // the header block (configure skips the footer when isOwner)
        guard let claim = data.claim, claim.canClaim else { return nil }
        return makeClaimStateRow(claim)
    }

    /// Card shown when the place has no rewards venue but can be claimed
    private func makeClaimOnlyFooter(_ claim: PlaceVenueClaim?) -> UIView? {
        guard let claim = claim, claim.canClaim || claim.myClaimStatus != nil else { return nil }
        return makeClaimStateRow(claim)
    }

    private func makeClaimStateRow(_ claim: PlaceVenueClaim) -> UIView {
        switch claim.myClaimStatus {
        case "pending":
            return makeFooterRow(text: "Your ownership claim is pending review", buttonTitle: nil, action: nil)
        case "approved":
            return makeFooterRow(text: "Your ownership claim was approved", buttonTitle: nil, action: nil)
        case "denied":
            return makeFooterRow(
                text: "Your ownership claim was declined",
                buttonTitle: "Request again"
            ) { [weak self] in
                guard let self = self else { return }
                self.delegate?.placeVenueViewDidTapClaim(self)
            }
        default:
            return makeFooterRow(
                text: "Is this your store?",
                buttonTitle: "Claim your store"
            ) { [weak self] in
                guard let self = self else { return }
                self.delegate?.placeVenueViewDidTapClaim(self)
            }
        }
    }

    private func makeFooterRow(text: String, buttonTitle: String?, action: (() -> Void)?) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2

        row.addSubview(label)

        var constraints = [
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ]

        if let buttonTitle = buttonTitle, let action = action {
            let button = UIButton.smallActionButton(title: buttonTitle, style: .primary)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            row.addSubview(button)
            constraints.append(contentsOf: [
                label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -10),
                button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor)
            ])
        } else {
            constraints.append(label.trailingAnchor.constraint(equalTo: row.trailingAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        return row
    }

    // MARK: - Storefront rows

    /// Reserve · Order · Catering · Book, as pills. nil when none are set.
    private func makeActionButtonsRow(_ actions: StorefrontActions) -> UIView? {
        let buttons = actions.buttons
        guard !buttons.isEmpty else { return nil }
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (index, button) in buttons.enumerated() {
            let b = UIButton.smallActionButton(title: button.title, style: index == 0 ? .primary : .secondary)
            b.setImage(UIImage(systemName: button.icon), for: .normal)
            b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            b.tag = index
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.placeVenueView(self, didTapStorefrontLink: button.url, title: button.title)
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        return row
    }

    /// Horizontal cards: photo, name, price. The thing that makes the page
    /// look like a real place rather than a listing.
    private func makeFeaturedStrip(_ items: [StorefrontFeaturedItem], label: String) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        let title = UILabel()
        title.text = "From the \(label.lowercased())"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabel
        container.addArrangedSubview(title)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let strip = UIStackView()
        strip.axis = .horizontal
        strip.spacing = 10
        strip.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(strip)
        let photoUrls = items.compactMap { $0.photoUrl }
        for item in items {
            let card = makeFeaturedCard(item)
            if let url = item.photoUrl, let index = photoUrls.firstIndex(of: url) {
                card.isUserInteractionEnabled = true
                card.addGestureRecognizer(FeaturedTap(target: self, action: #selector(featuredTapped(_:)), urls: photoUrls, index: index))
            }
            strip.addArrangedSubview(card)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            strip.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            strip.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 176)
        ])
        container.addArrangedSubview(scroll)
        return container
    }

    private func makeFeaturedCard(_ item: StorefrontFeaturedItem) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 10
        card.clipsToBounds = true
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.backgroundColor = .tertiarySystemFill
        if let url = item.photoUrl {
            ImageService.shared.loadImage(from: url) { loaded in
                DispatchQueue.main.async { image.image = loaded }
            }
        }
        let name = UILabel()
        name.translatesAutoresizingMaskIntoConstraints = false
        name.text = item.name
        name.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        name.textColor = .label
        name.numberOfLines = 2
        let price = UILabel()
        price.translatesAutoresizingMaskIntoConstraints = false
        price.text = [item.price, item.tags.first].compactMap { $0 }.joined(separator: " · ")
        price.font = UIFont.systemFont(ofSize: 12)
        price.textColor = .secondaryLabel
        price.numberOfLines = 1
        card.addSubview(image)
        card.addSubview(name)
        card.addSubview(price)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 150),
            image.topAnchor.constraint(equalTo: card.topAnchor),
            image.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            image.heightAnchor.constraint(equalToConstant: 110),
            name.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6),
            name.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            price.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            price.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            price.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            price.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }

    /// "See the full menu" — a link, or the owner's photos of the printed one.
    private func makeMenuRow(_ offerings: StorefrontOfferings, label: String) -> UIView? {
        let hasLink = !(offerings.link ?? "").isEmpty
        let photos = offerings.files.filter { $0.kind == "image" }.map(\.url)
        guard hasLink || !photos.isEmpty else { return nil }
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        if hasLink, let url = offerings.link {
            let b = UIButton.smallActionButton(title: "See the full \(label.lowercased())", style: .secondary)
            b.setImage(UIImage(systemName: "doc.text"), for: .normal)
            b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.placeVenueView(self, didTapStorefrontLink: url, title: label)
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        if !photos.isEmpty {
            let b = UIButton.smallActionButton(title: photos.count == 1 ? "\(label) photo" : "\(label) photos (\(photos.count))", style: .secondary)
            b.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
            b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.placeVenueView(self, didTapStorefrontPhotos: photos, startingAt: 0)
            }, for: .touchUpInside)
            row.addArrangedSubview(b)
        }
        return row
    }

    /// The owner's own photos, as a thumbnail strip.
    private func makeGalleryStrip(_ photos: [StorefrontGalleryPhoto]) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        let title = UILabel()
        title.text = "Photos from the owner"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabel
        container.addArrangedSubview(title)
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let strip = UIStackView()
        strip.axis = .horizontal
        strip.spacing = 6
        strip.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(strip)
        let urls = photos.map(\.url)
        for (index, photo) in photos.enumerated() {
            let iv = UIImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = 8
            iv.backgroundColor = .tertiarySystemFill
            iv.isUserInteractionEnabled = true
            iv.addGestureRecognizer(FeaturedTap(target: self, action: #selector(featuredTapped(_:)), urls: urls, index: index))
            ImageService.shared.loadImage(from: photo.url) { loaded in
                DispatchQueue.main.async { iv.image = loaded }
            }
            NSLayoutConstraint.activate([iv.widthAnchor.constraint(equalToConstant: 96), iv.heightAnchor.constraint(equalToConstant: 96)])
            strip.addArrangedSubview(iv)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            strip.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            strip.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 96)
        ])
        container.addArrangedSubview(scroll)
        return container
    }

    /// A tap that remembers which photo set it belongs to.
    private final class FeaturedTap: UITapGestureRecognizer {
        let urls: [String]
        let index: Int
        init(target: Any?, action: Selector?, urls: [String], index: Int) {
            self.urls = urls
            self.index = index
            super.init(target: target, action: action)
        }
    }

    @objc private func featuredTapped(_ tap: UITapGestureRecognizer) {
        guard let tap = tap as? FeaturedTap else { return }
        delegate?.placeVenueView(self, didTapStorefrontPhotos: tap.urls, startingAt: tap.index)
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return separator
    }
}

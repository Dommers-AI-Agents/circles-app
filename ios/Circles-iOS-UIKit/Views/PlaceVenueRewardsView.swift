import UIKit

protocol PlaceVenueRewardsViewDelegate: AnyObject {
    func placeVenueView(_ view: PlaceVenueRewardsView, didTapRedeem offer: RewardOffer, venue: PlaceVenue)
    func placeVenueViewDidTapClaim(_ view: PlaceVenueRewardsView)
    func placeVenueViewDidTapManage(_ view: PlaceVenueRewardsView, venue: PlaceVenue)
}

/// The rewards section of a place page: the venue's announcements and offers,
/// plus an ownership footer (claim / pending / manage). Collapses to zero
/// height when the place has no enrolled venue.
class PlaceVenueRewardsView: UIView {

    weak var delegate: PlaceVenueRewardsViewDelegate?

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
        let isOwner = data.isOwner == true
        layer.borderWidth = isOwner ? 1.5 : 0
        layer.borderColor = isOwner ? Constants.Colors.primary.withAlphaComponent(0.35).cgColor : nil

        containerStack.addArrangedSubview(makeHeader(venue, isOwner: isOwner))
        if isOwner {
            containerStack.addArrangedSubview(makeManageStoreButton(venue))
        }

        // Server filters expired announcements; re-filter as a stale-cache defense
        let announcements = (data.announcements ?? []).filter { !$0.isExpired }
        announcements.forEach { announcement in
            let row = makeAnnouncementRow(announcement)
            if isOwner { attachManageTap(to: row, venue: venue) }
            containerStack.addArrangedSubview(row)
        }

        let offers = data.offers ?? []
        if !offers.isEmpty && !announcements.isEmpty {
            containerStack.addArrangedSubview(makeSeparator())
        }
        offers.forEach { offer in
            containerStack.addArrangedSubview(
                makeOfferRow(offer, venue: venue, balance: data.balance ?? 0, isOwner: isOwner)
            )
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

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return separator
    }
}

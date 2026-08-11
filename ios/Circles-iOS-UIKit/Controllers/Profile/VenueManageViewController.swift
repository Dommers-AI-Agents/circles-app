import UIKit

/// Self-service venue management for store owners (and super-users): adjust
/// the points-per-purchase earn rate, add/edit/deactivate offers, and rotate
/// the register QR code. Reached from OwnerVenuesViewController or the
/// super-user VenueAdminViewController.
class VenueManageViewController: BaseViewController {

    // MARK: - Properties

    private let venueId: String
    private let venueName: String
    private var offers: [RewardOffer]
    private var announcements: [VenueAnnouncement]
    private var earnRate: Int
    private var registerCode: String
    private var contactName: String?
    private var contactEmail: String?
    private let windowCode: String
    private let windowStickerUrl: String?
    // Business-tier gate (offers/announcements/earn rate/register QR) —
    // per-venue: the subscription only covers the store it was bought for.
    // Seeded from the venue payload when present, otherwise optimistic to
    // avoid flashing locks; the server enforces regardless.
    private var ownerPremium: Bool

    private enum Section: Int, CaseIterable {
        case dashboard
        case businessInfo
        case windowQR
        case earnRate
        case offers
        case announcements
        case registerCode
        case codes
    }

    /// Free owner tier: everything else is business-tier (paywalled)
    private static let freeSections: Set<Section> = [.dashboard, .businessInfo, .windowQR]

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        return table
    }()

    // MARK: - Init

    init(venue: AdminVenue) {
        self.venueId = venue.venueId
        self.venueName = venue.venueName
        self.offers = venue.offers ?? []
        self.announcements = venue.announcements ?? []
        self.earnRate = venue.earnRate ?? 25
        self.registerCode = venue.registerCode
        self.contactName = venue.contactName
        self.contactEmail = venue.contactEmail
        self.windowCode = venue.windowCode
        self.windowStickerUrl = venue.windowStickerUrl
        self.venuePlaceId = venue.globalPlaceId ?? venue.googlePlaceId
        // Default LOCKED until the server confirms — an optimistic-true here
        // showed free owners unlocked tools that then 403'd on tap
        self.ownerPremium = venue.ownerPremium ?? false
        super.init(nibName: nil, bundle: nil)
    }

    /// Place identity for the "view public page" jump (globalPlaceId preferred)
    private let venuePlaceId: String?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = venueName
        view.backgroundColor = .systemBackground

        // Round trip to the public place page - the same page customers see
        if venuePlaceId != nil {
            let viewPageButton = UIBarButtonItem(
                image: UIImage(systemName: "eye"),
                style: .plain,
                target: self,
                action: #selector(viewPublicPageTapped)
            )
            viewPageButton.accessibilityLabel = "View public page"
            navigationItem.rightBarButtonItem = viewPageButton
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ManageCell")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshOwnerPremium()
    }

    // MARK: - Business gate

    private func refreshOwnerPremium() {
        RewardsService.shared.getRewardsProfile { [weak self] result in
            guard let self = self, case .success(let profile) = result else { return }
            if profile.isSuperUser {
                DispatchQueue.main.async { self.applyOwnerPremium(true) }
                return
            }
            // Per-venue: the subscription covers only the store it was bought
            // for, so ask for this venue's own flag rather than the account.
            RewardsService.shared.getMyVenues { [weak self] venuesResult in
                DispatchQueue.main.async {
                    guard let self = self, case .success(let venues) = venuesResult else { return }
                    let mine = venues.first { $0.venueId == self.venueId }
                    self.applyOwnerPremium(mine?.ownerPremium ?? false)
                }
            }
        }
    }

    private func applyOwnerPremium(_ premium: Bool) {
        if premium != ownerPremium {
            ownerPremium = premium
            tableView.reloadData()
        }
        // Header only on server confirmation — ownerPremium may start
        // optimistic, and neither state should flash before it's known.
        updateBusinessHeader(premium: premium)
    }

    private func presentOwnerPaywall() {
        let paywallVC = OwnerPaywallViewController()
        paywallVC.venueId = venueId
        paywallVC.onSubscribed = { [weak self] in
            // Server truth, not local optimism: the purchase path now awaits
            // the backend verify (and the backend busts its user cache), so
            // this refresh comes back premium — and if activation is still in
            // flight, the screen stays honest instead of unlocking rows that
            // would 403.
            self?.refreshOwnerPremium()
        }
        navigationController?.pushViewController(paywallVC, animated: true)
    }

    // MARK: - Business status header

    /// nil until the server has confirmed the venue's premium state
    private var businessHeaderState: Bool?

    /// Top-of-screen subscription feedback, server-confirmed only. Subscribed:
    /// a green "Business active" banner — otherwise the only signal owners get
    /// is the *absence* of locks, which is easy to miss. Not subscribed: the
    /// bold Business upsell; tapping it opens the paywall for this venue.
    private func updateBusinessHeader(premium: Bool) {
        guard businessHeaderState != premium else { return }
        businessHeaderState = premium

        let content: UIView
        if premium {
            content = makeBusinessActiveBanner()
        } else {
            let promo = BusinessUpsellBanner()
            promo.onTap = { [weak self] in self?.presentOwnerPaywall() }
            content = promo
        }

        let container = UIView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // tableHeaderView needs an explicit frame; size it for the current width
        let width = tableView.bounds.width
        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        container.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = container
    }

    private func makeBusinessActiveBanner() -> UIView {
        let banner = UIView()
        banner.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        banner.layer.cornerRadius = 10
        banner.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        icon.tintColor = .systemGreen
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "FavCircles Business active"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "This store's offers, announcements, loyalty, and full stats are unlocked."
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(icon)
        banner.addSubview(titleLabel)
        banner.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
        ])
        return banner
    }

    // MARK: - Public page

    @objc private func viewPublicPageTapped() {
        guard let placeId = venuePlaceId else { return }
        let loading = AlertPresenter.showLoading(message: "Loading...", from: self)
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let place):
                        let placeVC = PlaceDetailViewController(place: place)
                        self.navigationController?.pushViewController(placeVC, animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    // MARK: - Earn rate

    private func editEarnRate() {
        showTextInput(
            title: "Points per purchase",
            message: "How many points customers earn each time they scan your register card after buying something.",
            placeholder: "e.g. 25",
            initialText: "\(earnRate)",
            keyboardType: .numberPad
        ) { [weak self] value in
            guard let self = self,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let rate = Int(value), rate > 0 else { return }

            let loading = AlertPresenter.showLoading(message: "Updating...", from: self)
            RewardsService.shared.updateEarnRate(venueId: self.venueId, earnRate: rate) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success(let newRate):
                            self.earnRate = newRate
                            self.tableView.reloadData()
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offers

    private func addOffer() {
        showTextInput(
            title: "New Offer",
            message: "What does the customer get? (e.g. \"Free coffee\", \"10% off\")",
            placeholder: "Offer title"
        ) { [weak self] title in
            guard let self = self,
                  let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return }

            self.showTextInput(
                title: "Point Cost",
                message: "How many points does \"\(title)\" cost?",
                placeholder: "e.g. 250",
                keyboardType: .numberPad
            ) { [weak self] cost in
                guard let self = self,
                      let cost = cost?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let pointsCost = Int(cost), pointsCost > 0 else { return }

                let loading = AlertPresenter.showLoading(message: "Adding offer...", from: self)
                RewardsService.shared.addOffer(venueId: self.venueId, title: title, pointsCost: pointsCost) { [weak self] result in
                    DispatchQueue.main.async {
                        loading.dismiss(animated: true) {
                            guard let self = self else { return }
                            switch result {
                            case .success(let offers):
                                self.offers = offers
                                self.tableView.reloadData()
                            case .failure(let error):
                                self.showError(error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func manageOffer(_ offer: RewardOffer) {
        let isActive = offer.active != false
        showActionSheet(
            title: offer.title,
            message: "\(offer.pointsCost) points · \(isActive ? "active" : "inactive")",
            actions: [
                (title: "Edit title", style: .default, handler: { [weak self] in
                    self?.editOfferTitle(offer)
                }),
                (title: "Edit point cost", style: .default, handler: { [weak self] in
                    self?.editOfferCost(offer)
                }),
                (title: isActive ? "Deactivate" : "Activate", style: isActive ? .destructive : .default, handler: { [weak self] in
                    self?.updateOffer(offer, active: !isActive)
                })
            ]
        )
    }

    private func editOfferTitle(_ offer: RewardOffer) {
        showTextInput(title: "Edit Offer", placeholder: "Offer title", initialText: offer.title) { [weak self] title in
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            self?.updateOffer(offer, title: title)
        }
    }

    private func editOfferCost(_ offer: RewardOffer) {
        showTextInput(
            title: "Edit Point Cost",
            message: "How many points does \"\(offer.title)\" cost?",
            initialText: "\(offer.pointsCost)",
            keyboardType: .numberPad
        ) { [weak self] cost in
            guard let cost = cost?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let pointsCost = Int(cost), pointsCost > 0 else { return }
            self?.updateOffer(offer, pointsCost: pointsCost)
        }
    }

    private func updateOffer(_ offer: RewardOffer, title: String? = nil, pointsCost: Int? = nil, active: Bool? = nil) {
        let loading = AlertPresenter.showLoading(message: "Updating offer...", from: self)
        RewardsService.shared.updateOffer(
            venueId: venueId,
            offerId: offer.offerId,
            title: title,
            pointsCost: pointsCost,
            active: active
        ) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let offers):
                        self.offers = offers
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    // MARK: - Announcements

    private func addAnnouncement() {
        showTextInput(
            title: "New Announcement",
            message: "A short headline shown on your place's page (e.g. \"Happy Hour\", \"Live Music Friday\")",
            placeholder: "Headline"
        ) { [weak self] title in
            guard let self = self,
                  let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return }

            self.showTextInput(
                title: "Message",
                message: "The details visitors see under \"\(title)\"",
                placeholder: "e.g. 2-for-1 drinks, 3–5pm weekdays"
            ) { [weak self] message in
                guard let self = self,
                      let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !message.isEmpty else { return }

                self.pickExpiry(title: "When should it expire?") { [weak self] expiresAt, _ in
                    guard let self = self else { return }
                    let loading = AlertPresenter.showLoading(message: "Posting...", from: self)
                    RewardsService.shared.addAnnouncement(
                        venueId: self.venueId,
                        title: title,
                        message: message,
                        expiresAt: expiresAt
                    ) { [weak self] result in
                        self?.handleAnnouncementsResult(result, loading: loading)
                    }
                }
            }
        }
    }

    private func manageAnnouncement(_ announcement: VenueAnnouncement) {
        showActionSheet(
            title: announcement.title,
            message: announcement.message,
            actions: [
                (title: "Edit headline", style: .default, handler: { [weak self] in
                    self?.editAnnouncementTitle(announcement)
                }),
                (title: "Edit message", style: .default, handler: { [weak self] in
                    self?.editAnnouncementMessage(announcement)
                }),
                (title: "Change expiry", style: .default, handler: { [weak self] in
                    self?.changeAnnouncementExpiry(announcement)
                }),
                (title: "Delete", style: .destructive, handler: { [weak self] in
                    self?.confirmDeleteAnnouncement(announcement)
                })
            ]
        )
    }

    private func editAnnouncementTitle(_ announcement: VenueAnnouncement) {
        showTextInput(title: "Edit Headline", placeholder: "Headline", initialText: announcement.title) { [weak self] title in
            guard let self = self,
                  let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            let loading = AlertPresenter.showLoading(message: "Updating...", from: self)
            RewardsService.shared.updateAnnouncement(
                venueId: self.venueId,
                announcementId: announcement.announcementId,
                title: title
            ) { [weak self] result in
                self?.handleAnnouncementsResult(result, loading: loading)
            }
        }
    }

    private func editAnnouncementMessage(_ announcement: VenueAnnouncement) {
        showTextInput(title: "Edit Message", placeholder: "Message", initialText: announcement.message) { [weak self] message in
            guard let self = self,
                  let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else { return }
            let loading = AlertPresenter.showLoading(message: "Updating...", from: self)
            RewardsService.shared.updateAnnouncement(
                venueId: self.venueId,
                announcementId: announcement.announcementId,
                message: message
            ) { [weak self] result in
                self?.handleAnnouncementsResult(result, loading: loading)
            }
        }
    }

    private func changeAnnouncementExpiry(_ announcement: VenueAnnouncement) {
        pickExpiry(title: "New expiry") { [weak self] expiresAt, clearExpiry in
            guard let self = self else { return }
            let loading = AlertPresenter.showLoading(message: "Updating...", from: self)
            RewardsService.shared.updateAnnouncement(
                venueId: self.venueId,
                announcementId: announcement.announcementId,
                expiresAt: expiresAt,
                clearExpiry: clearExpiry
            ) { [weak self] result in
                self?.handleAnnouncementsResult(result, loading: loading)
            }
        }
    }

    private func confirmDeleteAnnouncement(_ announcement: VenueAnnouncement) {
        showConfirmation(
            title: "Delete \"\(announcement.title)\"?",
            message: "It disappears from your place's page immediately.",
            confirmTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self = self else { return }
            let loading = AlertPresenter.showLoading(message: "Deleting...", from: self)
            RewardsService.shared.deleteAnnouncement(
                venueId: self.venueId,
                announcementId: announcement.announcementId
            ) { [weak self] result in
                self?.handleAnnouncementsResult(result, loading: loading)
            }
        }
    }

    /// Expiry picker shared by add/change flows. Calls back with an ISO8601
    /// string (or nil for no expiry) plus a clear-expiry flag for updates.
    private func pickExpiry(title: String, completion: @escaping (String?, Bool) -> Void) {
        let iso = ISO8601DateFormatter()
        let fromNow: (TimeInterval) -> String = { iso.string(from: Date().addingTimeInterval($0)) }

        showActionSheet(
            title: title,
            message: "Expired announcements hide automatically.",
            actions: [
                (title: "No expiry", style: .default, handler: { completion(nil, true) }),
                (title: "1 day", style: .default, handler: { completion(fromNow(24 * 60 * 60), false) }),
                (title: "1 week", style: .default, handler: { completion(fromNow(7 * 24 * 60 * 60), false) }),
                (title: "1 month", style: .default, handler: { completion(fromNow(30 * 24 * 60 * 60), false) }),
                (title: "Custom date...", style: .default, handler: { [weak self] in
                    self?.pickCustomExpiry(completion: completion)
                })
            ]
        )
    }

    private func pickCustomExpiry(completion: @escaping (String?, Bool) -> Void) {
        showTextInput(
            title: "Expiry Date",
            message: "The announcement stays up through this day (YYYY-MM-DD).",
            placeholder: "2026-08-01"
        ) { [weak self] value in
            guard let self = self,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.timeZone = .current
            guard let day = parser.date(from: value) else {
                self.showError("Enter the date as YYYY-MM-DD (e.g. 2026-08-01).")
                return
            }
            // End of the chosen day, so "through this day" means what it says
            let endOfDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: day)) ?? day
            guard endOfDay > Date() else {
                self.showError("The expiry date must be in the future.")
                return
            }
            completion(ISO8601DateFormatter().string(from: endOfDay), false)
        }
    }

    private func handleAnnouncementsResult(_ result: Result<[VenueAnnouncement], Error>, loading: UIAlertController) {
        DispatchQueue.main.async {
            loading.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let announcements):
                    self.announcements = announcements
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Business info (free tier)

    private func editContactName() {
        showTextInput(
            title: "Contact Name",
            message: "Who should FavCircles reach about this venue?",
            placeholder: "Name",
            initialText: contactName
        ) { [weak self] value in
            guard let self = self,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.saveVenueInfo(contactName: value, contactEmail: nil)
        }
    }

    private func editContactEmail() {
        showTextInput(
            title: "Contact Email",
            message: "Monthly reports and printable QR codes are sent here.",
            placeholder: "you@business.com",
            initialText: contactEmail,
            keyboardType: .emailAddress
        ) { [weak self] value in
            guard let self = self,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            self.saveVenueInfo(contactName: nil, contactEmail: value)
        }
    }

    private func saveVenueInfo(contactName: String?, contactEmail: String?) {
        let loading = AlertPresenter.showLoading(message: "Saving...", from: self)
        RewardsService.shared.updateVenueInfo(
            venueId: venueId,
            contactName: contactName,
            contactEmail: contactEmail
        ) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let venue):
                        self.contactName = venue.contactName
                        self.contactEmail = venue.contactEmail
                        self.tableView.reloadData()
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    // MARK: - Window QR (free tier)

    private func showWindowQR() {
        // Fall back to the documented sticker link shape when an older
        // my-venues payload has no explicit URL
        let url = windowStickerUrl ?? "\(ShareLinks.base)/s/\(windowCode)"
        let qrVC = VenueQRViewController(venueName: venueName, stickerUrl: url)
        navigationController?.pushViewController(qrVC, animated: true)
    }

    // MARK: - Register QR

    private func rotateRegisterCode() {
        showTextInput(
            title: "Generate New Register QR",
            message: "Your current printed register card stops working IMMEDIATELY once the new code is generated. Set the points customers earn per purchase with the new card:",
            initialText: "\(earnRate)",
            keyboardType: .numberPad
        ) { [weak self] value in
            guard let self = self else { return }
            let rate = Int(value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")

            self.showConfirmation(
                title: "Replace register QR?",
                message: "The old card becomes invalid the moment the new code is created. Print and display the new one right away.",
                confirmTitle: "Generate",
                isDestructive: true
            ) { [weak self] in
                self?.performRotation(earnRate: rate)
            }
        }
    }

    private func performRotation(earnRate: Int?) {
        let loading = AlertPresenter.showLoading(message: "Generating new code...", from: self)
        RewardsService.shared.rotateRegisterCode(venueId: venueId, earnRate: earnRate) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let rotated):
                        self.registerCode = rotated.registerCode
                        self.earnRate = rotated.earnRate
                        self.tableView.reloadData()
                        self.showConfirmation(
                            title: "New register code: \(rotated.registerCode)",
                            message: "Email the printable QR codes to yourself now?",
                            confirmTitle: "Email me the QR"
                        ) { [weak self] in
                            self?.emailQR()
                        }
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func emailQR() {
        let loading = AlertPresenter.showLoading(message: "Sending QR codes...", from: self)
        RewardsService.shared.emailVenueQR(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let email):
                        AlertPresenter.showSuccess("QR codes sent to \(email)", from: self)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension VenueManageViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    /// Header title + the plain-language explanation behind its ⓘ button.
    /// Every tool here gets one — store owners shouldn't have to guess what
    /// anything is for.
    private func headerInfo(for section: Section) -> (title: String, explanation: String) {
        switch section {
        case .dashboard:
            return ("Dashboard",
                    "Your store's numbers: how many people saved your place, follow it, and scan your QR codes. Headline stats are free; detailed monthly trends come with FavCircles Business.")
        case .businessInfo:
            return ("Business info",
                    "How FavCircles reaches you about this venue, plus a link to your public place page. Monthly reports and printable QR codes go to the contact email.")
        case .windowQR:
            return ("Scan-to-save QR",
                    "Print this code and put it in your window. Customers scan it to save your place in FavCircles and start earning points. Free for every venue.")
        case .earnRate:
            return ("Points per purchase",
                    "How many points a customer earns each time they scan your register card after buying something (limited to once per day per customer).")
        case .offers:
            return ("Offers for points",
                    "Rewards customers can redeem with the points they earn at your store — for example \"Free coffee — 100 points\". The customer taps Redeem at your counter and shows you the confirmation screen; you hand over the reward.")
        case .announcements:
            return ("Announcements",
                    "Short updates shown on your place's page and in your followers' feeds — deals, happy hours, events. Expired announcements hide automatically.")
        case .registerCode:
            return ("Register QR card",
                    "The QR card you keep at the register. Customers scan it after a purchase to collect their points. Rotating it invalidates the old printed card — do this if a code leaks or is being abused.")
        case .codes:
            return ("Loyalty codes",
                    "Single-use codes worth loyalty points. Pack one into every shipped order or hand them out at your conference booth — customers redeem them in the app and become followers of your store.")
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let info = headerInfo(for: Section(rawValue: section)!)

        let header = UIView()

        let label = UILabel()
        label.text = info.title.uppercased()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        let infoButton = UIButton(type: .detailDisclosure)
        infoButton.tintColor = Constants.Colors.primary
        infoButton.tag = section
        infoButton.addTarget(self, action: #selector(sectionInfoTapped(_:)), for: .touchUpInside)
        infoButton.accessibilityLabel = "About \(info.title)"
        infoButton.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(label)
        header.addSubview(infoButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6),
            label.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor, constant: 6),

            infoButton.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            infoButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 2),
            infoButton.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -16)
        ])
        return header
    }

    @objc private func sectionInfoTapped(_ sender: UIButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        let info = headerInfo(for: section)
        AlertPresenter.showInfo(title: info.title, message: info.explanation, from: self)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .dashboard:
            return nil
        case .businessInfo:
            return "Where FavCircles reaches you about your venue. Monthly reports and printable QR codes go to the contact email."
        case .windowQR:
            return "Free for every venue: customers scan this in your window (or from your phone) to save your place and start earning points."
        case .earnRate:
            return "Customers earn these points each time they scan your register card after a purchase (once per day)."
        case .offers:
            return "Offers are what customers redeem their points for at your counter."
        case .announcements:
            return "Announcements show on your place's page to everyone — deals, happy hours, events. Expired ones hide automatically."
        case .registerCode:
            return "Generating a new QR immediately invalidates the old printed card — useful if a code leaks."
        case .codes:
            return "Mint a batch, share the list to your printer, and pack one code into every order."
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .dashboard: return 1
        case .businessInfo: return venuePlaceId != nil ? 3 : 2 // place page + contact name + contact email
        case .windowQR: return 2 // show QR + email QR codes
        case .earnRate: return 1
        case .offers: return offers.count + 1 // + "Add offer" row
        case .announcements: return announcements.count + 1 // + "Add announcement" row
        case .registerCode: return 1 // rotate
        case .codes: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ManageCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none

        switch Section(rawValue: indexPath.section)! {
        case .dashboard:
            config.text = "Stats & Insights"
            config.secondaryText = "Saves, followers, visits, redemptions"
            config.image = UIImage(systemName: "chart.bar.fill")
            config.imageProperties.tintColor = Constants.Colors.primary
            cell.accessoryType = .disclosureIndicator

        case .businessInfo:
            let contactRow = indexPath.row - (venuePlaceId != nil ? 1 : 0)
            if contactRow < 0 {
                config.text = "Your place page"
                config.secondaryText = "View and update your public listing"
                config.image = UIImage(systemName: "storefront")
            } else if contactRow == 0 {
                config.text = "Contact name"
                config.secondaryText = contactName?.isEmpty == false ? contactName : "Add your name"
                config.image = UIImage(systemName: "person.crop.circle")
            } else {
                config.text = "Contact email"
                config.secondaryText = contactEmail?.isEmpty == false ? contactEmail : "Add an email"
                config.image = UIImage(systemName: "envelope.badge")
            }
            config.imageProperties.tintColor = Constants.Colors.primary
            cell.accessoryType = .disclosureIndicator

        case .windowQR:
            if indexPath.row == 0 {
                config.text = "Show scan-to-save QR"
                config.secondaryText = "Display or share your window sticker"
                config.image = UIImage(systemName: "qrcode.viewfinder")
                cell.accessoryType = .disclosureIndicator
            } else {
                config.text = "Email QR codes to me"
                config.secondaryText = "Printable window + register stickers"
                config.image = UIImage(systemName: "envelope")
            }
            config.imageProperties.tintColor = Constants.Colors.primary

        case .earnRate:
            config.text = "\(earnRate) points"
            config.secondaryText = "Tap to change"
            config.image = UIImage(systemName: "dollarsign.circle")
            config.imageProperties.tintColor = Constants.Colors.primary

        case .offers:
            if indexPath.row < offers.count {
                let offer = offers[indexPath.row]
                let isActive = offer.active != false
                config.text = offer.title
                config.secondaryText = "\(offer.pointsCost) pts\(isActive ? "" : " · inactive")"
                config.textProperties.color = isActive ? .label : .secondaryLabel
                config.image = UIImage(systemName: isActive ? "gift" : "gift.fill")
                config.imageProperties.tintColor = isActive ? Constants.Colors.primary : .systemGray3
                cell.accessoryType = .disclosureIndicator
            } else {
                config.text = "Add offer"
                config.textProperties.color = Constants.Colors.primary
                config.image = UIImage(systemName: "plus.circle")
                config.imageProperties.tintColor = Constants.Colors.primary
            }

        case .announcements:
            if indexPath.row < announcements.count {
                let announcement = announcements[indexPath.row]
                let expired = announcement.isExpired
                var detail = announcement.message
                if let expiry = announcement.expiryDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none
                    detail += expired
                        ? " · expired \(formatter.string(from: expiry))"
                        : " · until \(formatter.string(from: expiry))"
                }
                config.text = announcement.title
                config.secondaryText = detail
                config.textProperties.color = expired ? .secondaryLabel : .label
                config.image = UIImage(systemName: expired ? "megaphone" : "megaphone.fill")
                config.imageProperties.tintColor = expired ? .systemGray3 : .systemOrange
                cell.accessoryType = .disclosureIndicator
            } else {
                config.text = "Add announcement"
                config.textProperties.color = Constants.Colors.primary
                config.image = UIImage(systemName: "plus.circle")
                config.imageProperties.tintColor = Constants.Colors.primary
            }

        case .registerCode:
            config.text = "Generate new register QR"
            config.secondaryText = "Current code: \(registerCode)"
            config.image = UIImage(systemName: "qrcode")
            config.imageProperties.tintColor = Constants.Colors.primary

        case .codes:
            config.text = "Loyalty codes"
            config.secondaryText = "Order-box cards & booth handouts"
            config.image = UIImage(systemName: "ticket")
            config.imageProperties.tintColor = Constants.Colors.primary
            cell.accessoryType = .disclosureIndicator
        }

        // Business-tier tools show a lock for free owners
        if !ownerPremium && !Self.freeSections.contains(Section(rawValue: indexPath.section)!) {
            let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
            lock.tintColor = .systemGray2
            cell.accessoryView = lock
        } else {
            cell.accessoryView = nil
        }

        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = Section(rawValue: indexPath.section)!

        // Free owners get the paywall for any business-tier tool
        if !ownerPremium && !Self.freeSections.contains(section) {
            presentOwnerPaywall()
            return
        }

        switch section {
        case .dashboard:
            let dashboardVC = VenueDashboardViewController(venueId: venueId, venueName: venueName)
            navigationController?.pushViewController(dashboardVC, animated: true)
        case .earnRate:
            editEarnRate()
        case .offers:
            if indexPath.row < offers.count {
                manageOffer(offers[indexPath.row])
            } else {
                addOffer()
            }
        case .announcements:
            if indexPath.row < announcements.count {
                manageAnnouncement(announcements[indexPath.row])
            } else {
                addAnnouncement()
            }
        case .businessInfo:
            let contactRow = indexPath.row - (venuePlaceId != nil ? 1 : 0)
            if contactRow < 0 {
                viewPublicPageTapped()
            } else if contactRow == 0 {
                editContactName()
            } else {
                editContactEmail()
            }
        case .windowQR:
            if indexPath.row == 0 {
                showWindowQR()
            } else {
                emailQR()
            }
        case .registerCode:
            rotateRegisterCode()
        case .codes:
            let codesVC = VenueCodesViewController(venueId: venueId, venueName: venueName)
            navigationController?.pushViewController(codesVC, animated: true)
        }
    }
}

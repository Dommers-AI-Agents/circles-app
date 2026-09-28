import UIKit

/// The store owner's page for one store (managers and super-users see it too),
/// grouped the way an owner thinks: at a glance, the place page, the loyalty
/// program, announcements, the window sticker, owner & team, help. Which rows
/// show and which need Business lives in VenueManageLayout; the copy in
/// VenueManageCopy. Reached from OwnerVenuesViewController, the place page and
/// the super-user store page.
class VenueManageViewController: BaseViewController {

    // MARK: - Properties

    // Internal: the place page pops back to an existing manage screen for the
    // same venue instead of pushing a duplicate
    let venueId: String

    /// Compose flow to fire as soon as the screen appears — set by the place
    /// page's inline "📣 Announcement" / "🎁 New Offer" quick actions
    enum QuickAction {
        case addAnnouncement
        case addOffer
    }
    var pendingQuickAction: QuickAction?
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
    private var managerCount: Int = 0
    private let stats: AdminVenueStats?
    /// Online-only brand store: no window sticker, register card, hours or cover
    private let isVirtual: Bool
    /// Summary line for the hours row, once the place has been read
    private var hoursSummary: String?

    private typealias Row = VenueManageLayout.Row

    /// Rebuilt on every reload so offers/announcements added in place show up
    private var layout: [(section: VenueManageLayout.Section, rows: [Row])] = []

    private func rebuildLayout() {
        layout = VenueManageLayout.sections(.init(
            isVirtual: isVirtual,
            hasPlace: venuePlaceId != nil,
            hasStats: stats != nil,
            offerCount: offers.count,
            announcementCount: announcements.count
        ))
    }

    private func reload() {
        rebuildLayout()
        tableView.reloadData()
    }

    // MARK: - Storefront (menu, buttons, photos)

    /// Loaded once on appear; the editors hand back the saved copy.
    private var storefront: VenueStorefront?

    private func loadStorefront() {
        RewardsService.shared.fetchStorefront(venueId: venueId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let storefront) = result else { return }
                self.storefront = storefront
                self.reload()
            }
        }
    }

    private func openStorefrontRow(_ row: Row) {
        let onSaved: (VenueStorefront) -> Void = { [weak self] saved in
            self?.storefront = saved
            self?.reload()
        }
        switch row {
        case .storefrontButtons:
            let vc = VenueStorefrontActionsViewController(venueId: venueId, actions: storefront?.actions)
            vc.onSaved = onSaved
            navigationController?.pushViewController(vc, animated: true)
        case .menu:
            let vc = VenueStorefrontOfferingsViewController(venueId: venueId, label: storefront?.offeringsLabel ?? "Menu", offerings: storefront?.offerings)
            vc.onSaved = onSaved
            navigationController?.pushViewController(vc, animated: true)
        case .gallery:
            let vc = VenueStorefrontGalleryViewController(venueId: venueId, photos: storefront?.gallery ?? [])
            vc.onSaved = onSaved
            navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }

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
        self.managerCount = venue.managerUserIds?.count ?? 0
        self.stats = venue.stats
        self.isVirtual = venue.isVirtual == true
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let action = pendingQuickAction {
            pendingQuickAction = nil
            switch action {
            case .addAnnouncement: addAnnouncement()
            case .addOffer: addOffer()
            }
        }
    }

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
        tableView.register(StatGridCell.self, forCellReuseIdentifier: StatGridCell.reuseId)
        rebuildLayout()

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshOwnerPremium()
        loadStorefront()
        loadHoursSummary()
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
        ownerPremium = premium
        // Header only on server confirmation — ownerPremium may start
        // optimistic, and neither state should flash before it's known.
        updateBusinessHeader(premium: premium)
        // The plan row reads the confirmed state, so reload either way
        reload()
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
                            self.reload()
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offers & announcements

    private func addOffer() { openOfferForm(nil) }
    private func manageOffer(_ offer: RewardOffer) { openOfferForm(offer) }

    private func openOfferForm(_ offer: RewardOffer?) {
        let form = VenueOfferFormViewController(venueId: venueId, earnRate: earnRate, offer: offer)
        form.onSaved = { [weak self] offers in
            self?.offers = offers
            self?.reload()
        }
        navigationController?.pushViewController(form, animated: true)
    }

    private func addAnnouncement() { openAnnouncementForm(nil) }
    private func manageAnnouncement(_ announcement: VenueAnnouncement) { openAnnouncementForm(announcement) }

    private func openAnnouncementForm(_ announcement: VenueAnnouncement?) {
        let form = VenueAnnouncementFormViewController(venueId: venueId, announcement: announcement)
        form.onSaved = { [weak self] announcements in
            self?.announcements = announcements
            self?.reload()
        }
        navigationController?.pushViewController(form, animated: true)
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
                        self.reload()
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
                        self.reload()
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

    // MARK: - Place page: hours & cover photo

    private func loadHoursSummary() {
        guard let placeId = venuePlaceId, !isVirtual else { return }
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let response) = result else { return }
                self.applyHoursSummary(response.globalPlace.googleData?.openingHours)
            }
        }
    }

    private func applyHoursSummary(_ hours: [OpeningHour]?) {
        let draft = VenueHoursDraft(hours: hours)
        let openDays = draft.days.filter { !$0.isClosed }.count
        hoursSummary = (hours ?? []).isEmpty
            ? "Add your hours so customers know when to come"
            : "Open \(openDays) day\(openDays == 1 ? "" : "s") a week"
        reload()
    }

    private func openHours() {
        guard let placeId = venuePlaceId else { return }
        let hoursVC = VenueHoursViewController(venueId: venueId, placeId: placeId)
        hoursVC.onSaved = { [weak self] hours in
            self?.applyHoursSummary(hours)
            self?.showSuccess("Hours updated on your place page")
        }
        navigationController?.pushViewController(hoursVC, animated: true)
    }

    /// Same flow as the place page's owner menu: pick which photo leads the page
    private func openCoverPhoto() {
        guard let placeId = venuePlaceId else { return }
        let loading = AlertPresenter.showLoading(message: "Loading photos...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.globalPlace
                        let urls = (place.photos ?? []).map(\.url)
                        guard !urls.isEmpty else {
                            AlertPresenter.showError(
                                title: "No Photos Yet",
                                message: "Add photos to your place first — then pick which one leads the page.",
                                from: self
                            )
                            return
                        }
                        let picker = CoverPhotoPickerViewController(photoUrls: urls, currentCoverUrl: place.coverPhotoUrl)
                        picker.onSelect = { [weak self] url in self?.saveCoverPhoto(url) }
                        self.present(UINavigationController(rootViewController: picker), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func saveCoverPhoto(_ url: String?) {
        RewardsService.shared.setVenueCoverPhoto(venueId: venueId, url: url) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.showSuccess("Cover photo updated")
                case .failure(let error): self?.showError(error)
                }
            }
        }
    }

    // MARK: - Register card

    private func showRegisterCard() {
        let qrVC = VenueQRViewController(
            venueName: venueName,
            stickerUrl: "\(ShareLinks.base)/s/\(registerCode)",
            screenTitle: "Register Card QR",
            caption: VenueAdminCopy.registerCardExplanation(earnRate: earnRate, loyaltyActive: ownerPremium)
        )
        navigationController?.pushViewController(qrVC, animated: true)
    }

    // MARK: - Plan & more

    private func openPlan() {
        if businessHeaderState == true {
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                UIApplication.shared.open(url)
            }
        } else {
            presentOwnerPaywall()
        }
    }

    private func openOwnerGuide() {
        guard let topic = HelpContentProvider.shared.topic(withId: "store-video-tutorial") else { return }
        navigationController?.pushViewController(HelpTopicViewController(topic: topic), animated: true)
    }

    private func openBrandStorefront() {
        guard let userId = AuthService.shared.getUserId() else { return }
        RewardsService.shared.getStorefront(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let editor = StorefrontEditViewController()
                if case .success(let data) = result {
                    editor.initialStorefront = data.storefront
                    editor.initialFindUsAtCircleId = nil
                }
                self.navigationController?.pushViewController(editor, animated: true)
            }
        }
    }

    private func openManagers() {
        let managersVC = VenueManagersViewController(venueId: venueId, venueName: venueName)
        managersVC.onManagersChanged = { [weak self] count in
            self?.managerCount = count
            self?.reload()
        }
        navigationController?.pushViewController(managersVC, animated: true)
    }
}



// MARK: - UITableViewDataSource / Delegate

extension VenueManageViewController: UITableViewDataSource, UITableViewDelegate {

    private func row(at indexPath: IndexPath) -> Row? {
        guard layout.indices.contains(indexPath.section) else { return nil }
        let rows = layout[indexPath.section].rows
        return rows.indices.contains(indexPath.row) ? rows[indexPath.row] : nil
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        layout.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        layout[section].rows.count
    }

    /// Uppercase title plus an ⓘ that explains the group in plain words —
    /// store owners shouldn't have to guess what anything is for.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let info = VenueManageCopy.header(layout[section].section, isVirtual: isVirtual)

        let header = UIView()

        let label = UILabel()
        label.text = info.title.uppercased()
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
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
        guard layout.indices.contains(sender.tag) else { return }
        let info = VenueManageCopy.header(layout[sender.tag].section, isVirtual: isVirtual)
        AlertPresenter.showInfo(title: info.title, message: info.explanation, from: self)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        VenueManageCopy.footer(layout[section].section, isVirtual: isVirtual)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }

        if row == .statTiles {
            let cell = tableView.dequeueReusableCell(withIdentifier: StatGridCell.reuseId, for: indexPath) as! StatGridCell
            if let stats = stats {
                cell.configure(tiles: VenueManageCopy.statTiles(stats))
            }
            cell.selectionStyle = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ManageCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.imageProperties.tintColor = Constants.Colors.primary
        cell.accessoryType = .disclosureIndicator
        describe(row, into: &config)

        // Business-tier tools show a lock for free owners
        if !ownerPremium && VenueManageLayout.isBusiness(row) {
            let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
            lock.tintColor = .systemGray2
            cell.accessoryView = lock
        } else {
            cell.accessoryView = nil
        }

        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
        cell.contentConfiguration = config
        return cell
    }

    /// Title, detail and symbol for one row
    private func describe(_ row: Row, into config: inout UIListContentConfiguration) {
        func set(_ text: String, _ detail: String?, _ symbol: String) {
            config.text = text
            config.secondaryText = detail
            config.image = UIImage(systemName: symbol)
        }
        func addRow(_ text: String) {
            set(text, nil, "plus.circle.fill")
            config.textProperties.color = Constants.Colors.primary
        }

        switch row {
        case .statTiles:
            break
        case .fullStats:
            set("Stats & Insights", "Monthly trends for saves, visits and redemptions", "chart.bar.fill")
        case .savers:
            set("Who saved your place", "The people with you in their circles", "bookmark.fill")
        case .followers:
            set("Followers", "People who get your announcements", "person.2.fill")
        case .activity:
            set("Visits & redemptions", "Every check-in and reward, newest first", "list.bullet.rectangle")

        case .viewPage:
            set("View your place page", "Exactly what customers see", "eye")
        case .hours:
            set("Opening hours", hoursSummary ?? "Set the hours shown on your page", "clock")
        case .coverPhoto:
            set("Cover photo", "Choose the photo that leads your page", "photo")
        case .storefrontButtons:
            let count = storefront?.actions?.buttons.count ?? 0
            set("Reserve · Order · Catering · Book",
                count > 0 ? "\(count) button\(count == 1 ? "" : "s") on your page" : "Add the links customers tap to spend money",
                "hand.tap")
        case .menu:
            let label = storefront?.offeringsLabel ?? "Menu"
            let o = storefront?.offerings
            var parts: [String] = []
            if let featured = o?.featured.count, featured > 0 { parts.append("\(featured) featured") }
            if let pages = o?.files.count, pages > 0 { parts.append("\(pages) photo\(pages == 1 ? "" : "s")") }
            if !(o?.link ?? "").isEmpty { parts.append("link") }
            set("\(label) & featured items",
                parts.isEmpty ? "A link or photos of your \(label.lowercased()), plus a few items with a picture and a price" : parts.joined(separator: " · "),
                "menucard")
        case .gallery:
            let count = storefront?.gallery.count ?? 0
            set("Your photos",
                count > 0 ? "\(count) photo\(count == 1 ? "" : "s") — yours, not Google's" : "Food, the room, the team. Yours, not Google's.",
                "photo.on.rectangle.angled")

        case .earnRate:
            set("Points per purchase", "\(earnRate) points each time a customer scans", "dollarsign.circle")
        case .offer(let index):
            let offer = offers[index]
            let isActive = offer.active != false
            set(offer.title, "\(offer.pointsCost) points\(isActive ? "" : " · paused")", isActive ? "gift" : "gift.fill")
            config.textProperties.color = isActive ? .label : .secondaryLabel
            config.imageProperties.tintColor = isActive ? Constants.Colors.primary : .systemGray3
        case .addOffer:
            addRow("Add an offer")
        case .showRegisterCard:
            set("Register card QR", "Code \(registerCode) · show or share it", "qrcode")
        case .replaceRegisterCard:
            set("Make a new register card", "Turns the printed card off right away", "arrow.triangle.2.circlepath")
        case .loyaltyCodes:
            set("Loyalty codes", "Single-use codes for orders and event handouts", "ticket")

        case .announcement(let index):
            let announcement = announcements[index]
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
            set(announcement.title, detail, expired ? "megaphone" : "megaphone.fill")
            config.textProperties.color = expired ? .secondaryLabel : .label
            config.imageProperties.tintColor = expired ? .systemGray3 : .systemOrange
        case .addAnnouncement:
            addRow("Post an announcement")

        case .showWindowSticker:
            set("Window sticker QR", "Show or share the scan-to-save code", "qrcode.viewfinder")
        case .emailStickers:
            set("Email me printable QR codes", contactEmail.map { "Sent to \($0)" } ?? "Window sticker and register card", "envelope")

        case .contactName:
            set("Contact name", contactName?.isEmpty == false ? contactName : "Add your name", "person.crop.circle")
        case .contactEmail:
            set("Contact email", contactEmail?.isEmpty == false ? contactEmail : "Add an email", "envelope.badge")
        case .managers:
            set("Managers", VenueManageCopy.managersLine(managerCount), "person.2.badge.gearshape")
        case .plan:
            let line = VenueManageCopy.planLine(premium: businessHeaderState)
            set(line.title, line.detail, businessHeaderState == true ? "checkmark.seal.fill" : "sparkles")
            if businessHeaderState == true { config.imageProperties.tintColor = .systemGreen }

        case .ownerGuide:
            set("Store owner guide", "A 4-minute video tour of everything here", "play.rectangle")
        case .brandStorefront:
            set("Brand storefront", "How your brand appears on your profile", "storefront")
        case .addBusiness:
            set("Add another location", "Claim another store you run", "plus.square.on.square")
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        row(at: indexPath) != .statTiles
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = row(at: indexPath) else { return }

        // Free owners get the paywall for any Business tool
        if !ownerPremium && VenueManageLayout.isBusiness(row) {
            presentOwnerPaywall()
            return
        }

        switch row {
        case .statTiles:
            break
        case .fullStats:
            navigationController?.pushViewController(VenueDashboardViewController(venueId: venueId, venueName: venueName), animated: true)
        case .savers:
            navigationController?.pushViewController(VenueAudienceViewController(venueId: venueId, mode: .savers), animated: true)
        case .followers:
            navigationController?.pushViewController(VenueAudienceViewController(venueId: venueId, mode: .followers), animated: true)
        case .activity:
            navigationController?.pushViewController(VenueActivityViewController(venueId: venueId), animated: true)

        case .viewPage:
            viewPublicPageTapped()
        case .hours:
            openHours()
        case .coverPhoto:
            openCoverPhoto()
        case .storefrontButtons, .menu, .gallery:
            openStorefrontRow(row)

        case .earnRate:
            editEarnRate()
        case .offer(let index):
            manageOffer(offers[index])
        case .addOffer:
            addOffer()
        case .showRegisterCard:
            showRegisterCard()
        case .replaceRegisterCard:
            rotateRegisterCode()
        case .loyaltyCodes:
            navigationController?.pushViewController(VenueCodesViewController(venueId: venueId, venueName: venueName), animated: true)

        case .announcement(let index):
            manageAnnouncement(announcements[index])
        case .addAnnouncement:
            addAnnouncement()

        case .showWindowSticker:
            showWindowQR()
        case .emailStickers:
            emailQR()

        case .contactName:
            editContactName()
        case .contactEmail:
            editContactEmail()
        case .managers:
            openManagers()
        case .plan:
            openPlan()

        case .ownerGuide:
            openOwnerGuide()
        case .brandStorefront:
            openBrandStorefront()
        case .addBusiness:
            navigationController?.pushViewController(ClaimBusinessViewController(), animated: true)
        }
    }
}

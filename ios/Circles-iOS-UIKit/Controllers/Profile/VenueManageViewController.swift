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

    private enum Section: Int, CaseIterable {
        case earnRate
        case offers
        case announcements
        case registerCode
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
        self.venuePlaceId = venue.globalPlaceId ?? venue.googlePlaceId
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

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .earnRate: return "Points per purchase"
        case .offers: return "Offers"
        case .announcements: return "Announcements"
        case .registerCode: return "Register QR card"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .earnRate:
            return "Customers earn these points each time they scan your register card after a purchase (once per day)."
        case .offers:
            return "Offers are what customers redeem their points for at your counter."
        case .announcements:
            return "Announcements show on your place's page to everyone — deals, happy hours, events. Expired ones hide automatically."
        case .registerCode:
            return "Generating a new QR immediately invalidates the old printed card — useful if a code leaks."
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .earnRate: return 1
        case .offers: return offers.count + 1 // + "Add offer" row
        case .announcements: return announcements.count + 1 // + "Add announcement" row
        case .registerCode: return 2 // rotate + email
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ManageCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none

        switch Section(rawValue: indexPath.section)! {
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
            if indexPath.row == 0 {
                config.text = "Generate new register QR"
                config.secondaryText = "Current code: \(registerCode)"
                config.image = UIImage(systemName: "qrcode")
                config.imageProperties.tintColor = Constants.Colors.primary
            } else {
                config.text = "Email QR codes to me"
                config.image = UIImage(systemName: "envelope")
                config.imageProperties.tintColor = Constants.Colors.primary
            }
        }

        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
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
        case .registerCode:
            if indexPath.row == 0 {
                rotateRegisterCode()
            } else {
                emailQR()
            }
        }
    }
}

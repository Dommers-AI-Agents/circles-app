import UIKit

/// Super-user page for one sticker-program store: identity, whether its
/// loyalty program is live and why, every counter, owner and team, both QR
/// codes explained, and links into the owner tools.
///
/// Opens instantly from the list row's data (name, address, codes), then
/// fills in the rest from GET /rewards/venues/:id/admin.
class VenueAdminDetailViewController: BaseViewController {

    /// Called after something the list shows changed (owner, codes)
    var onVenueChanged: (() -> Void)?

    private let listVenue: AdminVenue
    private var detail: AdminVenueDetail?

    override var enablesPullToRefresh: Bool { true }

    private enum Section: Int, CaseIterable {
        case loyalty, performance, team, codes, manage
    }

    private enum Row {
        case loyalty
        case statGrid
        case appClip(String)
        case fullDashboard
        case owner
        case managers
        case claim(AdminVenueClaim)
        case contact
        case windowCode
        case registerCode
        case replaceRegisterCode
        case emailCodes
        case manageTools
        case singleUseCodes
    }

    init(venue: AdminVenue) {
        self.listVenue = venue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        return table
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Store"
        view.backgroundColor = .systemGroupedBackground

        if placeId != nil {
            let eye = UIBarButtonItem(image: UIImage(systemName: "eye"), style: .plain, target: self, action: #selector(viewPublicPageTapped))
            eye.accessibilityLabel = "View public page"
            navigationItem.rightBarButtonItem = eye
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(StatGridCell.self, forCellReuseIdentifier: StatGridCell.reuseId)
        tableView.register(QRCodeCell.self, forCellReuseIdentifier: QRCodeCell.reuseId)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateHeader()
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.getAdminVenueDetail(venueId: listVenue.venueId) { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self = self else { return }
                switch result {
                case .success(let detail):
                    self.detail = detail
                    self.updateHeader()
                    self.tableView.reloadData()
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - Current values (detail when loaded, list row until then)

    private var venueName: String { detail?.venue.venueName ?? listVenue.venueName }
    private var windowCode: String { detail?.venue.windowCode ?? listVenue.windowCode }
    private var registerCode: String { detail?.venue.registerCode ?? listVenue.registerCode }
    private var earnRate: Int? { detail?.venue.earnRate ?? listVenue.earnRate }
    private var isVirtual: Bool { (detail?.venue.isVirtual ?? listVenue.isVirtual) == true }
    private var placeId: String? {
        detail?.venue.globalPlaceId ?? detail?.venue.googlePlaceId ?? listVenue.globalPlaceId ?? listVenue.googlePlaceId
    }
    private var windowStickerUrl: String {
        detail?.venue.windowStickerUrl ?? listVenue.windowStickerUrl ?? "\(ShareLinks.base)/s/\(windowCode)"
    }
    private var registerCardUrl: String {
        detail?.venue.registerCardUrl ?? "\(ShareLinks.base)/s/\(registerCode)"
    }

    /// The owner tools take the list shape; rebuild it from the fresh detail
    /// so a rotated code or new owner is what they see
    private var manageVenue: AdminVenue {
        guard let d = detail else { return listVenue }
        return AdminVenue(
            venueId: d.venue.venueId,
            venueName: d.venue.venueName,
            placeAddress: d.venue.placeAddress,
            contactName: d.venue.contactName,
            contactEmail: d.venue.contactEmail,
            windowStickerUrl: d.venue.windowStickerUrl,
            windowCode: d.venue.windowCode,
            registerCode: d.venue.registerCode,
            active: d.venue.active,
            stats: listVenue.stats,
            earnRate: d.venue.earnRate,
            offers: d.venue.offers,
            announcements: d.venue.announcements,
            googlePlaceId: d.venue.googlePlaceId,
            globalPlaceId: d.venue.globalPlaceId,
            ownerPremium: d.loyalty.active,
            isVirtual: d.venue.isVirtual,
            ownerUserId: d.venue.ownerUserId,
            managerUserIds: d.venue.managerUserIds,
            isPrimaryOwner: false
        )
    }

    // MARK: - Header

    private func updateHeader() {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let name = UILabel()
        name.text = venueName
        name.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        name.numberOfLines = 0
        stack.addArrangedSubview(name)

        let address = isVirtual
            ? "Online store · no physical location"
            : VenueAdminCopy.cleanAddress(detail?.venue.placeAddress ?? listVenue.placeAddress)
        if let address = address {
            let label = UILabel()
            label.text = address
            label.font = UIFont.systemFont(ofSize: 15)
            label.textColor = Constants.Colors.secondaryLabel
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }

        var facts: [String] = []
        if let category = detail?.venue.category, !category.isEmpty, !isVirtual {
            facts.append(category.capitalized)
        }
        if let added = VenueAdminCopy.parseDate(detail?.venue.createdAt) {
            facts.append("Added \(VenueAdminCopy.formatDate(added))")
        }
        if detail?.venue.active == false {
            facts.append("Inactive")
        }
        if !facts.isEmpty {
            let label = UILabel()
            label.text = facts.joined(separator: " · ")
            label.font = UIFont.systemFont(ofSize: 13)
            label.textColor = detail?.venue.active == false ? Constants.Colors.danger : Constants.Colors.tertiaryLabel
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        let size = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        container.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size the header to the real width once the table has one
        if let header = tableView.tableHeaderView, abs(header.frame.width - tableView.bounds.width) > 0.5 {
            updateHeader()
        }
    }

    // MARK: - Rows

    private func rows(in section: Section) -> [Row] {
        switch section {
        case .loyalty:
            return detail == nil ? [] : [.loyalty]
        case .performance:
            guard let d = detail else { return [] }
            var rows: [Row] = [.statGrid]
            if let clip = VenueAdminCopy.appClipLine(d.stats) { rows.append(.appClip(clip)) }
            rows.append(.fullDashboard)
            return rows
        case .team:
            guard let d = detail else { return [] }
            var rows: [Row] = [.owner, .managers]
            rows += d.pendingClaims.map { Row.claim($0) }
            if d.venue.contactName != nil || d.venue.contactEmail != nil { rows.append(.contact) }
            return rows
        case .codes:
            return [.windowCode, .registerCode, .replaceRegisterCode, .emailCodes]
        case .manage:
            return [.manageTools, .singleUseCodes]
        }
    }

    private func row(at indexPath: IndexPath) -> Row? {
        guard let section = Section(rawValue: indexPath.section) else { return nil }
        let rows = rows(in: section)
        return indexPath.row < rows.count ? rows[indexPath.row] : nil
    }

    // MARK: - Actions

    @objc private func viewPublicPageTapped() {
        guard let placeId = placeId else { return }
        let loading = AlertPresenter.showLoading(message: "Loading...", from: self)
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let place):
                        self.navigationController?.pushViewController(PlaceDetailViewController(place: place), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func changeOwner() {
        let current = detail?.owner
        AlertPresenter.showTextInput(
            title: current == nil ? "Assign Owner" : "Change Owner",
            message: "Email of the FavCircles account that owns \(venueName). They'll manage its offers, earn rate, and QR codes, and their Business plan is what keeps loyalty live.",
            placeholder: "owner@example.com",
            initialText: current?.email ?? detail?.venue.contactEmail ?? listVenue.contactEmail,
            keyboardType: .emailAddress,
            from: self
        ) { [weak self] email in
            guard let self = self,
                  let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else { return }

            let loading = AlertPresenter.showLoading(message: "Assigning...", from: self)
            RewardsService.shared.assignVenueOwner(venueId: self.listVenue.venueId, email: email) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success(let ownerEmail):
                            self.loadData()
                            self.onVenueChanged?()
                            AlertPresenter.showSuccess("\(ownerEmail) now owns \(self.venueName)", from: self)
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }

    private func showQR(register: Bool) {
        let qrVC = register
            ? VenueQRViewController(
                venueName: venueName,
                stickerUrl: registerCardUrl,
                screenTitle: "Register Card QR",
                caption: VenueAdminCopy.registerCardExplanation(earnRate: earnRate, loyaltyActive: detail?.loyalty.active ?? true))
            : VenueQRViewController(
                venueName: venueName,
                stickerUrl: windowStickerUrl,
                screenTitle: "Window Sticker QR",
                caption: VenueAdminCopy.windowStickerExplanation())
        navigationController?.pushViewController(qrVC, animated: true)
    }

    private func replaceRegisterCode() {
        showConfirmation(
            title: "Replace the register code?",
            message: "The card at \(venueName)'s counter (code \(registerCode)) stops working the moment the new code is made. Only do this if the card leaked or was lost, and get the new one printed right away.",
            confirmTitle: "Replace",
            isDestructive: true
        ) { [weak self] in
            self?.performRotation()
        }
    }

    private func performRotation() {
        let loading = AlertPresenter.showLoading(message: "Generating new code...", from: self)
        RewardsService.shared.rotateRegisterCode(venueId: listVenue.venueId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let rotated):
                        self.loadData()
                        self.onVenueChanged?()
                        self.showConfirmation(
                            title: "New register code: \(rotated.registerCode)",
                            message: "Email the printable QR codes to yourself now?",
                            confirmTitle: "Email me the QR codes"
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
        RewardsService.shared.emailVenueQR(venueId: listVenue.venueId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let email):
                        AlertPresenter.showSuccess("Printable QR codes for \(self.venueName) sent to \(email)", from: self)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func emailContact(_ email: String) {
        guard let url = URL(string: "mailto:\(email)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension VenueAdminDetailViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return rows(in: section).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section), !rows(in: section).isEmpty else { return nil }
        switch section {
        case .loyalty: return "Loyalty program"
        case .performance: return "Performance"
        case .team: return "Owner & team"
        case .codes: return "QR codes"
        case .manage: return "Manage"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .codes:
            return "The window sticker brings people in; the register card rewards purchases. Both are in the printable email."
        case .performance where detail != nil:
            return "\"Saved by\" counts everyone with the store saved, however they found it."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }

        switch row {
        case .statGrid:
            let cell = tableView.dequeueReusableCell(withIdentifier: StatGridCell.reuseId, for: indexPath) as! StatGridCell
            if let d = detail {
                cell.configure(tiles: VenueAdminCopy.statTiles(d.stats, thisMonth: d.thisMonth))
            }
            return cell

        case .windowCode:
            let cell = tableView.dequeueReusableCell(withIdentifier: QRCodeCell.reuseId, for: indexPath) as! QRCodeCell
            cell.configure(
                symbol: "storefront",
                title: "Window sticker",
                code: windowCode,
                explanation: VenueAdminCopy.windowStickerExplanation(),
                dimmed: false
            )
            return cell

        case .registerCode:
            let cell = tableView.dequeueReusableCell(withIdentifier: QRCodeCell.reuseId, for: indexPath) as! QRCodeCell
            let live = detail?.loyalty.active ?? true
            cell.configure(
                symbol: "creditcard",
                title: "Register card",
                code: registerCode,
                explanation: VenueAdminCopy.registerCardExplanation(earnRate: earnRate, loyaltyActive: live),
                dimmed: !live
            )
            return cell

        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.contentConfiguration = configuration(for: row, cell: cell)
            cell.accessoryType = isTappable(row) ? .disclosureIndicator : .none
            cell.selectionStyle = isTappable(row) ? .default : .none
            return cell
        }
    }

    private func isTappable(_ row: Row) -> Bool {
        switch row {
        case .loyalty, .appClip: return false
        case .contact: return detail?.venue.contactEmail != nil
        default: return true
        }
    }

    private func configuration(for row: Row, cell: UITableViewCell) -> UIListContentConfiguration {
        var config = UIListContentConfiguration.subtitleCell()
        config.secondaryTextProperties.color = Constants.Colors.secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
        config.imageProperties.tintColor = Constants.Colors.primary
        config.textToSecondaryTextVerticalPadding = 3

        switch row {
        case .loyalty:
            guard let d = detail else { break }
            let line = VenueAdminCopy.loyalty(d.loyalty, owner: d.owner)
            config.text = line.title
            config.textProperties.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            config.secondaryText = line.detail
            config.image = UIImage(systemName: line.symbol)
            switch line.tone {
            case .good: config.imageProperties.tintColor = Constants.Colors.success
            case .warning: config.imageProperties.tintColor = Constants.Colors.warning
            case .neutral: config.imageProperties.tintColor = Constants.Colors.secondaryLabel
            }

        case .appClip(let text):
            config = UIListContentConfiguration.cell()
            config.text = text
            config.textProperties.font = UIFont.systemFont(ofSize: 14)
            config.textProperties.color = Constants.Colors.secondaryLabel
            config.image = UIImage(systemName: "appclip")
            config.imageProperties.tintColor = Constants.Colors.secondaryLabel

        case .fullDashboard:
            config = UIListContentConfiguration.cell()
            config.text = "Full dashboard · 6-month history"
            config.image = UIImage(systemName: "chart.bar.xaxis")
            config.imageProperties.tintColor = Constants.Colors.primary

        case .owner:
            config.image = UIImage(systemName: "person.crop.circle")
            if let owner = detail?.owner {
                config.text = owner.displayName ?? owner.email ?? "Owner"
                var parts: [String] = ["Owner"]
                if let email = owner.email { parts.append(email) }
                if owner.isSuperUser == true { parts.append("FavCircles admin") }
                config.secondaryText = parts.joined(separator: " · ") + "\nTap to change the owner"
            } else {
                config.text = "No owner"
                config.secondaryText = "Tap to assign the FavCircles account that runs this store"
                config.imageProperties.tintColor = Constants.Colors.secondaryLabel
            }

        case .managers:
            let managers = detail?.managers ?? []
            config.image = UIImage(systemName: "person.2")
            config.text = managers.isEmpty ? "No managers" : VenueAdminCopy.count(managers.count, "manager")
            config.secondaryText = managers.isEmpty
                ? "Staff the owner lets run the store day to day"
                : managers.map { $0.displayName ?? $0.email ?? "Unknown" }.joined(separator: ", ")

        case .claim(let claim):
            config.image = UIImage(systemName: "tray.full")
            config.imageProperties.tintColor = Constants.Colors.warning
            config.text = "Pending claim · \(claim.name ?? claim.email ?? "Unknown")"
            var parts = [claim.email, claim.phone].compactMap { $0 }
            if let date = VenueAdminCopy.parseDate(claim.createdAt) {
                parts.append("filed \(VenueAdminCopy.formatDate(date))")
            }
            config.secondaryText = parts.joined(separator: " · ") + "\nTap to review"

        case .contact:
            config.image = UIImage(systemName: "envelope")
            config.text = detail?.venue.contactName ?? "Store contact"
            config.secondaryText = ["Contact from enrollment", detail?.venue.contactEmail]
                .compactMap { $0 }.joined(separator: " · ")

        case .replaceRegisterCode:
            config = UIListContentConfiguration.cell()
            config.text = "Replace register code…"
            config.textProperties.color = Constants.Colors.danger
            config.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            config.imageProperties.tintColor = Constants.Colors.danger

        case .emailCodes:
            config = UIListContentConfiguration.cell()
            config.text = "Email printable QR codes to me"
            config.image = UIImage(systemName: "envelope")

        case .manageTools:
            config.image = UIImage(systemName: "slider.horizontal.3")
            config.text = "Offers, earn rate & storefront"
            var parts: [String] = []
            if let rate = earnRate { parts.append("\(VenueAdminCopy.count(rate, "point")) per visit") }
            let offers = (detail?.venue.offers ?? listVenue.offers ?? []).filter { $0.active != false }.count
            parts.append(VenueAdminCopy.count(offers, "active offer"))
            if let storefront = detail?.storefront {
                parts.append(VenueAdminCopy.count(storefront.actions + storefront.offerings + storefront.gallery, "storefront item"))
            }
            config.secondaryText = parts.joined(separator: " · ")

        case .singleUseCodes:
            config.image = UIImage(systemName: "ticket")
            config.text = "Single-use codes"
            config.secondaryText = "One-time loyalty codes for order boxes and handouts"

        case .statGrid, .windowCode, .registerCode:
            break
        }
        return config
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = row(at: indexPath) else { return }
        let venueId = listVenue.venueId

        switch row {
        case .statGrid, .fullDashboard:
            navigationController?.pushViewController(
                VenueDashboardViewController(venueId: venueId, venueName: venueName), animated: true)
        case .owner:
            changeOwner()
        case .managers:
            navigationController?.pushViewController(
                VenueManagersViewController(venueId: venueId, venueName: venueName), animated: true)
        case .claim:
            navigationController?.pushViewController(VenueClaimsViewController(), animated: true)
        case .contact:
            if let email = detail?.venue.contactEmail { emailContact(email) }
        case .windowCode:
            showQR(register: false)
        case .registerCode:
            showQR(register: true)
        case .replaceRegisterCode:
            replaceRegisterCode()
        case .emailCodes:
            emailQR()
        case .manageTools:
            navigationController?.pushViewController(VenueManageViewController(venue: manageVenue), animated: true)
        case .singleUseCodes:
            navigationController?.pushViewController(
                VenueCodesViewController(venueId: venueId, venueName: venueName), animated: true)
        case .loyalty, .appClip:
            break
        }
    }
}

// MARK: - QR code cell

/// One printed code: what it's for, the code itself, and what scanning does
private final class QRCodeCell: UITableViewCell {
    static let reuseId = "QRCodeCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let codeLabel = UILabel()
    private let explanationLabel = UILabel()
    private let showLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        iconView.tintColor = Constants.Colors.primary
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        codeLabel.font = UIFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        explanationLabel.font = UIFont.systemFont(ofSize: 13)
        explanationLabel.textColor = Constants.Colors.secondaryLabel
        explanationLabel.numberOfLines = 0
        showLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        showLabel.textColor = Constants.Colors.primary
        showLabel.text = "Show QR to scan or share"

        let titleRow = UIStackView(arrangedSubviews: [iconView, titleLabel])
        titleRow.spacing = 8
        titleRow.alignment = .center
        let stack = UIStackView(arrangedSubviews: [titleRow, codeLabel, explanationLabel, showLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(8, after: explanationLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(symbol: String, title: String, code: String, explanation: String, dimmed: Bool) {
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        codeLabel.text = code
        codeLabel.textColor = dimmed ? Constants.Colors.secondaryLabel : Constants.Colors.label
        explanationLabel.text = explanation
        accessibilityLabel = "\(title), code \(code). \(explanation)"
    }
}

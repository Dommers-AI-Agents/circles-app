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
    private var earnRate: Int
    private var registerCode: String

    private enum Section: Int, CaseIterable {
        case earnRate
        case offers
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
        self.earnRate = venue.earnRate ?? 25
        self.registerCode = venue.registerCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = venueName
        view.backgroundColor = .systemBackground

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
        case .registerCode: return "Register QR card"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .earnRate:
            return "Customers earn these points each time they scan your register card after a purchase (once per day)."
        case .offers:
            return "Offers are what customers redeem their points for at your counter."
        case .registerCode:
            return "Generating a new QR immediately invalidates the old printed card — useful if a code leaks."
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .earnRate: return 1
        case .offers: return offers.count + 1 // + "Add offer" row
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
        case .registerCode:
            if indexPath.row == 0 {
                rotateRegisterCode()
            } else {
                emailQR()
            }
        }
    }
}

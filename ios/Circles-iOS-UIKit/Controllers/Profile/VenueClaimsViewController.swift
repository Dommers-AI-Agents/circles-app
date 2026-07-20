import UIKit

/// Super-user screen: pending business-ownership claims filed from place
/// pages. Approving a claim makes the claimant the venue's owner (same write
/// path as assigning by email) and closes competing claims.
class VenueClaimsViewController: BaseViewController {

    // MARK: - Properties

    private var claims: [VenueClaim] = []

    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No pending claims." }

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        return table
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ownership Claims"
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ClaimCell")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }

    // MARK: - BaseViewController

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.listClaims(status: "pending") { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                switch result {
                case .success(let claims):
                    self?.claims = claims
                    self?.tableView.reloadData()
                    if claims.isEmpty {
                        self?.showEmptyState()
                    } else {
                        self?.hideEmptyState()
                    }
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    // MARK: - Review actions

    private func reviewClaim(_ claim: VenueClaim) {
        let claimant = claim.userDisplayName ?? claim.userEmail ?? claim.userId
        showActionSheet(
            title: claim.venueName ?? "Ownership claim",
            message: "\(claimant)\(claim.message.map { " — \"\($0)\"" } ?? "")",
            actions: [
                (title: "Approve", style: .default, handler: { [weak self] in
                    self?.confirmApprove(claim)
                }),
                (title: "Deny", style: .destructive, handler: { [weak self] in
                    self?.denyClaim(claim)
                })
            ]
        )
    }

    private func confirmApprove(_ claim: VenueClaim) {
        let claimant = claim.userDisplayName ?? claim.userEmail ?? claim.userId
        let business = claim.venueName ?? claim.placeName ?? "this business"
        let isEnrolled = claim.venueId != nil

        let message = isEnrolled
            ? "\(claimant) becomes the owner of \(business) and can manage its offers and announcements. Other pending claims for this venue are denied."
            : "\(business) isn't in the sticker program yet. Approving will enroll it, make \(claimant) the owner, and email you the printable QR codes."

        showConfirmation(
            title: "Approve claim?",
            message: message,
            confirmTitle: "Approve"
        ) { [weak self] in
            guard let self = self else { return }
            let loading = AlertPresenter.showLoading(message: isEnrolled ? "Approving..." : "Enrolling business...", from: self)
            RewardsService.shared.approveClaim(claimId: claim.claimId) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            let successMessage = isEnrolled
                                ? "\(claimant) now owns \(business)."
                                : "\(business) is enrolled and \(claimant) now owns it. QR codes are on the way to your email."
                            self.showSuccess(successMessage)
                            self.loadData()
                        case .failure(let error):
                            self.showError(error)
                            self.loadData() // claim may have been auto-denied (venue already owned)
                        }
                    }
                }
            }
        }
    }

    private func denyClaim(_ claim: VenueClaim) {
        showTextInput(
            title: "Deny claim",
            message: "Optional reason (shown to the requester)",
            placeholder: "e.g. couldn't verify ownership"
        ) { [weak self] reason in
            guard let self = self else { return }
            let loading = AlertPresenter.showLoading(message: "Denying...", from: self)
            RewardsService.shared.denyClaim(
                claimId: claim.claimId,
                reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch result {
                        case .success:
                            self.loadData()
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension VenueClaimsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return claims.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ClaimCell", for: indexPath)
        let claim = claims[indexPath.row]

        var config = cell.defaultContentConfiguration()
        let businessName = claim.venueName ?? claim.placeName ?? claim.venueId ?? "Unknown business"
        config.text = claim.venueId == nil ? "\(businessName) (not enrolled)" : businessName

        var details: [String] = []
        details.append(claim.contactName ?? claim.userDisplayName ?? claim.userEmail ?? claim.userId)
        if let contactEmail = claim.contactEmail { details.append(contactEmail) }
        if let contactPhone = claim.contactPhone { details.append(contactPhone) }
        if let message = claim.message, !message.isEmpty { details.append("\"\(message)\"") }
        if let createdAt = claim.createdAt { details.append(String(createdAt.prefix(10))) }
        config.secondaryText = details.joined(separator: " · ")

        config.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
        config.imageProperties.tintColor = Constants.Colors.primary
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        reviewClaim(claims[indexPath.row])
    }
}

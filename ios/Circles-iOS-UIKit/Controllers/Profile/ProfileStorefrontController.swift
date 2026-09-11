import UIKit

/// What the storefront pieces need from the profile screen: the profile's
/// user, the card view (laid out by the screen) and its collapse toggle,
/// and the navigation bar/stack for the owner button and destinations.
protocol ProfileStorefrontControllerDelegate: AnyObject {
    var user: User? { get }
    var storefrontCard: StorefrontCardView { get }
    var navigationItem: UINavigationItem { get }
    var navigationController: UINavigationController? { get }
    func setStorefrontCardVisible(_ visible: Bool)
}

/// The profile's two storefront surfaces (Phase 5, profile step 7), moved
/// verbatim from ProfileViewController:
/// - the owner/super-user "My Storefront" bar button with its pending-claims
///   dot, and where it leads;
/// - the public storefront card for brand accounts, loaded once per profile
///   and wired to its website / catalog / find-us-at / offers / edit actions.
final class ProfileStorefrontController: NSObject {
    weak var delegate: ProfileStorefrontControllerDelegate?

    private var storefrontOpensVenueAdmin = false
    private weak var storefrontClaimsDot: UIView?
    private var loadedStorefrontUserId: String?

    // MARK: Owner button

    /// Store owners (and super-users) get a storefront button on their own
    /// profile — the entry point to venue management. Normal users never see
    /// it, and the consumer rewards page stays merchant-free.
    func addStorefrontButtonIfEligible() {
        RewardsService.shared.getRewardsProfile { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate,
                      delegate.user?.id == AuthService.shared.getUserId(),
                      case .success(let profile) = result else { return }
                let isSuper = profile.isSuperUser
                guard isSuper || profile.ownsVenues == true else { return }
                self.storefrontOpensVenueAdmin = isSuper

                let existing = delegate.navigationItem.rightBarButtonItems ?? []
                if !existing.contains(where: { $0.accessibilityLabel == "My Storefront" }) {
                    // Custom view so a pending-claims dot can sit on the icon
                    let button = UIButton.iconButton(systemName: "storefront", pointSize: 19)
                    button.tintColor = Constants.Colors.primary
                    button.addTarget(self, action: #selector(self.storefrontButtonTapped), for: .touchUpInside)

                    let dot = UIView()
                    dot.backgroundColor = .systemRed
                    dot.layer.cornerRadius = 4.5
                    dot.isHidden = true
                    dot.isUserInteractionEnabled = false
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(dot)
                    NSLayoutConstraint.activate([
                        button.widthAnchor.constraint(equalToConstant: 30),
                        button.heightAnchor.constraint(equalToConstant: 30),
                        dot.widthAnchor.constraint(equalToConstant: 9),
                        dot.heightAnchor.constraint(equalToConstant: 9),
                        dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
                        dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1)
                    ])
                    self.storefrontClaimsDot = dot

                    let storefrontButton = UIBarButtonItem(customView: button)
                    storefrontButton.accessibilityLabel = "My Storefront"
                    delegate.navigationItem.rightBarButtonItems = existing + [storefrontButton]
                }
                self.refreshStorefrontClaimsDot()
            }
        }
    }

    /// Red dot on the storefront icon while ownership claims await review —
    /// super-users only; it mirrors the claims tray in venue admin.
    private func refreshStorefrontClaimsDot() {
        guard storefrontOpensVenueAdmin else { return }
        RewardsService.shared.listClaims(status: "pending") { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let claims) = result else { return }
                self?.storefrontClaimsDot?.isHidden = claims.isEmpty
            }
        }
    }

    @objc private func storefrontButtonTapped() {
        let destination: UIViewController = storefrontOpensVenueAdmin
            ? VenueAdminViewController()
            : OwnerVenuesViewController()
        delegate?.navigationController?.pushViewController(destination, animated: true)
    }

    // MARK: Storefront card (brand accounts)

    /// Loads the profile user's public storefront and expands the card when
    /// one exists. Non-business accounts return storefront: null and the card
    /// stays collapsed — one cheap call per profile view.
    func refreshStorefrontCard() {
        guard let delegate = delegate else { return }
        let profileUserId = delegate.user?.id ?? AuthService.shared.getUserId()
        guard let userId = profileUserId else { return }
        // Same profile already loaded — don't flicker on every displayUser pass
        if loadedStorefrontUserId == userId, delegate.storefrontCard.isHidden == false { return }

        RewardsService.shared.getStorefront(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate else { return }
                // Profile may have been reconfigured while the read was in flight
                let currentId = delegate.user?.id ?? AuthService.shared.getUserId()
                guard currentId == userId else { return }
                self.loadedStorefrontUserId = userId

                guard case .success(let data) = result, let storefront = data.storefront else {
                    delegate.setStorefrontCardVisible(false)
                    return
                }
                let isOwn = delegate.user == nil || IDNormalizer.isSameUser(userId, AuthService.shared.getUserId() ?? "")
                delegate.storefrontCard.configure(
                    storefront: storefront,
                    findUsAtCircle: data.findUsAtCircle,
                    venues: data.venues,
                    isOwnProfile: isOwn
                )
                self.wireStorefrontCardActions(storefront: storefront, findUsAtCircle: data.findUsAtCircle)
                delegate.setStorefrontCardVisible(true)
            }
        }
    }

    private func wireStorefrontCardActions(storefront: StorefrontInfo, findUsAtCircle: StorefrontCircleSummary?) {
        guard let card = delegate?.storefrontCard else { return }
        card.onWebsite = { [weak self] in
            self?.openStorefrontLink(storefront.website)
        }
        card.onCatalog = { [weak self] in
            self?.openStorefrontLink(storefront.catalogUrl)
        }
        card.onFindUsAt = { [weak self] in
            guard let self = self, let circleId = findUsAtCircle?.id else { return }
            CircleService.shared.fetchCircleById(id: circleId) { result in
                DispatchQueue.main.async {
                    guard case .success(let circle) = result else { return }
                    let detailVC = CircleDetailViewController(circle: circle)
                    self.delegate?.navigationController?.pushViewController(detailVC, animated: true)
                }
            }
        }
        card.onOffers = { [weak self] in
            // Store offers live in the rewards hub
            let hub = RewardsHubViewController()
            hub.initialTab = .rewards
            self?.delegate?.navigationController?.pushViewController(hub, animated: true)
        }
        card.onEdit = { [weak self] in
            guard let self = self else { return }
            let editor = StorefrontEditViewController()
            editor.initialStorefront = storefront
            editor.initialFindUsAtCircleId = findUsAtCircle?.id
            editor.onSaved = { [weak self] in
                self?.loadedStorefrontUserId = nil
                self?.refreshStorefrontCard()
            }
            self.delegate?.navigationController?.pushViewController(editor, animated: true)
        }
    }

    private func openStorefrontLink(_ urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

import UIKit
import CoreLocation

/// Drives the UX after a physical sticker QR code is scanned:
/// - window QR → "Build your map!" save prompt (never points, 2026-10-30)
/// - register card  → visit points + offer redemption sheet → voucher screen
///
/// Every scan first opens the store's place page, so the result (and the
/// points balance on the store card) reads over the store itself.
/// SceneDelegate calls `handleScannedCode` and this coordinator owns the rest,
/// including the CircleSelection delegate round-trip.

final class StickerRewardCoordinator: NSObject {

    static let shared = StickerRewardCoordinator()

    private var pendingVenue: RewardVenue?
    private var pendingCode: String?

    private override init() {
        super.init()
    }

    private var presenter: UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Entry point

    func handleScannedCode(_ code: String) {
        guard let presenter = presenter else {
            // No window yet (a cold launch from the QR): keep the code so the
            // launch redeems it, instead of dropping the scan
            RewardsService.shared.savePendingStickerCode(code)
            return
        }
        // "Checking rewards…", then the store's name as soon as it's known
        // (a quick lookup alongside the scan; remembered for repeat scans)
        let loading = AlertPresenter.showLoading(message: "Checking rewards\u{2026}", from: presenter)
        RewardsService.shared.storeName(forCode: code) { name in
            guard let name else { return }
            DispatchQueue.main.async { loading.message = "Checking rewards at \(name)\u{2026}" }
        }

        scanWithRetry(code: code) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let scan) = result {
                    UserDefaults.standard.set(scan.venue.venueName, forKey: "storeNameForCode." + code.uppercased())
                }
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let scan):
                        NotificationCenter.default.post(name: .rewardPointsDidChange, object: nil)
                        self?.showStorePage(for: scan.venue) {
                            if scan.kind == "register" {
                                self?.handleRegisterScan(scan, code: code)
                            } else {
                                self?.handleWindowScan(scan, code: code)
                            }
                        }
                    case .failure(let error):
                        if let presenter = self?.presenter {
                            AlertPresenter.showError(error, from: presenter)
                        }
                    }
                }
            }
        }
    }

    /// A scan that hits a dropped or slow connection tries once more before
    /// saying so: the server records a visit once a day and a signup once,
    /// so a second try is safe and answers "already earned today" if the
    /// first one landed (2026-10-30: a scan that succeeded on the server
    /// showed "Can't reach FavCircles" on the phone).
    private func scanWithRetry(code: String, completion: @escaping (Result<RewardScanData, Error>) -> Void) {
        RewardsService.shared.scan(code: code) { result in
            if case .failure(let error) = result, Self.isConnectivity(error) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    RewardsService.shared.scan(code: code, completion: completion)
                }
                return
            }
            completion(result)
        }
    }

    private static func isConnectivity(_ error: Error) -> Bool {
        if let api = error as? APIError, case .noInternet = api { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }

    // MARK: - Store page

    /// Opens the store's place page on the current tab (unless it's already
    /// the page on screen), then runs `then` over it. Falls back to `then`
    /// alone when the store has no place or the page can't load.
    private func showStorePage(for venue: RewardVenue, then: @escaping () -> Void) {
        guard let placeId = venue.globalPlaceId,
              let tabBar = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController as? CirclesTabBarController })
                .first,
              let nav = tabBar.selectedViewController as? UINavigationController else {
            then()
            return
        }
        let push = {
            if let showing = nav.topViewController as? PlaceDetailViewController,
               showing.shownGlobalPlaceId == placeId {
                then()
                return
            }
            PlaceService.shared.fetchPlaceById(id: placeId) { result in
                DispatchQueue.main.async {
                    guard case .success(let place) = result else { then(); return }
                    nav.pushViewController(PlaceDetailViewController(place: place), animated: true)
                    // Present only once the page has finished sliding in: an
                    // alert presented mid-push is silently dropped, which hid
                    // the points result
                    if let transition = nav.transitionCoordinator {
                        transition.animate(alongsideTransition: nil) { _ in then() }
                    } else {
                        then()
                    }
                }
            }
        }
        // Never close a sheet that's up (a new account's zip-code prompt was
        // shut by this, Wes 2026-10-29): wait for it to be answered, then go
        waitUntilNothingPresented(over: tabBar, then: push)
    }

    /// Runs `then` once nothing is presented over `host` (checked every half
    /// second for up to five minutes; after that it goes ahead anyway).
    private func waitUntilNothingPresented(over host: UIViewController, attempt: Int = 0, then: @escaping () -> Void) {
        guard host.presentedViewController != nil, attempt < 600 else { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitUntilNothingPresented(over: host, attempt: attempt + 1, then: then)
        }
    }

    // MARK: - Typed codes

    /// "Type a code": a brand redemption code from an order card or handout,
    /// or a store sticker's code typed by hand — one box takes both.
    /// `onRedeemed` runs after a brand code is accepted (sticker codes carry
    /// on through the scan flow above).
    func promptForCode(from presenter: UIViewController, onRedeemed: (() -> Void)? = nil) {
        AlertPresenter.showTextInput(
            title: "Type a Code",
            message: "Enter the code from the store's QR card, your receipt, or an order card",
            placeholder: "CODE",
            confirmTitle: "Redeem",
            from: presenter
        ) { [weak self] text in
            let code = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty else { return }
            self?.submitTypedCode(code, from: presenter, onRedeemed: onRedeemed)
        }
    }

    private func submitTypedCode(_ code: String, from presenter: UIViewController, onRedeemed: (() -> Void)?) {
        RewardsService.shared.redeemCode(code) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    NotificationCenter.default.post(name: .rewardPointsDidChange, object: nil)
                    if let awarded = data.awarded {
                        let store = awarded.venueName ?? "the store"
                        AlertPresenter.showSuccess("+\(awarded.points) points from \(store)!", from: presenter)
                    } else {
                        AlertPresenter.showSuccess("Code accepted", from: presenter)
                    }
                    onRedeemed?()
                case .failure(let error):
                    // Not a brand code? It may be a sticker code typed by hand.
                    let message = (error as? APIError)?.serverMessage ?? error.localizedDescription
                    if message.localizedCaseInsensitiveContains("not found") {
                        self?.handleScannedCode(code)
                    } else {
                        AlertPresenter.showError(message: message, from: presenter)
                    }
                }
            }
        }
    }

    // MARK: - Window sticker (discovery / signup / save)

    /// The window QR is for getting the app, saving the store and building
    /// your map: no points and no rewards wording, ever (Wes, 2026-10-30).
    /// Store points come only from the register QR.
    private func handleWindowScan(_ scan: RewardScanData, code: String) {
        guard let presenter = presenter else { return }
        let name = scan.venue.venueName
        if scan.alreadySaved == true {
            var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
            // Show me: the circle it's saved in, scrolled to it (2026-10-30)
            if let saved = scan.savedPlace, let circleId = saved.circleId {
                actions.append((title: "Show me", style: .default, handler: { [weak self] in
                    self?.openSavedCircle(circleId: circleId, placeId: saved.placeId)
                }))
            }
            actions.append((title: "OK", style: .cancel, handler: {}))
            AlertPresenter.showAlert(title: "Welcome back!", message: "\(name) is already in your circles.", actions: actions, from: presenter)
            return
        }
        AlertPresenter.showConfirmation(
            title: "Don't forget \(name)!",
            message: "Build your map! Save \(name) to one of your circles and never forget it.",
            confirmTitle: "Save",
            cancelTitle: "Not Now",
            from: presenter
        ) { [weak self] in
            self?.startSaveFlow(venue: scan.venue, code: code)
        }
    }

    /// "Save this store?" after a register scan, into the circle they pick
    private func offerSave(venue: RewardVenue, code: String, bonus: Int) {
        guard let presenter = presenter else { return }
        AlertPresenter.showConfirmation(
            title: "Save \(venue.venueName)?",
            message: bonus > 0
                ? "Build your map! Save \(venue.venueName) to one of your circles and earn \(bonus) more points here."
                : "Build your map! Save \(venue.venueName) to one of your circles and never forget it.",
            confirmTitle: bonus > 0 ? "Save & Earn" : "Save",
            cancelTitle: "Not Now",
            from: presenter
        ) { [weak self] in
            self?.startSaveFlow(venue: venue, code: code)
        }
    }

    private func startSaveFlow(venue: RewardVenue, code: String) {
        guard let presenter = presenter else { return }
        pendingVenue = venue
        pendingCode = code

        let circleSelectionVC = CircleSelectionViewController(
            customTitle: "Save \(venue.venueName) to a Circle"
        )
        circleSelectionVC.delegate = self
        presenter.present(circleSelectionVC, animated: true)
    }

    private func savePlace(venue: RewardVenue, code: String, to circle: Circle) {
        guard let presenter = presenter else { return }
        let loading = AlertPresenter.showLoading(message: "Saving place...", from: presenter)

        var geoLocation: GeoLocation?
        if let location = venue.location {
            geoLocation = GeoLocation(type: "Point", coordinates: [location.lng, location.lat])
        }

        let category = PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant

        PlaceService.shared.addPlaceFromPOI(
            name: venue.placeName ?? venue.venueName,
            address: venue.placeAddress ?? "",
            location: geoLocation,
            category: category,
            circleId: circle.id,
            notes: nil,
            googlePlaceId: venue.googlePlaceId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.confirmSaveReward(code: code, venue: venue, loading: loading)
                case .failure(let error):
                    if let duplicate = PlaceDuplicate.from(error) {
                        // Already in one of their circles (the scan's own check
                        // missed it): not an error — say so, and still claim
                        // the save points if they were never paid
                        self?.confirmSaveReward(code: code, venue: venue, loading: loading, alreadySaved: duplicate)
                        return
                    }
                    loading.dismiss(animated: true) {
                        if let presenter = self?.presenter {
                            AlertPresenter.showError(error, from: presenter)
                        }
                    }
                }
            }
        }
    }

    /// Claims the one-time save points, then tells the user. `alreadySaved`
    /// is the server's "you already have it" answer to the save: the place
    /// was in a circle all along, so the wording is "already saved", never
    /// an error.
    private func confirmSaveReward(code: String, venue: RewardVenue, loading: UIAlertController,
                                   alreadySaved: PlaceDuplicate? = nil) {
        RewardsService.shared.confirmStickerSave(code: code) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let presenter = self?.presenter else { return }
                    let savedWhere: String = {
                        guard let duplicate = alreadySaved else { return "Place saved to your circle!" }
                        if let circle = duplicate.circleName {
                            return "\(venue.venueName) is already in your \"\(circle)\" circle."
                        }
                        return "\(venue.venueName) is already in your circles."
                    }()
                    switch result {
                    case .success(let save):
                        if let awarded = save.awarded {
                            self?.showWithMyRewards(
                                title: alreadySaved == nil
                                    ? "Place saved! +\(awarded.points) points"
                                    : "Already saved! +\(awarded.points) points",
                                message: "You now have \(save.venueBalance ?? save.balance) points at \(venue.venueName).",
                                from: presenter
                            )
                        } else if alreadySaved != nil {
                            AlertPresenter.showSuccess(title: "Already saved", message: savedWhere, from: presenter)
                        } else {
                            AlertPresenter.showSuccess(savedWhere, from: presenter)
                        }
                    case .failure:
                        // The place is saved either way — don't surface a reward hiccup as an error
                        AlertPresenter.showSuccess(savedWhere, from: presenter)
                    }
                }
            }
        }
    }

    // MARK: - Register card (visit + redemption)

    private func handleRegisterScan(_ scan: RewardScanData, code: String) {
        guard let presenter = presenter else { return }
        // After the points, offer to save the store if it isn't saved yet
        let offerSave: () -> Void = { [weak self] in
            guard scan.alreadySaved == false else { return }
            self?.offerSave(venue: scan.venue, code: code, bonus: scan.saveBonus)
        }

        // Per-store loyalty: points earned here spend here — every number in
        // this flow is the balance AT this shop (fallback: old-server payload)
        let balanceHere = scan.venueBalance ?? scan.balance

        // A store not on the loyalty program: no rewards wording at all (Wes,
        // 2026-10-30: never embarrass an owner who allows the window QR but
        // hasn't bought into rewards). The store page is open; offer the save.
        if scan.loyaltyPaused == true {
            offerSave()
            return
        }

        var title = scan.venue.venueName
        var message = ""
        if let awarded = scan.awarded {
            title = "+\(awarded.points) points at \(scan.venue.venueName)!"
            // First visit here: the balance is exactly this visit's points
            message = balanceHere <= awarded.points
                ? "Welcome! You now have \(balanceHere) points here."
                : "Thanks for coming back. You now have \(balanceHere) points here."
        } else if scan.alreadyEarnedToday == true {
            title = "Already earned today"
            message = "You've collected today's visit points at \(scan.venue.venueName). You have \(balanceHere) points here."
        } else if balanceHere > 0 {
            message = "You have \(balanceHere) points here."
        }

        let affordableOffers = (scan.offers ?? []).filter { $0.pointsCost <= balanceHere }

        guard !affordableOffers.isEmpty else {
            // The store's own terms (Wes, 2026-10-29): "75 more points for a
            // free coffee · about 3 more visits", the same line as Get Rewards
            if let next = RewardsAvailability.nextReward(scan.rewardDetails) {
                message += "\n\n\(RewardsAvailability.nextRewardLine(next))"
            }
            // OK, or straight to their rewards (Wes, 2026-10-30). The save
            // offer follows OK only: My Rewards leaves the store page.
            AlertPresenter.showAlert(title: title, message: message, actions: [
                (title: "My Rewards", style: .default, handler: { [weak self] in self?.openStoreRewards() }),
                (title: "OK", style: .cancel, handler: offerSave)
            ], from: presenter)
            return
        }

        message += "\n\nYou have enough points for a reward — redeem one right now at the counter?"

        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = affordableOffers.map { offer in
            (title: "\(offer.title) — \(offer.pointsCost) pts", style: .default, handler: { [weak self] in
                self?.redeemOffer(offer, venue: scan.venue)
            })
        }
        actions.append((title: "My Rewards", style: .default, handler: { [weak self] in self?.openStoreRewards() }))
        actions.append((title: "Not now", style: .default, handler: offerSave))

        AlertPresenter.showActionSheet(
            title: title,
            message: message,
            actions: actions,
            from: presenter
        )
    }

    /// A rewards result with two ways out: My Rewards (the Store Rewards
    /// screen) or OK, which carries on with `onOK` (Wes, 2026-10-30: saving a
    /// store from its QR code earns points too, so it gets the button as well)
    private func showWithMyRewards(title: String, message: String, from presenter: UIViewController, onOK: (() -> Void)? = nil) {
        AlertPresenter.showAlert(title: title, message: message, actions: [
            (title: "My Rewards", style: .default, handler: { [weak self] in self?.openStoreRewards() }),
            (title: "OK", style: .cancel, handler: { onOK?() })
        ], from: presenter)
    }

    /// The circle a store is saved in, scrolled to the store and flashed
    private func openSavedCircle(circleId: String, placeId: String) {
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let circle) = result else {
                    if case .failure(let error) = result, let presenter = self?.presenter { AlertPresenter.showError(error, from: presenter) }
                    return
                }
                let detail = CircleDetailViewController(circle: circle)
                detail.highlightPlaceId = placeId
                let tabNav = (self.presenter as? UITabBarController)?.selectedViewController as? UINavigationController
                if let nav = tabNav ?? self.presenter?.navigationController ?? (self.presenter as? UINavigationController) {
                    nav.pushViewController(detail, animated: true)
                } else if let presenter = self.presenter {
                    presenter.present(UINavigationController(rootViewController: detail), animated: true)
                }
            }
        }
    }

    /// The Store Rewards screen (every store's points and offers), pushed on
    /// the screen the scan result showed over
    private func openStoreRewards() {
        let hub = RewardsHubViewController()
        hub.initialTab = .rewards
        // Usually the tab bar: push onto the current tab, after the store page,
        // so Back returns to the store
        let tabNav = (presenter as? UITabBarController)?.selectedViewController as? UINavigationController
        if let nav = tabNav ?? presenter?.navigationController ?? (presenter as? UINavigationController) {
            nav.pushViewController(hub, animated: true)
        } else if let presenter {
            presenter.present(UINavigationController(rootViewController: hub), animated: true)
        }
    }

    private func redeemOffer(_ offer: RewardOffer, venue: RewardVenue) {
        guard let presenter = presenter else { return }
        let loading = AlertPresenter.showLoading(message: "Redeeming...", from: presenter)

        RewardsService.shared.redeemOffer(venueId: venue.venueId, offerId: offer.offerId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let presenter = self?.presenter else { return }
                    switch result {
                    case .success(let redeem):
                        let voucherVC = VoucherViewController(voucher: redeem.voucher)
                        voucherVC.modalPresentationStyle = .fullScreen
                        presenter.present(voucherVC, animated: true)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }
}

// MARK: - CircleSelectionDelegate

extension StickerRewardCoordinator: CircleSelectionDelegate {

    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle) {
        let venue = pendingVenue
        let code = pendingCode
        pendingVenue = nil
        pendingCode = nil

        controller.dismiss(animated: true) { [weak self] in
            guard let venue = venue, let code = code else { return }
            self?.savePlace(venue: venue, code: code, to: circle)
        }
    }

    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController) {
        pendingVenue = nil
        pendingCode = nil
        controller.dismiss(animated: true)
    }
}

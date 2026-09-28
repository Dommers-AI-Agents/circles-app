import UIKit
import CoreLocation

/// Drives the UX after a physical sticker QR code is scanned:
/// - window sticker → signup points + "save this place" flow (+ save points)
/// - register card  → visit points + offer redemption sheet → voucher screen
///
/// SceneDelegate calls `handleScannedCode` and this coordinator owns the rest,
/// including the CircleSelection delegate round-trip.
extension Notification.Name {
    /// A scan or a typed code may have changed the user's store points.
    /// Screens showing a balance refetch.
    static let rewardPointsDidChange = Notification.Name("rewardPointsDidChange")
}

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
        guard let presenter = presenter else { return }
        let loading = AlertPresenter.showLoading(message: "Checking sticker...", from: presenter)

        RewardsService.shared.scan(code: code) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let scan):
                        NotificationCenter.default.post(name: .rewardPointsDidChange, object: nil)
                        if scan.kind == "register" {
                            self?.handleRegisterScan(scan)
                        } else {
                            self?.handleWindowScan(scan, code: code)
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

    private func handleWindowScan(_ scan: RewardScanData, code: String) {
        guard let presenter = presenter else { return }

        var message = ""
        if let awarded = scan.awarded {
            message += "You earned \(awarded.points) store points for joining! 🎉\n\n"
        }

        if scan.alreadySaved == true {
            message += "\(scan.venue.venueName) is already in your circles. Come back and scan the register card with a purchase to keep earning!"
            AlertPresenter.showSuccess(title: "Welcome back!", message: message, from: presenter)
            return
        }

        message += "Save \(scan.venue.venueName) to one of your circles so you don't forget it — and earn 50 more store points."

        AlertPresenter.showConfirmation(
            title: "Don't forget \(scan.venue.venueName)!",
            message: message,
            confirmTitle: "Save & Earn",
            cancelTitle: "Not Now",
            from: presenter
        ) { [weak self] in
            self?.startSaveFlow(venue: scan.venue, code: code)
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
                    self?.confirmSaveReward(code: code, loading: loading)
                case .failure(let error):
                    loading.dismiss(animated: true) {
                        if let presenter = self?.presenter {
                            AlertPresenter.showError(error, from: presenter)
                        }
                    }
                }
            }
        }
    }

    private func confirmSaveReward(code: String, loading: UIAlertController) {
        RewardsService.shared.confirmStickerSave(code: code) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let presenter = self?.presenter else { return }
                    switch result {
                    case .success(let save):
                        if let awarded = save.awarded {
                            AlertPresenter.showSuccess(
                                title: "Place saved! +\(awarded.points) store points",
                                message: "You now have \(save.venueBalance ?? save.balance) points at this shop. Scan the register card with a purchase next time you visit to earn more.",
                                from: presenter
                            )
                        } else {
                            AlertPresenter.showSuccess("Place saved to your circle!", from: presenter)
                        }
                    case .failure:
                        // The place still saved — don't surface a reward hiccup as an error
                        AlertPresenter.showSuccess("Place saved to your circle!", from: presenter)
                    }
                }
            }
        }
    }

    // MARK: - Register card (visit + redemption)

    private func handleRegisterScan(_ scan: RewardScanData) {
        guard let presenter = presenter else { return }

        var title = scan.venue.venueName
        var message = ""

        // Per-store loyalty: points earned here spend here — every number in
        // this flow is the balance AT this shop (fallback: old-server payload)
        let balanceHere = scan.venueBalance ?? scan.balance

        if let awarded = scan.awarded {
            title = "+\(awarded.points) store points at \(scan.venue.venueName)!"
            message = "Thanks for coming back. You now have \(balanceHere) points here."
        } else if scan.alreadyEarnedToday == true {
            title = "Already earned today"
            message = "You've collected today's visit points at \(scan.venue.venueName). You have \(balanceHere) points here."
        }

        let affordableOffers = (scan.offers ?? []).filter { $0.pointsCost <= balanceHere }

        guard !affordableOffers.isEmpty else {
            if let cheapest = (scan.offers ?? []).map({ $0.pointsCost }).min() {
                message += "\n\nEarn \(cheapest - balanceHere > 0 ? "\(cheapest - balanceHere) more points here" : "more points") to unlock a reward."
            }
            AlertPresenter.showSuccess(title: title, message: message, from: presenter)
            return
        }

        message += "\n\nYou have enough points for a reward — redeem one right now at the counter?"

        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = affordableOffers.map { offer in
            (title: "\(offer.title) — \(offer.pointsCost) pts", style: .default, handler: { [weak self] in
                self?.redeemOffer(offer, venue: scan.venue)
            })
        }
        actions.append((title: "Not now", style: .default, handler: {}))

        AlertPresenter.showActionSheet(
            title: title,
            message: message,
            actions: actions,
            from: presenter
        )
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

import UIKit
import CoreLocation

/// Drives the UX after a physical sticker QR code is scanned:
/// - window sticker → signup points + "save this place" flow (+ save points)
/// - register card  → visit points + offer redemption sheet → voucher screen
///
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
        guard let presenter = presenter else { return }
        let loading = AlertPresenter.showLoading(message: "Checking sticker...", from: presenter)

        RewardsService.shared.scan(code: code) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let scan):
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

    // MARK: - Window sticker (discovery / signup / save)

    private func handleWindowScan(_ scan: RewardScanData, code: String) {
        guard let presenter = presenter else { return }

        var message = ""
        if let awarded = scan.awarded {
            message += "You earned \(awarded.points) points for joining! 🎉\n\n"
        }

        if scan.alreadySaved == true {
            message += "\(scan.venue.venueName) is already in your circles. Come back and scan the register card with a purchase to keep earning!"
            AlertPresenter.showSuccess(title: "Welcome back!", message: message, from: presenter)
            return
        }

        message += "Save \(scan.venue.venueName) to one of your circles so you don't forget it — and earn 50 more points."

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
                                title: "Place saved! +\(awarded.points) points",
                                message: "You now have \(save.balance) points. Scan the register card with a purchase next time you visit to earn more.",
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

        if let awarded = scan.awarded {
            title = "+\(awarded.points) points at \(scan.venue.venueName)!"
            message = "Thanks for coming back. You now have \(scan.balance) points."
        } else if scan.alreadyEarnedToday == true {
            title = "Already earned today"
            message = "You've collected today's visit points at \(scan.venue.venueName). You have \(scan.balance) points."
        }

        let affordableOffers = (scan.offers ?? []).filter { $0.pointsCost <= scan.balance }

        guard !affordableOffers.isEmpty else {
            if let cheapest = (scan.offers ?? []).map({ $0.pointsCost }).min() {
                message += "\n\nEarn \(cheapest - scan.balance > 0 ? "\(cheapest - scan.balance) more points" : "more points") to unlock a reward here."
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

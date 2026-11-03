import UIKit

/// Shared offer-redemption flow: confirm → redeem → present the voucher.
/// Used by the Rewards page, the place-page rewards section and the scan
/// coordinator so every screen behaves identically. The first reward at a
/// store asks to share name, photo and email with it (Wes, 2026-11-02:
/// rewards are claimed by name — regulars don't mind, cheaters do).
extension UIViewController {

    func confirmAndRedeemOffer(_ offer: RewardOffer, venueId: String, venueName: String,
                               onSuccess: ((RewardRedeemData) -> Void)? = nil) {
        showConfirmation(
            title: "Redeem \(offer.title)?",
            message: "This uses \(offer.pointsCost) of your points at \(venueName) and opens a 15-minute ticket to show at the counter. If it isn\u{2019}t used in time, your points come back.",
            confirmTitle: "Redeem"
        ) { [weak self] in
            self?.redeemOffer(offer, venueId: venueId, venueName: venueName, onSuccess: onSuccess)
        }
    }

    /// Redeem without the confirm step (the caller already asked)
    func redeemOffer(_ offer: RewardOffer, venueId: String, venueName: String,
                     onSuccess: ((RewardRedeemData) -> Void)? = nil) {
        let loading = AlertPresenter.showLoading(message: "Redeeming...", from: self)

        RewardsService.shared.redeemOffer(venueId: venueId, offerId: offer.offerId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let redeem):
                        let voucherVC = VoucherViewController(voucher: redeem.voucher)
                        voucherVC.modalPresentationStyle = .fullScreen
                        self.present(voucherVC, animated: true)
                        onSuccess?(redeem)
                    case .failure(let error):
                        if (error as? APIError)?.serverCode == "share_required" {
                            self.askToShare(venueId: venueId, venueName: venueName) { [weak self] in
                                self?.redeemOffer(offer, venueId: venueId, venueName: venueName, onSuccess: onSuccess)
                            }
                        } else {
                            self.showError(error)
                        }
                    }
                }
            }
        }
    }

    /// Once per store: a terms-style checkbox to let the store see the name,
    /// photo and email already on the FavCircles profile (ShareWithStoreViewController)
    private func askToShare(venueId: String, venueName: String, then retry: @escaping () -> Void) {
        let sheet = ShareWithStoreViewController(venueName: venueName) { [weak self] in
            RewardsService.shared.shareWithStore(venueId: venueId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: retry()
                    case .failure(let error): self?.showError(error)
                    }
                }
            }
        }
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }
}

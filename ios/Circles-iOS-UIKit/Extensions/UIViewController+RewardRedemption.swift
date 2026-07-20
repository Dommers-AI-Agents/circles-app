import UIKit

/// Shared offer-redemption flow: confirm → redeem → present the voucher.
/// Used by the Rewards page and the place-page rewards section so both
/// screens behave identically.
extension UIViewController {

    func confirmAndRedeemOffer(_ offer: RewardOffer, venueId: String, venueName: String,
                               onSuccess: ((RewardRedeemData) -> Void)? = nil) {
        showConfirmation(
            title: "Redeem \(offer.title)?",
            message: "This uses \(offer.pointsCost) points and shows a 5-minute voucher — redeem it at the counter at \(venueName)."
        ) { [weak self] in
            self?.redeemOffer(offer, venueId: venueId, onSuccess: onSuccess)
        }
    }

    private func redeemOffer(_ offer: RewardOffer, venueId: String,
                             onSuccess: ((RewardRedeemData) -> Void)?) {
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
                        self.showError(error)
                    }
                }
            }
        }
    }
}

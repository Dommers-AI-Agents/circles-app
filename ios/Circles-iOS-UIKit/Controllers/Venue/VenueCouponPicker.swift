import UIKit

/// "Which coupon?" for a win-back or a Bring-a-friend link (2026-11-14): the
/// store's live coupons as a sheet, plus "No coupon". Loads the list itself.
enum VenueCouponPicker {

    /// `onPick` gets the chosen coupon's id, or nil for none
    static func present(venueId: String, current: String?, from presenter: UIViewController, sourceView: UIView? = nil,
                        onPick: @escaping (String?, VenueCoupon?) -> Void) {
        let loading = AlertPresenter.showLoading(message: "Loading your coupons…", from: presenter)
        RewardsService.shared.fetchCoupons(venueId: venueId) { result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let coupons):
                        let live = coupons.filter { $0.state == "live" }
                        guard !live.isEmpty else {
                            AlertPresenter.showInfo(title: "No live coupons", message: StoreCouponCopy.noneToPick, from: presenter)
                            return
                        }
                        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = live.map { coupon in
                            (title: coupon.couponId == current ? "\(coupon.title) ✓" : coupon.title, style: .default, handler: { onPick(coupon.couponId, coupon) })
                        }
                        actions.append((title: current == nil ? "No coupon ✓" : "No coupon", style: .default, handler: { onPick(nil, nil) }))
                        actions.append((title: "Cancel", style: .cancel, handler: {}))
                        AlertPresenter.showActionSheet(title: "Which coupon?", actions: actions, from: presenter, sourceView: sourceView)
                    case .failure(let error):
                        presenter.showError(error)
                    }
                }
            }
        }
    }

    /// The row's words for the chosen coupon, when the list is known
    static func title(for couponId: String?, in coupons: [VenueCoupon]) -> String {
        guard let couponId else { return "None" }
        return coupons.first { $0.couponId == couponId }?.title ?? "A coupon that's gone"
    }
}

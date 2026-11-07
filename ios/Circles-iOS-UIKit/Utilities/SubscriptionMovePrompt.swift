import UIKit

/// The phone's App Store subscription is on another FavCircles account (one
/// subscription, one account — Wes, 2026-11-07). Says where it is and offers
/// to move it here; asked once per account (a restore asks again).
enum SubscriptionMovePrompt {
    private static func askedKey(_ userId: String) -> String { "subscriptionMove.asked.\(userId)" }

    static func offer(emailHint: String?, force: Bool = false, move: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let userId = AuthService.shared.getUserId() else { return }
            if !force && UserDefaults.standard.bool(forKey: askedKey(userId)) { return }
            guard let top = topViewController() else { return }
            UserDefaults.standard.set(true, forKey: askedKey(userId))
            AlertPresenter.showAlert(
                title: "Your subscription is on another account",
                message: SubscriptionMoveCopy.message(emailHint: emailHint),
                actions: [
                    (title: "Move it here", style: .default, handler: move),
                    (title: "Not now", style: .cancel, handler: {})
                ],
                from: top
            )
        }
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// The words for it. Pure.
enum SubscriptionMoveCopy {
    static func message(emailHint: String?) -> String {
        let account = emailHint.map { "your other FavCircles account (\($0))" } ?? "your other FavCircles account"
        return "The App Store subscription on this iPhone is on \(account). Sign in there to use it, or move it to this account. Moving it takes Premium off the other account."
    }
}

import UIKit

/// Store QR (sticker) codes and the App Clip handoff: adopt the clip's
/// session, redeem a scanned code now or once signed in, and the
/// "Rewards Waiting!" prompt. Owned by SceneDelegate.
@MainActor
final class RewardCodeHandler: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    // MARK: - App Clip Handoff

    private static let clipHandledStickerCodeKey = "clipHandledStickerCode"

    /// Adopts credentials the App Clip left in the shared keychain mailbox
    /// (see ClipKeychain.swift in the Circles-Clip target and
    /// KeychainService.adoptClipCredentialsIfPresent).
    func adoptAppClipSessionIfPresent() {
        guard let result = KeychainService.shared.adoptClipCredentialsIfPresent() else { return }

        // Clip users never saw the Safari landing page, so the one-shot
        // pasteboard check would just be a pointless paste-permission prompt
        UserDefaults.standard.set(true, forKey: "hasCheckedPasteboardForStickerCode")

        if let handledCode = result.handledStickerCode {
            // The clip already redeemed this code — remember it so the
            // invocation URL replay on first launch doesn't re-run the reward UX
            UserDefaults.standard.set(handledCode, forKey: Self.clipHandledStickerCodeKey)
        }
        if let email = result.unconfirmedEmail {
            // Signed up in the clip with just an email: ask them to keep the
            // account (Face ID or confirm the email) once they're in
            AccountSafetyPrompt.stash(email: email)
        }
        if let welcome = result.welcome {
            // Their first look at the app is that store's page with what they
            // earned and what the points buy (Wes, 2026-10-31)
            ClipWelcome.stash(welcome)
        }
        if let pendingCode = result.pendingStickerCode {
            // The clip's scan call failed — the normal pending-code flow
            // (redeemPendingStickerCodeIfNeeded) completes the award
            RewardsService.shared.savePendingStickerCode(pendingCode)
        }

        if AuthService.shared.isLoggedIn {
            notifyClipInstallConverted()
        }
        Logger.info("📎 App Clip session adoption: adopted=\(result.adopted)")
    }

    /// Tells the backend this user converted from clip to full app (funnel
    /// analytics). Idempotent server-side and a no-op for non-clip accounts —
    /// safe to fire-and-forget.
    private func notifyClipInstallConverted() {
        APIService.shared.request(
            endpoint: "clip/install-converted",
            method: .post,
            body: nil,
            requiresAuth: true
        ) { (result: Result<SimpleResponse, APIError>) in
            switch result {
            case .success:
                Logger.debug("📎 Clip install conversion recorded")
            case .failure(let error):
                Logger.warning("📎 Clip install conversion failed: \(error)")
            }
        }
    }

    // MARK: - Sticker Code Handling

    /// A "Rewards Waiting!" prompt that couldn't show yet (see presentRewardsWaitingPrompt)
    var rewardsPromptOwed = false

    func handleStickerCode(_ code: String) {
        Logger.debug("📱 SceneDelegate: handleStickerCode called with code: \(code)")

        // First launch after a clip install re-delivers the invocation URL as a
        // user activity; the clip already redeemed this code (backend award is
        // idempotent regardless — this guard is just to skip the duplicate UX)
        if code == UserDefaults.standard.string(forKey: Self.clipHandledStickerCodeKey) {
            UserDefaults.standard.removeObject(forKey: Self.clipHandledStickerCodeKey)
            Logger.debug("📱 SceneDelegate: code \(code) already redeemed in App Clip — skipping")
            return
        }

        // If the user is not logged in, save the code — it's redeemed right
        // after signup/login via runPostLaunchSideEffects (all auth routes)
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, saving sticker code for later")
            RewardsService.shared.savePendingStickerCode(code)
            presentRewardsWaitingPrompt()
            return
        }

        // A cold launch from the QR card's Open button delivers the link
        // before the window is showing; the scan was silently dropped and
        // the user had to scan again. Keep it pending until the tab bar is
        // up and the app is active (sceneDidBecomeActive / post-launch).
        guard UIApplication.shared.applicationState == .active,
              window?.rootViewController is CirclesTabBarController else {
            RewardsService.shared.savePendingStickerCode(code)
            return
        }
        StickerRewardCoordinator.shared.handleScannedCode(code)
    }

    /// "Rewards Waiting!" for a scan before there's an account. A fresh
    /// install delivers the QR link while the launch root is still up; an
    /// alert presented there was orphaned when the login screen replaced the
    /// root a moment later, and its buttons stopped responding (Wes's iPad,
    /// 2026-10-29). So wait until the login screen is the root and the scene
    /// is active, then present on whatever is on top. Sign Up opens Create
    /// Account; the code stays pending and is redeemed after signup.
    func presentRewardsWaitingPrompt(attempt: Int = 0) {
        // Owed until shown: if the retries below run out (something else
        // presenting for a long time), sceneDidBecomeActive asks again
        rewardsPromptOwed = true
        guard !AuthService.shared.isLoggedIn else { rewardsPromptOwed = false; return }
        let authNav = window?.rootViewController as? UINavigationController
        let loginReady = authNav?.viewControllers.first is LoginViewController
        // Not gated on the app being active: a system alert over a fresh
        // install can keep it inactive with no later activation, and the
        // freeze came from a root swap, not from presenting while inactive
        guard loginReady,
              let presenter = topViewController(), presenter.view.window != nil,
              !(presenter is UIAlertController), !presenter.isBeingPresented, !presenter.isBeingDismissed else {
            // The login root animates in over ~0.3 s; keep trying for ~10 s,
            // then sceneDidBecomeActive asks again
            guard attempt < 40 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentRewardsWaitingPrompt(attempt: attempt + 1)
            }
            return
        }
        rewardsPromptOwed = false
        AlertPresenter.showConfirmation(
            title: "Rewards Waiting! 🎁",
            message: "Sign up for FavCircles to save this place and earn store points you can use on your next visit.",
            confirmTitle: "Sign Up",
            cancelTitle: "Later",
            from: presenter
        ) {
            // Create Account, unless they're already on it
            guard let nav = authNav, !(nav.topViewController is RegisterViewController) else { return }
            nav.pushViewController(RegisterViewController(), animated: true)
        }
    }

    /// Deferred deep link for store QR codes: the App Store install wipes any
    /// link context, so the sticker landing page copies
    /// "favcircles-sticker:<CODE>" to the clipboard when the visitor taps
    /// Get the App. On the very first activation after install we check the
    /// pasteboard once and stash the code so the normal pending-sticker
    /// redemption picks it up after signup. One-shot by design — the paste
    /// permission prompt must not become a recurring launch experience.
    func captureStickerCodeFromPasteboardIfFirstLaunch() {
        let checkedKey = "hasCheckedPasteboardForStickerCode"
        guard !UserDefaults.standard.bool(forKey: checkedKey) else { return }
        UserDefaults.standard.set(true, forKey: checkedKey)

        // hasStrings doesn't trigger the paste permission prompt; reading
        // .string does — which is why this whole check is one-shot
        guard UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string,
              let match = text.range(of: #"favcircles-sticker:([A-Z0-9]{4,16})"#, options: .regularExpression) else {
            return
        }

        let code = String(text[match].dropFirst("favcircles-sticker:".count))
        Logger.debug("📱 SceneDelegate: Found sticker code on pasteboard from pre-install scan: \(code)")

        // Consume it so a later launch (or another app) doesn't see it
        UIPasteboard.general.items = []

        RewardsService.shared.savePendingStickerCode(code)
        if AuthService.shared.isLoggedIn {
            redeemPendingStickerCodeIfNeeded()
        }
        // Not logged in: redeemPendingStickerCodeIfNeeded runs after every
        // auth route via runPostLaunchSideEffects
    }

    /// Redeems a sticker code that was scanned before the user was logged in.
    /// Runs for every auth route (email + social), unlike the referral replay
    /// which only covers email signup.
    func redeemPendingStickerCodeIfNeeded() {
        // Splash or onboarding still up: the post-launch pass picks it up
        guard AuthService.shared.isLoggedIn,
              window?.rootViewController is CirclesTabBarController else { return }
        if let welcome = ClipWelcome.takeStashed() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                StickerRewardCoordinator.shared.showClipWelcome(welcome)
            }
        } else if let email = AccountSafetyPrompt.stashedEmail, let top = topViewController() {
            // No store welcome (the generic code): ask on its own
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AccountSafetyPrompt.present(email: email, from: top)
            }
        }
        guard let code = RewardsService.shared.getPendingStickerCode() else { return }

        RewardsService.shared.clearPendingStickerCode()

        // Already redeemed inside the App Clip — nothing left to do
        if code == UserDefaults.standard.string(forKey: Self.clipHandledStickerCodeKey) {
            UserDefaults.standard.removeObject(forKey: Self.clipHandledStickerCodeKey)
            Logger.debug("📱 SceneDelegate: pending code \(code) already redeemed in App Clip — skipping")
            return
        }
        Logger.debug("📱 SceneDelegate: Redeeming pending sticker code: \(code)")

        // Give the main interface (and any onboarding modals) a moment to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StickerRewardCoordinator.shared.handleScannedCode(code)
        }
    }
}

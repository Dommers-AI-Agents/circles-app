import UIKit

/// After an instant App Clip sign-up (just an email, nothing confirmed —
/// Wes, 2026-10-31), the app offers Face ID (a passkey) so signing back in
/// is a glance. Shown in the clip welcome sheet, or on its own when there's
/// no store welcome.
///
/// Asked at most twice, at least three days apart (Wes, 2026-11-12: a new
/// tester was interrupted three times in one first session). There is no
/// "confirm your email" option any more: an emailed code signs anyone in to
/// their account whether or not it was confirmed, and that first code
/// confirms it, so asking up front gave the person nothing.
enum AccountSafetyPrompt {

    private static let emailKey = "accountSafety.unconfirmedEmail"
    private static let askedKey = "accountSafety.timesAsked"
    private static let lastAskedKey = "accountSafety.lastAskedAt"
    static let maxAsks = 2
    static let minGap: TimeInterval = 3 * 24 * 3600

    /// Pure pacing rule: never more than `maxAsks`, never twice within `minGap`
    static func shouldAsk(timesAsked: Int, lastAskedAt: Date?, now: Date = Date()) -> Bool {
        guard timesAsked < maxAsks else { return false }
        guard let last = lastAskedAt else { return true }
        return now.timeIntervalSince(last) >= minGap
    }

    static func stash(email: String) {
        UserDefaults.standard.set(email, forKey: emailKey)
        UserDefaults.standard.set(0, forKey: askedKey)
        UserDefaults.standard.removeObject(forKey: lastAskedKey)
    }

    /// The email still waiting, if it's time to ask again
    /// …and only for the account it was stashed for (2026-11-07)
    static var stashedEmail: String? {
        let defaults = UserDefaults.standard
        guard shouldAsk(timesAsked: defaults.integer(forKey: askedKey),
                        lastAskedAt: defaults.object(forKey: lastAskedKey) as? Date),
              let email = defaults.string(forKey: emailKey),
              PasskeyAccountMatch.isForSignedInAccount(stashedEmail: email,
                                                       signedInEmail: AuthService.shared.currentUser?.email) else { return nil }
        return email
    }

    static func markAsked() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: askedKey) + 1, forKey: askedKey)
        UserDefaults.standard.set(Date(), forKey: lastAskedKey)
    }

    static func done() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: askedKey)
        UserDefaults.standard.removeObject(forKey: lastAskedKey)
    }

    /// The stand-alone ask (no store welcome sheet to put it in)
    /// `then` runs once they're finished with it, whichever way they went
    /// (the first run continues from there)
    static func present(email: String, from presenter: UIViewController, then: (() -> Void)? = nil) {
        markAsked()
        AlertPresenter.showAlert(
            title: "Sign in with Face ID?",
            message: "Set up Face ID for \(email) and signing in is a glance, with no codes to type.",
            actions: [
                (title: "Set Up Face ID", style: .default, handler: { setUpFaceID(email: email, from: presenter, then: then) }),
                (title: "Not Now", style: .cancel, handler: { then?() })
            ],
            from: presenter
        )
    }

    /// A passkey for this account: Face ID signs them in from now on
    static func setUpFaceID(email: String, from presenter: UIViewController, then: (() -> Void)? = nil) {
        PasskeyAuthService.shared.addPasskeyForCurrentUser(accountName: email, presentationAnchor: presenter.view.window) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    done()
                    AlertPresenter.showSuccess(title: "You're all set", message: "Sign in with Face ID from now on.", from: presenter) { then?() }
                case .failure(let error):
                    // Closing Face ID's sheet isn't worth an alert (the
                    // service reports it as .canceled, not ASAuthorization's 1001)
                    if case PasskeyAuthService.PasskeyError.canceled? = error as? PasskeyAuthService.PasskeyError { then?(); return }
                    if (error as NSError).code == 1001 { then?(); return }
                    AlertPresenter.showError(message: FriendlyError.message(for: error), from: presenter) { then?() }
                }
            }
        }
    }
}

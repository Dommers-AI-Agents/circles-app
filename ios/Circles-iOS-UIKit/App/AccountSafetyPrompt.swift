import UIKit

/// After an instant App Clip sign-up (just an email, nothing confirmed —
/// Wes, 2026-10-31), the app asks them to keep the account: set up Face ID
/// (a passkey) or confirm the email with a 6-digit code. Either one means
/// they can always sign back in. Shown in the clip welcome sheet, or on its
/// own when there's no store welcome; asked up to three launches.
enum AccountSafetyPrompt {

    private static let emailKey = "accountSafety.unconfirmedEmail"
    private static let askedKey = "accountSafety.timesAsked"
    private static let maxAsks = 3

    static func stash(email: String) {
        UserDefaults.standard.set(email, forKey: emailKey)
        UserDefaults.standard.set(0, forKey: askedKey)
    }

    /// The email still waiting, if we haven't asked too many times
    static var stashedEmail: String? {
        guard UserDefaults.standard.integer(forKey: askedKey) < maxAsks else { return nil }
        return UserDefaults.standard.string(forKey: emailKey)
    }

    static func markAsked() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: askedKey) + 1, forKey: askedKey)
    }

    static func done() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: askedKey)
    }

    /// The stand-alone ask (no store welcome sheet to put it in)
    static func present(email: String, from presenter: UIViewController) {
        markAsked()
        AlertPresenter.showAlert(
            title: "Keep your points safe",
            message: "You joined with \(email). Set up Face ID so you can always sign back in, or confirm your email.",
            actions: [
                (title: "Set Up Face ID", style: .default, handler: { setUpFaceID(email: email, from: presenter) }),
                (title: "Confirm Email", style: .default, handler: { confirmEmail(email, from: presenter) }),
                (title: "Not Now", style: .cancel, handler: {})
            ],
            from: presenter
        )
    }

    /// A passkey for this account: Face ID signs them in from now on
    static func setUpFaceID(email: String, from presenter: UIViewController) {
        PasskeyAuthService.shared.addPasskeyForCurrentUser(accountName: email, presentationAnchor: presenter.view.window) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    done()
                    AlertPresenter.showSuccess(title: "You're all set", message: "Sign in with Face ID from now on.", from: presenter)
                case .failure(let error):
                    // Closing Face ID's sheet isn't worth an alert
                    if (error as NSError).code == 1001 { return }
                    AlertPresenter.showError(error, from: presenter)
                }
            }
        }
    }

    /// Emails a code to their own address, then asks for it
    static func confirmEmail(_ email: String, from presenter: UIViewController) {
        let loading = AlertPresenter.showLoading(message: "Sending a code\u{2026}", from: presenter)
        APIService.shared.request(endpoint: "auth/email-code/start", method: .post, body: ["email": email], requiresAuth: false) { (result: Result<SimpleResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success:
                        askForCode(email: email, from: presenter)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }

    private static func askForCode(email: String, from presenter: UIViewController) {
        AlertPresenter.showTextInput(
            title: "Check your email",
            message: "Enter the 6-digit code we sent to \(email).",
            placeholder: "6-digit code",
            keyboardType: .numberPad,
            autocapitalization: .none,
            confirmTitle: "Confirm",
            from: presenter
        ) { text in
            let code = (text ?? "").filter(\.isNumber)
            guard code.count == 6 else { return }
            APIService.shared.request(endpoint: "auth/email-code/confirm", method: .post, body: ["code": code], requiresAuth: true) { (result: Result<SimpleResponse, APIError>) in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        done()
                        AlertPresenter.showSuccess(title: "Email confirmed", message: "Your account and points are safe.", from: presenter)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }
}

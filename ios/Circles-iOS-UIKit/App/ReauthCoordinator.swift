import UIKit

/// Keeping the session: revalidate an expired token in place, offer Face ID
/// sign-in after a password login, and when the session can't be
/// revalidated, log out and try to sign back in
/// silently (Google session restore, saved credentials, Face ID), or say
/// the session expired. Owned by SceneDelegate.
@MainActor
final class ReauthCoordinator: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    /// Tries to refresh an expired token in place. Logs out ONLY when the server
    /// definitively rejects the token; transient network failures keep the session
    /// so the user isn't kicked to the login screen over a connectivity blip.
    func revalidateExpiredTokenNonDestructively() {
        AuthService.shared.refreshToken { [weak self] result in
            if case .failure(let error) = result {
                if AuthService.isDefinitiveAuthFailure(error) {
                    Logger.info("Token definitively rejected, starting re-auth flow")
                    DispatchQueue.main.async { self?.handleAutoLogoutAndReauth() }
                } else {
                    Logger.warning("Transient token refresh failure, keeping session: \(error)")
                    // API-level 401 handling covers the case where the token is truly dead
                }
            }
        }
    }

    /// After a password login (LoginViewController sets pendingPasskeyOfferEmail),
    /// offer to enroll a passkey once per account so they can go passwordless.
    func offerPasskeySetupIfPending() {
        guard AuthService.shared.isLoggedIn,
              let email = UserDefaults.standard.string(forKey: "pendingPasskeyOfferEmail"),
              !email.isEmpty else { return }
        // Consume the pending flag regardless of outcome
        UserDefaults.standard.removeObject(forKey: "pendingPasskeyOfferEmail")

        // Only nudge once per account
        var offered = UserDefaults.standard.stringArray(forKey: "passkeyOfferedEmails") ?? []
        guard !offered.contains(email) else { return }
        offered.append(email)
        UserDefaults.standard.set(offered, forKey: "passkeyOfferedEmails")

        // Let the home screen settle before presenting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self,
                  let top = self.topViewController(),
                  top.presentedViewController == nil else { return }
            AlertPresenter.showConfirmation(
                title: "Set up Face ID sign-in?",
                message: "Skip the password next time — sign in with Face ID or your passcode.",
                confirmTitle: "Set Up",
                cancelTitle: "Not Now",
                from: top
            ) { [weak self] in
                PasskeyAuthService.shared.addPasskeyForCurrentUser(accountName: email, presentationAnchor: self?.window) { result in
                    if case .success = result {
                        DispatchQueue.main.async {
                            if let top = self?.topViewController() {
                                AlertPresenter.showSuccess("You're all set — Face ID next time.", from: top)
                            }
                        }
                    }
                    // Failure/cancel: silent; the row in Settings remains available
                }
            }
        }
    }

    /// Handles automatic logout after max retry attempts and attempts to re-authenticate for social auth users
    func handleAutoLogoutAndReauth() {
        Logger.debug("🔐 SceneDelegate: Handling auto-logout and re-authentication")

        // Get the auth provider before logging out
        let authProvider = AuthService.shared.getAuthProvider()
        Logger.debug("🔐 SceneDelegate: Auth provider: \(authProvider ?? "none")")

        // Show a loading message
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if we can attempt silent re-authentication
            if let provider = authProvider, provider == "email" {
                // For email/password users, check if biometric is enabled
                if BiometricAuthService.shared.isBiometricLoginEnabled {
                    Logger.debug("🔐 SceneDelegate: Email user with biometric enabled - attempting biometric re-auth")
                    self.attemptEmailBiometricReauth()
                } else {
                    // No biometric - try silent re-login with saved credentials
                    // before falling back to the login screen
                    Logger.debug("🔐 SceneDelegate: Email/password user - attempting silent re-login")
                    self.attemptSilentCredentialReauth()
                }
            } else if let provider = authProvider {
                // For social auth providers, attempt silent re-authentication
                self.attemptSilentReauth(provider: provider)
            } else {
                // No auth provider, just logout
                Logger.debug("🔐 SceneDelegate: No auth provider - logging out")
                AuthService.shared.logout { success in
                    if success {
                        Logger.debug("🔐 SceneDelegate: Logout successful, showing login screen")
                    }
                }
            }
        }
    }

    /// Attempts silent re-authentication for social auth providers
    private func attemptSilentReauth(provider: String) {
        Logger.debug("🔐 SceneDelegate: Attempting silent re-authentication for provider: \(provider)")

        // Show a temporary loading message
        var loadingAlert: UIAlertController?
        if let topController = topViewController() {
            loadingAlert = AlertPresenter.showLoading(
                message: "Please wait while we refresh your session...",
                from: topController
            )
        }

        // Logout first to clear expired session
        AuthService.shared.logout { [weak self] success in
            guard let self = self else { return }

            // Dismiss loading alert, then continue (the next step may present
            // its own alert, so wait for the dismissal to finish)
            DispatchQueue.main.async {
                let continueReauth = {
                    switch provider {
                    case "google":
                        self.attemptGoogleReauth()
                    case "apple":
                        self.attemptAppleReauth()
                    case "facebook":
                        self.attemptFacebookReauth()
                    default:
                        Logger.debug("🔐 SceneDelegate: No silent re-auth available for provider: \(provider)")
                        // Just show login screen
                    }
                }
                if let loadingAlert = loadingAlert {
                    loadingAlert.dismiss(animated: true, completion: continueReauth)
                } else {
                    continueReauth()
                }
            }
        }
    }

    /// Attempts to silently re-authenticate with Google
    private func attemptGoogleReauth() {
        Logger.debug("🔐 SceneDelegate: Attempting Google re-authentication")

        // Show a loading indicator
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var loadingAlert: UIAlertController?
            if let topController = self.topViewController() {
                loadingAlert = AlertPresenter.showLoading(
                    message: "Signing you back in...",
                    from: topController
                )
            }

            SocialAuthService.shared.restoreGoogleSignInSession { [weak self] result in
                // Dismiss loading alert
                DispatchQueue.main.async {
                    let handleResult = {
                        switch result {
                        case .success:
                            Logger.debug("🔐 SceneDelegate: Google session restored and logged in successfully")
                            // The session is restored and login was triggered
                            // The auth state listener will handle showing the main interface

                        case .failure(let error):
                            Logger.debug("🔐 SceneDelegate: Google re-auth failed: \(error)")
                            // Show a message to the user
                            self?.showReauthFailedMessage()
                        }
                    }
                    if let loadingAlert = loadingAlert {
                        loadingAlert.dismiss(animated: true, completion: handleResult)
                    } else {
                        handleResult()
                    }
                }
            }
        }
    }

    /// Attempts to silently re-authenticate with Apple
    private func attemptAppleReauth() {
        Logger.debug("🔐 SceneDelegate: Apple re-auth not implemented - showing login screen")
        // Apple Sign In doesn't support silent re-authentication
        // User needs to manually sign in again
        showReauthFailedMessage()
    }

    /// Attempts to silently re-authenticate with Facebook
    private func attemptFacebookReauth() {
        Logger.debug("🔐 SceneDelegate: Facebook re-auth not implemented - showing login screen")
        // Facebook re-auth would need to check if there's an active token
        // For now, just show login screen
        showReauthFailedMessage()
    }

    /// Attempts a silent re-login with credentials saved in the keychain (no biometric required)
    private func attemptSilentCredentialReauth() {
        guard let credentials = KeychainManager.shared.retrieveCredentials() else {
            Logger.debug("🔐 SceneDelegate: No saved credentials - logging out")
            AuthService.shared.logout { success in
                if success {
                    Logger.debug("🔐 SceneDelegate: Logout successful, showing login screen")
                }
            }
            return
        }

        Logger.debug("🔐 SceneDelegate: Found saved credentials, attempting silent re-login")
        AuthService.shared.login(email: credentials.email, password: credentials.password) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Logger.debug("🔐 SceneDelegate: Silent re-login successful")
                    // Auth state listener will refresh the UI
                case .failure(let error):
                    Logger.debug("🔐 SceneDelegate: Silent re-login failed: \(error) - logging out")
                    AuthService.shared.logout { _ in }
                    self?.showReauthFailedMessage()
                }
            }
        }
    }

    /// Attempts to re-authenticate email/password user with biometric
    private func attemptEmailBiometricReauth() {
        Logger.debug("🔐 SceneDelegate: Attempting email biometric re-authentication")

        // Show a loading message
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var loadingAlert: UIAlertController?
            if let topController = self.topViewController() {
                loadingAlert = AlertPresenter.showLoading(
                    message: BiometricAuthService.shared.getBiometricPrompt(),
                    from: topController
                )
            }

            let finish: (@escaping () -> Void) -> Void = { action in
                DispatchQueue.main.async {
                    if let loadingAlert = loadingAlert {
                        loadingAlert.dismiss(animated: true, completion: action)
                    } else {
                        action()
                    }
                }
            }

            // Logout first to clear expired session
            AuthService.shared.logout { [weak self] success in
                guard let self = self else { return }

                // The biometric keychain read blocks while Face ID is showing,
                // so keep it off the main thread
                DispatchQueue.global(qos: .userInitiated).async {
                    let credentials = KeychainManager.shared.retrieveCredentialsWithBiometric(
                        reason: BiometricAuthService.shared.getBiometricPrompt()
                    )

                    guard let credentials = credentials else {
                        Logger.debug("🔐 SceneDelegate: Failed to retrieve credentials with biometric")
                        finish {
                            self.showReauthFailedMessage()
                        }
                        return
                    }

                    Logger.debug("🔐 SceneDelegate: Retrieved credentials with biometric, attempting login")
                    AuthService.shared.login(email: credentials.email, password: credentials.password) { [weak self] result in
                        finish {
                            switch result {
                            case .success:
                                Logger.debug("🔐 SceneDelegate: Email biometric re-auth successful")
                                // Auth state listener will handle showing main interface

                            case .failure(let error):
                                Logger.debug("🔐 SceneDelegate: Email biometric re-auth failed: \(error)")
                                self?.showReauthFailedMessage()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Shows a message when automatic re-authentication fails
    private func showReauthFailedMessage() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let topController = self.topViewController() else { return }

            AlertPresenter.showError(
                title: "Session Expired",
                message: "Your session has expired. Please log in again to continue.",
                from: topController
            )
        }
    }
}

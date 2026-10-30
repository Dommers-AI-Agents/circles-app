import UIKit

struct ShareValidationResponse: Codable {
    let success: Bool
    let isValid: Bool
    let accessLevel: String?
    let message: String?
}

/// Links that carry an invitation: a shared circle (with or without a
/// share token), a connection invite and a referral code. Owned by
/// SceneDelegate; navigation goes back through its DeepLinkCoordinator.
@MainActor
final class InviteLinkHandler: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    func handleSharedCircleWithToken(circleId: String, shareToken: String) {
        // First, validate the share token with the backend
        // This doesn't require authentication
        APIService.shared.request(
            endpoint: "circles/share/validate",
            method: .post,
            body: ["circleId": circleId, "shareToken": shareToken],
            requiresAuth: false
        ) { [weak self] (result: Result<ShareValidationResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.isValid {
                        // Try to fetch the circle details to check if it's public
                        CircleService.shared.fetchCircleByIdPublic(id: circleId) { circleResult in
                            DispatchQueue.main.async {
                                switch circleResult {
                                case .success(let circle):
                                    // Circle is public, allow viewing even without login
                                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController,
                                       let navController = tabBarController.selectedViewController as? UINavigationController {
                                        let detailVC = CircleDetailViewController(circle: circle, isSharedViaLink: true)
                                        navController.pushViewController(detailVC, animated: true)
                                    }
                                case .failure:
                                    // Circle is not public or error occurred, require login
                                    if AuthService.shared.isLoggedIn {
                                        // User is logged in, navigate normally
                                        self?.host?.deepLinks.navigateToCircle(circleId: circleId, isSharedViaLink: true)
                                    } else {
                                        // User not logged in, store deep link and prompt login
                                        UserDefaults.standard.set("shareToken:\(circleId):\(shareToken)", forKey: "pendingDeepLink")

                                        if let rootVC = self?.window?.rootViewController {
                                            // Login: the auth state listener handles showing the login screen
                                            AlertPresenter.showConfirmation(
                                                title: "Login Required",
                                                message: "Please login to view this circle",
                                                confirmTitle: "Login",
                                                from: rootVC
                                            ) {}
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // Share is invalid or expired
                        self?.showShareError(message: response.message ?? "This share link is no longer valid")
                    }

                case .failure(let error):
                    self?.showShareError(message: FriendlyError.message(for: error))
                }
            }
        }
    }

    private func showShareAccessBanner(accessLevel: String) {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController,
              let currentVC = tabBarController.selectedViewController else { return }

        let banner = UIView()
        banner.backgroundColor = .systemBlue
        banner.layer.cornerRadius = 10
        banner.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = accessLevel == "viewOnly" ? "View-only access" : "Limited access"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(label)
        currentVC.view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: currentVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            banner.centerXAnchor.constraint(equalTo: currentVC.view.centerXAnchor),
            banner.heightAnchor.constraint(equalToConstant: 40),
            banner.widthAnchor.constraint(equalToConstant: 150),

            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])

        // Animate and remove after 5 seconds
        banner.alpha = 0
        UIView.animate(withDuration: 0.3) {
            banner.alpha = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UIView.animate(withDuration: 0.3, animations: {
                banner.alpha = 0
            }) { _ in
                banner.removeFromSuperview()
            }
        }
    }

    private func showShareError(message: String) {
        if let rootVC = window?.rootViewController {
            AlertPresenter.showError(title: "Unable to Access Circle", message: message, from: rootVC)
        }
    }

    func handleSharedCircle(shareId: String) {
        // If user is not logged in, store the share ID and prompt login
        guard AuthService.shared.isLoggedIn else {
            UserDefaults.standard.set("share:\(shareId)", forKey: "pendingDeepLink")

            // Show alert prompting user to login
            if let rootVC = window?.rootViewController {
                // Login: the auth state listener handles showing the login screen
                AlertPresenter.showAlert(title: "Login Required", message: "Please login to view the shared circle",
                                         actions: [("Login", .default, {})], from: rootVC)
            }
            return
        }

        // Accept the shared circle
        NetworkManager.shared.acceptSharedCircle(shareId: shareId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sharedCircle):
                    // Navigate to the shared circle
                    self?.host?.deepLinks.navigateToCircle(circleId: sharedCircle.circleId)

                    // Show success message
                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController,
                       let currentVC = tabBarController.selectedViewController {
                        let banner = UIView()
                        banner.backgroundColor = .systemGreen
                        banner.layer.cornerRadius = 10
                        banner.translatesAutoresizingMaskIntoConstraints = false

                        let label = UILabel()
                        label.text = "Circle imported successfully!"
                        label.textColor = .white
                        label.translatesAutoresizingMaskIntoConstraints = false

                        banner.addSubview(label)
                        currentVC.view.addSubview(banner)

                        NSLayoutConstraint.activate([
                            banner.topAnchor.constraint(equalTo: currentVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
                            banner.centerXAnchor.constraint(equalTo: currentVC.view.centerXAnchor),
                            banner.heightAnchor.constraint(equalToConstant: 50),
                            banner.widthAnchor.constraint(equalToConstant: 250),

                            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
                            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
                        ])

                        // Animate and remove after 3 seconds
                        UIView.animate(withDuration: 0.3) {
                            banner.alpha = 1.0
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            UIView.animate(withDuration: 0.3, animations: {
                                banner.alpha = 0
                            }) { _ in
                                banner.removeFromSuperview()
                            }
                        }
                    }

                case .failure(let error):
                    // Show error alert
                    if let rootVC = self?.window?.rootViewController {
                        AlertPresenter.showError(title: "Import Failed", message: FriendlyError.message(for: error), from: rootVC)
                    }
                }
            }
        }
    }

    func handleConnectionInvite(from userId: String, inviteToken: String? = nil) {
        Logger.debug("📱 SceneDelegate: handleConnectionInvite called with userId: \(userId)")
        Logger.debug("📱 SceneDelegate: Current user logged in: \(AuthService.shared.isLoggedIn)")
        Logger.debug("📱 SceneDelegate: Current user ID: \(AuthService.shared.getUserId() ?? "nil")")

        // If user is not logged in, store the connection invite and prompt login
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, storing pending connection invite")
            // Store both as pending deep link and specific connection invite
            UserDefaults.standard.set("connect:\(userId)", forKey: "pendingDeepLink")
            NetworkManager.storePendingConnectionInvite(userId: userId, inviteToken: inviteToken)

            // Show alert prompting user to login
            if let rootVC = window?.rootViewController {
                // Login: the auth state listener handles showing the login screen
                AlertPresenter.showConfirmation(
                    title: "Connection Invite",
                    message: "Please login to connect with this user",
                    confirmTitle: "Login",
                    from: rootVC
                ) {}
            }
            return
        }

        // Handle the connection invite
        Logger.debug("📱 SceneDelegate: About to call NetworkManager.handleConnectionInvite")
        NetworkManager.shared.handleConnectionInvite(from: userId, inviteToken: inviteToken) { [weak self] result in
            Logger.debug("📱 SceneDelegate: NetworkManager.handleConnectionInvite callback received")
            DispatchQueue.main.async {
                switch result {
                case .success(let connection):
                    Logger.debug("📱 SceneDelegate: Connection successful! Connection ID: \(connection.id), Status: \(connection.status)")
                    // Refresh connections list to ensure UI is updated
                    NetworkManager.shared.loadConnections()

                    // Navigate to the My Network tab (tab order: 0 Home, 1 My Network, 2 Messages, 3 Me)
                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController {
                        tabBarController.selectedIndex = 1 // My Network tab

                        // Show success message
                        let banner = UIView()
                        banner.backgroundColor = .systemGreen
                        banner.layer.cornerRadius = 10
                        banner.translatesAutoresizingMaskIntoConstraints = false

                        let label = UILabel()
                        let labelText = connection.status == .accepted ? "Connected successfully!" : "Connection request sent!"
                        label.text = labelText
                        label.textColor = .white
                        label.translatesAutoresizingMaskIntoConstraints = false

                        banner.addSubview(label)
                        tabBarController.view.addSubview(banner)

                        NSLayoutConstraint.activate([
                            banner.topAnchor.constraint(equalTo: tabBarController.view.safeAreaLayoutGuide.topAnchor, constant: 20),
                            banner.centerXAnchor.constraint(equalTo: tabBarController.view.centerXAnchor),
                            banner.heightAnchor.constraint(equalToConstant: 50),
                            banner.widthAnchor.constraint(equalToConstant: 250),

                            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
                            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
                        ])

                        // Animate and remove after 3 seconds
                        UIView.animate(withDuration: 0.3) {
                            banner.alpha = 1.0
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            UIView.animate(withDuration: 0.3, animations: {
                                banner.alpha = 0
                            }) { _ in
                                banner.removeFromSuperview()
                            }
                        }
                    }

                case .failure(let error):
                    Logger.debug("📱 SceneDelegate: Connection failed with error: \(error)")

                    // Say what actually happened. Most of these aren't failures
                    // at all — the invite was declined locally on purpose — so
                    // only genuine errors get the "Connection Failed" title.
                    let title: String
                    let errorMessage: String

                    switch error as? ConnectionInviteError {
                    case .ownInviteLink:
                        title = "That's Your Invite Link"
                        errorMessage = "Share it with someone else — they'll connect with you when they open it."
                    case .alreadyConnected:
                        title = "Already Connected"
                        errorMessage = "You are already connected to this user."
                    case .requestPending:
                        title = "Request Pending"
                        errorMessage = "You already have a connection request with this user."
                    case nil:
                        // Anything else is a real failure. Prefer the server's
                        // own wording when it sent one.
                        title = "Connection Failed"
                        errorMessage = (error as? APIError)?.serverMessage ?? "Failed to send connection request"
                    }

                    if let rootVC = self?.window?.rootViewController {
                        AlertPresenter.showError(title: title, message: errorMessage, from: rootVC)
                    }
                }
            }
        }
    }

    // MARK: - Referral Code Handling

    /// Connect invite links can carry the sharer's referral code (?code=XXXXXX).
    /// For a recipient who isn't signed in yet, stash it as the pending referral
    /// code so the Register screen prefills it and applies it after signup.
    /// Logged-in users just get the normal auto-connect — no referral involved.
    func stashInviteReferralCode(_ code: String?) {
        guard !AuthService.shared.isLoggedIn,
              !ReferralService.shared.hasUsedReferralCode(),
              let code, !code.isEmpty else { return }
        Logger.debug("📱 SceneDelegate: Stashing referral code from connect invite: \(code)")
        ReferralService.shared.savePendingReferralCode(code.uppercased())
    }

    func handleReferralCode(_ code: String) {
        Logger.debug("📱 SceneDelegate: handleReferralCode called with code: \(code)")

        // If user is not logged in, save the code for later
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, saving referral code for later")
            ReferralService.shared.savePendingReferralCode(code)

            // Show alert prompting user to sign up
            if let topVC = window?.rootViewController {
                // Sign Up: the auth state listener handles showing the auth screen
                AlertPresenter.showConfirmation(
                    title: "Referral Code Saved",
                    message: "Your referral code \(code) will apply automatically when you sign up.",
                    confirmTitle: "Sign Up",
                    cancelTitle: "Later",
                    from: topVC
                ) {}
            }
            return
        }

        // If user is logged in, check if they've already used a referral code
        if ReferralService.shared.hasUsedReferralCode() {
            Logger.debug("📱 SceneDelegate: User has already used a referral code")

            if let topVC = window?.rootViewController {
                AlertPresenter.showInfo(title: "Referral Code", message: "You have already used a referral code.", from: topVC)
            }
            return
        }

        // Apply the referral code
        var loading: UIAlertController?
        if let topVC = window?.rootViewController {
            loading = AlertPresenter.showLoading(message: "Applying Code...", from: topVC)
        }

        ReferralService.shared.applyReferralCode(code) { [weak self] result in
            DispatchQueue.main.async {
                let showResult = {
                    guard let topVC = self?.window?.rootViewController else { return }
                    switch result {
                    case .success(let response):
                        AlertPresenter.showAlert(title: "Success!", message: response.message,
                                                 actions: [("Great!", .default, {})], from: topVC)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: topVC)
                    }
                }
                if let loading {
                    loading.dismiss(animated: true, completion: showResult)
                } else {
                    showResult()
                }
            }
        }
    }
}

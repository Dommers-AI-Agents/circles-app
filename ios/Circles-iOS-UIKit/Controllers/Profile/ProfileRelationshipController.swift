import UIKit

/// What the relationship flows need from the profile screen. The profile
/// keeps `user`, `isFollowing` and `connectionStatus` (other code on the
/// screen reads them) and all button rendering; the controller drives them
/// through these accessors at the same points the inline code did.
protocol ProfileRelationshipControllerDelegate: AnyObject {
    var user: User? { get set }
    var isFollowing: Bool { get set }
    var connectionStatus: ConnectionStatus? { get set }
    var followButton: UIButton { get }
    var navigationController: UINavigationController? { get }

    func updateButtonVisibility()
    func updateLocalFollowingCount(increment: Bool)
    func showAlert(title: String, message: String)
    func showError(_ message: String)
}

/// Follow / connect / message actions on another user's profile, plus the
/// connection-and-follow status resolution that renders the buttons
/// (Phase 5, profile step 5). Moved verbatim from ProfileViewController;
/// the screen keeps its `@objc` targets as forwarders.
final class ProfileRelationshipController {
    weak var delegate: ProfileRelationshipControllerDelegate?

    /// The bits of a connection record the flows need.
    struct ConnectionMatch {
        let id: String
        let status: ConnectionStatus
        /// Who sent the request (`Connection.userId`).
        let initiatorId: String
    }

    // MARK: Service seams (tests inject fakes)

    var currentUserId: () -> String? = { AuthService.shared.getUserId() }

    /// The accepted-or-pending connection with `userId`, if any.
    var findConnection: (_ userId: String, _ currentUserId: String) -> ConnectionMatch? = { userId, currentUserId in
        let allConnections = NetworkManager.shared.connections + NetworkManager.shared.pendingConnections
        return allConnections
            .first { $0.otherUserId(currentUserId: currentUserId) == userId }
            .map { ConnectionMatch(id: $0.id, status: $0.status, initiatorId: $0.userId) }
    }

    /// The signed-in user's following list, when the cached user is loaded.
    var localFollowing: () -> [String]?? = {
        guard let currentUser = AuthService.shared.currentUser else { return nil }
        return .some(currentUser.following)
    }

    var fetchCurrentUser: (_ completion: @escaping (Result<User, Error>) -> Void) -> Void = { completion in
        AuthService.shared.fetchCurrentUser(completion: completion)
    }

    // MARK: Status

    func checkConnectionAndFollowStatus() {
        guard let delegate = delegate, let user = delegate.user else { return }

        Logger.debug("🔍 Checking connection and follow status for user: \(user.displayName)")

        // Check if user is in current user's connections (both accepted and pending)
        let currentUserId = self.currentUserId() ?? ""
        let connection = findConnection(user.id, currentUserId)

        delegate.connectionStatus = connection?.status

        // Set connection direction based on who initiated the request
        if let connection = connection, connection.status == .pending {
            // If the current user initiated the request, it's outgoing
            let direction = connection.initiatorId == currentUserId ? "outgoing" : "incoming"

            // Create new user instance with updated connection direction
            if let currentUser = delegate.user {
                delegate.user = User(
                    id: currentUser.id,
                    email: currentUser.email,
                    displayName: currentUser.displayName,
                    firstName: currentUser.firstName,
                    lastName: currentUser.lastName,
                    phoneNumber: currentUser.phoneNumber,
                    profilePicture: currentUser.profilePicture,
                    bio: currentUser.bio,
                    location: currentUser.location,
                    friends: currentUser.friends,
                    friendRequests: currentUser.friendRequests,
                    circleOrder: currentUser.circleOrder,
                    preferences: currentUser.preferences,
                    createdAt: currentUser.createdAt,
                    connectionStatus: currentUser.connectionStatus,
                    connectionDirection: direction,
                    connectionId: currentUser.connectionId,
                    followers: currentUser.followers,
                    following: currentUser.following,
                    followersCount: currentUser.followersCount,
                    followingCount: currentUser.followingCount,
                    connectionsCount: currentUser.connectionsCount,
                    pinnedPlaces: currentUser.pinnedPlaces,
                    isFollowing: currentUser.isFollowing
                )
            }
        }

        // First, check if the user object has isFollowing property (from backend)
        if let userIsFollowing = user.isFollowing {
            let wasFollowing = delegate.isFollowing
            delegate.isFollowing = userIsFollowing
            Logger.debug("📊 Follow status from backend - Was: \(wasFollowing), Now: \(delegate.isFollowing)")
        } else {
            // Fallback: Check follow status from current user's following list
            let cached = localFollowing()
            if let cachedFollowing = cached, let following = cachedFollowing {
                let wasFollowing = delegate.isFollowing
                delegate.isFollowing = following.contains(user.id)
                Logger.debug("📊 Follow status from local - Was: \(wasFollowing), Now: \(delegate.isFollowing), Following array: \(following.count) users")
            } else {
                delegate.isFollowing = false
                Logger.debug("📊 No following data available")
            }

            // If we're viewing another user and don't have current user data, fetch it
            if cached == nil && user.id != self.currentUserId() {
                fetchCurrentUser { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // Re-check follow status after fetching current user
                        self.checkConnectionAndFollowStatus()
                    }
                }
            }
        }

        delegate.updateButtonVisibility()
    }

    // MARK: Actions

    func messageTapped() {
        Logger.debug("🔍 ProfileViewController: messageButtonTapped called")
        guard let user = delegate?.user else {
            Logger.debug("❌ ProfileViewController: messageButtonTapped - user is nil")
            return
        }

        Logger.debug("🔍 ProfileViewController: Creating/getting conversation with user: \(user.displayName) (ID: \(user.id))")

        // Create or get conversation with this user
        MessagingManager.shared.createOrGetDirectConversation(with: user.id) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let conversation):
                Logger.debug("✅ ProfileViewController: Successfully got conversation:")
                Logger.debug("   - ID: \(conversation.id)")
                Logger.debug("   - Type: \(conversation.type)")
                Logger.debug("   - Participants: \(conversation.participants)")
                Logger.debug("   - Display Name: \(conversation.displayName ?? "nil")")

                DispatchQueue.main.async {
                    Logger.debug("🔍 ProfileViewController: Creating ChatViewController and navigating")
                    let chatVC = ChatViewController()
                    chatVC.conversation = conversation
                    self.delegate?.navigationController?.pushViewController(chatVC, animated: true)
                }
            case .failure(let error):
                Logger.debug("❌ ProfileViewController: Failed to create/get conversation: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.delegate?.showAlert(title: "Error", message: "Failed to start conversation: \(error.localizedDescription)")
                }
            }
        }
    }

    func followTapped() {
        guard let delegate = delegate, let user = delegate.user else { return }

        // Disable button to prevent rapid toggles
        delegate.followButton.isEnabled = false
        delegate.followButton.alpha = 0.6

        let endpoint = delegate.isFollowing ? "users/\(user.id)/unfollow" : "users/\(user.id)/follow"
        let action = delegate.isFollowing ? "unfollow" : "follow"

        Logger.debug("🔵 Follow button tapped - Action: \(action), User: \(user.displayName)")

        // Store original states for rollback
        let originalIsFollowing = delegate.isFollowing
        let originalUser = delegate.user

        // Apply optimistic UI updates immediately
        delegate.isFollowing.toggle()
        delegate.updateButtonVisibility()
        delegate.updateLocalFollowingCount(increment: action == "follow")

        // Update the user object's isFollowing flag optimistically. The full
        // copy() preserves followsYou and every other field — the hand-built
        // User this replaces silently dropped them, so tapping Follow erased
        // the very "follows you" state that justified the Follow Back label.
        delegate.user = delegate.user?.copy(isFollowing: delegate.isFollowing)

        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate else { return }

                switch result {
                case .success(let response):
                    Logger.debug("✅ Successfully \(action)ed user: \(user.displayName)")
                    AuthService.shared.recordFollowChange(userId: user.id, isFollowing: action == "follow")
                    // First-ever follow earns a dime (nil on unfollow)
                    PiggyBankDepositView.play(credit: response.piggyBank)

                    // Re-enable button after successful action
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        delegate.followButton.isEnabled = true
                        delegate.followButton.alpha = 1.0
                    }

                case .failure(let error):
                    Logger.debug("❌ Failed to \(action) user: \(error)")

                    // Rollback optimistic updates on failure
                    delegate.isFollowing = originalIsFollowing
                    delegate.user = originalUser
                    delegate.updateButtonVisibility()
                    delegate.updateLocalFollowingCount(increment: action == "unfollow") // Reverse the action

                    delegate.showAlert(title: "Error", message: "Failed to \(action) user: \(error.localizedDescription)")

                    // Re-enable button immediately on error
                    delegate.followButton.isEnabled = true
                    delegate.followButton.alpha = 1.0
                }
            }
        }
    }

    func connectTapped() {
        guard let delegate = delegate, let user = delegate.user else { return }

        // Check if this is an incoming request to accept
        if delegate.connectionStatus == .pending && user.connectionDirection == "incoming" {
            // Find the connection to accept (check both accepted and pending connections)
            guard let connection = findConnection(user.id, currentUserId() ?? "") else {
                delegate.showAlert(title: "Error", message: "Connection request not found")
                return
            }

            // Accept the incoming request
            NetworkManager.shared.acceptConnection(connection.id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate else { return }

                    switch result {
                    case .success:
                        // Update connection status
                        delegate.connectionStatus = .accepted
                        delegate.updateButtonVisibility()
                        delegate.showAlert(title: "Success", message: "Connection request accepted!")

                        // Refresh connections
                        NetworkManager.shared.loadConnections()
                    case .failure(let error):
                        delegate.showAlert(title: "Error", message: "Failed to accept connection request: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Send new connection request
            NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate else { return }

                    switch result {
                    case .success:
                        // Update connection status locally. Connecting implies
                        // following (the server auto-follows on connect), so
                        // the Follow button flips to "Following" right away.
                        delegate.connectionStatus = .pending
                        delegate.isFollowing = true
                        delegate.user = delegate.user?.copy(
                            connectionStatus: "pending",
                            connectionDirection: "outgoing",
                            isFollowing: true
                        )
                        delegate.updateButtonVisibility()
                        delegate.showAlert(title: "Success", message: "Connection request sent!")

                        // Refresh connections to get updated list
                        NetworkManager.shared.loadConnections()
                    case .failure(let error):
                        // Show the server's own wording ("Cannot connect to
                        // yourself", "Connection request already sent") rather
                        // than appending a raw localizedDescription.
                        delegate.showError((error as? APIError)?.serverMessage ?? "Failed to send connection request")
                    }
                }
            }
        }
    }
}

import Foundation

/// What the loader needs from the profile screen as data arrives. Each
/// method is the block of UI work the inline fetch used to do at that
/// point, in the same order; the screen keeps `user`, `circles` and the
/// relationship flags because other code on the screen reads them.
protocol ProfileDataLoaderDelegate: AnyObject {
    var user: User? { get set }
    var circles: [Circle] { get set }
    var isFollowing: Bool { get set }
    var connectionStatus: ConnectionStatus? { get set }

    /// Render a user (header, stats placeholders, storefront card...).
    func displayUser(_ user: User)
    /// No server data and no cache: show the empty default profile.
    func displayDefaultProfile()
    /// Re-render the relationship buttons after the flags changed.
    func updateButtonVisibility()

    /// One circle's places arrived for the map (append + re-filter).
    func loaderDidLoadPlaces(_ places: [Place])

    /// Own profile: circles fetched — totals, stats, badge, grid, moments,
    /// search index.
    func loaderDidLoadOwnCircles(_ circles: [Circle])
    /// Own profile: circles fetch failed — zeroed stats, grid, moments, and
    /// an error alert whose Retry reloads the profile.
    func loaderDidFailOwnCircles(_ error: Error)
    /// Own profile: the connections / followers / following stats that come
    /// from local data, shown while the circles fetch is in flight.
    func presentLocalOwnProfileCounts()

    /// Another user's circles + fresh user record arrived.
    func loaderDidLoadOtherUserCircles(_ data: UserCirclesData)
}

/// Loads the profile: own vs other user, stats, circles (with the quiet
/// one-time retry for other users), and places for the map (Phase 5,
/// profile step 6). Moved from ProfileViewController; the screen forwards
/// its old method names here.
final class ProfileDataLoader {
    weak var delegate: ProfileDataLoaderDelegate?

    /// Prevent multiple simultaneous requests for the same user.
    private(set) var isFetchingOtherUserCircles = false
    private(set) var hasRetriedOtherUserCircles = false

    // MARK: Service seams (tests inject fakes)

    var currentUserId: () -> String? = { AuthService.shared.getUserId() }
    var cachedCurrentUser: () -> User? = { AuthService.shared.currentUser }
    var fetchPlaces: (_ circleId: String, _ completion: @escaping (Result<[Place], Error>) -> Void) -> Void = { circleId, completion in
        PlaceService.shared.fetchPlacesByCircleId(circleId: circleId, completion: completion)
    }
    var fetchUserProfile: (_ userId: String?, _ completion: @escaping (Result<User, Error>) -> Void) -> Void = { userId, completion in
        UserService.shared.fetchUserProfile(userId: userId, completion: completion)
    }
    var fetchOwnCircles: (_ completion: @escaping (Result<[Circle], Error>) -> Void) -> Void = { completion in
        CircleService.shared.fetchUserCircles(completion: completion)
    }
    var requestUserCircles: (_ userId: String, _ completion: @escaping (Result<UserCirclesResponse, APIError>) -> Void) -> Void = { userId, completion in
        APIService.shared.request(
            endpoint: "network/user-circles/\(userId)",
            method: .get,
            requiresAuth: true,
            completion: completion
        )
    }
    var schedule: (_ delay: TimeInterval, _ block: @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    // MARK: Places (map)

    func loadAllPlaces() {
        guard let delegate = delegate else { return }
        // Load places from all circles
        for circle in delegate.circles {
            fetchPlaces(circle.id) { [weak self] result in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    switch result {
                    case .success(let places):
                        self.delegate?.loaderDidLoadPlaces(places)
                    case .failure(let error):
                        Logger.debug("Failed to load places for circle \(circle.name): \(error)")
                    }
                }
            }
        }
    }

    // MARK: Profile

    func loadUserProfile(completion: (() -> Void)? = nil) {
        guard let delegate = delegate else { return }
        Logger.debug("🚀 ProfileViewController: loadUserProfile called")
        Logger.debug("🚀 ProfileViewController: Has existing user? \(delegate.user != nil)")

        // The OWN profile always refetches — re-rendering the held snapshot
        // meant Edit Profile changes (location, zipcode, ...) never appeared
        // until app restart. Other users' profiles render what they were given.
        let currentUserId = self.currentUserId() ?? ""
        let isOwnProfile = delegate.user == nil || IDNormalizer.isSameUser(delegate.user!.id, currentUserId)

        if let user = delegate.user, !isOwnProfile {
            // Another user's profile — render the provided snapshot instantly,
            // then refetch so relationship state is CURRENT. The snapshot's
            // isFollowing/connectionStatus are frozen at list-fetch time, which
            // is how a profile kept showing "Follow" after Connect (connect
            // auto-follows server-side, but the stale snapshot didn't know).
            Logger.debug("✅ ProfileViewController: Using existing user: \(user.id)")
            delegate.displayUser(user)
            fetchUserStats(userId: user.id)
            fetchUserProfile(user.id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate, case .success(let fresh) = result,
                          delegate.user?.id == fresh.id else { return }
                    // Merge fresh relationship flags over the snapshot
                    delegate.user = fresh
                    if let freshFollowing = fresh.isFollowing {
                        delegate.isFollowing = freshFollowing
                    }
                    if let freshStatus = ConnectionStatus(rawValue: fresh.connectionStatus ?? "") {
                        delegate.connectionStatus = freshStatus
                    }
                    delegate.updateButtonVisibility()
                }
            }
            completion?()
        } else {
            // Own profile — always get fresh data
            Logger.debug("🔄 ProfileViewController: Own profile, fetching fresh data")
            fetchFreshUserData(completion: completion)
        }
    }

    func fetchFreshUserData(completion: (() -> Void)? = nil) {
        Logger.debug("🚀 ProfileViewController: fetchFreshUserData called")

        // Always fetch fresh user data from the server
        fetchUserProfile(nil) { [weak self] result in
            Logger.debug("📡 ProfileViewController: fetchUserProfile callback received")
            guard let self = self, let delegate = self.delegate else {
                Logger.debug("⚠️ ProfileViewController: Self deallocated during fetch")
                completion?()
                return
            }

            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    Logger.debug("✅ ProfileViewController: Successfully fetched user profile")
                    Logger.debug("✅ ProfileViewController: User ID: \(user.id)")
                    Logger.debug("✅ ProfileViewController: User name: \(user.displayName)")
                    delegate.user = user
                    delegate.displayUser(user)
                    self.fetchUserStats(userId: user.id)

                    // Update the cached user in AuthService
                    AuthService.shared.updateCurrentUser(user)

                case .failure(let error):
                    Logger.debug("❌ ProfileViewController: Failed to fetch user profile: \(error)")
                    Logger.debug("❌ ProfileViewController: Error type: \(type(of: error))")

                    // If we have cached data, use it as fallback
                    if let cachedUser = self.cachedCurrentUser() {
                        Logger.debug("⚠️ ProfileViewController: Using cached user as fallback: \(cachedUser.id)")
                        delegate.user = cachedUser
                        delegate.displayUser(cachedUser)
                        self.fetchUserStats(userId: cachedUser.id)
                    } else {
                        Logger.debug("❌ ProfileViewController: No cached user available, showing default profile")
                        // Show error or default values
                        delegate.displayDefaultProfile()
                    }
                }

                // Call completion after all data loading is done
                completion?()
            }
        }
    }

    // MARK: Stats + circles

    func fetchUserStats(userId: String) {
        Logger.debug("🚀 ProfileViewController: fetchUserStats called for userId: \(userId)")
        Logger.debug("🚀 ProfileViewController: Current user ID: \(currentUserId() ?? "nil")")

        // For current user, fetch their circles
        if userId == currentUserId() {
            Logger.debug("✅ ProfileViewController: Fetching stats for current user")
            // Fetch circles
            fetchOwnCircles { [weak self] result in
                Logger.debug("📡 ProfileViewController: fetchUserCircles callback received")
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate else { return }

                    switch result {
                    case .success(let circles):
                        delegate.circles = circles
                        Logger.debug("🔍 ProfileViewController - Fetched \(circles.count) circles")
                        delegate.loaderDidLoadOwnCircles(circles)
                    case .failure(let error):
                        delegate.circles = []
                        delegate.loaderDidFailOwnCircles(error)
                    }
                }
            }

            delegate?.presentLocalOwnProfileCounts()
        } else {
            // For other users, fetch their public circles
            fetchOtherUserCircles(userId: userId)
        }
    }

    func fetchOtherUserCircles(userId: String) {
        // Prevent multiple simultaneous requests for the same user
        guard !isFetchingOtherUserCircles else {
            Logger.debug("🔍 Already fetching circles for user \(userId), skipping duplicate request")
            return
        }

        isFetchingOtherUserCircles = true

        // Fetch circles from network endpoint for other users
        requestUserCircles(userId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard let delegate = self.delegate else { return }
                // Reset the flag when request completes
                self.isFetchingOtherUserCircles = false

                switch result {
                case .success(let response):
                    self.hasRetriedOtherUserCircles = false
                    delegate.circles = response.data.circles
                    delegate.loaderDidLoadOtherUserCircles(response.data)

                case .failure(let error):
                    Logger.debug("Failed to load other user circles: \(error)")

                    // A failed fetch is not information about the profile — it
                    // must never overwrite data we're already showing. This
                    // branch used to write zeros into every stat and clear the
                    // grid, so one transient error made a real profile look
                    // empty until a pull-to-refresh happened to succeed.
                    if !delegate.circles.isEmpty { return }

                    // Nothing shown yet: retry once, quietly. Covers cold
                    // starts and rate-limit blips without anyone having to
                    // know the swipe-down gesture exists.
                    if !self.hasRetriedOtherUserCircles {
                        self.hasRetriedOtherUserCircles = true
                        self.schedule(ProfileDataLoader.retryDelay(for: error)) { [weak self] in
                            self?.fetchOtherUserCircles(userId: userId)
                        }
                    }
                }
            }
        }
    }

    /// Rate-limited responses wait what the server asked (3s if it didn't
    /// say); anything else retries after 2s.
    static func retryDelay(for error: Error) -> TimeInterval {
        if case APIError.rateLimited(let retryAfter) = error {
            return retryAfter ?? 3
        }
        return 2
    }
}

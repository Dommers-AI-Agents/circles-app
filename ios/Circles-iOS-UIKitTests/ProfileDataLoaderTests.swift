import Testing
import Foundation
@testable import Circles_iOS

/// The profile's other-user circles fetch: in-flight de-duplication and
/// the quiet one-time retry that never overwrites data already shown.
@MainActor
struct ProfileDataLoaderTests {
    final class Screen: ProfileDataLoaderDelegate {
        var user: User?
        var circles: [Circle] = []
        var isFollowing = false
        var connectionStatus: ConnectionStatus?
        var events: [String] = []
        func displayUser(_ user: User) { events.append("display:\(user.id)") }
        func displayDefaultProfile() { events.append("default") }
        func updateButtonVisibility() { events.append("buttons") }
        func loaderDidLoadPlaces(_ places: [Place]) { events.append("places:\(places.count)") }
        func loaderDidLoadOwnCircles(_ circles: [Circle]) { events.append("ownCircles:\(circles.count)") }
        func loaderDidFailOwnCircles(_ error: Error) { events.append("ownCirclesFailed") }
        func presentLocalOwnProfileCounts() { events.append("localCounts") }
        func loaderDidLoadOtherUserCircles(_ data: UserCirclesData) { events.append("otherCircles:\(data.circles.count)") }
    }

    private func user(_ id: String) -> User {
        User(id: id, displayName: id, profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil)
    }

    private func circle(_ id: String) -> Circle {
        Circle(id: id, name: id, description: nil, coverImage: nil, owner: "bob", ownerDetails: nil,
               editors: nil, editorsDetails: nil, places: nil, placesCount: nil, placesWithDetails: nil,
               privacy: .public, allowNetworkEdit: nil, showOnMap: nil, category: .other,
               location: nil, tags: nil, sharedWith: nil, followers: nil, activeShares: nil,
               shareSettings: nil, isSharedWithMe: nil, sharedBy: nil, myAccessLevel: nil,
               createdAt: Date(), updatedAt: Date())
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }
    }

    /// A loader whose circles request is held until the test completes it.
    private func make() -> (ProfileDataLoader, Screen, pending: () -> [(Result<UserCirclesResponse, APIError>) -> Void], scheduled: () -> [(TimeInterval, () -> Void)]) {
        let screen = Screen()
        screen.user = user("bob")
        let loader = ProfileDataLoader()
        loader.delegate = screen
        loader.currentUserId = { "me" }
        var pending: [(Result<UserCirclesResponse, APIError>) -> Void] = []
        var scheduled: [(TimeInterval, () -> Void)] = []
        loader.requestUserCircles = { _, completion in pending.append(completion) }
        loader.schedule = { delay, block in scheduled.append((delay, block)) }
        return (loader, screen, { pending }, { scheduled })
    }

    @Test func retryDelays() {
        #expect(ProfileDataLoader.retryDelay(for: APIError.rateLimited(retryAfter: 5)) == 5)
        #expect(ProfileDataLoader.retryDelay(for: APIError.rateLimited(retryAfter: nil)) == 3)
        #expect(ProfileDataLoader.retryDelay(for: APIError.noInternet) == 2)
    }

    @Test func aSecondCallWhileInFlightIsIgnored() {
        let (loader, _, pending, _) = make()
        loader.fetchUserStats(userId: "bob")
        loader.fetchUserStats(userId: "bob")
        #expect(pending().count == 1)
        #expect(loader.isFetchingOtherUserCircles)
    }

    @Test func failureWithNothingShownRetriesExactlyOnce() async {
        let (loader, screen, pending, scheduled) = make()
        loader.fetchOtherUserCircles(userId: "bob")
        pending()[0](.failure(.noInternet))
        await drainMainQueue()
        #expect(!loader.isFetchingOtherUserCircles)
        #expect(scheduled().count == 1)
        #expect(scheduled()[0].0 == 2)
        #expect(screen.events.isEmpty)

        // The retry fires and fails again: no third attempt
        scheduled()[0].1()
        #expect(pending().count == 2)
        pending()[1](.failure(.rateLimited(retryAfter: 9)))
        await drainMainQueue()
        #expect(scheduled().count == 1)
        #expect(screen.events.isEmpty)
    }

    @Test func failureNeverOverwritesCirclesAlreadyShown() async {
        let (loader, screen, pending, scheduled) = make()
        screen.circles = [circle("c1")]
        loader.fetchOtherUserCircles(userId: "bob")
        pending()[0](.failure(.noInternet))
        await drainMainQueue()
        #expect(scheduled().isEmpty)
        #expect(screen.circles.count == 1)
        #expect(screen.events.isEmpty)
    }

    @Test func successStoresCirclesAndReportsThem() async {
        let (loader, screen, pending, _) = make()
        loader.fetchOtherUserCircles(userId: "bob")
        let data = UserCirclesData(user: user("bob"), circles: [circle("c1"), circle("c2")])
        pending()[0](.success(UserCirclesResponse(success: true, data: data)))
        await drainMainQueue()
        #expect(screen.circles.map { $0.id } == ["c1", "c2"])
        #expect(screen.events == ["otherCircles:2"])
        #expect(!loader.isFetchingOtherUserCircles)
    }

    @Test func ownProfileFetchesOwnCirclesAndShowsLocalCountsMeanwhile() async {
        let (loader, screen, pending, _) = make()
        var ownCompletion: ((Result<[Circle], Error>) -> Void)?
        loader.fetchOwnCircles = { completion in ownCompletion = completion }
        loader.fetchUserStats(userId: "me")
        #expect(pending().isEmpty)
        #expect(screen.events == ["localCounts"])
        ownCompletion?(.success([circle("c1")]))
        await drainMainQueue()
        #expect(screen.circles.map { $0.id } == ["c1"])
        #expect(screen.events == ["localCounts", "ownCircles:1"])
    }
}

import Testing
import UIKit
@testable import Circles_iOS

/// How a profile resolves its connection + follow state before rendering
/// the Follow / Connect / Message buttons.
@MainActor
struct ProfileRelationshipControllerTests {
    final class Screen: ProfileRelationshipControllerDelegate {
        var user: User?
        var isFollowing = false
        var connectionStatus: ConnectionStatus?
        let followButton = UIButton()
        var navigationController: UINavigationController? { nil }
        var visibilityUpdates = 0
        var alerts: [String] = []
        func updateButtonVisibility() { visibilityUpdates += 1 }
        func updateLocalFollowingCount(increment: Bool) {}
        func showAlert(title: String, message: String) { alerts.append(title) }
        func showError(_ message: String) { alerts.append(message) }
    }

    private func user(_ id: String, isFollowing: Bool? = nil, followsYou: Bool? = nil) -> User {
        User(id: id, displayName: id, profilePicture: nil, bio: nil, location: nil,
             friends: nil, friendRequests: nil, isFollowing: isFollowing, followsYou: followsYou)
    }

    private func make(user: User, me: String = "me",
                      connection: ProfileRelationshipController.ConnectionMatch? = nil,
                      localFollowing: [String]?? = .some(nil)) -> (ProfileRelationshipController, Screen) {
        let screen = Screen()
        screen.user = user
        let controller = ProfileRelationshipController()
        controller.delegate = screen
        controller.currentUserId = { me }
        controller.findConnection = { _, _ in connection }
        controller.localFollowing = { localFollowing }
        controller.fetchCurrentUser = { _ in Issue.record("no fetch expected") }
        return (controller, screen)
    }

    @Test func pendingRequestSetsDirectionFromTheInitiator() {
        let outgoing = ProfileRelationshipController.ConnectionMatch(id: "c1", status: .pending, initiatorId: "me")
        let (c1, s1) = make(user: user("bob", isFollowing: true), connection: outgoing)
        c1.checkConnectionAndFollowStatus()
        #expect(s1.connectionStatus == .pending)
        #expect(s1.user?.connectionDirection == "outgoing")
        #expect(s1.isFollowing)
        #expect(s1.visibilityUpdates == 1)

        let incoming = ProfileRelationshipController.ConnectionMatch(id: "c2", status: .pending, initiatorId: "bob")
        let (c2, s2) = make(user: user("bob", isFollowing: false), connection: incoming)
        c2.checkConnectionAndFollowStatus()
        #expect(s2.user?.connectionDirection == "incoming")
        #expect(!s2.isFollowing)
    }

    @Test func acceptedAndUnknownConnectionsLeaveDirectionAlone() {
        let accepted = ProfileRelationshipController.ConnectionMatch(id: "c1", status: .accepted, initiatorId: "bob")
        let (c1, s1) = make(user: user("bob", isFollowing: true), connection: accepted)
        c1.checkConnectionAndFollowStatus()
        #expect(s1.connectionStatus == .accepted)
        #expect(s1.user?.connectionDirection == nil)

        let (c2, s2) = make(user: user("bob", isFollowing: true), connection: nil)
        c2.checkConnectionAndFollowStatus()
        #expect(s2.connectionStatus == nil)
    }

    @Test func followStatusFallsBackToTheLocalFollowingList() {
        let (c1, s1) = make(user: user("bob"), localFollowing: .some(["bob", "carl"]))
        s1.isFollowing = false
        c1.checkConnectionAndFollowStatus()
        #expect(s1.isFollowing)

        let (c2, s2) = make(user: user("bob"), localFollowing: .some(["carl"]))
        s2.isFollowing = true
        c2.checkConnectionAndFollowStatus()
        #expect(!s2.isFollowing)

        // Cached user loaded but has no following array: not following, no fetch
        let (c3, s3) = make(user: user("bob"), localFollowing: .some(nil))
        s3.isFollowing = true
        c3.checkConnectionAndFollowStatus()
        #expect(!s3.isFollowing)
    }

    @Test func missingCachedUserTriggersOneFetchOnOtherProfiles() {
        let (controller, screen) = make(user: user("bob"), localFollowing: nil)
        var fetches = 0
        controller.fetchCurrentUser = { _ in fetches += 1 }
        controller.checkConnectionAndFollowStatus()
        #expect(!screen.isFollowing)
        #expect(fetches == 1)

        // Own profile: no fetch
        let (own, _) = make(user: user("me"), localFollowing: nil)
        own.fetchCurrentUser = { _ in fetches += 1 }
        own.checkConnectionAndFollowStatus()
        #expect(fetches == 1)
    }
}

import Testing
@testable import Circles_iOS

/// The expanded map's Connection dropdown shows the filtered person's face.
struct MapHeaderFaceTests {
    private func user(_ id: String) -> User {
        User(id: id, displayName: id, profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil)
    }

    @Test func aFilteredPersonShowsTheirFace() {
        let matti = user("matti")
        #expect(MapHeaderFace.user(selectedId: "matti", selectedUser: matti, me: user("me"))?.id == "matti")
    }

    @Test func myPlacesShowsMyFace() {
        #expect(MapHeaderFace.user(selectedId: HomePlaceFilter.myPlacesOnlyId, selectedUser: nil, me: user("me"))?.id == "me")
    }

    @Test func everyoneAndMyConnectionsShowNobody() {
        #expect(MapHeaderFace.user(selectedId: nil, selectedUser: user("matti"), me: user("me")) == nil)
        #expect(MapHeaderFace.user(selectedId: HomePlaceFilter.myConnectionsOnlyId, selectedUser: user("matti"), me: user("me")) == nil)
    }

    @Test func aPersonWithoutAResolvedUserShowsNothingRatherThanTheWrongFace() {
        #expect(MapHeaderFace.user(selectedId: "matti", selectedUser: nil, me: user("me")) == nil)
    }
}

import Testing
import Foundation
@testable import Circles_iOS

/// My Network → Discover: which cards show, and the words on them.
struct NetworkDiscoverLayoutTests {

    private func user(_ id: String) -> User {
        User(id: id, displayName: id, profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil)
    }

    @Test func emptyCardsHideButPeopleAndInviteAlwaysShow() {
        #expect(NetworkDiscoverLayout.cards(lovedPlaces: 5, boardRows: 4, people: 2) == [.lovedPlaces, .leaderboard, .people, .invite])
        // No fresh suggestions: the people card still offers See all
        #expect(NetworkDiscoverLayout.cards(lovedPlaces: 0, boardRows: 1, people: 0) == [.people, .invite])
        #expect(NetworkDiscoverLayout.cards(lovedPlaces: 3, boardRows: 0, people: 0) == [.lovedPlaces, .people, .invite])
    }

    @Test func eachPersonOnceUnderTheirFirstReason() {
        let merged = NetworkDiscoverLayout.mergePeople([[user("a"), user("b")], [user("b"), user("c")], [user("a")]])
        #expect(merged.map(\.id) == ["a", "b", "c"])
        let connected = User(id: "x", displayName: "x", profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil, connectionStatus: "accepted")
        let asked = User(id: "z", displayName: "z", profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil, connectionStatus: "pending")
        #expect(NetworkDiscoverLayout.mergePeople([[connected, user("y"), asked]]).map(\.id) == ["y"])
    }

    @Test func followThenConnectThenStates() {
        func person(_ status: String?, following: Bool?) -> User {
            User(id: "p", displayName: "p", profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil, connectionStatus: status, isFollowing: following)
        }
        #expect(NetworkDiscoverLayout.action(for: person(nil, following: nil)) == .follow)
        #expect(NetworkDiscoverLayout.action(for: person("none", following: false)) == .follow)
        // Following someone is when Connect appears — like LinkedIn
        #expect(NetworkDiscoverLayout.action(for: person("none", following: true)) == .connect)
        #expect(NetworkDiscoverLayout.action(for: person(nil, following: true)) == .connect)
        #expect(NetworkDiscoverLayout.action(for: person("pending", following: true)) == .requestSent)
        #expect(NetworkDiscoverLayout.action(for: person("accepted", following: true)) == .connected)
        #expect(NetworkDiscoverLayout.action(for: person("connected", following: false)) == .connected)
    }

    @Test func savedByReadsNaturally() {
        #expect(NetworkDiscoverLayout.savedByLine(names: ["Brit", "Sal", "Joe"], total: 5) == "Saved by Brit, Sal + 3")
        #expect(NetworkDiscoverLayout.savedByLine(names: ["Brit", "Sal"], total: 2) == "Saved by Brit, Sal")
        #expect(NetworkDiscoverLayout.savedByLine(names: [], total: 4) == "Saved by 4 people")
    }

    @Test func standingLine() {
        #expect(NetworkDiscoverLayout.standingLine(rank: 2, contributors: 48, behindFirst: 8) == "You're 2nd of 48 · 8 behind first")
        #expect(NetworkDiscoverLayout.standingLine(rank: 1, contributors: 48, behindFirst: 0) == "You're 1st of 48 · leading")
        #expect(NetworkDiscoverLayout.standingLine(rank: nil, contributors: 48, behindFirst: nil) == nil)
    }

    @Test func shortCity() {
        #expect(PlaceAddressShort.city("123 Main St, Charlotte, NC 28202") == "Charlotte")
        #expect(PlaceAddressShort.city("Charlotte") == nil)
        #expect(PlaceAddressShort.city("2200 Thrift Rd, Charlotte, NC, 28203, United States") == "Charlotte")
        #expect(PlaceAddressShort.city("Nickyo's, 1500 W Bland St, Charlotte, NC 28203") == "Charlotte")
        #expect(PlaceAddressShort.city("1 Main St, NC 28203") == nil)
    }
}

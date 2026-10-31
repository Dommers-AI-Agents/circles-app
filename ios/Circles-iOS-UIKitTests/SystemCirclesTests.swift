import Foundation
import Testing
@testable import Circles_iOS

/// System circles are found by the server's flag, never by name: a renamed
/// one still works; the name is only a fallback for an unflagged legacy circle.
struct SystemCirclesTests {
    private struct Stub: SystemCircleFlagged {
        let id: String
        let name: String
        var systemKind: String? = nil
        var isDefaultCircle: Bool? = nil
    }

    @Test func renamedFlaggedCircleIsStillFound() {
        let circles = [
            Stub(id: "mine", name: "Eateries"),
            Stub(id: "fav", name: "My block", systemKind: "favoriteLocal", isDefaultCircle: true)
        ]
        #expect(SystemCircles.first(.favoriteLocal, in: circles)?.id == "fav")
    }

    @Test func flagBeatsALegacyNameMatch() {
        let circles = [
            Stub(id: "lookalike", name: "Favorite Local Spots"),
            Stub(id: "real", name: "Around here", systemKind: "favoriteLocal")
        ]
        #expect(SystemCircles.first(.favoriteLocal, in: circles)?.id == "real")
    }

    @Test func legacyUnflaggedCircleMatchesByName() {
        let circles = [Stub(id: "a", name: "Eateries"), Stub(id: "b", name: "Favorite Local Spots")]
        #expect(SystemCircles.first(.favoriteLocal, in: circles)?.id == "b")
        #expect(SystemCircles.first(.wantToTry, in: circles) == nil)
    }

    @Test func aFlaggedCircleIsOnlyItsOwnKind() {
        let followed = Stub(id: "f", name: "Places from my photos", systemKind: "followedPlaces")
        #expect(SystemCircles.isKind(.followedPlaces, followed))
        #expect(!SystemCircles.isKind(.photoPlaces, followed))
        #expect(SystemCircles.isKind(.photoPlaces, Stub(id: "p", name: "Camera roll", systemKind: "photoPlaces")))
        #expect(SystemCircles.isKind(.photoPlaces, Stub(id: "l", name: "Places from my photos")))
    }

    @Test func startersByFlagThenLegacyName() {
        #expect(SystemCircles.isStarter(Stub(id: "1", name: "Trips", isDefaultCircle: true)))
        #expect(SystemCircles.isStarter(Stub(id: "2", name: "Someday", systemKind: "wantToTry")))
        #expect(SystemCircles.isStarter(Stub(id: "3", name: "Vacation")))
        #expect(!SystemCircles.isStarter(Stub(id: "4", name: "Eateries")))
        #expect(!SystemCircles.isStarter(Stub(id: "5", name: "Vacation", systemKind: "dogSpots")))
    }

    @Test func rawValuesMatchTheServer() {
        #expect(SystemCircleKind.allCases.map(\.rawValue)
            == ["followedPlaces", "checkIns", "favoriteLocal", "wantToTry", "dogSpots", "photoPlaces"])
    }

    @Test func photoDoneLineUsesTheCircleCurrentName() {
        #expect(PhotoMapPlanner.doneLine(added: 2, circleName: "Camera roll") == "Added 2 places to \u{201C}Camera roll.\u{201D}")
        #expect(PhotoMapPlanner.doneLine(added: 1).contains("Places from my photos"))
    }
}

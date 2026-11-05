import Foundation
import Testing
@testable import Circles_iOS

/// My Network opens on its last list (2026-11-05): a saved person must read
/// back with what the rows show and the buttons decide on
struct ScreenSnapshotTests {
    @Test func aSavedPersonReadsBackTheSame() throws {
        let json = #"{"_id":"u1","displayName":"Brittany C","profilePicture":"https://x/b.jpg","isFollowing":true,"followsYou":true,"connectionStatus":"accepted","placesCount":42}"#
        let decoder = APIService.makeResponseDecoder()
        let original = try decoder.decode(User.self, from: Data(json.utf8))
        let back = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(original))
        #expect(back.id == "u1")
        #expect(back.displayName == "Brittany C")
        #expect(back.profilePicture == original.profilePicture)
        #expect(back.isFollowing == true)
        #expect(back.followsYou == true)
        #expect(back.connectionStatus == "accepted")
        #expect(back.placesCount == original.placesCount)
    }
}

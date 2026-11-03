import Foundation
import Testing
@testable import Circles_iOS

/// "Only what changed" must give the same list a full download does
struct PlaceBatchSyncTests {
    private func place(_ id: String, _ name: String, isNew: Bool = false) -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "likesCount": .int(3), "rating": .double(4.5),
                 "closed": .null, "isNew": .bool(isNew), "tags": .array([.string("coffee")])])
    }

    @Test func changedPlacesReplaceTheirCopiesInTheServersOrder() {
        let cached = [place("a", "A"), place("b", "B"), place("c", "C")]
        let merged = PlaceBatchSync.merge(cached: cached, changed: [place("b", "B renamed")], ids: ["c", "b", "a"], newIds: ["a"])
        #expect(merged == [place("c", "C"), place("b", "B renamed"), place("a", "A", isNew: true)])
    }

    @Test func removedPlacesDropOutAndNewOnesComeIn() {
        let cached = [place("a", "A"), place("b", "B")]
        let merged = PlaceBatchSync.merge(cached: cached, changed: [place("d", "D")], ids: ["a", "d"], newIds: [])
        #expect(merged?.compactMap(\.placeId) == ["a", "d"])
    }

    @Test func aGapMeansDownloadInFull() {
        #expect(PlaceBatchSync.merge(cached: [place("a", "A")], changed: [], ids: ["a", "x"], newIds: []) == nil)
    }

    @Test func wireJSONSurvivesTheRoundTrip() throws {
        let json = #"{"id":"a","n":938,"r":4.5,"x":null,"b":true,"s":"hi","l":[1,"two"],"o":{"k":false}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let back = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(back == value)
        guard case .object(let fields) = value else { Issue.record("not an object"); return }
        #expect(fields["n"] == .int(938))   // whole numbers stay whole (Int fields still decode)
        #expect(fields["x"] == .null)
    }
}

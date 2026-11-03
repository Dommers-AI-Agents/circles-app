import Foundation
import Testing
@testable import Circles_iOS

/// "Only what changed" must give the same list a full download does
struct DeltaSyncTests {
    private func place(_ id: String, _ name: String, isNew: Bool = false) -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "likesCount": .int(3), "rating": .double(4.5),
                 "closed": .null, "isNew": .bool(isNew), "tags": .array([.string("coffee")])])
    }

    @Test func changedItemsReplaceTheirCopiesInTheServersOrder() {
        let cached = [place("a", "A"), place("b", "B"), place("c", "C")]
        let dotted: Set<String> = ["a"]
        let merged = DeltaSync.merge(cached: cached, changed: [place("b", "B renamed")], ids: ["c", "b", "a"]) { id, fields in
            fields["isNew"] = .bool(dotted.contains(id))
        }
        #expect(merged == [place("c", "C"), place("b", "B renamed"), place("a", "A", isNew: true)])
    }

    @Test func removedItemsDropOutAndNewOnesComeIn() {
        let merged = DeltaSync.merge(cached: [place("a", "A"), place("b", "B")], changed: [place("d", "D")], ids: ["a", "d"])
        #expect(merged?.compactMap(\.itemId) == ["a", "d"])
    }

    @Test func aGapMeansDownloadInFull() {
        #expect(DeltaSync.merge(cached: [place("a", "A")], changed: [], ids: ["a", "x"]) == nil)
    }

    @Test func ownerCardsAreRestampedOnEveryCircle() {
        let circle: JSONValue = .object(["_id": .string("c1"), "owner": .string("u1"), "ownerDetails": .object(["displayName": .string("Old name")])])
        let owners: [String: JSONValue] = ["u1": .object(["displayName": .string("New name")])]
        let merged = DeltaSync.merge(cached: [circle], changed: [], ids: ["c1"]) { _, fields in
            if case .string(let owner)? = fields["owner"] { fields["ownerDetails"] = owners[owner] ?? .null }
        }
        guard case .object(let fields)? = merged?.first, case .object(let details)? = fields["ownerDetails"] else {
            Issue.record("no owner card"); return
        }
        #expect(details["displayName"] == .string("New name"))
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

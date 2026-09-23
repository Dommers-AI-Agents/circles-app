import Testing
import Foundation
@testable import Circles_iOS

/// One row the app has never heard of must not take the other 72 with it.
@Suite("Connection decoding")
struct ConnectionDecodingTests {
    private func decode(_ json: String) throws -> ConnectionsResponse {
        try JSONDecoder().decode(ConnectionsResponse.self, from: Data(json.utf8))
    }

    @Test func aMergeTombstoneDecodesAsUnknownAndTheListSurvives() throws {
        let response = try decode("""
        {"success":true,"connections":[
          {"id":"a","userId":"me","connectedUserId":"friend","status":"accepted"},
          {"id":"b","userId":"me","connectedUserId":"ghost","status":"merged"}
        ]}
        """)
        #expect(response.connections.count == 2)
        #expect(response.connections[0].status == .accepted)
        #expect(response.connections[1].status == .unknown)
    }

    @Test func theAcceptedFilterLeavesAnUnknownRowOut() throws {
        let response = try decode("""
        {"success":true,"connections":[
          {"id":"a","userId":"me","connectedUserId":"friend","status":"accepted"},
          {"id":"b","userId":"me","connectedUserId":"ghost","status":"merged"}
        ]}
        """)
        let people = response.connections.filter { $0.status == .accepted }
        #expect(people.map(\.connectedUserId) == ["friend"])
    }

    @Test func knownStatusesStillDecodeExactly() throws {
        for (raw, expected) in [("pending", ConnectionStatus.pending), ("accepted", .accepted), ("blocked", .blocked), ("following", .following)] {
            let response = try decode("""
            {"success":true,"connections":[{"id":"x","userId":"me","connectedUserId":"y","status":"\(raw)"}]}
            """)
            #expect(response.connections.first?.status == expected)
        }
    }
}

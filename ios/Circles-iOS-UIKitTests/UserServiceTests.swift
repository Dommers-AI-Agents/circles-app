import Foundation
import Testing
@testable import Circles_iOS

/// UserService against a fake APIClient: what it asks for and how it reads
/// the answer.
struct UserServiceTests {
    @Test func searchUsersHitsSearchWithTheQuery() {
        let api = FakeAPIClient()
        api.responseJSON = #"{"success": true, "users": []}"#
        let service = UserService(api: api)

        service.searchUsers(query: "brit s") { _ in }

        #expect(api.calls.count == 1)
        #expect(api.calls.first?.endpoint == "users/search")
        #expect(api.calls.first?.method == .get)
        #expect(api.calls.first?.queryParams == ["query": "brit s"])
        #expect(api.calls.first?.requiresAuth == true)
    }

    @Test func searchUsersDecodesUsersAndDropsBadRows() throws {
        let api = FakeAPIClient()
        api.responseJSON = #"""
        {"success": true, "users": [
            {"_id": "u1", "displayName": "Brit"},
            {"displayName": 42},
            {"_id": "u2", "displayName": "Sal"}
        ]}
        """#
        let service = UserService(api: api)

        var received: Result<[User], Error>?
        service.searchUsers(query: "s") { received = $0 }

        let users = try #require(try received?.get())
        #expect(users.map(\.id) == ["u1", "u2"])
        #expect(users.map(\.displayName) == ["Brit", "Sal"])
    }

    @Test func searchUsersSurfacesTheServersReason() {
        let api = FakeAPIClient()
        api.error = .httpError(429, Data(#"{"error": "Slow down"}"#.utf8))
        let service = UserService(api: api)

        var received: Result<[User], Error>?
        service.searchUsers(query: "s") { received = $0 }

        guard case .failure(let error)? = received else {
            Issue.record("expected a failure"); return
        }
        #expect(error.localizedDescription == "Slow down")
    }
}

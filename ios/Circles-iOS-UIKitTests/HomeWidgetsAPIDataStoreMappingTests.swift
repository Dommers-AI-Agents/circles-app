import Testing
import Foundation
import FavWidgetsCore
@testable import Circles_iOS

/// The bridge between the app's transport errors / wire shape and the
/// FavWidgets package contract, exercised without a network.
struct HomeWidgetsAPIDataStoreMappingTests {
    @Test func conflictCarriesTheServerDocument() throws {
        let body = """
        {"success":false,"code":"VERSION_CONFLICT","current":{"widgetId":"water","version":4,"payload":"{\\"goalCups\\":9}","schemaVersion":1,"updatedAt":"2026-09-13T10:00:00.000Z"}}
        """
        let error = HomeWidgetsAPIDataStore.storeError(from: .httpError(409, Data(body.utf8)))
        guard case .conflict(let server) = error, let server else {
            Issue.record("expected conflict with server doc, got \(error)")
            return
        }
        #expect(server.version == 4)
        #expect(String(decoding: server.payload, as: UTF8.self) == #"{"goalCups":9}"#)
        #expect(server.updatedAt != nil)
    }

    @Test func conflictWithoutBodyStillConflicts() {
        let error = HomeWidgetsAPIDataStore.storeError(from: .httpError(409, nil))
        #expect(error == .conflict(server: nil))
    }

    @Test func statusCodesMapToStoreErrors() {
        #expect(HomeWidgetsAPIDataStore.storeError(from: .httpError(413, nil)) == .payloadTooLarge(bytes: 0))
        #expect(HomeWidgetsAPIDataStore.storeError(from: .httpError(401, nil)) == .unauthorized)
        #expect(HomeWidgetsAPIDataStore.storeError(from: .httpError(404, nil)) == .notFound)
        #expect(HomeWidgetsAPIDataStore.storeError(from: .unauthorized) == .unauthorized)
        #expect(HomeWidgetsAPIDataStore.storeError(from: .noInternet) == .network("No internet connection"))
    }

    @Test func documentDecodesFromWireShape() throws {
        let json = #"{"widgetId":"habits","version":2,"payload":"{}","schemaVersion":3,"updatedAt":"2026-09-13T10:00:00Z"}"#
        let dto = try JSONDecoder().decode(HomeWidgetsAPIDataStore.DocumentDTO.self, from: Data(json.utf8))
        let document = dto.document
        #expect(document.version == 2 && document.schemaVersion == 3)
        #expect(document.payload == Data("{}".utf8))
        #expect(document.updatedAt != nil)
    }
}

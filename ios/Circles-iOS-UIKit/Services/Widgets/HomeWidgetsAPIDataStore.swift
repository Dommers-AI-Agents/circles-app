import Foundation
import FavWidgets
import FavWidgetsCore

/// The FavWidgets package's `WidgetDataStore`, backed by `/api/widgets/data`.
/// Not the WidgetKit home-screen widget (see `WidgetSnapshotStore`) — this
/// is the Widgets tab's per-user mini-app documents.
///
/// Wire format: `payload` travels as a JSON *string* both ways, so the
/// package's `Data` payload is just its UTF-8 bytes. A 409 carries the
/// server's current document so the package can merge without a refetch.
final class HomeWidgetsAPIDataStore: WidgetDataStore {
    struct DocumentDTO: Decodable {
        let widgetId: String
        let version: Int
        let payload: String
        let schemaVersion: Int?
        let updatedAt: String?

        var document: WidgetDocument {
            WidgetDocument(
                version: version,
                payload: Data(payload.utf8),
                schemaVersion: schemaVersion ?? 1,
                updatedAt: updatedAt.flatMap { ISO8601DateFormatter.piggyFlexible.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            )
        }
    }

    private struct ListResponse: Decodable {
        let success: Bool
        let documents: [DocumentDTO]
    }

    private struct SingleResponse: Decodable {
        let success: Bool
        let document: DocumentDTO?
        let piggyBank: PiggyBankCredit?
    }

    struct ConflictBody: Decodable {
        let code: String?
        let current: DocumentDTO?
    }

    // MARK: - WidgetDataStore

    func load(ids: [String]) async throws -> [String: WidgetDocument] {
        guard !ids.isEmpty else { return [:] }
        let response: ListResponse = try await call(endpoint: "widgets/data", method: .get,
                                                    queryParams: ["ids": ids.joined(separator: ",")])
        var result: [String: WidgetDocument] = [:]
        for dto in response.documents { result[dto.widgetId] = dto.document }
        return result
    }

    func load(id: String) async throws -> WidgetDocument? {
        let response: SingleResponse = try await call(endpoint: "widgets/data/\(id)", method: .get)
        return response.document?.document
    }

    func save(id: String, document: WidgetDocument) async throws -> WidgetDocument {
        let body: [String: Any] = [
            "version": document.version,
            "payload": String(decoding: document.payload, as: UTF8.self),
            "schemaVersion": document.schemaVersion
        ]
        let response: SingleResponse = try await call(endpoint: "widgets/data/\(id)", method: .put, body: body)
        guard let saved = response.document?.document else {
            throw WidgetDataStoreError.decoding("Save returned no document")
        }
        // The first save of the day may earn FavCoins; the animation is
        // nil-safe and only plays for an actual credit.
        PiggyBankDepositView.play(credit: response.piggyBank)
        return saved
    }

    // MARK: - Bridging

    private func call<T: Decodable>(endpoint: String, method: RequestMethod, queryParams: [String: String]? = nil, body: [String: Any]? = nil) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(endpoint: endpoint, method: method, queryParams: queryParams, body: body, requiresAuth: true) { (result: Result<T, APIError>) in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: Self.storeError(from: error))
                }
            }
        }
    }

    /// Maps the app's transport errors onto the package's store errors.
    static func storeError(from error: APIError) -> WidgetDataStoreError {
        switch error {
        case .httpError(let status, let data):
            switch status {
            case 409:
                let body = data.flatMap { try? JSONDecoder().decode(ConflictBody.self, from: $0) }
                // Not another device — this build is older than the stored
                // schema, and only an update fixes that.
                if body?.code == "SCHEMA_TOO_OLD" { return .schemaTooOld }
                return .conflict(server: body?.current?.document)
            case 413:
                return .payloadTooLarge(bytes: 0)
            case 401, 403:
                return .unauthorized
            case 404:
                return .notFound
            default:
                return .network(error.serverMessage ?? "Server error (\(status))")
            }
        case .unauthorized:
            return .unauthorized
        case .noInternet:
            return .network("No internet connection")
        case .decodingFailed(let inner):
            return .decoding(inner.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }
}

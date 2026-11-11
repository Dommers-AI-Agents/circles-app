import Foundation

/// Scan Actions API (2026-11-11): make a QR, read what a code does, do it.
/// Backend: routes/scanActionRoutes.js → services/scanActionService.js.
final class ScanActionService {
    static let shared = ScanActionService()

    /// The most a set QR holds (the server's MAX_SET_PLACES)
    static let maxSetPlaces = 50

    /// A refusal the server explained (`code` to switch on, words to show)
    struct Refusal: Error, LocalizedError, Equatable {
        let status: Int
        let code: String?
        let message: String
        var errorDescription: String? { message }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let data: T
    }

    private struct ServerError: Decodable {
        let code: String?
        let message: String?
        let error: String?
    }

    private func mapError(_ error: APIError) -> Error {
        if case .httpError(let status, let data) = error, let data,
           let body = try? JSONDecoder().decode(ServerError.self, from: data) {
            return Refusal(status: status, code: body.code, message: body.message ?? body.error ?? error.localizedDescription)
        }
        return error
    }

    private func call<T: Decodable>(_ endpoint: String, method: RequestMethod, body: [String: Any]? = nil,
                                    requiresAuth: Bool = true, completion: @escaping (Result<T, Error>) -> Void) {
        APIService.shared.request(endpoint: endpoint, method: method, body: body, requiresAuth: requiresAuth) { [weak self] (result: Result<Envelope<T>, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let envelope): completion(.success(envelope.data))
                case .failure(let error): completion(.failure(self?.mapError(error) ?? error))
                }
            }
        }
    }

    // MARK: - Making a QR

    /// One place (a save of theirs or one they can see). `globalPlaceId` is
    /// the venue, used when the page shows the venue rather than a save.
    func createPlace(saveId: String, globalPlaceId: String?, note: String? = nil, completion: @escaping (Result<ScanActionCreated, Error>) -> Void) {
        var body: [String: Any] = ["kind": "place", "saveId": saveId]
        if let globalPlaceId { body["globalPlaceId"] = globalPlaceId }
        if let note, !note.isEmpty { body["note"] = note }
        call("scan-actions", method: .post, body: body, completion: completion)
    }

    /// A list (a filtered circle or Home view), frozen as it is now
    func createSet(title: String, saveIds: [String], source: [String: String] = [:],
                   completion: @escaping (Result<ScanActionCreated, Error>) -> Void) {
        let body: [String: Any] = ["kind": "placeSet", "title": title,
                                   "saveIds": Array(saveIds.prefix(Self.maxSetPlaces)), "source": source]
        call("scan-actions", method: .post, body: body, completion: completion)
    }

    /// A store owner's setup QR for one store (super-users)
    func createStoreSetup(venueId: String?, globalPlaceId: String?, completion: @escaping (Result<ScanActionCreated, Error>) -> Void) {
        var body: [String: Any] = ["kind": "storeSetup"]
        if let venueId { body["venueId"] = venueId }
        if let globalPlaceId { body["globalPlaceId"] = globalPlaceId }
        call("scan-actions", method: .post, body: body, completion: completion)
    }

    // MARK: - Scanning one

    func resolve(code: String, completion: @escaping (Result<ScanAction, Error>) -> Void) {
        call("scan-actions/\(code)", method: .get, requiresAuth: AuthService.shared.isLoggedIn, completion: completion)
    }

    /// Saves the ticked places into `circleId`. `requestId` is one per tap of
    /// Save, so a resend on a weak signal never saves twice.
    func savePlaces(code: String, globalPlaceIds: [String], circleId: String, requestId: String,
                    completion: @escaping (Result<ScanActionSaveResult, Error>) -> Void) {
        let body: [String: Any] = ["globalPlaceIds": globalPlaceIds, "circleId": circleId, "requestId": requestId]
        call("scan-actions/\(code)/complete", method: .post, body: body, completion: completion)
    }

    /// Redeems a store setup QR: the store becomes theirs
    func redeemStore(code: String, contactName: String?, contactPhone: String?,
                     completion: @escaping (Result<ScanActionStoreResult, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let contactName, !contactName.isEmpty { body["contactName"] = contactName }
        if let contactPhone, !contactPhone.isEmpty { body["contactPhone"] = contactPhone }
        call("scan-actions/\(code)/complete", method: .post, body: body, completion: completion)
    }
}

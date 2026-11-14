import Foundation

// Trimmed fork of the app's APIService (Services/APIService.swift) — plain
// URLSession + Codable, none of the retry/dedup/rate-limit machinery. The clip
// calls: venue preview, email code start/verify, Apple sign-in, sticker scan,
// and its notification token.
enum ClipAPIError: LocalizedError {
    case network(Error)
    case server(String)
    /// The server's error code with its message (VERIFY_REQUIRED, CODE_INVALID…)
    case coded(String, String)
    case decoding
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .network: return "Couldn't reach FavCircles. Check your connection and try again."
        case .server(let message): return message
        case .coded(_, let message): return message
        case .decoding: return "Something went wrong. Please try again."
        case .unauthorized: return "Please sign in again."
        }
    }
}

final class ClipAPIClient {
    static let shared = ClipAPIClient()
    private init() {}

    // Same production base URL as APIService.APIEnvironment
    private let baseURL = URL(string: "https://circles-backend-196924649787.us-central1.run.app/api")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Endpoints

    /// `tag`: the NFC sticker that was tapped, counted with the preview
    func venuePreview(code: String, tag: String? = nil, coupon: String? = nil) async throws -> VenuePreview {
        var query: [URLQueryItem] = []
        if let tag { query.append(URLQueryItem(name: "t", value: tag)) }
        if let coupon { query.append(URLQueryItem(name: "c", value: coupon)) }
        let response: VenuePreviewResponse = try await request(path: "clip/venue/\(code)", method: "GET",
                                                               query: query.isEmpty ? nil : query)
        return response.data
    }

    /// Just an email, straight in (Wes, 2026-10-31): a new email gets an
    /// account on the spot, confirmed later in the app. An email that already
    /// has an account answers VERIFY_REQUIRED and the server emails the code.
    func emailInstant(email: String, stickerCode: String?) async throws -> ClipAuthResponse {
        var body: [String: Any] = ["email": email]
        if let stickerCode {
            body["signupSource"] = "app_clip"
            body["stickerCode"] = stickerCode
        }
        return try await request(path: "auth/email-instant", method: "POST", body: body)
    }

    /// Emails a 6-digit code (no password anywhere in the clip)
    func startEmailCode(email: String) async throws -> EmailCodeStartResponse {
        try await request(path: "auth/email-code/start", method: "POST", body: ["email": email])
    }

    /// The code → a session: signs in, or creates the account when `displayName` is given
    func verifyEmailCode(email: String, code: String, displayName: String?, stickerCode: String?) async throws -> ClipAuthResponse {
        var body: [String: Any] = ["email": email, "code": code]
        if let displayName, !displayName.isEmpty { body["displayName"] = displayName }
        if let stickerCode {
            body["signupSource"] = "app_clip"
            body["stickerCode"] = stickerCode
        }
        return try await request(path: "auth/email-code/verify", method: "POST", body: body)
    }

    // Apple identity token → backend JWT. Mirrors the body AuthService.loginWithSocialProvider
    // sends to auth/firebase ({idToken, name?, email?}), plus the clip attribution fields.
    func loginWithApple(idToken: String, name: String?, email: String?, stickerCode: String?) async throws -> ClipAuthResponse {
        var body: [String: Any] = ["idToken": idToken]
        if let name = name, !name.isEmpty { body["name"] = name }
        if let email = email, !email.isEmpty { body["email"] = email }
        if let stickerCode = stickerCode {
            body["signupSource"] = "app_clip"
            body["stickerCode"] = stickerCode
        }
        return try await request(path: "auth/firebase", method: "POST", body: body)
    }

    /// `atStore`: Apple's location check (nil when it couldn't tell)
    /// `save`: a window code saves the store for them (2026-11-01)
    func redeemSticker(code: String, token: String, atStore: Bool?, save: Bool = false, ref: String? = nil, coupon: String? = nil) async throws -> ScanResult {
        var body: [String: Any] = ["code": code]
        if let atStore { body["atStore"] = atStore }
        if save { body["save"] = true }
        if let ref { body["ref"] = ref }
        if let coupon { body["c"] = coupon }
        let response: ScanResponse = try await request(
            path: "rewards/scan", method: "POST",
            body: body,
            bearerToken: token
        )
        return response.data
    }

    /// The clip's notification token: one reminder within Apple's 8-hour
    /// window if they haven't installed the app yet (server decides)
    /// A quick 0–10 FavCircles rating on the store they just saved (their own
    /// save record; Wes, 2026-11-09). Same PUT the app's rating sheet uses.
    func ratePlace(placeId: String, rating: Int, bearer: String) async throws {
        let _: ClipSimpleResponse = try await request(path: "places/\(placeId)", method: "PUT",
                                                      body: ["userRating": rating], bearerToken: bearer)
    }

    /// Join the store's waitlist from the clip (2026-11-09); the host's Notify pushes this phone
    func joinWaitlist(venueId: String, partySize: Int, bearer: String) async throws -> ClipWaitlistEntry {
        let response: ClipWaitlistResponse = try await request(path: "waitlist/\(venueId)/join", method: "POST",
                                                               body: ["partySize": partySize], bearerToken: bearer)
        return response.data
    }

    func registerDevice(token deviceToken: String, code: String?, bearer: String) async throws {
        var body: [String: Any] = ["token": deviceToken]
        if let code { body["code"] = code }
        #if DEBUG
        body["environment"] = "development" // Xcode builds get sandbox tokens
        #endif
        let _: ClipSimpleResponse = try await request(path: "clip/device", method: "POST", body: body, bearerToken: bearer)
    }

    /// A Scan Action QR (/q/<code>, 2026-11-11): what it holds
    func scanAction(code: String, bearer: String?) async throws -> ClipScanAction {
        let response: ClipScanActionResponse = try await request(path: "scan-actions/\(code)", method: "GET", bearerToken: bearer)
        return response.data
    }

    /// Saves every place in it to their Want to Try (the clip has no circle
    /// picker; the app lets them move it). `requestId`: a resend never saves twice.
    func saveScanAction(code: String, requestId: String, bearer: String) async throws -> ClipScanSaveResult {
        let response: ClipScanSaveResponse = try await request(path: "scan-actions/\(code)/complete", method: "POST",
                                                               body: ["requestId": requestId], bearerToken: bearer)
        return response.data
    }

    // MARK: - Core

    private func request<T: Decodable>(path: String,
                                       method: String,
                                       query: [URLQueryItem]? = nil,
                                       body: [String: Any]? = nil,
                                       bearerToken: String? = nil) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        if let query, !query.isEmpty { url.append(queryItems: query) }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken = bearerToken {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ClipAPIError.network(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            if statusCode == 401 { throw ClipAPIError.unauthorized }
            if let errorBody = try? JSONDecoder().decode(ClipErrorBody.self, from: data),
               let message = errorBody.message ?? errorBody.error {
                if let code = errorBody.code { throw ClipAPIError.coded(code, message) }
                throw ClipAPIError.server(message)
            }
            throw ClipAPIError.server("Something went wrong (\(statusCode)). Please try again.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClipAPIError.decoding
        }
    }
}

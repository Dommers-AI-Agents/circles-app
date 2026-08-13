import Foundation

// Trimmed fork of the app's APIService (Services/APIService.swift) — plain
// URLSession + Codable, none of the retry/dedup/rate-limit machinery. The clip
// makes exactly four calls: venue preview, register, Apple sign-in, sticker scan.
enum ClipAPIError: LocalizedError {
    case network(Error)
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .network: return "Couldn't reach FavCircles. Check your connection and try again."
        case .server(let message): return message
        case .decoding: return "Something went wrong. Please try again."
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

    func venuePreview(code: String) async throws -> VenuePreview {
        let response: VenuePreviewResponse = try await request(path: "clip/venue/\(code)", method: "GET")
        return response.data
    }

    func register(email: String, password: String, displayName: String, stickerCode: String?) async throws -> ClipAuthResponse {
        var body: [String: Any] = [
            "email": email,
            "password": password,
            "displayName": displayName
        ]
        if let stickerCode = stickerCode {
            body["signupSource"] = "app_clip"
            body["stickerCode"] = stickerCode
        }
        return try await request(path: "auth/register", method: "POST", body: body)
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

    func redeemSticker(code: String, token: String) async throws -> ScanResult {
        let response: ScanResponse = try await request(
            path: "rewards/scan", method: "POST",
            body: ["code": code],
            bearerToken: token
        )
        return response.data
    }

    // MARK: - Core

    private func request<T: Decodable>(path: String,
                                       method: String,
                                       body: [String: Any]? = nil,
                                       bearerToken: String? = nil) async throws -> T {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
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
            if let errorBody = try? JSONDecoder().decode(ClipErrorBody.self, from: data),
               let message = errorBody.error ?? errorBody.message {
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

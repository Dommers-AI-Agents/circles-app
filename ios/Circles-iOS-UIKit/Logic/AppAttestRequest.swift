import CryptoKit
import Foundation

/// What the phone signs for a protected request, and the headers it sends
/// (2026-11-01). Must match the server's appAttestService.clientDataFor:
/// "<METHOD> <path> <unix time>". Pure.
enum AppAttestRequest {

    static func clientData(method: String, path: String, time: Int) -> Data {
        Data("\(method.uppercased()) \(path) \(time)".utf8)
    }

    static func clientDataHash(method: String, path: String, time: Int) -> Data {
        Data(SHA256.hash(data: clientData(method: method, path: path, time: time)))
    }

    /// The request path the server sees for an APIService endpoint
    /// ("rewards/scan" → "/api/rewards/scan")
    static func path(baseURL: String, endpoint: String) -> String {
        URL(string: "\(baseURL)/\(endpoint)")?.path ?? "/\(endpoint)"
    }

    static func headers(keyId: String?, assertion: Data?, time: Int, capable: Bool) -> [String: String] {
        var headers: [String: String] = capable ? ["X-App-Attest-Capable": "1"] : [:]
        if let keyId, let assertion {
            headers["X-App-Attest-Key"] = keyId
            headers["X-App-Attest-Assertion"] = assertion.base64EncodedString()
            headers["X-App-Attest-Time"] = String(time)
        }
        return headers
    }
}

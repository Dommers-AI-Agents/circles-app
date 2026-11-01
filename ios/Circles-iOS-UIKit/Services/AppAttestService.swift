import CryptoKit
import DeviceCheck
import Foundation

/// Apple App Attest (2026-11-01): proves to the server that requests moving
/// points and coins come from the real FavCircles app on a real iPhone.
/// One key per install, made and registered once (`prepare`); every
/// protected request then carries a fresh assertion (`headers`).
///
/// The server only watches for now (monitor mode), so any failure here just
/// means a request goes without an assertion. Simulators and the App Clip
/// can't attest and send nothing.
final class AppAttestService {

    static let shared = AppAttestService()

    private let service = DCAppAttestService.shared
    private let defaults = UserDefaults.standard
    // UserDefaults, not the Keychain: the key itself dies with the app, and
    // the Keychain would hand a reinstall a key id that no longer exists
    private let keyIdKey = "appAttest.keyId"
    private let registeredKey = "appAttest.registered"
    private let lock = NSLock()
    private var preparing = false

    var isSupported: Bool { service.isSupported }

    private init() {}

    /// Makes and registers this install's key, once. Cheap to call often.
    func prepare() {
        guard isSupported, KeychainService.shared.getAuthToken() != nil else { return }
        lock.lock()
        if preparing || defaults.bool(forKey: registeredKey) { lock.unlock(); return }
        preparing = true
        lock.unlock()
        Task {
            defer { lock.lock(); preparing = false; lock.unlock() }
            do {
                let keyId: String
                if let existing = defaults.string(forKey: keyIdKey) {
                    keyId = existing
                } else {
                    keyId = try await service.generateKey()
                    defaults.set(keyId, forKey: keyIdKey)
                }
                let challenge = try await fetchChallenge()
                let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
                let attestation = try await service.attestKey(keyId, clientDataHash: hash)
                try await register(keyId: keyId, attestation: attestation, challenge: challenge)
                defaults.set(true, forKey: registeredKey)
            } catch {
                // A key Apple won't attest (or lost) starts over next time
                if (error as? DCError)?.code == .invalidKey { reset() }
                Logger.debug("App Attest prepare failed: \(error.localizedDescription)")
            }
        }
    }

    /// Headers for one protected request. Always calls back (main queue),
    /// with an assertion when this install has a registered key.
    func headers(method: String, endpoint: String, completion: @escaping ([String: String]) -> Void) {
        let time = Int(Date().timeIntervalSince1970)
        let finish: ([String: String]) -> Void = { headers in DispatchQueue.main.async { completion(headers) } }
        guard isSupported else { return finish([:]) }
        guard defaults.bool(forKey: registeredKey), let keyId = defaults.string(forKey: keyIdKey) else {
            prepare()
            return finish(AppAttestRequest.headers(keyId: nil, assertion: nil, time: time, capable: true))
        }
        let path = AppAttestRequest.path(baseURL: APIEnvironment.current.baseURL, endpoint: endpoint)
        let hash = AppAttestRequest.clientDataHash(method: method, path: path, time: time)
        Task {
            do {
                let assertion = try await service.generateAssertion(keyId, clientDataHash: hash)
                finish(AppAttestRequest.headers(keyId: keyId, assertion: assertion, time: time, capable: true))
            } catch {
                if (error as? DCError)?.code == .invalidKey { reset(); prepare() }
                finish(AppAttestRequest.headers(keyId: nil, assertion: nil, time: time, capable: true))
            }
        }
    }

    private func reset() {
        defaults.removeObject(forKey: keyIdKey)
        defaults.removeObject(forKey: registeredKey)
    }

    // MARK: - Server

    private struct ChallengeData: Codable { let challenge: String }
    private struct RegisterData: Codable { let environment: String? }
    private struct Envelope<T: Codable>: Codable { let success: Bool; let data: T }

    private func fetchChallenge() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(endpoint: "attest/challenge", method: .get, requiresAuth: true) {
                (result: Result<Envelope<ChallengeData>, APIError>) in
                continuation.resume(with: result.map(\.data.challenge).mapError { $0 as Error })
            }
        }
    }

    private func register(keyId: String, attestation: Data, challenge: String) async throws {
        let body: [String: Any] = ["keyId": keyId, "attestation": attestation.base64EncodedString(), "challenge": challenge]
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RegisterData, Error>) in
            APIService.shared.request(endpoint: "attest/register", method: .post, body: body, requiresAuth: true) {
                (result: Result<Envelope<RegisterData>, APIError>) in
                continuation.resume(with: result.map(\.data).mapError { $0 as Error })
            }
        }
    }
}

extension APIService {
    /// `request`, plus this install's App Attest assertion for the server to
    /// check: for calls that move points or coins (2026-11-01)
    func attestedRequest<T: Decodable>(
        endpoint: String,
        method: RequestMethod,
        body: [String: Any]? = nil,
        requiresAuth: Bool = true,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        AppAttestService.shared.headers(method: method.rawValue, endpoint: endpoint) { headers in
            self.request(endpoint: endpoint, method: method, body: body, headers: headers.isEmpty ? nil : headers,
                         requiresAuth: requiresAuth, completion: completion)
        }
    }
}

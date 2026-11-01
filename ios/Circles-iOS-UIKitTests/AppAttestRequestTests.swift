import CryptoKit
import Foundation
import Testing
@testable import Circles_iOS

/// App Attest: what the phone signs must match the server's clientDataFor
struct AppAttestRequestTests {

    @Test func clientDataMatchesTheServer() {
        let data = AppAttestRequest.clientData(method: "post", path: "/api/rewards/scan", time: 1_730_000_000)
        #expect(String(data: data, encoding: .utf8) == "POST /api/rewards/scan 1730000000")
        #expect(AppAttestRequest.clientDataHash(method: "post", path: "/api/rewards/scan", time: 1_730_000_000)
                == Data(SHA256.hash(data: data)))
    }

    @Test func pathIsWhatTheServerSees() {
        #expect(AppAttestRequest.path(baseURL: "https://circles-backend-196924649787.us-central1.run.app/api", endpoint: "rewards/scan")
                == "/api/rewards/scan")
        #expect(AppAttestRequest.path(baseURL: "https://api.favcircles.com/api", endpoint: "piggy-bank/claim")
                == "/api/piggy-bank/claim")
    }

    @Test func headers() {
        let full = AppAttestRequest.headers(keyId: "k1", assertion: Data([1, 2, 3]), time: 42, capable: true)
        #expect(full == ["X-App-Attest-Capable": "1", "X-App-Attest-Key": "k1", "X-App-Attest-Assertion": "AQID", "X-App-Attest-Time": "42"])
        #expect(AppAttestRequest.headers(keyId: nil, assertion: nil, time: 42, capable: true) == ["X-App-Attest-Capable": "1"])
        #expect(AppAttestRequest.headers(keyId: nil, assertion: nil, time: 42, capable: false).isEmpty)
    }
}

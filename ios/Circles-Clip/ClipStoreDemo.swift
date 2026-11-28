#if DEBUG
import Foundation

// Debug builds only: plays a store's Welcome → sign-in → connected screens
// in the simulator with canned server answers, so the screens can be
// refined before the server switch (CLIP_STORE_WELCOME) is on (2026-11-26).
//
//   CLIP_STORE_DEMO=<folder>        holds experience.json ({plain, live}, made
//                                   by backend/services/clipExperience.js) and
//                                   the store's photos (file:// URLs in it)
//   CLIP_STORE_DEMO_REWARDS=1       the store's rewards are live (points, Wallet)
//   CLIP_STORE_DEMO_NAME=<name>     the store's full name (default Caffeena Coffee House)
//   CLIP_STORE_DEMO_BALANCE=<n>     points already there (default 0): 100+ makes
//                                   the latte redeemable, to walk redeem → ticket → Given
//
// Launch with _XCAppClipURL=https://api.favcircles.com/s/STOREDEMO. Nothing
// reaches the network: sign-in, the save, the follow and the bell answer here.
enum ClipStoreDemo {
    static let code = "STOREDEMO"
    private static let env = ProcessInfo.processInfo.environment
    static let folder: URL? = env["CLIP_STORE_DEMO"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var isActive: Bool { folder != nil }
    static var rewardsLive: Bool { env["CLIP_STORE_DEMO_REWARDS"] == "1" }
    static var storeName: String { env["CLIP_STORE_DEMO_NAME"] ?? "Caffeena Coffee House" }
    static var startingBalance: Int { Int(env["CLIP_STORE_DEMO_BALANCE"] ?? "") ?? 0 }
    static let latte: [String: Any] = ["offerId": "demo-latte", "title": "Free latte", "pointsCost": 100]
    /// The demo store asks to share once, like a real one
    nonisolated(unsafe) static var shared = false
    nonisolated(unsafe) static var ticket: [String: Any]?

    static func voucher(status: String = "issued") -> [String: Any] {
        let f = ISO8601DateFormatter()
        return ["voucherId": "demo-ticket", "voucherCode": "7KQ2", "offerTitle": "Free latte", "pointsCost": 100,
                "venueId": "store-demo-venue", "venueName": storeName,
                "expiresAt": f.string(from: Date().addingTimeInterval(15 * 60)), "status": status,
                "givenAt": status == "given" ? f.string(from: Date()) : NSNull()]
    }

    static func install() {
        guard isActive else { return }
        URLProtocol.registerClass(ClipStoreDemoStub.self)
    }

    static var experience: Any {
        guard let folder,
              let data = try? Data(contentsOf: folder.appendingPathComponent("experience.json")),
              let both = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return NSNull() }
        return both[rewardsLive ? "live" : "plain"] ?? NSNull()
    }

    static var coverUrl: Any {
        ((experience as? [String: Any])?["welcome"] as? [String: Any])?["photoUrl"] ?? NSNull()
    }

    static var preview: [String: Any] {
        ["success": true, "data": [
            "venueName": storeName, "placeName": storeName, "placeAddress": "3101 Griffith St, Charlotte, NC",
            "category": "cafe", "kind": "window",
            "signupBonusPoints": rewardsLive ? 25 : 0, "scanPoints": rewardsLive ? 25 : 0, "scanPointsKind": "save",
            "loyaltyLive": rewardsLive, "earnRate": rewardsLive ? 25 : NSNull(),
            "offers": rewardsLive ? [latte] : [],
            "coverUrl": coverUrl,
            "location": ["lat": 35.200618, "lng": -80.872306],
            "experience": experience
        ]]
    }

    static func auth(email: String) -> [String: Any] {
        ["success": true, "token": "store-demo-token", "expiresIn": 2_592_000, "emailUnverified": true,
         "newAccount": false, "user": ["_id": "store-demo-user", "email": email]]
    }

    static var scan: [String: Any] {
        var data: [String: Any] = [
            "kind": "window",
            "venue": ["venueId": "store-demo-venue", "venueName": storeName, "placeName": storeName,
                      "placeAddress": "3101 Griffith St, Charlotte, NC", "category": "cafe",
                      "globalPlaceId": "store-demo-place", "location": ["lat": 35.200618, "lng": -80.872306]],
            "saved": true, "savedPlace": ["placeId": "store-demo-save", "circleId": "store-demo-circle"],
            "loyaltyLive": rewardsLive, "offers": rewardsLive ? [latte] : []
        ]
        if rewardsLive {
            data["awarded"] = ["type": "save", "points": 25]
            data["balance"] = 25 + startingBalance
            data["venueBalance"] = 25 + startingBalance
            data["earnRate"] = 25
            data["nextRewardLine"] = "75 more points for a Free latte \u{00b7} about 3 more visits"
        }
        return ["success": true, "data": data]
    }
}

/// Answers the clip's requests from the fixtures above; anything else is
/// refused, so the run is offline
final class ClipStoreDemoStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ClipStoreDemo.isActive && request.url?.scheme?.hasPrefix("http") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path
        var status = 200
        var body = Data()
        func json(_ object: [String: Any]) { body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

        if path.hasSuffix("/clip/venue/\(ClipStoreDemo.code)") {
            json(ClipStoreDemo.preview)
        } else if path.hasSuffix("/auth/email-instant") {
            let sent = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            json(ClipStoreDemo.auth(email: sent?["email"] as? String ?? "guest@example.com"))
        } else if path.hasSuffix("/rewards/scan") {
            json(ClipStoreDemo.scan)
        } else if path.hasSuffix("/rewards/redeem-offer") {
            if ClipStoreDemo.shared {
                ClipStoreDemo.ticket = ClipStoreDemo.voucher()
                json(["success": true, "data": ["voucher": ClipStoreDemo.ticket!, "venueBalance": 25 + ClipStoreDemo.startingBalance - 100]])
            } else {
                status = 400
                json(["success": false, "code": "share_required",
                      "error": "Rewards at \(ClipStoreDemo.storeName) are claimed by name."])
            }
        } else if path.hasSuffix("/share") && path.contains("/rewards/venues/") {
            ClipStoreDemo.shared = true
            json(["success": true, "data": ["shared": true]])
        } else if path.hasSuffix("/rewards/vouchers") {
            json(["success": true, "data": ["active": ClipStoreDemo.ticket.map { [$0] } ?? [], "recent": []]])
        } else if path.hasSuffix("/given") {
            ClipStoreDemo.ticket = nil
            json(["success": true, "data": ClipStoreDemo.voucher(status: "given")])
        } else if path.hasSuffix("/clip/device") || path.contains("/places/") {
            json(["success": true])
        } else {
            status = 404
            json(["error": "Not part of the store demo"])
        }

        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
}
#endif

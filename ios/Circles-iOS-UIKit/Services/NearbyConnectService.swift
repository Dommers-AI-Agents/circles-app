import Foundation
import MultipeerConnectivity

/// "Tap to Stay in Touch" proximity discovery. Session-less
/// MultipeerConnectivity: both phones advertise + browse the `fc-tap`
/// Bonjour service with a tiny discoveryInfo payload (uid + display name).
/// No MCSession is ever formed — the actual connection happens through the
/// backend's autoAccept invite path once a user taps a discovered card, so
/// this class is purely a "who's holding their phone near mine" radar.
///
/// True phone-to-phone NFC (NameDrop) is Apple-private; this is the
/// canonical third-party equivalent.
protocol NearbyConnectServiceDelegate: AnyObject {
    func nearbyService(_ service: NearbyConnectService, found peer: NearbyConnectService.NearbyPeer)
    func nearbyService(_ service: NearbyConnectService, lost peerUserId: String)
}

final class NearbyConnectService: NSObject {

    struct NearbyPeer: Equatable {
        let userId: String
        let displayName: String
    }

    static let serviceType = "fc-tap"   // must match NSBonjourServices (_fc-tap._tcp/_udp)

    weak var delegate: NearbyConnectServiceDelegate?

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var myPeerID: MCPeerID?
    /// MCPeerID displayName → advertised userId, so lost-peer callbacks can
    /// be translated back for the UI.
    private var peerUserIds: [MCPeerID: String] = [:]

    func start() {
        stop()
        guard let rawId = AuthService.shared.getUserId(),
              let uid = IDNormalizer.normalize(rawId),
              let user = AuthService.shared.currentUser else {
            Logger.warning("📡 NearbyConnect: no logged-in user — not starting")
            return
        }

        // PeerID display names must be unique-ish and ≤63 bytes; the uid alone
        // is both. Human name travels in discoveryInfo.
        let peerID = MCPeerID(displayName: String(uid.prefix(60)))
        myPeerID = peerID

        let info = [
            "uid": uid,
            // Bonjour TXT records are tight — clamp the name
            "name": String(user.displayName.prefix(40))
        ]

        let advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                                   discoveryInfo: info,
                                                   serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        Logger.debug("📡 NearbyConnect: advertising + browsing as \(uid)")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        peerUserIds.removeAll()
    }

    deinit { stop() }
}

extension NearbyConnectService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard let uid = info?["uid"], !uid.isEmpty else { return }
        // Never surface ourselves (two sessions on one account, or reflection)
        if IDNormalizer.isSameUser(uid, AuthService.shared.getUserId()) { return }
        let name = info?["name"] ?? "A FavCircles user"
        peerUserIds[peerID] = uid
        Logger.debug("📡 NearbyConnect: found \(name) (\(uid))")
        DispatchQueue.main.async {
            self.delegate?.nearbyService(self, found: NearbyPeer(userId: uid, displayName: name))
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        guard let uid = peerUserIds.removeValue(forKey: peerID) else { return }
        Logger.debug("📡 NearbyConnect: lost \(uid)")
        DispatchQueue.main.async {
            self.delegate?.nearbyService(self, lost: uid)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Logger.warning("📡 NearbyConnect: browse failed — \(error.localizedDescription)")
    }
}

extension NearbyConnectService: MCNearbyServiceAdvertiserDelegate {
    // Session-less design: politely decline any session invitation — peers
    // only need our discoveryInfo, which they already have.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(false, nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Logger.warning("📡 NearbyConnect: advertise failed — \(error.localizedDescription)")
    }
}

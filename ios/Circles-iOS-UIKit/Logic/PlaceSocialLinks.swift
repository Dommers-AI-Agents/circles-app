import Foundation

/// A store's Instagram, Facebook and X (Twitter) links (Wes, 2026-11-24:
/// "we are missing links on place view of stores"). The store's team sets
/// them in Manage Store → Store details; the place page shows a button for
/// each one that is set, and no row and no gap when none are.
///
/// The server keeps each as a full https address on that network's own site
/// (services/venueSocialLinks.js); this side only reads them. Pure, tested.
struct PlaceSocialLinks: Codable, Equatable {
    var instagram: String?
    var facebook: String?
    var twitter: String?

    enum Network: String, CaseIterable {
        case instagram, facebook, twitter

        /// The button on the place page
        var title: String {
            switch self {
            case .instagram: return "Instagram"
            case .facebook: return "Facebook"
            case .twitter: return "X"
            }
        }

        /// The row in Store details
        var settingsTitle: String { self == .twitter ? "X (Twitter)" : title }

        var addPrompt: String {
            switch self {
            case .instagram: return "Add your Instagram"
            case .facebook: return "Add your Facebook page"
            case .twitter: return "Add your X account"
            }
        }

        /// The sites a link may point at; anything else is never opened
        var hosts: [String] {
            switch self {
            case .instagram: return ["instagram.com", "instagr.am"]
            case .facebook: return ["facebook.com", "fb.com", "fb.me"]
            case .twitter: return ["x.com", "twitter.com"]
            }
        }
    }

    func link(_ network: Network) -> String? {
        switch network {
        case .instagram: return instagram
        case .facebook: return facebook
        case .twitter: return twitter
        }
    }

    /// The links worth a button, in a fixed order: set, https, and on the
    /// network they claim to be.
    var buttons: [(network: Network, url: URL)] {
        Network.allCases.compactMap { network in
            guard let url = Self.safeURL(link(network), for: network) else { return nil }
            return (network, url)
        }
    }

    var isEmpty: Bool { buttons.isEmpty }

    static func safeURL(_ link: String?, for network: Network) -> URL? {
        guard let text = link?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), url.scheme?.lowercased() == "https",
              var host = url.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        return network.hosts.contains(host) ? url : nil
    }

    /// How a saved link reads in Store details: "@giddygoat" for a plain
    /// profile address, the address without "https://" for anything longer.
    static func display(_ link: String?, for network: Network) -> String? {
        guard let url = safeURL(link, for: network) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count == 1, url.query == nil, parts[0] != "profile.php" { return "@" + parts[0] }
        return (url.host ?? "") + url.path + (url.query.map { "?" + $0 } ?? "")
    }
}

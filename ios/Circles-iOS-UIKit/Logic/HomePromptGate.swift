import Foundation

/// One home "daily card" as the server picks it (`GET /api/home/prompt`).
/// The server owns cadence and "already knows" memory; the app only renders,
/// routes the tap, and acks. Unknown targets decode (as `.unknown`) so a
/// catalog card for a target this build can't route still shows and can be
/// skipped, instead of failing the whole response.
struct HomePromptCard: Decodable, Equatable {
    let key: String
    let type: String
    let title: String
    let body: String
    let actionLabel: String
    let skipLabel: String
    let target: String
    let data: [String: HomePromptValue]
    let imageUrl: String?
    let actorPhoto: String?

    var destination: HomePromptTarget { HomePromptTarget(target: target, data: data) }

    enum CodingKeys: String, CodingKey {
        case key, type, title, body, actionLabel, skipLabel, target, data, imageUrl, actorPhoto
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        actionLabel = try c.decodeIfPresent(String.self, forKey: .actionLabel) ?? "Show me"
        skipLabel = try c.decodeIfPresent(String.self, forKey: .skipLabel) ?? "Skip"
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        data = try c.decodeIfPresent([String: HomePromptValue].self, forKey: .data) ?? [:]
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        actorPhoto = try c.decodeIfPresent(String.self, forKey: .actorPhoto)
    }

    init(key: String, type: String, title: String, body: String, actionLabel: String = "Show me",
         skipLabel: String = "Skip", target: String, data: [String: HomePromptValue] = [:],
         imageUrl: String? = nil, actorPhoto: String? = nil) {
        self.key = key; self.type = type; self.title = title; self.body = body
        self.actionLabel = actionLabel; self.skipLabel = skipLabel; self.target = target
        self.data = data; self.imageUrl = imageUrl; self.actorPhoto = actorPhoto
    }
}

/// `data` values are strings, numbers, or null — nothing nested.
enum HomePromptValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else { self = .null }
    }

    var stringValue: String? {
        if case .string(let s) = self, !s.isEmpty { return s }
        return nil
    }
}

/// Where a card's primary action goes. Mirrors the `data.type` targets the
/// push-tap router already understands, plus three home-only ones.
enum HomePromptTarget: Equatable {
    case place(id: String)
    case video(id: String)
    case addPlace
    case favCoinsIntro
    case widgetsTab
    case momentsTab
    case allPlacesMap
    case createWallet
    case network
    case unknown(String)

    init(target: String, data: [String: HomePromptValue]) {
        switch target {
        case "place":
            if let id = data["placeId"]?.stringValue { self = .place(id: id) } else { self = .unknown(target) }
        case "video", "moment":
            if let id = data["videoId"]?.stringValue ?? data["momentId"]?.stringValue {
                self = .video(id: id)
            } else { self = .unknown(target) }
        case "add_place", "add-place": self = .addPlace
        case "favcoins_intro": self = .favCoinsIntro
        case "widgets_tab": self = .widgetsTab
        case "moments_tab": self = .momentsTab
        case "all_places_map": self = .allPlacesMap
        case "create_wallet": self = .createWallet
        case "network": self = .network
        default: self = .unknown(target)
        }
    }
}

/// The client-side half of "within reason": decides whether the home screen
/// should ask the server for a card right now. Pure so the timing rules are
/// unit-tested without UIKit. The server enforces the real once-a-day window;
/// this only keeps the app from polling and from ever stacking a card on top
/// of onboarding, a tour, or a modal.
struct HomePromptGate {
    /// Never ask the server more than once an hour, regardless of foregrounds.
    static let minimumFetchInterval: TimeInterval = 60 * 60

    struct Context: Equatable {
        var now: Date
        var lastFetchAt: Date?
        var isSignedIn: Bool
        var isCardVisible: Bool
        var isPresentingModal: Bool
        var isTourRunning: Bool
        var isFirstSessionFlowActive: Bool
        /// The once-per-session onboarding decision has been made, so a card
        /// can't race the suggested-people overlay or the home tour.
        var onboardingCheckDone: Bool
    }

    static func shouldFetch(_ c: Context) -> Bool {
        guard c.isSignedIn, c.onboardingCheckDone else { return false }
        guard !c.isCardVisible, !c.isPresentingModal, !c.isTourRunning, !c.isFirstSessionFlowActive else { return false }
        if let last = c.lastFetchAt, c.now.timeIntervalSince(last) < minimumFetchInterval { return false }
        return true
    }

    /// A fetched card is only shown if the screen is still clear when the
    /// response lands (a modal may have opened in the meantime).
    static func canPresent(_ c: Context) -> Bool {
        !c.isPresentingModal && !c.isTourRunning && !c.isFirstSessionFlowActive
    }
}

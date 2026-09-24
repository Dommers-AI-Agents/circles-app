import Foundation

/// The one ladder every privacy picker and badge in the app is built from.
///
/// It mirrors `backend/services/visibility.js` exactly. Before this existed the
/// same tier went by three different names — Edit Circle called it "My Network",
/// Edit Place called it "Friends", and moments called it "Connections" — because
/// each screen hardcoded its own strings next to its own parallel array of
/// values. Anything that shows a privacy option now derives it from here.
///
/// Two things deliberately sit *outside* the ladder, because modelling them as
/// tiers is what produced the `allCases`-driven pickers in the first place:
/// a place's "same as circle" is an inherit pointer, not a level, and moments'
/// "followers" audience has no circle equivalent. Both live in `PrivacyOption`.
enum PrivacyTier: String, CaseIterable, Comparable {
    /// Anyone, including people who only follow you.
    case `public` = "public"
    /// Accepted connections. Stored as `myNetwork` for circles and places, and
    /// as `network` for moments — a historic split the backend normalises on
    /// read rather than migrating thousands of documents.
    case connections = "myNetwork"
    /// The people on your Inner Circle list.
    case innerCircle = "innerCircle"
    /// You alone.
    case `private` = "private"

    /// Open → closed. Used for ordering pickers and for `Comparable`.
    private var openness: Int {
        switch self {
        case .public: return 0
        case .connections: return 1
        case .innerCircle: return 2
        case .private: return 3
        }
    }

    static func < (lhs: PrivacyTier, rhs: PrivacyTier) -> Bool {
        lhs.openness < rhs.openness
    }

    var title: String {
        switch self {
        case .public: return "Public"
        case .connections: return "Connections"
        case .innerCircle: return "Inner Circle"
        case .private: return "Private"
        }
    }

    /// The line under the title. "including your followers" is doing real work:
    /// it is the only place the app explains, at the moment of choosing, that a
    /// follower is a wider audience than a connection.
    var subtitle: String {
        switch self {
        case .public: return "Anyone, including your followers"
        case .connections: return "People who accepted your request"
        case .innerCircle: return "Only the people on your list"
        case .private: return "Only you"
        }
    }

    var systemIconName: String {
        switch self {
        case .public: return "globe"
        case .connections: return "person.2.fill"
        case .innerCircle: return "star.fill"
        case .private: return "lock.fill"
        }
    }
}

/// What a given kind of thing can actually be set to. A circle has the four
/// tiers; a place adds "same as circle"; a moment adds the followers audience.
enum PrivacyOption: Equatable {
    /// Places only: whatever the circle says. Adds no restriction of its own.
    case inheritCircle
    /// Moments only: people who follow you. Sits between Public and Connections.
    case followers
    case tier(PrivacyTier)

    var title: String {
        switch self {
        case .inheritCircle: return "Same as circle"
        case .followers: return "Followers"
        case .tier(let tier): return tier.title
        }
    }

    var subtitle: String {
        switch self {
        case .inheritCircle: return "Use this circle's privacy setting"
        case .followers: return "Anyone who follows you"
        case .tier(let tier): return tier.subtitle
        }
    }

    var systemIconName: String {
        switch self {
        case .inheritCircle: return "circle.dashed"
        case .followers: return "person.badge.plus"
        case .tier(let tier): return tier.systemIconName
        }
    }
}

enum PrivacyEntity {
    case circle
    case place
    case moment
}

extension PrivacyTier {
    /// The options a picker should offer, open → closed.
    ///
    /// Circles have no followers tier on purpose: following is one-way, so it
    /// earns the public tier and nothing more.
    static func options(for entity: PrivacyEntity) -> [PrivacyOption] {
        let ladder = PrivacyTier.allCases.sorted().map(PrivacyOption.tier)
        switch entity {
        case .circle:
            return ladder
        case .place:
            return [.inheritCircle] + ladder
        case .moment:
            var options = ladder
            // Just after Public, matching the backend's ordering.
            options.insert(.followers, at: 1)
            return options
        }
    }
}

/// One group of a picker's menu. `title` is nil for the main group and a
/// heading ("Advanced") for a demoted one.
struct PrivacyMenuSection: Equatable {
    let title: String?
    let options: [PrivacyOption]
}

extension PrivacyTier {
    static let advancedSectionTitle = "Advanced"

    /// `options(for:)` grouped for display.
    ///
    /// Circles and places put Inner Circle under an "Advanced" heading: since
    /// the account-level activity grid arrived, it is the rare per-item
    /// override rather than a tier most people should weigh every time they
    /// save. The option set itself is unchanged — nothing is hidden, and an
    /// item already set to Inner Circle still shows as such. Moments keep one
    /// flat list; their picker was left alone on purpose.
    static func menuSections(for entity: PrivacyEntity) -> [PrivacyMenuSection] {
        let all = options(for: entity)
        switch entity {
        case .moment:
            return [PrivacyMenuSection(title: nil, options: all)]
        case .circle, .place:
            let demoted: PrivacyOption = .tier(.innerCircle)
            return [
                PrivacyMenuSection(title: nil, options: all.filter { $0 != demoted }),
                PrivacyMenuSection(title: advancedSectionTitle, options: all.filter { $0 == demoted })
            ]
        }
    }
}

import Foundation

/// The account-level "who can see my activity" grid: audience × activity type.
///
/// Per-item privacy (a circle's tier, a place's tier, a moment's audience)
/// stays the fine-grained control. This grid sits above it: a row of activity
/// is shown to someone only when the item itself already allows them AND at
/// least one checked column here is one they qualify for. It only ever
/// narrows; it never widens what an item allows.
///
/// Mirrors `backend/services/activityPrivacy.js`. Keys are the wire format.

// MARK: - Rows

/// One row of the grid. Raw values are the backend's category keys.
enum ActivityPrivacyCategory: String, CaseIterable, Codable {
    case checkIns
    case photos
    case moments
    case savedPlaces
    case likesComments
    case circles

    /// The row until its owner changes it (Wes, 2026-09-25): what you did
    /// somewhere — check-ins, photos, moments — reaches connections; what
    /// you curate — saved places, likes & comments, circles — everyone.
    var defaultAudience: AudienceSet {
        switch self {
        case .checkIns, .photos, .moments: return .connections
        case .savedPlaces, .likesComments, .circles: return .allAllowed
        }
    }

    var title: String {
        switch self {
        case .checkIns: return "Check-ins"
        case .photos: return "Photos at a place"
        case .moments: return "Moments"
        case .savedPlaces: return "Saved places"
        case .likesComments: return "Likes & comments"
        case .circles: return "New circles"
        }
    }

    var systemIconName: String {
        switch self {
        case .checkIns: return "mappin.and.ellipse"
        case .photos: return "photo.fill"
        case .moments: return "play.rectangle.fill"
        case .savedPlaces: return "bookmark.fill"
        case .likesComments: return "heart.fill"
        case .circles: return "circle.grid.3x3.fill"
        }
    }
}

// MARK: - Columns

/// One column of the grid. Raw values are the backend's audience keys; copy and
/// icons come from the same ladder every other privacy control uses.
enum ActivityAudience: String, CaseIterable, Codable {
    /// Anyone, including followers.
    case `public`
    /// Accepted connections.
    case myNetwork
    /// People on any of the account's Inner Circle lists.
    case innerCircle

    var tier: PrivacyTier {
        switch self {
        case .public: return .public
        case .myNetwork: return .connections
        case .innerCircle: return .innerCircle
        }
    }

    var title: String { tier.title }
    var subtitle: String { tier.subtitle }
    var systemIconName: String { tier.systemIconName }
}

// MARK: - One row's boxes

/// The three boxes of one row. Decoding is lenient on purpose: a missing or
/// malformed box reads as checked, because "absent means allowed" is the
/// server's rule too and a bad byte must never hide someone's activity from
/// people it was meant for — nor show a box unchecked that the server never
/// unchecked.
struct AudienceSet: Codable, Equatable {
    var `public`: Bool
    var myNetwork: Bool
    var innerCircle: Bool

    init(public: Bool = true, myNetwork: Bool = true, innerCircle: Bool = true) {
        self.public = `public`
        self.myNetwork = myNetwork
        self.innerCircle = innerCircle
    }

    static let allAllowed = AudienceSet()
    /// Connections and the Inner Circle, not the public.
    static let connections = AudienceSet(public: false, myNetwork: true, innerCircle: true)

    private enum CodingKeys: String, CodingKey {
        case `public`, myNetwork, innerCircle
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(
            public: (try? container.decodeIfPresent(Bool.self, forKey: .public)) ?? true,
            myNetwork: (try? container.decodeIfPresent(Bool.self, forKey: .myNetwork)) ?? true,
            innerCircle: (try? container.decodeIfPresent(Bool.self, forKey: .innerCircle)) ?? true
        )
    }

    /// The box as stored.
    subscript(audience: ActivityAudience) -> Bool {
        get {
            switch audience {
            case .public: return `public`
            case .myNetwork: return myNetwork
            case .innerCircle: return innerCircle
            }
        }
        set {
            switch audience {
            case .public: `public` = newValue
            case .myNetwork: myNetwork = newValue
            case .innerCircle: innerCircle = newValue
            }
        }
    }

    /// The box as it takes effect.
    ///
    /// Everyone on an Inner Circle list is a connection, and the server shows a
    /// row to anyone who qualifies for *any* checked column. So while
    /// Connections is checked, Inner Circle members see the row whatever the
    /// Inner Circle box says. Reading it as checked keeps the grid honest
    /// about that instead of showing an unchecked box that changes nothing.
    func allows(_ audience: ActivityAudience) -> Bool {
        switch audience {
        case .innerCircle: return innerCircle || myNetwork
        default: return self[audience]
        }
    }

    /// True when the Inner Circle box is checked only because Connections is.
    var innerCircleIsImplied: Bool { myNetwork }

    /// The stored form with the implied box made explicit.
    var normalized: AudienceSet {
        AudienceSet(public: `public`, myNetwork: myNetwork, innerCircle: allows(.innerCircle))
    }

    var allowsAnyone: Bool { ActivityAudience.allCases.contains { allows($0) } }

    var requestBody: [String: Any] {
        let n = normalized
        return ["public": n.public, "myNetwork": n.myNetwork, "innerCircle": n.innerCircle]
    }
}

// MARK: - The grid

struct ActivityPrivacy: Codable, Equatable {
    var checkIns: AudienceSet
    var photos: AudienceSet
    var moments: AudienceSet
    var savedPlaces: AudienceSet
    var likesComments: AudienceSet
    var circles: AudienceSet

    init(checkIns: AudienceSet = .allAllowed,
         photos: AudienceSet = .allAllowed,
         moments: AudienceSet = .allAllowed,
         savedPlaces: AudienceSet = .allAllowed,
         likesComments: AudienceSet = .allAllowed,
         circles: AudienceSet = .allAllowed) {
        self.checkIns = checkIns
        self.photos = photos
        self.moments = moments
        self.savedPlaces = savedPlaces
        self.likesComments = likesComments
        self.circles = circles
    }

    /// Every box checked.
    static let allAllowed = ActivityPrivacy()
    /// What an account has until it changes something: each category's
    /// `defaultAudience` — the same rule the server applies to an absent grid.
    static let standard = ActivityPrivacy(
        checkIns: .connections, photos: .connections, moments: .connections,
        savedPlaces: .allAllowed, likesComments: .allAllowed, circles: .allAllowed)

    private enum CodingKeys: String, CodingKey {
        case checkIns, photos, moments, savedPlaces, likesComments, circles
    }

    /// Never throws: a grid the app can't read is the same as no grid, which
    /// the server treats as the standard defaults.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .standard
            return
        }
        func row(_ key: CodingKeys, _ category: ActivityPrivacyCategory) -> AudienceSet {
            (try? container.decodeIfPresent(AudienceSet.self, forKey: key)) ?? category.defaultAudience
        }
        self.init(checkIns: row(.checkIns, .checkIns), photos: row(.photos, .photos), moments: row(.moments, .moments),
                  savedPlaces: row(.savedPlaces, .savedPlaces), likesComments: row(.likesComments, .likesComments),
                  circles: row(.circles, .circles))
    }

    subscript(category: ActivityPrivacyCategory) -> AudienceSet {
        get {
            switch category {
            case .checkIns: return checkIns
            case .photos: return photos
            case .moments: return moments
            case .savedPlaces: return savedPlaces
            case .likesComments: return likesComments
            case .circles: return circles
            }
        }
        set {
            switch category {
            case .checkIns: checkIns = newValue
            case .photos: photos = newValue
            case .moments: moments = newValue
            case .savedPlaces: savedPlaces = newValue
            case .likesComments: likesComments = newValue
            case .circles: circles = newValue
            }
        }
    }

    /// Whether the box takes effect (see `AudienceSet.allows`).
    func allows(_ category: ActivityPrivacyCategory, _ audience: ActivityAudience) -> Bool {
        self[category].allows(audience)
    }

    /// True for an Inner Circle box that is checked only because Connections is.
    /// The cell shows it checked and dimmed, and refuses the tap.
    func isImplied(_ category: ActivityPrivacyCategory, _ audience: ActivityAudience) -> Bool {
        audience == .innerCircle && self[category].innerCircleIsImplied
    }

    /// Flip one box.
    ///
    /// - Checking Connections also checks Inner Circle (it is implied anyway).
    /// - Unchecking Inner Circle while Connections is checked is refused: the
    ///   row would still reach every list member, so the box would lie.
    func toggled(category: ActivityPrivacyCategory, audience: ActivityAudience) -> ActivityPrivacy {
        var copy = self
        // Start from what the boxes show, not what was stored: a grid the
        // server sent as {myNetwork: true, innerCircle: false} shows Inner
        // Circle checked, and unchecking Connections must leave it that way.
        var row = self[category].normalized
        switch audience {
        case .innerCircle where row.myNetwork:
            return self
        case .myNetwork where !row.myNetwork:
            row.myNetwork = true
            row.innerCircle = true
        default:
            row[audience].toggle()
        }
        copy[category] = row
        return copy
    }

    /// Every implied box made explicit — what the server is sent, and what
    /// "unchanged" is measured against.
    var normalized: ActivityPrivacy {
        var copy = self
        for category in ActivityPrivacyCategory.allCases {
            copy[category] = self[category].normalized
        }
        return copy
    }

    var isDefault: Bool { normalized == .standard }

    /// The line under a row's title.
    ///
    /// - Parameter innerCircleIsEmpty: an Inner Circle with nobody on it reaches
    ///   nobody, so a row checked only there is, in practice, "Only you".
    func summary(for category: ActivityPrivacyCategory, innerCircleIsEmpty: Bool) -> String {
        let row = self[category]
        if row.allows(.public) { return "Everyone" }
        if row.allows(.myNetwork) { return "Connections" }
        if row.allows(.innerCircle) && !innerCircleIsEmpty { return "Inner Circle" }
        return "Only you"
    }

    /// The grid as `PUT users/me/activity-privacy` expects it: six category
    /// keys, each with all three audience booleans.
    func requestBody() -> [String: Any] {
        var body: [String: Any] = [:]
        for category in ActivityPrivacyCategory.allCases {
            body[category.rawValue] = self[category].requestBody
        }
        return body
    }
}

// MARK: - Copy

extension ActivityPrivacy {
    enum Copy {
        static let screenTitle = "Who can see my activity"
        static let headerTitle = "Activity"
        static let footer = "A place's own privacy still narrows this; it never widens it. Unchecking all three means only you."
        static let emptyInnerCircleTitle = "Your Inner Circle is empty"
        static let emptyInnerCircleDetail = "An Inner Circle box reaches no one until you add people. Tap to build your lists."
        static let impliedInnerCircleHint = "Included with Connections"
        static let saved = "Privacy saved"
        static let notAvailable = "Activity privacy isn't available yet. Please try again later."
        static let loadFailed = "Couldn't load your privacy settings."
    }
}

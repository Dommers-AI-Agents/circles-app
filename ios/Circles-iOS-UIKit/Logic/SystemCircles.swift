import Foundation

/// The circles the app makes and finds for you. The server stamps each with
/// `systemKind` (backend/services/systemCircles.js); the raw values match it.
enum SystemCircleKind: String, CaseIterable {
    case followedPlaces, checkIns, favoriteLocal, wantToTry, dogSpots, photoPlaces

    /// The name the app gives it when it makes one, and the fallback for
    /// circles written before the flag existed.
    var defaultName: String {
        switch self {
        case .followedPlaces: return "Places I Follow"
        case .checkIns: return "Check-in Places"
        case .favoriteLocal: return "Favorite Local Spots"
        case .wantToTry: return "Want to Try"
        case .dogSpots: return "Dog spots"
        case .photoPlaces: return "Places from my photos"
        }
    }
}

/// What `SystemCircles` reads off a circle (Circle conforms; tests use a stub).
protocol SystemCircleFlagged {
    var name: String { get }
    var systemKind: String? { get }
    var isDefaultCircle: Bool? { get }
}

extension Circle: SystemCircleFlagged {}

/// Finds system circles by the server's flag, never by name, so renaming one
/// never breaks the feature that uses it (Wes, 2026-10-31). The name is only
/// a fallback for an unflagged legacy circle. Pure.
enum SystemCircles {
    /// Onboarding's three starter circles, for legacy circles with no flags.
    static let starterNames: Set<String> = [
        SystemCircleKind.wantToTry.defaultName, SystemCircleKind.favoriteLocal.defaultName, "Vacation"
    ]

    /// Flagged as `kind`, or (legacy, no flag) named its default name.
    static func isKind(_ kind: SystemCircleKind, _ circle: SystemCircleFlagged) -> Bool {
        if let flag = circle.systemKind { return flag == kind.rawValue }
        return circle.name == kind.defaultName
    }

    /// The first circle of `kind`: a flagged one wins over a legacy name match.
    static func first<C: SystemCircleFlagged>(_ kind: SystemCircleKind, in circles: [C]) -> C? {
        circles.first { $0.systemKind == kind.rawValue }
            ?? circles.first { $0.systemKind == nil && $0.name == kind.defaultName }
    }

    /// One of the starter circles onboarding made (renamed or not).
    static func isStarter(_ circle: SystemCircleFlagged) -> Bool {
        if circle.isDefaultCircle == true { return true }
        if circle.systemKind == SystemCircleKind.favoriteLocal.rawValue
            || circle.systemKind == SystemCircleKind.wantToTry.rawValue { return true }
        return circle.systemKind == nil && starterNames.contains(circle.name)
    }
}

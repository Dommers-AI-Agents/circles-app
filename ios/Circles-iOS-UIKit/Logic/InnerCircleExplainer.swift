import Foundation

/// What an inner circle is FOR, said the same way everywhere (Wes,
/// 2026-11-25: the ⓘ "doesn't tell a user what the inner circles are for.
/// They are for defining who the user shares things with").
///
/// An inner circle is a sharing list: you choose who is on it, then choose it
/// when you share. It is about who sees YOUR things, never about who
/// influences you. Pure copy and the example a new user sees, so the wording
/// has one home and a test.
enum InnerCircleExplainer {

    static let title = "Inner Circles"

    /// The ⓘ beside Connections | Following | Inner Circles
    static let message = """
    An inner circle is a list of people you choose to share with.

    Name it (Family, Gym crew, Work) and put some of your connections on it. Then when you save a place, make a circle, post a moment or check in, choose that inner circle and only the people on it see it.

    You can keep several, and change who is on each one any time.
    """

    /// The page's title: Wes's line (2026-11-23), kept; what follows it says what the lists do
    static let pageTitle = "Your network is personal."

    /// Under the page title once you have lists
    static let headerHint = "Each one is a list of people you share with. Choose it when you save a place, post a moment or check in, and only they see it."

    /// How to work the rings
    static let ringHint = "Tap + to add someone. Tap a face to see them or take them off. Tap the middle for everyone."

    // MARK: - A new user's page: an example, never a blank

    static let firstRunBody = "An inner circle is a list of people you name. Share a place, a circle, a moment or a check-in with just them."

    static let exampleBadge = "EXAMPLE"
    static let exampleListName = "Family"
    /// The made-up people on the example ring (never real accounts)
    static let exampleMembers = ["Mom", "Dad", "Sam", "Ava", "Leo"]
    static let exampleCaption = "Save a place and choose Family, and only Mom, Dad, Sam, Ava and Leo see it."
    static let exampleAccessibilityLabel = "Example inner circle: Family, with Mom, Dad, Sam, Ava and Leo on it."

    /// Ids for the example faces; the prefix keeps them apart from real users
    static let exampleIdPrefix = "example-inner-circle-"
    static var exampleMemberIds: [String] { exampleMembers.map { exampleIdPrefix + $0.lowercased() } }
}

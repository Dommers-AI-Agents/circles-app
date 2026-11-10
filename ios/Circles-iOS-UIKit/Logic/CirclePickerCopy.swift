import Foundation

/// What the circle picker says before asking (Wes, 2026-11-09: "what is the
/// purpose of selecting a circle? Why is that the first action?"). Pure.
enum CirclePickerCopy {

    /// The one line above the list
    static func headline(forMove: Bool) -> String {
        forMove ? "Where should it live now?" : "Where should this place live?"
    }

    /// The why, in two sentences
    static func explanation(forMove: Bool, circleCount: Int) -> String {
        if forMove {
            return "A place lives in one circle at a time. Pick the circle it belongs in now; everything else about it stays the same."
        }
        if circleCount == 0 {
            return "Circles are the lists your places live in — a city, a trip, date nights, coffee spots. Start your first one and this place goes in it."
        }
        return "Circles are the lists your places live in — a city, a trip, date nights, coffee spots. Pick the one this place belongs in, or start a new one. You can move it later."
    }

    /// The ⓘ: a little more
    static let info = """
    Every place you save lives in a circle, so choosing one comes first.

    Circles keep your map readable — "Charlotte NC", "Date nights", "Coffee" — and they're what you share: a circle can be private, for your connections, or public, and each place keeps its circle's privacy unless you set its own.

    Nothing is final. Open a place later and move it to another circle any time.
    """

    static let infoTitle = "Why pick a circle?"
}

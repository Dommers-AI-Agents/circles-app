import Foundation

/// Add Place's "Fill this in from a photo": which place the photo shows.
/// A photo's location is rough indoors, so with more than one likely place
/// nearby it asks instead of guessing (Wes, 2026-11-07: a photo at Golden Cow
/// Creamery filled in the print shop next door). Pure.
enum PhotoFillChoices {
    /// Choices offered, best first
    static let maxChoices = 5

    enum Decision: Equatable {
        /// Nothing listed there: a pin where the photo was taken
        case pin
        /// One likely place: fill it in
        case fill(index: Int)
        /// Several: ask, best guess first
        case ask(count: Int)
    }

    static func decide(candidateCount: Int) -> Decision {
        switch candidateCount {
        case 0: return .pin
        case 1: return .fill(index: 0)
        default: return .ask(count: min(candidateCount, maxChoices))
        }
    }

    /// "Golden Cow Creamery · Ice Cream"; the kind is left off when it
    /// says nothing the name doesn't.
    static func rowTitle(name: String, kind: String) -> String {
        let trimmedKind = kind.trimmingCharacters(in: .whitespaces)
        guard !trimmedKind.isEmpty, trimmedKind.lowercased() != "other",
              !name.lowercased().contains(trimmedKind.lowercased()) else { return name }
        return "\(name) · \(trimmedKind)"
    }

    static let title = "Which place is this?"
    static let message = "Your photo was taken near these. Pick the one it shows."
    static let somewhereElse = "Somewhere else (pin the spot)"
}

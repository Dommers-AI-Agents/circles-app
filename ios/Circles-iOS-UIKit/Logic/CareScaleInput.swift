import Foundation

/// The number a parent typed on the Lock Screen for a 0–10 care question.
/// Forgiving about the shape (" 8 ", "7/10", "10.") and strict about the
/// range; anything else is nil and the app opens on the slider instead.
enum CareScaleInput {
    static func value(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = trimmed.prefix { $0.isNumber }
        guard !lead.isEmpty, let n = Int(lead), (0...10).contains(n) else { return nil }
        return n
    }
}

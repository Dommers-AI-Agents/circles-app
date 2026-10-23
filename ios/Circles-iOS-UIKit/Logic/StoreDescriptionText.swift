import Foundation

/// A store's description is PROSE: phone and website are their own fields,
/// so legacy embedded "Phone:" / "Website:" lines never appear in (or
/// survive) the description editor. Pure.
enum StoreDescriptionText {
    static func strippingContactLines(_ text: String?) -> String {
        guard let text = text else { return "" }
        return text
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("Phone:") && !trimmed.hasPrefix("Website:")
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

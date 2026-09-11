import Foundation

/// Finds the tappable URLs in a place description: legacy descriptions
/// carry "Website: https://…" lines, and the URL part becomes a link.
enum PlaceDescriptionLinks {
    struct Link: Equatable {
        let range: NSRange
        let url: URL
    }

    static func websiteLinks(in text: String) -> [Link] {
        // Find "Website: " patterns and make URLs clickable
        let websitePattern = "Website: (https?://[^\\s\\n]+)"
        let regex = try? NSRegularExpression(pattern: websitePattern, options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.count)) ?? []

        return matches.compactMap { match in
            // Get the URL part (capture group 1)
            guard match.numberOfRanges > 1 else { return nil }
            let urlRange = match.range(at: 1)
            let urlString = (text as NSString).substring(with: urlRange)
            guard let url = URL(string: urlString) else { return nil }
            return Link(range: urlRange, url: url)
        }
    }
}

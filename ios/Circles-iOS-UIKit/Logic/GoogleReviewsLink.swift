import Foundation

/// Where a tap on a place's star rating goes: a Google search for the venue
/// with "reviews" appended, which lands on the knowledge panel with the
/// review list up top. (Not a Maps place link — the rating shown is the
/// Google one, and the search page is what surfaces reviews first.)
enum GoogleReviewsLink {
    /// The name and address are one query VALUE, so every delimiter in them
    /// is encoded: "Pasta & Provisions" must reach Google whole, not as
    /// `q=Pasta ` plus a stray `Provisions` parameter.
    static func url(name: String, address: String?) -> URL? {
        var parts = [name.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            parts.append(address)
        }
        parts.append("reviews")
        let query = parts.filter { !$0.isEmpty }.joined(separator: " ")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.percentEncodedQuery = "q=\(query.urlQueryValueEncoded)"
        return components.url
    }
}

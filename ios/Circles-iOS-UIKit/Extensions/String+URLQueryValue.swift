import Foundation

extension CharacterSet {
    /// Characters safe inside ONE query value. `.urlQueryAllowed` is the set
    /// for a whole query string, so it keeps the delimiters (`&`, `=`, `+`,
    /// `?`, `#`) raw — encode "Pasta & Provisions" with it and the server sees
    /// `q=Pasta ` plus a stray `Provisions` parameter. Use this set for text
    /// that goes into a single parameter of a URL we assemble by hand.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#;/")
        return set
    }()
}

extension String {
    /// The string percent-encoded as one query value — see
    /// `CharacterSet.urlQueryValueAllowed`. Prefer `APIService`'s
    /// `queryParams:` for backend calls; this is for URLs handed to the OS
    /// (search links, `sms:` bodies) where no `URLComponents` fits.
    var urlQueryValueEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
    }
}

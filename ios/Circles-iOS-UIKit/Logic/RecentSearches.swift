import Foundation

/// The last few things a person searched for on the home bar, shown under
/// the empty, focused bar so a repeat search is one tap. Per account, on
/// this phone only (UserDefaults) — never sent anywhere.
struct RecentSearchList: Equatable {
    static let capacity = 8
    private(set) var queries: [String]

    init(_ queries: [String] = []) {
        self.queries = Array(queries.prefix(Self.capacity))
    }

    /// `query` moved (or added) to the front; a case/accent-only variant
    /// replaces the old one; too-short queries are not worth keeping.
    func adding(_ query: String) -> RecentSearchList {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= SearchDebouncer.minimumServerQueryLength else { return self }
        let key = PlaceSearchText.fold(trimmed)
        let rest = queries.filter { PlaceSearchText.fold($0) != key }
        return RecentSearchList([trimmed] + rest)
    }

    func removing(_ query: String) -> RecentSearchList {
        let key = PlaceSearchText.fold(query)
        return RecentSearchList(queries.filter { PlaceSearchText.fold($0) != key })
    }
}

/// UserDefaults persistence for `RecentSearchList`, keyed by user id.
final class RecentSearchStore {
    private let defaults: UserDefaults
    private let userId: () -> String?

    init(defaults: UserDefaults = .standard, userId: @escaping () -> String? = { AuthService.shared.getUserId() }) {
        self.defaults = defaults
        self.userId = userId
    }

    private var key: String? { userId().map { "homeRecentSearches.\($0)" } }

    var list: RecentSearchList {
        guard let key, let stored = defaults.stringArray(forKey: key) else { return RecentSearchList() }
        return RecentSearchList(stored)
    }

    func record(_ query: String) {
        guard let key else { return }
        defaults.set(list.adding(query).queries, forKey: key)
    }

    func remove(_ query: String) {
        guard let key else { return }
        defaults.set(list.removing(query).queries, forKey: key)
    }
}

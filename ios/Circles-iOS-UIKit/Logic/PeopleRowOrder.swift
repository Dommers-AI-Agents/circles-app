import Foundation

/// The home people row's last shown order (2026-10-30, Wes: "save the last
/// sort order rather than some stale previously saved sort order"). On
/// launch the row paints from the launch cache before the server's ranking
/// arrives; that first paint follows the order the row last showed, so the
/// avatars don't reshuffle a few seconds later. Pure.
enum PeopleRowOrder {
    /// `items` in the remembered order; anyone not remembered keeps their
    /// relative order after the remembered ones.
    static func apply<T>(_ savedIds: [String], to items: [T], id: (T) -> String?) -> [T] {
        guard !savedIds.isEmpty else { return items }
        let rank = Dictionary(savedIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { a, b in
            let ra = id(a.element).flatMap { rank[$0] } ?? Int.max
            let rb = id(b.element).flatMap { rank[$0] } ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Storage (per signed-in account)

    private static func key(_ userId: String) -> String { "homePeopleRowOrder.\(userId)" }

    static func saved(for userId: String?, defaults: UserDefaults = .standard) -> [String] {
        guard let userId else { return [] }
        return defaults.stringArray(forKey: key(userId)) ?? []
    }

    static func save(_ ids: [String], for userId: String?, defaults: UserDefaults = .standard) {
        guard let userId, !ids.isEmpty else { return }
        defaults.set(ids, forKey: key(userId))
    }
}

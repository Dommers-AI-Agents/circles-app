import Foundation

/// One thing under "Recent" on the home search: what the person actually
/// picked (a place, a person, a widget), or a search they ran with the
/// Search key without picking anything. Wes, 2026-11-03: recent shows the
/// selections, not the half-typed letters ("Walg", "Wo") that led there.
struct RecentSearchItem: Codable, Equatable {
    enum Kind: String, Codable {
        case query, place, person, widget
    }

    let kind: Kind
    /// The place, user or widget id; nil for a query
    let id: String?
    let title: String
    /// A place's address, a person's @username, a widget's one-liner
    let subtitle: String?
    /// A person's photo
    let imageURL: String?
    /// A place's canonical venue, to reopen it when it isn't one of their saves
    let globalPlaceId: String?
    /// A widget's SF Symbol
    let symbolName: String?

    init(kind: Kind, id: String? = nil, title: String, subtitle: String? = nil, imageURL: String? = nil,
         globalPlaceId: String? = nil, symbolName: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.globalPlaceId = globalPlaceId
        self.symbolName = symbolName
    }

    static func query(_ text: String) -> RecentSearchItem { RecentSearchItem(kind: .query, title: text) }

    /// Two entries are the same thing: the same place/person/widget, or the
    /// same words (case and accents aside)
    var key: String {
        if kind == .query || id == nil { return "q:" + PlaceSearchText.fold(title) }
        if kind == .place, let globalPlaceId { return "p:" + globalPlaceId }
        return "\(kind.rawValue):\(id ?? "")"
    }
}

struct RecentSearchList: Equatable {
    static let capacity = 8
    private(set) var items: [RecentSearchItem]

    init(_ items: [RecentSearchItem] = []) {
        self.items = Array(items.prefix(Self.capacity))
    }

    /// The titles, newest first
    var queries: [String] { items.map(\.title) }

    /// `item` moved (or added) to the front, replacing an older copy of the
    /// same thing; a too-short typed query isn't worth keeping.
    func adding(_ item: RecentSearchItem) -> RecentSearchList {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return self }
        if item.kind == .query, title.count < SearchDebouncer.minimumServerQueryLength { return self }
        let clean = RecentSearchItem(kind: item.kind, id: item.id, title: title, subtitle: item.subtitle,
                                     imageURL: item.imageURL, globalPlaceId: item.globalPlaceId, symbolName: item.symbolName)
        return RecentSearchList([clean] + items.filter { $0.key != clean.key })
    }

    func adding(_ query: String) -> RecentSearchList { adding(.query(query)) }

    func removing(_ item: RecentSearchItem) -> RecentSearchList {
        RecentSearchList(items.filter { $0.key != item.key })
    }

    func removing(_ query: String) -> RecentSearchList { removing(.query(query)) }

    /// This phone's list with the account's after it (a reinstall, a second
    /// phone): one copy of each thing, this phone's order first.
    func merging(_ other: RecentSearchList) -> RecentSearchList {
        var seen = Set<String>()
        return RecentSearchList((items + other.items).filter { seen.insert($0.key).inserted })
    }
}

/// UserDefaults persistence for `RecentSearchList`, keyed by user id; the
/// phone's copy. The account keeps one too (RecentSearchSync, Wes 2026-11-07:
/// a reinstall lost them), so `didSave` reports every change. The older list
/// of typed text (`homeRecentSearches.<uid>`) is left behind on purpose: it
/// was mostly half-typed letters.
final class RecentSearchStore {
    private let defaults: UserDefaults
    private let userId: () -> String?

    /// Every change, for the account copy (RecentSearchSync)
    private let didSave: ([RecentSearchItem]) -> Void

    init(defaults: UserDefaults = .standard, userId: @escaping () -> String? = { AuthService.shared.getUserId() },
         didSave: @escaping ([RecentSearchItem]) -> Void = { _ in }) {
        self.defaults = defaults
        self.userId = userId
        self.didSave = didSave
    }

    private var key: String? { userId().map { "homeRecentItems.\($0)" } }

    var list: RecentSearchList {
        guard let key, let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentSearchItem].self, from: data) else { return RecentSearchList() }
        return RecentSearchList(items)
    }

    func record(_ item: RecentSearchItem) {
        save(list.adding(item))
    }

    func record(_ query: String) { record(.query(query)) }

    func remove(_ item: RecentSearchItem) {
        save(list.removing(item))
    }

    func remove(_ query: String) { remove(.query(query)) }

    private func save(_ list: RecentSearchList) {
        replace(with: list)
        didSave(list.items)
    }

    /// The account's copy came back (RecentSearchSync): stored, not echoed up again.
    func replace(with list: RecentSearchList) {
        guard let key, let data = try? JSONEncoder().encode(list.items) else { return }
        defaults.set(data, forKey: key)
    }
}

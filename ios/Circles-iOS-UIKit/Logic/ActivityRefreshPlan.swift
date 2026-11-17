import Foundation

/// What a live refresh of the Activity feed should do with the rows on screen
/// (2026-11-16: new rows used to arrive by reloading the whole table). Pure.
enum ActivityRefreshPlan: Equatable {
    /// Nothing new, nothing gone
    case unchanged
    /// `added` are new activity ids, newest first; `removed` are ids the
    /// server no longer has. `atTop` says whether the viewer is at the top of
    /// the list, which decides between sliding the rows in and a pill.
    case changed(added: [String], removed: [String], atTop: Bool)

    /// `current`: ids on screen, newest first; `fresh`: the newest page from
    /// the server, newest first. A row newer than the oldest fresh row that
    /// the fresh page doesn't list was deleted on the server.
    static func plan(current: [(id: String, timestamp: Date)], fresh: [(id: String, timestamp: Date)], atTop: Bool) -> ActivityRefreshPlan {
        let onScreen = Set(current.map(\.id))
        let freshIds = Set(fresh.map(\.id))
        let added = fresh.map(\.id).filter { !onScreen.contains($0) }
        var removed: [String] = []
        if let oldestFetched = fresh.last?.timestamp {
            removed = current.filter { $0.timestamp > oldestFetched && !freshIds.contains($0.id) }.map(\.id)
        }
        guard !added.isEmpty || !removed.isEmpty else { return .unchanged }
        return .changed(added: added, removed: removed, atTop: atTop)
    }

    /// The pill's words: "1 new" / "3 new"
    static func pillTitle(count: Int) -> String { "\(count) new" }

    /// Slide the new rows in (and run their moment) only when the viewer is
    /// already at the top; otherwise they wait behind the pill.
    var slidesIn: Bool {
        if case .changed(let added, _, let atTop) = self { return atTop && !added.isEmpty }
        return false
    }
}

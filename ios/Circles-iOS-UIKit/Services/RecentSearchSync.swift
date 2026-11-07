import Foundation
import FavWidgetsCore

/// The home search's recent picks, kept on the account too (Wes, 2026-11-07:
/// deleting and reinstalling the app lost them; settings and history survive
/// a reinstall). One per-user document through the widget data API, like the
/// Home Screen shortcuts (HomeShortcutSettings). The phone's copy stays the
/// one the search reads; this keeps the account's in step.
enum RecentSearchSync {

    static let documentId = "home_recent_searches"

    private static func restoredKey(_ userId: String) -> String { "homeRecentSearches.restored.\(userId)" }

    /// Every change on the phone goes up (last write wins).
    static func push(_ items: [RecentSearchItem]) {
        guard AuthService.shared.isLoggedIn else { return }
        Task {
            let store = HomeWidgetsAPIDataStore()
            let current: WidgetDocument?
            do { current = try await store.load(id: documentId) } catch { return } // offline: the next change sends it
            await upload(items, store: store, current: current)
        }
    }

    /// Once per install and account: the account's recents join this phone's
    /// (a reinstall starts empty, so they simply come back).
    static func restoreOnce(into recents: RecentSearchStore) {
        guard AuthService.shared.isLoggedIn, let userId = KeychainService.shared.getUserId(),
              !UserDefaults.standard.bool(forKey: restoredKey(userId)) else { return }
        Task {
            let store = HomeWidgetsAPIDataStore()
            let loaded: WidgetDocument?
            do { loaded = try await store.load(id: documentId) } catch { return } // offline: next time
            let account = RecentSearchList(loaded.flatMap { try? JSONDecoder().decode([RecentSearchItem].self, from: $0.payload) } ?? [])
            let merged = await MainActor.run { () -> RecentSearchList in
                let merged = recents.list.merging(account)
                recents.replace(with: merged)
                return merged
            }
            if merged != account { await upload(merged.items, store: store, current: loaded) }
            UserDefaults.standard.set(true, forKey: restoredKey(userId))
        }
    }

    private static func upload(_ items: [RecentSearchItem], store: HomeWidgetsAPIDataStore, current: WidgetDocument?) async {
        guard let payload = try? JSONEncoder().encode(items) else { return }
        let document = WidgetDocument(version: current?.version ?? 0, payload: payload, schemaVersion: 1)
        _ = try? await store.save(id: documentId, document: document)
    }
}

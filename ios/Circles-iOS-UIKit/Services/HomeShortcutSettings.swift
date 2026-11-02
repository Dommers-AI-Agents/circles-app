import Foundation
import FavWidgetsCore

/// Reads and writes the Home Screen shortcuts and Home tab pins on this
/// phone and on the account (`HomeShortcutAccount`, 2026-11-01). Every
/// change goes through `saveSelection` / `savePins`; the app calls
/// `restoreOnce()` when it comes to the foreground signed in.
enum HomeShortcutSettings {

    static var storedSelection: [String]? {
        UserDefaults.standard.stringArray(forKey: HomeShortcutCatalog.selectionKey)
    }

    static func saveSelection(_ selection: [String]) {
        UserDefaults.standard.set(selection, forKey: HomeShortcutCatalog.selectionKey)
        push()
    }

    static func savePins(_ pins: [HomeButtonPin]) {
        HomeButtonPinStore.save(pins)
        push()
    }

    private static var phoneDocument: HomeShortcutAccount.Document {
        HomeShortcutAccount.Document(selection: storedSelection, pins: HomeButtonPinStore.load())
    }

    private static func restoredKey(_ userId: String) -> String { "homeShortcuts.restored.\(userId)" }

    /// Once per install and account: the account's shortcuts come back, or
    /// this phone's (chosen before they were saved to the account) go up.
    static func restoreOnce() {
        guard AuthService.shared.isLoggedIn, let userId = KeychainService.shared.getUserId(),
              !UserDefaults.standard.bool(forKey: restoredKey(userId)) else { return }
        Task {
            let store = HomeWidgetsAPIDataStore()
            let loaded: WidgetDocument?
            do { loaded = try await store.load(id: HomeShortcutAccount.documentId) } catch { return } // offline: next time
            let account = loaded.flatMap { try? JSONDecoder().decode(HomeShortcutAccount.Document.self, from: $0.payload) }
            switch HomeShortcutAccount.firstLaunch(account: account, phone: phoneDocument) {
            case .adopt(let document):
                await MainActor.run {
                    if let selection = document.selection {
                        UserDefaults.standard.set(selection, forKey: HomeShortcutCatalog.selectionKey)
                    }
                    HomeButtonPinStore.save(document.pins)
                    QuickCheckInShortcuts.updateFromCache()
                }
            case .upload:
                await upload(store: store, current: loaded)
            case .nothing:
                break
            }
            UserDefaults.standard.set(true, forKey: restoredKey(userId))
        }
    }

    /// Sends this phone's choices to the account (last write wins).
    private static func push() {
        guard AuthService.shared.isLoggedIn else { return }
        Task {
            let store = HomeWidgetsAPIDataStore()
            let current: WidgetDocument?
            do { current = try await store.load(id: HomeShortcutAccount.documentId) } catch { return }
            await upload(store: store, current: current)
        }
    }

    private static func upload(store: HomeWidgetsAPIDataStore, current: WidgetDocument?) async {
        guard let payload = try? JSONEncoder().encode(phoneDocument) else { return }
        let document = WidgetDocument(version: current?.version ?? 0, payload: payload, schemaVersion: 1)
        _ = try? await store.save(id: HomeShortcutAccount.documentId, document: document)
    }
}

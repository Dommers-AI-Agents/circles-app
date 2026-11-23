import Foundation

/// Whether a chat has the new look (color wash, grouped bubbles, day
/// dividers) or the classic one (Wes, 2026-11-23: "make this prettier").
/// Same two switches as the lively Activity feed, both on by default: the
/// server's `chat.polished` (off = every phone goes back on next launch, no
/// release) AND this phone's own toggle under Settings → Data. A chat reads
/// it when it opens.
enum ChatLookPreference {
    static let deviceKey = "chat.polished"

    /// This phone's toggle (default on)
    static var polishedOnThisPhone: Bool {
        get { UserDefaults.standard.object(forKey: deviceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: deviceKey) }
    }

    /// The server's switch (missing = on)
    static var polishedOnServer: Bool {
        ClientConfigService.shared.config.chat?.polished ?? true
    }

    static var isPolished: Bool { polishedOnServer && polishedOnThisPhone }

    static let rowTitle = "New chat look"
    static let rowDetail = "Grouped bubbles, day dividers and a color wash in Messages"
}

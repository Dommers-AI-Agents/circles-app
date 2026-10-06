import Foundation
import ActivityKit
import AppIntents

// Shared by the app and the Circles-Widget extension (membership exception
// in the project): what FavRun's lock-screen / Dynamic Island display
// shows, and its Pause/Resume button.

@available(iOS 16.1, *)
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: String        // "3.12"
        var unit: String            // "mi" / "km"
        var pace: String            // "8:42"
        var movingSeconds: Double   // shown while paused
        var clockStart: Date?       // running: the clock counts up from here by itself
        var isPaused: Bool
    }
}

extension Notification.Name {
    /// Posted in the app when the lock screen's Pause/Resume is tapped.
    static let runLiveActivityTogglePause = Notification.Name("RunLiveActivityTogglePause")
}

/// Runs in the app's process (LiveActivityIntent), so the run pauses
/// without opening the app.
@available(iOS 17.0, *)
struct ToggleRunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume run"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .runLiveActivityTogglePause, object: nil) }
        return .result()
    }
}

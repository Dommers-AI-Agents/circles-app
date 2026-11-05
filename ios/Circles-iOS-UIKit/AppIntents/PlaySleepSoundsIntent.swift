import AppIntents
import FavWidgets
import FavWidgetsCore

/// "Play Sleep Sounds" for the Shortcuts app (Wes, 2026-11-05): an audio
/// playback intent may start sound in the background, so a Shortcuts
/// automation (Time of Day → weekdays → Run Immediately) starts the bedtime
/// mix every night with no tap. Plays the Bedtime sound, else the last mix,
/// with the saved timer and volume (SleepSoundsBedtime.playNow).
@available(iOS 17.0, *)
struct PlaySleepSoundsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Sleep Sounds"
    static let description = IntentDescription("Starts your bedtime sleep sound in FavCircles, with its sleep timer.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let userId = KeychainService.shared.getUserId() else {
            return .result(dialog: "Sign in to FavCircles to play your sleep sounds.")
        }
        guard let name = await SleepSoundsBedtime.playNow(store: AppWidgetHost.makeDataStore(userId: userId)) else {
            return .result(dialog: "Sleep Sounds couldn't start. Open it in FavCircles and tap Play.")
        }
        return .result(dialog: "Playing \(name).")
    }
}

/// Puts "Play Sleep Sounds" in the Shortcuts app and Siri with no setup
@available(iOS 17.0, *)
struct FavCirclesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySleepSoundsIntent(),
            phrases: [
                "Play sleep sounds in \(.applicationName)",
                "Start sleep sounds in \(.applicationName)"
            ],
            shortTitle: "Play Sleep Sounds",
            systemImageName: "moon.zzz.fill"
        )
    }
}

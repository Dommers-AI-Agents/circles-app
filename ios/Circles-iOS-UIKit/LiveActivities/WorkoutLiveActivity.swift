import Foundation
import ActivityKit
import AppIntents

// Shared by the app and the Circles-Widget extension (membership exception
// in the project): the workout in progress on the lock screen / Dynamic
// Island, and its Done button for the next set (Wes, 2026-10-30).

@available(iOS 16.1, *)
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        var startedAt: Date          // the workout clock counts up from here by itself
        var doneSets: Int
        var totalSets: Int
        var exerciseName: String?    // nil once every set is done
        var setLabel: String?        // "Set 2 of 4"
        var numbers: String?         // "135 lb × 8"
        var nextSetId: String?       // what Done ticks
        var restEndsAt: Date?        // a rest countdown, if one is running
    }
    var sessionId: String
}

/// The app's side of the Done button. Set at launch; the intent runs in the
/// app's process, so it's there even when the tap cold-launches the app.
enum WorkoutLiveActivityBridge {
    static var completeSet: ((String) async -> Void)?
}

/// Ticks the set the lock screen shows, without opening the app.
@available(iOS 17.0, *)
struct CompleteWorkoutSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Done with this set"
    static var isDiscoverable = false

    @Parameter(title: "Set") var setId: String

    init() {}
    init(setId: String) { self.setId = setId }

    func perform() async throws -> some IntentResult {
        // The write happens here, awaited: a cold launch has no observers yet
        await WorkoutLiveActivityBridge.completeSet?(setId)
        return .result()
    }
}

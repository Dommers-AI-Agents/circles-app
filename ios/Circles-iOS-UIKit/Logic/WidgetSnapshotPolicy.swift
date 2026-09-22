import Foundation

/// Whether a home-screen widget refresh may overwrite the snapshot on disk.
///
/// The snapshot is written every time the app goes to the background. With
/// no signal both fetches fail instantly, and writing that result replaced
/// the rows the widget was showing with an empty card. A refresh in which
/// nothing came back has nothing to say; the last good snapshot stands.
enum WidgetSnapshotPolicy {
    static func shouldReplace(activitiesSucceeded: Bool, coinsSucceeded: Bool) -> Bool {
        activitiesSucceeded || coinsSucceeded
    }
}

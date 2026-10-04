import Foundation

/// What adding several photos to a place says, while it runs and when it ends.
///
/// Photos go up one at a time and each is attached as soon as it lands; one
/// that can't go up now waits on the phone and is added once there's a signal. (Edit Place used to upload a
/// batch and attach it in a separate save; when that save failed, every photo
/// was lost — Sal's two at the Atlantic Club, 2026-09-30.)
enum PlacePhotoBatchSummary {
    /// Most photos one pick may add.
    static let selectionLimit = 10

    /// "Uploading photo…" / "Uploading 2 of 3…"
    static func progress(current: Int, total: Int) -> String {
        total <= 1 ? "Uploading photo…" : "Uploading \(current) of \(total)…"
    }

    /// nil when nothing was attempted.
    static func result(added: Int, failed: Int) -> (title: String, message: String)? {
        switch (added, failed) {
        case (0, 0):
            return nil
        case (_, 0):
            return ("Added", added == 1 ? "Photo added" : "\(added) photos added")
        // `failed` photos are kept on the phone (PlacePhotoOutbox) and added
        // when there's a signal — nothing to redo
        case (0, _):
            return ("Saved for later", failed == 1
                    ? "No signal right now. Your photo will be added when you're back online."
                    : "No signal right now. Your \(failed) photos will be added when you're back online.")
        default:
            return ("Almost there", "\(added) added. \(failed) more will be added when you're back online.")
        }
    }
}

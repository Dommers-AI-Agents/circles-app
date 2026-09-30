import Foundation

/// What adding several photos to a place says, while it runs and when it ends.
///
/// Photos go up one at a time and each is attached as soon as it lands, so a
/// failure costs that one photo, not the batch. (Edit Place used to upload a
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
        case (0, _):
            return ("Couldn't upload", failed == 1 ? "The photo didn't upload. Try again." : "None of the \(failed) photos uploaded. Try again.")
        default:
            return ("Partly added", "\(added) added, \(failed) didn't upload. Try those again.")
        }
    }
}

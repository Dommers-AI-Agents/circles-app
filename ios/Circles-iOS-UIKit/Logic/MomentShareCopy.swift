import Foundation

/// The words on a shared moment. The link card is the whole message — the
/// app sends the URL alone, with no "check out this moment" bubble — so the
/// title has to carry the place. Mirrors the server's momentMeta.
enum MomentShareCopy {
    static func title(placeName: String?) -> String {
        let place = (placeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "Moment on Circles" : "Moment on Circles: \(place)"
    }
}

import Foundation

/// What the full-screen photo viewer shows when someone taps the place page's
/// top carousel: every carousel photo that has a URL, in carousel order, and
/// where the tapped one lands among them.
///
/// The carousel mixes venue photos, older save photos, a photo just taken on
/// this phone (no URL yet) and videos, so a carousel index is not a viewer
/// index. Videos keep their own player; a photo still uploading has nothing
/// to show full screen yet.
enum CarouselPhotoViewerMap {
    struct Result: Equatable {
        let urls: [String]
        let startIndex: Int
    }

    /// nil when the tapped item isn't a photo with a URL.
    static func viewer(for items: [MediaItem], tappedAt index: Int) -> Result? {
        guard items.indices.contains(index), url(of: items[index]) != nil else { return nil }
        var urls: [String] = []
        var start = 0
        for (i, item) in items.enumerated() {
            guard let url = url(of: item) else { continue }
            if i == index { start = urls.count }
            urls.append(url)
        }
        return Result(urls: urls, startIndex: start)
    }

    private static func url(of item: MediaItem) -> String? {
        switch item {
        case .photo(let url): return url.flatMap { $0.isEmpty ? nil : $0 }
        case .attributedPhoto(let photo): return photo.url.isEmpty ? nil : photo.url
        case .photoImage, .video: return nil
        }
    }
}

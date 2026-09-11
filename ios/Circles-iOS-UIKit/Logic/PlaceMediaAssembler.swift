import UIKit

/// Builds the ordered media list the place-detail carousel shows.
///
/// Extracted from `PlaceDetailViewController` so the merge rules are unit
/// tested rather than re-derived by reading a 4,000-line controller:
///
/// 1. Attributed venue photos (from the canonical GlobalPlace) come first —
///    they carry uploader attribution. The owner-curated cover photo leads.
/// 2. Legacy `place.photos` URLs not already represented follow. A URL we
///    already hold locally (a photo this session downloaded or captured) is
///    shown from memory instead of being re-fetched.
/// 3. Local photos not reflected in either server list (an upload whose
///    refresh hasn't landed) are appended.
/// 4. Videos follow the photos.
/// 5. With nothing at all, a single placeholder item.
///
/// Every photo URL appears at most once. The old exclusive-priority logic hid
/// legacy photos whenever the GlobalPlace doc had any photos at all.
struct PlaceMediaAssembler {
    struct LocalPhoto {
        let image: UIImage
        /// Storage URL once known — lets the carousel dedupe the local copy
        /// against the server lists.
        let url: String?
    }

    var attributedPhotos: [AttributedPhoto]? = nil
    var coverPhotoUrl: String? = nil
    var legacyPhotoUrls: [String]? = nil
    var localPhotos: [LocalPhoto] = []
    var videoUrls: [String]? = nil

    func assemble() -> [MediaItem] {
        var items: [MediaItem] = []
        var seenUrls = Set<String>()

        if var attributed = attributedPhotos {
            if let coverUrl = coverPhotoUrl,
               let coverIndex = attributed.firstIndex(where: { $0.url == coverUrl }),
               coverIndex != 0 {
                attributed.insert(attributed.remove(at: coverIndex), at: 0)
            }
            for photo in attributed {
                items.append(.attributedPhoto(photo: photo))
                seenUrls.insert(photo.url)
            }
        }

        for url in legacyPhotoUrls ?? [] where !seenUrls.contains(url) {
            seenUrls.insert(url)
            if let local = localPhotos.first(where: { $0.url == url }) {
                items.append(.photoImage(image: local.image))
            } else {
                items.append(.photo(url: url))
            }
        }

        for local in localPhotos {
            if let url = local.url {
                guard !seenUrls.contains(url) else { continue }
                seenUrls.insert(url)
            }
            items.append(.photoImage(image: local.image))
        }

        for url in videoUrls ?? [] {
            // The video URL doubles as its thumbnail until the API carries
            // separate thumbnail URLs.
            items.append(.video(thumbnailUrl: url, videoUrl: url))
        }

        if items.isEmpty {
            items.append(.photo(url: nil))
        }
        return items
    }
}

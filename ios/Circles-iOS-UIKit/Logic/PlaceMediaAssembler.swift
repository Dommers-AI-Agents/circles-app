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
/// 4. Short clips — the place's Moments recorded or uploaded in the app —
///    are woven in after the lead photo: photo, clip, photo, clip… so they
///    are seen without burying the photos (Wes, 2026-11-12). Pasted links
///    (TikTok, YouTube) and photo moments stay in the Moments row below.
/// 5. Legacy save videos follow, minus any that are already a clip.
/// 6. With nothing at all, a single placeholder item.
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
    /// Every moment at the place the viewer may see, newest first
    var moments: [PlaceVideo] = []

    /// A moment that plays in the strip: an in-app video with a file
    static func isClip(_ moment: PlaceVideo) -> Bool {
        !moment.isEmbedded && moment.contentType != "photo" && (moment.videoUrl?.isEmpty == false)
    }

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

        let clips = moments.filter(Self.isClip)
        if !clips.isEmpty {
            // Photo, clip, photo, clip… — the lead photo (the cover) stays first
            let photos = items
            items = []
            var pending = clips[...]
            for photo in photos {
                items.append(photo)
                if let clip = pending.popFirst() { items.append(.moment(clip)) }
            }
            items.append(contentsOf: pending.map { .moment($0) })
        }
        let clipUrls = Set(clips.compactMap(\.videoUrl))

        for url in videoUrls ?? [] where !clipUrls.contains(url) {
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

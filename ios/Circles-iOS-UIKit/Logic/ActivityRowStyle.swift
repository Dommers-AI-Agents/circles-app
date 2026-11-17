import Foundation

/// Which Activity rows get the big, media-first card and what it shows
/// (Wes, 2026-11-16: "make the activity feed feel more like a reel feed").
/// Everything without a picture stays the compact row. Pure, table-tested.
enum ActivityRowStyle: Equatable {
    case compact
    case hero(Hero)

    struct Coordinate: Equatable {
        let latitude: Double
        let longitude: Double
    }

    enum Hero: Equatable {
        /// A check-in: the map of the block (when the row carries coordinates)
        /// with the place photo inset, or the photo alone
        case checkIn(photo: String?, pin: Coordinate?)
        /// A saved place: its photo, "Saved to <circle>"
        case placeAdded(photo: String, circleName: String?)
        /// One or more photos at a place: a fanned stack
        case photos([String])
        /// A moment: its clip looping muted when the row knows the URL, else the thumbnail
        case moment(thumb: String, clip: String?)
        /// A postcard or Fridge Mail picture
        case postcard(String)
    }

    /// Up to this many photos in a stack
    static let maxStackPhotos = 6

    /// The style for one feed row. `enabled` is the server switch AND the
    /// phone's own toggle; off, every row is compact (today's feed).
    static func style(single activity: Activity, enabled: Bool = true) -> ActivityRowStyle {
        guard enabled else { return .compact }
        let meta = activity.metadata
        switch activity.type {
        case .checkIn:
            let pin = coordinate(meta)
            guard let photo = nonEmpty(meta?.placePhoto) ?? nil, true else {
                return pin.map { .hero(.checkIn(photo: nil, pin: $0)) } ?? .compact
            }
            return .hero(.checkIn(photo: photo, pin: pin))
        case .placeAdded:
            guard let photo = nonEmpty(meta?.placePhoto) else { return .compact }
            return .hero(.placeAdded(photo: photo, circleName: activity.circleName))
        case .photoUploaded:
            guard let photo = nonEmpty(meta?.placePhoto) else { return .compact }
            return .hero(.photos([photo]))
        case .videoUploaded:
            guard let thumb = nonEmpty(meta?.videoThumbnail) ?? nonEmpty(meta?.placePhoto) else { return .compact }
            return .hero(.moment(thumb: thumb, clip: meta?.contentType == "photo" ? nil : nonEmpty(meta?.videoUrl)))
        case .postcardSent, .postcardMailed, .fridgemailSent:
            guard let image = nonEmpty(meta?.imageUrl) else { return .compact }
            return .hero(.postcard(image))
        default:
            return .compact
        }
    }

    /// A collapsed burst: only an all-photos burst becomes a hero (the stack);
    /// mixed bursts keep the "added 12 places · Show all" summary row.
    static func style(group activities: [Activity], enabled: Bool = true) -> ActivityRowStyle {
        guard enabled, !activities.isEmpty, activities.allSatisfy({ $0.type == .photoUploaded }) else { return .compact }
        var seen = Set<String>()
        let photos = activities.compactMap { nonEmpty($0.metadata?.placePhoto) }.filter { seen.insert($0).inserted }
        guard !photos.isEmpty else { return .compact }
        return .hero(.photos(Array(photos.prefix(maxStackPhotos))))
    }

    /// The table's height guess per style, so scrolling stays smooth
    static func estimatedHeight(_ style: ActivityRowStyle) -> CGFloat {
        if case .hero = style { return 330 }
        return 120
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func coordinate(_ meta: ActivityMetadata?) -> Coordinate? {
        guard let lat = meta?.latitude, let lng = meta?.longitude, lat != 0 || lng != 0,
              abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        return Coordinate(latitude: lat, longitude: lng)
    }
}

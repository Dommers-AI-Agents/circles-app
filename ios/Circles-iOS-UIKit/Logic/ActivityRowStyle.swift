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
        /// A posted run: its route map, with the distance · time · pace line
        case run(snapshot: String, detail: String?)
        /// Anything else with a picture (a like, a comment, a circle): the
        /// picture with a short chip saying what happened (Wes, 2026-11-17:
        /// "make this pretty like the rest of the activity posts")
        case tagged(photo: String, chip: String)
    }

    /// Up to this many photos in a stack
    static let maxStackPhotos = 6

    /// The style for one feed row. `enabled` is the server switch AND the
    /// phone's own toggle; off, every row is compact (today's feed).
    /// `inGroup`: a row shown under its expanded burst stays compact — the
    /// burst's stack already shows its pictures.
    static func style(single activity: Activity, enabled: Bool = true, inGroup: Bool = false) -> ActivityRowStyle {
        guard enabled, !inGroup else { return .compact }
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
        case .runShared:
            // The route snapshot rides in placePhoto (or imageUrl); a run
            // without one stays the compact row with the runner badge
            guard let snapshot = nonEmpty(meta?.placePhoto) ?? nonEmpty(meta?.imageUrl) else { return .compact }
            return .hero(.run(snapshot: snapshot, detail: nonEmpty(meta?.runDetail)))
        default:
            guard let chip = chip(for: activity.type), let photo = picture(of: activity) else { return .compact }
            return .hero(.tagged(photo: photo, chip: chip))
        }
    }

    /// The chip on a `.tagged` card, by what the row says happened; nil for
    /// rows that never get a card (profile updates, suggestions, workouts…)
    static func chip(for type: ActivityType) -> String? {
        switch type {
        case .placeLiked: return "♥ Liked"
        case .globalPlaceLiked: return "♥ Liked this photo"
        case .videoLiked: return "♥ Liked this moment"
        case .commentLiked: return "♥ Liked a comment"
        case .circleLiked: return "♥ Liked this circle"
        case .placeCommented, .commentAdded, .circleCommented: return "💬 Commented"
        case .circleCreated: return "New circle"
        case .venueAnnouncement: return "📣 Announcement"
        case .venueOffer: return "🎁 New offer"
        default: return nil
        }
    }

    /// A collapsed burst: the stack of the pictures its activities carry
    /// (one per picture, at most `maxStackPhotos`); a burst with no pictures
    /// keeps the "liked 12 places · Show all" summary row.
    static func style(group activities: [Activity], enabled: Bool = true) -> ActivityRowStyle {
        guard enabled, !activities.isEmpty else { return .compact }
        var seen = Set<String>()
        let photos = activities.compactMap(picture(of:)).filter { seen.insert($0).inserted }
        guard !photos.isEmpty else { return .compact }
        return .hero(.photos(Array(photos.prefix(maxStackPhotos))))
    }

    /// The table's height guess per style, so scrolling stays smooth
    static func estimatedHeight(_ style: ActivityRowStyle) -> CGFloat {
        if case .hero = style { return 330 }
        return 120
    }

    /// The picture a row carries, the same chain the compact thumbnail uses
    static func picture(of activity: Activity) -> String? {
        let meta = activity.metadata
        return nonEmpty(meta?.placePhoto) ?? nonEmpty(meta?.videoThumbnail) ?? nonEmpty(meta?.imageUrl)
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

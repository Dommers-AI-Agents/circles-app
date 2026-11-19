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
        /// A place row with no picture but a pin: the map of the block
        case placeMap(pin: Coordinate, chip: String)
        /// A row with nothing to show: a designed card in the row's colour,
        /// the actor's photo as its wash, the name in large type (Wes,
        /// 2026-11-19: "I want every activity to have a full pretty card")
        case poster(Poster)
    }

    /// The colour family of a poster card
    enum Tint: Equatable { case brand, like, comment, circle, workout, run, mail, people, store }

    struct Poster: Equatable {
        let symbol: String
        let title: String
        let detail: String?
        let chip: String?
        let tint: Tint
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
            guard let photo = nonEmpty(meta?.placePhoto) else {
                if let pin { return .hero(.checkIn(photo: nil, pin: pin)) }
                return .hero(.poster(poster(for: activity)))
            }
            return .hero(.checkIn(photo: photo, pin: pin))
        case .placeAdded:
            if let photo = nonEmpty(meta?.placePhoto) {
                return .hero(.placeAdded(photo: photo, circleName: activity.circleName))
            }
            if let pin = coordinate(meta) { return .hero(.placeMap(pin: pin, chip: savedChip(activity.circleName))) }
            return .hero(.poster(poster(for: activity)))
        case .photoUploaded:
            guard let photo = nonEmpty(meta?.placePhoto) else { return .hero(.poster(poster(for: activity))) }
            return .hero(.photos([photo]))
        case .videoUploaded:
            guard let thumb = nonEmpty(meta?.videoThumbnail) ?? nonEmpty(meta?.placePhoto) else { return .hero(.poster(poster(for: activity))) }
            return .hero(.moment(thumb: thumb, clip: meta?.contentType == "photo" ? nil : nonEmpty(meta?.videoUrl)))
        case .postcardSent, .postcardMailed, .fridgemailSent:
            guard let image = nonEmpty(meta?.imageUrl) else { return .hero(.poster(poster(for: activity))) }
            return .hero(.postcard(image))
        case .runShared:
            // The route snapshot rides in placePhoto (or imageUrl); a run
            // without one is the runner on FavRun's orange
            guard let snapshot = nonEmpty(meta?.placePhoto) ?? nonEmpty(meta?.imageUrl) else { return .hero(.poster(poster(for: activity))) }
            return .hero(.run(snapshot: snapshot, detail: nonEmpty(meta?.runDetail)))
        default:
            if let chip = chip(for: activity.type), let photo = picture(of: activity) {
                return .hero(.tagged(photo: photo, chip: chip))
            }
            if let chip = chip(for: activity.type), activity.targetType == "place", let pin = coordinate(meta) {
                return .hero(.placeMap(pin: pin, chip: chip))
            }
            return .hero(.poster(poster(for: activity)))
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
    /// is a poster card carrying the "liked 12 places" summary.
    static func style(group activities: [Activity], enabled: Bool = true) -> ActivityRowStyle {
        guard enabled, !activities.isEmpty else { return .compact }
        var seen = Set<String>()
        let photos = activities.compactMap(picture(of:)).filter { seen.insert($0).inserted }
        if !photos.isEmpty { return .hero(.photos(Array(photos.prefix(maxStackPhotos)))) }
        let lead = activities[0]
        return .hero(.poster(Poster(symbol: "square.stack.fill", title: activities.groupSummary.capitalizedFirst,
                                    detail: nil, chip: "\(activities.count) activities", tint: tint(for: lead.type))))
    }

    static func savedChip(_ circleName: String?) -> String {
        circleName.map { "Saved to \($0)" } ?? "Saved"
    }

    /// The poster for a row with nothing else to show: its symbol, the thing's
    /// name in large type, the kind's colour, the same chip a pictured row gets
    static func poster(for activity: Activity) -> Poster {
        let meta = activity.metadata
        let name = activity.targetName
        let type = activity.type
        let tint = tint(for: type)
        switch type {
        case .checkIn:
            return Poster(symbol: "mappin.and.ellipse", title: name, detail: nonEmpty(meta?.message), chip: "Checked in", tint: tint)
        case .placeAdded:
            return Poster(symbol: "mappin.circle.fill", title: name, detail: nil, chip: savedChip(activity.circleName), tint: tint)
        case .photoUploaded:
            return Poster(symbol: "photo.fill", title: name, detail: nil, chip: "Photo", tint: tint)
        case .videoUploaded:
            return Poster(symbol: "play.rectangle.fill", title: name, detail: nil, chip: meta?.contentType == "photo" ? "Photo" : "Moment", tint: tint)
        case .placeDiscovered:
            return Poster(symbol: "sparkles", title: name, detail: nil, chip: "Discovered", tint: tint)
        case .suggestionSent:
            return Poster(symbol: "paperplane.fill", title: name, detail: nil, chip: "Suggested", tint: tint)
        case .suggestionAccepted:
            return Poster(symbol: "checkmark.seal.fill", title: name, detail: nil, chip: "Accepted a suggestion", tint: tint)
        case .reactionAdded:
            return Poster(symbol: "hand.thumbsup.fill", title: name, detail: nil, chip: "Reacted", tint: tint)
        case .workoutShared:
            return Poster(symbol: "dumbbell.fill", title: name, detail: nonEmpty(meta?.workoutDetail), chip: "🏋️ Workout", tint: tint)
        case .runShared:
            return Poster(symbol: "figure.run", title: "Went for a run", detail: nonEmpty(meta?.runDetail), chip: nonEmpty(meta?.runDetail).map { "🏃 \($0)" } ?? "🏃 Run", tint: tint)
        case .postcardSent, .postcardMailed:
            return Poster(symbol: "envelope.fill", title: "To \(name)", detail: nil, chip: type == .postcardMailed ? "Printed postcard" : "Postcard", tint: tint)
        case .fridgemailSent:
            return Poster(symbol: "envelope.open.fill", title: "To \(name)", detail: nil, chip: "Fridge Mail", tint: tint)
        case .venueAnnouncement:
            return Poster(symbol: "megaphone.fill", title: nonEmpty(meta?.message) ?? name, detail: nonEmpty(meta?.message) == nil ? nil : name, chip: "📣 Announcement", tint: tint)
        case .venueOffer:
            return Poster(symbol: "gift.fill", title: nonEmpty(meta?.message) ?? name, detail: nonEmpty(meta?.message) == nil ? nil : name, chip: "🎁 New offer", tint: tint)
        case .circleCreated:
            return Poster(symbol: "circle.hexagongrid.fill", title: name, detail: nil, chip: "New circle", tint: tint)
        case .circleLiked, .circleCommented:
            return Poster(symbol: "circle.hexagongrid.fill", title: name, detail: nil, chip: chip(for: type), tint: tint)
        case .placeLiked, .globalPlaceLiked, .videoLiked, .commentLiked:
            return Poster(symbol: "heart.fill", title: name, detail: nil, chip: chip(for: type), tint: tint)
        case .placeCommented, .commentAdded:
            return Poster(symbol: "text.bubble.fill", title: name, detail: nil, chip: chip(for: type), tint: tint)
        case .profileUpdated:
            return Poster(symbol: "person.crop.circle.badge.checkmark", title: "Updated their profile", detail: nil, chip: nil, tint: tint)
        case .userActivity, .unknown:
            return Poster(symbol: "sparkles", title: activity.formattedDescription.capitalizedFirst, detail: nil, chip: nil, tint: tint)
        }
    }

    static func tint(for type: ActivityType) -> Tint {
        switch type {
        case .placeLiked, .globalPlaceLiked, .videoLiked, .commentLiked, .circleLiked, .reactionAdded: return .like
        case .placeCommented, .commentAdded, .circleCommented: return .comment
        case .circleCreated: return .circle
        case .workoutShared: return .workout
        case .runShared: return .run
        case .postcardSent, .postcardMailed, .fridgemailSent: return .mail
        case .profileUpdated, .userActivity, .suggestionSent, .suggestionAccepted: return .people
        case .venueAnnouncement, .venueOffer: return .store
        default: return .brand
        }
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

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

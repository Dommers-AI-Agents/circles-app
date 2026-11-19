import Testing
import Foundation
@testable import Circles_iOS

/// The lively Activity feed (2026-11-16): which rows get a hero card, what a
/// live refresh does, and which clip plays.
struct ActivityRowStyleTests {
    private func activity(_ type: ActivityType, photo: String? = nil, lat: Double? = nil, lng: Double? = nil,
                          thumb: String? = nil, clip: String? = nil, contentType: String? = nil, image: String? = nil,
                          circle: String? = nil, runDetail: String? = nil, workoutDetail: String? = nil,
                          gym: String? = nil, id: String = "a") -> Activity {
        let json: [String: Any?] = [
            "_id": id, "type": type.rawValue, "actorId": "u1", "targetType": "place", "targetId": "p1", "targetName": "Sal's",
            "circleName": circle, "timestamp": "2026-11-16T15:00:00Z",
            "metadata": ["placePhoto": photo, "latitude": lat, "longitude": lng, "videoThumbnail": thumb,
                         "videoUrl": clip, "contentType": contentType, "imageUrl": image, "runDetail": runDetail,
                         "workoutDetail": workoutDetail, "workoutPlaceName": gym].compactMapValues { $0 }
        ]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Activity.self, from: data)
    }

    @Test func aWorkoutAtAGymShowsTheGymsPhoto() {
        let atGym = activity(.workoutShared, photo: "ymca.jpg", workoutDetail: "5 exercises · 54 min", gym: "Dowd YMCA")
        let poster = ActivityRowStyle.Poster(symbol: "dumbbell.fill", title: "Sal's", detail: "5 exercises · 54 min · Dowd YMCA",
                                             chip: "🏋️ Workout", tint: .workout)
        #expect(ActivityRowStyle.style(single: atGym) == .hero(.workout(photo: "ymca.jpg", poster: poster)))
        // No check-in nearby: the blue Workouts card, as before
        let home = activity(.workoutShared, workoutDetail: "5 exercises · 54 min")
        #expect(ActivityRowStyle.style(single: home) == .hero(.poster(.init(symbol: "dumbbell.fill", title: "Sal's",
                                                                            detail: "5 exercises · 54 min", chip: "🏋️ Workout", tint: .workout))))
    }

    @Test func rowsWithPicturesBecomeHeroCards() {
        let pin = ActivityRowStyle.Coordinate(latitude: 35.2, longitude: -80.8)
        #expect(ActivityRowStyle.style(single: activity(.checkIn, photo: "p.jpg", lat: 35.2, lng: -80.8)) == .hero(.checkIn(photo: "p.jpg", pin: pin)))
        #expect(ActivityRowStyle.style(single: activity(.checkIn, lat: 35.2, lng: -80.8)) == .hero(.checkIn(photo: nil, pin: pin)))
        // A check-in with neither photo nor pin: a poster, never the bare row (2026-11-19)
        #expect(ActivityRowStyle.style(single: activity(.checkIn)) == .hero(.poster(.init(symbol: "mappin.and.ellipse", title: "Sal's", detail: nil, chip: "Checked in", tint: .brand))))
        #expect(ActivityRowStyle.style(single: activity(.placeAdded, photo: "p.jpg", circle: "Brunch")) == .hero(.placeAdded(photo: "p.jpg", circleName: "Brunch")))
        #expect(ActivityRowStyle.style(single: activity(.placeAdded, lat: 35.2, lng: -80.8, circle: "Brunch")) == .hero(.placeMap(pin: pin, chip: "Saved to Brunch")))
        #expect(ActivityRowStyle.style(single: activity(.placeAdded, circle: "Brunch")) == .hero(.poster(.init(symbol: "mappin.circle.fill", title: "Sal's", detail: nil, chip: "Saved to Brunch", tint: .brand))))
        #expect(ActivityRowStyle.style(single: activity(.photoUploaded, photo: "p.jpg")) == .hero(.photos(["p.jpg"])))
        #expect(ActivityRowStyle.style(single: activity(.videoUploaded, thumb: "t.jpg", clip: "c.mp4")) == .hero(.moment(thumb: "t.jpg", clip: "c.mp4")))
        // A photo moment never loops; an older row has no clip
        #expect(ActivityRowStyle.style(single: activity(.videoUploaded, thumb: "t.jpg", clip: "c.mp4", contentType: "photo")) == .hero(.moment(thumb: "t.jpg", clip: nil)))
        #expect(ActivityRowStyle.style(single: activity(.videoUploaded, thumb: "t.jpg")) == .hero(.moment(thumb: "t.jpg", clip: nil)))
        #expect(ActivityRowStyle.style(single: activity(.postcardSent, image: "card.jpg")) == .hero(.postcard("card.jpg")))
        // Likes, comments and circles with a picture are cards too, with a chip saying which (2026-11-17)
        #expect(ActivityRowStyle.style(single: activity(.placeLiked, photo: "p.jpg")) == .hero(.tagged(photo: "p.jpg", chip: "♥ Liked")))
        #expect(ActivityRowStyle.style(single: activity(.globalPlaceLiked, photo: "liked.jpg")) == .hero(.tagged(photo: "liked.jpg", chip: "♥ Liked this photo")))
        #expect(ActivityRowStyle.style(single: activity(.videoLiked, thumb: "t.jpg")) == .hero(.tagged(photo: "t.jpg", chip: "♥ Liked this moment")))
        #expect(ActivityRowStyle.style(single: activity(.placeCommented, photo: "p.jpg")) == .hero(.tagged(photo: "p.jpg", chip: "💬 Commented")))
        #expect(ActivityRowStyle.style(single: activity(.circleCreated, photo: "cover.jpg")) == .hero(.tagged(photo: "cover.jpg", chip: "New circle")))
        #expect(ActivityRowStyle.style(single: activity(.placeLiked, lat: 35.2, lng: -80.8)) == .hero(.placeMap(pin: pin, chip: "♥ Liked")))
        #expect(ActivityRowStyle.style(single: activity(.placeLiked)) == .hero(.poster(.init(symbol: "heart.fill", title: "Sal's", detail: nil, chip: "♥ Liked", tint: .like))))
        #expect(ActivityRowStyle.style(single: activity(.profileUpdated, photo: "p.jpg")) == .hero(.poster(.init(symbol: "person.crop.circle.badge.checkmark", title: "Updated their profile", detail: nil, chip: nil, tint: .people))))
        // A row shown under its expanded burst stays compact: the burst's stack has its picture
        #expect(ActivityRowStyle.style(single: activity(.placeLiked, photo: "p.jpg"), inGroup: true) == .compact)
        #expect(ActivityRowStyle.style(single: activity(.checkIn, photo: "p.jpg"), inGroup: true) == .compact)
        // A posted run: the route map leads, the stats are the chip (2026-11-17)
        #expect(ActivityRowStyle.style(single: activity(.runShared, photo: "route.png", runDetail: "5.00 mi · 48:59 · 9:48/mi")) == .hero(.run(snapshot: "route.png", detail: "5.00 mi · 48:59 · 9:48/mi")))
        #expect(ActivityRowStyle.style(single: activity(.runShared, runDetail: "3.10 mi")) == .hero(.poster(.init(symbol: "figure.run", title: "Went for a run", detail: "3.10 mi", chip: "🏃 3.10 mi", tint: .run))))
        // The switch off: today's feed
        #expect(ActivityRowStyle.style(single: activity(.checkIn, photo: "p.jpg"), enabled: false) == .compact)
        // A 0,0 pin is no pin
        if case .hero(.poster) = ActivityRowStyle.style(single: activity(.checkIn, lat: 0, lng: 0)) {} else { Issue.record("expected a poster") }
    }

    /// Wes, 2026-11-19: "I want every activity to have a full pretty card" —
    /// every kind the app knows, with nothing in its metadata, is a card
    @Test func everyKindOfActivityIsACard() {
        for type in ActivityType.allCases {
            let style = ActivityRowStyle.style(single: activity(type))
            if case .hero = style {} else { Issue.record("\(type) is not a card: \(style)") }
            #expect(ActivityRowStyle.style(single: activity(type), enabled: false) == .compact)
        }
    }

    @Test func aBurstWithPicturesIsAStackAndOneWithoutStaysCompact() {
        let photos = [activity(.photoUploaded, photo: "1.jpg", id: "1"), activity(.photoUploaded, photo: "2.jpg", id: "2"), activity(.photoUploaded, photo: "2.jpg", id: "3")]
        #expect(ActivityRowStyle.style(group: photos) == .hero(.photos(["1.jpg", "2.jpg"])))
        let many = (0..<9).map { activity(.photoUploaded, photo: "\($0).jpg", id: "\($0)") }
        if case .hero(.photos(let urls)) = ActivityRowStyle.style(group: many) { #expect(urls.count == ActivityRowStyle.maxStackPhotos) } else { Issue.record("expected a stack") }
        // A mixed burst stacks whatever pictures it has (Wes, 2026-11-17); one with none keeps the summary row
        #expect(ActivityRowStyle.style(group: [activity(.photoUploaded, photo: "1.jpg"), activity(.placeAdded, photo: "p.jpg")]) == .hero(.photos(["1.jpg", "p.jpg"])))
        #expect(ActivityRowStyle.style(group: [activity(.placeLiked, photo: "1.jpg", id: "1"), activity(.placeLiked, photo: "2.jpg", id: "2")]) == .hero(.photos(["1.jpg", "2.jpg"])))
        // A burst with no pictures is a poster carrying its summary
        #expect(ActivityRowStyle.style(group: [activity(.placeLiked, id: "1"), activity(.placeCommented, id: "2")])
                == .hero(.poster(.init(symbol: "square.stack.fill", title: "Liked Sal's and commented on Sal's", detail: nil, chip: "2 activities", tint: .like))))
        #expect(ActivityRowStyle.style(group: photos, enabled: false) == .compact)
        #expect(ActivityRowStyle.estimatedHeight(.compact) < ActivityRowStyle.estimatedHeight(.hero(.photos(["1.jpg"]))))
    }
}

struct ActivityRefreshPlanTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func row(_ id: String, _ minutesAgo: Double) -> (id: String, timestamp: Date) { (id, Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60)) }

    @Test func newRowsSlideInAtTheTopAndWaitBehindAPillOtherwise() {
        let current = [row("b", 10), row("c", 20)]
        let fresh = [row("a", 1), row("b", 10), row("c", 20)]
        #expect(ActivityRefreshPlan.plan(current: current, fresh: fresh, atTop: true) == .changed(added: ["a"], removed: [], atTop: true))
        #expect(ActivityRefreshPlan.plan(current: current, fresh: fresh, atTop: true).slidesIn)
        #expect(!ActivityRefreshPlan.plan(current: current, fresh: fresh, atTop: false).slidesIn)
        #expect(ActivityRefreshPlan.plan(current: current, fresh: [row("b", 10), row("c", 20)], atTop: true) == .unchanged)
        #expect(ActivityRefreshPlan.pillTitle(count: 3) == "3 new")
    }

    @Test func aRowTheServerNoLongerListsIsRemoved() {
        // "b" is newer than the oldest fresh row and missing from the fresh page: deleted
        let current = [row("b", 5), row("c", 20), row("d", 40)]
        let fresh = [row("a", 1), row("c", 20)]
        #expect(ActivityRefreshPlan.plan(current: current, fresh: fresh, atTop: false) == .changed(added: ["a"], removed: ["b"], atTop: false))
        // "d" is older than the fresh page covers: left alone
    }
}

struct ActivityClipFocusTests {
    @Test func theClipNearestTheMiddlePlays() {
        #expect(ActivityClipFocus.focusedRow(rows: [(2, 100), (5, 420), (9, 900)], visibleMidY: 400) == 5)
        #expect(ActivityClipFocus.focusedRow(rows: [], visibleMidY: 400) == nil)
    }
}

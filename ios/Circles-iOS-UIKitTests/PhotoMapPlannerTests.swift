import Foundation
import CoreLocation
import Testing
@testable import Circles_iOS

/// Build my map from my photos: nearest first, then the regulars, then recent.
struct PhotoMapPlannerTests {
    private let home = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431) // Charlotte
    private func spot(_ lat: Double, _ lng: Double, days: Int = 1, photos: Int = 2, start: TimeInterval = 0) -> PhotoLibraryMath.Spot {
        let shots = (0..<max(days, photos)).map { i in
            PhotoLibraryMath.Shot(id: "\(lat)-\(lng)-\(i)", lat: lat, lng: lng,
                                  date: Date(timeIntervalSince1970: 1_790_000_000 + start + Double(i % days) * 86_400 + Double(i) * 60))
        }
        return PhotoLibraryMath.Spot(shots: shots, center: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    @Test func nearbyBeforeTheAreaBeforeTrips() {
        let paris = spot(48.8566, 2.3522, days: 5, photos: 30)   // a big trip
        let rockHill = spot(34.9249, -81.0251)                   // ~25 mi
        let southEnd = spot(35.2120, -80.8580)                   // ~1.5 mi
        let order = PhotoMapPlanner.ordered([paris, rockHill, southEnd], origin: home)
        #expect(order.map(\.center.latitude) == [35.2120, 34.9249, 48.8566])
    }

    @Test func withinATierRegularsThenRecent() {
        let oneOff = spot(35.22, -80.84, days: 1, photos: 9, start: 1_000_000)
        let regular = spot(35.23, -80.85, days: 4)
        let older = spot(35.24, -80.86, days: 1, start: 0)
        let order = PhotoMapPlanner.ordered([older, oneOff, regular], origin: home)
        #expect(order.map(\.center.latitude) == [35.23, 35.22, 35.24])
    }

    @Test func noLocationMeansMostPhotographedFirst() {
        let few = spot(35.22, -80.84, photos: 2)
        let many = spot(48.85, 2.35, photos: 20)
        #expect(PhotoMapPlanner.ordered([few, many], origin: nil).first?.center.latitude == 48.85)
        #expect(PhotoMapPlanner.origin(current: nil, home: home)?.latitude == home.latitude)
    }

    @Test func homeSavesAndEarlierRunsAreSkipped() {
        let atHome = spot(home.latitude + 0.0005, home.longitude)
        let saved = spot(35.30, -80.80)
        let done = spot(35.10, -80.70)
        let fresh = spot(35.15, -80.75)
        let left = PhotoMapPlanner.candidates([atHome, saved, done, fresh], home: home,
                                              saved: [saved.center], done: [PhotoMapPlanner.key(done)])
        #expect(left == [fresh])
    }

    @Test func words() {
        #expect(PhotoMapPlanner.progressLine(added: 1, checked: 3, total: 40) == "Added 1 place \u{00B7} checked 3 of 40 spots")
        #expect(PhotoMapPlanner.limitLine(added: 25, freeMax: 25, more: 12).contains("12 more spots"))
        #expect(PhotoMapPlanner.doneLine(added: 0).hasPrefix("No new places"))
        #expect(PhotoMapPlanner.coinsLine(3) == "+3 FavCoins for building your map")
        #expect(PhotoMapPlanner.coinsLine(0) == nil)
    }

    @Test func doneStoreIsPerAccount() {
        let defaults = UserDefaults(suiteName: "PhotoMapPlannerTests")!
        defaults.removePersistentDomain(forName: "PhotoMapPlannerTests")
        PhotoMapProgressStore.markDone(["a", "b"], uid: "u1", defaults: defaults)
        #expect(PhotoMapProgressStore.done(uid: "u1", defaults: defaults) == ["a", "b"])
        #expect(PhotoMapProgressStore.done(uid: "u2", defaults: defaults).isEmpty)
    }
}

/// My Places + → each origin of your own places switches on or off.
struct MapOriginVisibilityTests {
    private func place(_ id: String, by uid: String, source: String?) -> Place {
        var place = Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: "c", addedBy: uid, addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
        place.importSource = source
        return place
    }

    @Test func hidingAnOriginOnlyHidesYourOwnPlacesFromIt() {
        let mine = place("mine", by: "me", source: nil)
        let photo = place("photo", by: "me", source: "photos")
        let friendsPhoto = place("friend", by: "ana", source: "photos")
        let left = HomePlaceFilter.excludingHiddenOrigins([mine, photo, friendsPhoto], hidden: ["photos"], currentUserId: "me")
        #expect(left.map(\.id) == ["mine", "friend"])
        #expect(HomePlaceFilter.excludingHiddenOrigins([mine, photo], hidden: ["in_app"], currentUserId: "me").map(\.id) == ["photo"])
    }

    @Test func togglesPerAccount() {
        let defaults = UserDefaults(suiteName: "MapOriginVisibilityTests")!
        defaults.removePersistentDomain(forName: "MapOriginVisibilityTests")
        #expect(MapOriginVisibility.toggle("photos", uid: "me", defaults: defaults) == false)
        #expect(MapOriginVisibility.hidden(uid: "me", defaults: defaults) == ["photos"])
        #expect(MapOriginVisibility.hidden(uid: "you", defaults: defaults).isEmpty)
        #expect(MapOriginVisibility.toggle("photos", uid: "me", defaults: defaults) == true)
        #expect(MapOriginVisibility.isVisible("photos", uid: "me", defaults: defaults))
    }
}

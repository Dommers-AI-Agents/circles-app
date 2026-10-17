import UIKit
import MapKit
import CoreLocation

/// Where a find's photo comes from: the photo library (scans) or the image
/// the person picked (no library access needed).
enum PhotoRef {
    case asset(String)
    case image(UIImage)
}

/// One spot where photos were taken, before Apple Maps says what's there.
struct PhotoFindSpot {
    let key: String
    let center: CLLocationCoordinate2D
    let start: Date
    let photoCount: Int
    let photo: PhotoRef
    /// Every photo taken at this spot, in the order taken (the place card
    /// shows them; they never leave the phone)
    let photos: [PhotoRef]

    /// Library scans: a stop from PhotoLibraryMath with its middle photo.
    init(spot: PhotoLibraryMath.Spot) {
        key = PhotoMapPlanner.key(spot)
        center = spot.center
        start = spot.start
        photoCount = spot.shots.count
        photo = .asset(spot.shots[spot.shots.count / 2].id)
        photos = spot.shots.map { .asset($0.id) }
    }

    init(key: String, center: CLLocationCoordinate2D, start: Date, photoCount: Int, photo: PhotoRef, photos: [PhotoRef]? = nil) {
        self.key = key; self.center = center; self.start = start; self.photoCount = photoCount; self.photo = photo
        self.photos = photos ?? [photo]
    }

    /// Library scans: stops in these photos, minus home, places already saved
    /// and spots handled on an earlier run; nearest first from `origin`
    /// (Build my map) or in the order taken (a time period).
    static func fromLibrary(_ shots: [PhotoLibraryMath.Shot], saved: [CLLocationCoordinate2D], done: Set<String>,
                            nearestTo origin: CLLocationCoordinate2D?, nearestFirst: Bool) -> [PhotoFindSpot] {
        let ordered = shots.sorted { $0.date < $1.date }
        let home = PhotoLibraryMath.home(ordered)
        let spots = PhotoMapPlanner.candidates(PhotoLibraryMath.spots(ordered), home: home, saved: saved, done: done)
        let sorted = nearestFirst
            ? PhotoMapPlanner.ordered(spots, origin: PhotoMapPlanner.origin(current: origin, home: home))
            : spots.sorted { $0.start < $1.start }
        return sorted.map(PhotoFindSpot.init(spot:))
    }

    /// Picked photos: one spot per group of photos within 75 m. Returns the
    /// spots and how many picked photos had no location.
    static func fromPicked(_ picked: [PhotoMetadataReader.Picked]) -> (spots: [PhotoFindSpot], unlocated: Int) {
        let fixes = picked.enumerated().map { PhotoPlaceGrouper.Fix(id: $0.offset, coordinate: $0.element.coordinate, takenAt: $0.element.takenAt) }
        var unlocated = 0
        var spots: [PhotoFindSpot] = []
        for group in PhotoPlaceGrouper.group(fixes) {
            guard let center = group.center, let first = group.photoIds.first else {
                unlocated += group.photoIds.count
                continue
            }
            spots.append(PhotoFindSpot(
                key: String(format: "%.3f,%.3f", center.latitude, center.longitude), center: center,
                start: group.takenAt ?? Date(), photoCount: group.photoIds.count, photo: .image(picked[first].image),
                photos: group.photoIds.map { .image(picked[$0].image) }))
        }
        return (spots, unlocated)
    }
}

/// A spot with the places Apple Maps found there (nearest first), the one
/// chosen, and whether it's checked for saving.
final class PhotoFind {
    let spot: PhotoFindSpot
    let candidates: [MKMapItem]
    var choice = 0
    /// Checked by default (Wes, 2026-10-17): uncheck the ones you don't want
    var include = true
    /// Saved already (a later batch failed or hit the free limit)
    var saved = false

    /// Your own photo goes on the place only if you ask (off: the photo is
    /// just how the place was found; saved places get Apple's street photo)
    var addMyPhoto = false
    /// Every visit to this place in the photos (repeat visits merge into the
    /// first row instead of listing the same place again)
    private(set) var spotKeys: [String]
    private(set) var photoCount: Int
    private(set) var visits = 1
    private(set) var lastVisit: Date
    /// Every photo from every visit, oldest visit first
    private(set) var photos: [PhotoRef]

    init(spot: PhotoFindSpot, candidates: [MKMapItem]) {
        self.spot = spot
        self.candidates = candidates
        spotKeys = [spot.key]
        photoCount = spot.photoCount
        lastVisit = spot.start
        photos = spot.photos
    }

    var item: MKMapItem { candidates[min(choice, candidates.count - 1)] }

    /// Another visit to the same place
    func absorb(_ other: PhotoFindSpot) {
        spotKeys.append(other.key)
        photoCount += other.photoCount
        visits += 1
        lastVisit = max(lastVisit, other.start)
        photos += other.photos
    }

    /// Same place: same name, pins within 60 m (a chain's other branch is
    /// farther away than that)
    func isSamePlace(as other: MKMapItem) -> Bool {
        guard let a = item.name?.lowercased(), let b = other.name?.lowercased(), a == b else { return false }
        let here = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        let there = CLLocation(latitude: other.placemark.coordinate.latitude, longitude: other.placemark.coordinate.longitude)
        return here.distance(from: there) <= 60
    }
}

/// Looks up each spot with Apple Maps, one at a time (paced for Apple's ~50
/// a minute), keeping only real places (PhotoPlaceKind). Main thread.
final class PhotoPlaceFinder {
    enum Event { case found(PhotoFind), merged(PhotoFind), progress, finished }

    private(set) var spots: [PhotoFindSpot]
    private(set) var checked = 0
    private(set) var finds: [PhotoFind] = []
    private(set) var isRunning = false
    /// Pause once this many places are found ("Keep looking" resumes)
    var pauseAfterFinds: Int?
    var onEvent: ((Event) -> Void)?

    init(spots: [PhotoFindSpot]) { self.spots = spots }

    var isDone: Bool { checked >= spots.count }

    func start() {
        guard !isRunning, !isDone else { return }
        isRunning = true
        next()
    }

    func stop() { isRunning = false }

    private func next() {
        guard isRunning else { return }
        if let pause = pauseAfterFinds, finds.count >= pause {
            isRunning = false
            onEvent?(.finished)
            return
        }
        guard checked < spots.count else {
            isRunning = false
            onEvent?(.finished)
            return
        }
        let spot = spots[checked]
        let started = Date()
        NearbyPOILookup.savablePlaces(near: spot.center) { [weak self] items in
            guard let self, self.isRunning else { return }
            self.checked += 1
            if let best = items.first {
                if let existing = self.finds.first(where: { $0.isSamePlace(as: best) }) {
                    existing.absorb(spot)
                    self.onEvent?(.merged(existing))
                } else {
                    let find = PhotoFind(spot: spot, candidates: items)
                    self.finds.append(find)
                    self.onEvent?(.found(find))
                }
            }
            self.onEvent?(.progress)
            let pace = max(0, 1.2 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + pace) { self.next() }
        }
    }
}

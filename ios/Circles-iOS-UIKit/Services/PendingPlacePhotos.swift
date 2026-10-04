import UIKit
import CoreLocation

/// Photos waiting for a place that is being saved ("From photos"): the Add
/// Place form saves as usual, and once it announces the new place
/// (PlaceAddedToCircle) these go into that place's photo library through the
/// same uploader the place page uses — re-encoded, so their GPS isn't
/// published. Only a place saved near where the photos were taken, soon,
/// gets them (photos that don't say where: the next place saved): backing out of the form and saving somewhere else later never
/// attaches them by mistake.
final class PendingPlacePhotos {
    static let shared = PendingPlacePhotos()

    struct Attached { let place: Place; let added: Int; let failed: Int }

    private struct Pending {
        let images: [UIImage]
        let near: CLLocationCoordinate2D?
        let expires: Date
        let completion: (Attached) -> Void
    }

    static let matchRadiusMeters: CLLocationDistance = 150
    static let lifetime: TimeInterval = 15 * 60

    private var pending: Pending?
    private var observer: NSObjectProtocol?

    private init() {}

    func expect(_ images: [UIImage], near coordinate: CLLocationCoordinate2D?,
                completion: @escaping (Attached) -> Void = { _ in }) {
        guard !images.isEmpty else { return }
        pending = Pending(images: images, near: coordinate, expires: Date().addingTimeInterval(Self.lifetime), completion: completion)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: Notification.Name("PlaceAddedToCircle"), object: nil, queue: .main) { [weak self] note in
            self?.placeAdded(note.userInfo?["place"] as? Place)
        }
    }

    func cancel() { pending = nil }

    private func placeAdded(_ place: Place?) {
        guard let job = pending, let place else { return }
        guard Date() < job.expires else { pending = nil; return }
        // Photos with no location ride on the next place saved from this flow
        if let near = job.near {
            guard let spot = place.location?.clLocation?.coordinate,
                  PhotoPlaceGrouper.distance(spot, near) <= Self.matchRadiusMeters else { return }
        }
        pending = nil
        PlacePhotoBatchUploader.upload(job.images, to: place, progress: { _, _ in }) { added, failed in
            job.completion(Attached(place: place, added: added.count, failed: failed))
        }
    }
}

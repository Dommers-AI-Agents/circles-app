import CoreLocation
import MapKit
import UIKit

// The steps after the save for a brand-new account (Wes, 2026-11-24): where
// they live, a few first favorites, people to follow, then the app. Every
// step is optional, nothing waits on the install, and what they finish is
// written to the hand-off mailbox after every step and to the server at the
// end, so the app's first run never asks twice.

/// What the steps finished. The app decodes the same JSON (its
/// Models/ClipOnboardingSummary.swift — keep the two in step).
struct ClipOnboardingSummary: Codable {
    enum Step: String, Codable { case neighborhood, favorites, people }

    var zipcodeSet = false
    var city: String? = nil
    var favoritesSaved = 0
    var favoriteNames: [String] = []
    var followed = 0
    var requested = 0
    /// Finished with the step's own button (not Skip)
    var completed: [Step] = []
    /// "Not now": the app may ask on its own screen
    var skipped: [Step] = []
    var finished = false
}

/// One place picked from Apple Maps, as the server's clip/favorites takes it
struct ClipPlacePick: Equatable {
    let key: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let category: String
    let phone: String?
    let website: String?
    let neighborhood: String?
    let applePoiCategory: String?
    let applePlaceId: String?

    static func == (a: ClipPlacePick, b: ClipPlacePick) -> Bool { a.key == b.key }

    init?(_ item: MKMapItem) {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate), !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return nil }
        var appleId: String? = nil
        if #available(iOS 18.0, *) { appleId = item.identifier?.rawValue }
        self.key = appleId ?? "\(name.lowercased())|\(String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude))"
        self.name = name
        let parts = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }
        self.address = parts.isEmpty ? nil : parts.joined(separator: ", ")
        self.coordinate = coordinate
        self.category = Self.category(for: item.pointOfInterestCategory)
        self.phone = item.phoneNumber
        self.website = item.url?.absoluteString
        self.neighborhood = placemark.subLocality
        self.applePoiCategory = item.pointOfInterestCategory?.rawValue
        self.applePlaceId = appleId
    }

    /// Apple's POI category → the app's category ids (config/placeCategories);
    /// the server's derivation refines it from applePoiCategory
    static func category(for poi: MKPointOfInterestCategory?) -> String {
        guard let poi else { return "other" }
        switch poi {
        case .restaurant: return "restaurant"
        case .cafe, .bakery: return "cafe"
        case .foodMarket: return "retail"
        case .brewery, .winery, .nightlife: return "bar"
        case .hotel: return "hotel"
        case .store, .pharmacy: return "retail"
        case .park, .beach, .campground, .marina, .nationalPark: return "outdoor"
        case .fitnessCenter: return "fitness"
        case .museum: return "attraction"
        case .zoo, .aquarium, .amusementPark, .theater, .movieTheater, .stadium: return "entertainment"
        case .hospital: return "healthcare"
        case .school, .university, .library: return "education"
        case .airport, .publicTransport, .parking, .gasStation, .evCharger, .carRental: return "transport"
        case .bank, .atm: return "finance"
        default: return "other"
        }
    }

    var body: [String: Any] {
        var out: [String: Any] = [
            "name": name, "lat": coordinate.latitude, "lng": coordinate.longitude,
            "category": category, "clientSaveId": "clip:\(key)".prefix(64).description
        ]
        if let address { out["address"] = address }
        if let phone { out["phone"] = phone }
        if let website { out["website"] = website }
        if let neighborhood { out["neighborhood"] = neighborhood }
        if let applePoiCategory { out["applePoiCategory"] = applePoiCategory }
        if let applePlaceId { out["applePlaceId"] = applePlaceId }
        return out
    }
}

/// The chain: neighborhood → favorites (when there's somewhere to look
/// around) → people → all set. Owns the summary and writes it out.
@MainActor
final class ClipOnboardingFlow {
    struct Store {
        let name: String
        let coordinate: CLLocationCoordinate2D?
        let awardedPoints: Int
        /// On their map already (the scan saved it, or it was); false when
        /// the save waits for the app
        let saved: Bool
    }

    let session: ClipSession
    let code: String
    /// nil for the generic "Join FavCircles" code
    let store: Store?
    let coverURL: URL?
    private(set) var summary = ClipOnboardingSummary()
    /// Where "near you" looks: the store, else the zip they typed
    var origin: CLLocationCoordinate2D?
    private var recorded = false

    init(session: ClipSession, code: String, preview: VenuePreview, result: ScanResult?) {
        self.session = session
        self.code = code
        if preview.isGeneric {
            store = nil
        } else {
            let lat = result?.venue?.location?.lat ?? preview.location?.latitude
            let lng = result?.venue?.location?.lng ?? preview.location?.longitude
            let coordinate = (lat != nil && lng != nil) ? CLLocationCoordinate2D(latitude: lat!, longitude: lng!) : nil
            store = Store(name: preview.venueName, coordinate: coordinate, awardedPoints: result?.awarded?.points ?? 0,
                          saved: result?.isOnTheirMap == true)
        }
        coverURL = preview.coverUrl.flatMap(URL.init(string:))
        origin = store?.coordinate
    }

    /// Somewhere to look around: the store, or the zip they just gave
    var hasFavoritesStep: Bool { origin != nil }
    /// Always three on the label (the zip step can still produce an origin)
    let stepCount = 3

    func stepNumber(_ step: ClipOnboardingSummary.Step) -> Int {
        switch step {
        case .neighborhood: return 1
        case .favorites: return 2
        case .people: return 3
        }
    }

    /// Mutates the summary and writes it to the mailbox for the app
    func record(_ change: (inout ClipOnboardingSummary) -> Void) {
        change(&summary)
        ClipHandoff.updateOnboarding(summary)
    }

    func complete(_ step: ClipOnboardingSummary.Step) {
        record { s in
            s.skipped.removeAll { $0 == step }
            if !s.completed.contains(step) { s.completed.append(step) }
        }
    }

    func skip(_ step: ClipOnboardingSummary.Step) {
        record { s in
            if !s.completed.contains(step), !s.skipped.contains(step) { s.skipped.append(step) }
        }
    }

    /// The screen after `step` (nil = the first screen)
    func screen(after step: ClipOnboardingSummary.Step?) -> UIViewController {
        switch step {
        case nil: return ClipNeighborhoodViewController(flow: self)
        case .neighborhood?: return hasFavoritesStep ? ClipFavoritesViewController(flow: self) : ClipPeopleViewController(flow: self)
        case .favorites?: return ClipPeopleViewController(flow: self)
        case .people?: return ClipAllSetViewController(flow: self)
        }
    }

    /// The last screen reached: the summary goes to the server once
    func finish() {
        record { $0.finished = true }
        guard !recorded else { return }
        recorded = true
        let body: [String: Any] = [
            "zipcodeSet": summary.zipcodeSet,
            "favoritesSaved": summary.favoritesSaved,
            "followed": summary.followed + summary.requested,
            "skipped": summary.skipped.map(\.rawValue),
            "code": code
        ]
        let token = session.token
        Task { try? await ClipAPIClient.shared.recordOnboarding(body, bearer: token) }
    }
}

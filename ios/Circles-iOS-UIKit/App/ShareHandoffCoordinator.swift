import UIKit
import CoreLocation

/// Finishes a share the Share Extension parked in the App Group mailbox
/// (logged out or offline at share time). Owned by SceneDelegate.
@MainActor
final class ShareHandoffCoordinator: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    // MARK: - Pending Share (from the Share Extension)

    /// A share the extension couldn't finish (logged out or offline at share
    /// time) parks in the App Group mailbox; finish it here by dropping the
    /// user into the normal add-place flow, prefilled from the share.
    func drainPendingShareIfNeeded() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController,
              let pending = PendingShareMailbox.take() else { return }

        if let listURL = pending.googleListURL, !listURL.isEmpty {
            finishPendingGoogleListImport(url: listURL, pending: pending, host: tabBarController)
            return
        }

        let searchSeed = pending.sharedText ?? ""
        var coordinate: CLLocationCoordinate2D?
        if let urlString = pending.sharedURL, ImportParsingService.isGoogleMapsURL(urlString) {
            if let pin = ImportParsingService.pinCoordinates(fromGoogleURL: urlString)
                ?? ImportParsingService.featureCoordinate(fromGoogleURL: urlString) {
                coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
            }
        }
        guard !searchSeed.isEmpty || coordinate != nil else { return }

        CircleService.shared.fetchUserCircles { result in
            DispatchQueue.main.async {
                guard case .success(let circles) = result, !circles.isEmpty else {
                    // Offline relaunch: put the share back so a later launch
                    // gets another chance — the mailbox must not eat shares.
                    PendingShareMailbox.write(pending)
                    return
                }
                let lastUsedId = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey)
                let target = circles.first(where: { $0.id == lastUsedId }) ?? circles[0]
                let addPlaceVC = AddPlaceViewController(circleId: target.id, circles: circles)
                addPlaceVC.circleWasRemembered = target.id == lastUsedId && circles.count > 1
                addPlaceVC.prefillSearchWithPlace(name: searchSeed, coordinate: coordinate)
                if let navController = tabBarController.selectedViewController as? UINavigationController {
                    navController.pushViewController(addPlaceVC, animated: true)
                }
            }
        }
    }

    /// The share extension parked a Google Maps LIST it couldn't import
    /// (offline / logged out at share time). Resolve it here, confirm once,
    /// import it as one circle, and land on that circle. Errors put the share
    /// back so a later launch gets another chance.
    private func finishPendingGoogleListImport(url: String,
                                               pending: PendingShareMailbox.Payload,
                                               host: UIViewController) {
        struct ResolveResponse: Decodable {
            struct List: Decodable {
                struct Place: Decodable {
                    let name: String
                    let address: String?
                    let lat: Double?
                    let lng: Double?
                    let notes: String?
                    let sourceExternalId: String?
                    let sourceUrl: String?
                }
                let id: String
                let name: String
                let description: String?
                let url: String
                let places: [Place]
            }
            let list: List
        }
        struct ExecuteResponse: Decodable {
            struct Item: Decodable {
                let circleId: String?
                let circleName: String?
                let created: Int
                let skippedDuplicates: Int
            }
            let results: [Item]
        }

        APIService.shared.request(
            endpoint: "import/resolve-google-list",
            method: .post,
            body: ["url": url],
            requiresAuth: true
        ) { [weak self] (result: Result<ResolveResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard case .success(let response) = result else {
                    // Keep the share for another launch (offline again, or a
                    // transient Google hiccup); a private list can't be helped.
                    if case .failure(let error) = result {
                        var unrecoverable = false
                        if case .httpError(let code, _) = error, code == 422 || code == 404 { unrecoverable = true }
                        if !unrecoverable { PendingShareMailbox.write(pending) }
                    }
                    return
                }
                let list = response.list
                let count = list.places.count
                guard count > 0 else { return }
                let presenter = host.presentedViewController ?? host
                AlertPresenter.showConfirmation(
                    title: "Save “\(list.name)”?",
                    message: "The Google Maps list you shared has \(count) place\(count == 1 ? "" : "s"). "
                        + "They'll become a new circle with the same name.",
                    confirmTitle: "Save \(count) place\(count == 1 ? "" : "s")",
                    from: presenter
                ) {
                    let places: [[String: Any]] = list.places.map { place in
                        var body: [String: Any] = ["name": place.name]
                        if let address = place.address { body["address"] = address }
                        if let lat = place.lat, let lng = place.lng { body["lat"] = lat; body["lng"] = lng }
                        if let notes = place.notes { body["notes"] = notes }
                        if let id = place.sourceExternalId { body["sourceExternalId"] = id }
                        if let sourceUrl = place.sourceUrl { body["sourceUrl"] = sourceUrl }
                        return body
                    }
                    var listBody: [String: Any] = ["name": list.name, "sourceUrl": list.url, "places": places]
                    if let description = list.description { listBody["description"] = description }
                    APIService.shared.request(
                        endpoint: "import/execute",
                        method: .post,
                        body: ["source": "google_list", "lists": [listBody]],
                        requiresAuth: true
                    ) { [weak self] (result: Result<ExecuteResponse, APIError>) in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch result {
                            case .success(let response):
                                if let circleId = response.results.first?.circleId {
                                    self.host?.deepLinks.navigateToCircle(circleId: circleId)
                                }
                                ImportPhotoQueue.shared.kick()
                            case .failure(let error):
                                AlertPresenter.showError(error, from: presenter)
                            }
                        }
                    }
                }
            }
        }
    }
}

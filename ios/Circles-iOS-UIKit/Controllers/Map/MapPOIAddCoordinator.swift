import UIKit
import MapKit

protocol MapPOIAddCoordinatorDelegate: AnyObject {
    /// The user's already-saved place matching this point of interest, if any.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, existingPlaceNamed name: String, at coordinate: CLLocationCoordinate2D) -> Place?
    /// "View Details" on a point of interest that is already saved.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, didChooseExistingPlace place: Place)
    /// Present AddPlace with the person's circles (none chosen: they pick on
    /// the screen's Circle card); `configure` runs once it's on screen (to
    /// prefill the tapped point of interest).
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, openAddPlaceWith circles: [Circle], configure: @escaping (AddPlaceViewController) -> Void)
}

/// The "tap a map point of interest → add it" flow: the small sheet naming
/// the place, then AddPlace with it prefilled. The circle is chosen on Add
/// Place's Circle card, like Home's Add Place button (Wes, 2026-11-11: "I
/// thought we changed this flow to do it in the add place view").
final class MapPOIAddCoordinator {
    private unowned let presenter: UIViewController
    private unowned let mapView: MKMapView
    weak var delegate: MapPOIAddCoordinatorDelegate?

    init(presenter: UIViewController, mapView: MKMapView) {
        self.presenter = presenter
        self.mapView = mapView
    }

    func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Get POI details
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let poiSubtitle = featureAnnotation.subtitle ?? ""
        let coordinate = featureAnnotation.coordinate

        // Check if this place already exists in the current places
        let isAlreadySaved = delegate?.poiCoordinator(self, existingPlaceNamed: poiName, at: coordinate) != nil

        // Show custom action sheet with options
        let alertController = UIAlertController(
            title: poiName,
            message: isAlreadySaved ? "\(poiSubtitle)\n\n✓ Already saved" : poiSubtitle,
            preferredStyle: .actionSheet
        )

        if !isAlreadySaved {
            // Add Place only if not already saved
            alertController.addAction(UIAlertAction(title: "Add Place", style: .default) { [weak self] _ in
                self?.openAddPlace(for: featureAnnotation)
            })
        } else {
            // Show which circles contain this place
            let viewDetailsAction = UIAlertAction(title: "View Details", style: .default) { [weak self] _ in
                guard let self = self else { return }
                if let existingPlace = self.delegate?.poiCoordinator(self, existingPlaceNamed: poiName, at: coordinate) {
                    self.delegate?.poiCoordinator(self, didChooseExistingPlace: existingPlace)
                }
            }
            alertController.addAction(viewDetailsAction)
        }

        // Cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
        }
        alertController.addAction(cancelAction)

        // For iPad
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = mapView
            let point = mapView.convert(coordinate, toPointTo: mapView)
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 0, height: 0)
        }

        presenter.present(alertController, animated: true)
    }

    /// Add Place with the tapped place filled in; the person's circles go
    /// along so its Circle card can open straight away.
    private func openAddPlace(for featureAnnotation: MKMapFeatureAnnotation) {
        let loading = AlertPresenter.showLoading(message: "Loading your circles…", from: presenter)
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let circles):
                        self.mapView.deselectAnnotation(featureAnnotation, animated: false)
                        self.delegate?.poiCoordinator(self, openAddPlaceWith: circles) { addPlaceVC in
                            addPlaceVC.configureWithPOI(featureAnnotation)
                        }
                    case .failure(let error):
                        self.mapView.deselectAnnotation(featureAnnotation, animated: true)
                        self.presenter.showError(FriendlyError.message(for: error))
                    }
                }
            }
        }
    }
}

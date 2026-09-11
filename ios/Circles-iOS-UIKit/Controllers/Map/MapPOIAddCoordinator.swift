import UIKit
import MapKit

protocol MapPOIAddCoordinatorDelegate: AnyObject {
    /// The user's already-saved place matching this point of interest, if any.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, existingPlaceNamed name: String, at coordinate: CLLocationCoordinate2D) -> Place?
    /// "View Details" on a point of interest that is already saved.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, didChooseExistingPlace place: Place)
}

/// The "tap a map point of interest → add it to a circle" flow: the action
/// sheet, the circle slider picker, the create-a-circle detour, and the
/// hand-off into AddPlace with the POI prefilled. Owns the pending POI
/// while the user is choosing, so the map controller doesn't have to.
final class MapPOIAddCoordinator {
    private unowned let presenter: UIViewController
    private unowned let mapView: MKMapView
    weak var delegate: MapPOIAddCoordinatorDelegate?

    private var pendingPOIAnnotation: Any? // MKMapFeatureAnnotation for iOS 16+
    private var pendingPOINotes: String? // Temporary storage for notes when creating new circle
    private var currentCirclePicker: CirclePickerSliderView? // Reference to current circle picker

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
            // Add to Circle action only if not already saved
            let addToCircleAction = UIAlertAction(title: "Add to Circle", style: .default) { [weak self] _ in
                self?.showCirclePickerForPOI(featureAnnotation)
            }
            alertController.addAction(addToCircleAction)
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

    @available(iOS 16.0, *)
    private func showCirclePickerForPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // First, load user's circles
        let loadingAlert = UIAlertController(title: "Loading", message: "Fetching your circles...", preferredStyle: .alert)
        presenter.present(loadingAlert, animated: true)

        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circles):
                        self?.presentCirclePicker(for: featureAnnotation, circles: circles)
                    case .failure(let error):
                        self?.presenter.showError("Failed to load circles: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private func presentCirclePicker(for featureAnnotation: MKMapFeatureAnnotation, circles: [Circle]) {
        // Store the POI annotation for later use
        pendingPOIAnnotation = featureAnnotation

        // Circles arrive in the user's own order (same as the profile grid).
        // Create and configure the vertical slider picker
        let circlePicker = CirclePickerSliderView()
        circlePicker.delegate = self
        circlePicker.configure(with: circles)

        // Store reference to dismiss later
        currentCirclePicker = circlePicker

        // Show the picker
        if let window = presenter.view.window {
            circlePicker.show(in: window)
        }
    }

    @available(iOS 16.0, *)
    private func createNewCircleForPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Navigate to create circle view controller
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self

        // Store the POI annotation to add after circle creation
        pendingPOIAnnotation = featureAnnotation

        let navController = UINavigationController(rootViewController: createCircleVC)
        presenter.present(navController, animated: true)
    }

    /// Pushes AddPlace for the chosen circle with the pending POI prefilled.
    @available(iOS 16.0, *)
    private func pushAddPlace(circleId: String, for pendingPOI: MKMapFeatureAnnotation) {
        // Dismiss the circle picker if it exists
        currentCirclePicker?.dismiss()
        currentCirclePicker = nil

        // Find the parent navigation controller
        if let navController = presenter.navigationController
            ?? presenter.presentingViewController as? UINavigationController
            ?? presenter.parent?.navigationController {
            let addPlaceVC = AddPlaceViewController(circleId: circleId)
            navController.pushViewController(addPlaceVC, animated: true)

            // Configure with POI data after a brief delay to ensure view is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                addPlaceVC.configureWithPOI(pendingPOI)
            }

            // Clear the pending POI
            pendingPOIAnnotation = nil
            pendingPOINotes = nil
        }
    }
}

// MARK: - CreateCircleDelegate

extension MapPOIAddCoordinator: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        // If we have a pending POI annotation, navigate to AddPlaceViewController
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                pushAddPlace(circleId: circle.id, for: pendingPOI)
            }
        }
    }
}

// MARK: - CirclePickerSliderViewDelegate

extension MapPOIAddCoordinator: CirclePickerSliderViewDelegate {
    func circlePickerDidSelectCircle(_ circle: Circle, notes: String?) {
        // Navigate to AddPlaceViewController with the selected POI
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                pushAddPlace(circleId: circle.id, for: pendingPOI)
            }
        }
    }

    func circlePickerDidSelectCreateNew(notes: String?) {
        // Create a new circle for the POI
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                // Store notes temporarily to use after circle creation
                pendingPOINotes = notes
                createNewCircleForPOI(pendingPOI)
            }
        }
    }

    func circlePickerDidCancel() {
        // Clear the circle picker reference
        currentCirclePicker = nil

        // Deselect the annotation
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                mapView.deselectAnnotation(pendingPOI, animated: true)
                pendingPOIAnnotation = nil
            }
        }
    }
}

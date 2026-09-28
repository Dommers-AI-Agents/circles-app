import UIKit
import MapKit

protocol MapPOIAddCoordinatorDelegate: AnyObject {
    /// The user's already-saved place matching this point of interest, if any.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, existingPlaceNamed name: String, at coordinate: CLLocationCoordinate2D) -> Place?
    /// "View Details" on a point of interest that is already saved.
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, didChooseExistingPlace place: Place)
    /// Present AddPlace for `circleId`; `configure` runs once it's on screen
    /// (to prefill the tapped point of interest).
    func poiCoordinator(_ coordinator: MapPOIAddCoordinator, openAddPlaceIn circleId: String, circles: [Circle]?, configure: @escaping (AddPlaceViewController) -> Void)
}

/// The "tap a map point of interest → add it to a circle" flow: the action
/// sheet, the circle picker sheet, the create-a-circle detour, and the
/// hand-off into AddPlace with the POI prefilled. Owns the pending POI
/// while the user is choosing, so the map controller doesn't have to.
final class MapPOIAddCoordinator {
    private unowned let presenter: UIViewController
    private unowned let mapView: MKMapView
    weak var delegate: MapPOIAddCoordinatorDelegate?

    private var pendingPOIAnnotation: Any? // MKMapFeatureAnnotation for iOS 16+

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
        let loading = AlertPresenter.showLoading(message: "Loading your circles…", from: presenter)

        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
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

    /// The same circle sheet the map's "+" uses, with the tapped place shown
    /// on top. Tapping a circle goes straight to AddPlace, prefilled.
    @available(iOS 16.0, *)
    private func presentCirclePicker(for featureAnnotation: MKMapFeatureAnnotation, circles: [Circle]) {
        // Circles arrive in the user's own order (same as the profile grid).
        let picker = CirclePickerViewController(circles: circles)
        picker.pickerTitle = "Add to a Circle"
        picker.placeName = featureAnnotation.title ?? nil
        picker.placeAddress = featureAnnotation.subtitle ?? nil
        picker.onCircleSelected = { [weak self] circle in
            self?.openAddPlace(circleId: circle.id, circles: circles, poi: featureAnnotation)
        }
        picker.onCreateNewCircle = { [weak self] in
            self?.createNewCircleForPOI(featureAnnotation)
        }

        let nav = UINavigationController(rootViewController: picker)
        nav.presentationController?.delegate = dismissWatcher
        dismissWatcher.onSwipeDismiss = { [weak self] in
            self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            nav.modalPresentationStyle = .formSheet
            nav.preferredContentSize = CGSize(width: 400, height: 600)
        } else {
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        presenter.present(nav, animated: true)
    }

    @available(iOS 16.0, *)
    private func createNewCircleForPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Remember the POI; didCreateCircle picks it back up
        pendingPOIAnnotation = featureAnnotation
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        let navController = UINavigationController(rootViewController: createCircleVC)
        presenter.present(navController, animated: true)
    }

    /// The map opens AddPlace itself (modally, in its own nav controller —
    /// the expanded map has no navigation stack to push onto, which is why
    /// the old push silently did nothing there).
    @available(iOS 16.0, *)
    private func openAddPlace(circleId: String, circles: [Circle]?, poi: MKMapFeatureAnnotation) {
        pendingPOIAnnotation = nil
        mapView.deselectAnnotation(poi, animated: false)
        delegate?.poiCoordinator(self, openAddPlaceIn: circleId, circles: circles) { addPlaceVC in
            addPlaceVC.configureWithPOI(poi)
        }
    }

    private let dismissWatcher = SheetDismissWatcher()
}

/// Deselects the tapped POI when its circle sheet is swiped away.
private final class SheetDismissWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    var onSwipeDismiss: (() -> Void)?
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onSwipeDismiss?()
    }
}

// MARK: - CreateCircleDelegate

extension MapPOIAddCoordinator: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        if #available(iOS 16.0, *) {
            if let pendingPOI = pendingPOIAnnotation as? MKMapFeatureAnnotation {
                // CreateCircle dismisses itself right after this callback;
                // wait for it to clear or the add screen's present is dropped
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.openAddPlace(circleId: circle.id, circles: nil, poi: pendingPOI)
                }
            }
        }
    }
}

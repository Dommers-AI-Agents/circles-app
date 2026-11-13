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

/// The "tap a map point of interest → add it" flow: a card on the place
/// (MapPlaceCalloutView: its icon, name, kind and distance, Add Place and
/// Directions), then AddPlace with it prefilled. The circle is chosen on Add
/// Place's Circle card, like Home's Add Place button (Wes, 2026-11-11).
final class MapPOIAddCoordinator {
    private unowned let presenter: UIViewController
    private unowned let mapView: MKMapView
    weak var delegate: MapPOIAddCoordinatorDelegate?
    private var callout: MapPlaceCalloutView?

    init(presenter: UIViewController, mapView: MKMapView) {
        self.presenter = presenter
        self.mapView = mapView
    }

    func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        dismissCallout(animated: false)
        let name = featureAnnotation.title ?? "This place"
        let coordinate = featureAnnotation.coordinate
        let existing = delegate?.poiCoordinator(self, existingPlaceNamed: name, at: coordinate)

        let card = MapPlaceCalloutView(
            model: .init(feature: featureAnnotation, userLocation: mapView.userLocation.location, isSaved: existing != nil),
            coordinate: coordinate)
        card.onPrimary = { [weak self] in
            guard let self else { return }
            if let existing {
                self.close(featureAnnotation)
                self.delegate?.poiCoordinator(self, didChooseExistingPlace: existing)
            } else {
                self.openAddPlace(for: featureAnnotation)
            }
        }
        card.onDirections = { [weak self] in
            Self.openDirections(to: featureAnnotation)
            self?.close(featureAnnotation)
        }
        card.onClose = { [weak self] in self?.close(featureAnnotation) }
        card.show(on: mapView)
        callout = card
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Keeps the card on its place while the map moves
    func mapDidMove() {
        callout?.reposition()
    }

    /// The place was let go (a tap elsewhere on the map): the card goes too
    func dismissCallout(animated: Bool = true) {
        callout?.dismiss(animated: animated)
        callout = nil
    }

    private func close(_ featureAnnotation: MKMapFeatureAnnotation) {
        dismissCallout()
        mapView.deselectAnnotation(featureAnnotation, animated: true)
    }

    /// Apple Maps directions to the tapped place
    static func openDirections(to feature: MKMapFeatureAnnotation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: feature.coordinate))
        item.name = feature.title ?? nil
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
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
                        self.dismissCallout(animated: false)
                        self.mapView.deselectAnnotation(featureAnnotation, animated: false)
                        self.delegate?.poiCoordinator(self, openAddPlaceWith: circles) { addPlaceVC in
                            addPlaceVC.configureWithPOI(featureAnnotation)
                        }
                    case .failure(let error):
                        self.close(featureAnnotation)
                        self.presenter.showError(FriendlyError.message(for: error))
                    }
                }
            }
        }
    }
}

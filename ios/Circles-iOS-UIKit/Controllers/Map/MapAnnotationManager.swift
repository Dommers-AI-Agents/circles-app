import MapKit

/// Keeps a map's place annotations in step with a place list, and decides
/// which of them get full category pins vs. small dots.
///
/// Updates are differential (only what changed is removed or added), and
/// pin tiering is debounced because region changes and annotation churn
/// both trigger it. The greedy collision pass lives in `PinTierPlanner`;
/// this class does the projection (anchor, screen points, distances).
final class MapAnnotationManager {
    private unowned let mapView: MKMapView
    var maxFullPins = 45
    /// Called after annotations are added when the caller asked for a
    /// region adjustment (or when there was nothing to add but one was asked for).
    var adjustRegion: (() -> Void)?

    /// Place ids currently shown as full pins (the rest render as dots).
    private(set) var promotedPlaceIds = Set<String>()
    private var annotationPlaceMap: [ObjectIdentifier: Place] = [:]
    private var pinTierRecomputeTimer: Timer?

    init(mapView: MKMapView) {
        self.mapView = mapView
    }

    // MARK: - Differential update

    func update(with places: [Place], adjustRegion shouldAdjustRegion: Bool) {
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.debug("🗺️ [SmoothMap] Starting smooth annotation update...")

        // Get places that should be on the map
        let placesWithLocation = places.filter { $0.location?.clLocation != nil }
        let newPlaceIds = Set(placesWithLocation.map { $0.id })

        // Get current annotations and their place IDs
        let currentAnnotations = mapView.annotations.compactMap { $0 as? PlaceAnnotation }
        let currentPlaceIds = Set(currentAnnotations.compactMap { annotationPlaceMap[ObjectIdentifier($0)]?.id })

        // Calculate differences
        let placesToAdd = placesWithLocation.filter { !currentPlaceIds.contains($0.id) }
        let annotationsToRemove = currentAnnotations.filter {
            guard let place = annotationPlaceMap[ObjectIdentifier($0)] else { return true }
            return !newPlaceIds.contains(place.id)
        }

        Logger.debug("🗺️ [SmoothMap] Differential update:")
        Logger.debug("   Current: \(currentAnnotations.count) annotations")
        Logger.debug("   To add: \(placesToAdd.count) places")
        Logger.debug("   To remove: \(annotationsToRemove.count) annotations")

        // Remove obsolete annotations smoothly
        if !annotationsToRemove.isEmpty {
            // Clean up annotation mapping
            for annotation in annotationsToRemove {
                annotationPlaceMap.removeValue(forKey: ObjectIdentifier(annotation))
            }

            // Remove with animation
            mapView.removeAnnotations(annotationsToRemove)
        }

        // Add new annotations in batches for smooth loading
        if !placesToAdd.isEmpty {
            addAnnotationsBatched(placesToAdd, adjustRegion: shouldAdjustRegion)
        } else if shouldAdjustRegion {
            // If no new places to add, just adjust region
            adjustRegion?()
        } else if !annotationsToRemove.isEmpty {
            // Removal-only update (e.g. narrower filter): freed space may let
            // remaining dots promote to full pins
            schedulePinTierRecompute()
        }

        let loadTime = CFAbsoluteTimeGetCurrent() - startTime
        Logger.debug("🗺️ [SmoothMap] Update completed in \(String(format: "%.3f", loadTime))s")
    }

    private func addAnnotationsBatched(_ places: [Place], adjustRegion shouldAdjustRegion: Bool) {
        // Add all annotations in one pass. The previous 15-at-a-time staggering
        // (0.05s between batches + a 0.1s tail) delayed the camera by up to
        // ~0.75s on a filter change — the map felt slow to settle. MapKit
        // handles a bulk add fine, and the zoom can happen immediately after.
        let annotations = places.compactMap { place -> PlaceAnnotation? in
            guard place.location?.clLocation != nil else { return nil }
            let annotation = PlaceAnnotation(place: place)
            annotationPlaceMap[ObjectIdentifier(annotation)] = place
            return annotation
        }

        mapView.addAnnotations(annotations)
        Logger.debug("🗺️ [SmoothMap] Added \(annotations.count) annotations in one pass")

        schedulePinTierRecompute()

        if shouldAdjustRegion {
            adjustRegion?()
        }
    }

    // MARK: - Pin tiering (full pins near the user, dots elsewhere)

    /// Debounced recompute — region changes and annotation churn both land here.
    func schedulePinTierRecompute(delay: TimeInterval = 0.25) {
        pinTierRecomputeTimer?.invalidate()
        pinTierRecomputeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.recomputePinTiers()
        }
    }

    /// Decide which places get full category pins vs. small dots.
    private func recomputePinTiers() {
        let placeAnnotations = mapView.annotations.compactMap { $0 as? PlaceAnnotation }
        guard !placeAnnotations.isEmpty else {
            promotedPlaceIds.removeAll()
            return
        }

        // Anchor: pins should bloom around YOU when you're on screen
        let anchor: CLLocationCoordinate2D
        if let userCoord = mapView.userLocation.location?.coordinate,
           mapView.visibleMapRect.contains(MKMapPoint(userCoord)) {
            anchor = userCoord
        } else {
            anchor = mapView.centerCoordinate
        }
        let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)

        let candidates = placeAnnotations.map { annotation -> PinTierPlanner.Candidate in
            let c = annotation.coordinate
            return PinTierPlanner.Candidate(
                id: annotation.place.id,
                point: mapView.convert(c, toPointTo: mapView),
                distance: anchorLocation.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            )
        }

        // The selected annotation keeps its full pin no matter what —
        // demoting it would yank the callout out from under the user
        let selectedIds = Set(mapView.selectedAnnotations.compactMap { ($0 as? PlaceAnnotation)?.place.id })

        var planner = PinTierPlanner()
        planner.maxFullPins = maxFullPins
        let newPromoted = planner.fullPinIds(for: candidates, in: mapView.bounds, pinned: selectedIds)

        guard newPromoted != promotedPlaceIds else { return }
        let changedIds = newPromoted.symmetricDifference(promotedPlaceIds)
        promotedPlaceIds = newPromoted

        // Changed annotations must re-dequeue for their new tier; remove+add
        // is the reliable way to force that. Skip the selected annotation so
        // its open callout survives.
        let changed = placeAnnotations.filter {
            changedIds.contains($0.place.id) && !selectedIds.contains($0.place.id)
        }
        if !changed.isEmpty {
            mapView.removeAnnotations(changed)
            mapView.addAnnotations(changed)
        }
        Logger.debug("🗺️ [PinTiers] \(newPromoted.count) full pins, \(placeAnnotations.count - newPromoted.count) dots (\(changed.count) retiered)")
    }
}

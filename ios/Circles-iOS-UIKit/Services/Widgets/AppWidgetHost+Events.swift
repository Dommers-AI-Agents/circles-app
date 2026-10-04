import UIKit
import Photos
import MapKit
import FavWidgets
import FavWidgetsCore

/// Host abilities the Events widget (Party Bus) needs: saving an album photo
/// to Photos, and searching any venue to tag (not only saved places).
extension AppWidgetHost {
    func saveImageToPhotos(_ jpeg: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "AppWidgetHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access was declined"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
        }
    }

    func searchPlaces(_ text: String, near: WidgetCoordinate?) async throws -> [WidgetPlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        if let near {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                latitudinalMeters: 8_000, longitudinalMeters: 8_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(25).compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            let mapping = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: name)
            let address = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality]
                .compactMap { $0 }.joined(separator: " ")
            return WidgetPlaceCandidate(
                id: "apple:\(coordinate.latitude),\(coordinate.longitude)",
                name: name,
                address: address.isEmpty ? nil : address,
                coordinate: WidgetCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                category: mapping.category.rawValue,
                source: .mine,
                isGlobal: false
            )
        }
    }
}

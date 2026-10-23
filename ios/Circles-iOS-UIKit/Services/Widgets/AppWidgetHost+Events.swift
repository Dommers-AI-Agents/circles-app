import UIKit
import UserNotifications
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

    /// An event video into the camera roll (widgets 0.44.0)
    func saveVideoToPhotos(_ file: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "AppWidgetHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access was declined"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file, options: nil)
        }
    }

    /// A person's profile over the widget, with Close to come back
    /// (event People list, widgets 0.44.0)
    func openProfile(userId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.presentingViewController else { return }
            let present: (User?) -> Void = { user in
                let profile = ProfileViewController(user: user)
                let navigation = UINavigationController(rootViewController: profile)
                profile.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    systemItem: .close,
                    primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) })
                navigation.modalPresentationStyle = .pageSheet
                presenter.present(navigation, animated: true)
            }
            // Your own row opens your own profile
            if AuthService.shared.isMe(userId) { return present(nil) }
            let loading = AlertPresenter.showLoading(message: "Loading profile...", from: presenter)
            UserService.shared.fetchUserProfile(userId: userId) { result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        switch result {
                        case .success(let user): present(user)
                        case .failure(let error): AlertPresenter.showError(error, from: presenter)
                        }
                    }
                }
            }
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
            // Street, city, state and ZIP, like Add Place: the server matches
            // the venue to Google by it
            let street = [item.placemark.subThoroughfare, item.placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let address = [street, item.placemark.locality, item.placemark.administrativeArea, item.placemark.postalCode]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
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

// MARK: - Notification permission (widgets 0.33.0)

extension AppWidgetHost {
    func notificationPermission() async -> WidgetNotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed // authorized, provisional, ephemeral
        }
    }

    /// The app's own request: also registers for remote pushes and tells the
    /// server, so the coordinator's "can't get notifications" count updates.
    func requestNotificationPermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            NotificationService.shared.requestNotificationPermissions { continuation.resume(returning: $0) }
        }
        NotificationService.shared.reportPushStatus()
        return granted
    }

    func openNotificationSettings() {
        let url = URL(string: UIApplication.openNotificationSettingsURLString) ?? URL(string: UIApplication.openSettingsURLString)
        if let url { UIApplication.shared.open(url) }
    }
}

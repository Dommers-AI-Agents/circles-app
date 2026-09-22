import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// The app's side of the FavWidgets host contract: data sync, analytics,
/// haptics, sharing, alerts, connections, and postcard delivery. One per
/// signed-in user; the Widgets tab owns it.
final class AppWidgetHost: FavWidgetHost {
    /// The Widgets tab; sheets and alerts present from whatever is on
    /// screen above it (a pushed full view, the Manage sheet), resolved at
    /// call time — the tab itself leaves the window while a page is pushed.
    weak var presenter: UIViewController?

    var presentingViewController: UIViewController? {
        guard let presenter else { return nil }
        var top = presenter.navigationController?.visibleViewController ?? presenter
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    let dataStore: WidgetDataStore
    let userId: String

    init(userId: String) {
        self.userId = userId
        dataStore = AppWidgetHost.makeDataStore(userId: userId)
    }

    /// The per-user document cache, in Application Support so iOS doesn't
    /// purge it under storage pressure — it holds edits made offline that
    /// haven't reached the server yet. Every path that writes widget data
    /// (the tab, the water reminder's "Log a cup") must go through this, so
    /// an offline write lands in the same place the tab resumes from.
    static func makeDataStore(userId: String) -> CachedWidgetDataStore {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let directory = support.appendingPathComponent("HomeWidgets", isDirectory: true).appendingPathComponent(userId, isDirectory: true)
        // One-time move from the old Caches location (first build after this change).
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let legacy = caches.appendingPathComponent("HomeWidgets", isDirectory: true).appendingPathComponent(userId, isDirectory: true)
            if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.moveItem(at: legacy, to: directory)
            }
        }
        return CachedWidgetDataStore(wrapping: HomeWidgetsAPIDataStore(), directory: directory)
    }

    var currentUserId: String? { userId }


    /// Places handed to widgets, kept so `openPlace` can push the real
    /// detail page without a refetch. (Used by AppWidgetHost+Places.)
    var placeCache: [String: Place] = [:]

    // MARK: - UI adapters

    func track(_ event: WidgetAnalyticsEvent) {
        AnalyticsService.shared.logEvent(event.name, parameters: event.parameters)
    }

    func haptic(_ kind: WidgetHaptic) {
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    func share(_ items: [WidgetShareItem]) {
        let activityItems: [Any] = items.compactMap { item in
            switch item {
            case .text(let text): return text
            case .url(let url): return url
            case .imageJPEG(let data): return UIImage(data: data)
            }
        }
        guard let presenter = presentingViewController, !activityItems.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }

    func presentAlert(_ alert: WidgetAlert) {
        guard let presenter = presentingViewController else { return }
        AlertPresenter.showInfo(title: alert.title, message: alert.message, from: presenter)
    }

    /// Accepted connections (the `connections` collection — not the legacy
    /// `users/me/friends` array, which is empty for most accounts).
}

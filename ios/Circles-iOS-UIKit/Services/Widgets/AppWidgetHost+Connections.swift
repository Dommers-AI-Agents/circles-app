import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// Connections and the in-app postcard send.
extension AppWidgetHost {
    func fetchConnections() async throws -> [WidgetContact] {
        let users: [User] = try await withCheckedThrowingContinuation { continuation in
            NetworkManager.shared.getConnections { result in
                continuation.resume(with: result)
            }
        }
        return users.map { user in
            WidgetContact(id: user.id, displayName: user.displayName,
                          avatarURL: user.profilePicture.flatMap { URL(string: $0) })
        }
    }

    func sendPostcard(_ postcard: WidgetPostcardSend) async throws -> WidgetPostcardReceipt {
        try await HomeWidgetsPostcardSender.send(postcard)
    }

    /// Not wired in v1; the hook exists so bill split / postcard can pick up
    /// the current venue once visit detection exposes it.
    func nearbyOrCurrentPlace() async -> WidgetPlaceRef? { nil }
}

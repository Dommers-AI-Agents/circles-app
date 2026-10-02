import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// Account preferences the widgets may read.
extension AppWidgetHost {
    var quietHours: WidgetQuietHours? { Self.accountQuietHours }

    /// Also read outside a widget screen (re-planning local reminders).
    static var accountQuietHours: WidgetQuietHours? {
        guard let prefs = AuthService.shared.currentUser?.notificationPreferences, prefs.quietHoursEnabled else { return nil }
        return WidgetQuietHours(start: prefs.quietHoursStart, end: prefs.quietHoursEnd)
    }
}

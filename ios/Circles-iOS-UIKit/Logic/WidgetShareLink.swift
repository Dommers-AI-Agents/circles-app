import Foundation

/// The link a widget's share button hands out.
///
/// One shape, two outcomes: the app is registered for `api.favcircles.com/app/*`
/// (AASA), so a device with FavCircles installed opens straight onto the
/// widget's page; a device without it lands on the backend's page, which sends
/// it to the App Store. That fallback is the whole point — these links are
/// shared with people who mostly don't have the app yet.
///
/// Deliberately NOT `favcircles.com`: that host is claimed for passkeys only,
/// and adding an `applinks:` entry there means a new provisioning profile.
/// `api.favcircles.com` is already an associated domain, so this needs no
/// entitlement change at all.
enum WidgetShareLink {
    static let host = "api.favcircles.com"

    /// nil for an id that can't sit in a path — nothing shippable produces one,
    /// but a share button must never hand out a broken URL.
    static func url(widgetId: String) -> URL? {
        let trimmed = widgetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: allowed.inverted) == nil else { return nil }
        return URL(string: "https://\(host)/app/widget/\(trimmed)")
    }

    /// What rides above the link in the share sheet. The title carries the
    /// widget; the subtitle says why anyone would want it.
    static func message(title: String, subtitle: String) -> String {
        let blurb = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return blurb.isEmpty ? "\(title) on FavCircles" : "\(title) on FavCircles — \(blurb)"
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
}

import UIKit

/// Nudges people who have never set a real profile photo.
///
/// A face is what makes a follow feel like a person rather than a row, so this
/// is worth asking about — but only occasionally. Rules, in order:
///
///   • never more than once a week
///   • never for someone who already has a real photo (a Google-generated
///     monogram is not a photo — see `User.hasRealProfilePhoto`)
///   • never in the first days of an account, when the app is already asking
///     for a lot
///   • stops asking for good after a few declines; someone who has said "not
///     now" three times has answered.
enum ProfilePhotoReminder {

    private static let lastShownKey = "profilePhotoReminderLastShown"
    private static let declineCountKey = "profilePhotoReminderDeclines"

    private static let minimumInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Don't ask until the account is a few days old — new users are already
    /// being walked through circles, places and permissions.
    private static let minimumAccountAge: TimeInterval = 3 * 24 * 60 * 60
    private static let maximumDeclines = 3

    static func shouldShow(for user: User?) -> Bool {
        guard let user = user, !user.hasRealProfilePhoto else { return false }

        let defaults = UserDefaults.standard
        if defaults.integer(forKey: declineCountKey) >= maximumDeclines { return false }

        if let last = defaults.object(forKey: lastShownKey) as? Date,
           Date().timeIntervalSince(last) < minimumInterval {
            return false
        }

        if let created = user.createdAt,
           Date().timeIntervalSince(created) < minimumAccountAge {
            return false
        }

        return true
    }

    /// Presents the nudge if it's due. Safe to call on every appearance —
    /// the gating lives here, not at the call site.
    static func presentIfDue(from viewController: UIViewController,
                             user: User?,
                             onAddPhoto: @escaping () -> Void) {
        guard shouldShow(for: user) else { return }
        UserDefaults.standard.set(Date(), forKey: lastShownKey)

        AlertPresenter.showConfirmation(
            title: "Add a profile picture?",
            message: "Upload a photo or pick an avatar — we'll take you there.",
            confirmTitle: "Sure",
            cancelTitle: "Not Now",
            from: viewController,
            onConfirm: {
                // Answering the prompt resets the patience counter — this
                // person engages with it, so a future ask is fair.
                UserDefaults.standard.set(0, forKey: declineCountKey)
                onAddPhoto()
            },
            onCancel: {
                let defaults = UserDefaults.standard
                defaults.set(defaults.integer(forKey: declineCountKey) + 1, forKey: declineCountKey)
            }
        )
    }

    /// Called after a photo is set, so a later photo removal starts the
    /// schedule fresh rather than inheriting old declines.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: lastShownKey)
        UserDefaults.standard.set(0, forKey: declineCountKey)
    }
}

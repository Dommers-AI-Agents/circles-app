import UIKit

/// The account's notification mode ("Stores I follow only" or everything)
/// and the one-time "friends too?" questions (Logic/NotificationScope).
/// Kept on the server (notificationPreferences.mode / moreAsked) so it
/// survives a reinstall; mirrored on the device so a change shows at once.
final class NotificationScopeStore {
    static let shared = NotificationScopeStore()
    private init() {}

    private var userId: String? { AuthService.shared.currentUser?.id }
    private func key(_ name: String) -> String? { userId.map { "notificationScope.\(name).\($0)" } }

    var mode: NotificationScope.Mode {
        if let key = key("mode"), let raw = UserDefaults.standard.string(forKey: key) {
            return NotificationScope.Mode(raw: raw)
        }
        return NotificationScope.Mode(raw: AuthService.shared.currentUser?.notificationPreferences?.mode)
    }

    private var asked: Set<String> {
        var set = Set((AuthService.shared.currentUser?.notificationPreferences?.moreAsked ?? [:]).filter { $0.value }.keys)
        if let key = key("asked") { set.formUnion(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        return set
    }

    /// Records what the server said (Settings loads the whole map)
    func adopt(_ preferences: NotificationPreferences) {
        guard let key = key("mode") else { return }
        UserDefaults.standard.set(preferences.mode, forKey: key)
        if let askedKey = self.key("asked") {
            let fromServer = preferences.moreAsked.filter { $0.value }.map(\.key)
            let local = UserDefaults.standard.stringArray(forKey: askedKey) ?? []
            UserDefaults.standard.set(Array(Set(local + fromServer)), forKey: askedKey)
        }
    }

    func setMode(_ mode: NotificationScope.Mode, completion: ((Bool) -> Void)? = nil) {
        if let key = key("mode") { UserDefaults.standard.set(mode.rawValue, forKey: key) }
        UserService.shared.updateNotificationPreferenceFields(["mode": mode.rawValue]) { result in
            DispatchQueue.main.async { completion?((try? result.get()) != nil) }
        }
    }

    private func markAsked(_ moment: NotificationScope.Moment) {
        if let key = key("asked") {
            var list = UserDefaults.standard.stringArray(forKey: key) ?? []
            if !list.contains(moment.rawValue) { list.append(moment.rawValue) }
            UserDefaults.standard.set(list, forKey: key)
        }
        UserService.shared.updateNotificationPreferenceFields(["moreAsked": [moment.rawValue: true]])
    }

    /// The tour's notification step answered the question (2026-11-26)
    func recordTourAnswer(everything: Bool) {
        markAsked(.tour)
        if everything { setMode(.all) }
    }

    func shouldAsk(_ moment: NotificationScope.Moment) -> Bool {
        NotificationScope.shouldAsk(mode: mode, asked: asked, moment: moment)
    }

    /// Someone in "Stores I follow only" reached a moment where friends
    /// matter: ask once (when nothing else is on screen). Yes = everything.
    func consider(_ moment: NotificationScope.Moment, name: String? = nil) {
        guard shouldAsk(moment) else { return }
        markAsked(moment)
        present(NotificationScope.ask(moment, name: name), attempt: 0)
    }

    private func present(_ ask: NotificationScope.Ask, attempt: Int) {
        // Never over another alert or sheet (a "Request sent" alert, a tour
        // bubble's screen): wait for a clear screen, up to half a minute
        guard let top = Self.topViewController(), !(top is UIAlertController),
              !OnboardingManager.shared.isFirstSessionFlowActive else {
            guard attempt < 30 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.present(ask, attempt: attempt + 1) }
            return
        }
        AlertPresenter.showConfirmation(title: ask.title, message: ask.message,
                                        confirmTitle: ask.yes, cancelTitle: ask.no,
                                        from: top, onConfirm: { [weak self] in self?.setMode(.all) })
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

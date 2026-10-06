import CoreLocation
import UIKit

/// Asks for "Always" location for a feature someone just switched on (the
/// arrival check-in reminders), and reports whether they have it.
///
/// iOS shows the "Change to Always Allow?" prompt at most once per install;
/// after that the request does nothing at all, so a request that doesn't
/// take the app inactive within a moment means "no prompt is coming" and the
/// caller sends them to Settings instead (Wes, 2026-10-05).
final class AlwaysLocationRequester: NSObject, CLLocationManagerDelegate {
    static let shared = AlwaysLocationRequester()

    private let manager = CLLocationManager()
    private var completion: ((Bool) -> Void)?
    private var promptShown = false

    var hasAlways: Bool { manager.authorizationStatus == .authorizedAlways }

    /// Completion on main, once: true when the app ends up with Always.
    func request(completion: @escaping (Bool) -> Void) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways { return completion(true) }
        if status == .denied || status == .restricted { return completion(false) }
        finish(false)   // a request still waiting is answered first
        self.completion = completion
        promptShown = false
        manager.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(resignedActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        manager.requestAlwaysAuthorization()
        // No prompt within 1.5 s: iOS has already used its one ask
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.promptShown else { return }
            self.finish(self.hasAlways)
        }
    }

    @objc private func resignedActive() { promptShown = true }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        let status = manager.authorizationStatus
        // While the prompt is up the status can still read the old value
        if status == .notDetermined { return }
        if promptShown || status == .authorizedAlways || status == .denied { finish(status == .authorizedAlways) }
    }

    private func finish(_ granted: Bool) {
        guard let completion else { return }
        self.completion = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        DispatchQueue.main.async { completion(granted) }
    }
}

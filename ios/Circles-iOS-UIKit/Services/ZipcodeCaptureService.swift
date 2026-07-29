import UIKit
import CoreLocation

/// Fills in a missing zipcode for people who never saw the registration form.
///
/// The zipcode field lives on `RegisterViewController`, where it's required and
/// validated — but signing in with Google, Apple or Facebook skips that screen
/// entirely, so those accounts arrive with nothing. In practice that's most of
/// them: 46% of email sign-ups have a zipcode versus 5% of social sign-ups.
///
/// It matters because a person's location is the second-strongest signal the
/// suggestion engine has (after places you've both saved), and it's the only
/// one that works for somebody who hasn't saved anything yet.
///
/// The order here is deliberate: derive it silently if we already have
/// permission to, and only ask if we can't. Nobody should be made to type
/// something the device already knows.
final class ZipcodeCaptureService: NSObject {

    static let shared = ZipcodeCaptureService()

    /// Set once we've asked in this launch, so a tab switch can't re-prompt.
    private var hasRunThisSession = false

    /// Remembers a "Not now" so the prompt backs off instead of nagging. Asking
    /// on every launch is how a reasonable request becomes an annoying one.
    private let deferredUntilKey = "zipcodePromptDeferredUntil"
    private let deferralInterval: TimeInterval = 7 * 24 * 60 * 60

    private let locationManager = CLLocationManager()
    private var pendingCompletion: ((String?) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Entry point

    /// Call once the app is showing signed-in content. Does nothing at all when
    /// a zipcode is already known, which is the common case.
    func captureIfNeeded(from viewController: UIViewController) {
        guard !hasRunThisSession else { return }

        // Only latch the flag once there's actually a user to inspect. Setting
        // it earlier means a call that lands before the profile has loaded
        // burns the one attempt this session and we never ask at all.
        guard let user = AuthService.shared.currentUser else { return }
        hasRunThisSession = true

        guard (user.zipcode ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Already granted location? Then we can work it out without asking.
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            deriveFromLocation { [weak self] zipcode in
                guard let self = self else { return }
                if let zipcode = zipcode {
                    self.save(zipcode, source: "location")
                } else {
                    self.promptIfNotDeferred(from: viewController)
                }
            }
            return
        }

        promptIfNotDeferred(from: viewController)
    }

    // MARK: - Silent derivation

    private func deriveFromLocation(completion: @escaping (String?) -> Void) {
        pendingCompletion = completion
        locationManager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                Logger.debug("Zipcode reverse geocode failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            completion(placemarks?.first?.postalCode)
        }
    }

    // MARK: - Prompt

    private func promptIfNotDeferred(from viewController: UIViewController) {
        if let deferredUntil = UserDefaults.standard.object(forKey: deferredUntilKey) as? Date,
           deferredUntil > Date() {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.prompt(from: viewController)
        }
    }

    private func prompt(from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "Where are you based?",
            message: "Your zipcode is used to show you places and people nearby. It's never shown on your profile.",
            preferredStyle: .alert
        )

        alert.addTextField { field in
            field.placeholder = "5-digit zipcode"
            field.keyboardType = .numberPad
            field.textContentType = .postalCode
        }

        alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { [weak self] _ in
            guard let self = self else { return }
            UserDefaults.standard.set(
                Date().addingTimeInterval(self.deferralInterval),
                forKey: self.deferredUntilKey
            )
        })

        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let entered = alert?.textFields?.first?.text ?? ""
            guard self.isValid(entered) else {
                // Re-ask rather than silently discarding what they typed.
                self.prompt(from: viewController)
                return
            }
            self.save(entered, source: "prompt")
        })

        viewController.present(alert, animated: true)
    }

    private func isValid(_ zipcode: String) -> Bool {
        let trimmed = zipcode.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 5 && trimmed.allSatisfy { $0.isNumber }
    }

    // MARK: - Persistence

    private func save(_ zipcode: String, source: String) {
        guard isValid(zipcode) else { return }

        UserService.shared.updateUserProfile(zipcode: zipcode) { result in
            switch result {
            case .success:
                Logger.debug("✅ Zipcode captured via \(source)")
                // Clear any standing deferral — the question is answered.
                UserDefaults.standard.removeObject(forKey: "zipcodePromptDeferredUntil")
            case .failure(let error):
                Logger.debug("❌ Failed to save zipcode: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ZipcodeCaptureService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let completion = pendingCompletion else { return }
        pendingCompletion = nil
        reverseGeocode(location, completion: completion)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Zipcode capture location failed: \(error.localizedDescription)")
        pendingCompletion?(nil)
        pendingCompletion = nil
    }
}

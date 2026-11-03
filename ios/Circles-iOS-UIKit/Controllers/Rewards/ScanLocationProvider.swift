import UIKit
import CoreLocation

/// Where the phone is for a register scan (Wes, 2026-11-02): the store's
/// Activity marks scans from far away or with location off. It never costs
/// the customer the points (2026-11-03) — the owner reviews them instead.
///
/// Not asked yet → one plain-words alert, then iOS's own prompt (where
/// "Allow Once" is fine). Denied → no fix, `locationOff`. A fix older than
/// ten minutes isn't sent: a stale one from home would turn a regular away.
final class ScanLocationProvider: NSObject, CLLocationManagerDelegate {

    struct Result {
        let location: CLLocation?
        let locationOff: Bool
    }

    static let shared = ScanLocationProvider()
    static let maxFixAge: TimeInterval = 10 * 60

    private let manager = CLLocationManager()
    private var waitingForAnswer: (() -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
    }

    func locate(from presenter: UIViewController?, completion: @escaping (Result) -> Void) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            fix(completion)
        case .notDetermined:
            guard let presenter else { completion(Result(location: nil, locationOff: false)); return }
            AlertPresenter.showConfirmation(
                title: "Check you're at the store?",
                message: "FavCircles checks your phone is at the store when you scan, so points stay fair. Your location isn't shared with the store. \u{201C}Allow Once\u{201D} is fine.",
                confirmTitle: "Continue",
                cancelTitle: "Not now",
                from: presenter,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.waitingForAnswer = { [weak self] in
                        guard let self else { return }
                        let status = self.manager.authorizationStatus
                        if status == .authorizedWhenInUse || status == .authorizedAlways {
                            self.fix(completion)
                        } else {
                            completion(Result(location: nil, locationOff: true))
                        }
                    }
                    self.manager.requestWhenInUseAuthorization()
                },
                onCancel: { completion(Result(location: nil, locationOff: true)) }
            )
        default:
            completion(Result(location: nil, locationOff: true))
        }
    }

    private func fix(_ completion: @escaping (Result) -> Void) {
        // A fix from the last two minutes straight away, else a fresh one (3 s cap)
        LocationService.shared.recentLocation(maxAge: 120, timeout: 3) { location in
            let fresh = location.flatMap { -$0.timestamp.timeIntervalSinceNow <= Self.maxFixAge ? $0 : nil }
            DispatchQueue.main.async { completion(Result(location: fresh, locationOff: false)) }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let waiting = waitingForAnswer else { return }
        waitingForAnswer = nil
        DispatchQueue.main.async { waiting() }
    }
}

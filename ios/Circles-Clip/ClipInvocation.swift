import AppClip
import CoreLocation
import Foundation

// What launched the clip: the store code, and Apple's activation payload
// from the scan, which can confirm the phone is at the store without a
// location prompt (NSAppClipRequestLocationConfirmation).
struct ClipInvocation {
    let code: String?
    let payload: APActivationPayload?

    /// true = Apple confirmed the phone is at the store, false = Apple says
    /// it isn't, nil = it couldn't tell (no payload, no store location,
    /// location off, timed out). Only `false` ever costs the customer points.
    func confirmAtStore(latitude: Double?, longitude: Double?) async -> Bool? {
        guard let payload, let latitude, let longitude else { return nil }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                      radius: 300, // Apple allows up to 500 m
                                      identifier: "store")
        return await withCheckedContinuation { continuation in
            let once = ClipOnce()
            // Never hold up the scan for long
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if once.claim() { continuation.resume(returning: nil) }
            }
            payload.confirmAcquired(in: region) { inRegion, error in
                guard once.claim() else { return }
                if let error = error as? APActivationPayloadError,
                   error.code == .doesNotMatch {
                    // The payload wasn't from a physical code (a link): can't tell
                    continuation.resume(returning: nil)
                } else if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: inRegion)
                }
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever of two callers wins
final class ClipOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

#if DEBUG
import UIKit

/// Debug builds only: walks the clip for a simulator run or a screenshot
/// without a finger (2026-11-24). `CLIP_AUTOPILOT_EMAIL=<email>` signs in
/// with that email on the offer screen and takes each step as a person
/// would: yes to the neighborhood (or `CLIP_AUTOPILOT_ZIP`, default 28207),
/// the first two nearby places, no follows (a test account must never
/// follow real people), then the last screen. Each screen calls `ready`
/// when it has something to act on.
@MainActor
final class ClipAutopilot {
    static let shared: ClipAutopilot? = ProcessInfo.processInfo.environment["CLIP_AUTOPILOT_EMAIL"].map(ClipAutopilot.init)

    let email: String
    var zip: String { ProcessInfo.processInfo.environment["CLIP_AUTOPILOT_ZIP"] ?? "28207" }
    private var acted = Set<ObjectIdentifier>()

    init(email: String) { self.email = email }

    func ready(_ screen: UIViewController) {
        guard acted.insert(ObjectIdentifier(screen)).inserted else { return }
        let delay = TimeInterval(ProcessInfo.processInfo.environment["CLIP_AUTOPILOT_DELAY"] ?? "") ?? 1.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak screen] in
            guard let screen else { return }
            switch screen {
            case let welcome as ClipStoreWelcomeViewController: welcome.saveTapped()
            case let offer as ClipOfferViewController: offer.autopilotSignIn(email: self.email)
            case let success as ClipSuccessViewController: success.autopilotKeepGoing()
            case let step as ClipNeighborhoodViewController: step.autopilotAnswer(zip: self.zip)
            case let step as ClipFavoritesViewController: step.autopilotPick()
            case let step as ClipPeopleViewController: step.primaryTapped()
            default: break
            }
        }
    }
}
#endif

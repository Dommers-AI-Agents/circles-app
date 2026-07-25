import UIKit

/// A place-count achievement tier. Users earn badges as their saved-place
/// count grows; the current badge shows next to their name on their profile.
struct PlaceMilestone: Equatable {
    let threshold: Int
    let name: String
    let iconName: String
    let color: UIColor
}

enum PlaceMilestones {

    /// Ascending tiers. The profile badge always reflects the highest tier at
    /// or below the user's current place count; celebrations fire once per tier.
    static let all: [PlaceMilestone] = [
        PlaceMilestone(threshold: 5, name: "Explorer", iconName: "mappin.circle.fill", color: .systemTeal),
        PlaceMilestone(threshold: 10, name: "Adventurer", iconName: "map.fill", color: .systemGreen),
        PlaceMilestone(threshold: 20, name: "Pathfinder", iconName: "signpost.right.fill", color: .systemBlue),
        PlaceMilestone(threshold: 50, name: "Trailblazer", iconName: "flame.fill", color: .systemOrange),
        PlaceMilestone(threshold: 100, name: "Globetrotter", iconName: "globe.americas.fill", color: .systemIndigo),
        PlaceMilestone(threshold: 200, name: "Voyager", iconName: "airplane", color: .systemPurple),
        PlaceMilestone(threshold: 500, name: "Legend", iconName: "star.circle.fill", color: .systemPink),
        PlaceMilestone(threshold: 1000, name: "Cartographer", iconName: "crown.fill", color: .systemYellow)
    ]

    /// The badge earned at `count` places (nil below the first tier)
    static func badge(for count: Int) -> PlaceMilestone? {
        return all.last { count >= $0.threshold }
    }

    /// Per-account so switching users on one device doesn't suppress (or
    /// replay) another account's celebrations
    private static var celebratedKey: String {
        "highestCelebratedPlaceMilestone_\(AuthService.shared.getUserId() ?? "anonymous")"
    }

    /// Presents a one-time celebration when `totalPlaces` reaches a tier the
    /// user hasn't been congratulated for yet. Bulk jumps (e.g. imports)
    /// celebrate only the highest newly reached tier.
    static func celebrateIfNeeded(totalPlaces: Int?) {
        guard let totalPlaces = totalPlaces,
              let reached = badge(for: totalPlaces) else { return }
        let key = celebratedKey
        let celebrated = UserDefaults.standard.integer(forKey: key)
        guard reached.threshold > celebrated else { return }
        UserDefaults.standard.set(reached.threshold, forKey: key)

        // Give the add-place flow a beat to finish dismissing its own UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let presenter = topViewController() else { return }
            let celebrationVC = MilestoneCelebrationViewController(milestone: reached)
            celebrationVC.modalPresentationStyle = .overFullScreen
            celebrationVC.modalTransitionStyle = .crossDissolve
            presenter.present(celebrationVC, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

import Foundation
import WidgetKit

/// Keeps the home-screen widget fed: pulls the freshest network activity
/// (friends' recent saves) plus the FavCoin balance, writes the snapshot to
/// the App Group container, and pokes WidgetKit to re-render.
///
/// Refresh points: post-launch side effects and app backgrounding — the widget
/// shows what the user last saw, which is the honest contract for a
/// snapshot-driven widget (no background networking in the widget process).
final class WidgetSnapshotService {

    static let shared = WidgetSnapshotService()
    private init() {}

    private var isRefreshing = false

    func refresh() {
        guard AuthService.shared.isLoggedIn else { return }
        guard !isRefreshing else { return }
        isRefreshing = true

        var entries: [WidgetSnapshot.Entry] = []
        var coins: Double?
        let group = DispatchGroup()

        group.enter()
        ActivityService.shared.getNetworkActivities(limit: 20) { result in
            if case .success(let response) = result {
                entries = response.activities
                    .filter { $0.type == .placeAdded || $0.type == .checkIn }
                    .prefix(6)
                    .map { activity in
                        var subtitleParts: [String] = []
                        if let actorName = activity.actor?.displayName, !actorName.isEmpty {
                            subtitleParts.append(actorName)
                        }
                        if let circleName = activity.circleName, !circleName.isEmpty {
                            subtitleParts.append(circleName)
                        }
                        return WidgetSnapshot.Entry(
                            placeId: activity.targetType == "place" ? activity.targetId : nil,
                            title: activity.targetName,
                            subtitle: subtitleParts.joined(separator: " · "),
                            timestamp: activity.timestamp
                        )
                    }
            }
            group.leave()
        }

        group.enter()
        PiggyBankAPIService.shared.getPiggyBank { result in
            if case .success(let response) = result {
                let bank = response.bank
                coins = bank.confirmedCoins + bank.pendingCoins + bank.settledOnChain
            }
            group.leave()
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            self?.isRefreshing = false
            WidgetSnapshotStore.save(WidgetSnapshot(
                generatedAt: Date(),
                entries: entries,
                coinBalance: coins
            ))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func clearOnLogout() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation

/// The launch snapshot's refresh finishes after user + circles plus a short
/// grace period; whatever else hasn't arrived by then used to be saved as
/// EMPTY, so the next cold start painted no people, feed or moments and
/// waited on the network (Wes, 2026-10-02). A part that didn't arrive keeps
/// the previous snapshot's value instead — a refresh never replaces cached
/// data with nothing. A part that arrived empty is real and is kept empty.
enum LaunchSnapshotMerge {
    enum Part: Hashable, CaseIterable {
        case networkCircles, connections, activities, moments
    }

    static func merge(fresh: PreloadedData, arrived: Set<Part>, previous: PreloadedData?) -> PreloadedData {
        guard let previous else { return fresh }
        func pick<T>(_ part: Part, _ new: [T], _ old: [T]) -> [T] { choose(part, fresh: new, previous: old, arrived: arrived) }
        return PreloadedData(
            user: fresh.user ?? previous.user,
            circles: fresh.circles,
            networkCircles: pick(.networkCircles, fresh.networkCircles, previous.networkCircles),
            allPlaces: fresh.allPlaces,
            connections: pick(.connections, fresh.connections, previous.connections),
            unreadMessageCount: fresh.unreadMessageCount,
            pendingConnectionCount: fresh.pendingConnectionCount,
            activities: pick(.activities, fresh.activities, previous.activities),
            moments: pick(.moments, fresh.moments, previous.moments)
        )
    }

    /// The rule for one part, on its own so it's testable without model fixtures.
    static func choose<T>(_ part: Part, fresh: [T], previous: [T], arrived: Set<Part>) -> [T] {
        arrived.contains(part) ? fresh : previous
    }
}

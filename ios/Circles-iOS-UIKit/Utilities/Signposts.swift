import Foundation
import OSLog

/// Instruments markers for the home map and search, so "the map lags" can be
/// measured (Instruments → os_signpost, subsystem com.favcircles.circles)
/// instead of guessed. Zero cost when nothing is recording.
struct Signposts {
    static let map = Signposts(category: "map")
    static let search = Signposts(category: "search")

    /// An open interval; hand it back to `end`.
    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
    }

    private let signposter: OSSignposter

    private init(category: String) {
        signposter = OSSignposter(subsystem: "com.favcircles.circles", category: category)
    }

    func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name))
    }

    func end(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
    }

    func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let interval = begin(name)
        defer { end(interval) }
        return body()
    }
}

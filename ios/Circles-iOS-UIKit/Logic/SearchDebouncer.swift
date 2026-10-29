import Foundation

/// One debounce for a search field, shared by every screen that searches as
/// you type.
///
/// Each keystroke starts a new *generation*; work scheduled for an older
/// generation never runs, and answers that come back for one are recognised
/// as stale by `isCurrent(_:)` — instead of every completion re-reading the
/// search bar and comparing text (the home search did that in five places,
/// and the add-place, map and people screens each had their own timer).
final class SearchDebouncer {
    /// Server lookups wait for this many characters: one letter matches half
    /// the catalog and costs a request per channel.
    static let minimumServerQueryLength = 2

    /// Runs `work` after `delay` on the main queue unless cancelled.
    typealias Scheduler = (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void

    let delay: TimeInterval
    private let scheduler: Scheduler
    private var pending: DispatchWorkItem?
    private(set) var generation = 0

    init(delay: TimeInterval = 0.3,
         scheduler: @escaping Scheduler = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }) {
        self.delay = delay
        self.scheduler = scheduler
    }

    /// Starts a new generation and schedules `work` for it, replacing anything
    /// still waiting. Returns the generation.
    @discardableResult
    func schedule(_ work: @escaping (_ generation: Int) -> Void) -> Int {
        pending?.cancel()
        generation += 1
        let current = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            work(current)
        }
        pending = item
        scheduler(delay, item)
        return current
    }

    /// Ends the current generation: waiting work never runs and in-flight
    /// answers become stale.
    func cancel() {
        pending?.cancel()
        pending = nil
        generation += 1
    }

    /// Is an answer for `generation` still the one on screen's business?
    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

    /// Does `query` deserve a server round trip?
    static func isServerEligible(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumServerQueryLength
    }
}

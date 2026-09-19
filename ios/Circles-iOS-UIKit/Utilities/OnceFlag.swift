import Foundation

/// Thread-safe "first caller wins" flag for one-shot callbacks.
final class OnceFlag {
    private let lock = NSLock()
    private var claimed = false
    /// True exactly once.
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

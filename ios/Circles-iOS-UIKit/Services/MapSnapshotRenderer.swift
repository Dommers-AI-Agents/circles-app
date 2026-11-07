import MapKit
import UIKit

/// Every map and Look Around snapshot goes through here (2026-11-07: the app
/// crashed saving Babaloo right after picking Fresh Monkee). A snapshot's
/// task was cancelled when the selection changed, MapKit's renderer was
/// dropped mid-draw, and its graphics buffers were freed while still in use —
/// a debug build aborts on that, a release build leaks. So: one snapshot at a
/// time, and each one is held until MapKit says it's done, whatever happens
/// to whoever asked.
@MainActor
final class MapSnapshotRenderer {
    static let shared = MapSnapshotRenderer()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Snapshotters still drawing
    private var inFlight: [AnyObject] = []

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private func hold(_ object: AnyObject) { inFlight.append(object) }
    private func drop(_ object: AnyObject) { inFlight.removeAll { $0 === object } }

    /// A map picture; nil when MapKit couldn't draw one (no connection)
    func map(_ options: MKMapSnapshotter.Options) async -> MKMapSnapshotter.Snapshot? {
        await acquire()
        let snapshotter = MKMapSnapshotter(options: options)
        hold(snapshotter)
        // The completion-handler form: a cancelled caller can't cut it short
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in continuation.resume(returning: snapshot) }
        }
        drop(snapshotter)
        release()
        return snapshot
    }

    /// A Look Around picture of a scene
    func lookAround(_ scene: MKLookAroundScene, options: MKLookAroundSnapshotter.Options) async throws -> UIImage {
        await acquire()
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        hold(snapshotter)
        defer {
            drop(snapshotter)
            release()
        }
        // Its own task: cancelling the caller's task can't cut the draw short
        let drawing = Task { @MainActor in try await snapshotter.snapshot.image }
        return try await drawing.value
    }
}

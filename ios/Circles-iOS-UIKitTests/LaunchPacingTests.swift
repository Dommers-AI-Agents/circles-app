import Foundation
import Testing
@testable import Circles_iOS

/// Deferred launch work always runs: a fixed timer, never a condition
@MainActor
struct LaunchPacingTests {
    @Test func workAfterTheWindowRunsRightAway() async throws {
        var ran = false
        LaunchPacing.afterLaunch(0) { ran = true }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(ran)
    }

    @Test func workInsideTheWindowRunsWhenItEnds() async throws {
        var ran = false
        let window = Date().timeIntervalSince(LaunchPacing.launchedAt) + 0.3
        LaunchPacing.afterLaunch(window) { ran = true }
        #expect(!ran)
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(ran)
    }
}

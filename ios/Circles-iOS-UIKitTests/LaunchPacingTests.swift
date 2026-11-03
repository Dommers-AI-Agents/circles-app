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

/// A whole-account rescan runs at most once per interval, per account
struct PeriodicPassTests {
    @Test func dueOncePerIntervalPerAccount() {
        let defaults = UserDefaults(suiteName: "PeriodicPassTests.\(UUID().uuidString)")!
        let now = Date()
        #expect(PeriodicPass.isDue("x", every: 3600, defaults: defaults, userId: "a", now: now))
        #expect(!PeriodicPass.isDue("x", every: 3600, defaults: defaults, userId: "a", now: now.addingTimeInterval(60)))
        #expect(PeriodicPass.isDue("x", every: 3600, defaults: defaults, userId: "b", now: now.addingTimeInterval(60)))
        #expect(PeriodicPass.isDue("x", every: 3600, defaults: defaults, userId: "a", now: now.addingTimeInterval(3601)))
        #expect(!PeriodicPass.isDue("x", every: 3600, defaults: defaults, userId: nil, now: now))
    }
}

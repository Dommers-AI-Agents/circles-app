import Foundation
import CoreLocation
import Testing
@testable import Circles_iOS

/// "Walked in the door" versus "drove past": the verdicts behind the
/// arrival check-in banner. Fixes are synthesized; distances are metres
/// due north of the pin.
struct ArrivalVerifierTests {
    private let pin = CLLocationCoordinate2D(latitude: 40.748_817, longitude: -73.985_428)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let radius: CLLocationDistance = 100

    private func fix(meters: Double, accuracy: Double = 10, speed: Double = -1, at seconds: TimeInterval) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: pin.latitude + meters / 111_320, longitude: pin.longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                   course: 0, speed: speed, timestamp: t0.addingTimeInterval(seconds))
    }

    private func verifier() -> ArrivalVerifier { ArrivalVerifier(center: pin, radius: radius, startedAt: t0) }

    @Test func twoGoodFixesAtTheDoorIsAnArrival() {
        var v = verifier()
        #expect(v.observe(fix(meters: 20, at: 1)) == .watching)
        #expect(v.observe(fix(meters: 18, at: 5)) == .arrived)
    }

    @Test func oneGoodFixThenABadOneResets() {
        var v = verifier()
        v.observe(fix(meters: 20, at: 1))
        v.observe(fix(meters: 45, at: 25))           // stepped back out past 30 m, at a walk
        #expect(v.observe(fix(meters: 20, at: 50)) == .watching)
        #expect(v.observe(fix(meters: 20, at: 55)) == .arrived)
    }

    @Test func walkingPastAtTheEdgeNeverArrives() {
        var v = verifier()
        for s in stride(from: 1.0, through: 40, by: 4) { v.observe(fix(meters: 35, at: s)) }
        #expect(v.verdict == .watching)
    }

    /// A slow car on the road out front never comes within 30 m of the pin.
    @Test func aSlowCarOnTheRoadThirtyFiveMetresOutNeverArrives() {
        var v = verifier()
        for (i, s) in stride(from: 1.0, through: 60, by: 5).enumerated() {
            v.observe(fix(meters: 35, speed: 1, at: s))
            if i == 0 { continue }
            #expect(v.verdict == .watching)
        }
    }

    /// The accepted edge (Wes chose precision over delay): a car stopped or
    /// creeping right at the door reads as an arrival. No position data can
    /// tell it from a person walking in.
    @Test func aCarStoppedAtTheDoorIsTheAcceptedEdge() {
        var v = verifier()
        v.observe(fix(meters: 25, speed: 1, at: 1))
        #expect(v.observe(fix(meters: 0, speed: 1, at: 26)) == .arrived)
    }

    /// Simulated and WiFi fixes carry no speed; movement between fixes
    /// still says driving.
    @Test func fixesWithInvalidSpeedStillCountAsDrivingWhenTheyMoveFastEnough() {
        var v = verifier()
        v.observe(fix(meters: 60, at: 0))
        #expect(v.observe(fix(meters: 40, at: 4)) == .watching)  // 5 m/s derived
        #expect(v.observe(fix(meters: 20, at: 8)) == .driving)   // second fast fix
    }

    @Test func twoFastFixesMeanDrivingButOneIsNoise() {
        var v = verifier()
        #expect(v.observe(fix(meters: 20, speed: 8, at: 1)) == .watching)
        #expect(v.observe(fix(meters: 20, speed: 0, at: 5)) == .watching)
        #expect(v.observe(fix(meters: 20, speed: 8, at: 9)) == .watching)
        #expect(v.observe(fix(meters: 20, speed: 8, at: 13)) == .driving)
    }

    @Test func trafficLightThenDrivingOffAborts() {
        var v = verifier()
        v.observe(fix(meters: 40, speed: 0, at: 1))
        v.observe(fix(meters: 40, speed: 0, at: 20))
        v.observe(fix(meters: 40, speed: 9, at: 24))
        #expect(v.observe(fix(meters: 60, speed: 9, at: 28)) == .driving)
    }

    @Test func aFixOutsideTheCircleAbortsBeforeIOSReportsTheExit() {
        var v = verifier()
        v.observe(fix(meters: 40, at: 1))
        #expect(v.observe(fix(meters: 180, accuracy: 30, at: 30)) == .leftRegion)
    }

    @Test func accuracySlackKeepsAWobblyIndoorFixInside() {
        var v = verifier()
        #expect(v.observe(fix(meters: 120, accuracy: 65, at: 1)) == .watching)   // 100 + min(65, 50) = 150
        #expect(v.observe(fix(meters: 160, accuracy: 65, at: 5)) == .leftRegion)
    }

    @Test func poorAccuracyInsideThirtyMetresNeverArrives() {
        var v = verifier()
        for s in stride(from: 1.0, through: 60, by: 4) { v.observe(fix(meters: 10, accuracy: 60, at: s)) }
        #expect(v.verdict == .watching)
    }

    @Test func unusableAndStaleFixesAreIgnored() {
        var v = verifier()
        v.observe(fix(meters: 10, accuracy: -1, at: 1))
        v.observe(fix(meters: 10, accuracy: 500, at: 2))
        v.observe(fix(meters: 10, at: -40))  // Core Location's cached fix from before the watch
        #expect(v.verdict == .watching)
        #expect(v.observe(fix(meters: 10, at: 3)) == .watching)  // first usable fix, streak of one
        #expect(v.observe(fix(meters: 10, at: 7)) == .arrived)
    }

    @Test func deadlineWithoutAnAnswerIsInconclusive() {
        var v = verifier()
        v.observe(fix(meters: 60, at: 1))
        #expect(v.deadlineReached(at: t0.addingTimeInterval(60)) == .watching)
        #expect(v.deadlineReached(at: t0.addingTimeInterval(ArrivalVerifier.Thresholds.maxWatch)) == .inconclusive)
    }

    @Test func verdictIsTerminal() {
        var v = verifier()
        v.observe(fix(meters: 20, at: 1))
        v.observe(fix(meters: 20, at: 5))
        #expect(v.verdict == .arrived)
        #expect(v.observe(fix(meters: 500, at: 9)) == .arrived)
        #expect(v.deadlineReached(at: t0.addingTimeInterval(3600)) == .arrived)
    }

    @Test func derivedSpeedNeedsAPreviousFixAndASecondBetween() {
        let a = fix(meters: 0, at: 0), b = fix(meters: 10, at: 0.5), c = fix(meters: 20, at: 4)
        #expect(ArrivalVerifier.speed(of: a, after: nil) == nil)
        #expect(ArrivalVerifier.speed(of: b, after: a) == nil)
        #expect(ArrivalVerifier.speed(of: c, after: a).map { abs($0 - 5) < 0.2 } == true)
        #expect(ArrivalVerifier.speed(of: fix(meters: 0, speed: 3, at: 8), after: a) == 3)
    }
}

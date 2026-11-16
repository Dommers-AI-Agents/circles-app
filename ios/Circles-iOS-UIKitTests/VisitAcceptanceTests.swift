import Testing
import Foundation
@testable import Circles_iOS

/// Only a finished stop iOS reported becomes a visit — never a drive.
struct VisitAcceptanceTests {

    private typealias V = VisitAcceptance
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let lat = 33.38, lon = -112.17

    private func verdict(minutes: Double, accuracy: Double = 40, arrival: Date? = nil,
                         departure: Date? = nil, recorded: [V.Stay] = []) -> V.Verdict {
        let a = arrival ?? t0
        let d = departure ?? a.addingTimeInterval(minutes * 60)
        return V.verdict(arrival: a, departure: d, horizontalAccuracy: accuracy,
                         minDuration: 5 * 60, latitude: lat, longitude: lon, recorded: recorded)
    }

    @Test func aFinishedStopLongEnoughIsRecorded() {
        #expect(verdict(minutes: 20) == .record)
        #expect(verdict(minutes: 5) == .record)
    }

    @Test func shortStopsLikeALightOrTrafficAreNot() {
        #expect(verdict(minutes: 2) == .tooShort)
        #expect(verdict(minutes: 4.9) == .tooShort)
    }

    @Test func anArrivalWaitsForItsDeparture() {
        #expect(verdict(minutes: 0, departure: .distantFuture) == .notFinished)
    }

    @Test func anUnknownArrivalIsNotGuessed() {
        // distantPast to now would otherwise look like a very long stay
        #expect(verdict(minutes: 0, arrival: .distantPast, departure: t0) == .unknownArrival)
    }

    @Test func aRoughFixIsNotRecorded() {
        #expect(verdict(minutes: 30, accuracy: 150) == .record)
        #expect(verdict(minutes: 30, accuracy: 600) == .tooRough)
        #expect(verdict(minutes: 30, accuracy: -1) == .tooRough)
    }

    @Test func theSameStayReportedTwiceIsRecordedOnce() {
        let same = V.Stay(arrival: t0.addingTimeInterval(60), latitude: lat + 0.0003, longitude: lon)
        #expect(verdict(minutes: 20, recorded: [same]) == .duplicate)
        let laterVisit = V.Stay(arrival: t0.addingTimeInterval(-3 * 3600), latitude: lat, longitude: lon)
        #expect(verdict(minutes: 20, recorded: [laterVisit]) == .record)
        let elsewhere = V.Stay(arrival: t0, latitude: lat + 0.01, longitude: lon)
        #expect(verdict(minutes: 20, recorded: [elsewhere]) == .record)
    }

    @Test func durationIsArrivalToDeparture() {
        #expect(V.durationMinutes(arrival: t0, departure: t0.addingTimeInterval(16 * 60)) == 16)
        #expect(V.durationMinutes(arrival: t0, departure: t0) == 0)
    }
}

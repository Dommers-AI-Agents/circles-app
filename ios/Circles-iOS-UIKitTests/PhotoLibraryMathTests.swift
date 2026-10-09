import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Photos → places: near a place, stops, home, trips.
struct PhotoLibraryMathTests {
    typealias M = PhotoLibraryMath
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()

    func shot(_ id: String, _ lat: Double, _ lng: Double, minutes: Double) -> M.Shot {
        M.Shot(id: id, lat: lat, lng: lng, date: base.addingTimeInterval(minutes * 60))
    }

    @Test func photosNearAPlaceNewestFirst() {
        let shots = [shot("a", 35.2271, -80.8431, minutes: 0), shot("b", 35.2272, -80.8432, minutes: 60),
                     shot("far", 35.30, -80.84, minutes: 30)]
        #expect(M.near(shots, center: CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)).map(\.id) == ["b", "a"])
    }

    @Test func stopsNeedTwoPhotosOrTenMinutes() {
        let shots = [
            shot("cafe1", 35.2271, -80.8431, minutes: 0), shot("cafe2", 35.2272, -80.8431, minutes: 5),   // a stop
            shot("car", 35.2400, -80.8500, minutes: 20),                                                // one shot: not a stop
            shot("park1", 35.2500, -80.8600, minutes: 40)                                              // one shot: not a stop
        ]
        let spots = M.spots(shots)
        #expect(spots.count == 1)
        #expect(spots[0].shots.map(\.id) == ["cafe1", "cafe2"])
    }

    @Test func homeIsTheSpotOnTheMostDays() {
        var shots: [M.Shot] = []
        for day in 0..<5 { shots.append(shot("h\(day)", 35.2000, -80.8000, minutes: Double(day) * 1440)) }
        for i in 0..<8 { shots.append(shot("t\(i)", 32.7765, -79.9311, minutes: 10 * 1440 + Double(i))) } // one busy day away
        let home = M.home(shots, calendar: cal)!
        #expect(abs(home.latitude - 35.2) < 0.01)
    }

    @Test func backToBackDaysAwayAreOneTrip() {
        let home = CLLocationCoordinate2D(latitude: 35.2, longitude: -80.8)
        var shots: [M.Shot] = []
        for day in 0..<3 { for i in 0..<2 { shots.append(shot("c\(day)\(i)", 32.7765, -79.9311, minutes: Double(day) * 1440 + Double(i) * 30)) } }
        shots.append(shot("home", 35.2, -80.8, minutes: 9 * 1440))
        let trips = M.trips(shots, home: home, calendar: cal)
        #expect(trips.count == 1)
        #expect(trips[0].shots.count == 6)
    }

    @Test func stopsAtHomeOrAnExistingSaveAreSkipped() {
        let spot = M.Spot(shots: [shot("a", 35.2, -80.8, minutes: 0)], center: CLLocationCoordinate2D(latitude: 35.2, longitude: -80.8))
        #expect(M.isSkippable(spot, home: CLLocationCoordinate2D(latitude: 35.2005, longitude: -80.8), saved: []))
        #expect(M.isSkippable(spot, home: nil, saved: [CLLocationCoordinate2D(latitude: 35.2003, longitude: -80.8)]))
        #expect(!M.isSkippable(spot, home: nil, saved: []))
    }

    @Test func circleNames() {
        #expect(M.circleName(place: "Charleston", start: base, end: base, calendar: cal).hasPrefix("Charleston · "))
        #expect(!M.circleName(place: nil, start: base, end: base.addingTimeInterval(3 * 86400), calendar: cal).isEmpty)
    }
}

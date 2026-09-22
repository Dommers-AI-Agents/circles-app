import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Where "near me" is measured from: the phone over the server, the server
/// over the map, and the map only when it is all there is.
struct SearchOriginResolverTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ lat: Double, _ lng: Double, age: TimeInterval) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), altitude: 0,
                   horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
    }
    private func c(_ source: SearchOriginResolver.Source, _ lat: Double, _ lng: Double, age: TimeInterval = 0) -> SearchOriginResolver.Candidate {
        .init(location: at(lat, lng, age: age), source: source)
    }

    @Test func aRecentDeviceFixBeatsEverythingTheServerRemembers() {
        let r = SearchOriginResolver.resolve([c(.serverLastKnown, 40.2, -74.0), c(.osCachedFix, 35.2, -80.8, age: 600), c(.mapRegion, 40.1, -74.1)], now: now)
        #expect(r?.source == .osCachedFix)
        #expect(r?.location.coordinate.latitude == 35.2)
    }

    @Test func theNewestDeviceFixWinsWhateverItsSource() {
        let r = SearchOriginResolver.resolve([c(.serviceFix, 1, 1, age: 3600), c(.persistedFix, 2, 2, age: 60), c(.osCachedFix, 3, 3, age: 1800)], now: now)
        #expect(r?.source == .persistedFix)
    }

    @Test func aStaleDeviceFixLosesToTheServer() {
        let r = SearchOriginResolver.resolve([c(.persistedFix, 1, 1, age: 3 * 24 * 3600), c(.serverLastKnown, 35.2, -80.8), c(.mapRegion, 40, -74)], now: now)
        #expect(r?.source == .serverLastKnown)
    }

    @Test func theMapIsLastAndOnlyWhenAlone() {
        #expect(SearchOriginResolver.resolve([c(.mapRegion, 40, -74), c(.serverAssumed, 35, -80)], now: now)?.source == .serverAssumed)
        #expect(SearchOriginResolver.resolve([c(.mapRegion, 40, -74)], now: now)?.source == .mapRegion)
        #expect(SearchOriginResolver.resolve([], now: now) == nil)
    }

    @Test func nullIslandAndInvalidCoordinatesAreNotPositions() {
        #expect(SearchOriginResolver.resolve([c(.serviceFix, 0, 0)], now: now) == nil)
        #expect(SearchOriginResolver.resolve([c(.serviceFix, 95, 0)], now: now) == nil)
    }

    @Test func aPersistedFixKeepsItsTimestampThroughTheRoundTrip() throws {
        let original = at(35.2, -80.8, age: 900)
        let data = try JSONEncoder().encode(PersistedFix(original))
        let back = try JSONDecoder().decode(PersistedFix.self, from: data).location
        #expect(back.timestamp == original.timestamp)
        #expect(back.coordinate.latitude == 35.2)
    }
}

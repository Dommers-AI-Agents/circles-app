import Testing
import MapKit
@testable import Circles_iOS

/// Camera framing for the full-screen map.
struct MapRegionFitterTests {
    private let charlotte = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)
    private let raleigh = CLLocationCoordinate2D(latitude: 35.7796, longitude: -78.6382)

    @Test func nothingToFrameGivesNil() {
        #expect(MapRegionFitter.enclosingRect([]) == nil)
        #expect(MapRegionFitter.boundingRegion([], clampSpan: true) == nil)
    }

    @Test func singlePlaceIsFramedAtTwoKilometers() {
        let region = MapRegionFitter.singleRegion(charlotte)
        #expect(abs(region.center.latitude - charlotte.latitude) < 0.0001)
        // 2 km of latitude is about 0.018°
        #expect(abs(region.span.latitudeDelta - 0.018) < 0.002)
    }

    @Test func boundingRegionCentersAndPadsTheBox() {
        let region = MapRegionFitter.boundingRegion([charlotte, raleigh], clampSpan: true)!
        #expect(abs(region.center.latitude - (35.2271 + 35.7796) / 2) < 0.0001)
        #expect(abs(region.center.longitude - (-80.8431 + -78.6382) / 2) < 0.0001)
        #expect(abs(region.span.latitudeDelta - (35.7796 - 35.2271) * 1.3) < 0.0001)
        #expect(abs(region.span.longitudeDelta - (80.8431 - 78.6382) * 1.3) < 0.0001)
    }

    @Test func clampingKeepsCoincidentPlacesVisible() {
        let clamped = MapRegionFitter.boundingRegion([charlotte, charlotte], clampSpan: true)!
        #expect(clamped.span.latitudeDelta == 0.01)
        #expect(clamped.span.longitudeDelta == 0.01)
        let raw = MapRegionFitter.boundingRegion([charlotte, charlotte], clampSpan: false)!
        #expect(raw.span.latitudeDelta == 0)
    }

    @Test func enclosingRectCoversBothEnds() {
        let rect = MapRegionFitter.enclosingRect([charlotte, raleigh])!
        #expect(rect.contains(MKMapPoint(charlotte)))
        #expect(rect.contains(MKMapPoint(raleigh)))
    }

    @Test func focusRadiusWithNoFavoritesIsTheMaximum() {
        #expect(MapRegionFitter.focusRadius(distances: []) == MapRegionFitter.maxFocusRadius)
    }

    @Test func focusRadiusFitsTheClosestTenWhenEnoughAreNearby() {
        // Twelve favorites 1 km apart: the tenth is 10 km out, padded by 20%
        let distances = (1...12).map { Double($0) * 1_000 }.reversed()
        #expect(abs(MapRegionFitter.focusRadius(distances: Array(distances)) - 12_000) < 0.001)
        // Never tighter than two miles
        #expect(MapRegionFitter.focusRadius(distances: [100, 200, 300]) == MapRegionFitter.minFocusRadius)
        // Never wider than 25 miles on the nearby branch
        #expect(MapRegionFitter.focusRadius(distances: [39_000, 39_500, 40_000]) == MapRegionFitter.maxFocusRadius)
    }

    @Test func focusRadiusReachesTheNearestFewWhenFavoritesAreFar() {
        // Only two within 25 miles: zoom out to the third-nearest, padded
        let distances: [CLLocationDistance] = [50_000, 5_000, 90_000, 70_000]
        #expect(abs(MapRegionFitter.focusRadius(distances: distances) - 70_000 * 1.2) < 0.001)
        // A single far favorite still gets the padded reach
        #expect(abs(MapRegionFitter.focusRadius(distances: [100_000]) - 120_000) < 0.001)
    }
}

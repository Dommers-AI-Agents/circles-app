import Testing
import Foundation
import CoreLocation
import ImageIO
import MapKit
import UIKit
import UniformTypeIdentifiers
@testable import Circles_iOS

/// Using each photo's own GPS accuracy to place a spot and match it to a
/// place (2026-10-17).
struct PhotoLocationAccuracyTests {
    typealias G = PhotoPlaceGrouper
    let cafe = CLLocationCoordinate2D(latitude: 35.2116, longitude: -80.8601)

    /// `meters` north of the café
    func north(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: cafe.latitude + meters / 111_320, longitude: cafe.longitude)
    }

    @Test func aRoughFixCannotDragSharpOnes() throws {
        var fixes: [(coordinate: CLLocationCoordinate2D, accuracy: Double?)] = (0..<5).map { _ in (cafe, 8) }
        fixes.append((north(80), 120))
        let est = try #require(G.estimate(fixes))
        #expect(G.distance(est.center, cafe) < 3)
        // Without accuracies the same rough fix is averaged in
        let mean = try #require(G.estimate(fixes.map { ($0.coordinate, nil) }))
        #expect(G.distance(mean.center, cafe) > G.distance(est.center, cafe))
    }

    @Test func sharpFixesOutweighRoughOnesEvenWhenFewer() throws {
        // Two 6 m fixes at the café, three 60 m fixes 40 m north (plausible
        // for indoor Wi-Fi positioning): the centre stays near the café
        let fixes: [(coordinate: CLLocationCoordinate2D, accuracy: Double?)] =
            [(cafe, 6), (cafe, 6), (north(40), 60), (north(40), 60), (north(40), 60)]
        let est = try #require(G.estimate(fixes))
        #expect(G.distance(est.center, cafe) < 5)
    }

    @Test func morePhotosSharpenUpToTwice() throws {
        let one = try #require(G.estimate([(cafe, 20)]))
        let four = try #require(G.estimate(Array(repeating: (cafe, 20.0), count: 4)))
        let ten = try #require(G.estimate(Array(repeating: (cafe, 20.0), count: 10)))
        #expect(abs(one.uncertainty - 20) < 0.01)
        #expect(abs(four.uncertainty - 10) < 0.01)
        #expect(abs(ten.uncertainty - 10) < 0.01)
        #expect(try #require(G.estimate([(cafe, 2)])).uncertainty == G.minUncertainty)
    }

    @Test func unknownAccuracyCountsAsTypicalIndoor() throws {
        let est = try #require(G.estimate([(cafe, nil), (cafe, -1)]))
        #expect(abs(est.uncertainty - G.assumedAccuracy / 2.squareRoot()) < 0.01)
    }

    @Test func libraryStopsCarryTheirUncertainty() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let shots = (0..<3).map { i in
            PhotoLibraryMath.Shot(id: "\(i)", lat: cafe.latitude, lng: cafe.longitude,
                                  date: base.addingTimeInterval(Double(i) * 120), acc: 20)
        }
        let spots = PhotoLibraryMath.spots(shots)
        #expect(spots.count == 1)
        #expect(abs(spots[0].uncertainty - 20 / 3.0.squareRoot()) < 0.01)
        #expect(PhotoFindSpot(spot: spots[0]).uncertainty == spots[0].uncertainty)
    }

    @Test func picksGroupWithTheirAccuracy() throws {
        let fixes = [G.Fix(id: 0, coordinate: cafe, takenAt: nil, accuracy: 5),
                     G.Fix(id: 1, coordinate: north(50), takenAt: nil, accuracy: 200)]
        let group = try #require(G.group(fixes).first)
        #expect(G.distance(try #require(group.center), cafe) < 1)
        #expect(group.uncertainty == G.minUncertainty)
    }

    @Test func reachFollowsTheUncertainty() {
        let store = MKPointOfInterestCategory.store.rawValue
        let park = MKPointOfInterestCategory.park.rawValue
        #expect(PhotoPlaceKind.reach(categoryRaw: store) == 100)              // no estimate: as before
        #expect(PhotoPlaceKind.reach(categoryRaw: store, uncertainty: 8) == 60)
        #expect(PhotoPlaceKind.reach(categoryRaw: store, uncertainty: 30) == 90)
        #expect(PhotoPlaceKind.reach(categoryRaw: store, uncertainty: 80) == 150)
        #expect(PhotoPlaceKind.reach(categoryRaw: park, uncertainty: 8) == 220)
    }

    /// The café's head start shrinks when the fix is sharp: a photo good to
    /// 8 m taken on the shop's doorstep is the shop, not the café 40 m away.
    @Test func aSharpFixKeepsTheShopItSitsOn() {
        let store = MKPointOfInterestCategory.store.rawValue
        let cafeKind = MKPointOfInterestCategory.cafe.rawValue
        #expect(PhotoPlaceKind.rankScore(distance: 10, categoryRaw: store, uncertainty: 8)
                < PhotoPlaceKind.rankScore(distance: 40, categoryRaw: cafeKind, uncertainty: 8))
        // A rough fix still prefers the café, as before
        #expect(PhotoPlaceKind.rankScore(distance: 40, categoryRaw: cafeKind, uncertainty: 30)
                < PhotoPlaceKind.rankScore(distance: 10, categoryRaw: store, uncertainty: 30))
        #expect(PhotoPlaceKind.rankScore(distance: 40, categoryRaw: cafeKind)
                == PhotoPlaceKind.rankScore(distance: 40, categoryRaw: cafeKind, uncertainty: 30))
    }

    @Test func roughSpotsWithACloseRunnerUpAreBestGuesses() {
        #expect(PhotoPlaceKind.isBestGuess(distances: [20, 45], uncertainty: 60))
        #expect(!PhotoPlaceKind.isBestGuess(distances: [20, 45], uncertainty: 20))    // sharp: trust it
        #expect(!PhotoPlaceKind.isBestGuess(distances: [10, 130], uncertainty: 60))   // runner-up far off
        #expect(!PhotoPlaceKind.isBestGuess(distances: [20], uncertainty: 90))        // nothing else here
    }

    @Test func accuracyReportBucketsPhotosAndSpots() {
        let d = Date()
        let shots = [5.0, 25, 50, 90, nil].enumerated().map { i, acc in
            PhotoLibraryMath.Shot(id: "\(i)", lat: 35, lng: -80, date: d, acc: acc)
        }
        let report = PhotoLibraryMath.accuracyReport(shots: shots, spotUncertainties: [40, 10, 20])
        #expect(report["acc_le10"] == "1" && report["acc_le30"] == "1" && report["acc_le65"] == "1")
        #expect(report["acc_gt65"] == "1" && report["acc_none"] == "1")
        #expect(report["spot_uncertainty_median"] == "20" && report["spots"] == "3")
    }

    @Test func pickedPhotosReadTheirGPSError() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage!
        func jpeg(_ gps: [CFString: Any]) -> Data {
            let data = NSMutableData()
            let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
            CGImageDestinationFinalize(dest)
            return data as Data
        }
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 35.2216, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 80.8418, kCGImagePropertyGPSLongitudeRef: "W"]
        var withError = gps
        withError[kCGImagePropertyGPSHPositioningError] = 14.5
        #expect(PhotoMetadataReader.metadata(from: jpeg(withError)).accuracy == 14.5)
        #expect(PhotoMetadataReader.metadata(from: jpeg(gps)).accuracy == nil)
    }
}

extension PhotoLocationAccuracyTests {
    /// A fix that claims 5 m but is 300 m off (a bad GPS jump) can't drag
    /// five honest 8 m fixes, or knock them out as "outliers"
    @Test func aConfidentWrongFixIsDropped() throws {
        var fixes: [(coordinate: CLLocationCoordinate2D, accuracy: Double?)] = (0..<5).map { _ in (cafe, 8) }
        fixes.append((north(300), 5))
        let est = try #require(G.estimate(fixes))
        #expect(G.distance(est.center, cafe) < 3)
    }
}

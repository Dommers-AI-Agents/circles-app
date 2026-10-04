import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreLocation
@testable import Circles_iOS

struct PhotoPlaceGrouperTests {
    private let diner = CLLocationCoordinate2D(latitude: 35.2216, longitude: -80.8418)      // uptown Charlotte
    private func near(_ c: CLLocationCoordinate2D, north meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + meters / 111_320, longitude: c.longitude)
    }
    private func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60) }

    @Test func twoSpotsAndOneWithoutLocationMakeThreeGroups() {
        let southEnd = CLLocationCoordinate2D(latitude: 35.2118, longitude: -80.8577)
        let groups = PhotoPlaceGrouper.group([
            .init(id: 0, coordinate: southEnd, takenAt: at(90)),
            .init(id: 1, coordinate: diner, takenAt: at(0)),
            .init(id: 2, coordinate: near(diner, north: 30), takenAt: at(5)),
            .init(id: 3, coordinate: nil, takenAt: at(10)),
            .init(id: 4, coordinate: near(southEnd, north: 20), takenAt: at(95))
        ])
        #expect(groups.count == 3)
        #expect(groups[0].photoIds == [1, 2])           // earliest spot first
        #expect(groups[1].photoIds == [0, 4])
        #expect(groups[2].center == nil && groups[2].photoIds == [3])
        #expect(groups[0].takenAt == at(0))
    }

    @Test func chainsWithinReachJoinButFarSpotsDoNot() {
        // 0—60 m—1—60 m—2 chain into one; 3 is 300 m off
        let groups = PhotoPlaceGrouper.group([
            .init(id: 0, coordinate: diner, takenAt: nil),
            .init(id: 1, coordinate: near(diner, north: 60), takenAt: nil),
            .init(id: 2, coordinate: near(diner, north: 120), takenAt: nil),
            .init(id: 3, coordinate: near(diner, north: 420), takenAt: nil)
        ])
        #expect(groups.map { $0.photoIds.sorted() }.sorted { $0[0] < $1[0] } == [[0, 1, 2], [3]])
    }

    @Test func centerIsTheMedianSoOneStrayFixDoesNotDragIt() {
        let c = PhotoPlaceGrouper.median([diner, near(diner, north: 10), near(diner, north: 70)])!
        #expect(abs(PhotoPlaceGrouper.distance(c, near(diner, north: 10))) < 1)
    }
}

struct PhotoPlaceRankerTests {
    private let spot = CLLocationCoordinate2D(latitude: 35.2216, longitude: -80.8418)
    private func north(_ m: Double) -> CLLocationCoordinate2D { .init(latitude: spot.latitude + m / 111_320, longitude: spot.longitude) }

    @Test func aSavedPlaceBeatsACloserNewBusiness() {
        let picks = PhotoPlaceRanker.rank(center: spot,
            saved: [.init(id: "s1", name: "Midnight Diner", coordinate: north(40))],
            pois: [.init(name: "Bank of America", coordinate: north(5), isResidential: false)])
        #expect(picks.count == 2)
        if case .saved(let id, _) = picks[0] { #expect(id == "s1") } else { Issue.record("saved first") }
        if case .poi(let index, _) = picks[1] { #expect(index == 0) } else { Issue.record("then the POI") }
    }

    @Test func homeAddressesFarPlacesAndTheSavedOneAgainAreLeftOut() {
        let picks = PhotoPlaceRanker.rank(center: spot,
            saved: [.init(id: "s1", name: "Midnight Diner", coordinate: north(20))],
            pois: [.init(name: "123 Main St", coordinate: north(3), isResidential: true),
                   .init(name: "Far Cafe", coordinate: north(400), isResidential: false),
                   .init(name: "Midnight Diner", coordinate: north(22), isResidential: false),
                   .init(name: "Fuel Pizza", coordinate: north(50), isResidential: false),
                   .init(name: "Trade & Tryon", coordinate: north(30), isResidential: false)])
        #expect(picks == [.saved(id: "s1", meters: picks[0].meters), .poi(index: 4, meters: picks[1].meters), .poi(index: 3, meters: picks[2].meters)])
    }

    @Test func nothingNearbyIsEmpty() {
        #expect(PhotoPlaceRanker.rank(center: spot, saved: [], pois: []).isEmpty)
    }
}

private extension PhotoPlaceRanker.Pick {
    var meters: Double { switch self { case .saved(_, let m), .poi(_, let m): return m } }
}

struct PhotoMetadataReaderTests {
    /// A real JPEG carrying the GPS and EXIF a phone writes.
    private func jpeg(gps: [CFString: Any]?, exif: [CFString: Any]?) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let gps { props[kCGImagePropertyGPSDictionary] = gps }
        if let exif { props[kCGImagePropertyExifDictionary] = exif }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    @Test func westAndSouthRefsMakeNegativeCoordinates() {
        let data = jpeg(gps: [kCGImagePropertyGPSLatitude: 35.2216, kCGImagePropertyGPSLatitudeRef: "N",
                              kCGImagePropertyGPSLongitude: 80.8418, kCGImagePropertyGPSLongitudeRef: "W"], exif: nil)
        let c = PhotoMetadataReader.metadata(from: data).coordinate!
        #expect(abs(c.latitude - 35.2216) < 0.0001 && abs(c.longitude + 80.8418) < 0.0001)
        let sydney = jpeg(gps: [kCGImagePropertyGPSLatitude: 33.8568, kCGImagePropertyGPSLatitudeRef: "S",
                                kCGImagePropertyGPSLongitude: 151.2153, kCGImagePropertyGPSLongitudeRef: "E"], exif: nil)
        #expect(PhotoMetadataReader.metadata(from: sydney).coordinate!.latitude < 0)
    }

    @Test func noGPSMeansNoLocation() {
        #expect(PhotoMetadataReader.metadata(from: jpeg(gps: nil, exif: nil)).coordinate == nil)
    }

    @Test func captureTimeHonorsTheRecordedOffset() {
        let data = jpeg(gps: nil, exif: [kCGImagePropertyExifDateTimeOriginal: "2026:10:04 14:10:05",
                                         kCGImagePropertyExifOffsetTimeOriginal: "-04:00"])
        let taken = PhotoMetadataReader.metadata(from: data).takenAt
        #expect(taken == ISO8601DateFormatter().date(from: "2026-10-04T18:10:05Z"))
    }

    @Test func theDisplayImageCarriesNoLocation() {
        let data = jpeg(gps: [kCGImagePropertyGPSLatitude: 35.2, kCGImagePropertyGPSLatitudeRef: "N",
                              kCGImagePropertyGPSLongitude: 80.8, kCGImagePropertyGPSLongitudeRef: "W"], exif: nil)
        let image = PhotoMetadataReader.displayImage(from: data)!
        let reencoded = image.jpegData(compressionQuality: 0.8)!
        #expect(PhotoMetadataReader.metadata(from: reencoded).coordinate == nil)
    }
}

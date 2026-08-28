import XCTest
import MapKit

/// Harness test for Apple Look Around snapshots — exercises the raw MapKit
/// API (deliberately NOT AppleLookAroundService) so "does the API deliver
/// imagery" is isolated from the app's wiring. Writes PNGs to /tmp for
/// visual inspection.
final class LookAroundSnapshotTests: XCTestCase {

    private struct Venue {
        let name: String
        let lat: Double
        let lng: Double
    }

    private let venues = [
        Venue(name: "cvs-south-blvd", lat: 35.213866, lng: -80.855098),
        Venue(name: "spectrum-center", lat: 35.2251, lng: -80.8392),
        Venue(name: "office-depot", lat: 35.2129124, lng: -80.8567158)
    ]

    func testLookAroundSnapshots() async throws {
        var results: [String] = []

        for venue in venues {
            let coordinate = CLLocationCoordinate2D(latitude: venue.lat, longitude: venue.lng)
            do {
                guard let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
                    results.append("\(venue.name): NO SCENE (no coverage at coordinate)")
                    continue
                }
                let options = MKLookAroundSnapshotter.Options()
                options.size = CGSize(width: 600, height: 400)
                let snapshot = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot
                let image = snapshot.image
                if let data = image.pngData() {
                    let url = URL(fileURLWithPath: "/tmp/lookaround-\(venue.name).png")
                    try data.write(to: url)
                    results.append("\(venue.name): OK \(Int(image.size.width))x\(Int(image.size.height)) -> \(url.path)")
                } else {
                    results.append("\(venue.name): snapshot produced no PNG data")
                }
            } catch {
                results.append("\(venue.name): ERROR \(error)")
            }
        }

        print("LOOKAROUND RESULTS:\n" + results.joined(separator: "\n"))
        XCTAssertTrue(results.contains { $0.contains("OK") },
                      "No venue produced a snapshot — " + results.joined(separator: " | "))
    }
}

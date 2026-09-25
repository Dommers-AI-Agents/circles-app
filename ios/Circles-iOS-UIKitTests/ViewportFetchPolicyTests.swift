import Foundation
import Testing
@testable import Circles_iOS

/// When a map movement loads places, and when — during a search — it doesn't.
struct ViewportFetchPolicyTests {
    private func vp(_ lat: Double, _ lng: Double, _ r: Double) -> ViewportFetchPolicy.Viewport {
        .init(latitude: lat, longitude: lng, radiusM: r)
    }
    private let charlotte = ViewportFetchPolicy.Viewport(latitude: 35.2271, longitude: -80.8431, radiusM: 3_000)

    @Test func idleLoadsAnythingNotAlreadyCovered() {
        #expect(ViewportFetchPolicy.shouldFetch(searching: false, viewport: charlotte, fetched: []))
        // A small pan inside the fetched circle: covered, nothing to load.
        #expect(!ViewportFetchPolicy.shouldFetch(searching: false, viewport: vp(35.2280, -80.8431, 1_000), fetched: [charlotte]))
        // A pan that pokes outside it loads when idle...
        #expect(ViewportFetchPolicy.shouldFetch(searching: false, viewport: vp(35.2450, -80.8431, 3_000), fetched: [charlotte]))
    }

    @Test func searchingIgnoresSmallPansAndZooms() {
        // ...but not while searching: it still overlaps what is loaded.
        #expect(!ViewportFetchPolicy.shouldFetch(searching: true, viewport: vp(35.2450, -80.8431, 3_000), fetched: [charlotte]))
        // Zoomed out a bit (1.5×): still no.
        #expect(!ViewportFetchPolicy.shouldFetch(searching: true, viewport: vp(35.2271, -80.8431, 4_500), fetched: [charlotte]))
    }

    @Test func searchingLoadsOnABigZoomOutOrAWhollyNewArea() {
        // Zoomed out to twice the widest fetched area.
        #expect(ViewportFetchPolicy.shouldFetch(searching: true, viewport: vp(35.2271, -80.8431, 6_000), fetched: [charlotte]))
        // Belmar NJ: overlaps nothing fetched.
        #expect(ViewportFetchPolicy.shouldFetch(searching: true, viewport: vp(40.1706, -74.0654, 3_000), fetched: [charlotte]))
        // Nothing fetched yet: the first load always happens.
        #expect(ViewportFetchPolicy.shouldFetch(searching: true, viewport: charlotte, fetched: []))
    }

    @Test func distanceIsRoughlyRight() {
        let d = ViewportFetchPolicy.distanceM(vp(35.2271, -80.8431, 0), vp(40.1706, -74.0654, 0))
        #expect(d > 800_000 && d < 830_000) // Charlotte → Belmar ≈ 815 km
    }
}

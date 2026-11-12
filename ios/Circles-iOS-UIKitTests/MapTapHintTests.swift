import Foundation
import Testing
@testable import Circles_iOS

/// "Tap a place to add it" on the Home and expanded maps (2026-11-11)
struct MapTapHintTests {
    private func freshDefaults() -> UserDefaults {
        let name = "MapTapHintTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func showsOnTappableMapsUntilTheyAddFromOne() {
        let defaults = freshDefaults()
        #expect(MapTapHint.shows(placesTappable: true, defaults: defaults))
        #expect(!MapTapHint.shows(placesTappable: false, defaults: defaults)) // a circle's map: places aren't tappable
        MapTapHint.retire(defaults: defaults)
        #expect(!MapTapHint.shows(placesTappable: true, defaults: defaults))
        MapTapHint.retire(defaults: defaults) // again is harmless
        #expect(!MapTapHint.shows(placesTappable: true, defaults: defaults))
    }
}

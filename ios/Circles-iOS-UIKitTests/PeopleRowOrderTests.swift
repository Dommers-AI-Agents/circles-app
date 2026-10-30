import Testing
import Foundation
@testable import Circles_iOS

/// The home people row paints in the order it last showed (2026-10-30).
struct PeopleRowOrderTests {
    @Test func rememberedOrderFirstNewcomersAfterInTheirOwnOrder() {
        let cached = ["dan", "amy", "zoe", "bob", "new1", "new2"]
        let ordered = PeopleRowOrder.apply(["bob", "zoe", "amy", "dan"], to: cached) { $0 }
        #expect(ordered == ["bob", "zoe", "amy", "dan", "new1", "new2"])
        // Someone remembered who isn't in the list any more is just skipped
        #expect(PeopleRowOrder.apply(["gone", "amy"], to: ["dan", "amy"]) { $0 } == ["amy", "dan"])
        // Nothing remembered: unchanged
        #expect(PeopleRowOrder.apply([], to: ["b", "a"]) { $0 } == ["b", "a"])
    }

    @Test func savedPerAccount() {
        let defaults = UserDefaults(suiteName: "PeopleRowOrderTests")!
        defaults.removePersistentDomain(forName: "PeopleRowOrderTests")
        PeopleRowOrder.save(["a", "b"], for: "me", defaults: defaults)
        #expect(PeopleRowOrder.saved(for: "me", defaults: defaults) == ["a", "b"])
        #expect(PeopleRowOrder.saved(for: "someoneElse", defaults: defaults).isEmpty)
        #expect(PeopleRowOrder.saved(for: nil, defaults: defaults).isEmpty)
    }
}

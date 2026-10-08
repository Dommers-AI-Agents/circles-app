import Testing
@testable import Circles_iOS

struct HomeButtonPinsTests {
    private func pin(_ id: String) -> HomeButtonPin { .init(id: id, title: id.capitalized) }

    @Test func pinUnpinKeepsOrder() {
        var pins = HomeButtonPins.toggle(pin("water"), in: [])
        pins = HomeButtonPins.toggle(pin("workouts"), in: pins)
        #expect(pins.map(\.id) == ["water", "workouts"])
        pins = HomeButtonPins.toggle(pin("water"), in: pins)
        #expect(pins.map(\.id) == ["workouts"])
    }

    @Test func pastTheLimitTheOldestGoes() {
        var pins: [HomeButtonPin] = []
        for id in ["a", "b", "c", "d", "e", "f", "g"] { pins = HomeButtonPins.toggle(pin(id), in: pins) }
        #expect(pins.count == HomeButtonPins.limit)
        #expect(pins.first?.id == "b")
        #expect(pins.last?.id == "g")
    }

    @Test func retiredWidgetsDropOut() {
        #expect(HomeButtonPins.valid([pin("water"), pin("gone")], knownIds: ["water"]).map(\.id) == ["water"])
    }
}

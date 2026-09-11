import Testing
import CoreGraphics
@testable import Circles_iOS

/// Pin tiering is what keeps the map readable: nearest places win their full
/// pin, colliding neighbours become dots, and the selected pin never demotes.
struct PinTierPlannerTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    private func candidate(_ id: String, x: CGFloat, y: CGFloat, distance: Double) -> PinTierPlanner.Candidate {
        PinTierPlanner.Candidate(id: id, point: CGPoint(x: x, y: y), distance: distance)
    }

    @Test func emptyInputYieldsNoPins() {
        #expect(PinTierPlanner().fullPinIds(for: [], in: bounds) == [])
    }

    @Test func nonOverlappingPinsAllKeepFullPins() {
        let ids = PinTierPlanner().fullPinIds(for: [
            candidate("a", x: 50, y: 100, distance: 10),
            candidate("b", x: 200, y: 400, distance: 20),
            candidate("c", x: 350, y: 700, distance: 30)
        ], in: bounds)
        #expect(ids == ["a", "b", "c"])
    }

    @Test func nearerPlaceWinsACollision() {
        // Same screen spot; "far" is listed first but "near" has priority.
        let ids = PinTierPlanner().fullPinIds(for: [
            candidate("far", x: 100, y: 100, distance: 500),
            candidate("near", x: 105, y: 102, distance: 5)
        ], in: bounds)
        #expect(ids == ["near"])
    }

    @Test func pinsJustTouchingDoNotCollide() {
        var planner = PinTierPlanner()
        planner.pinSize = CGSize(width: 10, height: 10)
        // Rects [0,10] and [10,20] on x share only an edge — CGRect.intersects is false.
        let ids = planner.fullPinIds(for: [
            candidate("a", x: 5, y: 50, distance: 1),
            candidate("b", x: 15, y: 50, distance: 2)
        ], in: bounds)
        #expect(ids == ["a", "b"])
    }

    @Test func capStopsPromotionInPriorityOrder() {
        var planner = PinTierPlanner()
        planner.maxFullPins = 2
        let ids = planner.fullPinIds(for: [
            candidate("third", x: 300, y: 600, distance: 30),
            candidate("first", x: 50, y: 100, distance: 10),
            candidate("second", x: 150, y: 300, distance: 20)
        ], in: bounds)
        #expect(ids == ["first", "second"])
    }

    @Test func offscreenPlacesBecomeDotsButOverscanCounts() {
        var planner = PinTierPlanner()
        planner.overscan = CGSize(width: 40, height: 50)
        let ids = planner.fullPinIds(for: [
            candidate("wayOff", x: -200, y: 100, distance: 1),
            candidate("justOff", x: -20, y: 100, distance: 2),   // inside the 40pt overscan
            candidate("on", x: 200, y: 400, distance: 3)
        ], in: bounds)
        #expect(ids == ["justOff", "on"])
    }

    @Test func pinnedIdsAlwaysKeepFullPinsEvenOverCapOrOffscreen() {
        var planner = PinTierPlanner()
        planner.maxFullPins = 1
        let ids = planner.fullPinIds(for: [
            candidate("nearest", x: 50, y: 100, distance: 1),
            candidate("selected", x: -500, y: -500, distance: 999)
        ], in: bounds, pinned: ["selected"])
        #expect(ids == ["nearest", "selected"])
    }

    @Test func collisionLoserDoesNotBlockLaterCandidates() {
        // "loser" collides with "winner" and is skipped; its rect must NOT be
        // reserved, so "later" (which only overlaps the loser) still promotes.
        var planner = PinTierPlanner()
        planner.pinSize = CGSize(width: 20, height: 20)
        let ids = planner.fullPinIds(for: [
            candidate("winner", x: 100, y: 100, distance: 1),
            candidate("loser", x: 115, y: 100, distance: 2),
            candidate("later", x: 130, y: 100, distance: 3)
        ], in: bounds)
        #expect(ids == ["winner", "later"])
    }
}

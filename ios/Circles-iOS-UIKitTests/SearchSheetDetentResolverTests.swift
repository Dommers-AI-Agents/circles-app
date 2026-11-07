import CoreGraphics
import Testing
@testable import Circles_iOS

/// Where a drag leaves the home search sheet: the resting height nearest to
/// where it would coast (collapsed / half / full, Wes 2026-11-07).
struct SearchSheetDetentResolverTests {
    private let heights: [SearchSheetState: CGFloat] = [.collapsed: 52, .expanded: 341, .full: 560]

    @Test func aFlickCarriesTheSheet() {
        // Released near half, flicked up: full; flicked down: collapsed
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 360, velocityY: -1200, heights: heights) == .full)
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 320, velocityY: 1400, heights: heights) == .collapsed)
    }

    @Test func aSlowDragSettlesOnTheNearestHeight() {
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 480, velocityY: 0, heights: heights) == .full)
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 400, velocityY: 20, heights: heights) == .expanded)
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 150, velocityY: 0, heights: heights) == .collapsed)
    }

    @Test func aShortListHasNoFullHeight() {
        let two: [SearchSheetState: CGFloat] = [.collapsed: 52, .expanded: 268]
        #expect(SearchSheetDetentResolver.resolve(currentHeight: 268, velocityY: -1500, heights: two) == .expanded)
    }

    @Test func pullingTheListDownStepsTheSheetDown() {
        #expect(SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: -61))
        #expect(!SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: -30))
        #expect(!SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: 40))
        #expect(SearchSheetDetentResolver.stepDown(from: .full) == .expanded)
        #expect(SearchSheetDetentResolver.stepDown(from: .expanded) == .collapsed)
    }

    @Test func fullLeavesAStripOfMap() {
        #expect(SearchSheetLayout.fullHeight(available: 620, content: 2000) == 564)
        #expect(SearchSheetLayout.fullHeight(available: 620, content: 300) == 300)
    }
}

import Foundation
import Testing
@testable import Circles_iOS

/// Where a drag leaves the search results sheet.
struct SearchSheetDetentResolverTests {
    private let travel: CGFloat = 289 // 341 expanded − 52 handle

    @Test func aFlickDecidesByDirectionAlone() {
        #expect(SearchSheetDetentResolver.resolve(from: .expanded, translationY: 10, velocityY: 900, travel: travel) == .collapsed)
        #expect(SearchSheetDetentResolver.resolve(from: .collapsed, translationY: -10, velocityY: -900, travel: travel) == .expanded)
        // A flick the way it already is changes nothing.
        #expect(SearchSheetDetentResolver.resolve(from: .collapsed, translationY: 10, velocityY: 900, travel: travel) == .collapsed)
    }

    @Test func aSlowDragFlipsPastHalfway() {
        #expect(SearchSheetDetentResolver.resolve(from: .expanded, translationY: 160, velocityY: 50, travel: travel) == .collapsed)
        #expect(SearchSheetDetentResolver.resolve(from: .expanded, translationY: 120, velocityY: 50, travel: travel) == .expanded)
        #expect(SearchSheetDetentResolver.resolve(from: .collapsed, translationY: -160, velocityY: -50, travel: travel) == .expanded)
        #expect(SearchSheetDetentResolver.resolve(from: .collapsed, translationY: -120, velocityY: -50, travel: travel) == .collapsed)
    }

    @Test func pullingTheListPastItsTopCollapses() {
        #expect(SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: -61))
        #expect(!SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: -30))
        #expect(!SearchSheetDetentResolver.shouldCollapse(forPullDownOffset: 40))
    }
}

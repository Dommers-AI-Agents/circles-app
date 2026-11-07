import Foundation
import Testing
@testable import Circles_iOS

/// The height rules of the home search results sheet.
struct SearchSheetLayoutTests {
    private func plan(places: Int, nearby: Int = 0, people: Int = 0) -> HomeSearchPlan {
        HomeSearchPlan(placeRows: places, suggestedRows: nearby, peopleRows: people)
    }

    /// Results sections have no titles (the chips name them); recent and browse keep theirs
    @Test func contentIsTheHandlePlusEachNonEmptySection() {
        #expect(SearchSheetLayout.contentHeight(for: plan(places: 3, nearby: 3)) == 484)
        #expect(SearchSheetLayout.contentHeight(for: plan(places: 1)) == 124)
        #expect(SearchSheetLayout.contentHeight(for: plan(places: 0, people: 2)) == 196)
        let idleExpected: CGFloat = 324   // handle 52 + RECENT 28 + 2 rows + BROWSE 28 + 1 row
        #expect(SearchSheetLayout.contentHeight(for: .idle(recent: 2, browse: 1)) == idleExpected)
    }

    @Test func aboutHalfTheRoomButTheMapKeepsItsStrip() {
        // iPhone 16 Pro, keyboard up: 323 pt of room → the 150 pt map strip wins over 55 %.
        let content = SearchSheetLayout.contentHeight(for: plan(places: 3, nearby: 3))
        #expect(SearchSheetLayout.expandedHeight(available: 323, content: content) == 173)
        // Keyboard down: 620 pt of room → 55 %.
        #expect(SearchSheetLayout.expandedHeight(available: 620, content: content) == 341)
    }

    @Test func neverBelowOneRowEvenOnASmallPhone() {
        // SE-class with the keyboard up: 253 pt of room would leave 103 → one row (152) wins.
        let content = SearchSheetLayout.contentHeight(for: plan(places: 3, nearby: 3))
        #expect(SearchSheetLayout.expandedHeight(available: 253, content: content) == SearchSheetLayout.minSheetHeight)
    }

    @Test func neverTallerThanItsContent() {
        #expect(SearchSheetLayout.expandedHeight(available: 620, content: 152) == 152)
    }

    @Test func collapsedIsJustTheHandle() {
        #expect(SearchSheetLayout.height(for: .collapsed, available: 620, content: 540) == 52)
        #expect(SearchSheetLayout.height(for: .expanded, available: 620, content: 540) == 341)
    }
}

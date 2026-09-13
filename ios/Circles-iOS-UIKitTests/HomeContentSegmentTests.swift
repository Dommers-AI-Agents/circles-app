import Testing
@testable import Circles_iOS

/// The home segment enum replaces the raw segment indices; these pin the
/// order and the per-segment chrome so a future insertion can't silently
/// shift Specials or hide the camera button.
struct HomeContentSegmentTests {
    @Test func orderMatchesSegmentedControl() {
        #expect(HomeContentSegment.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(HomeContentSegment.allCases.map(\.title) == ["Activity", "Moments", "Specials", "Widgets"])
        #expect(HomeContentSegment(rawValue: 2) == .specials)
        #expect(HomeContentSegment(rawValue: 3) == .widgets)
        #expect(HomeContentSegment(rawValue: 4) == nil)
    }

    @Test func onlyMomentsShowsTheCameraButton() {
        #expect(HomeContentSegment.allCases.filter(\.showsCameraButton) == [.moments])
    }

    @Test func headerTitles() {
        #expect(HomeContentSegment.activity.headerTitle == "Recent Activity")
        #expect(HomeContentSegment.widgets.headerTitle == "Widgets")
    }
}

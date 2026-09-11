import Testing
@testable import Circles_iOS

/// The profile's Moments/Uploads grids size themselves: rows of square
/// 3-column tiles plus padding, or a fixed minimum when empty.
struct ProfileGridTabTests {
    @Test func emptyGridReservesRoomForTheEmptyLabel() {
        #expect(ProfileGridTabViewController.gridHeight(itemCount: 0, width: 390) == ProfileGridTabViewController.emptyHeight)
    }

    @Test func heightIsRowsOfSquareTilesPlusSpacingAndPadding() {
        // 390pt wide, 2pt gaps → tiles are (390 - 4) / 3 ≈ 128.67pt
        let tile = (390.0 - 4.0) / 3.0
        func height(_ count: Int) -> Double { Double(ProfileGridTabViewController.gridHeight(itemCount: count, width: 390)) }
        #expect(abs(height(3) - (tile + 20)) < 0.01)          // one row
        #expect(abs(height(4) - (2 * tile + 2 + 20)) < 0.01)  // two rows
        #expect(abs(height(9) - (3 * tile + 4 + 20)) < 0.01)  // three rows
    }
}

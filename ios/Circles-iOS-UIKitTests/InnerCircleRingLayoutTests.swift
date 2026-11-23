import Testing
import Foundation
import CoreGraphics
@testable import Circles_iOS

/// The ring on My People → Inner Circles: who gets a face, when "+N" appears,
/// and where each bubble sits (Wes, 2026-11-23).
struct InnerCircleRingLayoutTests {
    typealias Layout = InnerCircleRingLayout

    @Test func capacityIsHowManyBubblesFitTheCircumference() {
        // 2π·125 ≈ 785 pt of ring, 56 pt per bubble
        #expect(Layout.capacity(ringRadius: 125, bubbleDiameter: 46, minimumGap: 10) == 14)
        #expect(Layout.capacity(ringRadius: 0, bubbleDiameter: 46, minimumGap: 10) == 0)
        #expect(Layout.capacity(ringRadius: 125, bubbleDiameter: 0, minimumGap: 10) == 0)
    }

    @Test func anEmptyListIsJustTheAddBubble() {
        #expect(Layout.slots(memberCount: 0, capacity: 14, canAdd: true) == [.add])
    }

    @Test func everyoneGetsAFaceWhenThereIsRoom() {
        let slots = Layout.slots(memberCount: 3, capacity: 14, canAdd: true)
        #expect(slots == [.member(index: 0), .member(index: 1), .member(index: 2), .add])
        // Exactly full: 13 faces and the add bubble
        let full = Layout.slots(memberCount: 13, capacity: 14, canAdd: true)
        #expect(full.count == 14)
        #expect(full.last == .add)
        #expect(!full.contains(.overflow(count: 1)))
    }

    @Test func aLongListEndsInPlusNCountingEveryoneNotShown() {
        let slots = Layout.slots(memberCount: 40, capacity: 14, canAdd: true)
        #expect(slots.count == 14)
        #expect(slots[11] == .member(index: 11))
        #expect(slots[12] == .overflow(count: 28))
        #expect(slots[13] == .add)
        // Faces shown + N is always the whole list
        #expect(12 + 28 == 40)
    }

    @Test func aFullListHasNoAddBubble() {
        let slots = Layout.slots(memberCount: 150, capacity: 14, canAdd: false)
        #expect(slots.count == 14)
        #expect(!slots.contains(.add))
        #expect(slots.last == .overflow(count: 137))
    }

    @Test func noRoomDrawsNothing() {
        #expect(Layout.slots(memberCount: 5, capacity: 0, canAdd: true).isEmpty)
        // Room for one bubble only: the add bubble wins, so the list is never stuck
        #expect(Layout.slots(memberCount: 5, capacity: 1, canAdd: true) == [.add])
    }

    @Test func theFirstBubbleSitsAtTheTopAndTheRestGoClockwise() {
        let center = CGPoint(x: 100, y: 100)
        let top = Layout.point(forSlot: 0, of: 4, ringRadius: 50, around: center)
        let right = Layout.point(forSlot: 1, of: 4, ringRadius: 50, around: center)
        let bottom = Layout.point(forSlot: 2, of: 4, ringRadius: 50, around: center)
        let left = Layout.point(forSlot: 3, of: 4, ringRadius: 50, around: center)
        #expect(abs(top.x - 100) < 0.001 && abs(top.y - 50) < 0.001)
        #expect(abs(right.x - 150) < 0.001 && abs(right.y - 100) < 0.001)
        #expect(abs(bottom.x - 100) < 0.001 && abs(bottom.y - 150) < 0.001)
        #expect(abs(left.x - 50) < 0.001 && abs(left.y - 100) < 0.001)
    }

    @Test func removingSomeoneKeepsEveryoneElseIncludingThoseBehindPlusN() {
        let all = (0..<40).map { "u\($0)" }
        let after = Layout.membersAfterRemoving("u3", from: all)
        #expect(after.count == 39)
        #expect(!after.contains("u3"))
        // u39 was never on screen (behind "+28") and must survive the save
        #expect(after.contains("u39"))
        #expect(Layout.membersAfterRemoving("nobody", from: all) == all)
    }

    // MARK: - The people picker's Done

    private func person(_ id: String) -> TaggedMomentUser {
        TaggedMomentUser(id: id, displayName: id, profilePicture: nil)
    }

    @Test func doneBeforeConnectionsLoadKeepsWhoWasAlreadyOnTheList() {
        let onList = [person("a"), person("b")]
        let chosen = TagPeoplePickerViewController.chosen(loaded: [], initialSelection: onList, selectedIds: ["a", "b"])
        #expect(chosen.map { $0.id } == ["a", "b"])
    }

    @Test func doneReturnsEveryoneCheckedOnceAndDropsTheUnchecked() {
        let loaded = [person("a"), person("b"), person("c")]
        // a was on the list and stays, b was unchecked, c was added
        let chosen = TagPeoplePickerViewController.chosen(loaded: loaded, initialSelection: [person("a"), person("b")], selectedIds: ["a", "c"])
        #expect(chosen.map { $0.id } == ["a", "c"])
    }
}

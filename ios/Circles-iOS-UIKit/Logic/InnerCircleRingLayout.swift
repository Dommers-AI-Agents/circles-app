import Foundation
import CoreGraphics

/// Where things sit on an inner circle's ring (My Network → My People →
/// Inner Circles): the people on the list as faces around a circle, a "+N"
/// bubble when there are more people than room, and an add bubble last.
///
/// Pure geometry and counting, so the drawing code never decides who is
/// shown. The ring only ever shows SOME of a long list — edits are made from
/// the list's full membership, never from what happens to be on screen.
enum InnerCircleRingLayout {

    enum Slot: Equatable {
        /// The person at this index of the list's members
        case member(index: Int)
        /// "+N": the people who didn't fit
        case overflow(count: Int)
        /// The add-people bubble
        case add
    }

    /// How many bubbles fit around a ring without touching.
    static func capacity(ringRadius: CGFloat, bubbleDiameter: CGFloat, minimumGap: CGFloat) -> Int {
        guard ringRadius > 0, bubbleDiameter > 0 else { return 0 }
        let circumference = 2 * CGFloat.pi * ringRadius
        return max(0, Int(circumference / (bubbleDiameter + max(0, minimumGap))))
    }

    /// The bubbles to draw, in ring order (clockwise from the top).
    ///
    /// The add bubble is kept whenever the list has room for another person;
    /// when the members don't all fit, the last member slot becomes "+N" and
    /// N counts everyone not shown.
    static func slots(memberCount: Int, capacity: Int, canAdd: Bool) -> [Slot] {
        let members = max(0, memberCount)
        let forMembers = max(0, capacity - (canAdd ? 1 : 0))
        var slots: [Slot] = []
        if members <= forMembers {
            slots = (0..<members).map { .member(index: $0) }
        } else if forMembers > 0 {
            let shown = forMembers - 1
            slots = (0..<shown).map { .member(index: $0) }
            slots.append(.overflow(count: members - shown))
        }
        if canAdd && capacity > 0 { slots.append(.add) }
        return slots
    }

    /// The angle of slot `index` of `count`, in radians: the first sits at the
    /// top and the rest follow clockwise, evenly spaced.
    static func angle(forSlot index: Int, of count: Int) -> CGFloat {
        guard count > 0 else { return -CGFloat.pi / 2 }
        return -CGFloat.pi / 2 + (2 * CGFloat.pi) * CGFloat(index) / CGFloat(count)
    }

    /// The centre of slot `index` of `count` on a ring around `center`.
    static func point(forSlot index: Int, of count: Int, ringRadius: CGFloat, around center: CGPoint) -> CGPoint {
        let a = angle(forSlot: index, of: count)
        return CGPoint(x: center.x + ringRadius * cos(a), y: center.y + ringRadius * sin(a))
    }

    /// The list's members after taking one person off — always computed from
    /// the whole list. (A save replaces the list, so working from the faces
    /// on screen would drop everyone behind "+N".)
    static func membersAfterRemoving(_ userId: String, from allUserIds: [String]) -> [String] {
        allUserIds.filter { $0 != userId }
    }
}

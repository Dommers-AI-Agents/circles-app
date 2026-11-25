import Testing
import UIKit
@testable import Circles_iOS

/// Inner circles are explained as what they are for: choosing who you share
/// with. A new user sees an example, not an empty page (Wes, 2026-11-25).
@MainActor
struct InnerCircleExplainerTests {
    typealias Copy = InnerCircleExplainer

    @Test func theExplainerSaysTheyAreForSharing() {
        let text = Copy.message.lowercased()
        #expect(text.contains("share with"))
        #expect(text.contains("only the people on it see it"))
        // Not the other way around: nothing about who influences you
        #expect(!text.contains("influence"))
        #expect(!text.contains("defines you"))
        #expect(!Copy.headerHint.lowercased().contains("influence"))
    }

    @Test func theExampleNamesItsListAndEveryoneOnIt() {
        #expect(Copy.exampleMembers.count >= 3)
        #expect(Copy.exampleMemberIds.count == Copy.exampleMembers.count)
        #expect(Set(Copy.exampleMemberIds).count == Copy.exampleMembers.count)
        #expect(Copy.exampleMemberIds.allSatisfy { $0.hasPrefix(Copy.exampleIdPrefix) })
        #expect(Copy.exampleCaption.contains(Copy.exampleListName))
        for name in Copy.exampleMembers {
            #expect(Copy.exampleCaption.contains(name))
            #expect(Copy.exampleAccessibilityLabel.contains(name))
        }
    }

    @Test func theExampleRingDrawsEveryFaceAndNothingToTap() {
        let list = InnerCirclesVisualViewController.exampleList()
        #expect(list.name == Copy.exampleListName)
        #expect(list.users.map { $0.displayName } == Copy.exampleMembers)
        // Full to its own size: no add bubble on a list that isn't real
        let slots = InnerCircleRingLayout.slots(memberCount: list.users.count, capacity: 12, canAdd: false)
        #expect(slots == (0..<list.users.count).map { .member(index: $0) })
    }

    @Test func aNewUsersPageShowsTheExample() {
        let controller = InnerCirclesVisualViewController()
        let state = controller.makeFirstCircleState(width: 390)
        let rings = state.allSubviews.compactMap { $0 as? InnerCircleRingView }
        #expect(rings.count == 1)
        #expect(rings.first?.list.name == Copy.exampleListName)
        // The example is a picture: taps go to the real button under it
        #expect(rings.first?.isUserInteractionEnabled == false)
        let labels = state.allSubviews.compactMap { ($0 as? UILabel)?.text }
        #expect(labels.contains(Copy.exampleBadge))
        #expect(labels.contains(Copy.exampleCaption))
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap { $0.allSubviews } }
}

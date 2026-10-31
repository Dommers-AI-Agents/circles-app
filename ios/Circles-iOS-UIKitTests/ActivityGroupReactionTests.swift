import Testing
@testable import Circles_iOS

struct ActivityGroupReactionTests {
    @Test func reactedOnlyWhenEveryActivityIs() {
        #expect(ActivityGroupReaction.groupReaction([]) == nil)
        #expect(ActivityGroupReaction.groupReaction(["👍", nil, "👍"]) == nil)
        #expect(ActivityGroupReaction.groupReaction(["👍", "👍"]) == "👍")
        #expect(ActivityGroupReaction.groupReaction(["❤️", "👍", "❤️"]) == "❤️")
        #expect(ActivityGroupReaction.groupReaction(["🎉", "👍"]) == "🎉")
    }

    @Test func tapTogglesTheWholeGroup() {
        #expect(ActivityGroupReaction.removes(memberReactions: ["👍", "👍"], tapped: "👍"))
        #expect(!ActivityGroupReaction.removes(memberReactions: ["👍", nil], tapped: "👍"))
        #expect(!ActivityGroupReaction.removes(memberReactions: ["👍", "👍"], tapped: "❤️"))
    }

    @Test func chipsCountPeopleNotActivities() {
        let a = [ReactionSummary(emoji: "👍", count: 2, users: nil)]
        let b = [ReactionSummary(emoji: "👍", count: 3, users: nil), ReactionSummary(emoji: "🎉", count: 1, users: nil)]
        let out = ActivityGroupReaction.summary([a, nil, b])
        #expect(out.map(\.emoji) == ["👍", "🎉"])
        #expect(out.map(\.count) == [3, 1])
        #expect(ActivityGroupReaction.summary([nil, []]).isEmpty)
        #expect(ActivityGroupReaction.total([2, nil, 5]) == 5)
        #expect(ActivityGroupReaction.total([nil]) == 0)
    }
}

import Foundation

/// One heart for a whole group row (Wes, 2026-10-31). The feed collapses a
/// burst of one person's activities into a summary row; a reaction there
/// lands on every activity in it (POST activities/reactions/group, one
/// notification). Pure so the rules are tested.
enum ActivityGroupReaction {
    /// The group counts as reacted only when every activity in it has your
    /// reaction: then it's the emoji you used most. Partly reacted reads as
    /// not reacted, so one tap fills in the rest.
    static func groupReaction(_ memberReactions: [String?]) -> String? {
        guard !memberReactions.isEmpty else { return nil }
        let emojis = memberReactions.compactMap { $0 }
        guard emojis.count == memberReactions.count else { return nil }
        var counts: [String: Int] = [:]
        for emoji in emojis { counts[emoji, default: 0] += 1 }
        // Most used; ties go to the first one in the group
        return emojis.first { counts[$0] == counts.values.max() }
    }

    /// Tapping the emoji the group already shows takes it off every
    /// activity; anything else puts that emoji on all of them.
    static func removes(memberReactions: [String?], tapped: String) -> Bool {
        groupReaction(memberReactions) == tapped
    }

    /// Chips for the group: per emoji the most any single activity got,
    /// which is how many different people at least reacted that way (the
    /// same friend hearting five activities is one friend, not five).
    static func summary(_ members: [[ReactionSummary]?]) -> [ReactionSummary] {
        var best: [String: Int] = [:]
        var order: [String] = []
        for list in members {
            for reaction in list ?? [] where reaction.count > 0 {
                if best[reaction.emoji] == nil { order.append(reaction.emoji) }
                best[reaction.emoji] = max(best[reaction.emoji] ?? 0, reaction.count)
            }
        }
        return order
            .map { ReactionSummary(emoji: $0, count: best[$0] ?? 0, users: nil) }
            .sorted { $0.count > $1.count }
    }

    /// The total under the chips: the busiest single activity's count.
    static func total(_ counts: [Int?]) -> Int {
        counts.compactMap { $0 }.max() ?? 0
    }
}

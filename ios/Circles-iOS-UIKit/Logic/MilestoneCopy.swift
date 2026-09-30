import Foundation

/// Words for the milestone push's screen (MilestoneMonthViewController).
enum MilestoneCopy {

    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10, ones = n % 10
        let suffix = tens == 1 ? "th" : (ones == 1 ? "st" : ones == 2 ? "nd" : ones == 3 ? "rd" : "th")
        return "\(n)\(suffix)"
    }

    static func navTitle(_ m: PushMilestone) -> String {
        m.kind == "top_contributor" ? "Your Month" : "Milestone"
    }

    static func emoji(_ m: PushMilestone) -> String {
        switch m.kind {
        case "top_contributor":
            switch m.position { case 1: return "🥇"; case 2: return "🥈"; case 3: return "🥉"; default: return "🏆" }
        case "connections": return "👥"
        case "moments": return "📸"
        default: return "🎉"
        }
    }

    /// The live rank wins over the push's (the month moved on since it was sent)
    static func headline(_ m: PushMilestone, month: (count: Int, rank: Int?)?) -> String {
        switch m.kind {
        case "top_contributor":
            if let rank = month?.rank ?? m.position { return "\(ordinal(rank)) for adding places this month" }
            return "One of this month's top contributors"
        case "connections":
            return m.value.map { $0 == 1 ? "Your first connection" : "\($0) connections" } ?? "Your network is growing"
        case "moments":
            return m.value.map { $0 == 1 ? "Your first moment" : "\($0) moments shared" } ?? "Your moments are adding up"
        default:
            return m.value.map { $0 == 1 ? "Your first place" : "\($0) places saved" } ?? "Your circles are growing"
        }
    }

    static func detail(_ m: PushMilestone, count: Int?, behindFirst: Int?) -> String {
        switch m.kind {
        case "top_contributor":
            let added = (count ?? m.value).map { "You added \($0) place\($0 == 1 ? "" : "s") in the last 30 days." } ?? ""
            guard let behind = behindFirst else { return added }
            if behind == 0 { return added + " Nobody has added more." }
            return added + " \(behind) more and you'd tie for first."
        case "connections": return "Everyone you connect with makes the places you see better."
        case "moments": return "Your moments show people what a place is really like."
        default: return "Every place you add helps the people who trust your taste."
        }
    }

    static func primaryAction(_ m: PushMilestone) -> String {
        m.kind == "connections" ? "Find more people" : "Add a place"
    }

    /// An /app/open path (DeepLinkRouter.openPathDestination)
    static func primaryPath(_ m: PushMilestone) -> String {
        m.kind == "connections" ? "network" : "add-place"
    }

    static func shareText(_ m: PushMilestone, count: Int?) -> String {
        switch m.kind {
        case "top_contributor":
            let rank = m.position.map { ordinal($0) + " place" } ?? "a top spot"
            let places = count.map { " with \($0) places" } ?? ""
            return "I took \(rank) for adding favorite places on FavCircles this month\(places) 🏆"
        default:
            return "\(headline(m, month: nil)) on FavCircles 🎉"
        }
    }
}

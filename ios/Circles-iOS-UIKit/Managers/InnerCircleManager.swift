import Foundation

extension Notification.Name {
    /// The Inner Circle list changed. Privacy pickers listen so their caption
    /// ("3 people · Edit list") stays true while a form is open.
    static let innerCircleDidChange = Notification.Name("innerCircleDidChange")
}

/// App-wide cache of the signed-in user's Inner Circle list.
///
/// Every privacy picker wants to say how many people the tier reaches, and the
/// moment tag picker needs the membership to avoid tagging someone who can't
/// see the moment. Neither should fire its own request, so the list is fetched
/// once and refreshed whenever a write returns a new one.
final class InnerCircleManager {
    static let shared = InnerCircleManager()
    private init() {}

    private(set) var list: InnerCircleList = .empty
    private(set) var hasLoaded = false

    var memberCount: Int { list.userIds.count }
    /// The named lists worth offering as an audience (the ones with people on).
    var usableLists: [InnerCircleNamedList] { list.usableLists }
    var members: [User] { list.users }

    func contains(userId: String) -> Bool { list.userIds.contains(userId) }

    /// Fetch unless we already have it. Safe to call from any screen's load.
    func primeIfNeeded(completion: (() -> Void)? = nil) {
        guard !hasLoaded else { completion?(); return }
        refresh { _ in completion?() }
    }

    func refresh(completion: ((Result<InnerCircleList, Error>) -> Void)? = nil) {
        InnerCircleService.shared.getList { result in
            // `update` already ran inside the service on success; this is just
            // the caller's completion.
            completion?(result)
        }
    }

    /// Called by InnerCircleService after every successful read or write.
    func update(with list: InnerCircleList) {
        self.list = list
        self.hasLoaded = true
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .innerCircleDidChange, object: nil)
        }
    }

    /// Signing out must not leave one account's list visible to the next.
    func clear() {
        list = .empty
        hasLoaded = false
    }

    /// The caption under a picker set to Inner Circle. Says the quiet part out
    /// loud when the list is empty, because that tier with nobody on it is
    /// simply Private and people will not guess that.
    var pickerCaption: String {
        switch memberCount {
        case 0: return "No one yet — add people, or this is the same as Private"
        case 1: return "1 person · Edit list"
        default: return "\(memberCount) people · Edit list"
        }
    }
}

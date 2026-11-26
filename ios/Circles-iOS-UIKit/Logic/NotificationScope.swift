import Foundation

/// "Stores I follow only" (Wes, 2026-11-26). Someone who joined by scanning a
/// store said yes to hearing from that store, not to everything FavCircles
/// sends, so a new account made that way starts in `.storesOnly`. They get
/// more by choosing it: once at the end of the tour, once at each moment that
/// shows friends matter to them (a request, a suggestion, a message, following
/// someone), or in Notification Settings. Pure: no UIKit, no services.
enum NotificationScope {
    enum Mode: String {
        case all
        case storesOnly

        init(raw: String?) { self = Mode(rawValue: raw ?? "") ?? .all }
    }

    /// A moment that asks "Get notified about friends too?", once each
    enum Moment: String, CaseIterable {
        case tour
        case friendRequest
        case suggestion
        case message
        case follow
    }

    /// The three choices in Notification Settings
    enum Choice: Equatable {
        case all
        case storesOnly
        case custom
    }

    static func shouldAsk(mode: Mode, asked: Set<String>, moment: Moment) -> Bool {
        mode == .storesOnly && !asked.contains(moment.rawValue)
    }

    /// Settings' selected row: Stores only, else All when every switch is on,
    /// else Let me choose
    static func choice(mode: Mode, everySwitchOn: Bool) -> Choice {
        if mode == .storesOnly { return .storesOnly }
        return everySwitchOn ? .all : .custom
    }

    struct Ask: Equatable {
        let title: String
        let message: String
        let yes: String
        let no: String
    }

    /// The words for each moment; `name` is the person (first name only)
    static func ask(_ moment: Moment, name: String? = nil) -> Ask {
        let first = name?.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first.flatMap { $0.isEmpty ? nil : $0 }
        let yes = "Yes, notify me"
        let no = "Not now"
        switch moment {
        case .tour:
            return Ask(title: "Hear about friends too?",
                       message: "Right now FavCircles only tells you about the stores you follow. Turn on the rest to hear when friends save places, send you suggestions or follow you.",
                       yes: "Notify me about everything", no: "Just my stores")
        case .friendRequest:
            return Ask(title: first.map { "\($0) wants to connect" } ?? "Someone wants to connect",
                       message: "Get notified when friends connect, message you or suggest places?",
                       yes: yes, no: no)
        case .suggestion:
            return Ask(title: first.map { "\($0) suggested a place for you" } ?? "A place was suggested for you",
                       message: "Get notified when friends suggest places, message you or connect?",
                       yes: yes, no: no)
        case .message:
            return Ask(title: "Messages from friends",
                       message: "Get notified when friends message you, suggest places or connect?",
                       yes: yes, no: no)
        case .follow:
            return Ask(title: first.map { "Want to know when \($0) saves new places?" } ?? "Want to know when friends save new places?",
                       message: "Right now you only get notifications from the stores you follow.",
                       yes: yes, no: no)
        }
    }
}

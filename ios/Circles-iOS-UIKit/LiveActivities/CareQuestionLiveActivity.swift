import Foundation
import ActivityKit
import AppIntents

// Shared by the app and the Circles-Widget extension (membership exception in
// the project): a How Are You? question on the parent's Lock Screen until they
// answer it (Wes, 2026-10-30). The server starts it by push (push-to-start,
// iOS 17.2+) — backend services/careCheckin/liveActivity.js contentState; the
// struct name and every key must match it exactly.

@available(iOS 16.1, *)
struct CareQuestionAttributes: ActivityAttributes {
    let askId: String
    let planId: String
    let fromName: String

    struct Choice: Codable, Hashable {
        let key: String
        let label: String
    }

    struct ContentState: Codable, Hashable {
        var question: String
        var kind: String           // mood | done | yesno | scale | text
        var choices: [Choice]      // the buttons; empty for scale and text
        var low: String?           // scale ends ("None" … "Worst")
        var high: String?
        var answered: Bool
        var answerText: String?    // shown for a moment after answering
    }
}

enum CareQuestionLinks {
    /// The How Are You? widget, where a 0–10 or typed answer is given.
    static let open = URL(string: "https://api.favcircles.com/app/widget/howareyou")!
}

/// The app's answer path, set at launch. A LiveActivityIntent always runs in
/// the app's process, so this is never nil when the intent performs.
enum CareQuestionAnswerBridge {
    nonisolated(unsafe) static var answer: ((_ askId: String, _ answer: String) async -> Bool)?
}

/// A choice button on the Lock Screen: answers without opening the app.
@available(iOS 17.0, *)
struct AnswerCareQuestionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Answer a check-in question"
    static var isDiscoverable = false

    @Parameter(title: "Question") var askId: String
    @Parameter(title: "Answer") var answer: String

    init() {}
    init(askId: String, answer: String) {
        self.askId = askId
        self.answer = answer
    }

    func perform() async throws -> some IntentResult {
        _ = await CareQuestionAnswerBridge.answer?(askId, answer)
        return .result()
    }
}

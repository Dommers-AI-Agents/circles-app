import Testing
import Foundation
@testable import Circles_iOS

/// The chat's rows (2026-11-23): day dividers, runs of one person's
/// messages, and the Read / Sent word.
struct ChatTimelineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ id: String, _ sender: String, _ date: Date?, mine: Bool = false, read: Bool = false) -> ChatTimeline.Entry {
        ChatTimeline.Entry(id: id, senderId: sender, date: date, isMine: mine, readByOther: read)
    }

    private func bubble(_ id: String, starts: Bool, ends: Bool) -> ChatTimeline.Row {
        .message(ChatTimeline.Bubble(id: id, startsRun: starts, endsRun: ends))
    }

    @Test func theClassicChatIsOneRowPerMessage() {
        let entries = [entry("a", "me", date(22, 9), mine: true), entry("b", "me", date(23, 9, 1), mine: true)]
        #expect(ChatTimeline.rows(entries, grouped: false, calendar: calendar, now: date(23, 12))
                == [bubble("a", starts: true, ends: true), bubble("b", starts: true, ends: true)])
    }

    @Test func aNewDayGetsADivider() {
        let entries = [entry("a", "me", date(22, 21), mine: true), entry("b", "sunil", date(23, 10))]
        #expect(ChatTimeline.rows(entries, grouped: true, calendar: calendar, now: date(23, 12))
                == [.day("Yesterday"), bubble("a", starts: true, ends: true),
                    .day("Today"), bubble("b", starts: true, ends: true)])
    }

    @Test func quickMessagesFromOnePersonAreOneRun() {
        let entries = [entry("a", "sunil", date(23, 10, 0)), entry("b", "sunil", date(23, 10, 2)),
                       entry("c", "sunil", date(23, 10, 4)), entry("d", "me", date(23, 10, 5), mine: true)]
        #expect(ChatTimeline.rows(entries, grouped: true, calendar: calendar, now: date(23, 12))
                == [.day("Today"), bubble("a", starts: true, ends: false), bubble("b", starts: false, ends: false),
                    bubble("c", starts: false, ends: true), bubble("d", starts: true, ends: true)])
    }

    @Test func aLongPauseStartsANewRun() {
        let entries = [entry("a", "sunil", date(23, 10, 0)), entry("b", "sunil", date(23, 10, 6))]
        #expect(ChatTimeline.rows(entries, grouped: true, calendar: calendar, now: date(23, 12))
                == [.day("Today"), bubble("a", starts: true, ends: true), bubble("b", starts: true, ends: true)])
    }

    @Test func midnightSplitsARun() {
        let entries = [entry("a", "sunil", date(22, 23, 59)), entry("b", "sunil", date(23, 0, 1))]
        #expect(ChatTimeline.rows(entries, grouped: true, calendar: calendar, now: date(23, 12))
                == [.day("Yesterday"), bubble("a", starts: true, ends: true),
                    .day("Today"), bubble("b", starts: true, ends: true)])
    }

    @Test func aMessageWithNoDateStillShows() {
        let entries = [entry("a", "sunil", nil), entry("b", "sunil", nil)]
        #expect(ChatTimeline.rows(entries, grouped: true, calendar: calendar, now: date(23, 12))
                == [bubble("a", starts: true, ends: false), bubble("b", starts: false, ends: true)])
    }

    @Test func dayTitles() {
        let now = date(23, 12) // Monday
        let english = Locale(identifier: "en_US")
        #expect(ChatTimeline.dayTitle(for: date(23, 1), calendar: calendar, now: now, locale: english) == "Today")
        #expect(ChatTimeline.dayTitle(for: date(22, 23), calendar: calendar, now: now, locale: english) == "Yesterday")
        #expect(ChatTimeline.dayTitle(for: date(19, 8), calendar: calendar, now: now, locale: english) == "Thursday")
        #expect(ChatTimeline.dayTitle(for: date(3, 8), calendar: calendar, now: now, locale: english) == "Tue, Nov 3")
        #expect(ChatTimeline.dayTitle(for: date(3, 8, year: 2025), calendar: calendar, now: now, locale: english) == "Nov 3, 2025")
    }

    @Test func theReceiptSitsUnderYourNewestMessageOnly() {
        let mineLast = [entry("a", "sunil", date(23, 9)), entry("b", "me", date(23, 10), mine: true)]
        #expect(ChatTimeline.receipt(mineLast)?.id == "b")
        #expect(ChatTimeline.receipt(mineLast)?.text == "Sent")
        let read = [entry("b", "me", date(23, 10), mine: true, read: true)]
        #expect(ChatTimeline.receipt(read)?.text == "Read")
        // They answered: no word under the older message
        let theirsLast = [entry("b", "me", date(23, 10), mine: true, read: true), entry("c", "sunil", date(23, 11))]
        #expect(ChatTimeline.receipt(theirsLast) == nil)
        #expect(ChatTimeline.receipt([]) == nil)
    }
}

import Testing
import Foundation
@testable import Circles_iOS

/// The My check-ins screen's words.
struct MyCheckInsCopyTests {
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }
    /// 2026-11-09 20:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_794_254_400)

    private func place(count: Int, lastDaysAgo: Double, firstDaysAgo: Double, imported: Int? = nil, recent: Int = 0) -> CheckInPlaceSummary {
        CheckInPlaceSummary(globalPlaceId: "g", placeId: nil, name: "Crunch Fitness", address: nil, category: nil, photoUrl: nil,
                            count: count, importedCount: imported,
                            firstCheckInAt: now.addingTimeInterval(-firstDaysAgo * 86_400),
                            lastCheckInAt: now.addingTimeInterval(-lastDaysAgo * 86_400), recentCount: recent)
    }

    @Test func headlineCountsBoth() {
        #expect(MyCheckInsCopy.headline(total: 42, places: 17) == "42 check-ins at 17 places")
        #expect(MyCheckInsCopy.headline(total: 1, places: 1) == "1 check-in at 1 place")
    }

    @Test func recentLineOnlyWhenThereWereAny() {
        #expect(MyCheckInsCopy.recent(0, days: 30) == nil)
        #expect(MyCheckInsCopy.recent(5, days: 30) == "5 in the last 30 days")
        #expect(MyCheckInsCopy.recentBadge(0) == nil)
        #expect(MyCheckInsCopy.recentBadge(3) == "×3 lately")
    }

    @Test func detailReusesThePlacePageCaptionAndAddsTheFirstTime() {
        let line = MyCheckInsCopy.detail(for: place(count: 7, lastDaysAgo: 1, firstDaysAgo: 65), now: now, calendar: calendar, locale: locale)
        #expect(line == "Checked in 7 times · last yesterday · first Sep 5")
    }

    @Test func singleVisitHasNoFirst() {
        let line = MyCheckInsCopy.detail(for: place(count: 1, lastDaysAgo: 0, firstDaysAgo: 0), now: now, calendar: calendar, locale: locale)
        #expect(line == "Checked in once · last today")
    }

    @Test func swarmHistoryIsNamed() {
        let line = MyCheckInsCopy.detail(for: place(count: 12, lastDaysAgo: 100, firstDaysAgo: 400, imported: 12), now: now, calendar: calendar, locale: locale)
        #expect(line.hasPrefix("Checked in 12 times on Swarm · last Aug 1"))
        #expect(line.hasSuffix("· first Oct 5, 2025"))
    }
}

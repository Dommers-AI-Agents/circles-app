import Foundation
import Testing
@testable import Circles_iOS

/// Add from photos → Scan a time period.
struct PhotoPeriodTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    @Test func monthsAndYearsNewestFirstWithCounts() {
        let dates = [day(2026, 9, 3), day(2026, 9, 20), day(2026, 5, 1), day(2025, 12, 31)]
        let months = PhotoPeriod.months(of: dates, calendar: calendar)
        #expect(months.map(\.count) == [2, 1, 1])
        #expect(calendar.component(.month, from: months[0].start) == 9)
        #expect(PhotoPeriod.years(of: dates, calendar: calendar).map(\.year) == [2026, 2025])
    }

    @Test func whichPhotosAreIn() {
        let sep = PhotoPeriod.month(day(2026, 9, 1))
        #expect(PhotoPeriod.contains([sep], day(2026, 9, 30), calendar: calendar))
        #expect(!PhotoPeriod.contains([sep], day(2026, 10, 1), calendar: calendar))
        #expect(PhotoPeriod.contains([.year(2025)], day(2025, 7, 4), calendar: calendar))
        #expect(PhotoPeriod.contains([.all], day(2019, 1, 1), calendar: calendar))
    }

    @Test func circleNames() {
        let sep = PhotoPeriod.month(day(2026, 9, 1)), oct = PhotoPeriod.month(day(2026, 10, 1))
        #expect(PhotoPeriod.circleName([sep], place: "Charleston", calendar: calendar) == "Charleston \u{00B7} Sep 2026")
        #expect(PhotoPeriod.circleName([sep, oct], place: nil, calendar: calendar) == "Sep\u{2013}Oct 2026")
        #expect(PhotoPeriod.circleName([.year(2025)], place: nil, calendar: calendar) == "2025")
        #expect(PhotoPeriod.circleName([.all], place: "Paris", calendar: calendar) == "All my photos")
    }
}

import Foundation
import Testing
@testable import Circles_iOS

/// "Happening nearby" rows on the Specials tab: day words, time, place, price.
struct NearbyEventFormatterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9))! }

    @Test func dayWords() {
        #expect(NearbyEventFormatter.dateLine(localDate: "2026-10-15", localTime: "20:00:00", now: now, calendar: calendar) == "Tonight · 8:00 PM")
        #expect(NearbyEventFormatter.dateLine(localDate: "2026-10-15", localTime: "13:30:00", now: now, calendar: calendar) == "Today · 1:30 PM")
        #expect(NearbyEventFormatter.dateLine(localDate: "2026-10-16", localTime: "19:30:00", now: now, calendar: calendar) == "Tomorrow · 7:30 PM")
        #expect(NearbyEventFormatter.dateLine(localDate: "2026-10-18", localTime: nil, now: now, calendar: calendar) == "Sun, Oct 18")
        #expect(NearbyEventFormatter.dateLine(localDate: "garbage", localTime: nil, now: now, calendar: calendar) == "garbage")
    }

    @Test func placeLine() {
        #expect(NearbyEventFormatter.placeLine(venueName: "The Fillmore", city: "Charlotte", distanceMeters: 965) == "The Fillmore · 0.6 mi")
        #expect(NearbyEventFormatter.placeLine(venueName: nil, city: "Charlotte", distanceMeters: nil) == "Charlotte")
        #expect(NearbyEventFormatter.placeLine(venueName: nil, city: nil, distanceMeters: nil) == nil)
    }

    @Test func price() {
        #expect(NearbyEventFormatter.priceText(min: 25, currency: "USD") == "$25+")
        #expect(NearbyEventFormatter.priceText(min: 19.5, currency: "USD") == "$19.50+")
        #expect(NearbyEventFormatter.priceText(min: 0, currency: "USD") == "Free")
        #expect(NearbyEventFormatter.priceText(min: nil, currency: "USD") == nil)
    }
}

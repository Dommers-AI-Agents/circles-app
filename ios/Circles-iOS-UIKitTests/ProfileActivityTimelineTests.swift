import Testing
import Foundation
@testable import Circles_iOS

struct ProfileActivityTimelineTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 ~11:33 ET

    private func item(_ id: String, _ type: String, category: String, hoursAgo: Double, name: String = "Tommy's Tavern") -> OwnActivityItem {
        OwnActivityItem(id: id, type: type, category: category, timestamp: now.addingTimeInterval(-hoursAgo * 3600), targetName: name)
    }

    @Test func daysAreNewestFirstAndSocialFoldsIntoOneRow() {
        let items = [
            item("a", "check_in", category: "checkins", hoursAgo: 1),
            item("b", "place_liked", category: "social", hoursAgo: 2),
            item("c", "video_uploaded", category: "moments", hoursAgo: 3),
            item("d", "comment_added", category: "social", hoursAgo: 4),
            item("e", "check_in", category: "checkins", hoursAgo: 30),
            item("f", "user_followed", category: "social", hoursAgo: 31)
        ]
        let sections = ProfileActivityTimeline.sections(from: items.shuffled(), now: now, calendar: cal)
        #expect(sections.map(\.title) == ["Today", "Yesterday"])
        // Today: check-in, then the digest where the newest social row was, then the moment.
        #expect(sections[0].rows.count == 3)
        if case .socialDigest(_, let folded) = sections[0].rows[1] {
            #expect(folded.map(\.id) == ["b", "d"])
            #expect(ProfileActivityTimeline.digestTitle(folded) == "1 like, 1 comment")
        } else {
            Issue.record("expected a social digest")
        }
        // Yesterday: a single social row stays a plain row.
        #expect(sections[1].rows == [.single(items[4]), .single(items[5])])
    }

    @Test func dayTitlesUseWeekdayThisYearAndTheYearOtherwise() {
        let sep2 = cal.date(byAdding: .day, value: -19, to: now)!
        #expect(ProfileActivityTimeline.dayTitle(sep2, now: now, calendar: cal) == "Wed, Sep 2")
        let lastYear = cal.date(byAdding: .year, value: -1, to: now)!
        #expect(ProfileActivityTimeline.dayTitle(lastYear, now: now, calendar: cal) == "Sep 21, 2025")
    }

    @Test func rowsAreWordedByType() {
        let checkIn = OwnActivityItem(id: "1", type: "check_in", category: "checkins", timestamp: now, targetName: "Tommy's Tavern",
                                      message: "great wings", rating: 9, companions: ["Brittany"], isPrivate: true)
        #expect(ProfileActivityTimeline.title(for: checkIn) == "Checked in at Tommy's Tavern")
        #expect(ProfileActivityTimeline.detail(for: checkIn) == "with Brittany · rated 9 · “great wings” · Private · only you")

        let place = OwnActivityItem(id: "2", type: "place_added", category: "places", timestamp: now, targetName: "Pasta & Provisions",
                                    circleName: "Date Night", placeAddress: "1528 East Blvd, Charlotte, NC 28203, USA")
        #expect(ProfileActivityTimeline.title(for: place) == "Added Pasta & Provisions to Date Night")
        #expect(ProfileActivityTimeline.detail(for: place) == "Charlotte")

        let moment = OwnActivityItem(id: "3", type: "video_uploaded", category: "moments", timestamp: now, targetName: "Stadium", likeCount: 14, commentCount: 3)
        #expect(ProfileActivityTimeline.title(for: moment) == "Posted a moment at Stadium")
        #expect(ProfileActivityTimeline.detail(for: moment) == "14 likes · 3 comments")

        let postcard = OwnActivityItem(id: "4", type: "postcard_mailed", category: "sent", timestamp: now, targetName: "Mom", recipientName: "Mom", mailStatus: "submitted")
        #expect(ProfileActivityTimeline.title(for: postcard) == "Mailed a postcard to Mom")
        #expect(ProfileActivityTimeline.detail(for: postcard) == "printed, in the mail")

        let fridge = OwnActivityItem(id: "5", type: "fridgemail_sent", category: "sent", timestamp: now, recipientName: "Grandma")
        #expect(ProfileActivityTimeline.title(for: fridge) == "Mailed Grandma a drawing")
        #expect(ProfileActivityTimeline.detail(for: OwnActivityItem(id: "6", type: "check_in", category: "checkins", timestamp: now)) == nil)
    }

    @Test func summaryWordsAndRecap() {
        let summary = OwnActivitySummary(month: "2026-09", counts: .init(checkins: 12, places: 5, moments: 3, sent: 2, social: 9, postcards: 2),
                                         streakWeeks: 4, mostVisited: .init(name: "Tommy's Tavern", count: 5), privateCheckIns: 3, onThisDay: [])
        #expect(ProfileActivityTimeline.summaryLine(summary) == "4-week check-in streak · most visited: Tommy's Tavern · 3 private check-ins")
        #expect(ProfileActivityTimeline.monthName("2026-09", now: now, calendar: cal) == "September")
        #expect(ProfileActivityTimeline.monthName("2025-12", now: now, calendar: cal) == "December 2025")
        #expect(ProfileActivityTimeline.recapText(summary, name: "Wes", now: now, calendar: cal)
                == "Wes's September on FavCircles: 12 check-ins, 5 places added, 3 moments, 2 postcards. Most visited: Tommy's Tavern.")
        let quiet = OwnActivitySummary(month: "2026-09", counts: .init(checkins: 1, places: 0, moments: 0, sent: 0, social: 0, postcards: 0),
                                       streakWeeks: 1, mostVisited: .init(name: "X", count: 1), privateCheckIns: 0, onThisDay: [])
        #expect(ProfileActivityTimeline.summaryLine(quiet) == nil)
    }

    @Test func aRowFromTheServerDecodesWithMissingFields() throws {
        let json = #"{"id":"a1","type":"check_in","category":"checkins","timestamp":"2026-09-25T22:40:00.000Z","targetName":"Tommy's Tavern","isPrivate":true}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let item = try d.decode(OwnActivityItem.self, from: Data(json.utf8))
        #expect(item.isPrivate)
        #expect(item.companions.isEmpty)
        #expect(item.likeCount == nil)
    }
}

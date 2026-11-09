import Foundation
import Testing
@testable import Circles_iOS

/// Swarm import (Wes, 2026-11-09): the zip Foursquare emails after Data
/// download request. The first fixture is the real shape of Wes's export.
struct SwarmExportParserTests {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    /// Wes's export, verbatim apart from the share token
    private let realExport = """
    {"count":1,"items":[{"id":"6aef144fd00cf1214ce930c9","createdAt":"2026-11-07 12:06:39.000000","type":"checkin",\
    "visibility":"private","timeZoneOffset":-300,"canonicalUrl":"https://app.foursquare.com/share/checkin/6aef144fd00cf1214ce930c9",\
    "private":true,"editableUntil":"2126-10-14 12:06:39.000000","venue":{"id":"5ecea99334eba80008b02265","name":"Ilios Crafted Greek",\
    "url":"https://app.foursquare.com/v/ilios-crafted-greek/5ecea99334eba80008b02265"},"comments":{"count":0},\
    "lat":35.216958949672104,"lng":-80.85934366999905,"hacc":8}]}
    """

    private func checkIn(_ venueId: String, _ name: String, _ at: String, lat: Double = 35.2, lng: Double = -80.8, hacc: Double = 20, type: String = "checkin") -> String {
        """
        {"id":"c\(UUID().uuidString.prefix(6))","createdAt":"\(at)","type":"\(type)","venue":{"id":"\(venueId)","name":"\(name)","url":"https://app.foursquare.com/v/x/\(venueId)"},"lat":\(lat),"lng":\(lng),"hacc":\(hacc)}
        """
    }

    private func file(_ items: [String]) -> Data {
        data("{\"count\":\(items.count),\"items\":[\(items.joined(separator: ","))]}")
    }

    @Test func readsTheRealExport() throws {
        let export = try SwarmExportParser.parse(files: [
            ("checkins1.json", data(realExport)),
            ("checkins1.csv", data("ignored")), // the CSV twin is never read alongside the JSON
            ("users.json", data("{}")), ("shares.json", data("{\"count\":0,\"items\":[]}"))
        ])
        #expect(export.checkInCount == 1)
        let ilios = try #require(export.venues.first)
        #expect(ilios.id == "5ecea99334eba80008b02265")
        #expect(ilios.name == "Ilios Crafted Greek")
        #expect(ilios.url == "https://app.foursquare.com/v/ilios-crafted-greek/5ecea99334eba80008b02265")
        #expect(ilios.latitude == 35.216958949672104 && ilios.longitude == -80.85934366999905)
        #expect(ilios.isVenueLocation == false)
        // createdAt is UTC (the export's saves, stamped in epoch seconds, came minutes after)
        #expect(ilios.lastCheckInAt == ISO8601DateFormatter().date(from: "2026-11-07T12:06:39Z"))
    }

    @Test func foldsCheckInsAcrossFilesIntoOneVenueEach() throws {
        let one = file([
            checkIn("v1", "Common Market", "2015-03-01 10:00:00.000000", lat: 35.21, hacc: 65),
            checkIn("v1", "Common Market", "2019-06-01 10:00:00.000000", lat: 35.2101, hacc: 5),
            checkIn("v2", "Starbucks", "2020-01-01 09:00:00.000000", lat: 35.10),
            checkIn("v9", "Shout", "2020-01-01 09:00:00.000000", type: "shout")
        ])
        let two = file([
            checkIn("v1", "Common Market (South End)", "2024-08-08 18:30:00.000000", lat: 35.2102, hacc: 30),
            // Another Starbucks a few miles away: a different venue
            checkIn("v3", "Starbucks", "2021-01-01 09:00:00.000000", lat: 35.30)
        ])
        let export = try SwarmExportParser.parse(files: [("export/checkins1.json", one), ("export/checkins2.json", two)])
        #expect(export.checkInCount == 5)
        #expect(export.venues.map(\.id) == ["v1", "v3", "v2"]) // most-visited, then most recent
        let market = export.venues[0]
        #expect(market.checkInCount == 3)
        #expect(market.name == "Common Market (South End)") // the newest name
        #expect(market.latitude == 35.2101) // the most accurate spot (5 m)
        #expect(market.firstCheckInAt == ISO8601DateFormatter().date(from: "2015-03-01T10:00:00Z"))
        #expect(market.lastCheckInAt == ISO8601DateFormatter().date(from: "2024-08-08T18:30:00Z"))
    }

    @Test func readsTheCSVWhenThereIsNoJSON() throws {
        let csv = #"""
        "id","createdAt","type","visibility","timeZoneOffset","canonicalUrl","private","editableUntil","venue.id","venue.name","venue.url","comments.count","lat","lng","hacc"
        "a1","2026-11-07 12:06:39.000000","checkin","private","-300","https://x","true","2126-10-14 12:06:39.000000","5ecea99334eba80008b02265","Ilios Crafted Greek","https://app.foursquare.com/v/ilios","0","35.216958949672104","-80.85934366999905","8"
        "a2","2025-01-02 20:00:00.000000","checkin","private","-300","https://x","true","","5ecea99334eba80008b02265","Ilios Crafted Greek","https://app.foursquare.com/v/ilios","0","35.2170","-80.8594","40"
        "a3","2025-01-03 20:00:00.000000","checkin","private","-300","https://x","true","","v7","Tony's, Pizza ""Place""","https://app.foursquare.com/v/tonys","0","35.3","-80.9","10"
        """#
        let export = try SwarmExportParser.parse(files: [("checkins1.csv", data(csv))])
        #expect(export.venues.count == 2)
        #expect(export.venues[0].checkInCount == 2)
        #expect(export.venues[0].latitude == 35.216958949672104)
        #expect(export.venues[1].name == "Tony's, Pizza \"Place\"")
    }

    @Test func readsAnOlderExportWithTheVenueLocationAndEpochTimes() throws {
        let old = """
        {"items":[{"id":"x","createdAt":1388592000,"type":"checkin","venue":{"id":"v5","name":"The Diamond",
        "location":{"lat":35.22,"lng":-80.81,"address":"1901 Commonwealth Ave","city":"Charlotte","state":"NC","postalCode":"28205","country":"United States"},
        "categories":[{"name":"Diner","primary":true}]}}]}
        """
        let venue = try #require(try SwarmExportParser.parse(files: [("checkins.json", data(old))]).venues.first)
        #expect(venue.isVenueLocation)
        #expect(venue.latitude == 35.22)
        #expect(venue.address == "1901 Commonwealth Ave, Charlotte, NC, 28205, United States")
        #expect(venue.category == "Diner")
        #expect(venue.firstCheckInAt == Date(timeIntervalSince1970: 1388592000))
    }

    @Test func refusesFilesThatAreNotASwarmExport() {
        #expect(throws: SwarmExportParser.Failure.noCheckInFiles) {
            try SwarmExportParser.parse(files: [("Saved Places.json", data("{}")), ("users.csv", data("a,b"))])
        }
        #expect(throws: SwarmExportParser.Failure.noCheckIns) {
            try SwarmExportParser.parse(files: [("checkins1.json", data("{\"count\":0,\"items\":[]}"))])
        }
    }

    @Test func knowsItsFiles() {
        #expect(SwarmExportParser.checkInsFileKind("checkins1.json") == "json")
        #expect(SwarmExportParser.checkInsFileKind("data-export/checkins12.CSV") == "csv")
        #expect(SwarmExportParser.checkInsFileKind("checkins.json") == "json")
        #expect(SwarmExportParser.checkInsFileKind("__MACOSX/._checkins1.json") == nil)
        #expect(SwarmExportParser.checkInsFileKind("checkinsBackup.json") == nil)
        #expect(SwarmExportParser.checkInsFileKind("checkins1.txt") == nil)
        #expect(SwarmExportParser.isSwarmExport(fileNames: ["readme.html", "checkins1.json", "users.json"]))
        #expect(!SwarmExportParser.isSwarmExport(fileNames: ["Saved Places.json"]))
    }

    @Test func becomesImportCandidatesWithTheirHistory() throws {
        let export = try SwarmExportParser.parse(files: [("checkins1.json", data(realExport))])
        let list = ImportParsingService.swarmList(from: export)
        #expect(list.name == "Swarm check-ins")
        let ilios = try #require(list.places.first)
        #expect(ilios.sourceExternalId == "5ecea99334eba80008b02265")
        #expect(ilios.needsVenueLookup) // the phone's spot, not the venue's
        #expect(ilios.address == nil)
        #expect(ilios.lat == 35.216958949672104)
        #expect(ilios.checkIns == ImportCheckInHistory(count: 1, firstAt: "2026-11-07T12:06:39Z", lastAt: "2026-11-07T12:06:39Z"))
        let body = ilios.asRequestBody
        #expect((body["checkIns"] as? [String: Any])?["count"] as? Int == 1)
    }

    @Test func reviewRowsSayTheHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-09T12:00:00Z")!
        let last = ISO8601DateFormatter().date(from: "2026-11-07T12:06:39Z")!
        let locale = Locale(identifier: "en_US")
        #expect(SwarmImportCopy.historyLine(count: 12, last: last, now: now, calendar: calendar, locale: locale) == "12 check-ins · last Nov 7")
        #expect(SwarmImportCopy.historyLine(count: 1, last: nil) == "1 check-in")
        #expect(SwarmImportCopy.historySentence(0) == nil)
        #expect(SwarmImportCopy.historySentence(1) == "Your Swarm check-in history is on 1 place.")
        #expect(ImportCheckInHistory(count: 1, firstAt: "2026-11-07T12:06:39Z", lastAt: "2026-11-07T12:06:39.000Z").lastDate == last)
    }
}

struct SwarmCheckInHistoryLineTests {
    @Test func thePlacePageSaysWhatCameFromSwarm() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-09T12:00:00Z")!
        let last = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
        let locale = Locale(identifier: "en_US")
        let line = { (count: Int, imported: Int?) in
            CheckInHistoryFormatter.line(for: CheckInStats(count: count, firstCheckInAt: nil, lastCheckInAt: last, importedCount: imported),
                                         now: now, calendar: calendar, locale: locale)
        }
        #expect(line(12, 12) == "Checked in 12 times on Swarm · last Nov 7")
        #expect(line(14, 12) == "Checked in 14 times (12 on Swarm) · last Nov 7")
        #expect(line(3, 0) == "Checked in 3 times · last Nov 7")
        #expect(line(3, nil) == "Checked in 3 times · last Nov 7")
    }
}

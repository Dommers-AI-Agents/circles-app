import Foundation
import Testing
@testable import Circles_iOS

/// The Locals tab's search box (Wes, 2026-11-04: "Panthers football")
struct LocalsSearchTests {
    private func event(_ id: String, _ name: String, date: String, time: String? = "13:00:00",
                       source: String = "ticketmaster", venue: String? = "Bank of America Stadium") -> NearbyEvent {
        let json: [String: Any?] = ["id": id, "source": source, "name": name, "startLocalDate": date,
                                    "startLocalTime": time, "venueName": venue, "category": "Football",
                                    "url": "https://example.com/\(id)"]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(NearbyEvent.self, from: data)
    }

    @Test func everyWordAnywhereAnyCaseOrAccent() {
        let game = event("a", "Carolina Panthers v Denver Broncos", date: "2026-11-08")
        #expect(LocalsSearch.matches(game, query: "panthers FOOTBALL"))
        #expect(LocalsSearch.matches(game, query: "bank panthers"))
        #expect(!LocalsSearch.matches(game, query: "panthers hockey"))
        #expect(!LocalsSearch.matches(game, query: "   "))
        #expect(LocalsSearch.matches(["Café Monté"], query: "cafe monte"))
    }

    @Test func serverAnswerPlusTabMatchesStoresFirstThenSoonest() {
        let remote = [event("tm_2", "Panthers v Ravens", date: "2026-11-22"),
                      event("tm_1", "Panthers v Broncos", date: "2026-11-08")]
        let local = [event("tm_1", "Panthers v Broncos", date: "2026-11-08"),
                     event("store_1", "Panthers watch party", date: "2026-11-30", source: "store", venue: "Sal's")]
        let merged = LocalsSearch.mergeEvents(local: local, remote: remote)
        #expect(merged.map(\.id) == ["store_1", "tm_1", "tm_2"])
    }
}

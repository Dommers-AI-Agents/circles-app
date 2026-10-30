import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Places, circles and locations shared in a chat (2026-10-30).
struct MessageShareCardTests {
    @Test func aSharedPlaceRoundTripsToACardThatOpensIt() {
        let out = MessageShareCard.place(id: "gp1", name: "Pasta & Provisions", address: "1600 S Mint St",
                                         photoURL: "https://x/p.jpg", coordinate: .init(latitude: 35.2, longitude: -80.8))
        #expect(out.type == .placeShare && out.content == "📍 Pasta & Provisions")
        let card = try! #require(MessageShareCard(type: out.type, metadata: out.metadata))
        #expect(card.title == "Pasta & Provisions" && card.subtitle == "1600 S Mint St" && card.imageURL == "https://x/p.jpg")
        #expect(card.target == .place(id: "gp1", coordinate: .init(latitude: 35.2, longitude: -80.8)))
        #expect(card.caption == "📍 Pasta & Provisions\n1600 S Mint St")
    }

    @Test func anAppleMapsPlaceNobodySavedOpensItsCoordinate() {
        let out = MessageShareCard.place(id: nil, name: "Flower Child", address: nil, photoURL: nil,
                                         coordinate: .init(latitude: 35.21, longitude: -80.85))
        let card = try! #require(MessageShareCard(type: out.type, metadata: out.metadata))
        #expect(card.imageURL == nil && card.mapCoordinate?.latitude == 35.21)
        #expect(card.target == .place(id: nil, coordinate: .init(latitude: 35.21, longitude: -80.85)))
    }

    @Test func circlesAndLocations() {
        let circle = MessageShareCard.circle(id: "c1", name: "Charlotte NC", placeCount: 90, coverURL: nil)
        let c = try! #require(MessageShareCard(type: circle.type, metadata: circle.metadata))
        #expect(c.subtitle == "90 places" && c.target == .circle(id: "c1"))
        let loc = MessageShareCard.location(.init(latitude: 35.2, longitude: -80.8), address: "South End, Charlotte")
        let l = try! #require(MessageShareCard(type: loc.type, metadata: loc.metadata))
        #expect(l.title == "My location" && l.subtitle == "South End, Charlotte" && l.mapCoordinate != nil)
    }

    @Test func numbersFromTheServerInAnyShapeAndBadDataIsNoCard() {
        // The server may hand numbers back as strings
        let card = MessageShareCard(type: .location, metadata: ["lat": "35.2", "lng": "-80.8"])
        #expect(card?.mapCoordinate?.longitude == -80.8)
        #expect(MessageShareCard(type: .location, metadata: ["lat": 200, "lng": 0]) == nil)
        #expect(MessageShareCard(type: .placeShare, metadata: [:]) == nil)
        #expect(MessageShareCard(type: .text, metadata: ["placeName": "x"]) == nil)
    }
}

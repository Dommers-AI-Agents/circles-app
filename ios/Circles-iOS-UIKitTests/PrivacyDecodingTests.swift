import Testing
import Foundation
@testable import Circles_iOS

/// What happens when the server sends a privacy value this build has never
/// heard of.
///
/// This used to throw. Circle and place lists decode lossily, so the row simply
/// disappeared from the list; moments have no lossy wrapper, so one such value
/// emptied a whole feed. Both failed silently and looked like data loss.
struct PrivacyDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Known values still decode

    @Test func knownValuesDecodeToTheirTier() throws {
        #expect(try decode(PrivacyLevel.self, "\"innerCircle\"") == .innerCircle)
        #expect(try decode(PrivacyLevel.self, "\"myNetwork\"") == .myNetwork)
        #expect(try decode(PlacePrivacy.self, "\"innerCircle\"") == .innerCircle)
        #expect(try decode(PlacePrivacy.self, "\"followCircle\"") == .followCirclePrivacy)
        #expect(try decode(VideoVisibility.self, "\"innerCircle\"") == .innerCircle)
        #expect(try decode(VideoVisibility.self, "\"followers\"") == .followers)
    }

    // MARK: - Unknown values land on .unknown rather than throwing

    @Test func unknownValuesDecodeWithoutThrowing() throws {
        #expect(try decode(PrivacyLevel.self, "\"someFutureTier\"") == .unknown)
        #expect(try decode(PlacePrivacy.self, "\"someFutureTier\"") == .unknown)
        #expect(try decode(VideoVisibility.self, "\"someFutureTier\"") == .unknown)
    }

    /// Fail closed: an unrecognised tier must never present as more open than
    /// it is, and must offer no picker selection that could save over it.
    @Test func unknownPresentsAsPrivateAndOffersNoSelection() {
        #expect(PrivacyLevel.unknown.tier == nil)
        #expect(PlacePrivacy.unknown.option == nil)
        #expect(VideoVisibility.unknown.option == nil)
        #expect(PlacePrivacy.unknown.displayName == PrivacyTier.private.title)
        #expect(PlacePrivacy.unknown.systemIconName == PrivacyTier.private.systemIconName)
        #expect(VideoVisibility.unknown.displayLabel == PrivacyTier.private.title)
    }

    /// `unknown` sorts most restrictive so it never wins a comparison against
    /// a real tier and get treated as the looser of the two.
    @Test func unknownSortsMostRestrictive() {
        #expect(PrivacyLevel.private < PrivacyLevel.unknown)
        #expect(PrivacyLevel.public < PrivacyLevel.unknown)
        #expect(max(PrivacyLevel.public, .unknown) == .unknown)
    }

    // MARK: - The bug this is really guarding

    @Test func aCircleWithAnUnknownTierStillDecodes() throws {
        let json = """
        {
          "_id": "c1",
          "name": "Date Nights",
          "owner": "u1",
          "privacy": "someFutureTier",
          "category": "food",
          "createdAt": "2026-09-18T00:00:00.000Z",
          "updatedAt": "2026-09-18T00:00:00.000Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let circle = try decoder.decode(Circle.self, from: Data(json.utf8))
        #expect(circle.name == "Date Nights")
        #expect(circle.privacy == .unknown)
    }

    /// The moments equivalent: PlaceVideo has no lossy array wrapper, so an
    /// unrecognised value here used to fail the whole response.
    @Test func momentsKeepTheirOwnSpellingForConnections() throws {
        #expect(try decode(VideoVisibility.self, "\"network\"") == .network)
        #expect(VideoVisibility.network.displayLabel == PrivacyTier.connections.title)
        // "Only Me" is the wording moments have always used for private.
        #expect(VideoVisibility.private.displayLabel == "Only Me")
    }
}

import Testing
import Foundation
@testable import Circles_iOS

/// The account-level "who can see my activity" grid: its wire format, its
/// lenient decoding, the one-box toggle, and the summary line under each row.
struct ActivityPrivacyGridTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func user(_ extra: String) -> String {
        """
        {"_id": "u1", "displayName": "Brit"\(extra.isEmpty ? "" : ", " + extra)}
        """
    }

    // MARK: - Wire format

    @Test func rawValuesMatchTheBackendKeys() {
        #expect(ActivityPrivacyCategory.allCases.map(\.rawValue) ==
                ["checkIns", "photos", "moments", "savedPlaces", "likesComments", "circles"])
        #expect(ActivityAudience.allCases.map(\.rawValue) == ["public", "myNetwork", "innerCircle"])
    }

    @Test func audiencesBorrowTheLadderCopy() {
        #expect(ActivityAudience.public.title == PrivacyTier.public.title)
        #expect(ActivityAudience.myNetwork.title == "Connections")
        #expect(ActivityAudience.innerCircle.systemIconName == PrivacyTier.innerCircle.systemIconName)
    }

    @Test func requestBodyIsSixRowsOfThreeBooleans() {
        let body = ActivityPrivacy.allAllowed.toggled(category: .checkIns, audience: .public).requestBody()
        #expect(body.count == 6)
        #expect(Set(body.keys) == Set(ActivityPrivacyCategory.allCases.map(\.rawValue)))
        for (_, value) in body {
            let row = value as? [String: Bool]
            #expect(row?.count == 3)
            #expect(row.map { Set($0.keys) } == Set(ActivityAudience.allCases.map(\.rawValue)))
        }
        let checkIns = body["checkIns"] as? [String: Bool]
        #expect(checkIns?["public"] == false)
        #expect(checkIns?["myNetwork"] == true)
    }

    // MARK: - Defaults and lenient decoding

    /// Wes, 2026-09-25: check-ins, photos and moments reach connections by
    /// default; saved places, likes & comments and circles reach everyone.
    @Test func theStandardGridIsConnectionsForDoingsAndEveryoneForCuration() {
        let grid = ActivityPrivacy.standard
        for category in [ActivityPrivacyCategory.checkIns, .photos, .moments] {
            #expect(!grid.allows(category, .public))
            #expect(grid.allows(category, .myNetwork))
            #expect(grid.allows(category, .innerCircle))
            #expect(grid.summary(for: category, innerCircleIsEmpty: false) == "Connections")
        }
        for category in [ActivityPrivacyCategory.savedPlaces, .likesComments, .circles] {
            #expect(grid.allows(category, .public))
            #expect(grid.summary(for: category, innerCircleIsEmpty: false) == "Everyone")
        }
        #expect(grid.isDefault)
        #expect(!ActivityPrivacy.allAllowed.isDefault)
    }

    @Test func partialJSONFillsTheGapsWithTheCategoryDefault() throws {
        let grid = try decode(ActivityPrivacy.self, #"{"checkIns": {"public": true}}"#)
        #expect(grid.checkIns.public == true)
        #expect(grid.checkIns.myNetwork == true)
        #expect(grid.checkIns.innerCircle == true)
        #expect(grid.photos == .connections)
        #expect(grid.circles == .allAllowed)
        #expect(!grid.isDefault)
    }

    @Test func malformedRowsAndBoxesReadAsTheStandard() throws {
        let grid = try decode(ActivityPrivacy.self, #"{"checkIns": "nope", "photos": {"public": "yes", "moments": 3}}"#)
        // A malformed box inside a present row reads as true (the row was sent).
        #expect(grid.checkIns == .connections)
        #expect(grid.photos == .allAllowed)
        #expect(grid.moments == .connections)
        let scalar = try decode(ActivityPrivacy.self, #""nonsense""#)
        #expect(scalar == .standard)
    }

    @Test func roundTripsThroughCodable() throws {
        let original = ActivityPrivacy.allAllowed
            .toggled(category: .checkIns, audience: .public)
            .toggled(category: .checkIns, audience: .myNetwork)
            .toggled(category: .circles, audience: .public)
        let data = try JSONEncoder().encode(original)
        let back = try decode(ActivityPrivacy.self, String(decoding: data, as: UTF8.self))
        #expect(back == original)
    }

    // MARK: - Through the User model

    @Test func userDecodesWithoutAGrid() throws {
        let u = try decode(User.self, user(""))
        #expect(u.activityPrivacy == nil)
        #expect((u.activityPrivacy ?? .standard).isDefault)
    }

    @Test func userDecodesWithAGrid() throws {
        let u = try decode(User.self, user(#""activityPrivacy": {"photos": {"public": false, "myNetwork": false}}"#))
        let grid = try #require(u.activityPrivacy)
        #expect(grid.photos.public == false)
        #expect(grid.photos.myNetwork == false)
        #expect(grid.photos.innerCircle == true)
        #expect(grid.checkIns == .connections)
    }

    @Test func userSurvivesAMalformedGrid() throws {
        let u = try decode(User.self, user(#""activityPrivacy": 42"#))
        #expect(u.displayName == "Brit")
        #expect(u.activityPrivacy == nil || u.activityPrivacy == .standard)
    }

    @Test func userCopyCarriesTheGrid() {
        let grid = ActivityPrivacy.allAllowed.toggled(category: .moments, audience: .public)
        let base = User(id: "u1", displayName: "Brit", profilePicture: nil, bio: nil, location: nil, friends: nil, friendRequests: nil)
        #expect(base.activityPrivacy == nil)
        let withGrid = base.copy(activityPrivacy: grid)
        #expect(withGrid.activityPrivacy == grid)
        #expect(withGrid.copy(displayName: "B").activityPrivacy == grid)
    }

    // MARK: - Toggling

    @Test func toggledFlipsExactlyOneBox() {
        let grid = ActivityPrivacy.allAllowed.toggled(category: .savedPlaces, audience: .public)
        #expect(!grid.allows(.savedPlaces, .public))
        for category in ActivityPrivacyCategory.allCases {
            for audience in ActivityAudience.allCases where !(category == .savedPlaces && audience == .public) {
                #expect(grid.allows(category, audience), "\(category) \(audience) should be untouched")
            }
        }
        #expect(grid.toggled(category: .savedPlaces, audience: .public) == .allAllowed)
    }

    /// Everyone on an Inner Circle list is a connection, and the server shows a
    /// row to anyone qualifying for any checked column. So while Connections is
    /// checked, Inner Circle is checked whether the box says so or not.
    @Test func innerCircleIsImpliedByConnections() throws {
        // Unchecking Inner Circle while Connections is on is refused.
        let refused = ActivityPrivacy.allAllowed.toggled(category: .checkIns, audience: .innerCircle)
        #expect(refused == .allAllowed)
        #expect(refused.isImplied(.checkIns, .innerCircle))

        // Turn Connections off, then Inner Circle can come off.
        let noConnections = ActivityPrivacy.allAllowed.toggled(category: .checkIns, audience: .myNetwork)
        #expect(!noConnections.isImplied(.checkIns, .innerCircle))
        #expect(noConnections.allows(.checkIns, .innerCircle))
        let noInner = noConnections.toggled(category: .checkIns, audience: .innerCircle)
        #expect(!noInner.allows(.checkIns, .innerCircle))

        // Checking Connections again re-checks Inner Circle.
        let back = noInner.toggled(category: .checkIns, audience: .myNetwork)
        #expect(back.allows(.checkIns, .myNetwork))
        #expect(back.allows(.checkIns, .innerCircle))
        #expect(back.isImplied(.checkIns, .innerCircle))

        // A grid the server sent with the box unchecked reads, and is sent
        // back, as checked — the cell, summary and payload agree.
        let fromServer = try decode(ActivityPrivacy.self, #"{"photos": {"myNetwork": true, "innerCircle": false}}"#)
        #expect(fromServer.photos.innerCircle == false)
        #expect(fromServer.allows(.photos, .innerCircle))
        #expect(fromServer.isImplied(.photos, .innerCircle))
        let sent = fromServer.requestBody()["photos"] as? [String: Bool]
        #expect(sent?["innerCircle"] == true)
        #expect(fromServer.isDefault)
        #expect(fromServer.normalized == .allAllowed)

        // ...and unchecking Connections on it leaves Inner Circle checked, as
        // the box showed, rather than dropping to the stored false.
        let offConnections = fromServer.toggled(category: .photos, audience: .myNetwork)
        #expect(!offConnections.allows(.photos, .myNetwork))
        #expect(offConnections.allows(.photos, .innerCircle))
        let innerOnly = offConnections.toggled(category: .photos, audience: .public)
        #expect(innerOnly.summary(for: .photos, innerCircleIsEmpty: false) == "Inner Circle")
    }

    // MARK: - Summary line

    @Test func summaryNamesTheWidestAudienceThatIsChecked() {
        let all = ActivityPrivacy.allAllowed
        #expect(all.summary(for: .checkIns, innerCircleIsEmpty: false) == "Everyone")

        let connections = all.toggled(category: .checkIns, audience: .public)
        #expect(connections.summary(for: .checkIns, innerCircleIsEmpty: false) == "Connections")
        #expect(connections.summary(for: .checkIns, innerCircleIsEmpty: true) == "Connections")

        let innerOnly = connections.toggled(category: .checkIns, audience: .myNetwork)
        #expect(innerOnly.summary(for: .checkIns, innerCircleIsEmpty: false) == "Inner Circle")

        let nobody = innerOnly.toggled(category: .checkIns, audience: .innerCircle)
        #expect(nobody.summary(for: .checkIns, innerCircleIsEmpty: false) == "Only you")
        #expect(!nobody.checkIns.allowsAnyone)

        // Other rows keep their own line.
        #expect(nobody.summary(for: .photos, innerCircleIsEmpty: false) == "Everyone")
    }

    @Test func anEmptyInnerCircleReadsOnlyYou() {
        let innerOnly = ActivityPrivacy.allAllowed
            .toggled(category: .moments, audience: .public)
            .toggled(category: .moments, audience: .myNetwork)
        #expect(innerOnly.allows(.moments, .innerCircle))
        #expect(innerOnly.summary(for: .moments, innerCircleIsEmpty: true) == "Only you")
    }

    @Test func copyIsFilledIn() {
        #expect(ActivityPrivacy.Copy.footer.contains("only you"))
        #expect(!ActivityPrivacy.Copy.emptyInnerCircleTitle.isEmpty)
        #expect(!ActivityPrivacy.Copy.emptyInnerCircleDetail.isEmpty)
        #expect(Set(ActivityPrivacyCategory.allCases.map(\.title)).count == ActivityPrivacyCategory.allCases.count)
    }
}

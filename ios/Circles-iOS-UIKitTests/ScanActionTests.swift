import Foundation
import Testing
@testable import Circles_iOS

/// Scan Actions (2026-11-11): "scan this QR and it adds this place to your
/// profile". Links, the stash while the app isn't ready, what a scanned code
/// does, and the words around it.
struct ScanActionLinkTests {
    @Test func codesAreEightEasyCharactersOrAGuideName() {
        #expect(ScanActionLink.code("ab7k2mqz") == "AB7K2MQZ")
        #expect(ScanActionLink.code(" AB7K2MQZ\n") == "AB7K2MQZ")
        #expect(ScanActionLink.code("AB0K2MQZ") == nil) // no zero
        #expect(ScanActionLink.code("AB1K2MQZ") == nil) // no one
        #expect(ScanActionLink.code("Share-A-Place") == "share-a-place")
        #expect(ScanActionLink.code("store-") == nil)
        #expect(ScanActionLink.code("../etc") == nil)
        #expect(ScanActionLink.code("") == nil)
        #expect(ScanActionLink.url(code: "AB7K2MQZ").absoluteString == "https://api.favcircles.com/q/AB7K2MQZ")
    }

    @Test func theWebPageLeavesTheCodeOnThePasteboard() {
        #expect(ScanActionLink.code(fromPasteboard: "favcircles-scan:AB7K2MQZ") == "AB7K2MQZ")
        #expect(ScanActionLink.code(fromPasteboard: "favcircles-sticker:JOINUS") == nil)
        #expect(ScanActionLink.code(fromPasteboard: nil) == nil)
    }

    @Test func everyLinkShapeOpensTheCode() {
        let router = DeepLinkRouter()
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/q/AB7K2MQZ")!) == .scanAction(code: "AB7K2MQZ"))
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/q/see-widgets")!) == .scanAction(code: "see-widgets"))
        #expect(router.destination(for: URL(string: "circles://q/AB7K2MQZ")!) == .scanAction(code: "AB7K2MQZ"))
        #expect(router.destination(for: URL(string: "circles:///q/AB7K2MQZ")!) == .scanAction(code: "AB7K2MQZ"))
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/q/")!) == nil)
        #expect(router.destination(for: URL(string: "https://api.favcircles.com/q/not*a*code")!) == nil)
    }

    @Test func aCodeThatArrivesEarlyWaits() {
        #expect(PendingLinkParser.parse("scan:AB7K2MQZ") == .scanAction(code: "AB7K2MQZ"))
        #expect(PendingLinkParser.parse("scan:share-a-place") == .scanAction(code: "share-a-place"))
        #expect(PendingLinkParser.parse("scan:bad*code") == nil)
    }

    @Test func theSharePagesAppLinkKeepsTheSharer() {
        let router = DeepLinkRouter()
        #expect(router.destination(for: URL(string: "circles://place/p1?ref=u9")!) == .place(id: "p1", refUserId: "u9"))
        #expect(router.destination(for: URL(string: "circles://place/p1")!) == .placeFromExtension(id: "p1"))
    }

    @Test func aSharedPlaceKeepsItsSharerThroughSignIn() {
        #expect(PendingLinkParser.parse("place:p1") == .place(id: "p1", refUserId: nil))
        #expect(PendingLinkParser.parse("place:p1:u9") == .place(id: "p1", refUserId: "u9"))
    }
}

struct ScanActionPlanTests {
    private func place(_ id: String, saved: Bool = false) -> ScanAction.Place {
        ScanAction.Place(globalPlaceId: id, name: "Place \(id)", address: nil, category: "restaurant", photoUrl: nil,
                         location: nil, googlePlaceId: nil, applePlaceId: nil, alreadySaved: saved,
                         savedPlaceId: saved ? "s\(id)" : nil, savedCircleId: nil)
    }
    private let wes = ScanAction.Creator(id: "wes", displayName: "Wes", profilePicture: nil)

    @Test func placesTheyDontHaveComeTicked() {
        let action = ScanAction(code: "AB7K2MQZ", kind: .placeSet, creator: wes, places: [place("a"), place("b", saved: true), place("c")])
        #expect(ScanActionPlan.plan(for: action) == .review(places: action.places, preselected: ["a", "c"]))
    }

    @Test func allSavedExpiredAndEmpty() {
        let all = ScanAction(code: "AB7K2MQZ", kind: .place, places: [place("a", saved: true)])
        #expect(ScanActionPlan.plan(for: all) == .alreadyHaveAll(places: all.places))
        let old = ScanAction(code: "AB7K2MQZ", kind: .place, expired: true, creator: wes, places: [place("a")])
        #expect(ScanActionPlan.plan(for: old) == .expired(from: "Wes"))
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .placeSet)) == .nothingLeft)
    }

    @Test func guidesOpenTheirScreenAndUnknownOnesAskForAnUpdate() {
        let guide = { (raw: String) in ScanAction(code: "x-guide", kind: .guide, guide: .init(id: "x", appGuide: raw, title: "X", blurb: nil)) }
        #expect(ScanActionPlan.plan(for: guide("widgets")) == .guide(.widgets))
        #expect(ScanActionPlan.plan(for: guide("sharePlace")) == .guide(.sharePlace))
        #expect(ScanActionPlan.plan(for: guide("ownPlace")) == .updateApp) // not a scannable guide
        #expect(ScanActionPlan.plan(for: guide("somethingNew")) == .updateApp)
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .unknown)) == .updateApp)
    }

    @Test func storeSetup() {
        let store = { (redeemed: Bool, mine: Bool) in
            ScanAction.Store(venueId: "v1", globalPlaceId: "g1", googlePlaceId: nil, name: "Sal's", address: nil,
                             redeemed: redeemed, redeemedByViewer: mine)
        }
        #expect(ScanActionPlan.plan(for: ScanAction(code: "store-setup", kind: .storeSetup)) == .claimStore)
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .storeSetup, store: store(false, false))) == .redeemStore(name: "Sal's"))
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .storeSetup, store: store(true, true))) == .manageStore(venueId: "v1"))
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .storeSetup, store: store(true, false))) == .storeTaken(name: "Sal's"))
        #expect(ScanActionPlan.plan(for: ScanAction(code: "AB7K2MQZ", kind: .storeSetup, expired: true, store: store(false, false))) == .expired(from: nil))
    }

    @Test func theServersAnswerDecodes() throws {
        let json = #"""
        {"code":"AB7K2MQZ","kind":"placeSet","url":"https://api.favcircles.com/q/AB7K2MQZ","title":"Brunch","note":null,
         "expired":false,"expiresAt":"2026-12-11T18:00:00.000Z","creator":{"id":"wes","displayName":"Wes","profilePicture":null},
         "guide":null,"store":null,"places":[{"globalPlaceId":"g1","name":"Over Easy","address":"1 Main St","category":"restaurant",
         "photoUrl":null,"location":{"lat":33.3,"lng":-111.84},"googlePlaceId":null,"applePlaceId":"I1","alreadySaved":false,
         "savedPlaceId":null,"savedCircleId":null}]}
        """#
        let action = try JSONDecoder().decode(ScanAction.self, from: Data(json.utf8))
        #expect(action.kind == .placeSet)
        #expect(action.places.first?.location == ScanAction.Spot(lat: 33.3, lng: -111.84))
        let newer = try JSONDecoder().decode(ScanAction.self, from: Data(#"{"code":"AB7K2MQZ","kind":"teleport"}"#.utf8))
        #expect(newer.kind == .unknown)
        #expect(newer.places.isEmpty)
    }
}

struct ScanActionCopyTests {
    private func row(_ name: String, circle: String? = nil, upgrade: Bool = false) -> ScanActionSaveResult.Saved {
        .init(globalPlaceId: name, name: name, placeId: "p", circleId: nil, circleName: circle, message: nil, upgradeRequired: upgrade)
    }

    @Test func whatASaveSays() {
        let one = ScanActionSaveResult(circleId: "c", saved: [row("Over Easy")], alreadySaved: [], failed: [])
        #expect(ScanActionCopy.saved(one, circleName: "Brunch").title == "Saved Over Easy to Brunch")
        let some = ScanActionSaveResult(circleId: "c", saved: [row("A"), row("B")], alreadySaved: [row("C", circle: "Coffee")], failed: [])
        let words = ScanActionCopy.saved(some, circleName: "Brunch")
        #expect(words.title == "Saved 2 places to Brunch")
        #expect(words.message == "You already had C in Coffee.")
        let full = ScanActionSaveResult(circleId: "c", saved: [], alreadySaved: [], failed: [row("A", upgrade: true), row("B", upgrade: true)])
        #expect(ScanActionCopy.saved(full, circleName: nil).message.contains("plan is full"))
    }

    @Test func theCreatorHearsWhatWasLeftOut() {
        #expect(ScanActionCopy.leftOut(privateCount: 0, hiddenCount: 0) == nil)
        #expect(ScanActionCopy.leftOut(privateCount: 2, hiddenCount: 1) == "2 private places left out · 1 place that can't be shared yet left out")
        #expect(ScanActionCopy.capped(total: 60, max: 50) == "The first 50 of 60 places go in the QR.")
        #expect(ScanActionCopy.capped(total: 50, max: 50) == nil)
        #expect(ScanActionCopy.setTitle(circleName: "Brunch", category: nil, tag: "patio") == "Brunch: patio")
    }

    @Test func everyScannableGuideHasItsWords() {
        for kind in [ScreenGuideKind.sharePlace, .makeCircle, .widgets, .storeSetup, .storeManage, .addPlace, .checkIn, .rewards] {
            #expect(!ScreenGuideCopy.stops(kind).isEmpty)
            #expect(!ScreenGuideCopy.finish(kind).back.isEmpty)
        }
        #expect(ScreenGuideCopy.stops(.storeManage).count == 4)
        #expect(ScreenGuideCopy.stops(.sharePlace, placeName: "Over Easy").first?.title == "Share Over Easy")
    }
}

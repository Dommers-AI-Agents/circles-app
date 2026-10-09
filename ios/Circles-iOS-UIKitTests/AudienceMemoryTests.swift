import Testing
import Foundation
@testable import Circles_iOS

/// The last audience a share went to opens the next one (Wes, 2026-10-09).
struct AudienceMemoryTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AudienceMemoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func tiersAndListsRoundTrip() {
        let plain = AudienceMemory.Choice(tier: "followers", listId: nil)
        let listed = AudienceMemory.Choice(tier: "innerCircle", listId: "list_abc-1")
        #expect(AudienceMemory.encode(plain) == "followers")
        #expect(AudienceMemory.encode(listed) == "innerCircle:list_abc-1")
        #expect(AudienceMemory.decode("followers") == plain)
        #expect(AudienceMemory.decode("innerCircle:list_abc-1") == listed)
        #expect(AudienceMemory.decode("innerCircle:") == AudienceMemory.Choice(tier: "innerCircle", listId: nil))
        #expect(AudienceMemory.decode("") == nil)
        #expect(AudienceMemory.decode(nil) == nil)
    }

    @Test func aListThatIsGoneFallsBack() {
        let saved = AudienceMemory.Choice(tier: "innerCircle", listId: "family")
        #expect(AudienceMemory.resolve(saved, usableListIds: ["family", "work"]) == saved)
        // Deleted, or everyone taken off it (usable lists only hold lists with people)
        #expect(AudienceMemory.resolve(saved, usableListIds: ["work"]) == nil)
        #expect(AudienceMemory.resolve(saved, usableListIds: []) == nil)
    }

    @Test func beforeTheListsLoadTheChoiceIsKept() {
        let saved = AudienceMemory.Choice(tier: "innerCircle", listId: "family")
        #expect(AudienceMemory.resolve(saved, usableListIds: nil) == saved)
    }

    @Test func tiersWithoutAListNeverDependOnLists() {
        let saved = AudienceMemory.Choice(tier: "public", listId: nil)
        #expect(AudienceMemory.resolve(saved, usableListIds: []) == saved)
        #expect(AudienceMemory.resolve(nil, usableListIds: ["x"]) == nil)
    }

    @Test func savedPerScreenAndPerAccount() {
        let defaults = freshDefaults()
        let moment = AudienceMemory.Choice(tier: "innerCircle", listId: "family")
        let circle = AudienceMemory.Choice(tier: "myNetwork", listId: nil)
        AudienceMemory.save(moment, for: .moment, userId: "u1", defaults: defaults)
        AudienceMemory.save(circle, for: .newCircle, userId: "u1", defaults: defaults)
        #expect(AudienceMemory.load(.moment, userId: "u1", defaults: defaults) == moment)
        #expect(AudienceMemory.load(.newCircle, userId: "u1", defaults: defaults) == circle)
        // Another account on the same phone starts fresh
        #expect(AudienceMemory.load(.moment, userId: "u2", defaults: defaults) == nil)
        // Signed out: nothing read, nothing written
        AudienceMemory.save(moment, for: .moment, userId: nil, defaults: defaults)
        #expect(AudienceMemory.load(.moment, userId: nil, defaults: defaults) == nil)
    }

    @Test func storedTiersAreTheScreensOwnRawValues() {
        #expect(VideoVisibility(rawValue: AudienceMemory.decode("followers")!.tier) == .followers)
        #expect(PrivacyTier(rawValue: AudienceMemory.decode("myNetwork")!.tier) == .connections)
    }
}

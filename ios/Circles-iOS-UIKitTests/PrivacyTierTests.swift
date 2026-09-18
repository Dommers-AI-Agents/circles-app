import Testing
import Foundation
@testable import Circles_iOS

/// The one ladder every picker and badge is built from, and the fail-closed
/// decoding that keeps a tier this build doesn't know from either vanishing a
/// row or being shown as more open than it is.
struct PrivacyTierTests {

    // MARK: - The ladder

    @Test func ladderRunsOpenToClosed() {
        #expect(PrivacyTier.public < PrivacyTier.connections)
        #expect(PrivacyTier.connections < PrivacyTier.innerCircle)
        #expect(PrivacyTier.innerCircle < PrivacyTier.private)
    }

    @Test func rawValuesMatchTheBackendVocabulary() {
        #expect(PrivacyTier.public.rawValue == "public")
        #expect(PrivacyTier.connections.rawValue == "myNetwork")
        #expect(PrivacyTier.innerCircle.rawValue == "innerCircle")
        #expect(PrivacyTier.private.rawValue == "private")
    }

    @Test func everyTierSaysSomethingDistinct() {
        let titles = PrivacyTier.allCases.map(\.title)
        let subtitles = PrivacyTier.allCases.map(\.subtitle)
        let icons = PrivacyTier.allCases.map(\.systemIconName)
        #expect(Set(titles).count == PrivacyTier.allCases.count)
        #expect(Set(subtitles).count == PrivacyTier.allCases.count)
        #expect(Set(icons).count == PrivacyTier.allCases.count)
        let allTitlesFilled = titles.allSatisfy { !$0.isEmpty }
        let allSubtitlesFilled = subtitles.allSatisfy { !$0.isEmpty }
        #expect(allTitlesFilled)
        #expect(allSubtitlesFilled)
    }

    /// The single highest-value line of copy in the feature: it is the only
    /// place, at the moment of choosing, that says a follower sees more than a
    /// connection does.
    @Test func publicSubtitleNamesFollowers() {
        #expect(PrivacyTier.public.subtitle.lowercased().contains("follower"))
    }

    // MARK: - Option sets

    @Test func circlesGetTheFourTiersAndNothingElse() {
        let options = PrivacyTier.options(for: .circle)
        #expect(options == [.tier(.public), .tier(.connections), .tier(.innerCircle), .tier(.private)])
    }

    @Test func placesAddInheritAtTheTop() {
        let options = PrivacyTier.options(for: .place)
        #expect(options.first == .inheritCircle)
        #expect(options.count == PrivacyTier.allCases.count + 1)
    }

    /// Following is one-way, so it earns the public tier and no more. A circle
    /// offering a followers option would promise something the server does not
    /// implement.
    @Test func onlyMomentsOfferFollowers() {
        #expect(PrivacyTier.options(for: .moment).contains(.followers))
        #expect(!PrivacyTier.options(for: .circle).contains(.followers))
        #expect(!PrivacyTier.options(for: .place).contains(.followers))
    }

    @Test func momentFollowersSitsBetweenPublicAndConnections() {
        let options = PrivacyTier.options(for: .moment)
        #expect(options[0] == .tier(.public))
        #expect(options[1] == .followers)
        #expect(options[2] == .tier(.connections))
    }

    // MARK: - Round trips through each entity's vocabulary

    @Test func circleOptionsRoundTrip() {
        for option in PrivacyTier.options(for: .circle) {
            guard case .tier(let tier) = option else { continue }
            #expect(tier.circlePrivacy.tier == tier)
        }
    }

    @Test func placeOptionsRoundTrip() {
        for option in PrivacyTier.options(for: .place) {
            let stored = option.placePrivacy
            #expect(stored != nil)
            #expect(stored?.option == option)
        }
    }

    /// Moments spell the connections tier `network`, a historic split the
    /// backend normalises on read rather than migrating thousands of docs.
    @Test func momentOptionsRoundTripWithTheirOwnSpelling() {
        for option in PrivacyTier.options(for: .moment) {
            let stored = option.videoVisibility
            #expect(stored != nil)
            #expect(stored?.option == option)
        }
        #expect(PrivacyOption.tier(.connections).videoVisibility == .network)
        #expect(PrivacyOption.tier(.innerCircle).videoVisibility == .innerCircle)
    }

    /// `selectable` exists so a picker never offers `.unknown`.
    @Test func momentSelectableListExcludesUnknown() {
        #expect(!VideoVisibility.selectable.contains(.unknown))
        #expect(VideoVisibility.selectable.count == PrivacyTier.options(for: .moment).count)
    }
}

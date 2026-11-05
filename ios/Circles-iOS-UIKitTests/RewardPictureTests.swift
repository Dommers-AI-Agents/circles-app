import Foundation
import Testing
@testable import Circles_iOS

/// A reward's picture from its title (Wes, 2026-11-05)
struct RewardPictureTests {
    @Test func picksWhatTheRewardIs() {
        #expect(RewardPicture.emoji(for: "Free drip coffee") == "☕️")
        #expect(RewardPicture.emoji(for: "Free Iced Latte") == "☕️")
        #expect(RewardPicture.emoji(for: "Free croissant") == "🥐")
        #expect(RewardPicture.emoji(for: "2 Free Muffins") == "🧁")
        #expect(RewardPicture.emoji(for: "Free slice of pizza") == "🍕")
        #expect(RewardPicture.emoji(for: "Free boba tea") == "🧋")
        #expect(RewardPicture.emoji(for: "Free Café Crème Brûlée Latte") == "☕️")
    }

    @Test func mostSpecificWins() {
        #expect(RewardPicture.emoji(for: "Free coffee cake") == "🍰")
        #expect(RewardPicture.emoji(for: "Free cake pop") == "🎂")
        #expect(RewardPicture.emoji(for: "Matcha latte") == "🍵")
        #expect(RewardPicture.emoji(for: "Free cinnamon roll") == "🥐")
    }

    @Test func wholeWordsOnly() {
        // "tea" isn't in "steak", "cut" isn't in "biscuit"
        #expect(RewardPicture.emoji(for: "Free steak") == RewardPicture.fallback)
        #expect(RewardPicture.emoji(for: "Free biscuit") == RewardPicture.fallback)
        #expect(RewardPicture.emoji(for: "Free haircut") == "💇")
    }

    @Test func discountsMoneyAndUnknown() {
        #expect(RewardPicture.emoji(for: "10% off your order") == "🏷️")
        #expect(RewardPicture.emoji(for: "$5 credit") == "💵")
        #expect(RewardPicture.emoji(for: "Mystery prize") == RewardPicture.fallback)
        #expect(RewardPicture.emoji(for: "") == RewardPicture.fallback)
    }
}

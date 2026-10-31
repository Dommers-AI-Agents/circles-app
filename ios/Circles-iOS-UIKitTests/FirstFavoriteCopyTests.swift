import Testing
@testable import Circles_iOS

struct FirstFavoriteCopyTests {
    @Test func saversLine() {
        #expect(FirstFavoriteCopy.saversLine(count: 0, placeName: "P&P") == nil)
        #expect(FirstFavoriteCopy.saversLine(count: 1, placeName: "P&P") == "1 person also loves P&P")
        #expect(FirstFavoriteCopy.saversLine(count: 3, placeName: "P&P") == "3 people also love P&P")
    }

    @Test func rewardsLineOnlyWhenLiveAndNotOwner() {
        #expect(FirstFavoriteCopy.rewardsLine(placeName: "Bakery", rewardsLive: false, isOwner: false) == nil)
        #expect(FirstFavoriteCopy.rewardsLine(placeName: "Bakery", rewardsLive: true, isOwner: true) == nil)
        #expect(FirstFavoriteCopy.rewardsLine(placeName: "Bakery", rewardsLive: true, isOwner: false)?.hasPrefix("Bakery has FavCircles Rewards") == true)
    }

    @Test func chipsSearchPlainWords() {
        #expect(FirstFavoriteCopy.chips.count == 7)
        #expect(FirstFavoriteCopy.chips.allSatisfy { !$0.query.contains(" ") && $0.title.hasSuffix($0.query) })
    }

    @Test func homeCard() {
        #expect(FirstFavoriteCopy.homeCard(firstPlaceName: nil, ownPlaceCount: 1, goal: 3) == nil)
        #expect(FirstFavoriteCopy.homeCard(firstPlaceName: "P&P", ownPlaceCount: 0, goal: 3) == nil)
        #expect(FirstFavoriteCopy.homeCard(firstPlaceName: "P&P", ownPlaceCount: 3, goal: 3) == nil)
        #expect(FirstFavoriteCopy.homeCard(firstPlaceName: "P&P", ownPlaceCount: 1, goal: 3)?.body == "You saved P&P. Add two more places you love.")
        #expect(FirstFavoriteCopy.homeCard(firstPlaceName: "P&P", ownPlaceCount: 2, goal: 3)?.body == "You saved P&P. Add one more place you love.")
    }

    @Test func photoMapCopy() {
        #expect(FirstFavoriteCopy.photoMapHeadline(placeName: nil) == "Fill your map from your photos")
        #expect(FirstFavoriteCopy.photoMapHeadline(placeName: "P&P") == "Add more places like P&P")
    }

    @Test func fallbackHeader() {
        #expect(FirstFavoriteCopy.fallbackPeopleHeader(cityName: "Charlotte") == "People mapping Charlotte")
        #expect(FirstFavoriteCopy.fallbackPeopleHeader(cityName: " ") == "Maps worth exploring")
    }
}

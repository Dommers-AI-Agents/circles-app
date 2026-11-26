import Testing
@testable import Circles_iOS

/// After joining at a store in the App Clip, the app opens on that store and
/// shows them around it, then carries on like any new user (Wes, 2026-11-26).
struct StoreWelcomeGuideTests {

    @Test func theTourIsTheStoresPageThenTheBell() {
        let stops = StoreWelcomeGuideCopy.stops(storeName: "Caffeena", rewardsLive: false)
        #expect(stops.count == 2)
        #expect(stops[0].title == "Welcome to Caffeena’s page")
        #expect(stops[1].title == "You’re connected")
        #expect(stops[1].message.contains("bell is on"))
        #expect(!stops.contains { $0.message.localizedCaseInsensitiveContains("points") })
    }

    @Test func rewardsOnlyWhereTheStoresAreLive() {
        let stops = StoreWelcomeGuideCopy.stops(storeName: "Caffeena", rewardsLive: true)
        #expect(stops.count == 3)
        #expect(stops[2].title == "Your rewards")
    }

    @Test func itEndsByCarryingOnIntoFavCircles() {
        #expect(StoreWelcomeGuideCopy.finish.back == "Keep exploring")
        #expect(StoreWelcomeGuideCopy.finish.next == nil)
    }
}

/// "Stores I follow only" and the one-time "friends too?" questions
struct NotificationScopeTests {

    @Test func onlyStoresOnlyAccountsAreAskedAndEachMomentOnce() {
        #expect(NotificationScope.shouldAsk(mode: .storesOnly, asked: [], moment: .friendRequest))
        #expect(!NotificationScope.shouldAsk(mode: .storesOnly, asked: ["friendRequest"], moment: .friendRequest))
        #expect(NotificationScope.shouldAsk(mode: .storesOnly, asked: ["friendRequest"], moment: .suggestion))
        #expect(!NotificationScope.shouldAsk(mode: .all, asked: [], moment: .follow))
    }

    @Test func unknownOrMissingModeIsEverything() {
        #expect(NotificationScope.Mode(raw: nil) == .all)
        #expect(NotificationScope.Mode(raw: "weird") == .all)
        #expect(NotificationScope.Mode(raw: "storesOnly") == .storesOnly)
    }

    @Test func settingsShowsStoresOnlyAllOrLetMeChoose() {
        #expect(NotificationScope.choice(mode: .storesOnly, everySwitchOn: true) == .storesOnly)
        #expect(NotificationScope.choice(mode: .all, everySwitchOn: true) == .all)
        #expect(NotificationScope.choice(mode: .all, everySwitchOn: false) == .custom)
    }

    @Test func theQuestionsNameThePersonByFirstName() {
        #expect(NotificationScope.ask(.friendRequest, name: "Maria Lopez").title == "Maria wants to connect")
        #expect(NotificationScope.ask(.follow, name: "Maria Lopez").title == "Want to know when Maria saves new places?")
        #expect(NotificationScope.ask(.suggestion, name: " ").title == "A place was suggested for you")
        #expect(NotificationScope.ask(.tour).no == "Just my stores")
        for moment in NotificationScope.Moment.allCases {
            #expect(!NotificationScope.ask(moment).message.isEmpty)
        }
    }
}

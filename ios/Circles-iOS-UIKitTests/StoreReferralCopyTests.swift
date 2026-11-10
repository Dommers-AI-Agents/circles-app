import Testing
import Foundation
@testable import Circles_iOS

struct StoreReferralCopyTests {
    @Test func inviteButtonAndShareTitle() {
        let same = StoreReferral(enabled: true, referrerPoints: 50, friendPoints: 50, inviteUrl: "https://x/s/WIN?ref=u")
        #expect(StoreReferralCopy.inviteButton(same) == "Invite a friend · you both get 50 points")
        let split = StoreReferral(enabled: true, referrerPoints: 50, friendPoints: 25, inviteUrl: nil)
        #expect(StoreReferralCopy.inviteButton(split) == "Invite a friend · you get 50, they get 25")
        #expect(StoreReferralCopy.shareTitle(storeName: "Sal's", referral: split) == "Join me at Sal's on FavCircles — 25 bonus points on your first visit")
    }

    @Test func ownerLines() {
        #expect(StoreReferralCopy.summary(.off).hasPrefix("Off"))
        #expect(StoreReferralCopy.summary(StoreReferralSettings(enabled: true, referrerPoints: 50, friendPoints: 25)) == "On · inviter 50 pts, friend 25 pts")
        #expect(StoreReferralCopy.statsLine(nil) == "No friends brought in yet")
        #expect(StoreReferralCopy.statsLine(StoreReferralStats(friendsBrought: 3, thisMonth: 1, pointsPaid: 225)) == "3 friends brought in · 1 this month · 225 points paid")
        for text in [StoreReferralCopy.explanation, StoreReferralCopy.summary(.off)] {
            #expect(!text.lowercased().contains(" text"), "\(text)")
            #expect(!text.lowercased().contains("sms"), "\(text)")
        }
    }
}

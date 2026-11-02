import Foundation
import Testing
@testable import Circles_iOS

/// Home Screen shortcuts and Home tab pins come back after a reinstall
struct HomeShortcutAccountTests {
    private typealias Doc = HomeShortcutAccount.Document
    private let saved = Doc(selection: ["checkIn", "widget:water"], pins: [HomeButtonPin(id: "water", title: "Water")])
    private let fresh = Doc(selection: nil, pins: [])

    @Test func aReinstallTakesTheAccountsShortcuts() {
        #expect(HomeShortcutAccount.firstLaunch(account: saved, phone: fresh) == .adopt(saved))
    }

    @Test func choicesMadeBeforeTheAccountKeptThemGoUp() {
        #expect(HomeShortcutAccount.firstLaunch(account: nil, phone: saved) == .upload)
        #expect(HomeShortcutAccount.firstLaunch(account: nil, phone: fresh) == .nothing)
    }

    @Test func inStepNothingHappens() {
        #expect(HomeShortcutAccount.firstLaunch(account: saved, phone: saved) == .nothing)
    }
}

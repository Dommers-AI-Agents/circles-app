import Testing
import Foundation
@testable import Circles_iOS

/// Picked avatars are real URLs the website and emails can show, read back
/// from the app's bundle.
struct ProfileAvatarCatalogTests {

    private typealias C = ProfileAvatarCatalog

    @Test func sixWomenSixMenAndThreeRobots() {
        #expect(C.groups.map(\.title) == ["Women", "Men", "Robots"])
        #expect(C.groups.map(\.ids.count) == [6, 6, 3])
        #expect(Set(C.allIds).count == C.allIds.count)
    }

    @Test func eachAvatarIsAHostedImage() {
        #expect(C.url(for: "woman-1") == "https://favcircles.com/avatars/woman-1.png")
        #expect(C.id(from: C.url(for: "man-4")) == "man-4")
        #expect(C.id(from: " https://favcircles.com/avatars/robot-2.png ") == "robot-2")
    }

    @Test func anythingElseIsNotACatalogAvatar() {
        #expect(C.id(from: nil) == nil)
        #expect(C.id(from: "stock-avatar:🦊:2") == nil)
        #expect(C.id(from: "https://firebasestorage.googleapis.com/x.jpg") == nil)
        #expect(C.id(from: "https://favcircles.com/avatars/woman-99.png") == nil)
        #expect(C.id(from: "https://favcircles.com/avatars/../app-icon.png") == nil)
    }

    @Test func everyAvatarShipsInTheApp() {
        for id in C.allIds {
            #expect(UIImageAssetCheck.exists(C.assetName(for: id)), "missing asset for \(id)")
        }
    }
}

import UIKit
private enum UIImageAssetCheck {
    // Tests run inside the app, so the main bundle is the app's
    static func exists(_ name: String) -> Bool { UIImage(named: name) != nil }
}

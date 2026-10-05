import Testing
import UIKit
@testable import Circles_iOS

/// The loading box must never strand the work waiting on its dismissal.
@MainActor
struct LoadingAlertControllerTests {
    @Test func aBoxThatNeverReachedTheScreenStillHandsOn() {
        let box = LoadingAlertController(title: nil, message: "Reading your photos…", preferredStyle: .alert)
        var continued = false
        box.dismiss(animated: true) { continued = true }
        #expect(continued)
    }
}

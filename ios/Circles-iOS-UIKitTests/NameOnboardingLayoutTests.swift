import UIKit
import Testing
@testable import Circles_iOS

/// "What should friends call you?" with the keyboard up: the buttons ride on
/// the keyboard, so on a smaller phone they landed on Last name (2026-11-07).
/// The fields now scroll in the space above the buttons.
@MainActor
struct NameOnboardingLayoutTests {
    private func laidOut(height: CGFloat) -> UIViewController {
        let vc = NameOnboardingViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: height))
        window.rootViewController = vc
        window.isHidden = false
        vc.view.layoutIfNeeded()
        return vc
    }

    private func frames(_ vc: UIViewController) -> (fields: CGRect, buttons: CGRect) {
        let scroll = vc.view.subviews.first { $0 is UIScrollView }!
        let buttons = vc.view.subviews.filter { $0 is UIButton }.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return (scroll.frame, buttons)
    }

    @Test func fieldsNeverRunUnderTheButtonsOnAShortScreen() {
        // About what's left of an iPhone 17 Pro above the keyboard
        let vc = laidOut(height: 520)
        let (fields, buttons) = frames(vc)
        #expect(fields.maxY <= buttons.minY)
        let scroll = vc.view.subviews.first { $0 is UIScrollView } as! UIScrollView
        #expect(scroll.contentSize.height > scroll.bounds.height)   // it scrolls instead of overlapping
    }

    @Test func roomyScreenStillFitsWithoutScrolling() {
        let vc = laidOut(height: 874)
        let (fields, buttons) = frames(vc)
        #expect(fields.maxY <= buttons.minY)
        let scroll = vc.view.subviews.first { $0 is UIScrollView } as! UIScrollView
        #expect(scroll.contentSize.height <= scroll.bounds.height)
    }
}

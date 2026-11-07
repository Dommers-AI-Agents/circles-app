import UIKit

/// Bubbles on a screen the home tour's "Show me" opened: what it is, then a
/// next step, so nobody lands on a new screen with nothing to go on (Wes,
/// 2026-11-07). Runs only when the tour sent them (OnboardingManager
/// takeGuide), so opening the screen normally shows nothing. Done ends the
/// tour; "Back to the tour" returns to Home, where it carries on.
enum ScreenGuide {
    struct Stop {
        let copy: ScreenGuideCopy.Stop
        let target: () -> UIView?
        var arrow: BubbleView.ArrowDirection = .top
        /// Runs before the bubble (switch a tab, scroll)
        var prepare: (() -> Void)? = nil
    }

    /// "Back to the tour": Home, where the paused tour carries on
    static func backToTour(from host: UIViewController) {
        let go = {
            guard let tabs = host.view.window?.rootViewController as? UITabBarController ?? (UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow }?.rootViewController }.first as? UITabBarController),
                  let nav = tabs.viewControllers?.first as? UINavigationController else { return }
            tabs.selectedIndex = 0
            nav.popToRootViewController(animated: true)
            (nav.viewControllers.first as? CirclesHomeViewController)?.resumeHomeTourIfPaused()
        }
        if host.navigationController?.presentingViewController != nil || host.presentingViewController != nil {
            host.dismiss(animated: true, completion: go)
        } else {
            go()
        }
    }

    /// "Add a place you love" from a guide
    static func addPlace(from host: UIViewController) {
        let go = { OnboardingManager.shared.startAddPlaceFromGuide() }
        if host.navigationController?.presentingViewController != nil || host.presentingViewController != nil {
            host.dismiss(animated: true, completion: go)
        } else {
            go()
        }
    }

    /// The one-bubble screens: what it is, then "Add a place you love" or back
    static func runSimple(_ kind: ScreenGuideKind, in host: UIViewController, target: (() -> UIView?)? = nil,
                          arrow: BubbleView.ArrowDirection = .top) {
        let stops = ScreenGuideCopy.stops(kind).map { Stop(copy: $0, target: target ?? { nil }, arrow: arrow) }
        run(stops, finish: ScreenGuideCopy.finish(kind), in: host,
            onNext: { addPlace(from: host) },
            onBack: { [weak host] in
                guard let host else { return }
                // Got it on Add Place: stay and add the place
                if kind == .addPlace { return }
                backToTour(from: host)
            })
    }

    static func run(_ stops: [Stop], finish: ScreenGuideCopy.Finish, in host: UIViewController,
                    onNext: (() -> Void)? = nil, onBack: @escaping () -> Void) {
        show(index: 0, stops: stops, finish: finish, host: host, onNext: onNext, onBack: onBack, attempt: 0)
    }

    private static func show(index: Int, stops: [Stop], finish: ScreenGuideCopy.Finish, host: UIViewController,
                             onNext: (() -> Void)?, onBack: @escaping () -> Void, attempt: Int) {
        // Never under a sheet or alert (stray taps would hit its buttons)
        guard host.viewIfLoaded?.window != nil else { return }
        if host.presentedViewController != nil {
            if attempt < 60 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    show(index: index, stops: stops, finish: finish, host: host, onNext: onNext, onBack: onBack, attempt: attempt + 1)
                }
            }
            return
        }
        let hasCard = finish.title != nil
        let total = stops.count + (hasCard ? 1 : 0)
        let isLast = index == total - 1
        let stop: Stop? = index < stops.count ? stops[index] : nil
        stop?.prepare?()
        // A beat for layout (a just-switched tab, a just-pushed screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard host.viewIfLoaded?.window != nil else { return }
            let manager = OnboardingManager.shared
            manager.dismissCurrentBubble()
            let bubble = BubbleView()
            let title = stop?.copy.title ?? finish.title ?? ""
            let message = stop?.copy.message ?? finish.message ?? ""
            bubble.configureTour(title: title, description: message, arrowDirection: stop?.arrow ?? .bottom,
                                 stepText: total > 1 ? "\(index + 1) of \(total)" : nil,
                                 canGoBack: index > 0,
                                 learnMore: isLast && finish.next != nil, video: false,
                                 skipTitle: "Done", nextTitle: isLast ? finish.back : "Next",
                                 learnMoreTitle: isLast ? finish.next : nil)
            bubble.onNext = {
                manager.dismissCurrentBubble()
                if isLast { onBack() } else {
                    show(index: index + 1, stops: stops, finish: finish, host: host, onNext: onNext, onBack: onBack, attempt: 0)
                }
            }
            bubble.onBack = {
                manager.dismissCurrentBubble()
                show(index: index - 1, stops: stops, finish: finish, host: host, onNext: onNext, onBack: onBack, attempt: 0)
            }
            bubble.onLearnMore = {
                manager.dismissCurrentBubble()
                onNext?()
            }
            bubble.onSkip = {
                manager.dismissCurrentBubble()
                manager.completeOnboarding()
            }
            host.view.addSubview(bubble)
            bubble.pointTo(stop?.target(), in: host.view)
            bubble.show()
            manager.currentBubbleView = bubble
        }
    }
}

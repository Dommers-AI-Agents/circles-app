import UIKit
import FavWidgetsCore

// MARK: - Home "daily card"
//
// One server-picked card per visit (roughly once a day), rendered inline
// between the segment bar and the tab content. The server decides what and
// whether (`GET /api/home/prompt`); this file decides *when it's safe* —
// never over onboarding, the home tour, or a modal — and routes the tap.
// Timing rules are in `HomePromptGate` (unit tested).
extension CirclesHomeViewController {

    /// Called from viewDidAppear (after the onboarding check has had its
    /// turn) and on foreground. Cheap when nothing needs doing.
    func refreshDailyCardIfAppropriate() {
        let context = dailyCardContext()
        guard HomePromptGate.shouldFetch(context) else { return }
        lastHomePromptFetchAt = context.now

        HomePromptService.shared.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let card):
                    guard let card, HomePromptGate.canPresent(self.dailyCardContext()) else { return }
                    self.presentDailyCard(card)
                case .failure(let error):
                    Logger.debug("🃏 home prompt fetch failed: \(error)")
                }
            }
        }
    }

    private func dailyCardContext() -> HomePromptGate.Context {
        HomePromptGate.Context(
            now: Date(),
            lastFetchAt: lastHomePromptFetchAt,
            isSignedIn: AuthService.shared.currentUser != nil,
            isCardVisible: dailyCardView != nil,
            isPresentingModal: presentedViewController != nil,
            isTourRunning: isShowingWelcomeTour,
            isFirstSessionFlowActive: OnboardingManager.shared.isFirstSessionFlowActive,
            onboardingCheckDone: hasCheckedTutorialAndOverlay
        )
    }

    // MARK: Presentation

    private func presentDailyCard(_ card: HomePromptCard) {
        dailyCardView?.removeFromSuperview()
        let view = HomePromptCardView()
        view.configure(with: card)
        view.onAct = { [weak self] in self?.dailyCardActed() }
        view.onSkip = { [weak self] in self?.dailyCardSkipped() }
        dailyCardView = view

        dailyCardContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: dailyCardContainer.topAnchor, constant: Constants.Spacing.small),
            view.leadingAnchor.constraint(equalTo: dailyCardContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: dailyCardContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: dailyCardContainer.bottomAnchor)
        ])
        dailyCardCollapsedHeight?.isActive = false

        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: -8)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            view.alpha = 1
            view.transform = .identity
            self.view.layoutIfNeeded()
        }
        AnalyticsService.shared.logEvent("home_card_shown", parameters: ["card_key": card.key, "card_type": card.type])
    }

    private func dismissDailyCard() {
        guard let view = dailyCardView else { return }
        dailyCardView = nil
        UIView.animate(withDuration: 0.25, animations: {
            view.alpha = 0
        }, completion: { _ in
            view.removeFromSuperview()
            self.dailyCardCollapsedHeight?.isActive = true
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        })
    }

    private func dailyCardSkipped() {
        guard let card = dailyCardView?.card else { return }
        AnalyticsService.shared.logEvent("home_card_skipped", parameters: ["card_key": card.key, "card_type": card.type])
        HomePromptService.shared.ack(key: card.key, action: .skipped)
        dismissDailyCard()
    }

    private func dailyCardActed() {
        guard let card = dailyCardView?.card else { return }
        AnalyticsService.shared.logEvent("home_card_acted", parameters: ["card_key": card.key, "card_type": card.type])
        HomePromptService.shared.ack(key: card.key, action: .acted)
        dismissDailyCard()
        route(dailyCard: card)
    }

    // MARK: Routing

    private func route(dailyCard card: HomePromptCard) {
        switch card.destination {
        case .place(let id):
            NotificationCenter.default.post(name: Notification.Name("NavigateToPlace"), object: id)
        case .video(let id):
            UIApplication.shared.connectedScenes
                .compactMap { $0.delegate as? SceneDelegate }
                .first?
                .navigateToVideo(videoId: id)
        case .postcard(let placeId, let globalPlaceId, let placeName, let photoUrl):
            AnalyticsService.shared.logEvent("postcard_nudge_accepted", parameters: ["source": "home_card"])
            // The card already carries the venue's id and photo, so the
            // composer opens without re-fetching the place.
            let ref = WidgetPlaceRef(
                id: globalPlaceId ?? placeId,
                name: placeName ?? "",
                isGlobal: globalPlaceId != nil
            )
            PostcardComposerRouter.open(photoUrl: photoUrl, place: ref, from: self)
        case .addPlace:
            quickAddPlaceButtonTapped()
        case .widgetsTab:
            showWidgetsTab(openingWidget: nil)
        case .momentsTab:
            // Programmatic index changes don't fire .valueChanged; sending the
            // action runs the same handler a finger tap would.
            contentSegmentedControl.selectedSegmentIndex = HomeContentSegment.moments.rawValue
            contentSegmentedControl.sendActions(for: .valueChanged)
            scrollView.scrollRectToVisible(activityFeedSection.frame, animated: true)
        case .favCoinsIntro:
            let intro = FavCoinsIntroViewController()
            intro.onFinished = { [weak self] openPiggyBank in
                HomePromptService.shared.ack(key: "favcoins_intro", action: openPiggyBank ? .acted : .skipped)
                guard openPiggyBank else { return }
                self?.dismiss(animated: true) {
                    NotificationCenter.default.post(name: Notification.Name("NavigateToPiggyBank"), object: nil)
                }
            }
            present(intro, animated: true)
        case .allPlacesMap:
            NotificationCenter.default.post(name: Notification.Name("NavigateToAllPlacesMap"), object: nil)
        case .createWallet:
            NotificationCenter.default.post(name: Notification.Name("NavigateToCreateWallet"), object: nil)
        case .network:
            tabBarController?.selectedIndex = 1
        case .unknown(let target):
            Logger.debug("🃏 home card target not routable in this build: \(target)")
        }
    }
}

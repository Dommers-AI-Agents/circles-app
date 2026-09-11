import UIKit
import MapKit
import CoreLocation

// Scroll/gesture, SSE, and overlay-view delegate conformances for
// CirclesHomeViewController (suggested users, content upload, tutorials,
// permission prompts). Extracted from the main controller (Wave 4).

// The outer scroll view's delegate. Each content tab paginates its own
// list; nothing is needed here beyond the conformance.
extension CirclesHomeViewController: UIScrollViewDelegate {}

// MARK: - UIGestureRecognizerDelegate
extension CirclesHomeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ensure touch.view is valid and is a UIView
        guard let touchView = touch.view as? UIView else {
            return false
        }
        
        // Don't intercept touches on the search bar or keyboard
        if touchView.isDescendant(of: searchBar) {
            return false
        }
        
        // Don't intercept touches if keyboard is showing (this prevents issues
        // with keyboard buttons) — EXCEPT the map-peek tap: while search
        // results are up, a tap outside them (the visible map) must reach
        // dismissDropdowns so it can drop the list and show the filtered map.
        if searchBar.isFirstResponder {
            let location = touch.location(in: view)
            let allowForMapPeek = isSearching && !isSearchOverlayDismissed
                && !searchResultsTableView.isHidden
                && !searchResultsTableView.frame.contains(location)
            if !allowForMapPeek {
                return false
            }
        }
        
        // Don't intercept touches on the dropdown table views
        if touchView.isDescendant(of: searchScopeTableView) ||
           touchView.isDescendant(of: searchResultsTableView) {
            return false
        }

        // Don't intercept touches on the dropdown containers themselves
        let location = touch.location(in: view)
        if !searchScopeDropdownView.isHidden && searchScopeDropdownView.frame.contains(location) {
            return false
        }
        if !searchResultsTableView.isHidden && searchResultsTableView.frame.contains(location) {
            return false
        }
        
        return true
    }
}

// MARK: - SSEServiceDelegate
extension CirclesHomeViewController {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        switch event.type {
        case .onboardingCompleted:
            // Onboarding completed - reload circles to show the new ones
            Logger.info("Received onboarding completed event, reloading circles")
            DispatchQueue.main.async { [weak self] in
                self?.loadData()
            }
            
        case .placeAdded, .circleCreated, .connectionActivity:
            // Connection activity events - refresh user list to show updated activity
            Logger.info("Received connection activity event, refreshing user list")
            DispatchQueue.main.async { [weak self] in
                self?.userListView.refresh()
                // Update notification badge for new activity
                Logger.debug("🔔 CirclesHomeViewController: Updating badge for connection activity SSE event")
                self?.updateNotificationBadge()
                
                // Also refresh activity feed if on Activity tab
                if self?.contentSegmentedControl.selectedSegmentIndex == 0 {
                    self?.refreshActivityFeedWithNewItem()
                }
            }
            
        case .newActivity:
            // New activity in network - refresh activity feed
            Logger.info("Received new activity event for activity feed")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Update notification badge when new activity arrives
                Logger.debug("🔔 CirclesHomeViewController: Updating badge for new activity SSE event")
                self.updateNotificationBadge()
                
                // Only refresh if Activity tab is selected
                if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                    self.refreshActivityFeedWithNewItem()
                }
            }
            
        case .specialsUpdated:
            // A venue changed its offers or announcements — refresh the
            // Specials tab live if it's showing, otherwise drop the loaded
            // list so the next visit refetches
            Logger.info("Received specials updated event")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.contentSegmentedControl.selectedSegmentIndex == 2 {
                    self.specialsTab.refreshTab()
                } else {
                    self.specialsTab.invalidate()
                }
            }

        default:
            // Handle other specific event types
            if let eventTypeString = event.data["type"] as? String {
                switch eventTypeString {
                case "moment_uploaded":
                    Logger.info("Received moment uploaded event")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // Refresh activity feed if on Activity tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                            self.refreshActivityFeedWithNewItem()
                        }
                        // Refresh moments feed if on Moments tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 1 {
                            self.fetchReels()
                        }
                    }
                    
                case "comment_added", "reaction_added", "check_in":
                    Logger.info("Received \(eventTypeString) event")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // Refresh activity feed if on Activity tab
                        if self.contentSegmentedControl.selectedSegmentIndex == 0 {
                            self.refreshActivityFeedWithNewItem()
                        }
                    }
                    
                default:
                    break
                }
            }
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
        Logger.info("SSE connection established")
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
        if let error = error {
            Logger.error("SSE connection lost: \(error)")
        } else {
            Logger.info("SSE connection closed")
        }
    }
}

// MARK: - SuggestedUsersOverlayViewDelegate
extension CirclesHomeViewController: SuggestedUsersOverlayViewDelegate {
    func didSelectUser(_ user: User) {
        // User selected a suggested user - refresh connections
        userListView.refresh()
    }
    
    func didTapExploreNetwork() {
        // Navigate directly to DiscoverUsersViewController for new users
        let discoverVC = DiscoverUsersViewController()
        let navController = UINavigationController(rootViewController: discoverVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    func didTapImportContacts() {
        // "Share an Invite": straight to the share sheet. (The phone-contacts
        // import this used to trigger is gone.)
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityVC = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(activityVC, animated: true)
    }
    
    func didDismissOverlay() {
        // Clean up overlay reference
        suggestedUsersOverlay = nil

        if isShowingWelcomeTour {
            // If in tour mode, reset the flag
            isShowingWelcomeTour = false
        } else {
            // Mark that user has dismissed the overlay in normal flow
            OnboardingManager.shared.disableSuggestedUsersOverlay()

            // The overlay used to hard-exit the tutorial for the session
            // (checkTutorialAndOverlay's once-per-session latch was already
            // burned) — hand off to the home tour explicitly instead
            startHomeTourIfNeededAfterOverlay()
        }
    }

    func didTapNext(selectedUsers: [User]) {
        // Clean up overlay reference
        suggestedUsersOverlay = nil

        if isShowingWelcomeTour {
            // In tour mode, force show the add place tutorial
            forceShowAddPlaceTutorial()
        } else {
            startHomeTourIfNeededAfterOverlay()
        }
    }

    func didTapSkip() {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        hasCheckedForSuggestedUsers = true  // Set the flag to prevent showing again

        if isShowingWelcomeTour {
            // In tour mode, force show the add place tutorial
            forceShowAddPlaceTutorial()
        } else {
            startHomeTourIfNeededAfterOverlay()
        }
    }
}

// MARK: - ContentUploadDelegate
extension CirclesHomeViewController: ContentUploadDelegate {
    func contentUploadDidFinish(with moment: PlaceMoment) {
        // Refresh reels to show the newly uploaded video
        fetchReels()
        
        // Also refresh activities to show the upload activity
        fetchActivities()
        
        // Ensure the correct tab content is displayed based on selected tab
        // This prevents Moments content from showing when Activity tab is selected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.contentSegmentChanged()
        }
    }
    
    func contentUploadDidCancel() {
        // Nothing to do on cancel
    }
}

// MARK: - AddFirstPlaceTutorialViewDelegate
extension CirclesHomeViewController: AddFirstPlaceTutorialViewDelegate {
    func didTapGotIt() {
        // Clean up overlay reference
        addPlaceTutorialOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, just reset the flag
            isShowingWelcomeTour = false
            // Don't mark as shown so it can be shown again
        } else {
            // Normal flow - mark tutorial as shown
            OnboardingManager.shared.markAddPlaceTutorialShown()
        }
    }

    func didTapSkipTutorial() {
        // Clean up overlay reference
        addPlaceTutorialOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, just reset the flag
            isShowingWelcomeTour = false
            // Don't mark as shown so it can be shown again
        } else {
            // Normal flow - mark tutorial as shown
            OnboardingManager.shared.markAddPlaceTutorialShown()
        }
    }
}

// MARK: - VisitTrackingPermissionViewDelegate

extension CirclesHomeViewController: VisitTrackingPermissionViewDelegate {
    func didEnableVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark permission response
        OnboardingManager.shared.setVisitTrackingPermissionResponse(enabled: true)
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
    
    func didDisableVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark permission response
        OnboardingManager.shared.setVisitTrackingPermissionResponse(enabled: false)
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
    
    func didSkipVisitTracking() {
        // Clean up overlay
        visitTrackingPermissionOverlay = nil
        
        // Mark as shown but no response
        OnboardingManager.shared.markVisitTrackingPermissionShown()
        
        // Continue with normal flow
        checkTutorialAndOverlay()
    }
}

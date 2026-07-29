import UIKit
import MapKit
import CoreLocation

// Scroll/gesture, SSE, and overlay-view delegate conformances for
// CirclesHomeViewController (suggested users, content upload, tutorials,
// permission prompts). Extracted from the main controller (Wave 4).

extension CirclesHomeViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Handle activity table view scrolling for pagination
        if scrollView == activityTableView {
            let offsetY = scrollView.contentOffset.y
            let contentHeight = scrollView.contentSize.height
            let scrollViewHeight = scrollView.frame.height
            
            // Check if we're near the bottom (within 100 points)
            if offsetY > contentHeight - scrollViewHeight - 100 {
                if !activities.isEmpty && hasMoreActivities && !isLoadingMoreActivities {
                    Logger.debug("📊 Reached bottom of activity table, loading more...")
                    fetchActivities(loadMore: true)
                }
            }
        }
        // Handle pagination for reels collection view
        else if scrollView == reelsCollectionView {
            let contentHeight = scrollView.contentSize.height
            let scrollOffset = scrollView.contentOffset.y
            let frameHeight = scrollView.frame.size.height
            
            if scrollOffset > contentHeight - frameHeight * 1.5 {
                if !isLoadingMoreReels && hasMoreReels {
                    fetchReels(loadMore: true)
                }
            }
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate && scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView == reelsCollectionView {
            updateCurrentReelIndex()
        }
    }
}

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
        
        // Don't intercept touches if keyboard is showing (this prevents issues with keyboard buttons)
        if searchBar.isFirstResponder {
            return false
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
                    self.fetchSpecials(force: true)
                } else {
                    self.specials = []
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
    
    func refreshActivityFeedWithNewItem() {
        // Smart refresh - only load new items without full reload
        // This prevents scroll position loss and provides better UX
        
        // If we don't have any activities yet, do a full load
        if activities.isEmpty {
            fetchActivities()
            return
        }
        
        // Otherwise, fetch just the newest activities
        ActivityService.shared.getNetworkActivities(limit: 5, offset: 0) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let newActivities = response.activities
                    
                    // Find activities that aren't already in our list
                    var addedActivities: [Activity] = []
                    for activity in newActivities {
                        if !self.activities.contains(where: { $0.id == activity.id }) {
                            addedActivities.append(activity)
                        }
                    }
                    
                    if !addedActivities.isEmpty {
                        // Insert new activities at the beginning, then go
                        // through the grouped-feed pipeline — a direct
                        // insertRows would desync rows from feedItems
                        self.activities.insert(contentsOf: addedActivities, at: 0)
                        self.updateActivityFeed()

                        Logger.info("Added \(addedActivities.count) new activities to feed via SSE")
                    }
                    
                case .failure(let error):
                    Logger.error("Failed to fetch new activities via SSE: \(error)")
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
            
            // Now check and show tutorial
            checkTutorialAndOverlay()
        }
    }
    
    func didTapNext(selectedUsers: [User]) {
        // Clean up overlay reference
        suggestedUsersOverlay = nil
        
        if isShowingWelcomeTour {
            // In tour mode, force show the add place tutorial
            forceShowAddPlaceTutorial()
        } else {
            // Normal flow - check if should show add place tutorial
            showAddPlaceTutorialIfNeeded()
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
            // Normal flow - check if should show add place tutorial
            showAddPlaceTutorialIfNeeded()
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

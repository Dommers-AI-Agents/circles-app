import UIKit

// Horizontal user-list and daily-summary handling for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - HorizontalUserListViewDelegate
extension CirclesHomeViewController: HorizontalUserListViewDelegate {
    func didSelectUser(_ user: User, connectionId: String) {
        // Selecting a connection zooms the map to their places — switch back
        // to map view if the list is currently showing
        if isShowingPlacesList {
            listToggleTapped()
        }

        // Tapping a connection's avatar repopulates the map with their places.
        // Tapping the already-selected avatar opens their profile instead —
        // returning to your own places is what the "Me" button is for.
        if selectedConnectionId == user.id {
            let profileVC = ProfileViewController()
            profileVC.configureWith(user: user)
            navigationController?.pushViewController(profileVC, animated: true)
        } else {
            selectConnection(id: user.id, user: user)
        }
    }

    func didSelectSuggestedUser(_ user: User) {
        // Suggested people aren't followed yet, so there's nothing to filter
        // the map to — their profile (with its Follow button) is the destination
        pushProfile(for: user)
    }

    func didLongPressUser(_ user: User, connectionId: String) {
        // Long-press an avatar opens a quick-actions menu for that connection.
        let displayName = user.displayName.isEmpty ? "this person" : user.displayName
        AlertPresenter.showActionSheet(
            title: displayName,
            message: nil,
            actions: [
                (title: "View Profile", style: .default, handler: { [weak self] in
                    self?.pushProfile(for: user)
                }),
                (title: "Message", style: .default, handler: { [weak self] in
                    self?.openConversation(with: user)
                }),
                (title: "Suggest a Place", style: .default, handler: { [weak self] in
                    self?.suggestPlace(to: user)
                }),
                (title: "Show Their Places on Map", style: .default, handler: { [weak self] in
                    self?.showPlacesOnMap(for: user)
                })
            ],
            from: self
        )
    }

    private func suggestPlace(to user: User) {
        // Opens the suggestion composer pre-targeted to this person — they get
        // a directed suggestion (and a notification), not a network broadcast.
        let createVC = CreateSuggestionViewController()
        createVC.recipientUser = user
        let nav = UINavigationController(rootViewController: createVC)
        present(nav, animated: true)
    }

    private func pushProfile(for user: User) {
        let profileVC = ProfileViewController()
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }

    private func openConversation(with user: User) {
        let loading = AlertPresenter.showLoading(message: "Opening chat...", from: self)
        MessagingManager.shared.createOrGetDirectConversation(with: user.id) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let conversation):
                        let chatVC = ChatViewController()
                        chatVC.conversation = conversation
                        self.navigationController?.pushViewController(chatVC, animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    private func showPlacesOnMap(for user: User) {
        // Same as tapping the avatar: filter the map to their places, switching
        // back from list view if needed
        if isShowingPlacesList {
            listToggleTapped()
        }
        selectConnection(id: user.id, user: user)
    }
}

// MARK: - Daily Summary Methods
extension CirclesHomeViewController {
    func showDailySummaryIfAvailable() {
        // This is for showing stored summaries (if any) in the card view
        // Only used for persistent display, not for notification taps
        checkForDailySummary()
    }
    
    // Called when notification is tapped - fetch fresh data and show modal
    func fetchAndShowDailySummary() {
        // Always present the modal DailySummaryViewController
        // It will fetch its own data from the API
        let summaryVC = DailySummaryViewController()
        present(summaryVC, animated: true, completion: nil)
    }
    
    func checkForDailySummary() {
        // Remove any existing card since we're not using this feature anymore
        // Daily summaries should be shown as modals when notification is tapped
        removeDailySummaryCard()
        
        // Clear any old stored data
        if let latestKey = UserDefaults.standard.string(forKey: "latestDailySummaryKey") {
            UserDefaults.standard.removeObject(forKey: latestKey)
            UserDefaults.standard.removeObject(forKey: "latestDailySummaryKey")
        }
    }
    
    func showDailySummaryCard(with data: [String: Any]) {
        // Don't show if already showing
        if dailySummaryCard != nil { return }
        
        // Create the card
        let card = DailySummaryCardView()
        card.delegate = self
        card.configure(with: data)
        card.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to the activity feed section at the top
        activityFeedSection.addSubview(card)
        
        // Position between header and segmented control
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.small),
            card.leadingAnchor.constraint(equalTo: activityFeedSection.leadingAnchor, constant: Constants.Spacing.medium),
            card.trailingAnchor.constraint(equalTo: activityFeedSection.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        // Adjust segmented control position
        contentSegmentedControl.constraints.forEach { constraint in
            if constraint.firstItem === contentSegmentedControl && 
               constraint.firstAttribute == .top &&
               constraint.secondItem === activityHeaderLabel {
                constraint.isActive = false
            }
        }
        
        contentSegmentedControl.topAnchor.constraint(equalTo: card.bottomAnchor, constant: Constants.Spacing.small).isActive = true
        
        // Animate in
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -20)
        
        UIView.animate(withDuration: 0.3) {
            card.alpha = 1
            card.transform = .identity
        }
        
        dailySummaryCard = card
        hasDailySummaryData = true
    }
    
    func removeDailySummaryCard() {
        guard let card = dailySummaryCard else { return }
        
        // Restore segmented control constraint
        contentSegmentedControl.constraints.forEach { constraint in
            if constraint.firstItem === contentSegmentedControl && 
               constraint.firstAttribute == .top &&
               constraint.secondItem === card {
                constraint.isActive = false
            }
        }
        
        contentSegmentedControl.topAnchor.constraint(equalTo: activityHeaderLabel.bottomAnchor, constant: Constants.Spacing.small).isActive = true
        
        // Animate out
        UIView.animate(withDuration: 0.3, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: -20)
        }) { _ in
            card.removeFromSuperview()
        }
        
        dailySummaryCard = nil
        hasDailySummaryData = false
    }
}

// MARK: - DailySummaryCardViewDelegate
extension CirclesHomeViewController: DailySummaryCardViewDelegate {
    func dailySummaryCardDidTapNewPlaces() {
        // Already on home tab, just scroll to map
        scrollView.setContentOffset(.zero, animated: true)
    }
    
    func dailySummaryCardDidTapNewConnections() {
        // Navigate to network tab
        if let tabBarController = tabBarController {
            tabBarController.selectedIndex = 1
        }
    }
    
    func dailySummaryCardDidTapUnreadMessages() {
        // Navigate to messages tab
        if let tabBarController = tabBarController {
            tabBarController.selectedIndex = 2
        }
    }
    
    func dailySummaryCardDidTapClose() {
        removeDailySummaryCard()
        
        // Clear the stored data for today
        if let latestKey = UserDefaults.standard.string(forKey: "latestDailySummaryKey") {
            UserDefaults.standard.removeObject(forKey: latestKey)
            UserDefaults.standard.removeObject(forKey: "latestDailySummaryKey")
        }
    }
    
    func dailySummaryCardDidExpand() {
        // Track analytics if needed
        Logger.debug("📊 Daily summary expanded")
    }
    
    func dailySummaryCardDidCollapse() {
        // Track analytics if needed
        Logger.debug("📊 Daily summary collapsed")
    }
}

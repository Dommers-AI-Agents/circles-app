import UIKit

class CirclesTabBarController: UITabBarController, UITabBarControllerDelegate {
    
    private var badgeObservers: [NSObjectProtocol] = []
    private var messagesBadgeTimer: Timer?
    private var networkBadgeTimer: Timer?
    private var macKeyCommands: [UIKeyCommand] = []
    
    // Check if running on Mac
    private var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Use appropriate setup based on platform
        if isRunningOnMac {
            setupTabsForMac()
            setupTabBarAppearanceForMac()
            setupKeyboardShortcuts()
        } else {
            setupTabs()
            setupTabBarAppearance()
        }
        
        setupBadgeObservers()
        setupNotificationObservers()
        
        // Set self as delegate
        self.delegate = self
        
        // Update badges on load
        updateMessagesBadge()
        updateNetworkBadge()
        
        // Set initial messages tab state (default is Circles tab which is index 0)
        MessagingManager.shared.setMessagesTabActive(selectedIndex == 2)
        
        // Configure API logging level
        #if DEBUG
        // For debug builds, you can set verbose logging if needed
        // APIService.shared.setLogLevel(APIService.APILogLevel.verbose)
        APIService.shared.setLogLevel(APIService.APILogLevel.errors) // Only errors by default
        #else
        // For release builds, only log errors
        APIService.shared.setLogLevel(APIService.APILogLevel.errors)
        #endif
    }
    
    deinit {
        badgeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        messagesBadgeTimer?.invalidate()
        networkBadgeTimer?.invalidate()
    }
    
    private func setupTabBarAppearance() {
        // Customize tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = Constants.Colors.secondaryBackground
        
        // Configure item appearance
        appearance.stackedLayoutAppearance.normal.iconColor = Constants.Colors.secondaryLabel
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: Constants.Colors.secondaryLabel]
        
        appearance.stackedLayoutAppearance.selected.iconColor = Constants.Colors.primary
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: Constants.Colors.primary]
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        
        // Set tint color for selected items
        tabBar.tintColor = Constants.Colors.primary
    }
    
    private func setupTabs() {
        // Create view controllers for each tab
        let circlesVC = UINavigationController(rootViewController: CirclesHomeViewController())
        circlesVC.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "circle.grid.2x2"), tag: 0)
        
        let networkVC = UINavigationController(rootViewController: MyNetworkViewController())
        networkVC.tabBarItem = UITabBarItem(title: "My Network", image: UIImage(systemName: "person.2"), tag: 1)
        
        let messagesVC = UINavigationController(rootViewController: ConversationsListViewController())
        messagesVC.tabBarItem = UITabBarItem(title: "Messages", image: UIImage(systemName: "message"), tag: 2)
        
        // Discover tab commented out for now
        // let discoverVC = UINavigationController(rootViewController: DiscoverViewController())
        // discoverVC.tabBarItem = UITabBarItem(title: "Discover", image: UIImage(systemName: "magnifyingglass"), tag: 3)
        
        let profileVC = UINavigationController(rootViewController: ProfileViewController())
        profileVC.tabBarItem = UITabBarItem(title: "Me", image: UIImage(systemName: "person"), tag: 3)
        
        // Set view controllers to tab bar in the new order (without Discover)
        self.viewControllers = [circlesVC, networkVC, messagesVC, profileVC]
    }
    
    private func setupTabsForMac() {
        // Create view controllers for each tab with Mac-optimized icons
        let circlesVC = UINavigationController(rootViewController: CirclesHomeViewController())
        let circlesImage = UIImage(systemName: "circle.grid.2x2.fill") ?? UIImage(systemName: "circle.grid.2x2")!
        circlesVC.tabBarItem = UITabBarItem(title: nil, image: circlesImage, tag: 0)
        
        let networkVC = UINavigationController(rootViewController: MyNetworkViewController())
        let networkImage = UIImage(systemName: "person.2.fill") ?? UIImage(systemName: "person.2")!
        networkVC.tabBarItem = UITabBarItem(title: nil, image: networkImage, tag: 1)
        
        let messagesVC = UINavigationController(rootViewController: ConversationsListViewController())
        let messagesImage = UIImage(systemName: "message.fill") ?? UIImage(systemName: "message")!
        messagesVC.tabBarItem = UITabBarItem(title: nil, image: messagesImage, tag: 2)
        
        // Discover tab commented out for now
        // let discoverVC = UINavigationController(rootViewController: DiscoverViewController())
        // let discoverImage = UIImage(systemName: "magnifyingglass.circle.fill") ?? UIImage(systemName: "magnifyingglass")!
        // discoverVC.tabBarItem = UITabBarItem(title: nil, image: discoverImage, tag: 3)
        
        let profileVC = UINavigationController(rootViewController: ProfileViewController())
        let profileImage = UIImage(systemName: "person.circle.fill") ?? UIImage(systemName: "person")!
        profileVC.tabBarItem = UITabBarItem(title: nil, image: profileImage, tag: 3)
        
        // Set view controllers (without Discover)
        self.viewControllers = [circlesVC, networkVC, messagesVC, profileVC]
        
        // Configure icon sizes for Mac
        if #available(iOS 13.0, *) {
            let iconSize = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            viewControllers?.forEach { vc in
                vc.tabBarItem.image = vc.tabBarItem.image?.withConfiguration(iconSize)
            }
        }
    }
    
    private func setupTabBarAppearanceForMac() {
        // Customize tab bar appearance for Mac with compact design
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = Constants.Colors.secondaryBackground
        
        // Make the tab bar more compact
        appearance.compactInlineLayoutAppearance = appearance.inlineLayoutAppearance
        appearance.stackedLayoutAppearance.normal.iconColor = Constants.Colors.secondaryLabel
        appearance.stackedLayoutAppearance.selected.iconColor = Constants.Colors.primary
        
        // Remove title positioning to save space
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
        appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        
        // Set tint color for selected items
        tabBar.tintColor = Constants.Colors.primary
        
        // Additional Mac-specific adjustments
        tabBar.itemPositioning = .centered
        tabBar.itemSpacing = 20 // Tighter spacing between items
    }
    
    // MARK: - Badge Management
    
    private func setupBadgeObservers() {
        // Listen for unread message count changes
        let messagesObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UnreadMessagesCountChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMessagesBadge()
        }
        badgeObservers.append(messagesObserver)
        
        // Listen for pending connection requests
        let networkObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("PendingConnectionsCountChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateNetworkBadge()
        }
        badgeObservers.append(networkObserver)
    }
    
    private func setupNotificationObservers() {
        // Handle navigation from push notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateToMessages),
            name: Notification.Name("NavigateToMessages"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateToNetwork),
            name: Notification.Name("NavigateToNetwork"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateToCircle(_:)),
            name: Notification.Name("NavigateToCircle"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateToDailySummary(_:)),
            name: Notification.Name("NavigateToDailySummary"),
            object: nil
        )
    }
    
    private func updateMessagesBadge() {
        // Cancel any existing timer
        messagesBadgeTimer?.invalidate()
        
        // Debounce the update by 0.5 seconds
        messagesBadgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            // Get unread messages count from MessagingManager
            let count = MessagingManager.shared.unreadCount
            DispatchQueue.main.async {
                self?.viewControllers?[2].tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
                self?.updateApplicationBadge()
            }
        }
    }
    
    private func updateNetworkBadge() {
        // Cancel any existing timer
        networkBadgeTimer?.invalidate()
        
        // Debounce the update by 0.5 seconds
        networkBadgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            // Get pending connections count
            NetworkManager.shared.getPendingConnectionsCount { [weak self] count in
                DispatchQueue.main.async {
                    self?.viewControllers?[1].tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
                    self?.updateApplicationBadge()
                }
            }
        }
    }
    
    private func updateApplicationBadge() {
        // Calculate total badge count
        var totalCount = 0
        
        if let messagesCount = viewControllers?[2].tabBarItem.badgeValue,
           let count = Int(messagesCount) {
            totalCount += count
        }
        
        if let networkCount = viewControllers?[1].tabBarItem.badgeValue,
           let count = Int(networkCount) {
            totalCount += count
        }
        
        // Update app icon badge
        NotificationService.shared.updateApplicationBadge(count: totalCount)
    }
    
    // MARK: - Navigation
    
    @objc private func navigateToMessages() {
        selectedIndex = 2 // Messages tab
    }
    
    @objc private func navigateToNetwork() {
        selectedIndex = 1 // Network tab
    }
    
    @objc private func navigateToCircle(_ notification: Notification) {
        guard let circleId = notification.object as? String else { return }
        
        // Navigate to circles tab first
        selectedIndex = 0
        
        // Then navigate to specific circle
        if let navController = viewControllers?[0] as? UINavigationController,
           let circlesVC = navController.topViewController as? CirclesHomeViewController {
            circlesVC.navigateToCircle(withId: circleId)
        }
    }
    
    @objc private func navigateToDailySummary(_ notification: Notification) {
        // Navigate to Home tab (index 0)
        selectedIndex = 0
        
        // Tell the CirclesHomeViewController to fetch and show the daily summary
        if let navController = viewControllers?[0] as? UINavigationController,
           let circlesVC = navController.topViewController as? CirclesHomeViewController {
            // Let the home view controller fetch and display the daily summary
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                circlesVC.fetchAndShowDailySummary()
            }
        }
    }
    
    // MARK: - UITabBarControllerDelegate
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Check if user tapped the same tab they're already on
        if let currentIndex = viewControllers?.firstIndex(of: selectedViewController ?? UIViewController()),
           let tappedIndex = viewControllers?.firstIndex(of: viewController),
           currentIndex == tappedIndex {
            
            // User tapped the same tab - trigger refresh for that tab
            if let navController = viewController as? UINavigationController {
                switch currentIndex {
                case 0: // Home tab
                    if let circlesVC = navController.topViewController as? CirclesHomeViewController {
                        circlesVC.scrollToTop()
                        circlesVC.refreshData()
                    }
                case 1: // My Network tab
                    if let networkVC = navController.topViewController as? MyNetworkViewController {
                        networkVC.loadData()
                    }
                case 2: // Messages tab
                    if let messagesVC = navController.topViewController as? ConversationsListViewController {
                        messagesVC.refreshConversations()
                    }
                case 3: // Profile tab
                    if let profileVC = navController.topViewController as? ProfileViewController {
                        profileVC.resetToListViewIfNeeded()
                        profileVC.loadData()
                    }
                default:
                    break
                }
            }
        }
        
        return true // Allow the selection to proceed
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        // Update MessagingManager based on selected tab
        let isMessagesTab = tabBarController.selectedIndex == 2
        MessagingManager.shared.setMessagesTabActive(isMessagesTab)
        
        // Clear pending requests when switching to Profile tab
        if tabBarController.selectedIndex == 3 { // Profile tab (was 4, now 3 without Discover)
            APIService.shared.clearPendingRequests()
        }
    }
    
    // MARK: - Keyboard Shortcuts for Mac
    
    private func setupKeyboardShortcuts() {
        #if targetEnvironment(macCatalyst)
        // Add keyboard shortcuts for tab navigation
        macKeyCommands = [
            UIKeyCommand(title: "Home", action: #selector(selectTab1), input: "1", modifierFlags: .command),
            UIKeyCommand(title: "My Network", action: #selector(selectTab2), input: "2", modifierFlags: .command),
            UIKeyCommand(title: "Messages", action: #selector(selectTab3), input: "3", modifierFlags: .command),
            // UIKeyCommand(title: "Discover", action: #selector(selectTab4), input: "4", modifierFlags: .command),
            UIKeyCommand(title: "Me", action: #selector(selectTab4), input: "4", modifierFlags: .command)
        ]
        #endif
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return isRunningOnMac ? macKeyCommands : nil
    }
    
    @objc private func selectTab1() {
        selectedIndex = 0
    }
    
    @objc private func selectTab2() {
        selectedIndex = 1
    }
    
    @objc private func selectTab3() {
        selectedIndex = 2
    }
    
    @objc private func selectTab4() {
        selectedIndex = 3 // Profile tab (Me)
    }
    
    // Commented out - Discover tab no longer in use
    // @objc private func selectTab5() {
    //     selectedIndex = 4
    // }
}

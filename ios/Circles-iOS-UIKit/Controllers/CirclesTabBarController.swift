import UIKit

class CirclesTabBarController: UITabBarController, UITabBarControllerDelegate {
    
    private var badgeObservers: [NSObjectProtocol] = []
    private var messagesBadgeTimer: Timer?
    private var networkBadgeTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupTabBarAppearance()
        setupBadgeObservers()
        setupNotificationObservers()
        
        // Set self as delegate
        self.delegate = self
        
        // Update badges on load
        updateMessagesBadge()
        updateNetworkBadge()
        
        // Set initial messages tab state (default is Circles tab which is index 0)
        MessagingManager.shared.setMessagesTabActive(selectedIndex == 2)
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
        circlesVC.tabBarItem = UITabBarItem(title: "My Circles", image: UIImage(systemName: "circle.grid.2x2"), tag: 0)
        
        let networkVC = UINavigationController(rootViewController: MyNetworkViewController())
        networkVC.tabBarItem = UITabBarItem(title: "My Network", image: UIImage(systemName: "person.2"), tag: 1)
        
        let messagesVC = UINavigationController(rootViewController: ConversationsListViewController())
        messagesVC.tabBarItem = UITabBarItem(title: "Messages", image: UIImage(systemName: "message"), tag: 2)
        
        let discoverVC = UINavigationController(rootViewController: DiscoverViewController())
        discoverVC.tabBarItem = UITabBarItem(title: "Discover", image: UIImage(systemName: "magnifyingglass"), tag: 3)
        
        let profileVC = UINavigationController(rootViewController: ProfileViewController())
        profileVC.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 4)
        
        // Set view controllers to tab bar in the new order
        self.viewControllers = [circlesVC, networkVC, messagesVC, discoverVC, profileVC]
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
    
    // MARK: - UITabBarControllerDelegate
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        // Update MessagingManager based on selected tab
        let isMessagesTab = tabBarController.selectedIndex == 2
        MessagingManager.shared.setMessagesTabActive(isMessagesTab)
    }
}

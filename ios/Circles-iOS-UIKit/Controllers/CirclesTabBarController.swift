import UIKit

class CirclesTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupTabBarAppearance()
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
        circlesVC.tabBarItem = UITabBarItem(title: "Circles", image: UIImage(systemName: "circle.grid.2x2"), tag: 0)
        
        let discoverVC = UINavigationController(rootViewController: DiscoverViewController())
        discoverVC.tabBarItem = UITabBarItem(title: "Discover", image: UIImage(systemName: "magnifyingglass"), tag: 1)
        
        let networkVC = UINavigationController(rootViewController: MyNetworkViewController())
        networkVC.tabBarItem = UITabBarItem(title: "Network", image: UIImage(systemName: "person.2"), tag: 2)
        
        let messagesVC = UINavigationController(rootViewController: ConversationsListViewController())
        messagesVC.tabBarItem = UITabBarItem(title: "Messages", image: UIImage(systemName: "message"), tag: 3)
        
        let profileVC = UINavigationController(rootViewController: ProfileViewController())
        profileVC.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 4)
        
        // Set view controllers to tab bar
        self.viewControllers = [circlesVC, discoverVC, networkVC, messagesVC, profileVC]
    }
}

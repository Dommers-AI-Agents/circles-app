import UIKit

class CirclesTabBarController: UITabBarController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
    }
    
    private func setupTabs() {
        // Create view controllers for each tab
        let circlesVC = UINavigationController(rootViewController: CirclesHomeViewController())
        circlesVC.tabBarItem = UITabBarItem(title: "Circles", image: UIImage(systemName: "circle.grid.2x2"), tag: 0)
        
        let discoverVC = UINavigationController(rootViewController: DiscoverViewController())
        discoverVC.tabBarItem = UITabBarItem(title: "Discover", image: UIImage(systemName: "magnifyingglass"), tag: 1)
        
        let createVC = UINavigationController(rootViewController: CreateCircleViewController())
        createVC.tabBarItem = UITabBarItem(title: "Create", image: UIImage(systemName: "plus.circle"), tag: 2)
        
        let profileVC = UINavigationController(rootViewController: ProfileViewController())
        profileVC.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person"), tag: 3)
        
        // Set view controllers to tab bar
        self.viewControllers = [circlesVC, discoverVC, createVC, profileVC]
    }
}

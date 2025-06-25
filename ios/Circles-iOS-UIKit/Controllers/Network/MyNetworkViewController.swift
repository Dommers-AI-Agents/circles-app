import UIKit

class MyNetworkViewController: UIViewController {
    
    // MARK: - UI Elements
    private let segmentedControl: UISegmentedControl = {
        let items = ["Connections", "Shared Circles"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Child View Controllers
    private var connectionsListVC: ConnectionsListViewController?
    private var sharedCirclesListVC: SharedCirclesListViewController?
    private var currentViewController: UIViewController?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupChildViewControllers()
        showConnectionsList()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        // Set the navigation title
        title = "My Network"
        
        // Set large title display mode
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        
        // Add views
        view.addSubview(segmentedControl)
        view.addSubview(containerView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Add action for segmented control
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }
    
    private func setupNavigationBar() {
        // Add the connection button
        let addConnectionButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(showConnectionMenu)
        )
        navigationItem.rightBarButtonItem = addConnectionButton
    }
    
    private func setupChildViewControllers() {
        // Create child view controllers
        connectionsListVC = ConnectionsListViewController()
        sharedCirclesListVC = SharedCirclesListViewController()
    }
    
    // MARK: - Actions
    @objc private func segmentChanged() {
        if segmentedControl.selectedSegmentIndex == 0 {
            showConnectionsList()
        } else {
            showSharedCirclesList()
        }
    }
    
    @objc private func showConnectionMenu() {
        // Directly show the share sheet without a menu
        shareConnectionInvite()
    }
    
    private func shareConnectionInvite() {
        let shareItems = NetworkManager.shared.shareConnectionInvite()
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    // MARK: - Child View Controller Management
    private func showConnectionsList() {
        guard let connectionsListVC = connectionsListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        addChild(connectionsListVC)
        containerView.addSubview(connectionsListVC.view)
        connectionsListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            connectionsListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            connectionsListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            connectionsListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            connectionsListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        connectionsListVC.didMove(toParent: self)
        currentViewController = connectionsListVC
    }
    
    private func showSharedCirclesList() {
        guard let sharedCirclesListVC = sharedCirclesListVC else { return }
        
        if currentViewController != nil {
            removeCurrentViewController()
        }
        
        addChild(sharedCirclesListVC)
        containerView.addSubview(sharedCirclesListVC.view)
        sharedCirclesListVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            sharedCirclesListVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            sharedCirclesListVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            sharedCirclesListVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            sharedCirclesListVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        sharedCirclesListVC.didMove(toParent: self)
        currentViewController = sharedCirclesListVC
    }
    
    private func removeCurrentViewController() {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()
        currentViewController = nil
    }
}
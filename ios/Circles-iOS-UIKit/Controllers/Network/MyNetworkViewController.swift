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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        // Add the search button
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchButtonTapped)
        )
        
        // Add the connection button
        let addConnectionButton = UIBarButtonItem(
            image: UIImage(systemName: "person.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(showConnectionMenu)
        )
        
        navigationItem.rightBarButtonItems = [addConnectionButton, searchButton]
    }
    
    private func setupChildViewControllers() {
        // Create child view controllers
        connectionsListVC = ConnectionsListViewController()
        sharedCirclesListVC = SharedCirclesListViewController()
    }
    
    // MARK: - Actions
    @objc private func segmentChanged() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            showConnectionsList()
        case 1:
            showSharedCirclesList()
        default:
            break
        }
    }
    
    @objc private func showConnectionMenu() {
        // Directly show the share sheet without a menu
        shareConnectionInvite()
    }
    
    @objc private func searchButtonTapped() {
        let searchVC = UserSearchViewController()
        searchVC.delegate = self
        let navController = UINavigationController(rootViewController: searchVC)
        present(navController, animated: true)
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

// MARK: - UserSearchViewControllerDelegate
extension MyNetworkViewController: UserSearchViewControllerDelegate {
    func userSearchViewController(_ controller: UserSearchViewController, didSelectUser user: User) {
        // Dismiss the search controller
        controller.dismiss(animated: true) { [weak self] in
            // Send connection request
            self?.sendConnectionRequest(to: user)
        }
    }
    
    private func sendConnectionRequest(to user: User) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Sending Request", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        NetworkManager.shared.sendConnectionRequest(to: user.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        let successAlert = UIAlertController(
                            title: "Request Sent",
                            message: "Connection request sent to \(user.displayName)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(successAlert, animated: true)
                        
                        // Refresh connections list if it's currently showing
                        if self?.segmentedControl.selectedSegmentIndex == 0 {
                            self?.connectionsListVC?.loadConnections()
                        }
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
}
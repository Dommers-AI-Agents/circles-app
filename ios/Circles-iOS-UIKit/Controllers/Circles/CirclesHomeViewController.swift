import UIKit
import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

class CirclesHomeViewController: UIViewController {
    
    // MARK: - Properties
    private var circles: [Circle] = []
    private var networkCircles: [Circle] = []
    private var isShowingNetworkCircles = false
    private let refreshControl = UIRefreshControl()
    
    // MARK: - UI Elements
    private let quickAccessContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let homeCard: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.lightGray.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let workCard: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.lightGray.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let homeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let workButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let homeNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let workNavigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let filterContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    
    private let myNetworkCirclesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("My Network's Circles", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.backgroundColor = Constants.Colors.tertiaryBackground
        button.tintColor = Constants.Colors.primary
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let suggestionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Suggestions", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.backgroundColor = Constants.Colors.tertiaryBackground
        button.tintColor = Constants.Colors.primary
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let suggestionsBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = .systemRed
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.register(CircleTableViewCell.self, forCellReuseIdentifier: "CircleCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyStateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "circle.dashed")
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "You don't have any circles yet"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let createCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create a Circle", for: .normal)
        button.setTitleColor(Constants.Colors.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupNotifications()
        checkForNewSuggestions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchCircles()
        checkForNewSuggestions()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update colors when dark mode changes
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAppearance()
        }
    }
    
    private func updateAppearance() {
        // Update border colors that don't automatically adapt
        homeCard.layer.borderColor = Constants.Colors.separator.cgColor
        workCard.layer.borderColor = Constants.Colors.separator.cgColor
        quickAccessContainer.layer.shadowColor = Constants.Colors.label.cgColor
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        navigationController?.navigationBar.prefersLargeTitles = true
        title = "My Circles"
        
        // Setup navigation bar
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped))
        navigationItem.rightBarButtonItem = addButton
        
        // Add tap gesture to navigation bar for returning to My Circles
        setupNavigationTitleTap()
        
        // Setup empty state view
        emptyStateView.addSubview(emptyStateImageView)
        emptyStateView.addSubview(emptyStateLabel)
        emptyStateView.addSubview(createCircleButton)
        
        // Setup quick access buttons
        setupQuickAccessButtons()
        
        view.addSubview(quickAccessContainer)
        quickAccessContainer.addSubview(homeCard)
        quickAccessContainer.addSubview(workCard)
        homeCard.addSubview(homeButton)
        homeCard.addSubview(homeNavigateButton)
        workCard.addSubview(workButton)
        workCard.addSubview(workNavigateButton)
        view.addSubview(filterContainer)
        filterContainer.addSubview(myNetworkCirclesButton)
        filterContainer.addSubview(suggestionsButton)
        filterContainer.addSubview(suggestionsBadge)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            // Quick access container
            quickAccessContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            quickAccessContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickAccessContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            quickAccessContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Home card
            homeCard.leadingAnchor.constraint(equalTo: quickAccessContainer.leadingAnchor, constant: Constants.Spacing.large),
            homeCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            homeCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.42),
            homeCard.heightAnchor.constraint(equalToConstant: 60),
            
            // Work card
            workCard.trailingAnchor.constraint(equalTo: quickAccessContainer.trailingAnchor, constant: -Constants.Spacing.large),
            workCard.centerYAnchor.constraint(equalTo: quickAccessContainer.centerYAnchor),
            workCard.widthAnchor.constraint(equalTo: quickAccessContainer.widthAnchor, multiplier: 0.42),
            workCard.heightAnchor.constraint(equalToConstant: 60),
            
            // Home button (inside home card)
            homeButton.leadingAnchor.constraint(equalTo: homeCard.leadingAnchor),
            homeButton.topAnchor.constraint(equalTo: homeCard.topAnchor),
            homeButton.bottomAnchor.constraint(equalTo: homeCard.bottomAnchor),
            homeButton.trailingAnchor.constraint(equalTo: homeNavigateButton.leadingAnchor, constant: -8),
            
            // Home navigate button
            homeNavigateButton.centerYAnchor.constraint(equalTo: homeCard.centerYAnchor),
            homeNavigateButton.trailingAnchor.constraint(equalTo: homeCard.trailingAnchor, constant: -8),
            homeNavigateButton.widthAnchor.constraint(equalToConstant: 30),
            homeNavigateButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Work button (inside work card)
            workButton.leadingAnchor.constraint(equalTo: workCard.leadingAnchor),
            workButton.topAnchor.constraint(equalTo: workCard.topAnchor),
            workButton.bottomAnchor.constraint(equalTo: workCard.bottomAnchor),
            workButton.trailingAnchor.constraint(equalTo: workNavigateButton.leadingAnchor, constant: -8),
            
            // Work navigate button
            workNavigateButton.centerYAnchor.constraint(equalTo: workCard.centerYAnchor),
            workNavigateButton.trailingAnchor.constraint(equalTo: workCard.trailingAnchor, constant: -8),
            workNavigateButton.widthAnchor.constraint(equalToConstant: 30),
            workNavigateButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Filter container
            filterContainer.topAnchor.constraint(equalTo: quickAccessContainer.bottomAnchor),
            filterContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // My Network's Circles button
            myNetworkCirclesButton.leadingAnchor.constraint(equalTo: filterContainer.leadingAnchor, constant: Constants.Spacing.large),
            myNetworkCirclesButton.centerYAnchor.constraint(equalTo: filterContainer.centerYAnchor),
            myNetworkCirclesButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Suggestions button
            suggestionsButton.leadingAnchor.constraint(equalTo: myNetworkCirclesButton.trailingAnchor, constant: Constants.Spacing.medium),
            suggestionsButton.centerYAnchor.constraint(equalTo: filterContainer.centerYAnchor),
            suggestionsButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Suggestions badge
            suggestionsBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            suggestionsBadge.heightAnchor.constraint(equalToConstant: 20),
            suggestionsBadge.leadingAnchor.constraint(equalTo: suggestionsButton.trailingAnchor, constant: -12),
            suggestionsBadge.bottomAnchor.constraint(equalTo: suggestionsButton.topAnchor, constant: 8),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: filterContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            
            emptyStateImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyStateImageView.widthAnchor.constraint(equalToConstant: 100),
            emptyStateImageView.heightAnchor.constraint(equalToConstant: 100),
            
            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateImageView.bottomAnchor, constant: Constants.Spacing.medium),
            emptyStateLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            createCircleButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: Constants.Spacing.large),
            createCircleButton.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            createCircleButton.widthAnchor.constraint(equalTo: emptyStateView.widthAnchor, multiplier: 0.8),
            createCircleButton.heightAnchor.constraint(equalToConstant: 44),
            createCircleButton.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
        
        createCircleButton.addTarget(self, action: #selector(createCircleButtonTapped), for: .touchUpInside)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupQuickAccessButtons() {
        // Configure Home button
        var homeConfig = UIButton.Configuration.filled()
        homeConfig.image = UIImage(systemName: "house.fill")
        homeConfig.title = "Home"
        homeConfig.imagePlacement = .leading
        homeConfig.imagePadding = 8
        homeConfig.baseBackgroundColor = .clear
        homeConfig.baseForegroundColor = Constants.Colors.primary
        homeConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        homeButton.configuration = homeConfig
        homeButton.addTarget(self, action: #selector(homeButtonTapped), for: .touchUpInside)
        
        // Configure Work button
        var workConfig = UIButton.Configuration.filled()
        workConfig.image = UIImage(systemName: "building.2.fill")
        workConfig.title = "Work"
        workConfig.imagePlacement = .leading
        workConfig.imagePadding = 8
        workConfig.baseBackgroundColor = .clear
        workConfig.baseForegroundColor = Constants.Colors.secondary
        workConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 0)
        workButton.configuration = workConfig
        workButton.addTarget(self, action: #selector(workButtonTapped), for: .touchUpInside)
        
        // Add targets for navigate buttons
        homeNavigateButton.addTarget(self, action: #selector(homeNavigateButtonTapped), for: .touchUpInside)
        workNavigateButton.addTarget(self, action: #selector(workNavigateButtonTapped), for: .touchUpInside)
        
        // Add targets for filter buttons
        myNetworkCirclesButton.addTarget(self, action: #selector(myNetworkCirclesButtonTapped), for: .touchUpInside)
        suggestionsButton.addTarget(self, action: #selector(suggestionsButtonTapped), for: .touchUpInside)
        
        // Add shadow to container
        quickAccessContainer.layer.shadowOpacity = 0.05
        quickAccessContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        quickAccessContainer.layer.shadowRadius = 4
        
        // Apply appearance
        updateAppearance()
    }
    
    private func setupNavigationTitleTap() {
        // Create a custom title view that's tappable
        let titleLabel = UILabel()
        titleLabel.text = "My Circles"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.isUserInteractionEnabled = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(navigationTitleTapped))
        titleLabel.addGestureRecognizer(tapGesture)
        
        navigationItem.titleView = titleLabel
    }
    
    @objc private func navigationTitleTapped() {
        // Return to My Circles tab if not already there
        if isShowingNetworkCircles {
            isShowingNetworkCircles = false
            updateFilterButtons()
            tableView.reloadData()
            updateEmptyState()
        }
    }
    
    // MARK: - Data Fetching
    private func fetchCircles() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    print("✅ Successfully fetched \(circles.count) circles")
                    for circle in circles {
                        print("Circle: \(circle.name), coverImage: \(circle.coverImage ?? "nil")")
                    }
                    self?.circles = circles
                case .failure(let error):
                    print("❌ Error fetching circles: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                    // Don't use sample circles - show empty state instead
                    self?.circles = []
                }
                
                self?.tableView.reloadData()
                self?.updateEmptyState()
                self?.refreshControl.endRefreshing()
            }
        }
    }
    
    private func fetchNetworkCircles() {
        // Define response structure
        struct NetworkCirclesResponse: Codable {
            let success: Bool
            let data: [Circle]
        }
        
        // Use CircleService to fetch network circles
        APIService.shared.request(
            endpoint: "network/my-network-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<NetworkCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ Successfully fetched \(response.data.count) network circles")
                    self?.networkCircles = response.data
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                case .failure(let error):
                    print("❌ Error fetching network circles: \(error.localizedDescription)")
                    self?.networkCircles = []
                    self?.tableView.reloadData()
                    self?.updateEmptyState()
                }
                self?.refreshControl.endRefreshing()
            }
        }
    }
    
    private func createSampleCircles() -> [Circle] {
        let userId = AuthService.shared.getUserId() ?? "user123"
        
        let date = Date()
        
        // Create sample circles
        let travelCircle = Circle(
            id: "circle1",
            name: "New York Trip",
            description: "All my favorite places in NYC",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            places: ["place1", "place2", "place3"],
            placesWithDetails: nil,
            privacy: .private,
            allowNetworkEdit: false,
            category: .travel,
            location: "New York, NY",
            tags: ["travel", "nyc", "vacation"],
            sharedWith: ["friend1", "friend2"],
            followers: nil,
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 7), // 7 days ago
            updatedAt: date.addingTimeInterval(-3600) // 1 hour ago
        )
        
        let foodCircle = Circle(
            id: "circle2",
            name: "Best Restaurants",
            description: "My favorite places to eat",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            places: ["place4", "place5"],
            placesWithDetails: nil,
            privacy: .myNetwork,
            allowNetworkEdit: true,
            category: .food,
            location: nil,
            tags: ["food", "restaurants", "dining"],
            sharedWith: nil,
            followers: ["friend3", "friend4"],
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 14), // 14 days ago
            updatedAt: date.addingTimeInterval(-86400) // 1 day ago
        )
        
        let shoppingCircle = Circle(
            id: "circle3",
            name: "Shopping Spots",
            description: "Best places to shop",
            coverImage: nil,
            owner: userId,
            ownerDetails: nil,
            places: ["place6", "place7", "place8", "place9"],
            placesWithDetails: nil,
            privacy: .public,
            allowNetworkEdit: false,
            category: .shopping,
            location: nil,
            tags: ["shopping", "retail", "fashion"],
            sharedWith: nil,
            followers: ["friend5", "friend6", "friend7"],
            activeShares: nil,
            shareSettings: nil,
            isSharedWithMe: false,
            sharedBy: nil,
            myAccessLevel: nil,
            createdAt: date.addingTimeInterval(-86400 * 30), // 30 days ago
            updatedAt: date.addingTimeInterval(-43200) // 12 hours ago
        )
        
        return [travelCircle, foodCircle, shoppingCircle]
    }
    
    private func updateEmptyState() {
        let isEmpty = isShowingNetworkCircles ? networkCircles.isEmpty : circles.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        
        // Update empty state message based on filter
        if isShowingNetworkCircles {
            emptyStateLabel.text = "No circles from your network yet"
        } else {
            emptyStateLabel.text = "You don't have any circles yet"
        }
    }
    
    // MARK: - Suggestions Management
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateSuggestionsBadge(_:)),
            name: .suggestionsBadgeUpdate,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearSuggestionsBadge),
            name: .clearSuggestionsBadge,
            object: nil
        )
    }
    
    @objc private func updateSuggestionsBadge(_ notification: Notification) {
        guard let count = notification.userInfo?["count"] as? Int else { return }
        
        DispatchQueue.main.async { [weak self] in
            if count > 0 {
                self?.suggestionsBadge.text = "\(count)"
                self?.suggestionsBadge.isHidden = false
            } else {
                self?.suggestionsBadge.isHidden = true
            }
        }
    }
    
    @objc private func clearSuggestionsBadge() {
        DispatchQueue.main.async { [weak self] in
            self?.suggestionsBadge.isHidden = true
        }
    }
    
    private func checkForNewSuggestions() {
        SuggestionService.shared.getUnreadSuggestionsCount { [weak self] count in
            DispatchQueue.main.async {
                if count > 0 {
                    self?.suggestionsBadge.text = "\(count)"
                    self?.suggestionsBadge.isHidden = false
                } else {
                    self?.suggestionsBadge.isHidden = true
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func addButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        navigationController?.pushViewController(createCircleVC, animated: true)
    }
    
    @objc private func createCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        navigationController?.pushViewController(createCircleVC, animated: true)
    }
    
    @objc private func refreshData() {
        if isShowingNetworkCircles {
            fetchNetworkCircles()
        } else {
            fetchCircles()
        }
    }
    
    @objc private func homeButtonTapped() {
        handleQuickAccessTapped(type: .home)
    }
    
    @objc private func workButtonTapped() {
        handleQuickAccessTapped(type: .work)
    }
    
    @objc private func homeNavigateButtonTapped() {
        navigateToQuickAccess(type: .home)
    }
    
    @objc private func workNavigateButtonTapped() {
        navigateToQuickAccess(type: .work)
    }
    
    
    @objc private func myNetworkCirclesButtonTapped() {
        // Navigate to NetworkUsersViewController instead of showing circles directly
        let networkUsersVC = NetworkUsersViewController()
        navigationController?.pushViewController(networkUsersVC, animated: true)
    }
    
    @objc private func suggestionsButtonTapped() {
        // Navigate to SuggestionsViewController instead of showing inline
        let suggestionsVC = SuggestionsViewController()
        navigationController?.pushViewController(suggestionsVC, animated: true)
    }
    
    private func updateFilterButtons() {
        // Since we're always showing My Circles (no tab for it), just reset the other buttons
        myNetworkCirclesButton.backgroundColor = Constants.Colors.tertiaryBackground
        myNetworkCirclesButton.tintColor = Constants.Colors.primary
        suggestionsButton.backgroundColor = Constants.Colors.tertiaryBackground
        suggestionsButton.tintColor = Constants.Colors.primary
    }
    
    private func navigateToQuickAccess(type: QuickAccessType) {
        let key = type == .home ? "userHomeAddress" : "userWorkAddress"
        let savedAddress = UserDefaults.standard.string(forKey: key)
        
        if let address = savedAddress, !address.isEmpty {
            // Create the same place object that would be created for viewing
            // This ensures we use the same geocoded location
            navigateToQuickAccessPlace(type: type, address: address, directNavigation: true)
        } else {
            // Show setup prompt
            let alert = UIAlertController(
                title: "Set \(type.rawValue) Address",
                message: "You need to set your \(type.rawValue.lowercased()) address first.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Set Address", style: .default) { [weak self] _ in
                self?.showAddressEntry(for: type)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }
    
    private func handleQuickAccessTapped(type: QuickAccessType) {
        // Check if address is already saved
        let key = type == .home ? "userHomeAddress" : "userWorkAddress"
        let savedAddress = UserDefaults.standard.string(forKey: key)
        
        if let address = savedAddress, !address.isEmpty {
            // Create a place from saved address and navigate to detail view
            navigateToQuickAccessPlace(type: type, address: address)
        } else {
            // Show address entry
            showAddressEntry(for: type)
        }
    }
    
    private func showAddressEntry(for type: QuickAccessType) {
        let alert = UIAlertController(
            title: "Set \(type.rawValue) Address",
            message: "Enter your \(type.rawValue.lowercased()) address",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "123 Main St, City, State"
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let address = alert.textFields?.first?.text, !address.isEmpty {
                // Save address
                let key = type == .home ? "userHomeAddress" : "userWorkAddress"
                UserDefaults.standard.set(address, forKey: key)
                
                // Navigate to place detail
                self?.navigateToQuickAccessPlace(type: type, address: address)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func navigateToQuickAccessPlace(type: QuickAccessType, address: String, directNavigation: Bool = false) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading", message: "Finding location...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Geocode the address to get coordinates
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
            loadingAlert.dismiss(animated: true) {
                guard let self = self else { return }
                
                var location: GeoLocation? = nil
                if let placemark = placemarks?.first,
                   let clLocation = placemark.location {
                    // Convert to GeoLocation format (MongoDB uses [longitude, latitude])
                    location = GeoLocation(type: "Point", coordinates: [clLocation.coordinate.longitude, clLocation.coordinate.latitude])
                }
                
                if directNavigation {
                    // Navigate directly using the geocoded location
                    if let location = location?.clLocation {
                        // Try Google Maps first
                        let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
                        
                        if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else {
                            // Fallback to Apple Maps
                            let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                            if let url = appleMapsURL {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        let alert = UIAlertController(title: "Navigation Error", message: "Could not find location for this address.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                } else {
                    // Show home/work address details
                    self.showAddressDetails(type: type, address: address, location: location)
                }
            }
        }
    }
    
    private func showAddressDetails(type: QuickAccessType, address: String, location: GeoLocation?) {
        let detailVC = UIViewController()
        detailVC.view.backgroundColor = .systemBackground
        detailVC.title = type.rawValue
        
        // Create content stack view
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Address section
        let addressContainer = UIView()
        addressContainer.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.1)
        addressContainer.layer.cornerRadius = 12
        
        let addressLabel = UILabel()
        addressLabel.text = "Address"
        addressLabel.font = .systemFont(ofSize: 14, weight: .medium)
        addressLabel.textColor = .secondaryLabel
        
        let addressValueLabel = UILabel()
        addressValueLabel.text = address
        addressValueLabel.font = .systemFont(ofSize: 16)
        addressValueLabel.numberOfLines = 0
        
        let addressStack = UIStackView(arrangedSubviews: [addressLabel, addressValueLabel])
        addressStack.axis = .vertical
        addressStack.spacing = 4
        addressStack.translatesAutoresizingMaskIntoConstraints = false
        
        addressContainer.addSubview(addressStack)
        NSLayoutConstraint.activate([
            addressStack.topAnchor.constraint(equalTo: addressContainer.topAnchor, constant: 16),
            addressStack.leadingAnchor.constraint(equalTo: addressContainer.leadingAnchor, constant: 16),
            addressStack.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -16),
            addressStack.bottomAnchor.constraint(equalTo: addressContainer.bottomAnchor, constant: -16)
        ])
        
        stackView.addArrangedSubview(addressContainer)
        
        // Navigate button
        let navigateButton = UIButton(type: .system)
        navigateButton.setTitle("Navigate", for: .normal)
        navigateButton.setImage(UIImage(systemName: "location.arrow"), for: .normal)
        navigateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        navigateButton.backgroundColor = Constants.Colors.primary
        navigateButton.setTitleColor(.white, for: .normal)
        navigateButton.tintColor = .white
        navigateButton.layer.cornerRadius = 12
        navigateButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        navigateButton.addAction(UIAction { [weak self] _ in
            if let location = location?.clLocation {
                // Try Google Maps first
                let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
                
                if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                } else {
                    // Fallback to Apple Maps
                    let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                    if let url = appleMapsURL {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }, for: .touchUpInside)
        
        stackView.addArrangedSubview(navigateButton)
        
        // Edit button
        let editButton = UIButton(type: .system)
        editButton.setTitle("Edit Address", for: .normal)
        editButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        editButton.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.2)
        editButton.layer.cornerRadius = 12
        editButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        editButton.addAction(UIAction { [weak self] _ in
            self?.setupQuickAccess(forType: type)
        }, for: .touchUpInside)
        
        stackView.addArrangedSubview(editButton)
        
        detailVC.view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: detailVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: detailVC.view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: detailVC.view.trailingAnchor, constant: -20)
        ])
        
        self.navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private enum QuickAccessType: String {
        case home = "Home"
        case work = "Work"
    }
    
    private func setupQuickAccess(forType type: QuickAccessType) {
        let alert = UIAlertController(title: "Set \(type.rawValue) Address", message: "Enter your \(type.rawValue.lowercased()) address", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter address"
            textField.autocapitalizationType = .words
            textField.returnKeyType = .done
            
            // Load existing address if available
            let key = type == .home ? "userHomeAddress" : "userWorkAddress"
            if let existingAddress = UserDefaults.standard.string(forKey: key) {
                textField.text = existingAddress
            }
        }
        
        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let address = alert.textFields?.first?.text, !address.isEmpty else { return }
            
            // Save to UserDefaults
            let key = type == .home ? "userHomeAddress" : "userWorkAddress"
            UserDefaults.standard.set(address, forKey: key)
            
            // Geocode the address
            let geocoder = CLGeocoder()
            geocoder.geocodeAddressString(address) { placemarks, error in
                if let placemark = placemarks?.first, let location = placemark.location {
                    // Save location
                    let locationKey = type == .home ? "userHomeLocation" : "userWorkLocation"
                    let locationData = [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude
                    ]
                    UserDefaults.standard.set(locationData, forKey: locationKey)
                    
                    // Update UI
                    DispatchQueue.main.async {
                        self?.setupQuickAccessButtons()
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(saveAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    // MARK: - Circle Management
    private func editCircle(at indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    private func deleteCircle(at indexPath: IndexPath) {
        let circle = circles[indexPath.row]
        
        let alert = UIAlertController(
            title: "Delete Circle",
            message: "Are you sure you want to delete '\(circle.name)'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(circle: circle, at: indexPath)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func performDelete(circle: Circle, at indexPath: IndexPath) {
        CircleService.shared.deleteCircle(id: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self?.circles.remove(at: indexPath.row)
                    self?.tableView.deleteRows(at: [indexPath], with: .fade)
                    self?.updateEmptyState()
                    
                case .failure(let error):
                    self?.presentAlert(
                        title: "Error",
                        message: "Failed to delete circle: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension CirclesHomeViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isShowingNetworkCircles ? networkCircles.count : circles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath) as? CircleTableViewCell else {
            return UITableViewCell()
        }
        
        let circle = isShowingNetworkCircles ? networkCircles[indexPath.row] : circles[indexPath.row]
        cell.configure(with: circle)
        cell.delegate = self
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 160
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let circle = isShowingNetworkCircles ? networkCircles[indexPath.row] : circles[indexPath.row]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Don't allow editing/deleting network circles
        if isShowingNetworkCircles {
            return nil
        }
        
        // Edit action
        let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            self?.editCircle(at: indexPath)
            completion(true)
        }
        editAction.backgroundColor = Constants.Colors.primary
        editAction.image = UIImage(systemName: "pencil")
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteCircle(at: indexPath)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
        configuration.performsFirstActionWithFullSwipe = false
        
        return configuration
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let circle = isShowingNetworkCircles ? networkCircles[indexPath.row] : circles[indexPath.row]
        
        // Don't show edit/delete options for network circles
        if isShowingNetworkCircles {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let viewAction = UIAction(
                    title: "View Circle",
                    image: UIImage(systemName: "eye")
                ) { [weak self] _ in
                    let detailVC = CircleDetailViewController(circle: circle)
                    self?.navigationController?.pushViewController(detailVC, animated: true)
                }
                
                return UIMenu(title: circle.name, children: [viewAction])
            }
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let editAction = UIAction(
                title: "Edit Circle",
                image: UIImage(systemName: "pencil")
            ) { _ in
                self?.editCircle(at: indexPath)
            }
            
            let deleteAction = UIAction(
                title: "Delete Circle",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.deleteCircle(at: indexPath)
            }
            
            return UIMenu(title: circle.name, children: [editAction, deleteAction])
        }
    }
    
    // MARK: - Drag Delegate
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Disable drag when showing network circles
        guard !isShowingNetworkCircles else { return [] }
        
        let circle = circles[indexPath.row]
        let itemProvider = NSItemProvider(object: circle.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = circle
        return [dragItem]
    }
    
    // MARK: - Drop Delegate
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.text.identifier])
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if tableView.hasActiveDrag {
            if session.items.count > 1 {
                return UITableViewDropProposal(operation: .cancel)
            } else {
                return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
        } else {
            return UITableViewDropProposal(operation: .forbidden)
        }
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        for item in coordinator.items {
            guard let sourceIndexPath = item.sourceIndexPath else { continue }
            
            tableView.performBatchUpdates({
                let movedCircle = circles.remove(at: sourceIndexPath.row)
                circles.insert(movedCircle, at: destinationIndexPath.row)
                tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
            })
            
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            
            // Update the order in the backend
            updateCircleOrder()
        }
    }
    
    // MARK: - Helper method to update circle order
    private func updateCircleOrder() {
        // Update the order of circles in the backend
        Task {
            do {
                // Create an array of circle IDs in the new order
                let orderedCircleIds = circles.map { $0.id }
                
                // Call the API to update the order
                try await CircleService.shared.updateCircleOrder(circleIds: orderedCircleIds)
                
                print("Circle order updated successfully")
            } catch {
                print("Failed to update circle order: \(error)")
                // Optionally, revert the changes if the API call fails
                await MainActor.run {
                    self.fetchCircles()
                }
            }
        }
    }
}

// MARK: - CircleTableViewCellDelegate
protocol CircleTableViewCellDelegate: AnyObject {
    func circleTableViewCell(_ cell: CircleTableViewCell, didTapShareForCircle circle: Circle)
}

// MARK: - CircleTableViewCell
class CircleTableViewCell: UITableViewCell {
    
    weak var delegate: CircleTableViewCellDelegate?
    private var circle: Circle?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addShadow(opacity: 0.1, radius: 5, offset: CGSize(width: 0, height: 2))
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.white
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private(set) var shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.setTitle(" Share", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = Constants.Colors.primary
        button.tintColor = .white
        button.layer.cornerRadius = 15
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        nameLabel.text = nil
        descriptionLabel.text = nil
        placeCountLabel.text = nil
        privacyImageView.image = nil
        categoryLabel.text = nil
        categoryLabel.backgroundColor = nil
    }
    
    // MARK: - Setup
    private func setupCell() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        containerView.addSubview(coverImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(descriptionLabel)
        containerView.addSubview(placeCountLabel)
        containerView.addSubview(privacyImageView)
        containerView.addSubview(categoryLabel)
        containerView.addSubview(shareButton)
        
        // Add target for share button
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.small),
            
            coverImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.medium),
            coverImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.medium),
            coverImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.Spacing.medium),
            coverImageView.widthAnchor.constraint(equalTo: coverImageView.heightAnchor),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.medium),
            nameLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: Constants.Spacing.medium),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            categoryLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.medium),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20),
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            descriptionLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            placeCountLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: Constants.Spacing.medium),
            placeCountLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            shareButton.centerYAnchor.constraint(equalTo: placeCountLabel.centerYAnchor),
            shareButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.medium),
            shareButton.heightAnchor.constraint(equalToConstant: 30),
            
            privacyImageView.centerYAnchor.constraint(equalTo: placeCountLabel.centerYAnchor),
            privacyImageView.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -Constants.Spacing.small),
            privacyImageView.widthAnchor.constraint(equalToConstant: 16),
            privacyImageView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    
    // MARK: - Configure
    func configure(with circle: Circle) {
        self.circle = circle
        nameLabel.text = circle.name
        descriptionLabel.text = circle.description
        
        // Place count
        if let places = circle.places {
            placeCountLabel.text = "\(places.count) place\(places.count != 1 ? "s" : "")"
        } else {
            placeCountLabel.text = "0 places"
        }
        
        // Privacy icon
        switch circle.privacy {
        case .public:
            privacyImageView.image = UIImage(systemName: "globe")
        case .myNetwork:
            privacyImageView.image = UIImage(systemName: "person.2")
        case .private:
            privacyImageView.image = UIImage(systemName: "lock")
        }
        
        
        // Category label
        categoryLabel.text = circle.category.rawValue.capitalized
        
        // Category color
        switch circle.category {
        case .travel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .food:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
        case .services:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .shopping:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
        }
        
        // Cover image
        if let coverImageUrl = circle.coverImage {
            print("📷 Loading image for circle '\(circle.name)' from URL: \(coverImageUrl)")
            // Load image from URL
            ImageService.shared.loadImage(from: coverImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    if let image = image {
                        print("✅ Successfully loaded image for circle '\(circle.name)'")
                        self?.coverImageView.image = image
                        self?.coverImageView.contentMode = .scaleAspectFill
                    } else {
                        print("❌ Failed to load image for circle '\(circle.name)'")
                        // Fall back to default icon
                        self?.setDefaultIcon(for: circle.category)
                    }
                }
            }
        } else {
            print("ℹ️ No cover image URL for circle '\(circle.name)'")
            // Default image based on category
            setDefaultIcon(for: circle.category)
        }
    }
    
    private func setDefaultIcon(for category: CircleCategory) {
        switch category {
        case .travel:
            coverImageView.image = UIImage(systemName: "airplane.departure")
        case .food:
            coverImageView.image = UIImage(systemName: "fork.knife.circle.fill")
        case .services:
            coverImageView.image = UIImage(systemName: "wrench.and.screwdriver.fill")
        case .shopping:
            coverImageView.image = UIImage(systemName: "bag.fill")
        case .healthcare:
            coverImageView.image = UIImage(systemName: "heart.text.square.fill")
        case .entertainment:
            coverImageView.image = UIImage(systemName: "music.note.tv.fill")
        case .other:
            coverImageView.image = UIImage(systemName: "square.stack.3d.up.fill")
        }
        coverImageView.tintColor = Constants.Colors.primary
        coverImageView.contentMode = .scaleAspectFit
    }
    
    // MARK: - Actions
    @objc private func shareButtonTapped() {
        guard let circle = circle else { return }
        delegate?.circleTableViewCell(self, didTapShareForCircle: circle)
    }
}

// MARK: - CreateCircleDelegate
protocol CreateCircleDelegate: AnyObject {
    func didCreateCircle(_ circle: Circle)
}

extension CirclesHomeViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - EditCircleDelegate
extension CirclesHomeViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        // Find and update the circle in the array
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        // Find and remove the circle from the array
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
            updateEmptyState()
        }
    }
}

// MARK: - CircleTableViewCellDelegate
extension CirclesHomeViewController: CircleTableViewCellDelegate {
    func circleTableViewCell(_ cell: CircleTableViewCell, didTapShareForCircle circle: Circle) {
        // Create a formatted string with circle details
        var shareText = "🔵 \(circle.name)\n"
        
        if let description = circle.description, !description.isEmpty {
            shareText += "\(description)\n"
        }
        
        // Calculate member count from sharedWith and followers
        let memberCount = 1 + (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        shareText += "\n👥 \(memberCount) members"
        shareText += "\n📍 \(circle.places?.count ?? 0) places"
        
        // Add privacy info
        switch circle.privacy {
        case .public:
            shareText += "\n🌐 Public Circle"
        case .myNetwork:
            shareText += "\n👥 My Network"
        case .private:
            shareText += "\n🔒 Private Circle"
        }
        
        // Add deep link and web link
        shareText += "\n\n📱 Open in Circles: circles://circle/\(circle.id)"
        
        // Add a web link that could redirect to App Store or open the app
        // For now, use TestFlight link since app isn't on App Store yet
        shareText += "\n\n🔗 Get Circles App: https://testflight.apple.com/join/YourTestFlightCode"
        // TODO: Replace with App Store link when published: https://apps.apple.com/app/circles/idYOURAPPID
        
        shareText += "\n\nJoin me on Circles!"
        
        var activityItems: [Any] = [shareText]
        
        // Function to present the share sheet
        let presentShareSheet = { [weak self] in
            let activityViewController = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
            
            // For iPad - set the source view for the popover
            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = cell.shareButton
                popover.sourceRect = cell.shareButton.bounds
            }
            
            self?.present(activityViewController, animated: true)
        }
        
        // Add cover image if available (load asynchronously)
        if let coverImageUrl = circle.coverImage,
           let url = URL(string: coverImageUrl) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    if let data = data, let image = UIImage(data: data) {
                        activityItems.append(image)
                    }
                    presentShareSheet()
                }
            }.resume()
        } else {
            presentShareSheet()
        }
    }
}

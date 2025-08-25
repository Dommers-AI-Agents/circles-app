//
//  DailySummaryViewController.swift
//  Circles-iOS-UIKit
//
//  Created by Claude on 7/28/2025.
//

import UIKit

class DailySummaryViewController: UIViewController {
    
    // MARK: - Properties
    private var summaryData: LocalDailySummaryData?
    private let containerView = UIView()
    private let dismissButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerLabel = UILabel()
    private let dateLabel = UILabel()
    private let stackView = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let refreshControl = UIRefreshControl()
    
    // MARK: - Data Model
    struct LocalDailySummaryData {
        let date: Date
        let newPlaces: Int
        let newPlacesByCategory: [String: Int]
        let newConnections: Int
        let unreadMessages: Int
        let placeComments: Int
        let placeLikes: Int
        let topContributors: [(name: String, count: Int)]
        
        init(from apiData: DailySummaryData) {
            // Parse date string to Date
            let formatter = ISO8601DateFormatter()
            self.date = formatter.date(from: apiData.date) ?? Date()
            
            self.newPlaces = apiData.newPlaces
            self.newConnections = apiData.newConnections
            self.unreadMessages = apiData.unreadMessages
            self.placeComments = apiData.placeComments
            self.placeLikes = apiData.placeLikes
            self.newPlacesByCategory = apiData.newPlacesByCategory
            
            // Convert contributors
            self.topContributors = apiData.topContributors.map { ($0.name, $0.count) }
            
            print("📊 DailySummaryData initialized from API response")
        }
    }
    
    // MARK: - Initialization
    init() {
        super.init(nibName: nil, bundle: nil)
        
        print("📊 DailySummaryViewController: Initializing (will fetch data from API)")
        
        // Present as modal
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .coverVertical
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        fetchDailySummary()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📊 ViewDidAppear - Final frames:")
        print("  - View frame: \(view.frame)")
        print("  - Container frame: \(containerView.frame)")
        print("  - ScrollView frame: \(scrollView.frame)")
        print("  - ContentView frame: \(contentView.frame)")
        print("  - StackView frame: \(stackView.frame)")
        print("  - ScrollView contentSize: \(scrollView.contentSize)")
        print("  - Number of cards: \(stackView.arrangedSubviews.count)")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Background with blur effect
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        
        // Container view
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 16
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        // Dismiss button
        dismissButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        dismissButton.tintColor = .systemGray2
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dismissButton)
        
        // Header
        headerLabel.text = "Your Daily Summary"
        headerLabel.font = .systemFont(ofSize: 24, weight: .bold)
        headerLabel.textAlignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerLabel)
        
        // Date
        dateLabel.font = .systemFont(ofSize: 14, weight: .medium)
        dateLabel.textColor = .secondaryLabel
        dateLabel.textAlignment = .center
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dateLabel)
        
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.refreshControl = refreshControl
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        containerView.addSubview(scrollView)
        
        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        containerView.addSubview(loadingIndicator)
        
        // Content view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Stack view for summary items
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
        stackView.alignment = .fill
        contentView.addSubview(stackView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Blur view
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Container
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            containerView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.8),
            
            // Dismiss button
            dismissButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            dismissButton.widthAnchor.constraint(equalToConstant: 30),
            dismissButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Header
            headerLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 50),
            headerLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -50),
            
            // Date
            dateLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            
            // Content view - Use contentLayoutGuide for proper scrolling
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            
            // Stack view
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
    }
    
    // MARK: - Fetch Data
    private func fetchDailySummary() {
        print("📊 Fetching daily summary from API...")
        
        // Show loading state
        loadingIndicator.startAnimating()
        scrollView.isHidden = true
        
        APIService.shared.fetchDailySummary { [weak self] result in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()
                self?.refreshControl.endRefreshing()
                
                switch result {
                case .success(let apiData):
                    print("📊 Successfully fetched daily summary data")
                    self?.summaryData = LocalDailySummaryData(from: apiData)
                    self?.scrollView.isHidden = false
                    self?.displaySummary()
                    
                case .failure(let error):
                    print("📊 Failed to fetch daily summary: \(error)")
                    self?.scrollView.isHidden = false
                    self?.displayError(error)
                }
            }
        }
    }
    
    @objc private func refreshData() {
        fetchDailySummary()
    }
    
    // MARK: - Display Summary
    private func displaySummary() {
        // Clear existing content
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Ensure scrollView is visible
        scrollView.isHidden = false
        scrollView.alpha = 1.0
        
        guard let data = summaryData else { 
            print("📊 ❌ No summary data available")
            displayError(nil)
            return
        }
        
        print("📊 ✅ Displaying summary with data:")
        print("  - newPlaces: \(data.newPlaces)")
        print("  - newConnections: \(data.newConnections)")
        print("  - unreadMessages: \(data.unreadMessages)")
        print("  - placeComments: \(data.placeComments)")
        print("  - placeLikes: \(data.placeLikes)")
        print("  - topContributors: \(data.topContributors.count) contributors")
        
        // Format date
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        dateLabel.text = formatter.string(from: data.date)
        
        // Add summary cards
        if data.newPlaces > 0 {
            // Build subtitle with top contributor
            var subtitle = ""
            if let topContributor = data.topContributors.first {
                subtitle = "\(topContributor.name) added \(topContributor.count)"
                if data.topContributors.count > 1 {
                    let othersCount = data.topContributors.dropFirst().reduce(0) { $0 + $1.count }
                    subtitle += " • Others added \(othersCount)"
                }
            } else {
                subtitle = formatPlaceCategories(data.newPlacesByCategory)
            }
            
            let placesCard = createSummaryCard(
                emoji: "📍",
                title: "\(data.newPlaces) New Place\(data.newPlaces > 1 ? "s" : "")",
                subtitle: subtitle,
                color: Constants.Colors.primary,
                action: #selector(viewNewPlaces)
            )
            stackView.addArrangedSubview(placesCard)
            print("📊 Added places card with \(data.newPlaces) places")
        }
        
        if data.newConnections > 0 {
            let connectionsCard = createSummaryCard(
                emoji: "👥",
                title: "\(data.newConnections) New Connection\(data.newConnections > 1 ? "s" : "")",
                subtitle: "Your network is growing!",
                color: .systemBlue,
                action: #selector(viewConnections)
            )
            stackView.addArrangedSubview(connectionsCard)
        }
        
        if data.unreadMessages > 0 {
            let messagesCard = createSummaryCard(
                emoji: "💬",
                title: "\(data.unreadMessages) Unread Message\(data.unreadMessages > 1 ? "s" : "")",
                subtitle: "Check your messages",
                color: .systemOrange,
                action: #selector(viewMessages)
            )
            stackView.addArrangedSubview(messagesCard)
        }
        
        if data.placeComments > 0 || data.placeLikes > 0 {
            var activities: [String] = []
            if data.placeComments > 0 {
                activities.append("\(data.placeComments) comment\(data.placeComments > 1 ? "s" : "")")
            }
            if data.placeLikes > 0 {
                activities.append("\(data.placeLikes) like\(data.placeLikes > 1 ? "s" : "")")
            }
            
            let activityCard = createSummaryCard(
                emoji: "❤️",
                title: "Activity on Your Places",
                subtitle: activities.joined(separator: " and "),
                color: .systemPink,
                action: #selector(viewActivity)
            )
            stackView.addArrangedSubview(activityCard)
        }
        
        // Add top contributors if available
        if !data.topContributors.isEmpty {
            let contributorsView = createContributorsView(data.topContributors)
            stackView.addArrangedSubview(contributorsView)
        }
        
        // If no activity at all, show a message
        if data.newPlaces == 0 && data.newConnections == 0 && data.unreadMessages == 0 && 
           data.placeComments == 0 && data.placeLikes == 0 {
            print("📊 No activity to display")
            let noActivityCard = createSummaryCard(
                emoji: "😴",
                title: "No New Activity",
                subtitle: "Check back tomorrow for updates from your network",
                color: .systemGray,
                action: #selector(dismissTapped)
            )
            stackView.addArrangedSubview(noActivityCard)
        }
        
        // Log final state
        print("📊 StackView now has \(stackView.arrangedSubviews.count) subviews")
        print("📊 ScrollView hidden: \(scrollView.isHidden)")
        
        // Force layout and log sizes
        view.layoutIfNeeded()
        
        // Debug view hierarchy
        print("📊 View hierarchy debug:")
        print("  - Container frame: \(containerView.frame)")
        print("  - ScrollView frame: \(scrollView.frame)")
        print("  - ContentView frame: \(contentView.frame)")
        print("  - StackView frame: \(stackView.frame)")
        print("  - ScrollView contentSize: \(scrollView.contentSize)")
        
        // Log each card's frame
        for (index, subview) in stackView.arrangedSubviews.enumerated() {
            print("  - Card \(index) frame: \(subview.frame)")
        }
    }
    
    // MARK: - Helper Methods
    private func createSummaryCard(emoji: String, title: String, subtitle: String, color: UIColor, action: Selector) -> UIView {
        let card = UIView()
        card.backgroundColor = color.withAlphaComponent(0.1)
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: action)
        card.addGestureRecognizer(tapGesture)
        card.isUserInteractionEnabled = true
        
        let emojiLabel = UILabel()
        emojiLabel.text = emoji
        emojiLabel.font = .systemFont(ofSize: 32)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(emojiLabel)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = color
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)
        
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chevron)
        
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
            emojiLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            emojiLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: emojiLabel.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chevron.widthAnchor.constraint(equalToConstant: 12)
        ])
        
        return card
    }
    
    private func createContributorsView(_ contributors: [(name: String, count: Int)]) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.05)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = "🏆 Top Contributors"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        
        let contributorsStack = UIStackView()
        contributorsStack.axis = .vertical
        contributorsStack.spacing = 12
        contributorsStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contributorsStack)
        
        for (index, contributor) in contributors.prefix(3).enumerated() {
            let contributorView = UIView()
            contributorView.translatesAutoresizingMaskIntoConstraints = false
            
            let medalEmoji = index == 0 ? "🥇" : (index == 1 ? "🥈" : "🥉")
            
            let label = UILabel()
            label.text = "\(medalEmoji) \(contributor.name) added \(contributor.count) place\(contributor.count > 1 ? "s" : "")"
            label.font = .systemFont(ofSize: 16, weight: index == 0 ? .medium : .regular)
            label.textColor = .label
            label.translatesAutoresizingMaskIntoConstraints = false
            contributorView.addSubview(label)
            
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: contributorView.topAnchor),
                label.leadingAnchor.constraint(equalTo: contributorView.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: contributorView.trailingAnchor),
                label.bottomAnchor.constraint(equalTo: contributorView.bottomAnchor)
            ])
            
            contributorsStack.addArrangedSubview(contributorView)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            contributorsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contributorsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            contributorsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            contributorsStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        
        return container
    }
    
    private func formatPlaceCategories(_ categories: [String: Int]) -> String {
        let sorted = categories.sorted { $0.value > $1.value }
        let formatted = sorted.prefix(3).map { "\($0.value) \($0.key)\($0.value > 1 ? "s" : "")" }
        return formatted.joined(separator: ", ")
    }
    
    // MARK: - Actions
    @objc private func dismissTapped() {
        dismiss(animated: true)
    }
    
    @objc private func viewNewPlaces() {
        print("📊 View New Places tapped")
        dismiss(animated: true) { 
            // Navigate to home tab to see new places
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let tabBar = window.rootViewController as? UITabBarController {
                    print("📊 Navigating to home tab (index 0)")
                    tabBar.selectedIndex = 0  // Circles/Home is at index 0
                    
                    // Optional: Scroll to top of the home feed to show latest places
                    if let navController = tabBar.viewControllers?[0] as? UINavigationController,
                       let circlesVC = navController.topViewController as? CirclesHomeViewController {
                        // The view controller will refresh and show latest places
                        print("📊 ✅ Successfully navigated to Circles home")
                    }
                } else {
                    print("📊 ❌ Failed to find tab bar controller")
                }
            }
        }
    }
    
    @objc private func viewConnections() {
        print("📊 View Connections tapped")
        dismiss(animated: true) {
            // Navigate to network tab
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let tabBar = window.rootViewController as? UITabBarController {
                    print("📊 Navigating to network tab (index 1)")
                    tabBar.selectedIndex = 1  // Network is at index 1
                } else {
                    print("📊 ❌ Failed to find tab bar controller")
                }
            }
        }
    }
    
    @objc private func viewMessages() {
        print("📊 View Messages tapped")
        dismiss(animated: true) {
            // Navigate to messages tab
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let tabBar = window.rootViewController as? UITabBarController {
                    print("📊 Navigating to messages tab (index 2)")
                    tabBar.selectedIndex = 2  // Messages is at index 2
                    
                    // The Messages tab already shows ConversationsListViewController, no need to push
                } else {
                    print("📊 ❌ Failed to find tab bar controller")
                }
            }
        }
    }
    
    @objc private func viewActivity() {
        print("📊 View Activity tapped")
        dismiss(animated: true) {
            // Navigate to profile to see user's places with activity
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let tabBar = window.rootViewController as? UITabBarController {
                    print("📊 Navigating to profile tab (index 3)")
                    tabBar.selectedIndex = 3  // Profile is at index 3
                } else {
                    print("📊 ❌ Failed to find tab bar controller")
                }
            }
        }
    }
    
    // MARK: - Error Display
    private func displayError(_ error: Error?) {
        // Clear existing content
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Set a default date if not available
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        dateLabel.text = formatter.string(from: Date())
        
        let errorCard = createSummaryCard(
            emoji: "⚠️",
            title: "Unable to Load Summary",
            subtitle: error?.localizedDescription ?? "Please check your connection and try again",
            color: .systemRed,
            action: #selector(refreshData)
        )
        stackView.addArrangedSubview(errorCard)
        
        // Add a refresh hint
        let hintLabel = UILabel()
        hintLabel.text = "Pull down to refresh"
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(hintLabel)
    }
}
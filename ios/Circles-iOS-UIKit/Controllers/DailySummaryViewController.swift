//
//  DailySummaryViewController.swift
//  Circles-iOS-UIKit
//
//  Created by Claude on 7/28/2025.
//

import UIKit

class DailySummaryViewController: UIViewController {
    
    // MARK: - Properties
    private var summaryData: DailySummaryData?
    private let dismissButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerLabel = UILabel()
    private let dateLabel = UILabel()
    private let stackView = UIStackView()
    
    // MARK: - Data Model
    struct DailySummaryData {
        let date: Date
        let newPlaces: Int
        let newPlacesByCategory: [String: Int]
        let newConnections: Int
        let unreadMessages: Int
        let placeComments: Int
        let placeLikes: Int
        let topContributors: [(name: String, count: Int)]
        
        init(from notification: [String: Any]) {
            // Debug logging
            print("📊 DailySummaryData: Parsing notification data")
            print("📊 Available keys: \(notification.keys.sorted())")
            
            self.date = Date()
            
            // FCM places data fields at the root level, not in a nested 'data' object
            self.newPlaces = Int(notification["newPlaces"] as? String ?? "0") ?? 0
            self.newConnections = Int(notification["newConnections"] as? String ?? "0") ?? 0
            self.unreadMessages = Int(notification["unreadMessages"] as? String ?? "0") ?? 0
            self.placeComments = Int(notification["placeComments"] as? String ?? "0") ?? 0
            self.placeLikes = Int(notification["placeLikes"] as? String ?? "0") ?? 0
            
            // Log parsed values
            print("📊 Parsed values:")
            print("  - newPlaces: \(self.newPlaces)")
            print("  - newConnections: \(self.newConnections)")
            print("  - unreadMessages: \(self.unreadMessages)")
            print("  - placeComments: \(self.placeComments)")
            print("  - placeLikes: \(self.placeLikes)")
            
            // Parse categories if available
            if let categoriesString = notification["placeCategories"] as? String {
                print("📊 Found placeCategories: \(categoriesString)")
                if let data = categoriesString.data(using: .utf8),
                   let categories = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                    self.newPlacesByCategory = categories
                    print("📊 Parsed categories: \(categories)")
                } else {
                    self.newPlacesByCategory = [:]
                    print("📊 Failed to parse categories")
                }
            } else {
                self.newPlacesByCategory = [:]
                print("📊 No placeCategories found")
            }
            
            // Parse contributors if available
            if let contributorsString = notification["topContributors"] as? String {
                print("📊 Found topContributors: \(contributorsString)")
                if let data = contributorsString.data(using: .utf8),
                   let contributors = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    self.topContributors = contributors.compactMap { dict in
                        guard let name = dict["name"] as? String,
                              let count = dict["count"] as? Int else { return nil }
                        return (name, count)
                    }
                    print("📊 Parsed contributors: \(self.topContributors)")
                } else {
                    self.topContributors = []
                    print("📊 Failed to parse contributors")
                }
            } else {
                self.topContributors = []
                print("📊 No topContributors found")
            }
            
            print("📊 DailySummaryData initialization complete")
        }
    }
    
    // MARK: - Initialization
    init(notificationData: [String: Any]) {
        super.init(nibName: nil, bundle: nil)
        
        print("📊 DailySummaryViewController: Initializing with notification data")
        print("📊 Raw notification data: \(notificationData)")
        
        self.summaryData = DailySummaryData(from: notificationData)
        
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
        displaySummary()
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
        containerView.addSubview(scrollView)
        
        // Content view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Stack view for summary items
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
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
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Stack view
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    // MARK: - Display Summary
    private func displaySummary() {
        guard let data = summaryData else { 
            print("📊 No summary data available")
            // Show a fallback message
            let noDataCard = createSummaryCard(
                emoji: "📊",
                title: "Your Daily Summary",
                subtitle: "Check out what's happening in your network",
                color: Constants.Colors.primary,
                action: #selector(dismissTapped)
            )
            stackView.addArrangedSubview(noDataCard)
            return
        }
        
        print("📊 Displaying summary with data:")
        print("  - newPlaces: \(data.newPlaces)")
        print("  - newConnections: \(data.newConnections)")
        print("  - unreadMessages: \(data.unreadMessages)")
        print("  - placeComments: \(data.placeComments)")
        print("  - placeLikes: \(data.placeLikes)")
        
        // Format date
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        dateLabel.text = formatter.string(from: data.date)
        
        // Add summary cards
        if data.newPlaces > 0 {
            let placesCard = createSummaryCard(
                emoji: "🆕",
                title: "\(data.newPlaces) New Places",
                subtitle: formatPlaceCategories(data.newPlacesByCategory),
                color: Constants.Colors.primary,
                action: #selector(viewNewPlaces)
            )
            stackView.addArrangedSubview(placesCard)
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
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = "Top Contributors"
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        
        let contributorsStack = UIStackView()
        contributorsStack.axis = .vertical
        contributorsStack.spacing = 8
        contributorsStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contributorsStack)
        
        for contributor in contributors.prefix(3) {
            let label = UILabel()
            label.text = "\(contributor.name) added \(contributor.count) place\(contributor.count > 1 ? "s" : "")"
            label.font = .systemFont(ofSize: 14)
            label.textColor = .label
            contributorsStack.addArrangedSubview(label)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            contributorsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            contributorsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contributorsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contributorsStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
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
        dismiss(animated: true) { [weak self] in
            // Navigate to home tab to see new places
            if let tabBar = UIApplication.shared.windows.first?.rootViewController as? UITabBarController {
                tabBar.selectedIndex = 0
            }
        }
    }
    
    @objc private func viewConnections() {
        dismiss(animated: true) { [weak self] in
            // Navigate to network tab
            if let tabBar = UIApplication.shared.windows.first?.rootViewController as? UITabBarController {
                tabBar.selectedIndex = 3
            }
        }
    }
    
    @objc private func viewMessages() {
        dismiss(animated: true) { [weak self] in
            // Navigate to messages
            if let tabBar = UIApplication.shared.windows.first?.rootViewController as? UITabBarController {
                tabBar.selectedIndex = 3
                
                // Find and push messages controller
                if let navController = tabBar.selectedViewController as? UINavigationController {
                    let messagesVC = ConversationsListViewController()
                    navController.pushViewController(messagesVC, animated: true)
                }
            }
        }
    }
    
    @objc private func viewActivity() {
        dismiss(animated: true) { [weak self] in
            // Navigate to profile to see user's places with activity
            if let tabBar = UIApplication.shared.windows.first?.rootViewController as? UITabBarController {
                tabBar.selectedIndex = 4
            }
        }
    }
}
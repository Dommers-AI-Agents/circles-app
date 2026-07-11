import UIKit

class HelpViewController: BaseViewController {
    
    // MARK: - Properties
    private var categories = HelpTopic.HelpCategory.allCases
    private var searchResults: [HelpTopic] = []
    private var isSearching = false
    
    // MARK: - UI Elements
    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Search help topics"
        controller.searchBar.delegate = self
        return controller
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        table.register(UITableViewCell.self, forCellReuseIdentifier: "TopicCell")
        table.backgroundColor = Constants.Colors.background
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private lazy var tutorialButton: UIButton = {
        let button = UIButton.primaryButton(title: "Watch Tutorial Video")
        button.addTarget(self, action: #selector(watchTutorialTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var relaunchOnboardingButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Show Welcome Tour")
        button.addTarget(self, action: #selector(relaunchOnboardingTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Add icon to make it more visually appealing
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "sparkles", withConfiguration: config)
        button.setImage(icon, for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        
        return button
    }()
    
    private lazy var dailySummaryButton: UIButton = {
        let button = UIButton.secondaryButton(title: "View Daily Summary")
        button.addTarget(self, action: #selector(viewDailySummaryTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Add icon to make it more visually appealing
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = UIImage(systemName: "calendar.badge.clock", withConfiguration: config)
        button.setImage(icon, for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureNavigationBar()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Help & Support"
        view.backgroundColor = Constants.Colors.background
        
        // Add search controller
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        
        // Add subviews
        view.addSubview(tutorialButton)
        view.addSubview(relaunchOnboardingButton)
        view.addSubview(dailySummaryButton)
        view.addSubview(tableView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Tutorial button at top
            tutorialButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            tutorialButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tutorialButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tutorialButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Relaunch onboarding button below tutorial button
            relaunchOnboardingButton.topAnchor.constraint(equalTo: tutorialButton.bottomAnchor, constant: 12),
            relaunchOnboardingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            relaunchOnboardingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            relaunchOnboardingButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Daily summary button below relaunch button
            dailySummaryButton.topAnchor.constraint(equalTo: relaunchOnboardingButton.bottomAnchor, constant: 12),
            dailySummaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dailySummaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dailySummaryButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Table view below daily summary button
            tableView.topAnchor.constraint(equalTo: dailySummaryButton.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func configureNavigationBar() {
        // Add close button if presented modally
        if presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeTapped)
            )
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func watchTutorialTapped() {
        let tutorialVC = TutorialViewController()
        let navController = UINavigationController(rootViewController: tutorialVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func relaunchOnboardingTapped() {
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Show Welcome Tour",
            message: "Would you like to see the welcome tour again? This will show you how to follow users and add your first place.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Show Tour", style: .default) { [weak self] _ in
            self?.launchOnboardingTour()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func viewDailySummaryTapped() {
        // Present the daily summary modal
        let summaryVC = DailySummaryViewController()
        present(summaryVC, animated: true)
    }
    
    private func launchOnboardingTour() {
        // Dismiss this view controller first
        dismiss(animated: true) { [weak self] in
            // Post notification to show onboarding overlays
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Reset the onboarding flags temporarily
                OnboardingManager.shared.enableSuggestedUsersOverlay()
                
                // Reset add place tutorial + map hint flags so the tour shows them again
                OnboardingManager.shared.resetAddPlaceHints()
                
                // Post notification to trigger the overlays
                NotificationCenter.default.post(
                    name: Notification.Name("ShowOnboardingTour"),
                    object: nil,
                    userInfo: ["source": "help"]
                )
                
                // Show success message
                if let window = UIApplication.shared.windows.first,
                   let rootVC = window.rootViewController {
                    let toast = UIAlertController(
                        title: "Welcome Tour Starting",
                        message: "Navigate to the Home tab to begin the tour",
                        preferredStyle: .alert
                    )
                    toast.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    // Present from the topmost view controller
                    var topVC = rootVC
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }
                    topVC.present(toast, animated: true)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func showHelpTopic(_ topic: HelpTopic) {
        let detailVC = HelpTopicViewController(topic: topic)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func showCategory(_ category: HelpTopic.HelpCategory) {
        let topics = HelpContentProvider.shared.topics(for: category)
        let categoryVC = HelpCategoryViewController(category: category, topics: topics)
        navigationController?.pushViewController(categoryVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension HelpViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return isSearching ? 1 : 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching {
            return searchResults.count
        }
        
        switch section {
        case 0:
            return 1 // Quick links section
        case 1:
            return categories.count
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TopicCell", for: indexPath)
            let topic = searchResults[indexPath.row]
            
            var config = UIListContentConfiguration.subtitleCell()
            config.text = topic.title
            config.secondaryText = topic.subtitle
            config.image = UIImage(systemName: topic.category.icon)
            config.imageProperties.tintColor = topic.category.color
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            
            return cell
        }
        
        if indexPath.section == 0 {
            // Quick links
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
            
            var config = UIListContentConfiguration.subtitleCell()
            config.text = "Quick Start Guide"
            config.secondaryText = "New to Circles? Start here"
            config.image = UIImage(systemName: "sparkles")
            config.imageProperties.tintColor = .systemYellow
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            
            return cell
        } else {
            // Categories
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
            let category = categories[indexPath.row]
            
            var config = UIListContentConfiguration.subtitleCell()
            config.text = category.rawValue
            config.secondaryText = "\(HelpContentProvider.shared.topics(for: category).count) topics"
            config.image = UIImage(systemName: category.icon)
            config.imageProperties.tintColor = category.color
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching {
            return searchResults.isEmpty ? "No Results" : "Search Results"
        }
        
        switch section {
        case 0:
            return "Featured"
        case 1:
            return "Help Topics"
        default:
            return nil
        }
    }
}

// MARK: - UITableViewDelegate
extension HelpViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if isSearching {
            let topic = searchResults[indexPath.row]
            showHelpTopic(topic)
        } else if indexPath.section == 0 {
            // Show quick start guide
            if let topic = HelpContentProvider.shared.topic(withId: "app-overview") {
                showHelpTopic(topic)
            }
        } else {
            // Show category
            let category = categories[indexPath.row]
            showCategory(category)
        }
    }
}

// MARK: - UISearchResultsUpdating
extension HelpViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            isSearching = false
            searchResults = []
            tableView.reloadData()
            return
        }
        
        isSearching = true
        searchResults = HelpContentProvider.shared.search(query: searchText)
        tableView.reloadData()
    }
}

// MARK: - UISearchBarDelegate
extension HelpViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        isSearching = false
        searchResults = []
        tableView.reloadData()
    }
}

// MARK: - Help Category View Controller
class HelpCategoryViewController: BaseViewController {
    
    private let category: HelpTopic.HelpCategory
    private let topics: [HelpTopic]
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "TopicCell")
        table.backgroundColor = Constants.Colors.background
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    init(category: HelpTopic.HelpCategory, topics: [HelpTopic]) {
        self.category = category
        self.topics = topics
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        title = category.rawValue
        view.backgroundColor = Constants.Colors.background
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - Category TableView DataSource & Delegate
extension HelpCategoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return topics.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TopicCell", for: indexPath)
        let topic = topics[indexPath.row]
        
        var config = UIListContentConfiguration.subtitleCell()
        config.text = topic.title
        config.secondaryText = topic.subtitle
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let topic = topics[indexPath.row]
        let detailVC = HelpTopicViewController(topic: topic)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
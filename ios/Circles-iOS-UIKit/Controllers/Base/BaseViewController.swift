import UIKit

/// Base view controller that provides common functionality for data loading, error handling, and UI setup
/// Eliminates redundant code across 29+ view controllers
class BaseViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Loading indicator for initial data load
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    /// Refresh control for pull-to-refresh
    private(set) lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return control
    }()
    
    /// Empty state label
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    /// Whether the view has loaded data at least once
    private(set) var hasLoadedData = false
    
    /// Whether data is currently being loaded
    private(set) var isLoadingData = false
    
    // MARK: - Configuration Properties (Override in subclasses)
    
    /// Whether to show loading indicator on initial load
    var showsLoadingIndicator: Bool { true }
    
    /// Whether to enable pull-to-refresh
    var enablesPullToRefresh: Bool { false }
    
    /// Empty state message when no data is available
    var emptyStateMessage: String? { nil }

    /// The empty screen's way forward (2026-11-02: never a dead end): a
    /// button under the message. Override with its words and
    /// `emptyStateActionTapped()`.
    var emptyStateActionTitle: String? { nil }
    func emptyStateActionTapped() {}

    private lazy var emptyStateButton: UIButton = {
        let button = UIButton.smallActionButton(title: emptyStateActionTitle ?? "", style: .primary)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(emptyStateButtonTapped), for: .touchUpInside)
        return button
    }()

    @objc private func emptyStateButtonTapped() {
        AnalyticsService.shared.logEvent("next_step_tapped", parameters: ["surface": "\(type(of: self))", "step": "empty_state"])
        emptyStateActionTapped()
    }
    
    /// Whether to automatically load data on viewDidLoad
    var loadsDataOnViewDidLoad: Bool { true }
    
    /// Whether to reload data on viewWillAppear
    var reloadsDataOnAppear: Bool { false }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBaseUI()
        
        if loadsDataOnViewDidLoad {
            loadInitialData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bringStateViewsToFront()

        if reloadsDataOnAppear && hasLoadedData {
            loadData()
        } else if !hasLoadedData && loadsDataOnViewDidLoad {
            // Handle case where viewDidLoad loading was skipped
            loadInitialData()
        }
    }
    
    // MARK: - Setup
    
    private func setupBaseUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Add loading indicator if needed
        if showsLoadingIndicator {
            view.addSubview(loadingIndicator)
            NSLayoutConstraint.activate([
                loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        
        // Add empty state label if message is provided
        if emptyStateMessage != nil {
            view.addSubview(emptyStateLabel)
            emptyStateLabel.text = emptyStateMessage
            NSLayoutConstraint.activate([
                emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                emptyStateLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
                emptyStateLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
            ])
            if emptyStateActionTitle != nil {
                view.addSubview(emptyStateButton)
                NSLayoutConstraint.activate([
                    emptyStateButton.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: 16),
                    emptyStateButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
                ])
            }
        }
        
        // Setup refresh control if enabled
        if enablesPullToRefresh {
            setupRefreshControl()
        }
    }
    
    /// Override to add refresh control to specific views (table view, collection view, etc.)
    func setupRefreshControl() {
        // Subclasses should override to add refresh control to their scroll views
    }
    
    // MARK: - Data Loading
    
    /// Load initial data with loading indicator
    private func loadInitialData() {
        guard !isLoadingData else { return }
        
        isLoadingData = true
        showLoadingState()
        
        loadData { [weak self] in
            self?.isLoadingData = false
            self?.hasLoadedData = true
            self?.hideLoadingState()
        }
    }
    
    /// Main data loading method - override in subclasses
    /// - Parameter completion: Called when loading completes (success or failure)
    func loadData(completion: (() -> Void)? = nil) {
        // Subclasses must override this method
        completion?()
    }
    
    /// Handle pull-to-refresh
    @objc private func handleRefresh() {
        loadData { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
    
    /// Force refresh data
    func refreshData() {
        if enablesPullToRefresh && !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        loadData { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
    
    // MARK: - Loading States
    
    /// Laid out after a subclass added its own views (its table, in its
    /// viewDidLoad after ours): put the spinner and empty message back on
    /// top. The first load starts inside our viewDidLoad, before the subclass
    /// has added anything, so viewWillAppear alone was too late for a child
    /// tab (Wes, 2026-11-05: Popular showed an empty list, no spinner).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if loadingIndicator.isAnimating || !emptyStateLabel.isHidden { bringStateViewsToFront() }
    }

    /// A subclass adds its table/list after `setupBaseUI`, which buried the
    /// spinner and empty message under it: a blank screen while loading
    /// (Wes, 2026-11-03, Comments). Keep them on top.
    private func bringStateViewsToFront() {
        for stateView in [loadingIndicator, emptyStateLabel, emptyStateButton] as [UIView] where stateView.superview === view {
            view.bringSubviewToFront(stateView)
        }
    }

    func showLoadingState() {
        bringStateViewsToFront()
        if showsLoadingIndicator && !hasLoadedData {
            loadingIndicator.startAnimating()
        }
        emptyStateLabel.isHidden = true
        emptyStateButton.isHidden = true
    }
    
    func hideLoadingState() {
        loadingIndicator.stopAnimating()
    }
    
    /// Show empty state with optional custom message
    func showEmptyState(message: String? = nil) {
        hideLoadingState()
        bringStateViewsToFront()
        emptyStateLabel.text = message ?? emptyStateMessage
        emptyStateLabel.isHidden = false
        emptyStateButton.isHidden = emptyStateActionTitle == nil
        if !emptyStateButton.isHidden { view.bringSubviewToFront(emptyStateButton) }
    }
    
    /// Hide empty state
    func hideEmptyState() {
        emptyStateLabel.isHidden = true
        emptyStateButton.isHidden = true
    }
    
    // MARK: - Error Handling
    
    /// Show error alert with retry option
    func showErrorWithRetry(_ error: Error, retryHandler: @escaping () -> Void) {
        hideLoadingState()
        
        // Filter out duplicate request errors - these are intentional and don't need user notification
        let errorMessage = error.localizedDescription
        if errorMessage == "Duplicate request prevented" || 
           errorMessage == "Network error: Duplicate request prevented" ||
           errorMessage.contains("Duplicate request prevented") {
            return
        }
        
        AlertPresenter.showConfirmation(
            title: FriendlyError.title,
            message: FriendlyError.message(for: error),
            confirmTitle: "Retry",
            cancelTitle: "Cancel",
            from: self,
            onConfirm: retryHandler
        )
    }
    
    // MARK: - Navigation Helpers
    
    /// Setup navigation bar with common styling
    func setupNavigationBar(title: String? = nil, largeTitleMode: UINavigationItem.LargeTitleDisplayMode = .automatic) {
        navigationItem.title = title ?? self.title
        navigationItem.largeTitleDisplayMode = largeTitleMode
        
        // Apply common navigation bar styling
        navigationController?.navigationBar.tintColor = Constants.Colors.primary
    }
    
    /// Add common navigation bar buttons
    func addNavigationBarButton(image: String? = nil, title: String? = nil, position: NavigationBarPosition, action: Selector) {
        let button: UIBarButtonItem
        
        if let image = image {
            button = UIBarButtonItem(image: UIImage(systemName: image), style: .plain, target: self, action: action)
        } else if let title = title {
            button = UIBarButtonItem(title: title, style: .plain, target: self, action: action)
        } else {
            return
        }
        
        switch position {
        case .left:
            navigationItem.leftBarButtonItem = button
        case .right:
            navigationItem.rightBarButtonItem = button
        }
    }
    
    enum NavigationBarPosition {
        case left
        case right
    }
}

// MARK: - Table View Controller Variant

/// Base table view controller with data loading functionality
class BaseTableViewController: UITableViewController {
    
    // MARK: - Properties
    
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()
    
    private(set) var hasLoadedData = false
    private(set) var isLoadingData = false
    
    // MARK: - Configuration Properties
    
    var emptyStateMessage: String? { nil }

    /// The empty screen's way forward (2026-11-02): a button under the message
    var emptyStateActionTitle: String? { nil }
    func emptyStateActionTapped() {}

    /// The label, and the button when there is one, as the table's background
    private lazy var emptyStateView: UIView = {
        guard let title = emptyStateActionTitle else { return emptyStateLabel }
        let container = UIView()
        let button = UIButton.smallActionButton(title: title, style: .primary)
        button.addTarget(self, action: #selector(emptyStateButtonTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [emptyStateLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])
        return container
    }()

    @objc private func emptyStateButtonTapped() {
        AnalyticsService.shared.logEvent("next_step_tapped", parameters: ["surface": "\(type(of: self))", "step": "empty_state"])
        emptyStateActionTapped()
    }
    var loadsDataOnViewDidLoad: Bool { true }
    var reloadsDataOnAppear: Bool { false }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBaseUI()
        
        if loadsDataOnViewDidLoad {
            loadInitialData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if reloadsDataOnAppear && hasLoadedData {
            loadData()
        }
    }
    
    // MARK: - Setup
    
    private func setupBaseUI() {
        view.backgroundColor = Constants.Colors.background
        tableView.backgroundColor = Constants.Colors.background
        
        // Setup refresh control
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        
        // Setup empty state
        if let message = emptyStateMessage {
            emptyStateLabel.text = message
            // Just the (hidden) message until the screen is actually empty
            tableView.backgroundView = emptyStateLabel
        }
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() {
        guard !isLoadingData else { return }
        
        isLoadingData = true
        
        loadData { [weak self] in
            self?.isLoadingData = false
            self?.hasLoadedData = true
        }
    }
    
    func loadData(completion: (() -> Void)? = nil) {
        // Subclasses must override
        completion?()
    }
    
    @objc private func handleRefresh() {
        loadData { [weak self] in
            self?.refreshControl?.endRefreshing()
        }
    }
    
    // MARK: - State Management
    
    func showEmptyState(message: String? = nil) {
        emptyStateLabel.text = message ?? emptyStateMessage
        emptyStateLabel.isHidden = false
        tableView.backgroundView = emptyStateView
    }
    
    func hideEmptyState() {
        emptyStateLabel.isHidden = true
        tableView.backgroundView = nil
    }
    
}

// Example usage:
// Instead of implementing all this code in each view controller:
//
// class MyViewController: UIViewController {
//     var hasLoadedData = false
//     let loadingIndicator = UIActivityIndicatorView()
//     
//     override func viewDidLoad() {
//         super.viewDidLoad()
//         setupUI()
//         loadData()
//     }
//     
//     func setupUI() { /* setup code */ }
//     func loadData() { /* loading code */ }
//     func showError(_ error: Error) { /* error handling */ }
// }
//
// Now you can simply:
//
// class MyViewController: BaseViewController {
//     override func loadData(completion: (() -> Void)? = nil) {
//         // Your data loading logic
//         MyService.shared.fetchData { result in
//             switch result {
//             case .success(let data):
//                 // Update UI
//             case .failure(let error):
//                 self.showError(error)
//             }
//             completion?()
//         }
//     }
// }
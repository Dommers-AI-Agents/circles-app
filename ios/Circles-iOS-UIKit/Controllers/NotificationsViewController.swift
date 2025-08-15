import UIKit

class NotificationsViewController: BaseViewController {
    
    // MARK: - Properties
    private var activeNotifications: [AppNotification] = []
    private var archivedNotifications: [AppNotification] = []
    private var hasMoreActive = true
    private var hasMoreArchived = true
    private var currentOffsetActive = 0
    private var currentOffsetArchived = 0
    private let pageSize = 50
    private var currentTab: NotificationTab = .active
    
    enum NotificationTab: Int {
        case active = 0
        case archived = 1
    }
    
    // Computed property for current data source
    private var notifications: [AppNotification] {
        return currentTab == .active ? activeNotifications : archivedNotifications
    }
    
    private var hasMore: Bool {
        return currentTab == .active ? hasMoreActive : hasMoreArchived
    }
    
    private var currentOffset: Int {
        get {
            return currentTab == .active ? currentOffsetActive : currentOffsetArchived
        }
        set {
            if currentTab == .active {
                currentOffsetActive = newValue
            } else {
                currentOffsetArchived = newValue
            }
        }
    }
    
    // MARK: - UI Elements
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Active", "Archived"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        return tableView
    }()
    
    
    // MARK: - BaseViewController Overrides
    override var emptyStateMessage: String? {
        return currentTab == .active ? "No notifications yet" : "No archived notifications"
    }
    override var enablesPullToRefresh: Bool { true }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Mark all notifications as read when viewing
        markAllNotificationsAsRead()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        setupNavigationBar(title: "Notifications")
        setupNavigationBarButtons()
        
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        
        // Configure segmented control
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationBarButtons() {
        // Clear All button for active notifications
        let clearAllButton = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )
        
        // Delete Permanently button for archived notifications
        let deleteButton = UIBarButtonItem(
            title: "Delete All",
            style: .plain,
            target: self,
            action: #selector(deletePermanentlyTapped)
        )
        deleteButton.tintColor = .systemRed
        
        updateNavigationBarButton()
    }
    
    private func updateNavigationBarButton() {
        if currentTab == .active {
            navigationItem.rightBarButtonItem = activeNotifications.isEmpty ? nil : UIBarButtonItem(
                title: "Clear All",
                style: .plain,
                target: self,
                action: #selector(clearAllTapped)
            )
        } else {
            let deleteButton = UIBarButtonItem(
                title: "Delete All",
                style: .plain,
                target: self,
                action: #selector(deletePermanentlyTapped)
            )
            deleteButton.tintColor = .systemRed
            navigationItem.rightBarButtonItem = archivedNotifications.isEmpty ? nil : deleteButton
        }
    }
    
    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(NotificationCell.self, forCellReuseIdentifier: "NotificationCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        print("🚀 NotificationsViewController: loadData called")
        loadNotifications(refresh: false, completion: completion)
    }
    
    private func loadNotifications(refresh: Bool = false, completion: (() -> Void)? = nil) {
        print("🚀 NotificationsViewController: loadNotifications called")
        print("🚀 NotificationsViewController: refresh: \(refresh), isLoadingData: \(isLoadingData)")
        print("🚀 NotificationsViewController: currentTab: \(currentTab)")
        
        let isArchived = currentTab == .archived
        
        if refresh {
            currentOffset = 0
            if currentTab == .active {
                hasMoreActive = true
            } else {
                hasMoreArchived = true
            }
        }
        
        print("🚀 NotificationsViewController: Calling NotificationService.getNotifications")
        print("🚀 NotificationsViewController: limit: \(pageSize), offset: \(currentOffset), archived: \(isArchived)")
        
        NotificationService.shared.getNotifications(limit: pageSize, offset: currentOffset, archived: isArchived) { [weak self] result in
            print("📡 NotificationsViewController: getNotifications callback received")
            
            DispatchQueue.main.async {
                guard let self = self else {
                    completion?()
                    return
                }
                
                switch result {
                case .success(let response):
                    print("✅ NotificationsViewController: Successfully loaded notifications")
                    print("✅ NotificationsViewController: Received \(response.notifications.count) notifications")
                    print("✅ NotificationsViewController: hasMore: \(response.hasMore)")
                    
                    if refresh {
                        if self.currentTab == .active {
                            self.activeNotifications = response.notifications
                            self.hasMoreActive = response.hasMore
                        } else {
                            self.archivedNotifications = response.notifications
                            self.hasMoreArchived = response.hasMore
                        }
                    } else {
                        if self.currentTab == .active {
                            self.activeNotifications.append(contentsOf: response.notifications)
                            self.hasMoreActive = response.hasMore
                        } else {
                            self.archivedNotifications.append(contentsOf: response.notifications)
                            self.hasMoreArchived = response.hasMore
                        }
                    }
                    
                    self.currentOffset += response.notifications.count
                    
                    print("✅ NotificationsViewController: Total notifications now: \(self.notifications.count)")
                    
                    self.updateUI()
                    self.updateNavigationBarButton()
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    print("❌ NotificationsViewController: Failed to load notifications: \(error)")
                    print("❌ NotificationsViewController: Error type: \(type(of: error))")
                    self.showError("Failed to load notifications: \(error.localizedDescription)")
                }
                
                // Always call completion to clear loading state
                completion?()
            }
        }
    }
    
    private func updateUI() {
        if notifications.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
    }
    
    private func markAllNotificationsAsRead() {
        NotificationService.shared.markAllNotificationsAsRead { _ in
            // Silent update - we don't need to handle the response
        }
    }
    
    // MARK: - Actions
    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        let newTab = NotificationTab(rawValue: sender.selectedSegmentIndex) ?? .active
        
        if newTab != currentTab {
            currentTab = newTab
            
            // Load data for the new tab if not loaded yet
            let notifications = self.notifications
            if notifications.isEmpty {
                loadNotifications(refresh: true)
            } else {
                updateUI()
                updateNavigationBarButton()
                tableView.reloadData()
            }
        }
    }
    
    @objc private func clearAllTapped() {
        guard currentTab == .active && !activeNotifications.isEmpty else { return }
        
        showConfirmation(
            title: "Clear All Notifications",
            message: "This will move all active notifications to the archived tab. You can delete them permanently from there."
        ) { [weak self] in
            self?.performClearAll()
        }
    }
    
    @objc private func deletePermanentlyTapped() {
        guard currentTab == .archived && !archivedNotifications.isEmpty else { return }
        
        showConfirmation(
            title: "Delete All Archived",
            message: "This will permanently delete all archived notifications. This cannot be undone."
        ) { [weak self] in
            self?.performDeletePermanently()
        }
    }
    
    private func performClearAll() {
        showLoadingState()
        
        NotificationService.shared.archiveAllNotifications { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.hideLoadingState()
                
                switch result {
                case .success(let message):
                    self.showSuccess(message)
                    // Clear active notifications and reload
                    self.activeNotifications.removeAll()
                    self.hasMoreActive = true
                    self.currentOffsetActive = 0
                    
                    // Clear archived cache to force reload when switching tabs
                    self.archivedNotifications.removeAll()
                    self.hasMoreArchived = true
                    self.currentOffsetArchived = 0
                    
                    self.updateUI()
                    self.updateNavigationBarButton()
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    private func performDeletePermanently() {
        showLoadingState()
        
        NotificationService.shared.clearArchivedNotifications { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.hideLoadingState()
                
                switch result {
                case .success(let message):
                    self.showSuccess(message)
                    // Clear archived notifications and reload
                    self.archivedNotifications.removeAll()
                    self.hasMoreArchived = true
                    self.currentOffsetArchived = 0
                    
                    self.updateUI()
                    self.updateNavigationBarButton()
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    
    // MARK: - Navigation
    private func navigateToPlace(notification: AppNotification) {
        guard let placeId = notification.data?.placeId,
              let circleId = notification.data?.circleId else { return }
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Opening place...", from: self)
        
        // First, fetch the circle
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            switch result {
            case .success(let circle):
                // Then fetch the place
                PlaceService.shared.fetchPlaceById(id: placeId) { placeResult in
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            switch placeResult {
                            case .success(let place):
                                // Navigate to place detail
                                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                                self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                                
                            case .failure(let error):
                                self?.showError(error)
                            }
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension NotificationsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return notifications.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NotificationCell", for: indexPath) as! NotificationCell
        let notification = notifications[indexPath.row]
        cell.configure(with: notification)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension NotificationsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let notification = notifications[indexPath.row]
        navigateToPlace(notification: notification)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Load more when reaching the end
        if indexPath.row == notifications.count - 5 && hasMore && !isLoadingData {
            loadNotifications()
        }
    }
    
    // Swipe-to-delete for archived notifications
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return currentTab == .archived
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && currentTab == .archived {
            let notification = archivedNotifications[indexPath.row]
            deleteNotification(notification, at: indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "Delete"
    }
    
    private func deleteNotification(_ notification: AppNotification, at indexPath: IndexPath) {
        showConfirmation(
            title: "Delete Notification",
            message: "This notification will be permanently deleted. This cannot be undone."
        ) { [weak self] in
            self?.performDeleteNotification(notification, at: indexPath)
        }
    }
    
    private func performDeleteNotification(_ notification: AppNotification, at indexPath: IndexPath) {
        NotificationService.shared.deleteNotification(notificationId: notification.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success:
                    // Remove from data source and update UI
                    self.archivedNotifications.remove(at: indexPath.row)
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                    self.updateUI()
                    self.updateNavigationBarButton()
                    self.showSuccess("Notification deleted")
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

// MARK: - NotificationCell
class NotificationCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let userImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = .tertiarySystemFill
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let iconBackgroundView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(userImageView)
        containerView.addSubview(iconBackgroundView)
        iconBackgroundView.addSubview(iconView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(bodyLabel)
        containerView.addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            userImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            userImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            userImageView.widthAnchor.constraint(equalToConstant: 40),
            userImageView.heightAnchor.constraint(equalToConstant: 40),
            
            iconBackgroundView.trailingAnchor.constraint(equalTo: userImageView.trailingAnchor, constant: 4),
            iconBackgroundView.bottomAnchor.constraint(equalTo: userImageView.bottomAnchor, constant: 4),
            iconBackgroundView.widthAnchor.constraint(equalToConstant: 24),
            iconBackgroundView.heightAnchor.constraint(equalToConstant: 24),
            
            iconView.centerXAnchor.constraint(equalTo: iconBackgroundView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackgroundView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: userImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),
            
            timeLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    func configure(with notification: AppNotification) {
        titleLabel.text = notification.title
        bodyLabel.text = notification.body
        timeLabel.text = formatTime(notification.createdAt)
        
        // Set background tint for unread notifications
        if !notification.read {
            containerView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.05)
        } else {
            containerView.backgroundColor = .secondarySystemGroupedBackground
        }
        
        // Configure icon based on type
        switch notification.type {
        case "place_like":
            iconView.image = UIImage(systemName: "heart.fill")
            iconBackgroundView.backgroundColor = .systemRed
        case "place_comment":
            iconView.image = UIImage(systemName: "bubble.left.fill")
            iconBackgroundView.backgroundColor = .systemBlue
        default:
            iconView.image = UIImage(systemName: "bell.fill")
            iconBackgroundView.backgroundColor = .systemGray
        }
        
        // Load user image if available
        if let photoUrl = notification.data?.fromUserPhoto, !photoUrl.isEmpty {
            ImageService.shared.loadImage(from: photoUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.userImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
    }
    
    private func formatTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return ""
            }
            return formatRelativeTime(date)
        }
        
        return formatRelativeTime(date)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            return days == 1 ? "1d ago" : "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1h ago" : "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1m ago" : "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - AppNotification Model
struct AppNotification: Codable {
    let id: String
    let userId: String
    let type: String
    let title: String
    let body: String
    let data: NotificationData?
    let read: Bool
    let archived: Bool?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, type, title, body, data, read, archived, createdAt
    }
}

struct NotificationData: Codable {
    let fromUserId: String?
    let fromUserName: String?
    let fromUserPhoto: String?
    let placeId: String?
    let placeName: String?
    let circleId: String?
    let commentText: String?
}

// Response structure for notifications
struct NotificationsResponse: Codable {
    let success: Bool
    let notifications: [AppNotification]
    let hasMore: Bool
}
import UIKit

class NotificationsViewController: BaseViewController {
    
    // MARK: - Properties
    private var notifications: [AppNotification] = []
    private var hasMore = true
    private var currentOffset = 0
    private let pageSize = 50
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        return tableView
    }()
    
    
    // MARK: - BaseViewController Overrides
    override var emptyStateMessage: String? { "No notifications yet" }
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
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        loadNotifications(refresh: false, completion: completion)
    }
    
    private func loadNotifications(refresh: Bool = false, completion: (() -> Void)? = nil) {
        guard !isLoadingData else { return }
        
        if refresh {
            currentOffset = 0
            hasMore = true
        }
        
        NotificationService.shared.getNotifications(limit: pageSize, offset: currentOffset) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if refresh {
                        self?.notifications = response.notifications
                    } else {
                        self?.notifications.append(contentsOf: response.notifications)
                    }
                    
                    self?.hasMore = response.hasMore
                    self?.currentOffset += response.notifications.count
                    
                    self?.updateUI()
                    self?.tableView.reloadData()
                    
                case .failure(let error):
                    self?.showError("Failed to load notifications: \(error.localizedDescription)")
                }
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
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, type, title, body, data, read, createdAt
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
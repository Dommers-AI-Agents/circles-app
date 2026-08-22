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
        // Don't mark as read immediately - let user see them first
        // We'll mark as read when they leave the view or after a delay
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Mark all notifications as read when leaving the view
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
        Logger.debug("🚀 NotificationsViewController: loadData called")
        loadNotifications(refresh: false, completion: completion)
    }
    
    private func loadNotifications(refresh: Bool = false, completion: (() -> Void)? = nil) {
        Logger.debug("🚀 NotificationsViewController: loadNotifications called")
        Logger.debug("🚀 NotificationsViewController: refresh: \(refresh), isLoadingData: \(isLoadingData)")
        Logger.debug("🚀 NotificationsViewController: currentTab: \(currentTab)")
        
        let isArchived = currentTab == .archived
        
        if refresh {
            currentOffset = 0
            if currentTab == .active {
                hasMoreActive = true
            } else {
                hasMoreArchived = true
            }
        }
        
        Logger.debug("🚀 NotificationsViewController: Calling NotificationService.getNotifications")
        Logger.debug("🚀 NotificationsViewController: limit: \(pageSize), offset: \(currentOffset), archived: \(isArchived)")
        
        NotificationService.shared.getNotifications(limit: pageSize, offset: currentOffset, archived: isArchived) { [weak self] result in
            Logger.debug("📡 NotificationsViewController: getNotifications callback received")
            
            DispatchQueue.main.async {
                guard let self = self else {
                    completion?()
                    return
                }
                
                switch result {
                case .success(let response):
                    Logger.debug("✅ NotificationsViewController: Successfully loaded notifications")
                    Logger.debug("✅ NotificationsViewController: Received \(response.notifications.count) notifications")
                    Logger.debug("✅ NotificationsViewController: hasMore: \(response.hasMore)")
                    
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
                    
                    Logger.debug("✅ NotificationsViewController: Total notifications now: \(self.notifications.count)")
                    
                    self.updateUI()
                    self.updateNavigationBarButton()
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    Logger.debug("❌ NotificationsViewController: Failed to load notifications: \(error)")
                    Logger.debug("❌ NotificationsViewController: Error type: \(type(of: error))")
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
            // Tell the home bell to clear its unseen dot once the server has
            // actually cleared unread — avoids racing the home screen's own
            // viewWillAppear refresh.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .notificationsMarkedRead, object: nil)
            }
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
        // circleId is optional — a like/comment notification often has none, and
        // PlaceDetailViewController takes an optional circle. Open the place
        // either way; the circle is just extra context when we have it.
        guard let placeId = notification.data?.placeId, !placeId.isEmpty else { return }

        let loadingAlert = AlertPresenter.showLoading(message: "Opening place...", from: self)
        let circleId = notification.data?.circleId

        let openPlace: (Circle?) -> Void = { [weak self] circle in
            PlaceService.shared.fetchPlaceById(id: placeId) { placeResult in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        guard let self = self else { return }
                        switch placeResult {
                        case .success(let place):
                            self.navigationController?.pushViewController(
                                PlaceDetailViewController(place: place, circle: circle), animated: true)
                        case .failure(let error):
                            self.showError(error)
                        }
                    }
                }
            }
        }

        if let circleId = circleId, !circleId.isEmpty {
            CircleService.shared.fetchCircleById(id: circleId) { result in
                DispatchQueue.main.async {
                    // Open the place even if the circle can't be fetched.
                    openPlace((try? result.get()))
                }
            }
        } else {
            openPlace(nil)
        }
    }

    /// Open a user's profile from a notification (fetches the full user first,
    /// same fetch-then-open pattern as navigateToPlace).
    private func navigateToProfile(userId: String) {
        let loadingAlert = AlertPresenter.showLoading(message: "Opening profile...", from: self)
        UserService.shared.fetchUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let user):
                        self.navigationController?.pushViewController(ProfileViewController(user: user), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// Route a tapped notification to the most relevant destination.
    private func route(_ notification: AppNotification) {
        let fromUserId = notification.data?.fromUserId ?? ""
        switch notification.type {
        case "connection_request":
            // Actioned via inline Accept/Decline; row body → the Requests
            // segment of My Network, where the request actually lives.
            routeToMyNetwork()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showRequestsSegment, object: nil)
            }
        case "connection_accepted":
            fromUserId.isEmpty ? routeToMyNetwork() : navigateToProfile(userId: fromUserId)
        case "new_follower":
            fromUserId.isEmpty ? routeToMyNetwork() : navigateToProfile(userId: fromUserId)
        case "store_claim":
            // Admin-only: a store-ownership claim awaits review in the claims tray.
            navigationController?.pushViewController(VenueClaimsViewController(), animated: true)
        case "store_claim_approved":
            // The claimant is now an owner — land them on their stores list,
            // which auto-pushes into the manage hub when there's just one.
            navigationController?.pushViewController(OwnerVenuesViewController(), animated: true)
        case "new_message":
            // A message notification opens the conversation — the row used to
            // fall to the default and do nothing (no placeId/fromUserId)
            if let conversationId = notification.data?.conversationId, !conversationId.isEmpty {
                NotificationCenter.default.post(name: Notification.Name("NavigateToConversation"), object: conversationId)
            } else if let senderId = notification.data?.senderId, !senderId.isEmpty {
                navigateToProfile(userId: senderId)
            } else {
                NotificationCenter.default.post(name: Notification.Name("NavigateToMessages"), object: nil)
            }
        default:
            // Place-centric (like/comment/new place/suggestion) → the place;
            // otherwise the person who triggered it; otherwise nothing to open.
            if let placeId = notification.data?.placeId, !placeId.isEmpty {
                navigateToPlace(notification: notification)
            } else if !fromUserId.isEmpty {
                navigateToProfile(userId: fromUserId)
            }
        }
    }

    /// Mark a notification read on tap so the bell badge reflects triage.
    private func markReadIfNeeded(_ notification: AppNotification) {
        guard !notification.read else { return }
        NotificationService.shared.markNotificationAsRead(notificationId: notification.id) { _ in }
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
        cell.delegate = self
        cell.configure(with: notification)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension NotificationsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let notification = notifications[indexPath.row]
        markReadIfNeeded(notification)
        route(notification)
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

// MARK: - Inline connection request actions
extension NotificationsViewController: NotificationCellDelegate {
    func notificationCell(_ cell: NotificationCell, didTapAcceptFor notification: AppNotification) {
        guard let connectionId = notification.data?.connectionId, !connectionId.isEmpty else {
            routeToMyNetwork() // Older notification without an id — send them where they can act
            return
        }
        NetworkManager.shared.acceptConnection(connectionId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    // The cell already shows the green "✓ Connected" confirmation
                    // (no modal needed). Let it read for a beat, then drop the row.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self.removeActionedNotification(notification)
                    }
                case .failure(let error):
                    self.showError(error)
                    self.tableView.reloadData() // re-enable the row's buttons
                }
            }
        }
    }

    func notificationCell(_ cell: NotificationCell, didTapDeclineFor notification: AppNotification) {
        guard let connectionId = notification.data?.connectionId, !connectionId.isEmpty else {
            routeToMyNetwork()
            return
        }
        NetworkManager.shared.declineConnection(connectionId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    // Cell shows the gray "Declined" state; hold briefly, then remove.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.removeActionedNotification(notification)
                    }
                case .failure(let error):
                    self.showError(error)
                    self.tableView.reloadData()
                }
            }
        }
    }

    func notificationCell(_ cell: NotificationCell, didTapFollowBackFor notification: AppNotification) {
        guard let userId = notification.data?.fromUserId, !userId.isEmpty else {
            routeToMyNetwork()
            return
        }

        // The cell has already flipped to "Following" — a follow is instant and
        // reversible, so there's nothing to wait for. Only failure needs to say
        // anything.
        APIService.shared.request(
            endpoint: "users/\(userId)/follow",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let response) = result {
                    // First-ever follow of this person earns a dime
                    PiggyBankDepositView.play(credit: response.piggyBank)
                } else if case .failure(let error) = result {
                    // "Already following" is the state the user wanted — the
                    // cell's "✓ Following" is correct, so stay quiet. (The
                    // server is idempotent now; this guards older responses.)
                    let message = (error.serverMessage ?? "").lowercased()
                    if message.contains("already following") { return }
                    self.showError(error)
                    self.tableView.reloadData()
                }
            }
        }
    }

    /// Once a request is accepted/declined the notification is stale — drop it
    /// from the list and clean it up server-side so it doesn't reappear on
    /// refresh. The tab badge is driven separately by pendingConnections, which
    /// acceptConnection/declineConnection already update.
    private func removeActionedNotification(_ notification: AppNotification) {
        NotificationService.shared.deleteNotification(notificationId: notification.id) { _ in }
        activeNotifications.removeAll { $0.id == notification.id }
        archivedNotifications.removeAll { $0.id == notification.id }
        tableView.reloadData()
        updateUI()
    }

    private func routeToMyNetwork() {
        // My Network is tab index 1 (see CirclesTabBarController)
        tabBarController?.selectedIndex = 1
    }
}

// MARK: - NotificationCellDelegate
protocol NotificationCellDelegate: AnyObject {
    func notificationCell(_ cell: NotificationCell, didTapAcceptFor notification: AppNotification)
    func notificationCell(_ cell: NotificationCell, didTapDeclineFor notification: AppNotification)
    func notificationCell(_ cell: NotificationCell, didTapFollowBackFor notification: AppNotification)
}

// MARK: - NotificationCell
class NotificationCell: UITableViewCell {

    weak var delegate: NotificationCellDelegate?
    private var notification: AppNotification?

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

    // Inline Accept/Decline for connection_request notifications, so a
    // recipient (often with push off) can act right where they see the request
    // instead of hunting through the My Network tab.
    private lazy var acceptButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Accept", style: .primary)
        button.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        return button
    }()

    private lazy var declineButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Decline", style: .secondary)
        button.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
        return button
    }()

    /// "X started following you" is the single best moment to offer a follow
    /// back: the other person has already opted in, so it's one tap with no
    /// approval step. Previously this row was read-only and the moment passed.
    private lazy var followBackButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Follow back", style: .primary)
        button.addTarget(self, action: #selector(followBackTapped), for: .touchUpInside)
        return button
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [acceptButton, declineButton, followBackButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    // Activated only for connection-request rows (adds the button row's height)
    private var actionConstraints: [NSLayoutConstraint] = []

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
        containerView.addSubview(actionStack)

        // Toggled on for connection_request rows in configure(). bodyLabel's
        // existing bottom constraint is a `<=`, so when these are inactive the
        // cell sizes exactly as before; when active the stack pins the bottom
        // and the cell grows to include the button row.
        actionConstraints = [
            actionStack.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 10),
            actionStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            actionStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            actionStack.heightAnchor.constraint(equalToConstant: 34)
        ]

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
        self.notification = notification
        followedBack = false
        // Cells are reused: restore the action buttons to their canonical look
        // in case a previous row left one in a success state (green "Connected",
        // gray "Following", etc.).
        resetActionButtonStyles()
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
        case "connection_request":
            iconView.image = UIImage(systemName: "person.badge.plus.fill")
            iconBackgroundView.backgroundColor = Constants.Colors.primary
        case "new_follower":
            iconView.image = UIImage(systemName: "person.fill.checkmark")
            iconBackgroundView.backgroundColor = Constants.Colors.primary
        case "store_claim":
            iconView.image = UIImage(systemName: "storefront.fill")
            iconBackgroundView.backgroundColor = .systemOrange
        case "store_claim_approved":
            iconView.image = UIImage(systemName: "storefront.fill")
            iconBackgroundView.backgroundColor = .systemGreen
        default:
            iconView.image = UIImage(systemName: "bell.fill")
            iconBackgroundView.backgroundColor = .systemGray
        }

        // Inline Accept/Decline only for a live, actionable connection request
        // (needs a connectionId; archived requests are read-only history)
        let hasConnectionId = !(notification.data?.connectionId ?? "").isEmpty
        let isLive = notification.archived != true
        let showConnectionActions = notification.type == "connection_request" && hasConnectionId && isLive
        // Follow back needs someone to follow, and is pointless once you
        // already follow them.
        let showFollowBack = notification.type == "new_follower"
            && !(notification.data?.fromUserId ?? "").isEmpty
            && isLive
            && !followedBack

        acceptButton.isHidden = !showConnectionActions
        declineButton.isHidden = !showConnectionActions
        followBackButton.isHidden = !showFollowBack

        if showConnectionActions || showFollowBack {
            actionStack.isHidden = false
            NSLayoutConstraint.activate(actionConstraints)
            setActionsEnabled(true)
        } else {
            NSLayoutConstraint.deactivate(actionConstraints)
            actionStack.isHidden = true
        }

        // A follow you've already made is settled state, not an action —
        // show the gray "✓ Following" instead of an inviting blue button
        // that can only no-op.
        if showFollowBack,
           let fromId = notification.data?.fromUserId,
           AuthService.shared.currentUser?.following?.contains(fromId) == true {
            applyFollowingStyle(followBackButton)
            followBackButton.isUserInteractionEnabled = false
        }

        // Reused cells must never keep the previous row's face: reset to the
        // placeholder unconditionally, then load only if this notification
        // carries a photo — and drop late responses that belong to a row this
        // cell no longer shows.
        userImageView.image = UIImage(systemName: "person.circle.fill")
        if let photoUrl = notification.data?.fromUserPhoto, !photoUrl.isEmpty {
            ImageService.shared.loadImage(from: photoUrl) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self = self, self.notification?.id == notification.id else { return }
                    self.userImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
    }

    // MARK: - Connection request actions
    private func setActionsEnabled(_ enabled: Bool) {
        acceptButton.isEnabled = enabled
        declineButton.isEnabled = enabled
        acceptButton.alpha = enabled ? 1.0 : 0.5
        declineButton.alpha = enabled ? 1.0 : 0.5
    }

    /// Set once the follow succeeds so the button doesn't reappear on reuse.
    private var followedBack = false

    @objc private func followBackTapped() {
        guard let notification = notification else { return }
        followedBack = true
        // Instant, reversible action — confirm optimistically. Blue "Follow
        // back" becomes a settled gray "✓ Following" so the tap clearly landed.
        applyFollowingStyle(followBackButton)
        Self.successHaptic()
        delegate?.notificationCell(self, didTapFollowBackFor: notification)
    }

    @objc private func acceptTapped() {
        guard let notification = notification else { return }
        setActionsEnabled(false) // prevent double-taps; row is removed on success
        // Collapse the two buttons into a single green "✓ Connected" so the
        // accept visibly succeeds before the row animates away.
        declineButton.isHidden = true
        applyConfirmedStyle(acceptButton, title: "✓ Connected", color: .systemGreen)
        Self.successHaptic()
        delegate?.notificationCell(self, didTapAcceptFor: notification)
    }

    @objc private func declineTapped() {
        guard let notification = notification else { return }
        setActionsEnabled(false)
        acceptButton.isHidden = true
        applyConfirmedStyle(declineButton, title: "Declined", color: .systemGray)
        Self.lightHaptic()
        delegate?.notificationCell(self, didTapDeclineFor: notification)
    }

    // MARK: - Action-button styling (success morphs + reuse reset)

    /// Restores the three action buttons to their factory look. Called from
    /// configure() because cells are reused and a success morph must not bleed
    /// into the next row.
    private func resetActionButtonStyles() {
        applyPrimaryStyle(acceptButton, title: "Accept")
        applySecondaryStyle(declineButton, title: "Decline")
        applyPrimaryStyle(followBackButton, title: "Follow back")
        [acceptButton, declineButton, followBackButton].forEach {
            $0.isEnabled = true
            $0.alpha = 1.0
            $0.isUserInteractionEnabled = true
        }
    }

    private func applyPrimaryStyle(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.borderWidth = 0
    }

    private func applySecondaryStyle(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .clear
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
    }

    private func applyFollowingStyle(_ button: UIButton) {
        button.isEnabled = false
        button.setTitle("✓ Following", for: .normal)
        button.setTitleColor(.systemGray, for: .normal)
        button.backgroundColor = .systemGray5
        button.layer.borderWidth = 0
    }

    private func applyConfirmedStyle(_ button: UIButton, title: String, color: UIColor) {
        button.isEnabled = false
        button.isHidden = false
        button.alpha = 1.0
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color
        button.layer.borderWidth = 0
    }

    private static func successHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private static func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        case id // Backend now sends "id" not "_id"
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
    let connectionId: String? // Present on connection_request notifications
    let senderId: String?        // new_message notifications
    let conversationId: String?  // new_message notifications
}

// Response structure for notifications
struct NotificationsResponse: Codable {
    let success: Bool
    let notifications: [AppNotification]
    let hasMore: Bool
}
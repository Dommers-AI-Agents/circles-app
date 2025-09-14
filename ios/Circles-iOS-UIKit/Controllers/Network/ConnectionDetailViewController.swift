import UIKit


class ConnectionDetailViewController: BaseViewController {
    
    // MARK: - Properties
    var connection: Connection?
    
    // MARK: - Helper Methods
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 60
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let userInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let connectionDateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var messageButton: UIButton = {
        let button = UIButton.primaryButton(title: "Message")
        button.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var followButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Follow")
        button.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var connectButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Connect")
        button.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var removeButton: UIButton = {
        let button = UIButton.dangerButton(title: "Remove Connection")
        button.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Notification Settings
    private let notificationsSectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Notifications"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notificationsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let notificationTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Activity Updates"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notificationDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Get notified when they add places, share moments, or create circles"
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var activityNotificationsToggle: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = false // Default to disabled - user must opt-in for comprehensive activity notifications
        toggle.addTarget(self, action: #selector(activityNotificationsToggled), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    private let circlesSectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circlesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 16
        let screenWidth = UIScreen.main.bounds.width
        let itemWidth = (screenWidth - 60) / 2 // 20 margin + 20 margin + 16 spacing = 56, remaining space / 2
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth + 40) // Extra height for labels
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let noCirclesLabel: UILabel = {
        let label = UILabel()
        label.text = "No circles to show"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // MARK: - Properties
    private var connectionCircles: [Circle] = []
    private var isFollowing: Bool = false
    private var connectionUser: User?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        configureView()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Connection"
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(userInfoLabel)
        contentView.addSubview(connectionDateLabel)
        contentView.addSubview(messageButton)
        contentView.addSubview(followButton)
        contentView.addSubview(connectButton)
        contentView.addSubview(removeButton)
        
        // Add notification settings views
        contentView.addSubview(notificationsSectionLabel)
        contentView.addSubview(notificationsContainer)
        notificationsContainer.addSubview(notificationTitleLabel)
        notificationsContainer.addSubview(notificationDescriptionLabel)
        notificationsContainer.addSubview(activityNotificationsToggle)
        
        contentView.addSubview(circlesSectionLabel)
        contentView.addSubview(circlesCollectionView)
        contentView.addSubview(noCirclesLabel)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            profileImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 120),
            profileImageView.heightAnchor.constraint(equalToConstant: 120),
            
            nameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            userInfoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            userInfoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            userInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            connectionDateLabel.topAnchor.constraint(equalTo: userInfoLabel.bottomAnchor, constant: 8),
            connectionDateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            connectionDateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            messageButton.topAnchor.constraint(equalTo: connectionDateLabel.bottomAnchor, constant: 24),
            messageButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            messageButton.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -8),
            messageButton.heightAnchor.constraint(equalToConstant: 48),
            
            followButton.topAnchor.constraint(equalTo: connectionDateLabel.bottomAnchor, constant: 24),
            followButton.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 8),
            followButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            followButton.heightAnchor.constraint(equalToConstant: 48),
            
            connectButton.topAnchor.constraint(equalTo: connectionDateLabel.bottomAnchor, constant: 24),
            connectButton.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 8),
            connectButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            connectButton.heightAnchor.constraint(equalToConstant: 48),
            
            removeButton.topAnchor.constraint(equalTo: messageButton.bottomAnchor, constant: 16),
            removeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Notification settings section
            notificationsSectionLabel.topAnchor.constraint(equalTo: removeButton.bottomAnchor, constant: 32),
            notificationsSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            notificationsSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            notificationsContainer.topAnchor.constraint(equalTo: notificationsSectionLabel.bottomAnchor, constant: 12),
            notificationsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            notificationsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Constraints inside notifications container
            notificationTitleLabel.topAnchor.constraint(equalTo: notificationsContainer.topAnchor, constant: 16),
            notificationTitleLabel.leadingAnchor.constraint(equalTo: notificationsContainer.leadingAnchor, constant: 16),
            notificationTitleLabel.trailingAnchor.constraint(equalTo: activityNotificationsToggle.leadingAnchor, constant: -16),
            
            activityNotificationsToggle.centerYAnchor.constraint(equalTo: notificationTitleLabel.centerYAnchor),
            activityNotificationsToggle.trailingAnchor.constraint(equalTo: notificationsContainer.trailingAnchor, constant: -16),
            
            notificationDescriptionLabel.topAnchor.constraint(equalTo: notificationTitleLabel.bottomAnchor, constant: 4),
            notificationDescriptionLabel.leadingAnchor.constraint(equalTo: notificationsContainer.leadingAnchor, constant: 16),
            notificationDescriptionLabel.trailingAnchor.constraint(equalTo: activityNotificationsToggle.leadingAnchor, constant: -16),
            notificationDescriptionLabel.bottomAnchor.constraint(equalTo: notificationsContainer.bottomAnchor, constant: -16),
            
            circlesSectionLabel.topAnchor.constraint(equalTo: notificationsContainer.bottomAnchor, constant: 32),
            circlesSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            circlesSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            circlesCollectionView.topAnchor.constraint(equalTo: circlesSectionLabel.bottomAnchor, constant: 12),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            circlesCollectionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            
            noCirclesLabel.centerXAnchor.constraint(equalTo: circlesCollectionView.centerXAnchor),
            noCirclesLabel.centerYAnchor.constraint(equalTo: circlesCollectionView.centerYAnchor),
            noCirclesLabel.leadingAnchor.constraint(equalTo: circlesCollectionView.leadingAnchor),
            noCirclesLabel.trailingAnchor.constraint(equalTo: circlesCollectionView.trailingAnchor, constant: -20),
            
            circlesCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        messageButton.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followButtonTapped), for: .touchUpInside)
        connectButton.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        
        // Setup collection view
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        
        // Add tap gesture for profile image to view full-screen
        profileImageView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.addGestureRecognizer(tapGesture)
    }
    
    private func configureView() {
        guard let connection = connection else { return }
        
        // Display only displayName for privacy
        nameLabel.text = connection.connectedUser?.displayName ?? "Unknown User"
        
        // Display user info instead of email for privacy
        if let phoneNumber = connection.connectedUser?.phoneNumber, !phoneNumber.isEmpty {
            userInfoLabel.text = "📞 \(phoneNumber)"
        } else if let bio = connection.connectedUser?.bio, !bio.isEmpty {
            userInfoLabel.text = bio
        } else if let location = connection.connectedUser?.location, !location.isEmpty {
            userInfoLabel.text = location
        } else {
            userInfoLabel.text = "Circles member"
        }
        
        if let acceptedAt = connection.acceptedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            connectionDateLabel.text = "Connected since \(formatter.string(from: acceptedAt))"
        }
        
        // Set initial state of activity notifications toggle
        activityNotificationsToggle.isOn = connection.activityNotificationsEnabled ?? false
        
        // Load connection's circles and check follow status
        loadConnectionCircles()
        checkFollowStatus()
        updateButtonVisibility()
    }
    
    private func loadConnectionCircles() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { 
            print("Error: No connection or current user ID found")
            return 
        }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
        print("Loading circles for user: \(userId)")
        
        // Use the network endpoint that properly checks connections
        struct UserCirclesResponse: Codable {
            let success: Bool
            let data: UserCirclesData
        }
        
        struct UserCirclesData: Codable {
            let user: User
            let circles: [Circle]
        }
        
        APIService.shared.request(
            endpoint: "network/user-circles/\(userId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCirclesResponse, APIError>) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.connectionCircles = response.data.circles
                    self.circlesCollectionView.reloadData()
                    self.noCirclesLabel.isHidden = !response.data.circles.isEmpty
                    self.circlesCollectionView.isHidden = response.data.circles.isEmpty
                case .failure(let error):
                    print("Failed to load connection circles: \(error)")
                    self.connectionCircles = []
                    self.circlesCollectionView.reloadData()
                    self.noCirclesLabel.isHidden = false
                    self.circlesCollectionView.isHidden = true
                    
                    // Show specific error message
                    let errorMessage: String
                    if case .httpError(let statusCode, _) = error {
                        switch statusCode {
                        case 403:
                            errorMessage = "You are not connected to this user"
                        case 404:
                            errorMessage = "User not found"
                        default:
                            errorMessage = "Failed to load circles"
                        }
                    } else {
                        errorMessage = "Failed to load circles: \(error.localizedDescription)"
                    }
                    
                    self.showError(errorMessage)
                }
            }
        }
    }
    
    private func checkFollowStatus() {
        // This should be updated when we implement follow checking
        // For now, default to not following
        isFollowing = false
    }
    
    private func updateButtonVisibility() {
        guard let connection = connection else { return }
        
        let isConnected = connection.status == .accepted
        
        // Show/hide buttons based on connection status
        messageButton.isHidden = !isConnected
        removeButton.isHidden = !isConnected
        
        // Show/hide notifications section only for connected users
        notificationsSectionLabel.isHidden = !isConnected
        notificationsContainer.isHidden = !isConnected
        
        // For connected users, show follow button but not connect button
        followButton.isHidden = !isConnected
        connectButton.isHidden = isConnected
        
        // Update follow button text based on follow status
        if isFollowing {
            followButton.setTitle("Following", for: .normal)
            followButton.backgroundColor = Constants.Colors.primary
            followButton.tintColor = .white
            followButton.layer.borderWidth = 0
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.backgroundColor = .clear
            followButton.tintColor = Constants.Colors.primary
            followButton.layer.borderWidth = 1
        }
    }
    
    // MARK: - Actions
    @objc private func followButtonTapped() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { return }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
        let endpoint = isFollowing ? "users/\(userId)/unfollow" : "users/\(userId)/follow"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowResponse, APIError>) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.isFollowing.toggle()
                    self.updateButtonVisibility()
                case .failure(let error):
                    self.showErrorWithRetry(error) {
                        self.followButtonTapped()
                    }
                }
            }
        }
    }
    
    @objc private func connectButtonTapped() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { return }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
        // Send connection request
        NetworkManager.shared.sendConnectionRequest(to: userId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    AlertPresenter.showSuccess(message: "Connection request sent!", from: self) {
                        self.updateButtonVisibility()
                    }
                case .failure(let error):
                    self.showErrorWithRetry(error) {
                        self.connectButtonTapped()
                    }
                }
            }
        }
    }

    @objc private func messageButtonTapped() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { return }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
        // Create or get conversation
        MessagingManager.shared.createOrGetDirectConversation(with: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let conversation):
                DispatchQueue.main.async {
                    let chatVC = ChatViewController()
                    chatVC.conversation = conversation
                    self.navigationController?.pushViewController(chatVC, animated: true)
                }
            case .failure(let error):
                self.showErrorWithRetry(error) {
                    self.messageButtonTapped()
                }
            }
        }
    }
    
    @objc private func removeButtonTapped() {
        AlertPresenter.showConfirmation(
            title: "Remove Connection",
            message: "Are you sure you want to remove this connection?",
            confirmTitle: "Remove",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                guard let self = self else { return }
                self.removeConnection()
            }
        )
    }
    
    private func removeConnection() {
        guard let connectionId = connection?.id else { return }
        
        let loadingAlert = AlertPresenter.showLoading(message: "Removing connection...", from: self)
        
        NetworkManager.shared.removeConnection(connectionId: connectionId) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    if let error = error {
                        self.showErrorWithRetry(error) {
                            self.removeConnection()
                        }
                    } else {
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            }
        }
    }
    
    @objc private func profileImageTapped() {
        // Show full-screen profile image
        if let user = connection?.connectedUser, let profileImageURL = user.profilePicture {
            ImageViewerService.shared.presentImageFromURL(profileImageURL, from: self)
        } else if let currentImage = profileImageView.image {
            ImageViewerService.shared.presentImage(currentImage, from: self)
        }
    }
    
    @objc private func activityNotificationsToggled() {
        guard let connection = connection else { return }
        
        let isEnabled = activityNotificationsToggle.isOn
        
        // Show loading state while updating
        activityNotificationsToggle.isEnabled = false
        
        // Update connection notification preference
        updateConnectionNotificationPreference(connectionId: connection.id, enabled: isEnabled) { [weak self] success in
            DispatchQueue.main.async {
                self?.activityNotificationsToggle.isEnabled = true
                
                if !success {
                    // Revert toggle state if update failed
                    self?.activityNotificationsToggle.setOn(!isEnabled, animated: true)
                    self?.showError("Failed to update notification preference")
                }
            }
        }
    }
    
    private func updateConnectionNotificationPreference(connectionId: String, enabled: Bool, completion: @escaping (Bool) -> Void) {
        // Create a simple response model for this endpoint
        struct NotificationPreferenceResponse: Codable {
            let success: Bool
            let message: String?
        }
        
        APIService.shared.request(
            endpoint: "connections/\(connectionId)/notifications",
            method: .put,
            body: ["activityNotificationsEnabled": enabled],
            requiresAuth: true
        ) { (result: Result<NotificationPreferenceResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ Connection notification preference updated: \(response.success)")
                completion(response.success)
            case .failure(let error):
                print("❌ Failed to update connection notification preference: \(error)")
                completion(false)
            }
        }
    }
    
}

// MARK: - UICollectionViewDataSource
extension ConnectionDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return connectionCircles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as! CircleCell
        let circle = connectionCircles[indexPath.item]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ConnectionDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let circle = connectionCircles[indexPath.item]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension ConnectionDetailViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let availableWidth = collectionView.frame.width
        let itemWidth = (availableWidth - 16) / 2 // 16 for spacing between items
        let itemHeight = itemWidth + 40 // Extra height for labels below circles
        return CGSize(width: itemWidth, height: itemHeight)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
    }
}
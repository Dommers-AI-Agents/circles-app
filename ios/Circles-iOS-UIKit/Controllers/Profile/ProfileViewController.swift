import UIKit

class ProfileViewController: UIViewController {
    
    // MARK: - Properties
    private var user: User?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileHeaderView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 50
        imageView.layer.borderWidth = 3
        imageView.layer.borderColor = Constants.Colors.background.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let displayNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xxlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let fullNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bioLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let editProfileButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Edit Profile", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let statsView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circlesLabel: UILabel = {
        let label = UILabel()
        label.text = "3"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circlesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placesLabel: UILabel = {
        let label = UILabel()
        label.text = "12"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Places"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let friendsLabel: UILabel = {
        let label = UILabel()
        label.text = "42"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let friendsTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Friends"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let divider1View: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let divider2View: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let logoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Log Out", for: .normal)
        button.setTitleColor(Constants.Colors.danger, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let versionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    
    init(user: User? = nil) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        loadUserProfile()
        displayAppVersion()
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
        profileImageView.layer.borderColor = Constants.Colors.background.cgColor
        editProfileButton.layer.borderColor = Constants.Colors.primary.cgColor
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Profile"
        
        // Add right bar button item (settings)
        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(settingsButtonTapped))
        navigationItem.rightBarButtonItem = settingsButton
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileHeaderView)
        profileHeaderView.addSubview(profileImageView)
        profileHeaderView.addSubview(displayNameLabel)
        profileHeaderView.addSubview(fullNameLabel)
        profileHeaderView.addSubview(emailLabel)
        profileHeaderView.addSubview(locationLabel)
        profileHeaderView.addSubview(bioLabel)
        profileHeaderView.addSubview(editProfileButton)
        
        contentView.addSubview(statsView)
        statsView.addSubview(circlesLabel)
        statsView.addSubview(circlesTitleLabel)
        statsView.addSubview(placesLabel)
        statsView.addSubview(placesTitleLabel)
        statsView.addSubview(friendsLabel)
        statsView.addSubview(friendsTitleLabel)
        statsView.addSubview(divider1View)
        statsView.addSubview(divider2View)
        
        contentView.addSubview(logoutButton)
        contentView.addSubview(versionLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Profile header view
            profileHeaderView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.medium),
            profileHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            profileHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Profile image view
            profileImageView.topAnchor.constraint(equalTo: profileHeaderView.topAnchor, constant: Constants.Spacing.large),
            profileImageView.centerXAnchor.constraint(equalTo: profileHeaderView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 100),
            profileImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Display name label
            displayNameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.medium),
            displayNameLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            displayNameLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Full name label
            fullNameLabel.topAnchor.constraint(equalTo: displayNameLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            fullNameLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            fullNameLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Email label
            emailLabel.topAnchor.constraint(equalTo: fullNameLabel.bottomAnchor, constant: Constants.Spacing.small),
            emailLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            emailLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Location label
            locationLabel.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: Constants.Spacing.small),
            locationLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            locationLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: Constants.Spacing.medium),
            bioLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            bioLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Edit profile button
            editProfileButton.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: Constants.Spacing.large),
            editProfileButton.centerXAnchor.constraint(equalTo: profileHeaderView.centerXAnchor),
            editProfileButton.widthAnchor.constraint(equalToConstant: 150),
            editProfileButton.heightAnchor.constraint(equalToConstant: 40),
            editProfileButton.bottomAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: -Constants.Spacing.large),
            
            // Stats view
            statsView.topAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: Constants.Spacing.large),
            statsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            statsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            statsView.heightAnchor.constraint(equalToConstant: 100),
            
            // Circles label
            circlesLabel.topAnchor.constraint(equalTo: statsView.topAnchor, constant: Constants.Spacing.medium),
            // Using fractional multipliers instead of bounds which aren't available yet
            
            // Divider 1
            divider1View.topAnchor.constraint(equalTo: statsView.topAnchor, constant: Constants.Spacing.medium),
            divider1View.centerXAnchor.constraint(equalTo: statsView.centerXAnchor),
            divider1View.widthAnchor.constraint(equalToConstant: 1),
            divider1View.bottomAnchor.constraint(equalTo: statsView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            // Places label
            placesLabel.topAnchor.constraint(equalTo: statsView.topAnchor, constant: Constants.Spacing.medium),
            placesLabel.centerXAnchor.constraint(equalTo: statsView.centerXAnchor),
            
            // Places title label
            placesTitleLabel.topAnchor.constraint(equalTo: placesLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            placesTitleLabel.centerXAnchor.constraint(equalTo: placesLabel.centerXAnchor),
            
            // Divider 2
            divider2View.topAnchor.constraint(equalTo: statsView.topAnchor, constant: Constants.Spacing.medium),
            divider2View.widthAnchor.constraint(equalToConstant: 1),
            divider2View.bottomAnchor.constraint(equalTo: statsView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            // Friends label
            friendsLabel.topAnchor.constraint(equalTo: statsView.topAnchor, constant: Constants.Spacing.medium),
            
            // Friends title label
            friendsTitleLabel.topAnchor.constraint(equalTo: friendsLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            friendsTitleLabel.centerXAnchor.constraint(equalTo: friendsLabel.centerXAnchor),
            
            // Logout button
            logoutButton.topAnchor.constraint(equalTo: statsView.bottomAnchor, constant: Constants.Spacing.xlarge),
            logoutButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoutButton.widthAnchor.constraint(equalToConstant: 100),
            logoutButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Version label
            versionLabel.topAnchor.constraint(equalTo: logoutButton.bottomAnchor, constant: Constants.Spacing.medium),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            versionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Create constraints using proportional horizontal distribution
        DispatchQueue.main.async {
            let statsWidth = self.statsView.frame.width
            
            // Position the elements using a proportional layout
            NSLayoutConstraint.activate([
                // Position circles at 1/6 of the width from the left
                self.circlesLabel.centerXAnchor.constraint(equalTo: self.statsView.leadingAnchor, constant: statsWidth/6),
                self.circlesTitleLabel.centerXAnchor.constraint(equalTo: self.circlesLabel.centerXAnchor),
                
                // Position divider2 at 2/3 of the width from the left
                self.divider2View.centerXAnchor.constraint(equalTo: self.statsView.leadingAnchor, constant: statsWidth*2/3),
                
                // Position friends at 5/6 of the width from the left
                self.friendsLabel.centerXAnchor.constraint(equalTo: self.statsView.leadingAnchor, constant: statsWidth*5/6),
                self.friendsTitleLabel.centerXAnchor.constraint(equalTo: self.friendsLabel.centerXAnchor)
            ])
            
            self.view.layoutIfNeeded()
        }
    }
    
    private func setupActions() {
        editProfileButton.addTarget(self, action: #selector(editProfileButtonTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        
        // Apply initial appearance
        updateAppearance()
    }
    
    // MARK: - Actions
    @objc private func editProfileButtonTapped() {
        let editProfileVC = EditProfileViewController()
        navigationController?.pushViewController(editProfileVC, animated: true)
    }
    
    @objc private func logoutButtonTapped() {
        let alert = UIAlertController(title: "Logout", message: "Are you sure you want to logout?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { [weak self] _ in
            self?.logout()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func settingsButtonTapped() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
    }
    
    // MARK: - Data Loading
    private func loadUserProfile() {
        if let user = self.user {
            // If user is provided, use it
            displayUser(user)
            fetchUserStats(userId: user.id)
        } else {
            // Otherwise fetch current user
            if let currentUser = AuthService.shared.currentUser {
                // If we already have current user cached, use it
                self.user = currentUser
                displayUser(currentUser)
                fetchUserStats(userId: currentUser.id)
            } else {
                // Otherwise load from API
                AuthService.shared.fetchCurrentUser { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let user):
                            self.user = user
                            self.displayUser(user)
                            self.fetchUserStats(userId: user.id)
                        case .failure:
                            // Show error or default values
                            self.displayDefaultProfile()
                        }
                    }
                }
            }
        }
    }
    
    private func displayUser(_ user: User) {
        // Update UI with user data
        if let profileImageUrl = user.profilePicture {
            // In a real app, load image from URL
            ImageService.shared.loadImage(from: profileImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        self?.profileImageView.tintColor = Constants.Colors.primary
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
        
        // Display user's name - show display name and full name separately
        displayNameLabel.text = user.displayName
        
        // Show full name if available
        if let firstName = user.firstName, let lastName = user.lastName {
            fullNameLabel.text = "\(firstName) \(lastName)"
            fullNameLabel.isHidden = false
        } else if let firstName = user.firstName {
            fullNameLabel.text = firstName
            fullNameLabel.isHidden = false
        } else if let lastName = user.lastName {
            fullNameLabel.text = lastName
            fullNameLabel.isHidden = false
        } else {
            fullNameLabel.isHidden = true
        }
        
        emailLabel.text = user.email
        locationLabel.text = user.location
        bioLabel.text = user.bio
        
        // Show/hide edit button based on whether this is the current user
        editProfileButton.isHidden = user.id != AuthService.shared.getUserId()
    }
    
    private func fetchUserStats(userId: String) {
        // For current user, fetch their circles
        if userId == AuthService.shared.getUserId() {
            // Fetch circles count
            CircleService.shared.fetchUserCircles { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let circles):
                        self?.circlesLabel.text = "\(circles.count)"
                    case .failure:
                        self?.circlesLabel.text = "0"
                    }
                }
            }
            
            // Fetch places count from circles
            CircleService.shared.fetchUserCircles { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let circles):
                        let totalPlaces = circles.reduce(0) { $0 + ($1.places?.count ?? 0) }
                        self?.placesLabel.text = "\(totalPlaces)"
                    case .failure:
                        self?.placesLabel.text = "0"
                    }
                }
            }
            
            // Fetch connections count
            let connectionsCount = NetworkManager.shared.connections.count
            friendsLabel.text = "\(connectionsCount)"
        } else {
            // For other users, show default stats
            // In a real app, you might have an endpoint to fetch public stats
            circlesLabel.text = "0"
            placesLabel.text = "0"
            friendsLabel.text = "0"
        }
    }
    
    private func displayDefaultProfile() {
        // Fallback default display
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = Constants.Colors.primary
        
        displayNameLabel.text = "User"
        fullNameLabel.isHidden = true
        emailLabel.text = "No email available"
        locationLabel.text = "No location available"
        bioLabel.text = "No bio available"
        
        circlesLabel.text = "0"
        placesLabel.text = "0"
        friendsLabel.text = "0"
    }
    
    private func displayAppVersion() {
        // Get app version from Info.plist
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        versionLabel.text = "Version \(appVersion) (\(buildNumber))"
    }
    
    private func logout() {
        // Log out the user
        AuthService.shared.logout()
        
        // Show login screen
        let loginVC = LoginViewController()
        let navController = UINavigationController(rootViewController: loginVC)
        
        // Get the scene from the current window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController = navController
            window.makeKeyAndVisible()
        }
    }
}

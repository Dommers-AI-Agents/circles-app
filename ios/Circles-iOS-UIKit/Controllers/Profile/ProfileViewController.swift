import UIKit

// MARK: - StatView
class StatView: UIView {
    private let numberLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        addSubview(numberLabel)
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            numberLabel.topAnchor.constraint(equalTo: topAnchor),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    func configure(number: String, title: String) {
        numberLabel.text = number
        titleLabel.text = title
    }
}

class ProfileViewController: UIViewController {
    
    // MARK: - Properties
    private var user: User?
    private var circles: [Circle] = []
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Profile Header Section
    private let profileHeaderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 45
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.separator.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // Username at top
    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Stats container
    private let statsContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Individual stat views
    private let circlesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placesStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let connectionsStatView: StatView = {
        let view = StatView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Bio section
    private let fullNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bioLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Buttons container
    private let buttonsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let editProfileButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Edit profile", for: .normal)
        button.setTitleColor(Constants.Colors.label, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let shareProfileButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Share profile", for: .normal)
        button.setTitleColor(Constants.Colors.label, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let suggestedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "person.badge.plus"), for: .normal)
        button.tintColor = Constants.Colors.label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
    
    // Separator line
    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Circles list section
    private let circlesHeaderView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circlesHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "" // No text for Instagram style
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 25
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.3
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let circlesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Constants.Colors.background
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.isScrollEnabled = false
        return collectionView
    }()
    
    private var circlesCollectionHeightConstraint: NSLayoutConstraint?
    
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
        setupNotificationObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Refresh stats when returning to profile page
        if let userId = self.user?.id {
            fetchUserStats(userId: userId)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        profileImageView.layer.borderColor = UIColor.separator.cgColor
        editProfileButton.layer.borderColor = UIColor.separator.cgColor
        shareProfileButton.layer.borderColor = UIColor.separator.cgColor
        suggestedButton.layer.borderColor = UIColor.separator.cgColor
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
        profileHeaderView.addSubview(usernameLabel)
        profileHeaderView.addSubview(profileImageView)
        profileHeaderView.addSubview(statsContainer)
        statsContainer.addSubview(circlesStatView)
        statsContainer.addSubview(placesStatView)
        statsContainer.addSubview(connectionsStatView)
        profileHeaderView.addSubview(bioLabel)
        profileHeaderView.addSubview(buttonsContainer)
        buttonsContainer.addSubview(editProfileButton)
        buttonsContainer.addSubview(shareProfileButton)
        buttonsContainer.addSubview(suggestedButton)
        
        contentView.addSubview(separatorLine)
        contentView.addSubview(circlesHeaderView)
        circlesHeaderView.addSubview(circlesHeaderLabel)
        contentView.addSubview(circlesCollectionView)
        contentView.addSubview(logoutButton)
        contentView.addSubview(versionLabel)
        
        // Add floating add button last so it's on top
        view.addSubview(addCircleButton)
        
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
            profileHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            profileHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Username at top
            usernameLabel.topAnchor.constraint(equalTo: profileHeaderView.topAnchor, constant: Constants.Spacing.medium),
            usernameLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            usernameLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Profile image view (Instagram style - smaller, on the left)
            profileImageView.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            profileImageView.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            profileImageView.widthAnchor.constraint(equalToConstant: 90),
            profileImageView.heightAnchor.constraint(equalToConstant: 90),
            
            // Stats container (to the right of profile image)
            statsContainer.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor),
            statsContainer.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: Constants.Spacing.large),
            statsContainer.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            statsContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Stats views (evenly distributed)
            circlesStatView.leadingAnchor.constraint(equalTo: statsContainer.leadingAnchor),
            circlesStatView.topAnchor.constraint(equalTo: statsContainer.topAnchor),
            circlesStatView.bottomAnchor.constraint(equalTo: statsContainer.bottomAnchor),
            circlesStatView.widthAnchor.constraint(equalTo: statsContainer.widthAnchor, multiplier: 0.33),
            
            placesStatView.centerXAnchor.constraint(equalTo: statsContainer.centerXAnchor),
            placesStatView.topAnchor.constraint(equalTo: statsContainer.topAnchor),
            placesStatView.bottomAnchor.constraint(equalTo: statsContainer.bottomAnchor),
            placesStatView.widthAnchor.constraint(equalTo: statsContainer.widthAnchor, multiplier: 0.33),
            
            connectionsStatView.trailingAnchor.constraint(equalTo: statsContainer.trailingAnchor),
            connectionsStatView.topAnchor.constraint(equalTo: statsContainer.topAnchor),
            connectionsStatView.bottomAnchor.constraint(equalTo: statsContainer.bottomAnchor),
            connectionsStatView.widthAnchor.constraint(equalTo: statsContainer.widthAnchor, multiplier: 0.33),
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.medium),
            bioLabel.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            bioLabel.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Buttons container
            buttonsContainer.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: Constants.Spacing.medium),
            buttonsContainer.leadingAnchor.constraint(equalTo: profileHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            buttonsContainer.trailingAnchor.constraint(equalTo: profileHeaderView.trailingAnchor, constant: -Constants.Spacing.medium),
            buttonsContainer.heightAnchor.constraint(equalToConstant: 30),
            buttonsContainer.bottomAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: -Constants.Spacing.medium),
            
            // Edit profile button
            editProfileButton.leadingAnchor.constraint(equalTo: buttonsContainer.leadingAnchor),
            editProfileButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            editProfileButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            editProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.44),
            
            // Share profile button
            shareProfileButton.leadingAnchor.constraint(equalTo: editProfileButton.trailingAnchor, constant: 6),
            shareProfileButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            shareProfileButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            shareProfileButton.widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor, multiplier: 0.44),
            
            // Suggested button
            suggestedButton.trailingAnchor.constraint(equalTo: buttonsContainer.trailingAnchor),
            suggestedButton.topAnchor.constraint(equalTo: buttonsContainer.topAnchor),
            suggestedButton.bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
            suggestedButton.widthAnchor.constraint(equalToConstant: 30),
            
            // Separator line
            separatorLine.topAnchor.constraint(equalTo: profileHeaderView.bottomAnchor, constant: Constants.Spacing.medium),
            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),
            
            // Circles header
            circlesHeaderView.topAnchor.constraint(equalTo: separatorLine.bottomAnchor),
            circlesHeaderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesHeaderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            circlesHeaderView.heightAnchor.constraint(equalToConstant: 0), // Hide header for Instagram style
            
            circlesHeaderLabel.centerYAnchor.constraint(equalTo: circlesHeaderView.centerYAnchor),
            circlesHeaderLabel.leadingAnchor.constraint(equalTo: circlesHeaderView.leadingAnchor, constant: Constants.Spacing.medium),
            
            // Floating add button
            addCircleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            addCircleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            addCircleButton.widthAnchor.constraint(equalToConstant: 50),
            addCircleButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Circles collection view
            circlesCollectionView.topAnchor.constraint(equalTo: circlesHeaderView.bottomAnchor),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Logout button
            logoutButton.topAnchor.constraint(equalTo: circlesCollectionView.bottomAnchor, constant: Constants.Spacing.xlarge),
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
        
        // Create height constraint for collection view
        circlesCollectionHeightConstraint = circlesCollectionView.heightAnchor.constraint(equalToConstant: 200)
        circlesCollectionHeightConstraint?.isActive = true
        
        // Setup collection view
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        
        // Enable drag and drop for reordering
        circlesCollectionView.dragDelegate = self
        circlesCollectionView.dropDelegate = self
        circlesCollectionView.dragInteractionEnabled = true
    }
    
    private func setupActions() {
        editProfileButton.addTarget(self, action: #selector(editProfileButtonTapped), for: .touchUpInside)
        shareProfileButton.addTarget(self, action: #selector(shareProfileButtonTapped), for: .touchUpInside)
        suggestedButton.addTarget(self, action: #selector(suggestedButtonTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        addCircleButton.addTarget(self, action: #selector(addCircleButtonTapped), for: .touchUpInside)
        
        // Apply initial appearance
        updateAppearance()
    }
    
    // MARK: - Actions
    @objc private func editProfileButtonTapped() {
        let editProfileVC = EditProfileViewController()
        navigationController?.pushViewController(editProfileVC, animated: true)
    }
    
    @objc private func shareProfileButtonTapped() {
        // Share profile functionality
        guard let user = user else { return }
        
        let shareText = "Check out my Circles profile: @\(user.displayName)"
        let activityController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        // For iPad
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = shareProfileButton
            popover.sourceRect = shareProfileButton.bounds
        }
        
        present(activityController, animated: true)
    }
    
    @objc private func suggestedButtonTapped() {
        // Navigate to suggested connections
        let suggestionsVC = SuggestionsViewController()
        navigationController?.pushViewController(suggestionsVC, animated: true)
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
    
    @objc private func addCircleButtonTapped() {
        let createCircleVC = CreateCircleViewController()
        createCircleVC.delegate = self
        let navController = UINavigationController(rootViewController: createCircleVC)
        present(navController, animated: true)
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
        
        // Display username at the top
        usernameLabel.text = user.displayName
        
        // Combine full name and bio like Instagram
        var bioText = ""
        if let firstName = user.firstName, let lastName = user.lastName {
            bioText = "\(firstName) \(lastName)"
        } else if let firstName = user.firstName {
            bioText = firstName
        } else if let lastName = user.lastName {
            bioText = lastName
        }
        
        if let bio = user.bio, !bio.isEmpty {
            if !bioText.isEmpty {
                bioText += "\n\(bio)"
            } else {
                bioText = bio
            }
        }
        
        bioLabel.text = bioText.isEmpty ? nil : bioText
        
        // Show/hide buttons based on whether this is the current user
        let isCurrentUser = user.id == AuthService.shared.getUserId()
        editProfileButton.isHidden = !isCurrentUser
        shareProfileButton.isHidden = !isCurrentUser
        suggestedButton.isHidden = !isCurrentUser
    }
    
    private func fetchUserStats(userId: String) {
        // For current user, fetch their circles
        if userId == AuthService.shared.getUserId() {
            // Fetch circles
            CircleService.shared.fetchUserCircles { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let circles):
                        self?.circles = circles
                        print("🔍 ProfileViewController - Fetched \(circles.count) circles")
                        
                        // Calculate total places from the same fetch
                        var totalPlaces = 0
                        for circle in circles {
                            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
                            totalPlaces += placeCount
                            print("   Circle '\(circle.name)': placesCount=\(circle.placesCount ?? -1), places array=\(circle.places?.count ?? 0)")
                        }
                        
                        // Update both stats
                        self?.circlesStatView.configure(number: "\(circles.count)", title: "Circles")
                        self?.placesStatView.configure(number: "\(totalPlaces)", title: "Places")
                        print("   Total places calculated: \(totalPlaces)")
                        
                        self?.circlesCollectionView.reloadData()
                        self?.updateCollectionViewHeight()
                    case .failure:
                        self?.circles = []
                        self?.circlesStatView.configure(number: "0", title: "Circles")
                        self?.placesStatView.configure(number: "0", title: "Places")
                        self?.circlesCollectionView.reloadData()
                        self?.updateCollectionViewHeight()
                    }
                }
            }
            
            // Fetch connections count
            let connectionsCount = NetworkManager.shared.connections.count
            print("🔍 ProfileViewController - Connections count: \(connectionsCount)")
            connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
        } else {
            // For other users, show default stats
            // In a real app, you might have an endpoint to fetch public stats
            circlesStatView.configure(number: "0", title: "Circles")
            placesStatView.configure(number: "0", title: "Places")
            connectionsStatView.configure(number: "0", title: "Connections")
        }
    }
    
    private func displayDefaultProfile() {
        // Fallback default display
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = Constants.Colors.primary
        
        usernameLabel.text = "User"
        bioLabel.text = "No bio available"
        
        circlesStatView.configure(number: "0", title: "Circles")
        placesStatView.configure(number: "0", title: "Places")
        connectionsStatView.configure(number: "0", title: "Connections")
    }
    
    private func displayAppVersion() {
        // Get app version from Info.plist
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        versionLabel.text = "Version \(appVersion) (\(buildNumber))"
    }
    
    private func setupNotificationObservers() {
        // Listen for circle deletion notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCircleDeleted(_:)),
            name: .circleDeleted,
            object: nil
        )
        
        // Listen for refresh circles notification (e.g., when a place is added)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefreshCircles),
            name: NSNotification.Name("RefreshCircles"),
            object: nil
        )
        
        // Listen for connections loaded notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionsLoaded),
            name: .connectionsLoaded,
            object: nil
        )
    }
    
    @objc private func handleCircleDeleted(_ notification: Notification) {
        guard let circleId = notification.userInfo?["circleId"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            // Remove the circle from our local array
            if let index = self?.circles.firstIndex(where: { $0.id == circleId }) {
                self?.circles.remove(at: index)
                self?.circlesCollectionView.reloadData()
                self?.updateCollectionViewHeight()
                
                // Update stats
                self?.circlesStatView.configure(number: "\(self?.circles.count ?? 0)", title: "Circles")
            }
        }
    }
    
    @objc private func handleRefreshCircles() {
        // Refresh user stats to get updated circle counts
        if let userId = self.user?.id {
            fetchUserStats(userId: userId)
        }
    }
    
    @objc private func handleConnectionsLoaded() {
        // Update connections count when NetworkManager finishes loading
        if let userId = self.user?.id, userId == AuthService.shared.getUserId() {
            let connectionsCount = NetworkManager.shared.connections.count
            print("🔍 ProfileViewController - Updated connections count after load: \(connectionsCount)")
            connectionsStatView.configure(number: "\(connectionsCount)", title: "Connections")
        }
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
    
    private func updateCollectionViewHeight() {
        // Calculate required height based on number of circles (3-column grid)
        let itemsPerRow: CGFloat = 3
        let spacing: CGFloat = 1
        let itemWidth = (view.bounds.width - (spacing * 2)) / itemsPerRow
        let itemHeight = itemWidth // Square cells
        
        let rows = ceil(CGFloat(circles.count) / itemsPerRow)
        let totalHeight = (rows * itemHeight) + ((rows - 1) * spacing)
        
        circlesCollectionHeightConstraint?.constant = max(totalHeight, 100) // Minimum height
        
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - UICollectionViewDataSource
extension ProfileViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return circles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as? CircleCell else {
            return UICollectionViewCell()
        }
        
        let circle = circles[indexPath.item]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let circle = circles[indexPath.item]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let circle = circles[indexPath.item]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let editAction = UIAction(
                title: "Edit Circle",
                image: UIImage(systemName: "pencil")
            ) { _ in
                self?.editCircle(circle)
            }
            
            let shareAction = UIAction(
                title: "Share Circle",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                self?.shareCircle(circle, from: indexPath)
            }
            
            let deleteAction = UIAction(
                title: "Delete Circle",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.deleteCircle(circle, at: indexPath)
            }
            
            return UIMenu(title: circle.name, children: [editAction, shareAction, deleteAction])
        }
    }
    
    private func editCircle(_ circle: Circle) {
        let editVC = EditCircleViewController(circle: circle)
        editVC.delegate = self
        navigationController?.pushViewController(editVC, animated: true)
    }
    
    private func shareCircle(_ circle: Circle, from indexPath: IndexPath) {
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
        
        // Add deep link
        shareText += "\n\n📱 Open in Circles: circles://circle/\(circle.id)"
        shareText += "\n🔗 Get Circles App: https://testflight.apple.com/join/n1sBRMG3"
        shareText += "\n\nJoin me on Circles!"
        
        let activityItems: [Any] = [shareText]
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad - set the source view for the popover
        if let popover = activityViewController.popoverPresentationController,
           let cell = circlesCollectionView.cellForItem(at: indexPath) {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        
        present(activityViewController, animated: true)
    }
    
    private func deleteCircle(_ circle: Circle, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Circle",
            message: "Are you sure you want to delete '\(circle.name)'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            CircleService.shared.deleteCircle(id: circle.id) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.didDeleteCircle(circle.id)
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to delete circle: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension ProfileViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Instagram-style 3-column grid
        let spacing: CGFloat = 1
        let numberOfColumns: CGFloat = 3
        let totalSpacing = spacing * (numberOfColumns - 1)
        let itemWidth = (collectionView.bounds.width - totalSpacing) / numberOfColumns
        let itemHeight = itemWidth // Square cells
        return CGSize(width: itemWidth, height: itemHeight)
    }
}

// MARK: - CreateCircleDelegate
extension ProfileViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        circles.insert(circle, at: 0)
        circlesCollectionView.reloadData()
        updateCollectionViewHeight()
        
        // Update stats
        circlesStatView.configure(number: "\(circles.count)", title: "Circles")
    }
}

// MARK: - EditCircleDelegate
extension ProfileViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            circlesCollectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            circlesCollectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            updateCollectionViewHeight()
            
            // Update stats
            circlesStatView.configure(number: "\(circles.count)", title: "Circles")
        }
    }
}

// MARK: - UICollectionViewDragDelegate
extension ProfileViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let circle = circles[indexPath.item]
        let itemProvider = NSItemProvider(object: circle.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = circle
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate
extension ProfileViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if collectionView.hasActiveDrag {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UICollectionViewDropProposal(operation: .forbidden)
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        var destinationIndexPath: IndexPath
        
        if let indexPath = coordinator.destinationIndexPath {
            destinationIndexPath = indexPath
        } else {
            let row = collectionView.numberOfItems(inSection: 0)
            destinationIndexPath = IndexPath(item: row - 1, section: 0)
        }
        
        if coordinator.proposal.operation == .move {
            self.reorderItems(coordinator: coordinator, destinationIndexPath: destinationIndexPath, collectionView: collectionView)
        }
    }
    
    private func reorderItems(coordinator: UICollectionViewDropCoordinator, destinationIndexPath: IndexPath, collectionView: UICollectionView) {
        if let item = coordinator.items.first,
           let sourceIndexPath = item.sourceIndexPath {
            
            collectionView.performBatchUpdates({
                // Update the data model
                let movedCircle = circles.remove(at: sourceIndexPath.item)
                circles.insert(movedCircle, at: destinationIndexPath.item)
                
                // Update the collection view
                collectionView.deleteItems(at: [sourceIndexPath])
                collectionView.insertItems(at: [destinationIndexPath])
            }, completion: { [weak self] _ in
                // Save the new order to the backend
                self?.saveCircleOrder()
            })
            
            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
        }
    }
    
    private func saveCircleOrder() {
        // Extract the circle IDs in their new order
        let circleIds = circles.map { $0.id }
        
        // Call the API to save the new order
        UserService.shared.reorderCircles(circleIds: circleIds) { [weak self] error in
            if let error = error {
                print("Failed to save circle order: \(error)")
                // Optionally reload circles to restore original order
                self?.loadUserCircles()
            } else {
                print("Circle order saved successfully")
            }
        }
    }
    
    private func loadUserCircles() {
        guard let userId = user?.id else { return }
        
        // Fetch circles (same logic as in fetchUserStats)
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    self?.circles = circles
                    self?.circlesStatView.configure(number: "\(circles.count)", title: "Circles")
                    self?.circlesCollectionView.reloadData()
                    self?.updateCollectionViewHeight()
                case .failure:
                    self?.circles = []
                    self?.circlesStatView.configure(number: "0", title: "Circles")
                    self?.circlesCollectionView.reloadData()
                    self?.updateCollectionViewHeight()
                }
            }
        }
    }
}

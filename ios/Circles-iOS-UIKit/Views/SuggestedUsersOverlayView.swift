import UIKit

protocol SuggestedUsersOverlayViewDelegate: AnyObject {
    func didSelectUser(_ user: User)
    func didTapExploreNetwork()
    func didTapImportContacts()
    func didDismissOverlay()
    func didTapNext(selectedUsers: [User])
    func didTapSkip()
}

class SuggestedUsersOverlayView: UIView, UIGestureRecognizerDelegate {
    
    // MARK: - Properties
    weak var delegate: SuggestedUsersOverlayViewDelegate?
    private var suggestedUsers: [User] = []
    private var userButtons: [UIButton] = []
    private let maxVisibleUsers = 8
    private var selectedUserIds: Set<String> = []
    private var clickedUserIds: Set<String> = []
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Discover Great Places"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Follow users with the best recommendations"
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap on profiles to follow and connect"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let counterLabel: UILabel = {
        let label = UILabel()
        label.text = "Select at least 1 connection to continue"
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circleContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var exploreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "person.2.fill"), for: .normal)
        button.setTitle("Explore Network", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = Constants.Colors.primary
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 25
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(exploreButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var importContactsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "person.crop.circle.badge.plus"), for: .normal)
        button.setTitle("Import Contacts", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .clear
        button.tintColor = Constants.Colors.primary
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.layer.borderWidth = 2
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.layer.cornerRadius = 25
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(importContactsButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let buttonContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var nextButton: UIButton = {
        let button = UIButton.primaryButton(title: "Next")
        button.isEnabled = false
        button.alpha = 0.5
        button.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(Constants.Colors.secondaryLabel, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Constants.Colors.primary
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        alpha = 0
        
        addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(instructionLabel)
        containerView.addSubview(counterLabel)
        containerView.addSubview(circleContainerView)
        containerView.addSubview(closeButton)
        containerView.addSubview(loadingIndicator)
        containerView.addSubview(importContactsButton)
        containerView.addSubview(buttonContainer)
        buttonContainer.addSubview(nextButton)
        buttonContainer.addSubview(skipButton)
        
        // Place explore button in center of circle
        circleContainerView.addSubview(exploreButton)
        
        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.9),
            containerView.heightAnchor.constraint(equalToConstant: 620),
            
            // Close button
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Counter label
            counterLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 4),
            counterLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            counterLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Circle container
            circleContainerView.topAnchor.constraint(equalTo: counterLabel.bottomAnchor, constant: 20),
            circleContainerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            circleContainerView.widthAnchor.constraint(equalToConstant: 300),
            circleContainerView.heightAnchor.constraint(equalToConstant: 300),
            
            // Explore button (center of circle)
            exploreButton.centerXAnchor.constraint(equalTo: circleContainerView.centerXAnchor),
            exploreButton.centerYAnchor.constraint(equalTo: circleContainerView.centerYAnchor),
            exploreButton.widthAnchor.constraint(equalToConstant: 180),
            exploreButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: circleContainerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: circleContainerView.centerYAnchor),
            
            // Import contacts button
            importContactsButton.topAnchor.constraint(equalTo: circleContainerView.bottomAnchor, constant: 24),
            importContactsButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            importContactsButton.widthAnchor.constraint(equalToConstant: 180),
            importContactsButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Button container
            buttonContainer.topAnchor.constraint(equalTo: importContactsButton.bottomAnchor, constant: 16),
            buttonContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            buttonContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 50),
            
            // Next button
            nextButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            nextButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            nextButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            nextButton.widthAnchor.constraint(equalTo: buttonContainer.widthAnchor, multiplier: 0.7),
            
            // Skip button
            skipButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            skipButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor)
        ])
    }
    
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to dismiss when tapping outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Public Methods
    func show(in parentView: UIView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            parentView.addSubview(self)
            self.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                self.topAnchor.constraint(equalTo: parentView.topAnchor),
                self.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                self.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                self.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
            ])
            
            // Load suggested users
            self.loadSuggestedUsers()
            
            // Animate in
            UIView.animate(withDuration: 0.3) {
                self.alpha = 1
            }
        }
    }
    
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0.3, animations: {
                self?.alpha = 0
            }) { _ in
                self?.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadSuggestedUsers() {
        loadingIndicator.startAnimating()
        exploreButton.isHidden = true
        
        ContactsService.shared.fetchSuggestedUsers(limit: maxVisibleUsers) { [weak self] result in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let users):
                    self?.suggestedUsers = users
                    self?.createUserButtons()
                    self?.exploreButton.isHidden = false
                    
                case .failure(let error):
                    Logger.error("Failed to load suggested users: \(error)")
                    self?.exploreButton.isHidden = false
                }
            }
        }
    }
    
    // MARK: - User Buttons
    private func createUserButtons() {
        // Clear existing buttons
        userButtons.forEach { $0.removeFromSuperview() }
        userButtons.removeAll()
        
        // Don't create buttons if no users
        guard !suggestedUsers.isEmpty else {
            Logger.info("No suggested users to display")
            return
        }
        
        let radius: CGFloat = 120 // Distance from center
        let angleStep = (2 * CGFloat.pi) / CGFloat(min(suggestedUsers.count, maxVisibleUsers))
        
        for (index, user) in suggestedUsers.prefix(maxVisibleUsers).enumerated() {
            let button = createUserButton(for: user)
            userButtons.append(button)
            circleContainerView.addSubview(button)
            
            // Position in circle
            let angle = angleStep * CGFloat(index) - CGFloat.pi / 2 // Start from top
            let x = cos(angle) * radius
            let y = sin(angle) * radius
            
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: circleContainerView.centerXAnchor, constant: x),
                button.centerYAnchor.constraint(equalTo: circleContainerView.centerYAnchor, constant: y),
                button.widthAnchor.constraint(equalToConstant: 70),
                button.heightAnchor.constraint(equalToConstant: 90)
            ])
            
            // Animate in with delay
            button.alpha = 0
            button.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            
            UIView.animate(withDuration: 0.3, delay: Double(index) * 0.05, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [], animations: {
                button.alpha = 1
                button.transform = .identity
            }) { _ in
                // Add subtle pulse animation to draw attention
                self.addPulseAnimation(to: button)
            }
        }
    }
    
    private func createUserButton(for user: User) -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = suggestedUsers.firstIndex(where: { $0.id == user.id }) ?? 0
        
        // Container view for profile image and label
        let containerView = UIView()
        containerView.isUserInteractionEnabled = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(containerView)
        
        // Profile image with border
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 30
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = Constants.Colors.primary.withAlphaComponent(0.3).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        
        // Load profile image
        if let urlString = user.profilePicture {
            ImageService.shared.loadImage(from: urlString) { image in
                DispatchQueue.main.async {
                    imageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        imageView.tintColor = Constants.Colors.secondaryLabel
                    }
                }
            }
        } else {
            imageView.image = UIImage(systemName: "person.circle.fill")
            imageView.tintColor = Constants.Colors.secondaryLabel
        }
        
        // Name label
        let nameLabel = UILabel()
        nameLabel.text = user.displayName
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(nameLabel)
        
        // Places count badge
        if let placesCount = user.placesCount, placesCount > 0 {
            let badgeView = UIView()
            badgeView.backgroundColor = Constants.Colors.primary
            badgeView.layer.cornerRadius = 10
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(badgeView)
            
            let badgeLabel = UILabel()
            badgeLabel.text = "\(placesCount)"
            badgeLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeView.addSubview(badgeLabel)
            
            NSLayoutConstraint.activate([
                badgeView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -5),
                badgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
                badgeView.heightAnchor.constraint(equalToConstant: 20),
                
                badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
                badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
                badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: 4),
                badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -4)
            ])
        }
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: button.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60),
            
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        button.addTarget(self, action: #selector(userButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    // MARK: - Actions
    @objc private func userButtonTapped(_ sender: UIButton) {
        guard sender.tag < suggestedUsers.count else { return }
        let user = suggestedUsers[sender.tag]
        
        // Check if already clicked
        guard !clickedUserIds.contains(user.id) else { return }
        
        // Animate button press
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = .identity
            }
        }
        
        // Mark as clicked
        clickedUserIds.insert(user.id)
        selectedUserIds.insert(user.id)
        
        // Update UI
        updateCounterLabel()
        updateNextButtonState()
        
        // Show persistent checkmark
        showPersistentCheckmark(for: sender)
        
        // Follow user and send connection request
        APIService.shared.request(
            endpoint: "users/\(user.id)/follow",
            method: .post,
            body: [:]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                // Send connection request
                NetworkManager.shared.sendConnectionRequest(to: user.id) { error in
                    if error == nil {
                        // Connection request sent successfully
                    }
                }
            case .failure:
                // Handle error if needed
                break
            }
        }
        
        delegate?.didSelectUser(user)
    }
    
    @objc private func exploreButtonTapped() {
        delegate?.didTapExploreNetwork()
        dismiss()
    }
    
    @objc private func importContactsButtonTapped() {
        delegate?.didTapImportContacts()
        dismiss()
    }
    
    @objc private func nextButtonTapped() {
        let selectedUsers = suggestedUsers.filter { selectedUserIds.contains($0.id) }
        delegate?.didTapNext(selectedUsers: selectedUsers)
        dismiss()
    }
    
    @objc private func skipButtonTapped() {
        delegate?.didTapSkip()
        dismiss()
    }
    
    @objc private func closeButtonTapped() {
        delegate?.didDismissOverlay()
        dismiss()
    }
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if !containerView.frame.contains(location) {
            delegate?.didDismissOverlay()
            dismiss()
        }
    }
    
    // MARK: - Animations
    private func addPulseAnimation(to button: UIButton) {
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.duration = 1.5
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.05
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        button.layer.add(pulseAnimation, forKey: "pulse")
    }
    
    // MARK: - UI Updates
    private func updateCounterLabel() {
        let count = selectedUserIds.count
        if count == 0 {
            counterLabel.text = "Select at least 1 connection to continue"
            counterLabel.textColor = Constants.Colors.secondaryLabel
        } else {
            counterLabel.text = "\(count) of \(suggestedUsers.count) selected"
            counterLabel.textColor = Constants.Colors.primary
        }
    }
    
    private func updateNextButtonState() {
        let hasSelection = !selectedUserIds.isEmpty
        nextButton.isEnabled = hasSelection
        UIView.animate(withDuration: 0.2) {
            self.nextButton.alpha = hasSelection ? 1.0 : 0.5
        }
    }
    
    // MARK: - Feedback
    private func showPersistentCheckmark(for button: UIButton) {
        // Add persistent checkmark overlay
        let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmarkView.tintColor = Constants.Colors.success
        checkmarkView.backgroundColor = .white
        checkmarkView.layer.cornerRadius = 15
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.tag = 999 // Tag to identify checkmark views
        button.addSubview(checkmarkView)
        
        NSLayoutConstraint.activate([
            checkmarkView.topAnchor.constraint(equalTo: button.topAnchor, constant: -5),
            checkmarkView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 5),
            checkmarkView.widthAnchor.constraint(equalToConstant: 30),
            checkmarkView.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Animate in
        checkmarkView.alpha = 0
        checkmarkView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [], animations: {
            checkmarkView.alpha = 1
            checkmarkView.transform = .identity
        }, completion: nil)
    }
    
    private func showSuccessFeedback(for button: UIButton) {
        // This method is no longer used but kept for compatibility
        // The persistent checkmark is shown instead
    }
}

// MARK: - UIGestureRecognizerDelegate
extension SuggestedUsersOverlayView {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle taps on the container view
        let location = touch.location(in: self)
        return !containerView.frame.contains(location)
    }
}
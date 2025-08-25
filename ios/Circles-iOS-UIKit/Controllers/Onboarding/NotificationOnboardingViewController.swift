import UIKit
import UserNotifications

class NotificationOnboardingViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let illustrationImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "bell.badge.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Stay Connected"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Never miss updates from your network"
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Feature cards
    private lazy var messagesCard = createFeatureCard(
        icon: "message.fill",
        title: "Messages & Suggestions",
        description: "Get notified when friends send you messages or suggest places"
    )
    
    private lazy var placesCard = createFeatureCard(
        icon: "mappin.circle.fill",
        title: "New Places",
        description: "Discover when your network adds new favorite spots"
    )
    
    private lazy var activityCard = createFeatureCard(
        icon: "heart.fill",
        title: "Activity Updates",
        description: "See when people like or comment on your places"
    )
    
    private lazy var summaryCard = createFeatureCard(
        icon: "newspaper.fill",
        title: "Daily Summary",
        description: "Get a daily digest of everything happening in your network"
    )
    
    private lazy var enableButton = UIButton.primaryButton(title: "Enable Notifications")
    private lazy var skipButton = UIButton.secondaryButton(title: "Maybe Later")
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Properties
    var onCompletion: (() -> Void)?
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Hide navigation bar for cleaner onboarding experience
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore navigation bar
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add container
        view.addSubview(containerView)
        
        // Add illustration
        containerView.addSubview(illustrationImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        
        // Add feature cards to stack
        stackView.addArrangedSubview(messagesCard)
        stackView.addArrangedSubview(placesCard)
        stackView.addArrangedSubview(activityCard)
        stackView.addArrangedSubview(summaryCard)
        
        containerView.addSubview(stackView)
        
        // Add buttons
        enableButton.addTarget(self, action: #selector(enableNotifications), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipNotifications), for: .touchUpInside)
        
        containerView.addSubview(enableButton)
        containerView.addSubview(skipButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Illustration
            illustrationImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            illustrationImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            illustrationImageView.widthAnchor.constraint(equalToConstant: 80),
            illustrationImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: illustrationImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Stack view
            stackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Enable button
            enableButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            enableButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            enableButton.bottomAnchor.constraint(equalTo: skipButton.topAnchor, constant: -12),
            
            // Skip button
            skipButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            skipButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -40)
        ])
    }
    
    private func createFeatureCard(icon: String, title: String, description: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = Constants.Colors.primary
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        card.addSubview(iconImageView)
        card.addSubview(titleLabel)
        card.addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            
            iconImageView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        
        return card
    }
    
    // MARK: - Actions
    @objc private func enableNotifications() {
        NotificationService.shared.requestNotificationPermissions { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notifications enabled during onboarding")
                    // Register for remote notifications
                    UIApplication.shared.registerForRemoteNotifications()
                    self?.showSuccess("Notifications enabled! You'll stay connected with your network.")
                } else {
                    print("❌ User denied notifications during onboarding")
                    self?.showNotificationDeniedAlert()
                }
                
                // Record that we've shown onboarding
                UserDefaults.standard.set(true, forKey: "hasShownNotificationOnboarding")
                
                // Complete onboarding after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.completeOnboarding()
                }
            }
        }
    }
    
    @objc private func skipNotifications() {
        print("⏭️ User skipped notifications during onboarding")
        
        // Record skip
        UserDefaults.standard.set(true, forKey: "hasShownNotificationOnboarding")
        UserDefaults.standard.set(Date(), forKey: "lastNotificationOnboardingSkip")
        
        // Show reminder
        AlertPresenter.showSuccess(
            title: "You can enable notifications anytime",
            message: "Go to your Profile → Settings → Notifications to stay connected with your network.",
            from: self
        ) { [weak self] in
            self?.completeOnboarding()
        }
    }
    
    private func showNotificationDeniedAlert() {
        AlertPresenter.showConfirmation(
            title: "Enable Notifications in Settings",
            message: "To receive notifications, go to Settings → Circles → Notifications and turn on Allow Notifications.",
            confirmTitle: "Open Settings",
            cancelTitle: "Later",
            from: self,
            onConfirm: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }
    
    private func completeOnboarding() {
        onCompletion?()
        
        // If presented modally, dismiss
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            // If pushed, pop
            navigationController?.popViewController(animated: true)
        }
    }
}
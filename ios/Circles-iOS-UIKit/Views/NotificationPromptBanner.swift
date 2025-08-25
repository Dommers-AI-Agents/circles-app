import UIKit

class NotificationPromptBanner: UIView {
    
    // MARK: - Properties
    private var autoDismissTimer: Timer?
    private let autoDismissDelay: TimeInterval = 10.0
    private var topConstraint: NSLayoutConstraint?
    private var onEnableAction: (() -> Void)?
    private var onDismissAction: (() -> Void)?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.layer.cornerRadius = 12
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "bell.badge.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Stay Connected"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.text = "Get notified when friends add new places or send you messages"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .white.withAlphaComponent(0.9)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // New: Activity indicator for context
    private let activityBadge: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let activityLabel: UILabel = {
        let label = UILabel()
        label.text = "3"
        label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var enableButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Enable Notifications", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(enableButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Not Now", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.setTitleColor(.white.withAlphaComponent(0.9), for: .normal)
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white.withAlphaComponent(0.8)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(enableButton)
        containerView.addSubview(dismissButton)
        containerView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            // Container
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Icon
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            // Title
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            
            // Message
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            // Enable Button
            enableButton.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            enableButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
            enableButton.heightAnchor.constraint(equalToConstant: 32),
            enableButton.widthAnchor.constraint(equalToConstant: 140),
            
            // Dismiss Button
            dismissButton.leadingAnchor.constraint(equalTo: enableButton.trailingAnchor, constant: 8),
            dismissButton.centerYAnchor.constraint(equalTo: enableButton.centerYAnchor),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),
            dismissButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            // Close Button
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    // MARK: - Public Methods
    func show(in view: UIView, onEnable: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.onEnableAction = onEnable
        self.onDismissAction = onDismiss
        
        // Add to view
        view.addSubview(self)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        // Position off-screen initially
        topConstraint = topAnchor.constraint(equalTo: view.topAnchor, constant: -200)
        topConstraint?.isActive = true
        
        view.layoutIfNeeded()
        
        // Animate in
        topConstraint?.constant = view.safeAreaInsets.top + 8
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            view.layoutIfNeeded()
        }
        
        // Start auto-dismiss timer
        startAutoDismissTimer()
    }
    
    func dismiss() {
        invalidateTimer()
        
        guard let superview = superview else { return }
        
        topConstraint?.constant = -200
        UIView.animate(withDuration: 0.3, animations: {
            superview.layoutIfNeeded()
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.onDismissAction?()
        }
    }
    
    // MARK: - Private Methods
    private func startAutoDismissTimer() {
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissDelay, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    private func invalidateTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
    
    // MARK: - Actions
    @objc private func enableButtonTapped() {
        invalidateTimer()
        onEnableAction?()
        dismiss()
    }
    
    @objc private func dismissButtonTapped() {
        dismiss()
    }
}

// MARK: - Notification Prompt Manager
class NotificationPromptManager {
    static let shared = NotificationPromptManager()
    
    private let lastPromptKey = "lastNotificationPromptDate"
    private let promptCountKey = "notificationPromptCount"
    private let dismissCountKey = "notificationDismissCount"
    private let userCreatedDateKey = "userCreatedDate"
    private var currentBanner: NotificationPromptBanner?
    
    private init() {}
    
    func checkAndPromptIfNeeded(in viewController: UIViewController, context: NotificationPromptContext) {
        // Check if notifications are already enabled
        NotificationService.shared.checkNotificationPermissions { [weak self] isEnabled in
            DispatchQueue.main.async {
                if !isEnabled && self?.shouldShowPrompt() == true {
                    self?.showPrompt(in: viewController, context: context)
                }
            }
        }
    }
    
    private func shouldShowPrompt() -> Bool {
        let defaults = UserDefaults.standard
        
        // Check if user has dismissed too many times (3 dismissals = stop prompting)
        let dismissCount = defaults.integer(forKey: dismissCountKey)
        if dismissCount >= 3 {
            return false
        }
        
        // Get smart interval based on user age
        let promptInterval = getSmartPromptInterval()
        
        // Check if we've prompted recently
        if let lastPromptDate = defaults.object(forKey: lastPromptKey) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            return daysSinceLastPrompt >= promptInterval
        }
        return true
    }
    
    private func getSmartPromptInterval() -> Int {
        let defaults = UserDefaults.standard
        
        // Get user creation date (or use current date if not set)
        let userCreatedDate = defaults.object(forKey: userCreatedDateKey) as? Date ?? Date()
        let daysSinceCreation = Calendar.current.dateComponents([.day], from: userCreatedDate, to: Date()).day ?? 0
        
        // Smart intervals:
        // First 3 days: prompt every day
        // Days 4-14: prompt every 3 days  
        // After 14 days: prompt every 14 days
        if daysSinceCreation <= 3 {
            return 1
        } else if daysSinceCreation <= 14 {
            return 3
        } else {
            return 14
        }
    }
    
    private func showPrompt(in viewController: UIViewController, context: NotificationPromptContext) {
        // Dismiss any existing banner
        currentBanner?.dismiss()
        
        // Create and show new banner
        let banner = NotificationPromptBanner()
        currentBanner = banner
        
        banner.show(in: viewController.view, onEnable: { [weak self] in
            self?.handleEnableNotifications(from: viewController)
        }, onDismiss: { [weak self] in
            self?.recordPromptShown()
        })
    }
    
    private func handleEnableNotifications(from viewController: UIViewController) {
        NotificationService.shared.requestNotificationPermissions { granted in
            if granted {
                print("✅ Notifications enabled via prompt banner")
                // Register device token if needed
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("❌ User denied notification permissions")
            }
        }
        recordPromptShown()
    }
    
    private func recordPromptShown() {
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
    }
}

// MARK: - Notification Prompt Context
enum NotificationPromptContext {
    case messages
    case connections
    case activityFeed
    case placeAdded
    
    var message: String {
        switch self {
        case .messages:
            return "Get notified when you receive new messages from your connections"
        case .connections:
            return "Get notified about new connection requests and updates"
        case .activityFeed:
            return "Stay updated when friends add new places or interact with your content"
        case .placeAdded:
            return "Get notified when your connections discover new places you might like"
        }
    }
}
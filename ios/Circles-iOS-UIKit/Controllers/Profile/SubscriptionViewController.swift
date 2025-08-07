import UIKit
import StoreKit

class SubscriptionViewController: BaseViewController {
    
    // MARK: - Properties
    private var subscriptionInfo: SubscriptionInfo?
    
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
    
    // Status card
    private let statusCard: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let statusBadge: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Your Subscription"
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let expiryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Features section
    private let featuresHeaderLabel: UILabel = {
        let label = UILabel()
        label.text = "Premium Features"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let featuresStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Action buttons
    private lazy var upgradeButton = UIButton.primaryButton(title: "Upgrade to Premium")
    private lazy var manageButton = UIButton.secondaryButton(title: "Manage Subscription")
    private lazy var restoreButton = UIButton.secondaryButton(title: "Restore Purchases")
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        updateSubscriptionDisplay()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSubscriptionStatus()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Subscription"
        
        // Add views
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(statusCard)
        statusCard.addSubview(statusBadge)
        statusCard.addSubview(statusTitleLabel)
        statusCard.addSubview(statusDescriptionLabel)
        statusCard.addSubview(expiryLabel)
        
        contentView.addSubview(featuresHeaderLabel)
        contentView.addSubview(featuresStackView)
        contentView.addSubview(upgradeButton)
        contentView.addSubview(manageButton)
        contentView.addSubview(restoreButton)
        
        // Setup features
        setupFeatures()
        
        // Actions
        upgradeButton.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)
        manageButton.addTarget(self, action: #selector(manageTapped), for: .touchUpInside)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
    }
    
    private func setupConstraints() {
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
            
            // Status card
            statusCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            statusCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Status badge
            statusBadge.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),
            statusBadge.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            statusBadge.heightAnchor.constraint(equalToConstant: 24),
            
            // Status title
            statusTitleLabel.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 12),
            statusTitleLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusTitleLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            
            // Status description
            statusDescriptionLabel.topAnchor.constraint(equalTo: statusTitleLabel.bottomAnchor, constant: 8),
            statusDescriptionLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusDescriptionLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            
            // Expiry
            expiryLabel.topAnchor.constraint(equalTo: statusDescriptionLabel.bottomAnchor, constant: 8),
            expiryLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            expiryLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            expiryLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -16),
            
            // Features header
            featuresHeaderLabel.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 32),
            featuresHeaderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            featuresHeaderLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Features stack
            featuresStackView.topAnchor.constraint(equalTo: featuresHeaderLabel.bottomAnchor, constant: 16),
            featuresStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            featuresStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Upgrade button
            upgradeButton.topAnchor.constraint(equalTo: featuresStackView.bottomAnchor, constant: 32),
            upgradeButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            upgradeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Manage button
            manageButton.topAnchor.constraint(equalTo: upgradeButton.bottomAnchor, constant: 12),
            manageButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            manageButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Restore button
            restoreButton.topAnchor.constraint(equalTo: manageButton.bottomAnchor, constant: 12),
            restoreButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            restoreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            restoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }
    
    private func setupFeatures() {
        for feature in PremiumFeatures.features {
            let featureView = createFeatureView(feature)
            featuresStackView.addArrangedSubview(featureView)
        }
    }
    
    private func createFeatureView(_ feature: PremiumFeatures.Feature) -> UIView {
        let container = UIView()
        container.backgroundColor = Constants.Colors.secondaryBackground
        container.layer.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = UIImageView()
        iconView.image = UIImage(systemName: feature.iconName)
        iconView.tintColor = Constants.Colors.primary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = feature.title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let checkmark = UIImageView()
        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = Constants.Colors.primary
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(checkmark)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56),
            
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: checkmark.leadingAnchor, constant: -12),
            
            checkmark.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            checkmark.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),
            checkmark.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Show/hide checkmark based on subscription status
        checkmark.isHidden = !SubscriptionManager.shared.isSubscribed
        
        return container
    }
    
    // MARK: - Subscription Status
    private func refreshSubscriptionStatus() {
        Task {
            await SubscriptionService.shared.updateSubscriptionStatus()
            
            DispatchQueue.main.async { [weak self] in
                self?.updateSubscriptionDisplay()
            }
        }
    }
    
    private func updateSubscriptionDisplay() {
        let status = SubscriptionManager.shared.subscriptionStatus
        subscriptionInfo = SubscriptionManager.shared.subscriptionInfo
        
        // Update status badge
        statusBadge.text = status.displayName.uppercased()
        statusBadge.backgroundColor = status.badgeColor
        
        // Update description and buttons
        switch status {
        case .none:
            statusDescriptionLabel.text = "You're on the free plan with limited features"
            expiryLabel.text = "Upgrade to unlock all features"
            upgradeButton.isHidden = false
            manageButton.isHidden = true
            
        case .trial:
            if let daysLeft = subscriptionInfo?.daysLeftInTrial {
                statusDescriptionLabel.text = "You have \(daysLeft) days left in your free trial"
                expiryLabel.text = "Enjoy unlimited access to all features"
            } else {
                statusDescriptionLabel.text = "You're in your free trial period"
                expiryLabel.text = ""
            }
            upgradeButton.isHidden = true
            manageButton.isHidden = false
            
        case .active:
            statusDescriptionLabel.text = "You have unlimited access to all features"
            if let expiryDate = subscriptionInfo?.expiryDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                expiryLabel.text = "Renews on \(formatter.string(from: expiryDate))"
            } else {
                expiryLabel.text = "Auto-renewal enabled"
            }
            upgradeButton.isHidden = true
            manageButton.isHidden = false
            
        case .expired:
            statusDescriptionLabel.text = "Your subscription has expired"
            expiryLabel.text = "Renew to regain access to premium features"
            upgradeButton.setTitle("Renew Subscription", for: .normal)
            upgradeButton.isHidden = false
            manageButton.isHidden = true
            
        case .cancelled:
            statusDescriptionLabel.text = "Your subscription has been cancelled"
            if let expiryDate = subscriptionInfo?.expiryDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                expiryLabel.text = "Access until \(formatter.string(from: expiryDate))"
            } else {
                expiryLabel.text = "Resubscribe to regain premium access"
            }
            upgradeButton.setTitle("Resubscribe", for: .normal)
            upgradeButton.isHidden = false
            manageButton.isHidden = false
        }
        
        // Update feature checkmarks
        for (index, _) in PremiumFeatures.features.enumerated() {
            if let featureView = featuresStackView.arrangedSubviews[safe: index],
               let checkmark = featureView.subviews.last as? UIImageView {
                checkmark.isHidden = !status.isActive
            }
        }
    }
    
    // MARK: - Actions
    @objc private func upgradeTapped() {
        SubscriptionManager.shared.showPaywall(from: self, reason: .generalUpgrade)
    }
    
    @objc private func manageTapped() {
        // Open App Store subscription management
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func restoreTapped() {
        showLoadingState()
        restoreButton.isEnabled = false
        
        Task {
            await SubscriptionManager.shared.restorePurchases(from: self)
            
            DispatchQueue.main.async { [weak self] in
                self?.hideLoadingState()
                self?.restoreButton.isEnabled = true
                self?.updateSubscriptionDisplay()
            }
        }
    }
}

// MARK: - Array Extension for Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
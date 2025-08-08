import UIKit
import StoreKit

class PaywallViewController: BaseViewController {
    
    // MARK: - Properties
    private var products: [SubscriptionProduct] = []
    private var selectedProduct: SubscriptionProduct?
    private let reason: SubscriptionManager.PaywallReason
    private let promotedProductId: String?
    
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
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "crown.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Unlock Circles Premium"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = Constants.Colors.label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Get unlimited access to all features"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Features section
    private let featuresStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Subscription options
    private let optionsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Action buttons
    private lazy var purchaseButton = UIButton.primaryButton(title: "Start Free Trial")
    private lazy var restoreButton = UIButton.secondaryButton(title: "Restore Purchases")
    
    private let termsLabel: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        let text = "By subscribing, you agree to our Terms of Service and Privacy Policy. Cancel anytime in Settings."
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: text.count))
        attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: 0, length: text.count))
        
        textView.attributedText = attributedString
        textView.textAlignment = .center
        
        return textView
    }()
    
    // MARK: - Init
    init(reason: SubscriptionManager.PaywallReason, promotedProductId: String? = nil) {
        self.reason = reason
        self.promotedProductId = promotedProductId
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        loadProducts()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Add views
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(closeButton)
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(featuresStackView)
        contentView.addSubview(optionsStackView)
        contentView.addSubview(purchaseButton)
        contentView.addSubview(restoreButton)
        contentView.addSubview(termsLabel)
        
        // Setup features
        setupFeatures()
        
        // Actions
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        
        // Customize based on reason
        customizeForReason()
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
            
            // Close button
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Icon
            iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            
            // Features
            featuresStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            featuresStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            featuresStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            
            // Options
            optionsStackView.topAnchor.constraint(equalTo: featuresStackView.bottomAnchor, constant: 32),
            optionsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            optionsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Purchase button
            purchaseButton.topAnchor.constraint(equalTo: optionsStackView.bottomAnchor, constant: 24),
            purchaseButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            purchaseButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Restore button
            restoreButton.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 12),
            restoreButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            restoreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            // Terms
            termsLabel.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 16),
            termsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            termsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            termsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }
    
    private func setupFeatures() {
        let topFeatures = Array(PremiumFeatures.features.prefix(3))
        for feature in topFeatures {
            let featureView = createCompactFeatureView(feature)
            featuresStackView.addArrangedSubview(featureView)
        }
    }
    
    private func createCompactFeatureView(_ feature: PremiumFeatures.Feature) -> UIView {
        let container = UIView()
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
        
        let descriptionLabel = UILabel()
        descriptionLabel.text = feature.description
        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = Constants.Colors.secondaryLabel
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    private func customizeForReason() {
        switch reason {
        case .circleLimit:
            titleLabel.text = "Create More Circles"
            subtitleLabel.text = "You've reached the free limit of \(PremiumFeatures.maxFreeCircles) circles"
        case .placeLimit:
            titleLabel.text = "Add More Places"
            subtitleLabel.text = "You've reached the free limit of \(PremiumFeatures.maxFreePlacesPerCircle) places per circle"
        case .exportFeature:
            titleLabel.text = "Premium Feature"
            subtitleLabel.text = "Export and advanced sharing features are available to Premium members"
        case .generalUpgrade:
            titleLabel.text = "Unlock Circles Premium"
            subtitleLabel.text = "Get unlimited access to all features"
        }
    }
    
    // MARK: - Products
    private func loadProducts() {
        showLoadingState()
        
        Task {
            do {
                try await SubscriptionService.shared.loadProducts()
                
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    self?.products = SubscriptionService.shared.products
                    self?.setupSubscriptionOptions()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    self?.showError(error)
                }
            }
        }
    }
    
    private func setupSubscriptionOptions() {
        optionsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if products.isEmpty {
            // Show message when no products are available
            let messageLabel = UILabel()
            messageLabel.text = "Subscription plans are being set up.\nPlease check back later."
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 0
            messageLabel.font = UIFont.systemFont(ofSize: 16)
            messageLabel.textColor = Constants.Colors.secondaryLabel
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            
            let container = UIView()
            container.backgroundColor = Constants.Colors.secondaryBackground
            container.layer.cornerRadius = 12
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(messageLabel)
            
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
                messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                messageLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
                container.heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
            ])
            
            optionsStackView.addArrangedSubview(container)
            
            // Disable purchase button
            purchaseButton.isEnabled = false
            purchaseButton.alpha = 0.5
            return
        }
        
        // Enable purchase button when products are available
        purchaseButton.isEnabled = true
        purchaseButton.alpha = 1.0
        
        for product in products.sorted(by: { $0.price > $1.price }) {
            let optionView = createSubscriptionOptionView(product)
            optionsStackView.addArrangedSubview(optionView)
        }
        
        // Select promoted product if provided, otherwise annual by default
        if let promotedId = promotedProductId,
           let promotedProduct = products.first(where: { $0.id == promotedId }) {
            selectProduct(promotedProduct)
        } else if let annualProduct = products.first(where: { $0.isAnnual }) {
            selectProduct(annualProduct)
        } else if let firstProduct = products.first {
            selectProduct(firstProduct)
        }
    }
    
    private func createSubscriptionOptionView(_ product: SubscriptionProduct) -> UIView {
        let container = UIView()
        container.backgroundColor = Constants.Colors.secondaryBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 2
        container.layer.borderColor = UIColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Badge for best value
        let badgeContainer = UIView()
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        
        if let badgeText = product.badgeText {
            let badge = UILabel()
            badge.text = badgeText
            badge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = Constants.Colors.primary
            badge.textAlignment = .center
            badge.layer.cornerRadius = 4
            badge.clipsToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            
            badgeContainer.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: badgeContainer.topAnchor),
                badge.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor),
                badge.heightAnchor.constraint(equalToConstant: 20),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
            ])
        }
        
        let titleLabel = UILabel()
        titleLabel.text = product.tierName
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let priceLabel = UILabel()
        priceLabel.text = product.subscriptionDescription
        priceLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        priceLabel.textColor = Constants.Colors.label
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let detailLabel = UILabel()
        if let pricePerMonth = product.pricePerMonth, let savings = product.savingsPercentage {
            detailLabel.text = "\(pricePerMonth) • Save \(savings)%"
            detailLabel.textColor = Constants.Colors.primary
        } else {
            detailLabel.text = "Billed monthly"
            detailLabel.textColor = Constants.Colors.secondaryLabel
        }
        detailLabel.font = UIFont.systemFont(ofSize: 14)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let selectionIndicator = UIImageView()
        selectionIndicator.image = UIImage(systemName: "circle")
        selectionIndicator.tintColor = Constants.Colors.secondaryLabel
        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(badgeContainer)
        container.addSubview(titleLabel)
        container.addSubview(priceLabel)
        container.addSubview(detailLabel)
        container.addSubview(selectionIndicator)
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 88),
            
            badgeContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: -10),
            badgeContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),
            
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            
            priceLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            priceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            
            detailLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            detailLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 2),
            
            selectionIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            selectionIndicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            selectionIndicator.widthAnchor.constraint(equalToConstant: 24),
            selectionIndicator.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(optionTapped(_:)))
        container.addGestureRecognizer(tapGesture)
        container.tag = products.firstIndex(where: { $0.id == product.id }) ?? 0
        
        return container
    }
    
    @objc private func optionTapped(_ sender: UITapGestureRecognizer) {
        guard let index = sender.view?.tag,
              index < products.count else { return }
        
        selectProduct(products[index])
    }
    
    private func selectProduct(_ product: SubscriptionProduct) {
        selectedProduct = product
        
        // Update UI
        for (index, view) in optionsStackView.arrangedSubviews.enumerated() {
            let isSelected = index == products.firstIndex(where: { $0.id == product.id })
            
            if isSelected {
                view.layer.borderColor = Constants.Colors.primary.cgColor
                view.backgroundColor = Constants.Colors.secondaryBackground
                
                if let indicator = view.subviews.last as? UIImageView {
                    indicator.image = UIImage(systemName: "checkmark.circle.fill")
                    indicator.tintColor = Constants.Colors.primary
                }
            } else {
                view.layer.borderColor = UIColor.clear.cgColor
                view.backgroundColor = Constants.Colors.secondaryBackground.withAlphaComponent(0.6)
                
                if let indicator = view.subviews.last as? UIImageView {
                    indicator.image = UIImage(systemName: "circle")
                    indicator.tintColor = Constants.Colors.secondaryLabel
                }
            }
        }
        
        // Update button text
        if product.hasFreeTrial, let trialPeriod = product.freeTrialPeriod {
            purchaseButton.setTitle("Start \(trialPeriod) Free Trial", for: .normal)
        } else {
            purchaseButton.setTitle("Subscribe for \(product.displayPrice)", for: .normal)
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func purchaseTapped() {
        // Check if products are available
        if products.isEmpty {
            AlertPresenter.showError(
                title: "Subscription Unavailable",
                message: "Premium subscriptions are not available yet. Please check back later or contact support.",
                from: self
            )
            return
        }
        
        guard let product = selectedProduct else {
            AlertPresenter.showError(
                title: "No Product Selected",
                message: "Please select a subscription plan.",
                from: self
            )
            return
        }
        
        showLoadingState()
        purchaseButton.isEnabled = false
        
        Task {
            do {
                let transaction = try await SubscriptionService.shared.purchase(product)
                
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    
                    if transaction != nil {
                        AlertPresenter.showSuccess("Welcome to Circles Premium! 🎉", from: self!)
                        self?.dismiss(animated: true)
                    } else {
                        self?.purchaseButton.isEnabled = true
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    self?.purchaseButton.isEnabled = true
                    self?.showError(error)
                }
            }
        }
    }
    
    @objc private func restoreTapped() {
        showLoadingState()
        restoreButton.isEnabled = false
        
        Task {
            do {
                try await SubscriptionService.shared.restorePurchases()
                await SubscriptionService.shared.updateSubscriptionStatus()
                
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    self?.restoreButton.isEnabled = true
                    
                    if SubscriptionManager.shared.isSubscribed {
                        AlertPresenter.showSuccess("Subscription restored successfully!", from: self!)
                        self?.dismiss(animated: true)
                    } else {
                        self?.showError("No active subscription found")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.hideLoadingState()
                    self?.restoreButton.isEnabled = true
                    self?.showError(error)
                }
            }
        }
    }
}
import UIKit
import Contacts

class ContactsPermissionViewController: BaseViewController {
    
    // MARK: - Properties
    private var onPermissionGranted: (() -> Void)?
    private var onSkip: (() -> Void)?
    
    // MARK: - UI Elements
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            Constants.Colors.primary.cgColor,
            Constants.Colors.primary.withAlphaComponent(0.8).cgColor,
            UIColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0).cgColor
        ]
        layer.locations = [0.0, 0.5, 1.0]
        layer.startPoint = CGPoint(x: 0.5, y: 0.0)
        layer.endPoint = CGPoint(x: 0.5, y: 1.0)
        return layer
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "person.2.circle.fill")
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Find Friends on Circles"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Connect with friends who are already using Circles and invite others to join"
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let featuresStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles syncs contact information to help you find friends. We never store your contacts or use them for anything else."
        label.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .white.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var allowButton = UIButton.primaryButton(title: "Allow Access")
    private lazy var skipButton = UIButton.secondaryButton(title: "Skip for Now")
    
    // MARK: - BaseViewController Overrides
    override var showsLoadingIndicator: Bool { true }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFeatures()
        setupActions()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Hide navigation bar
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        // Add gradient background
        view.layer.insertSublayer(gradientLayer, at: 0)
        
        // Add container
        view.addSubview(containerView)
        
        // Add elements to container
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(featuresStackView)
        containerView.addSubview(allowButton)
        containerView.addSubview(skipButton)
        containerView.addSubview(privacyLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Container
            containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Icon
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 100),
            iconImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            // Features
            featuresStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            featuresStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            featuresStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Allow button
            allowButton.topAnchor.constraint(equalTo: featuresStackView.bottomAnchor, constant: 40),
            allowButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            allowButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            allowButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Skip button
            skipButton.topAnchor.constraint(equalTo: allowButton.bottomAnchor, constant: 12),
            skipButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            skipButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            skipButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Privacy label
            privacyLabel.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 24),
            privacyLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            privacyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            privacyLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Style buttons
        allowButton.backgroundColor = .white
        allowButton.setTitleColor(Constants.Colors.primary, for: .normal)
        
        skipButton.backgroundColor = .clear
        skipButton.setTitleColor(.white, for: .normal)
        skipButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        skipButton.layer.borderWidth = 1
    }
    
    private func setupFeatures() {
        let features = [
            ("person.2.fill", "Find friends already on Circles"),
            ("envelope.fill", "Invite contacts to join"),
            ("shield.fill", "Your privacy is protected")
        ]
        
        for (icon, text) in features {
            let featureView = createFeatureView(icon: icon, text: text)
            featuresStackView.addArrangedSubview(featureView)
        }
    }
    
    private func createFeatureView(icon: String, text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = UIImageView()
        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconView)
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Actions
    private func setupActions() {
        allowButton.addTarget(self, action: #selector(allowButtonTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
    }
    
    @objc private func allowButtonTapped() {
        let contactsService = ContactsService.shared
        
        switch contactsService.checkContactsPermission() {
        case .authorized:
            // Already have permission
            proceedWithContacts()
            
        case .denied, .restricted:
            // Show alert to go to settings
            showSettingsAlert()
            
        case .notDetermined:
            // Request permission
            contactsService.requestContactsPermission { [weak self] granted in
                if granted {
                    self?.proceedWithContacts()
                } else {
                    self?.showSettingsAlert()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func skipButtonTapped() {
        Logger.info("User skipped contacts permission")
        dismiss(animated: true) { [weak self] in
            self?.onSkip?()
        }
    }
    
    private func proceedWithContacts() {
        // Show loading
        showLoadingState()
        allowButton.isEnabled = false
        skipButton.isEnabled = false
        
        // Navigate to contacts list
        let contactsListVC = ContactsListViewController()
        contactsListVC.onComplete = { [weak self] in
            self?.dismiss(animated: true) {
                self?.onPermissionGranted?()
            }
        }
        
        navigationController?.pushViewController(contactsListVC, animated: true)
        
        // Re-enable buttons and hide loading
        DispatchQueue.main.async { [weak self] in
            self?.hideLoadingState()
            self?.allowButton.isEnabled = true
            self?.skipButton.isEnabled = true
        }
    }
    
    private func showSettingsAlert() {
        let alert = UIAlertController(
            title: "Contacts Access Required",
            message: "Please enable contacts access in Settings to find your friends on Circles.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    // MARK: - Configuration
    func configure(onPermissionGranted: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onPermissionGranted = onPermissionGranted
        self.onSkip = onSkip
    }
}
import UIKit

protocol VisitTrackingPermissionViewDelegate: AnyObject {
    func didEnableVisitTracking()
    func didDisableVisitTracking()
    func didSkipVisitTracking()
}

class VisitTrackingPermissionView: UIView {
    
    // MARK: - Properties
    weak var delegate: VisitTrackingPermissionViewDelegate?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let illustrationImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "location.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Track Your Visits Privately"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Let Circles remember places you visit so you can review them later and save your favorites to circles"
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let benefitsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var enableButton = UIButton.primaryButton(title: "Enable Visit Tracking")
    
    private lazy var notNowButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Not Now")
        button.backgroundColor = .clear
        button.layer.borderWidth = 2
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        return button
    }()
    
    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "🔒 Your visits are private and only visible to you"
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        containerView.addSubview(illustrationImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(descriptionLabel)
        containerView.addSubview(benefitsStackView)
        containerView.addSubview(enableButton)
        containerView.addSubview(notNowButton)
        containerView.addSubview(skipButton)
        containerView.addSubview(privacyLabel)
        
        // Create benefit items
        let benefits = [
            ("clock.fill", "Review visits at your convenience"),
            ("star.fill", "Save only the places you love"),
            ("lock.fill", "Complete privacy control"),
            ("xmark.circle.fill", "Disable anytime in settings")
        ]
        
        for (iconName, text) in benefits {
            let benefitView = createBenefitView(iconName: iconName, text: text)
            benefitsStackView.addArrangedSubview(benefitView)
        }
        
        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.9),
            containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 600),
            
            // Illustration
            illustrationImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 40),
            illustrationImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            illustrationImageView.widthAnchor.constraint(equalToConstant: 80),
            illustrationImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: illustrationImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            // Description
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            
            // Benefits
            benefitsStackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 32),
            benefitsStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 40),
            benefitsStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40),
            
            // Enable button
            enableButton.topAnchor.constraint(equalTo: benefitsStackView.bottomAnchor, constant: 40),
            enableButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            enableButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            enableButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Not Now button
            notNowButton.topAnchor.constraint(equalTo: enableButton.bottomAnchor, constant: 12),
            notNowButton.leadingAnchor.constraint(equalTo: enableButton.leadingAnchor),
            notNowButton.trailingAnchor.constraint(equalTo: enableButton.trailingAnchor),
            notNowButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Skip button
            skipButton.topAnchor.constraint(equalTo: notNowButton.bottomAnchor, constant: 8),
            skipButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            
            // Privacy label
            privacyLabel.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 16),
            privacyLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            privacyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            privacyLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -24)
        ])
    }
    
    private func createBenefitView(iconName: String, text: String) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let iconImageView = UIImageView(image: UIImage(systemName: iconName))
        iconImageView.tintColor = Constants.Colors.primary
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(iconImageView)
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            
            label.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        return view
    }
    
    private func setupActions() {
        enableButton.addTarget(self, action: #selector(enableButtonTapped), for: .touchUpInside)
        notNowButton.addTarget(self, action: #selector(notNowButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to dismiss when tapping outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Public Methods
    func show(in parentView: UIView) {
        parentView.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }
    
    // MARK: - Actions
    @objc private func enableButtonTapped() {
        // Enable visit tracking in settings
        VisitDetectionService.shared.setTrackingEnabled(true)
        
        // Request location permissions
        VisitDetectionService.shared.requestLocationPermissions { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.delegate?.didEnableVisitTracking()
                } else {
                    // Show alert about needing location permissions
                    self?.showLocationPermissionAlert()
                }
                self?.dismiss()
            }
        }
    }
    
    @objc private func notNowButtonTapped() {
        delegate?.didDisableVisitTracking()
        dismiss()
    }
    
    @objc private func skipButtonTapped() {
        delegate?.didSkipVisitTracking()
        dismiss()
    }
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if !containerView.frame.contains(location) {
            delegate?.didSkipVisitTracking()
            dismiss()
        }
    }
    
    private func showLocationPermissionAlert() {
        if let topVC = UIApplication.shared.windows.first?.rootViewController {
            let alert = UIAlertController(
                title: "Location Permission Required",
                message: "To track your visits, Circles needs access to your location. Please enable location access in Settings.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            topVC.present(alert, animated: true)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension VisitTrackingPermissionView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        return !containerView.frame.contains(location)
    }
}
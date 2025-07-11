import UIKit

class UserActivityCell: UICollectionViewCell {
    
    // MARK: - Properties
    static let reuseIdentifier = "UserActivityCell"
    private var connection: Connection?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let activityDotView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 6
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.textColor = Constants.Colors.label
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.addSubview(containerView)
        containerView.addSubview(profileImageView)
        containerView.addSubview(activityDotView)
        contentView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 60),
            containerView.heightAnchor.constraint(equalToConstant: 60),
            
            // Profile image
            profileImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            profileImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 56),
            profileImageView.heightAnchor.constraint(equalToConstant: 56),
            
            // Activity dot
            activityDotView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 2),
            activityDotView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -2),
            activityDotView.widthAnchor.constraint(equalToConstant: 12),
            activityDotView.heightAnchor.constraint(equalToConstant: 12),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        
        // Make profile image circular
        profileImageView.layer.cornerRadius = 28
        profileImageView.layer.borderWidth = 2
        profileImageView.layer.borderColor = Constants.Colors.lightGray.cgColor
    }
    
    // MARK: - Configuration
    func configure(with connection: Connection) {
        self.connection = connection
        
        // Set user info
        if let user = connection.connectedUser {
            nameLabel.text = user.firstName ?? user.displayName
            
            // Set placeholder first
            profileImageView.image = createInitialsImage(for: user.displayName)
            
            // Load profile image using ImageService with caching
            if let profilePicture = user.profilePicture {
                // Store the current user ID to check later
                let currentUserId = user.id
                
                ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                    DispatchQueue.main.async {
                        // Check if the cell is still displaying the same user
                        guard let self = self,
                              let currentConnection = self.connection,
                              currentConnection.connectedUser?.id == currentUserId else {
                            return
                        }
                        
                        if let image = image {
                            self.profileImageView.image = image
                        }
                    }
                }
            }
        }
        
        // Show/hide activity dot based on recent place additions
        activityDotView.isHidden = !(connection.hasRecentPlace ?? false)
        
        // Add pulse animation to activity dot if visible
        if !activityDotView.isHidden {
            addPulseAnimation()
        }
    }
    
    // MARK: - Helper Methods
    private func createInitialsImage(for name: String) -> UIImage {
        let initials = name.components(separatedBy: " ")
            .compactMap { $0.first?.uppercased() }
            .prefix(2)
            .joined()
        
        let size = CGSize(width: 56, height: 56)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            Constants.Colors.tertiaryBackground.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: Constants.Colors.label
            ]
            
            let textSize = initials.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            initials.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func addPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.duration = 1.0
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        activityDotView.layer.add(pulse, forKey: "pulse")
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel any pending image loads by clearing the connection first
        connection = nil
        
        // Clear UI elements
        profileImageView.image = nil
        activityDotView.isHidden = true
        activityDotView.layer.removeAllAnimations()
        nameLabel.text = nil
    }
}
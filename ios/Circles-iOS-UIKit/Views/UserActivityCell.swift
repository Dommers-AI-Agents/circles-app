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
    
    private let activityRingView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.borderColor = UIColor.systemBlue.cgColor
        view.layer.borderWidth = 2.5
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
        containerView.addSubview(activityRingView)
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
            
            // Activity ring (surrounds profile image)
            activityRingView.centerXAnchor.constraint(equalTo: profileImageView.centerXAnchor),
            activityRingView.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor),
            activityRingView.widthAnchor.constraint(equalTo: profileImageView.widthAnchor, constant: 8),
            activityRingView.heightAnchor.constraint(equalTo: profileImageView.heightAnchor, constant: 8),
            
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
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Make activity ring circular
        activityRingView.layer.cornerRadius = activityRingView.frame.width / 2
    }
    
    // MARK: - Configuration
    func configure(with connection: Connection) {
        self.connection = connection
        
        // Set user info
        if let user = connection.connectedUser {
            // Add safety check for empty displayName
            let displayName = user.displayName.isEmpty ? ((user.email ?? "").components(separatedBy: "@").first ?? "User") : user.displayName
            nameLabel.text = displayName
            
            // Debug logging for Dan Wickner issue
            if user.displayName.isEmpty || user.displayName == "Dan Wickner" {
                print("DEBUG UserActivityCell: User \(user.id) has displayName: '\(user.displayName)' (length: \(user.displayName.count))")
                print("DEBUG UserActivityCell: Using display text: '\(displayName)'")
            }
            
            // Set placeholder first
            profileImageView.image = createInitialsImage(for: displayName)
            
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
        
        // Show/hide activity ring based on unviewed activity
        activityRingView.isHidden = !(connection.hasRecentPlace ?? false)
        
        // Add subtle animation to activity ring if visible
        if !activityRingView.isHidden {
            addRingAnimation()
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
    
    private func addRingAnimation() {
        // Subtle fade animation for the ring
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.duration = 2.0
        fade.fromValue = 0.7
        fade.toValue = 1.0
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.autoreverses = true
        fade.repeatCount = .infinity
        activityRingView.layer.add(fade, forKey: "fade")
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel any pending image loads by clearing the connection first
        connection = nil
        
        // Clear UI elements
        profileImageView.image = nil
        activityRingView.isHidden = true
        activityRingView.layer.removeAllAnimations()
        nameLabel.text = nil
    }
    
    // MARK: - Configure as Button
    func configureAsButton(title: String, icon: String) {
        // Reset normal configuration
        profileImageView.image = nil
        activityRingView.isHidden = true
        
        // Set up button appearance
        profileImageView.image = UIImage(systemName: icon)
        profileImageView.tintColor = Constants.Colors.primary
        profileImageView.contentMode = .scaleAspectFit
        profileImageView.backgroundColor = Constants.Colors.tertiaryBackground
        
        // Add button-like border
        profileImageView.layer.borderColor = Constants.Colors.primary.cgColor
        profileImageView.layer.borderWidth = 2
        
        // Set label
        nameLabel.text = title
        nameLabel.textColor = Constants.Colors.primary
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    }
}
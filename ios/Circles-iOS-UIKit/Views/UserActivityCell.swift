import UIKit

class UserActivityCell: UICollectionViewCell {
    
    // MARK: - Properties
    static let reuseIdentifier = "UserActivityCell"
    private var connection: Connection?
    /// Identity for async avatar loads on SUGGESTION cells (no Connection to
    /// check against) — cleared on reuse so a late image can't hit a recycled cell
    private var displayedUserId: String?
    
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
        // Ring size is fixed (avatar 56 + 8) — set the radius up front so the
        // ring is circular even before the first layout pass
        view.layer.cornerRadius = 32
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    // Solid blue ring shown around the avatar of the currently selected connection
    private let selectionRingView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.borderColor = Constants.Colors.primary.cgColor
        view.layer.borderWidth = 3
        view.layer.cornerRadius = 32
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

    // Dashed gray ring marking SUGGESTED people (not yet followed). A plain
    // border can't dash, so this is a CAShapeLayer with a fixed 64pt path —
    // same no-layout-time-radius rule as the rings above.
    private let suggestionRingView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: 1.25, y: 1.25, width: 61.5, height: 61.5)).cgPath
        ring.strokeColor = Constants.Colors.secondaryLabel.withAlphaComponent(0.6).cgColor
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 2
        ring.lineDashPattern = [4, 4]
        view.layer.addSublayer(ring)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    // Small blue plus at the avatar's bottom-trailing — "you can add this person"
    private let suggestionBadgeView: UIImageView = {
        let imageView = UIImageView(image: UIImage(
            systemName: "plus.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
        imageView.tintColor = Constants.Colors.primary
        // White disc behind the plus so it reads over any avatar photo
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 9
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
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
        containerView.addSubview(selectionRingView)
        containerView.addSubview(suggestionRingView)
        containerView.addSubview(suggestionBadgeView)
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

            // Selection ring (surrounds profile image, slightly larger)
            selectionRingView.centerXAnchor.constraint(equalTo: profileImageView.centerXAnchor),
            selectionRingView.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor),
            selectionRingView.widthAnchor.constraint(equalTo: profileImageView.widthAnchor, constant: 8),
            selectionRingView.heightAnchor.constraint(equalTo: profileImageView.heightAnchor, constant: 8),

            // Suggestion ring (same footprint as the other rings)
            suggestionRingView.centerXAnchor.constraint(equalTo: profileImageView.centerXAnchor),
            suggestionRingView.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor),
            suggestionRingView.widthAnchor.constraint(equalTo: profileImageView.widthAnchor, constant: 8),
            suggestionRingView.heightAnchor.constraint(equalTo: profileImageView.heightAnchor, constant: 8),

            // Plus badge at the avatar's bottom-trailing corner
            suggestionBadgeView.trailingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 2),
            suggestionBadgeView.bottomAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 2),
            suggestionBadgeView.widthAnchor.constraint(equalToConstant: 18),
            suggestionBadgeView.heightAnchor.constraint(equalToConstant: 18),

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
    
    // Note: ring corner radii are fixed at init (size is a constant 64pt).
    // Do NOT recompute them in layoutSubviews — an early layout pass with a
    // zero frame would reset the radius to 0 and draw square rings.

    /// Shows/hides the blue selection ring. Selection takes visual priority
    /// over the activity ring so the selected avatar is unambiguous.
    func setSelectedHighlight(_ isSelected: Bool) {
        selectionRingView.isHidden = !isSelected
        if isSelected {
            activityRingView.isHidden = true
            activityRingView.layer.removeAllAnimations()
        }
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
                Logger.debug("DEBUG UserActivityCell: User \(user.id) has displayName: '\(user.displayName)' (length: \(user.displayName.count))")
                Logger.debug("DEBUG UserActivityCell: Using display text: '\(displayName)'")
            }
            
            // Load profile image using ImageService with caching
            if let profilePicture = user.profilePicture {
                // Store the current user ID to check later
                let currentUserId = user.id

                // Use a namespaced cache key to prevent collisions with place images
                let profileCacheKey = "profile_\(currentUserId)_\(profilePicture)"

                if let cached = ImageService.shared.cachedImage(forKey: profileCacheKey) {
                    // Cache hit: set the real avatar immediately. Setting the
                    // initials placeholder first (as before) caused a one-frame
                    // gray flash on every reload — the visible "flashing".
                    profileImageView.image = cached
                } else {
                    // Cache miss: show initials, then swap in the downloaded image
                    profileImageView.image = createInitialsImage(for: displayName)
                    ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: profileCacheKey) { [weak self] image in
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
            } else {
                // No profile picture at all — show initials
                profileImageView.image = createInitialsImage(for: displayName)
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
    
    // MARK: - Suggested user

    /// Renders a SUGGESTED person (someone the user doesn't follow yet):
    /// same avatar treatment as a connection, plus a dashed ring and a small
    /// blue plus badge so it can't be mistaken for an existing relationship.
    func configure(withSuggestion user: User) {
        connection = nil
        displayedUserId = user.id

        let displayName = user.displayName.isEmpty
            ? ((user.email ?? "").components(separatedBy: "@").first ?? "User")
            : user.displayName
        nameLabel.text = displayName

        if let profilePicture = user.profilePicture, !profilePicture.isEmpty {
            let cacheKey = "profile_\(user.id)_\(profilePicture)"
            if let cached = ImageService.shared.cachedImage(forKey: cacheKey) {
                profileImageView.image = cached
            } else {
                profileImageView.image = createInitialsImage(for: displayName)
                let expectedId = user.id
                ImageService.shared.loadImageWithKey(from: profilePicture, cacheKey: cacheKey) { [weak self] image in
                    DispatchQueue.main.async {
                        guard let self = self, self.displayedUserId == expectedId,
                              let image = image else { return }
                        self.profileImageView.image = image
                    }
                }
            }
        } else {
            profileImageView.image = createInitialsImage(for: displayName)
        }

        activityRingView.isHidden = true
        activityRingView.layer.removeAllAnimations()
        selectionRingView.isHidden = true
        suggestionRingView.isHidden = false
        suggestionBadgeView.isHidden = false
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()

        // Cancel any pending image loads by clearing the identities first
        connection = nil
        displayedUserId = nil

        // Clear UI elements
        profileImageView.image = nil
        activityRingView.isHidden = true
        activityRingView.layer.removeAllAnimations()
        selectionRingView.isHidden = true
        suggestionRingView.isHidden = true
        suggestionBadgeView.isHidden = true
        nameLabel.text = nil

        // configureAsButton and configure(withSuggestion:) restyle the avatar
        // and label — reset EVERYTHING they touch or the styling bleeds into
        // recycled connection cells
        profileImageView.tintColor = nil
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.backgroundColor = Constants.Colors.tertiaryBackground
        profileImageView.layer.borderColor = Constants.Colors.lightGray.cgColor
        profileImageView.layer.borderWidth = 2
        nameLabel.textColor = Constants.Colors.label
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - Configure as Button
    func configureAsButton(title: String, icon: String) {
        // Reset normal configuration
        connection = nil
        displayedUserId = nil
        activityRingView.isHidden = true
        selectionRingView.isHidden = true
        suggestionRingView.isHidden = true
        suggestionBadgeView.isHidden = true

        // Set up button appearance (glyph sized so it doesn't fill the circle)
        profileImageView.image = UIImage(systemName: icon, withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        profileImageView.tintColor = Constants.Colors.primary
        profileImageView.contentMode = .center
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
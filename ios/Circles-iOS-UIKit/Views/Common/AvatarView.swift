import UIKit

/// A circular person avatar: their photo, or their initials avatar
/// (`AvatarPlaceholder`) while it loads and when they have none. Photos come
/// through `ImageService.loadProfileImage`, so every surface shares one cache.
final class AvatarView: UIImageView {

    /// The user this view is showing; a late photo for someone else (a reused
    /// cell) is dropped.
    private(set) var userId: String?

    init(diameter: CGFloat? = nil) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = Constants.Colors.tertiaryBackground
        translatesAutoresizingMaskIntoConstraints = false
        if let diameter {
            widthAnchor.constraint(equalToConstant: diameter).isActive = true
            heightAnchor.constraint(equalToConstant: diameter).isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func configure(with user: User) {
        configure(name: user.displayName, userId: user.id, photoUrl: user.profilePicture)
    }

    func configure(name: String?, userId: String?, photoUrl: String?) {
        self.userId = userId
        let diameter = max(bounds.width, 40)
        image = AvatarPlaceholder.image(name: name, seed: userId, diameter: diameter)

        guard let userId, let photoUrl, !photoUrl.isEmpty else { return }
        ImageService.shared.loadProfileImage(for: userId, from: photoUrl) { [weak self] loaded in
            guard let self, let loaded, self.userId == userId else { return }
            self.image = loaded
        }
    }

    /// Back to blank, for cell reuse.
    func reset() {
        userId = nil
        image = nil
    }
}

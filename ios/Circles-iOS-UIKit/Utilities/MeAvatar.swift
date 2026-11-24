import UIKit

/// The signed-in person's own face, as a small round thumbnail.
///
/// Every "Me" control — the Me tab and the Me chips over the maps — used to
/// wear the same `person` glyph. They now wear your profile picture (Wes,
/// 2026-11-24). This is the one place that picture is resolved, cropped and
/// refreshed, so the four surfaces can't drift apart.
///
/// Callers read `image(diameter:)` synchronously and redraw when
/// `.meAvatarDidChange` is posted (a sign-in, a new profile picture, or the
/// photo finishing its download). Main thread only.
enum MeAvatar {

    /// Size of the avatar inside a "Me" chip: the footprint of the 12pt
    /// `person` symbol it replaces, so the chip keeps its height.
    static let chipDiameter: CGFloat = 16

    /// Photo downloads in flight, by cache key, so a burst of redraws starts one.
    private static var loading = Set<String>()

    /// Your avatar, cropped to a circle and ready to hand to a button or a tab
    /// item as-is. `ring` draws a selection ring around it.
    ///
    /// Nil only when nobody is signed in — keep the glyph then. While a photo
    /// is still downloading this returns the initials avatar and posts
    /// `.meAvatarDidChange` when the photo arrives.
    static func image(diameter: CGFloat, ring: UIColor? = nil) -> UIImage? {
        guard let user = AuthService.shared.currentUser else { return nil }
        return circular(source(for: user, diameter: diameter), diameter: diameter, ring: ring)
    }

    /// The image for a "Me" chip: your avatar, or the old glyph signed out.
    static func chipImage(isActive: Bool) -> UIImage? {
        image(diameter: chipDiameter) ?? UIImage(
            systemName: isActive ? "person.fill" : "person",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
    }

    // MARK: - Source

    private static func source(for user: User, diameter: CGFloat) -> UIImage {
        let placeholder = AvatarPlaceholder.image(for: user, diameter: diameter)
        // No photo, or Google's generated monogram: initials, like everywhere else
        guard user.hasRealProfilePhoto, let url = user.profilePicture else { return placeholder }
        // Stock and catalog avatars are drawn on device, not downloaded
        if let stock = StockAvatar.image(from: url, diameter: diameter) { return stock }

        let key = ImageService.profileCacheKey(userId: user.id, url: url)
        if let cached = ImageService.shared.cachedImage(forKey: key) { return cached }

        if !loading.contains(key) {
            loading.insert(key)
            ImageService.shared.loadImageWithKey(from: url, cacheKey: key) { image in
                DispatchQueue.main.async {
                    loading.remove(key)
                    // A failed download keeps the initials; a later redraw retries
                    guard image != nil else { return }
                    NotificationCenter.default.post(name: .meAvatarDidChange, object: nil)
                }
            }
        }
        return placeholder
    }

    // MARK: - Drawing

    /// Aspect-fill crop to a circle at screen scale. Returned `.alwaysOriginal`
    /// so a tab bar or a button configuration doesn't tint it into a flat disc.
    static func circular(_ image: UIImage, diameter: CGFloat, ring: UIColor? = nil) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let ringWidth: CGFloat = ring == nil ? 0 : 1.5
        // The ring sits at the edge with a hair of space before the photo
        let inset: CGFloat = ring == nil ? 0 : ringWidth + 1
        let photoRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)

        return UIGraphicsImageRenderer(size: size).image { context in
            if let ring {
                ring.setStroke()
                let path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)
                    .insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
                path.lineWidth = ringWidth
                path.stroke()
            }

            context.cgContext.saveGState()
            UIBezierPath(ovalIn: photoRect).addClip()
            let scale = max(photoRect.width / max(image.size.width, 1),
                            photoRect.height / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: photoRect.midX - drawSize.width / 2,
                                  y: photoRect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height))
            context.cgContext.restoreGState()
        }.withRenderingMode(.alwaysOriginal)
    }
}

import UIKit

/// Default avatars for people who haven't set a photo.
///
/// The old placeholder was a grey `person.circle.fill` glyph, which made every
/// photo-less person look like the same anonymous silhouette — in a list of
/// connections they were indistinguishable. These render the person's initials
/// on a colour derived from their user id, so each one is stable, distinct, and
/// recognisable at a glance.
enum AvatarPlaceholder {

    /// Muted, desaturated hues that sit behind white text at any size and don't
    /// fight the brand blue. Deliberately not the system colours — those read as
    /// alerts (red) or actions (blue) when they appear in a list.
    fileprivate static let palette: [UIColor] = [
        UIColor(red: 0.36, green: 0.51, blue: 0.71, alpha: 1),  // slate blue
        UIColor(red: 0.42, green: 0.60, blue: 0.53, alpha: 1),  // sage
        UIColor(red: 0.72, green: 0.51, blue: 0.42, alpha: 1),  // clay
        UIColor(red: 0.55, green: 0.47, blue: 0.68, alpha: 1),  // muted violet
        UIColor(red: 0.78, green: 0.60, blue: 0.35, alpha: 1),  // amber
        UIColor(red: 0.44, green: 0.58, blue: 0.66, alpha: 1),  // steel
        UIColor(red: 0.70, green: 0.45, blue: 0.52, alpha: 1),  // rose
        UIColor(red: 0.48, green: 0.55, blue: 0.40, alpha: 1)   // olive
    ]

    static var paletteCount: Int { palette.count }

    /// Stable across launches and devices — `hashValue` is NOT (Swift seeds it
    /// per process), so someone's colour would change every cold start.
    private static func paletteIndex(for seed: String) -> Int {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(palette.count))
    }

    /// One or two letters: first letters of the first and last word. Emoji-only
    /// tokens are skipped — "Melinda 🧜‍♀️" should read as M, not a broken glyph.
    static func initials(for name: String?) -> String {
        let words = (name ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .compactMap { word -> String? in
                guard let first = word.first, first.isLetter || first.isNumber else { return nil }
                return String(first).uppercased()
            }
        if words.count >= 2, let first = words.first, let last = words.last {
            return first + last
        }
        return words.first ?? ""
    }

    /// A circular initials avatar for someone with no photo.
    static func image(name: String?, seed: String? = nil, diameter: CGFloat = 80) -> UIImage {
        let letters = initials(for: name)
        let colour = palette[paletteIndex(for: seed?.isEmpty == false ? seed! : (name ?? "?"))]
        let size = CGSize(width: diameter, height: diameter)

        return UIGraphicsImageRenderer(size: size).image { context in
            drawDisc(colour: colour, diameter: diameter, in: context)

            guard !letters.isEmpty else {
                let config = UIImage.SymbolConfiguration(pointSize: diameter * 0.5, weight: .regular)
                if let glyph = UIImage(systemName: "person.fill", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    glyph.draw(at: CGPoint(x: (diameter - glyph.size.width) / 2,
                                           y: (diameter - glyph.size.height) / 2))
                }
                return
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: diameter * (letters.count > 1 ? 0.38 : 0.46), weight: .semibold),
                .foregroundColor: UIColor.white,
                .kern: diameter * 0.01
            ]
            let text = NSAttributedString(string: letters, attributes: attributes)
            let bounds = text.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
            text.draw(at: CGPoint(x: (diameter - bounds.width) / 2,
                                  y: (diameter - bounds.height) / 2))
        }
    }

    /// Convenience for the common `User` case.
    static func image(for user: User, diameter: CGFloat = 80) -> UIImage {
        image(name: user.displayName, seed: user.id, diameter: diameter)
    }

    /// The gradient disc both avatar styles sit on. A flat circle reads as a
    /// placeholder; a shaded one reads as intentional.
    fileprivate static func drawDisc(colour: UIColor, diameter: CGFloat, in context: UIGraphicsImageRendererContext) {
        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        UIBezierPath(ovalIn: rect).addClip()
        let colours = [colour.lightened(by: 0.12).cgColor, colour.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colours, locations: [0, 1]) {
            context.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: 0, y: diameter), options: []
            )
        } else {
            colour.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
    }

    /// Draws a character face on the gradient disc (see `StockAvatar`).
    static func render(face: String, colourIndex: Int, diameter: CGFloat) -> UIImage {
        let colour = palette[abs(colourIndex) % palette.count]
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { context in
            drawDisc(colour: colour, diameter: diameter, in: context)
            // Emoji carry generous internal padding, so they have to be drawn
            // large to fill the disc the way a face photo would.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: diameter * 0.62)
            ]
            let text = NSAttributedString(string: face, attributes: attributes)
            let bounds = text.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
            text.draw(at: CGPoint(x: (diameter - bounds.width) / 2,
                                  y: (diameter - bounds.height) / 2))
        }
    }
}

fileprivate extension UIColor {
    func lightened(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: max(0, s - amount * 0.3), brightness: min(1, b + amount), alpha: a)
    }
}

// MARK: - Stock avatars

/// A pickable avatar for people who'd rather not upload a photo.
///
/// These are CHARACTERS, not icons. A mountain or a coffee cup is clip art —
/// a row of them doesn't read as people, which is the whole point of an avatar.
/// Emoji give us expressive, professionally drawn faces at every size, for free.
///
/// Stored on the user as `stock-avatar:<emoji>:<paletteIndex>` and drawn on
/// device, so there are no assets to ship and nothing to download. 28 faces ×
/// 8 backgrounds = 224 combinations, so two people who both pick the fox still
/// look different.
enum StockAvatar {

    static let scheme = "stock-avatar:"

    /// People first (the default reading of "avatar"), then characters, then
    /// animal faces — the three things people actually pick in every app that
    /// offers this.
    static let faces: [String] = [
        "🧑‍🚀", "👩‍🎨", "🧑‍🍳", "👨‍🎤", "🧑‍🌾", "👩‍🔬", "🧑‍✈️", "🕵️",
        "🦸", "🦹", "🧙", "🧝", "🧜", "🧚", "🤠", "🥷",
        "👽", "🤖", "🐱", "🐶", "🦊", "🐼", "🦁", "🐯",
        "🐨", "🐻", "🦄", "🐸"
    ]

    /// Face-major, so the grid reads as rows of one character in different
    /// colours rather than a jumble.
    static var allValues: [String] {
        faces.flatMap { face in
            (0..<AvatarPlaceholder.paletteCount).map { "\(scheme)\(face):\($0)" }
        }
    }

    static func isStockAvatar(_ urlString: String?) -> Bool {
        (urlString ?? "").hasPrefix(scheme)
    }

    /// Renders a stored value; nil when the string isn't a stock avatar.
    static func image(from value: String, diameter: CGFloat = 80) -> UIImage? {
        guard value.hasPrefix(scheme) else { return nil }
        let parts = value.dropFirst(scheme.count).components(separatedBy: ":")
        guard let face = parts.first, !face.isEmpty else { return nil }
        let colourIndex = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return AvatarPlaceholder.render(face: face, colourIndex: colourIndex, diameter: diameter)
    }
}

// MARK: - Does this person actually have a photo?

extension User {
    /// True when the profile picture is something the person chose — a real
    /// photograph or a stock avatar.
    ///
    /// Two things masquerade as photos: an empty/missing URL, and Google's
    /// auto-generated monogram. Google serves user-uploaded photos from the
    /// `/a-/` path and generated ones from `/a/`, so `/a/ACg8oc…` is the
    /// coloured letter Google made up, not a picture of anyone.
    var hasRealProfilePhoto: Bool {
        guard let url = profilePicture?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            return false
        }
        if StockAvatar.isStockAvatar(url) { return true }
        if url.contains("googleusercontent.com") {
            return url.contains("/a-/")
        }
        return true
    }
}

// MARK: - One-call avatar loading

extension UIImageView {
    /// Shows `user`'s photo, or their initials avatar while it loads / when
    /// they have none. Use this instead of hand-rolling
    /// `UIImage(systemName: "person.circle.fill")` — that grey silhouette is
    /// what made every photo-less person look identical.
    func setUserAvatar(name: String?, seed: String?, urlString: String?, diameter: CGFloat? = nil) {
        let size = diameter ?? max(bounds.width, 40)
        image = AvatarPlaceholder.image(name: name, seed: seed, diameter: size)
        contentMode = .scaleAspectFill
        clipsToBounds = true

        guard let urlString = urlString, !urlString.isEmpty, let seed = seed else { return }
        ImageService.shared.loadProfileImage(for: seed, from: urlString) { [weak self] loaded in
            DispatchQueue.main.async {
                // Keep the initials rather than falling back to a silhouette
                guard let self = self, let loaded = loaded else { return }
                self.image = loaded
            }
        }
    }

    func setUserAvatar(for user: User, diameter: CGFloat? = nil) {
        setUserAvatar(name: user.displayName, seed: user.id, urlString: user.profilePicture, diameter: diameter)
    }
}

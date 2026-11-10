import UIKit

extension UIFont {
    /// The brand's serif headline (the App Clip card, the welcome sheet): the
    /// system serif design, bold, falling back to the system font.
    static func serifBold(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

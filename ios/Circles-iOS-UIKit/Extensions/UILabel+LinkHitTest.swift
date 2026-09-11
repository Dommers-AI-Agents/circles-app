import UIKit

extension UILabel {
    /// The `.link` URL under a point in this label's attributed text, if
    /// any — for labels that show links but aren't text views.
    func link(at point: CGPoint) -> URL? {
        guard let attributedText = attributedText else { return nil }

        // Create text container
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode

        // Create layout manager
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        // Create text storage
        let textStorage = NSTextStorage(attributedString: attributedText)
        textStorage.addLayoutManager(layoutManager)

        // Find the character index at tap location
        let characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Check if tap is on a URL
        var found: URL?
        attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: attributedText.length), options: []) { (value, range, stop) in
            if let url = value as? URL, NSLocationInRange(characterIndex, range) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }
}

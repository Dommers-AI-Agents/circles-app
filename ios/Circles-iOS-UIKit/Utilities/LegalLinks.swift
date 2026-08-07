import UIKit

/// The hosted legal documents, plus a factory for "you agree to …" text with
/// FUNCTIONAL tappable links.
///
/// App Review requires these in two places (Guidelines 2.1(a) and 3.1.2(c)):
/// any screen that claims the user is agreeing to terms must actually link to
/// them, and every subscription purchase screen must carry functional links to
/// both the Terms of Use (EULA) and the Privacy Policy.
enum LegalLinks {
    static let termsURL = URL(string: "https://favcircles.com/terms.html")!
    static let privacyURL = URL(string: "https://favcircles.com/privacy.html")!

    /// Attributed agreement text where any occurrence of `termsPhrase` and
    /// `privacyPhrase` inside `text` becomes a tappable link. Display it in a
    /// non-editable, non-scrolling UITextView (UILabel ignores link attributes).
    static func agreementText(
        _ text: String,
        termsPhrase: String = "Terms of Use",
        privacyPhrase: String = "Privacy Policy",
        fontSize: CGFloat = 12,
        color: UIColor = .secondaryLabel
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: color
            ]
        )
        if let range = text.range(of: termsPhrase) {
            attributed.addAttribute(.link, value: termsURL, range: NSRange(range, in: text))
        }
        if let range = text.range(of: privacyPhrase) {
            attributed.addAttribute(.link, value: privacyURL, range: NSRange(range, in: text))
        }
        return attributed
    }

    /// A ready-to-constrain text view configured for legal footer text.
    static func makeLegalTextView(linkColor: UIColor = .systemBlue) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }
}

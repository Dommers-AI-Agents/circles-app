import UIKit

/// Explains the difference between following someone and connecting with them.
///
/// The distinction has always been real — following puts someone's public
/// activity in your feed, while connecting also opens their network-only
/// circles, messaging and place suggestions — but nothing in the app ever said
/// so, leaving two similar-looking buttons side by side for people to guess at.
enum RelationshipExplainer {

    private static let dismissedKey = "hasSeenFollowConnectExplainer"

    /// True until someone has dismissed the inline card at least once.
    static var shouldShowInlineCard: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func markInlineCardSeen() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    /// The full explanation, shown on demand from any section header's ⓘ and
    /// from the ⓘ beside a privacy picker.
    ///
    /// There used to be a second, differently worded version of this in
    /// AllUsersListViewController. Two explanations of the same thing is how
    /// people end up unsure which is authoritative, so there is now one.
    static func present(from viewController: UIViewController) {
        AlertPresenter.showInfo(
            title: "Followers, Connections, Inner Circle",
            message: """
            Following — they see your public places and activity in their feed.             One-way and instant; you don't have to approve it.

            Connections — you both agreed to connect. Opens your             Connections-only circles, messaging and place suggestions.

            Inner Circle — the connections you pick by name. Anything you set             to Inner Circle is visible only to them, and taking someone off the             list takes back what they could already see.

            Someone can follow you and be connected to you at once, so they             appear in both lists.
            """,
            from: viewController
        )
    }

    /// The dismissible card shown at the top of the tab until it's been read.
    /// Returns nil once dismissed, so callers can just check for a view.
    static func makeInlineCard(target: Any, dismissAction: Selector, infoAction: Selector) -> UIView? {
        guard shouldShowInlineCard else { return nil }

        let card = UIView()
        card.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.08)
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isUserInteractionEnabled = true

        let icon = UIImageView(image: UIImage(systemName: "info.circle.fill"))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Follow to see someone's public picks. Connect to unlock network-only circles and messaging."
        label.font = .systemFont(ofSize: 13)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .secondaryLabel
        close.accessibilityLabel = "Dismiss"
        close.addTarget(target, action: dismissAction, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(icon)
        card.addSubview(label)
        card.addSubview(close)

        let tap = UITapGestureRecognizer(target: target, action: infoAction)
        card.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),

            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 20),
            close.heightAnchor.constraint(equalToConstant: 20)
        ])

        return card
    }
}

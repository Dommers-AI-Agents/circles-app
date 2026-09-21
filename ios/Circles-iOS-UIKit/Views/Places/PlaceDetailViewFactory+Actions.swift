import UIKit
import MapKit

/// The practical row (check in, add to circle) and the like/comment/send/follow bar.
extension PlaceDetailViewFactory {
    static func practicalButtonsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func checkInRowButton() -> UIButton {
        let button = UIButton.rowButton(title: "Check In", systemName: "checkmark.circle")
        button.setImage(.checkInIcon, for: .normal)
        return button
    }

    // MARK: - Check-in strip (directly under the photo)

    /// The row that sits between the photo and the info card: either your
    /// history here, or an invitation to start one, plus an "i" that says
    /// what a check-in is. A stack so the unused half collapses.
    static func checkInStripView() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Constants.Spacing.small
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func checkInHistoryLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Shown only to someone who has never checked in here.
    static func checkInHereButton() -> UIButton {
        let button = UIButton.smallActionButton(title: "Check in here", style: .primary)
        button.setImage(.checkInIcon, for: .normal)
        button.tintColor = .white
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        return button
    }

    static func checkInInfoButton() -> UIButton {
        let button = UIButton.iconButton(systemName: "info.circle", pointSize: 17)
        button.tintColor = Constants.Colors.secondaryLabel
        button.accessibilityLabel = "What is a check-in?"
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func addToCircleButton() -> UIButton {
        let button = UIButton.smallActionButton(title: "Add to My Circle", style: .primary)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        button.isHidden = true // Hidden until eligibility is known
        return button
    }

    static func actionButtonsContainer() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func likeButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func likeCountLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }

    static func commentButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.left", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func commentCountLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func sendButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: PlaceDetailViewController.actionIconConfig), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func followButton() -> UIButton {
        let button = UIButton.smallActionButton(title: "Follow", style: .primary)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        return button
    }

}

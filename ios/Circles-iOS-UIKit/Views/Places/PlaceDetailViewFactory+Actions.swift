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

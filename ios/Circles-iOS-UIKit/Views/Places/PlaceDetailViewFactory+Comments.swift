import UIKit
import MapKit

/// The comments section.
extension PlaceDetailViewFactory {
    static func commentsSection() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true // Initially hidden until comments are loaded
        return view
    }

    static func commentsSectionTitle() -> UILabel {
        let label = UILabel()
        label.text = "Comments"
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func viewAllCommentsButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("View all", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func commentsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

}

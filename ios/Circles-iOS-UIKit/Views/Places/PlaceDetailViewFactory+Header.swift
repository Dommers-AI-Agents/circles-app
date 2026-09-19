import UIKit
import MapKit

/// Scroll container, media carousel, street-view/edit/update buttons, name, category, rating, creator, saved-by.
extension PlaceDetailViewFactory {
    static func scrollView() -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    static func contentView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func mediaCarouselView() -> MediaCarouselView {
        let view = MediaCarouselView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }

    static func streetViewToggleButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Street View", for: .normal)
        button.setImage(UIImage(systemName: "person.and.arrow.left.and.arrow.right"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }

    static func editImageButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Add Photo or Video", for: .normal)
        button.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = false  // Show by default
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }

    static func updateInfoButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Update Place Info", for: .normal)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true  // Hidden by default
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.layer.shadowRadius = 6
        return button
    }

    static func infoContainerView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func nameLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func categoryLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.white
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func categoryEditButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pencil"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func ratingView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }

    static func creatorLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }

    static func savedByView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }

    static func savedByFacepileView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = -8 // Overlapping avatars
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func savedByChevron() -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.tintColor = Constants.Colors.gray
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

}

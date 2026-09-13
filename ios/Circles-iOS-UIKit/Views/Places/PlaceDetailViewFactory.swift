import UIKit
import MapKit

/// The place page's view elements, one factory per outlet. Bodies moved
/// verbatim from the closure initializers on PlaceDetailViewController
/// (Phase 6); the controller keeps the outlets and every target/constraint.
enum PlaceDetailViewFactory {
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

    static func practicalButtonsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func checkInRowButton() -> UIButton {
        let button = PlaceDetailViewController.practicalButton(title: "Check In", systemName: "checkmark.circle")
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

    static func ratingImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "star.fill")
        imageView.tintColor = UIColor(hex: "#F6E05E") // Yellow
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

    static func ratingLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func descriptionLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }

    static func userRatingLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.primary
        label.numberOfLines = 1
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func addressLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func hoursLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func aboutCardView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func aboutStackView() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func aboutTitleLabel() -> UILabel {
        let label = UILabel()
        label.text = "ABOUT"
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = Constants.Colors.secondaryLabel
        return label
    }

    static func mapView() -> MKMapView {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }

    static func notesTitleLabel() -> UILabel {
        let label = UILabel()
        label.text = "Notes"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func notesButtonsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func notesEditButton() -> UIButton {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "pencil.circle")
        config.title = "Edit"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func notesLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func addNotesButton() -> UIButton {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "plus.circle")
        config.title = "Add Note"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }

    static func photosTitleLabel() -> UILabel {
        let label = UILabel()
        label.text = "Photos"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func photosButtonsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func photosEditButton() -> UIButton {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "pencil.circle")
        config.title = "Add Photo or Video"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func addPhotoButton() -> UIButton {
        let button = UIButton(type: .system)
        
        // Create configuration for button with icon
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "camera.fill")
        config.title = "Add Photo"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        
        button.configuration = config
        button.configurationUpdateHandler = { button in
            var config = button.configuration
            config?.baseForegroundColor = Constants.Colors.primary
            button.configuration = config
        }
        
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func tagsTitleLabel() -> UILabel {
        let label = UILabel()
        label.text = "Tags"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func tagsStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.alignment = .leading
        stackView.distribution = .fillProportionally
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }

    static func circleInfoView() -> UIView {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func circleNameLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func circleButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("View Circle", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

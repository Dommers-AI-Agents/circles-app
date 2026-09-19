import UIKit
import MapKit

/// Photos, tags and the circle-info footer.
extension PlaceDetailViewFactory {
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

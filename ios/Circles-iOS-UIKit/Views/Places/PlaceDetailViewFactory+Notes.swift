import UIKit
import MapKit

/// Notes title, edit/add buttons and the notes text.
extension PlaceDetailViewFactory {
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

}

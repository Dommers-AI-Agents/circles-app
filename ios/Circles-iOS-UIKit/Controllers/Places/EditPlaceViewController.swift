import UIKit
import MapKit
import CoreLocation
import PhotosUI

protocol EditPlaceDelegate: AnyObject {
    func didUpdatePlace(_ updatedPlace: Place)
    func didDeletePlace(_ placeId: String)
}

class EditPlaceViewController: UIViewController {
    
    // MARK: - Constants
    private enum Constants {
        enum Spacing {
            static let small: CGFloat = 8
            static let medium: CGFloat = 16
            static let large: CGFloat = 20
            static let xlarge: CGFloat = 32
        }
        
        enum FontSize {
            static let small: CGFloat = 14
            static let medium: CGFloat = 16
            static let large: CGFloat = 18
            static let xlarge: CGFloat = 20
            static let xxlarge: CGFloat = 24
        }
        
        enum Colors {
            static let primary = UIColor.systemBlue
            static let background = UIColor.systemBackground
            static let secondaryBackground = UIColor.secondarySystemBackground
            static let darkGray = UIColor.darkGray
            static let lightGray = UIColor.lightGray
            static let white = UIColor.white
        }
    }
    
    // MARK: - Properties
    private var place: Place
    private let locationManager = CLLocationManager()
    private var selectedLocation: CLLocationCoordinate2D?
    weak var delegate: EditPlaceDelegate?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "Place Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter place name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Category"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categorySegmentedControl: UISegmentedControl = {
        let categories = ["Restaurant", "Cafe", "Bar", "Hotel", "Retail", "Service", "Attraction", "Other"]
        let segmentedControl = UISegmentedControl(items: categories)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let customCategoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Custom Category Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let customCategoryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter custom category name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isHidden = true
        return textField
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Description (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.text = "Address"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let streetTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Street"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let cityTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "City"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let stateTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "State"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let zipCodeTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Zip Code"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let countryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Country"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let mapLabel: UILabel = {
        let label = UILabel()
        label.text = "Location"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let useCurrentLocationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Use Current Location", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Privacy"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacySegmentedControl: UISegmentedControl = {
        let items = ["Follow Circle", "Public", "Friends", "Private"]
        let segmentedControl = UISegmentedControl(items: items)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.text = "Notes (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let tagsLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags (optional, comma separated)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. family-friendly, romantic, cheap"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let websiteLabel: UILabel = {
        let label = UILabel()
        label.text = "Website (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let websiteTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "https://example.com"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .URL
        textField.autocapitalizationType = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let phoneLabel: UILabel = {
        let label = UILabel()
        label.text = "Phone (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let phoneTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "+1 (555) 123-4567"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .phonePad
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    // Photo UI elements
    private let photoLabel: UILabel = {
        let label = UILabel()
        label.text = "Photos"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let photoScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let photoStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let addPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = UIColor.systemGray6
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.systemBlue.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var photoImageViews: [UIImageView] = []
    private var selectedImages: [UIImage] = []
    private var existingPhotoURLs: [String] = []
    private var deletedPhotoURLs: [String] = []
    
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Save Changes", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Delete Place", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let moveToCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Move to Different Circle", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    
    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationManager()
        setupActions()
        populateFields()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Edit Place"
        
        // Navigation bar buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveButtonTapped))
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(nameTextField)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(categorySegmentedControl)
        contentView.addSubview(customCategoryLabel)
        contentView.addSubview(customCategoryTextField)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(descriptionTextView)
        contentView.addSubview(addressLabel)
        contentView.addSubview(streetTextField)
        contentView.addSubview(cityTextField)
        contentView.addSubview(stateTextField)
        contentView.addSubview(zipCodeTextField)
        contentView.addSubview(countryTextField)
        contentView.addSubview(mapLabel)
        contentView.addSubview(mapView)
        contentView.addSubview(useCurrentLocationButton)
        contentView.addSubview(privacyLabel)
        contentView.addSubview(privacySegmentedControl)
        contentView.addSubview(notesLabel)
        contentView.addSubview(notesTextView)
        contentView.addSubview(tagsLabel)
        contentView.addSubview(tagsTextField)
        contentView.addSubview(websiteLabel)
        contentView.addSubview(websiteTextField)
        contentView.addSubview(phoneLabel)
        contentView.addSubview(phoneTextField)
        
        // Add photo UI elements
        contentView.addSubview(photoLabel)
        contentView.addSubview(photoScrollView)
        photoScrollView.addSubview(photoStackView)
        photoStackView.addArrangedSubview(addPhotoButton)
        
        contentView.addSubview(moveToCircleButton)
        contentView.addSubview(deleteButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Name label and text field
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            nameTextField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            nameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            nameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            nameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Category label and segmented control
            categoryLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            categorySegmentedControl.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Custom category label and text field
            customCategoryLabel.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            customCategoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            customCategoryTextField.topAnchor.constraint(equalTo: customCategoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            customCategoryTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            customCategoryTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            customCategoryTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Description label and text view
            descriptionLabel.topAnchor.constraint(equalTo: customCategoryTextField.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            descriptionTextView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            descriptionTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            descriptionTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 80),
            
            // Address label and text fields
            addressLabel.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: Constants.Spacing.medium),
            addressLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            streetTextField.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.small),
            streetTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            streetTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            streetTextField.heightAnchor.constraint(equalToConstant: 40),
            
            cityTextField.topAnchor.constraint(equalTo: streetTextField.bottomAnchor, constant: Constants.Spacing.small),
            cityTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            cityTextField.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.4, constant: -Constants.Spacing.large),
            cityTextField.heightAnchor.constraint(equalToConstant: 40),
            
            stateTextField.topAnchor.constraint(equalTo: streetTextField.bottomAnchor, constant: Constants.Spacing.small),
            stateTextField.leadingAnchor.constraint(equalTo: cityTextField.trailingAnchor, constant: Constants.Spacing.medium),
            stateTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            stateTextField.heightAnchor.constraint(equalToConstant: 40),
            
            zipCodeTextField.topAnchor.constraint(equalTo: cityTextField.bottomAnchor, constant: Constants.Spacing.small),
            zipCodeTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            zipCodeTextField.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.4, constant: -Constants.Spacing.large),
            zipCodeTextField.heightAnchor.constraint(equalToConstant: 40),
            
            countryTextField.topAnchor.constraint(equalTo: stateTextField.bottomAnchor, constant: Constants.Spacing.small),
            countryTextField.leadingAnchor.constraint(equalTo: zipCodeTextField.trailingAnchor, constant: Constants.Spacing.medium),
            countryTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            countryTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Map label and view
            mapLabel.topAnchor.constraint(equalTo: countryTextField.bottomAnchor, constant: Constants.Spacing.medium),
            mapLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            mapView.topAnchor.constraint(equalTo: mapLabel.bottomAnchor, constant: Constants.Spacing.small),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            mapView.heightAnchor.constraint(equalToConstant: 180),
            
            useCurrentLocationButton.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.small),
            useCurrentLocationButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Privacy label and segmented control
            privacyLabel.topAnchor.constraint(equalTo: useCurrentLocationButton.bottomAnchor, constant: Constants.Spacing.medium),
            privacyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            privacySegmentedControl.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: Constants.Spacing.small),
            privacySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            privacySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Notes label and text view
            notesLabel.topAnchor.constraint(equalTo: privacySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            notesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            notesTextView.topAnchor.constraint(equalTo: notesLabel.bottomAnchor, constant: Constants.Spacing.small),
            notesTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            notesTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            notesTextView.heightAnchor.constraint(equalToConstant: 80),
            
            // Tags label and text field
            tagsLabel.topAnchor.constraint(equalTo: notesTextView.bottomAnchor, constant: Constants.Spacing.medium),
            tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            tagsTextField.topAnchor.constraint(equalTo: tagsLabel.bottomAnchor, constant: Constants.Spacing.small),
            tagsTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            tagsTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            tagsTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Website label and text field
            websiteLabel.topAnchor.constraint(equalTo: tagsTextField.bottomAnchor, constant: Constants.Spacing.medium),
            websiteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            websiteTextField.topAnchor.constraint(equalTo: websiteLabel.bottomAnchor, constant: Constants.Spacing.small),
            websiteTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            websiteTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            websiteTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Phone label and text field
            phoneLabel.topAnchor.constraint(equalTo: websiteTextField.bottomAnchor, constant: Constants.Spacing.medium),
            phoneLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            phoneTextField.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: Constants.Spacing.small),
            phoneTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            phoneTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            phoneTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Photo label and scroll view
            photoLabel.topAnchor.constraint(equalTo: phoneTextField.bottomAnchor, constant: Constants.Spacing.medium),
            photoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            photoScrollView.topAnchor.constraint(equalTo: photoLabel.bottomAnchor, constant: Constants.Spacing.small),
            photoScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            photoScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            photoScrollView.heightAnchor.constraint(equalToConstant: 100),
            
            photoStackView.topAnchor.constraint(equalTo: photoScrollView.topAnchor),
            photoStackView.leadingAnchor.constraint(equalTo: photoScrollView.leadingAnchor),
            photoStackView.trailingAnchor.constraint(equalTo: photoScrollView.trailingAnchor),
            photoStackView.bottomAnchor.constraint(equalTo: photoScrollView.bottomAnchor),
            photoStackView.heightAnchor.constraint(equalTo: photoScrollView.heightAnchor),
            
            addPhotoButton.widthAnchor.constraint(equalToConstant: 100),
            addPhotoButton.heightAnchor.constraint(equalToConstant: 100),
            
            // Move to Circle button
            moveToCircleButton.topAnchor.constraint(equalTo: photoScrollView.bottomAnchor, constant: Constants.Spacing.xlarge),
            moveToCircleButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Delete button
            deleteButton.topAnchor.constraint(equalTo: moveToCircleButton.bottomAnchor, constant: Constants.Spacing.medium),
            deleteButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Show current place location on map
        if let location = place.location?.clLocation {
            selectedLocation = location.coordinate
            
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            mapView.setRegion(region, animated: false)
            
            // Add annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = place.name
            mapView.addAnnotation(annotation)
        }
        
        // Add tap gesture recognizer to the map
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
    }
    
    private func setupActions() {
        // Add button actions
        useCurrentLocationButton.addTarget(self, action: #selector(useCurrentLocationButtonTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        moveToCircleButton.addTarget(self, action: #selector(moveToCircleButtonTapped), for: .touchUpInside)
        addPhotoButton.addTarget(self, action: #selector(addPhotoButtonTapped), for: .touchUpInside)
        
        // Add category change handler
        categorySegmentedControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func populateFields() {
        nameTextField.text = place.name
        descriptionTextView.text = place.description
        
        // Set category
        let categories = [PlaceCategory.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
        if let index = categories.firstIndex(of: place.category) {
            categorySegmentedControl.selectedSegmentIndex = index
        }
        
        // Set custom category if it's "Other"
        if place.category == .other {
            customCategoryTextField.text = place.customCategory
            customCategoryLabel.isHidden = false
            customCategoryTextField.isHidden = false
        }
        
        // Parse address
        let addressComponents = place.address.components(separatedBy: ", ")
        if addressComponents.count > 0 {
            streetTextField.text = addressComponents[0]
        }
        if addressComponents.count > 1 {
            cityTextField.text = addressComponents[1]
        }
        if addressComponents.count > 2 {
            stateTextField.text = addressComponents[2]
        }
        if addressComponents.count > 3 {
            zipCodeTextField.text = addressComponents[3]
        }
        if addressComponents.count > 4 {
            countryTextField.text = addressComponents[4]
        }
        
        // Set privacy
        let privacyOptions = [PlacePrivacy.followCirclePrivacy, .public, .myNetwork, .private]
        if let index = privacyOptions.firstIndex(of: place.privacy) {
            privacySegmentedControl.selectedSegmentIndex = index
        }
        
        notesTextView.text = place.notes
        
        // Tags
        if let tags = place.tags {
            tagsTextField.text = tags.joined(separator: ", ")
        }
        
        websiteTextField.text = place.website
        phoneTextField.text = place.phone
        
        // Load existing photos
        loadExistingPhotos()
    }
    
    // MARK: - Actions
    
    @objc private func categoryChanged() {
        let isOtherSelected = categorySegmentedControl.selectedSegmentIndex == 7 // "Other" is at index 7
        UIView.animate(withDuration: 0.3) {
            self.customCategoryLabel.isHidden = !isOtherSelected
            self.customCategoryTextField.isHidden = !isOtherSelected
        }
    }
    
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveButtonTapped() {
        // Validate required fields
        guard let name = nameTextField.text, !name.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a name for the place")
            return
        }
        
        // Check if any fields have changed
        let hasChanges = checkForChanges()
        
        guard hasChanges else {
            dismiss(animated: true)
            return
        }
        
        // Special handling for Home/Work places
        if place.id == "home-place" || place.id == "work-place" {
            saveHomeOrWorkPlace()
            return
        }
        
        // Get updated values
        let description = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : descriptionTextView.text
        
        // Get selected category
        let categoryIndex = categorySegmentedControl.selectedSegmentIndex
        let categories = [PlaceCategory.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
        let category = categories[categoryIndex]
        
        // Get custom category if "Other" is selected
        let customCategory: String? = category == .other ? customCategoryTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        
        // Format the address string
        let formattedAddress = [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        
        let address = formattedAddress.isEmpty ? nil : formattedAddress
        
        // Get optional fields
        let notes = notesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesTextView.text
        let website = websiteTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : websiteTextField.text
        let phone = phoneTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : phoneTextField.text
        
        // Get tags
        var tags: [String]?
        if let tagsText = tagsTextField.text, !tagsText.isEmpty {
            tags = tagsText.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        
        // Get privacy setting
        let privacyIndex = privacySegmentedControl.selectedSegmentIndex
        let privacyOptions = [PlacePrivacy.followCirclePrivacy, .public, .myNetwork, .private]
        let privacy = privacyOptions[privacyIndex]
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Updating Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Update place with photos (PlaceService handles upload internally)
        updatePlaceWithPhotos(
            name: name,
            description: description,
            address: address,
            category: category,
            customCategory: customCategory,
            privacy: privacy,
            website: website,
            phone: phone,
            tags: tags,
            photos: nil, // Not used anymore since we're using addPhotos/removePhotoUrls
            loadingAlert: loadingAlert
        )
    }
    
    @objc private func useCurrentLocationButtonTapped() {
        // Request location authorization if not already granted
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            showLocationPermissionAlert()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    @objc private func handleMapTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let touchPoint = gestureRecognizer.location(in: mapView)
        let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        
        // Store the selected location
        self.selectedLocation = coordinate
        
        // Clear existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add a new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Selected Location"
        mapView.addAnnotation(annotation)
        
        // Get address from coordinates
        lookUpCurrentLocation(coordinate) { [weak self] placemark in
            guard let self = self, let placemark = placemark else { return }
            
            DispatchQueue.main.async {
                self.updateAddressFields(with: placemark)
            }
        }
    }
    
    private func saveHomeOrWorkPlace() {
        // Format the address string
        let formattedAddress = [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        
        guard !formattedAddress.isEmpty else {
            presentAlert(title: "Error", message: "Please enter an address")
            return
        }
        
        // Save to UserDefaults
        let key = place.id == "home-place" ? "userHomeAddress" : "userWorkAddress"
        UserDefaults.standard.set(formattedAddress, forKey: key)
        
        // FIXME: Need to update this to handle Place creation properly
        // For now, just dismiss without updating since Place no longer has a direct initializer
        // This only affects local home/work places which are a special case
        dismiss(animated: true)
        
        /*
        // Create updated place object
        let updatedPlace = Place(
            id: place.id,
            name: nameTextField.text ?? place.name,
            description: descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : descriptionTextView.text,
            address: formattedAddress,
            location: place.location, // Keep existing location
            website: websiteTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : websiteTextField.text,
            phone: phoneTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true ? nil : phoneTextField.text,
            googlePlaceId: place.googlePlaceId,
            photos: place.photos,
            category: place.category,
            rating: place.rating,
            userRatingsTotal: place.userRatingsTotal,
            notes: notesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesTextView.text,
            privateNotes: place.privateNotes,
            publicNotes: place.publicNotes,
            tags: place.tags,
            reviews: place.reviews,
            openingHours: place.openingHours,
            priceLevel: place.priceLevel,
            circleId: place.circleId,
            addedBy: place.addedBy,
            addedByUser: place.addedByUser,
            privacy: place.privacy,
            createdAt: place.createdAt,
            updatedAt: Date()
        )
        
        // Notify delegate and dismiss
        delegate?.didUpdatePlace(updatedPlace)
        dismiss(animated: true)
        */
    }
    
    @objc private func moveToCircleButtonTapped() {
        let circleSelectionVC = CircleSelectionViewController(excludedCircleId: place.circleId)
        circleSelectionVC.delegate = self
        present(circleSelectionVC, animated: true)
    }
    
    @objc private func deleteButtonTapped() {
        // Special handling for Home/Work places
        if place.id == "home-place" || place.id == "work-place" {
            let alert = UIAlertController(
                title: "Clear \(place.name)",
                message: "Are you sure you want to clear your \(place.name.lowercased()) address?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
                self?.clearHomeOrWorkPlace()
            })
            
            present(alert, animated: true)
            return
        }
        
        let alert = UIAlertController(
            title: "Delete Place",
            message: "Are you sure you want to delete \(place.name)? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deletePlace()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func addPhotoButtonTapped() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 5 - (existingPhotoURLs.count + selectedImages.count)
        configuration.filter = .images
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // MARK: - Photo Methods
    
    private func updatePlaceWithPhotos(
        name: String,
        description: String?,
        address: String?,
        category: PlaceCategory,
        customCategory: String?,
        privacy: PlacePrivacy,
        website: String?,
        phone: String?,
        tags: [String]?,
        photos: [String]?,
        loadingAlert: UIAlertController
    ) {
        // Convert selected images to Data
        let photosData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        
        PlaceService.shared.updatePlace(
            id: place.id,
            name: name,
            description: description,
            address: address,
            category: category,
            customCategory: customCategory,
            privacy: privacy,
            website: website,
            phone: phone,
            tags: tags,
            addPhotos: photosData.isEmpty ? nil : photosData,
            removePhotoUrls: deletedPhotoURLs.isEmpty ? nil : deletedPhotoURLs
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        self?.delegate?.didUpdatePlace(updatedPlace)
                        self?.dismiss(animated: true)
                        
                    case .failure(let error):
                        self?.presentAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func loadExistingPhotos() {
        guard let photos = place.photos, !photos.isEmpty else { return }
        
        existingPhotoURLs = photos
        
        for (index, photoURL) in photos.enumerated() {
            let containerView = createPhotoImageView(tag: index)
            
            // Add to stack view before add button
            photoStackView.insertArrangedSubview(containerView, at: photoStackView.arrangedSubviews.count - 1)
            
            if let imageView = containerView.subviews.first(where: { $0 is UIImageView }) as? UIImageView {
                photoImageViews.append(imageView)
                
                // Load image from URL
                if let url = URL(string: photoURL) {
                    URLSession.shared.dataTask(with: url) { [weak imageView] data, _, _ in
                        if let data = data, let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                imageView?.image = image
                            }
                        }
                    }.resume()
                }
            }
        }
        
        // Update add button visibility
        updateAddPhotoButtonVisibility()
    }
    
    private func createPhotoImageView(tag: Int) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = UIColor.systemGray6
        imageView.tag = tag
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add remove button
        let removeButton = UIButton(type: .system)
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .white
        removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        removeButton.layer.cornerRadius = 12
        removeButton.tag = tag
        removeButton.addTarget(self, action: #selector(removePhotoTapped(_:)), for: .touchUpInside)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(imageView)
        containerView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 100),
            imageView.heightAnchor.constraint(equalToConstant: 100),
            
            removeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return containerView
    }
    
    @objc private func removePhotoTapped(_ sender: UIButton) {
        let index = sender.tag
        
        if index < existingPhotoURLs.count {
            // Removing existing photo
            let removedURL = existingPhotoURLs.remove(at: index)
            deletedPhotoURLs.append(removedURL)
        } else {
            // Removing newly selected photo
            let newPhotoIndex = index - existingPhotoURLs.count
            selectedImages.remove(at: newPhotoIndex)
        }
        
        // Remove from UI
        if let containerView = sender.superview {
            photoStackView.removeArrangedSubview(containerView)
            containerView.removeFromSuperview()
        }
        
        // Update photo image views array
        photoImageViews.remove(at: index)
        
        // Re-tag remaining photos
        for (newIndex, imageView) in photoImageViews.enumerated() {
            imageView.tag = newIndex
            if let removeButton = imageView.superview?.subviews.first(where: { $0 is UIButton }) as? UIButton {
                removeButton.tag = newIndex
            }
        }
        
        updateAddPhotoButtonVisibility()
    }
    
    private func updateAddPhotoButtonVisibility() {
        let totalPhotos = existingPhotoURLs.count + selectedImages.count
        addPhotoButton.isHidden = totalPhotos >= 5
    }
    
    // MARK: - Helper Methods
    
    private func checkForChanges() -> Bool {
        // Check name
        if nameTextField.text != place.name { return true }
        
        // Check description
        let currentDescription = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDescription = place.description ?? ""
        if currentDescription != originalDescription { return true }
        
        // Check category
        let categoryIndex = categorySegmentedControl.selectedSegmentIndex
        let categories = [PlaceCategory.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
        if categories[categoryIndex] != place.category { return true }
        
        // Check custom category if "Other" is selected
        if place.category == .other {
            let currentCustomCategory = customCategoryTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let originalCustomCategory = place.customCategory ?? ""
            if currentCustomCategory != originalCustomCategory { return true }
        }
        
        // Check address
        let formattedAddress = [streetTextField.text, cityTextField.text, stateTextField.text, zipCodeTextField.text, countryTextField.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if formattedAddress != place.address { return true }
        
        // Check privacy
        let privacyIndex = privacySegmentedControl.selectedSegmentIndex
        let privacyOptions = [PlacePrivacy.followCirclePrivacy, .public, .myNetwork, .private]
        if privacyOptions[privacyIndex] != place.privacy { return true }
        
        // Check notes
        let currentNotes = notesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalNotes = place.notes ?? ""
        if currentNotes != originalNotes { return true }
        
        // Check tags
        let currentTags = tagsTextField.text?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
        let originalTags = place.tags ?? []
        if currentTags != originalTags { return true }
        
        // Check website
        let currentWebsite = websiteTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalWebsite = place.website ?? ""
        if currentWebsite != originalWebsite { return true }
        
        // Check phone
        let currentPhone = phoneTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalPhone = place.phone ?? ""
        if currentPhone != originalPhone { return true }
        
        // Check photos
        if !selectedImages.isEmpty || !deletedPhotoURLs.isEmpty { return true }
        
        return false
    }
    
    private func clearHomeOrWorkPlace() {
        // Clear from UserDefaults
        let key = place.id == "home-place" ? "userHomeAddress" : "userWorkAddress"
        UserDefaults.standard.removeObject(forKey: key)
        
        // Notify delegate and dismiss
        delegate?.didDeletePlace(place.id)
        dismiss(animated: true)
    }
    
    private func deletePlace() {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Deleting Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.deletePlace(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(_):
                        self?.delegate?.didDeletePlace(self?.place.id ?? "")
                        self?.dismiss(animated: true)
                        
                    case .failure(let error):
                        self?.presentAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func showLocationPermissionAlert() {
        let alert = UIAlertController(
            title: "Location Access Required",
            message: "Please allow access to your location in Settings to use this feature.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func lookUpCurrentLocation(_ coordinate: CLLocationCoordinate2D, completionHandler: @escaping (CLPlacemark?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if error == nil {
                let placemark = placemarks?[0]
                completionHandler(placemark)
            } else {
                completionHandler(nil)
            }
        }
    }
    
    private func updateAddressFields(with placemark: CLPlacemark) {
        streetTextField.text = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        cityTextField.text = placemark.locality
        stateTextField.text = placemark.administrativeArea
        zipCodeTextField.text = placemark.postalCode
        countryTextField.text = placemark.country
    }
    
    private func presentAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alertController, animated: true)
    }
}

// MARK: - CLLocationManagerDelegate

// MARK: - PHPickerViewControllerDelegate

extension EditPlaceViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        for result in results {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.addSelectedPhoto(image)
                    }
                }
            }
        }
    }
    
    private func addSelectedPhoto(_ image: UIImage) {
        selectedImages.append(image)
        
        let tag = existingPhotoURLs.count + selectedImages.count - 1
        let containerView = createPhotoImageView(tag: tag)
        if let imageView = containerView.subviews.first(where: { $0 is UIImageView }) as? UIImageView {
            imageView.image = image
            photoImageViews.append(imageView)
        }
        
        // Add to stack view before add button
        photoStackView.insertArrangedSubview(containerView, at: photoStackView.arrangedSubviews.count - 1)
        
        updateAddPhotoButtonVisibility()
        
        // Scroll to show new photo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.photoScrollView.scrollRectToVisible(containerView.frame, animated: true)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension EditPlaceViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Stop updating location
        manager.stopUpdatingLocation()
        
        // Store user's location
        self.selectedLocation = location.coordinate
        
        // Center map on user's location
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: true)
        
        // Clear existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add a new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = location.coordinate
        annotation.title = "Current Location"
        mapView.addAnnotation(annotation)
        
        // Get address from coordinates
        lookUpCurrentLocation(location.coordinate) { [weak self] placemark in
            guard let self = self, let placemark = placemark else { return }
            
            DispatchQueue.main.async {
                self.updateAddressFields(with: placemark)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        default:
            break
        }
    }
}

// MARK: - CircleSelectionDelegate

extension EditPlaceViewController: CircleSelectionDelegate {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Moving Place", message: "Moving \(place.name) to \(circle.name)...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Perform the move
        PlaceService.shared.movePlaceToCircle(placeId: place.id, targetCircleId: circle.id) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedPlace):
                        // Update the local place object
                        self.place = updatedPlace
                        
                        // Notify delegate about the update
                        self.delegate?.didUpdatePlace(updatedPlace)
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(self.place.name) has been moved to \(circle.name)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                            self.dismiss(animated: true)
                        })
                        self.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to move place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController) {
        // User cancelled, nothing to do
    }
}
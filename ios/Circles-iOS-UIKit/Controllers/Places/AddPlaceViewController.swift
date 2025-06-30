import UIKit
import GoogleMaps
import GooglePlaces
import CoreLocation
import MapKit
import PhotosUI

protocol PlaceSearchDelegate: AnyObject {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?)
}

class AddPlaceViewController: UIViewController, CategoryPickerDelegate {
    
    // MARK: - Properties
    private let circleId: String
    private let locationManager = CLLocationManager()
    private var userLocation: CLLocation?
    private var selectedLocation: CLLocationCoordinate2D?
    private var searchResults: [GMSAutocompletePrediction] = []
    private var selectedPlace: GMSPlace?
    private var markers: [GMSMarker] = []
    private var placesClient: GMSPlacesClient!
    private var selectedMapItem: MKMapItem?
    private var sessionToken: GMSAutocompleteSessionToken?
    private var mapItemsByCoordinate: [String: MKMapItem] = [:]
    private var markerToPlaceIdMap: [GMSMarker: String] = [:]
    private var placeIdsByCoordinate: [String: String] = [:] // Additional storage by coordinate
    private var selectedCategory: PlaceCategory = .restaurant
    private var selectedSubcategory: String?
    private var selectedGooglePlaceDetails: GooglePlaceDetails?
    private var isCategoryDropdownVisible = false
    private var categoryDropdownItems: [(category: PlaceCategory, subcategory: String?)] = []
    private var searchTimer: Timer?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Hint label
    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "Search for a place, select a category, or tap markers on the map"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Search container for visual emphasis
    private let searchContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Search bar at the top
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "🔍 Search address or place name"
        searchBar.searchBarStyle = .minimal
        searchBar.searchTextField.backgroundColor = .clear
        searchBar.searchTextField.textColor = .darkGray
        searchBar.searchTextField.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        searchBar.tintColor = UIColor.systemBlue
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    // Map container for rounded corners
    private let mapContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Map view that shows immediately
    private let mapView: GMSMapView = {
        let camera = GMSCameraPosition.camera(withLatitude: 40.7128, longitude: -74.0060, zoom: 12.0)
        let mapView = GMSMapView.map(withFrame: .zero, camera: camera)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.tiltGestures = true
        mapView.settings.rotateGestures = true
        mapView.isMyLocationEnabled = true
        return mapView
    }()
    
    // Category buttons scroll view
    private let categoryScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        return scrollView
    }()
    
    private let categoryStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    // Search results overlay
    private let searchResultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.layer.cornerRadius = 12
        tableView.layer.shadowColor = UIColor.black.cgColor
        tableView.layer.shadowOpacity = 0.15
        tableView.layer.shadowOffset = CGSize(width: 0, height: 2)
        tableView.layer.shadowRadius = 8
        tableView.isHidden = true
        return tableView
    }()
    
    // Manual entry toggle
    private let manualEntryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Can't find it? Add manually", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.setTitleColor(UIColor.systemBlue, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Form fields container
    private let formContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "Place Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter a name for this place"
        textField.borderStyle = .none
        textField.backgroundColor = .white
        textField.textColor = .darkGray
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        textField.rightViewMode = .always
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Category"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        button.contentHorizontalAlignment = .left
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Set default category
        button.setTitle("Restaurant", for: .normal)
        button.setTitleColor(.darkGray, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        
        // Add chevron icon
        let chevronImage = UIImage(systemName: "chevron.down")
        button.setImage(chevronImage, for: .normal)
        button.tintColor = .systemBlue
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        
        return button
    }()
    
    private let categoryDropdownTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .systemBackground
        tableView.layer.cornerRadius = 8
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        tableView.layer.shadowColor = UIColor.label.cgColor
        tableView.layer.shadowOpacity = 0.2
        tableView.layer.shadowOffset = CGSize(width: 0, height: 4)
        tableView.layer.shadowRadius = 8
        tableView.translatesAutoresizingMaskIntoConstraints = true  // Use manual layout
        tableView.isHidden = true
        tableView.alpha = 0
        tableView.clipsToBounds = false
        tableView.layer.masksToBounds = false
        return tableView
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Description"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .white
        textView.textColor = .darkGray
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.text = "Address"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .white
        textView.textColor = .darkGray
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Privacy"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacySegmentedControl: UISegmentedControl = {
        let items = ["Follow Circle", "Private"]
        let segmentedControl = UISegmentedControl(items: items)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = UIColor.systemBlue
        segmentedControl.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        segmentedControl.setTitleTextAttributes([
            NSAttributedString.Key.foregroundColor: UIColor.darkGray
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            NSAttributedString.Key.foregroundColor: UIColor.white
        ], for: .selected)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    // Photo selection elements
    private let photoLabel: UILabel = {
        let label = UILabel()
        label.text = "Photo"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.systemGray6
        imageView.layer.cornerRadius = 8
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()
    
    private let addPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add Photo", for: .normal)
        button.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let removePhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .systemRed
        button.backgroundColor = .white
        button.layer.cornerRadius = 15
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private var selectedImage: UIImage?
    
    private let addPlaceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add Place", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    
    init(circleId: String) {
        self.circleId = circleId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("AddPlaceViewController loaded - Google Places integration active")
        
        setupUI()
        setupMap()
        setupSearchCompleter()
        setupActions()
        
        // Build comprehensive category list with subcategories
        setupCategoryDropdownItems()
        
        // Set up category dropdown
        categoryDropdownTableView.delegate = self
        categoryDropdownTableView.dataSource = self
        categoryDropdownTableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        categoryDropdownTableView.rowHeight = 44
        categoryDropdownTableView.separatorInset = UIEdgeInsets(top: 0, left: 50, bottom: 0, right: 0)
        
        // Add tap gesture to dismiss dropdown
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissCategoryDropdown))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        // Set initial map region to NYC to prevent black screen
        let initialLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // New York City
        let camera = GMSCameraPosition.camera(withTarget: initialLocation, zoom: 12.0)
        mapView.animate(to: camera)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Force map to render properly
        mapView.setNeedsDisplay()
        
        // Check current authorization status
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, start updating location
            locationManager.startUpdatingLocation()
        case .notDetermined:
            // Request permission
            locationManager.requestWhenInUseAuthorization()
        default:
            // Denied or restricted
            // Don't set a specific location - just leave the map gray
            break
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemGray6
        title = "Add Place"
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(hintLabel)
        contentView.addSubview(searchContainer)
        searchContainer.addSubview(searchBar)
        contentView.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)
        contentView.addSubview(mapContainer)
        mapContainer.addSubview(mapView)
        contentView.addSubview(manualEntryButton)
        contentView.addSubview(formContainer)
        contentView.addSubview(addPlaceButton)
        
        // Add search results overlay on top
        view.addSubview(searchResultsTableView)
        
        // Add form fields
        formContainer.addSubview(nameLabel)
        formContainer.addSubview(nameTextField)
        formContainer.addSubview(photoLabel)
        formContainer.addSubview(photoImageView)
        formContainer.addSubview(addPhotoButton)
        formContainer.addSubview(removePhotoButton)
        formContainer.addSubview(categoryLabel)
        formContainer.addSubview(categoryButton)
        // Don't add dropdown to formContainer - will add to main view later
        formContainer.addSubview(descriptionLabel)
        formContainer.addSubview(descriptionTextView)
        formContainer.addSubview(addressLabel)
        formContainer.addSubview(addressTextView)
        formContainer.addSubview(privacyLabel)
        formContainer.addSubview(privacySegmentedControl)
        
        // Layout
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
            
            // Hint label
            hintLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Search container at top
            searchContainer.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: Constants.Spacing.small),
            searchContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            searchContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            searchContainer.heightAnchor.constraint(equalToConstant: 56),
            
            // Search bar inside container
            searchBar.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            
            // Category scroll view
            categoryScrollView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: Constants.Spacing.small),
            categoryScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            categoryScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            categoryScrollView.heightAnchor.constraint(equalToConstant: 36),
            
            // Category stack view
            categoryStackView.topAnchor.constraint(equalTo: categoryScrollView.topAnchor),
            categoryStackView.leadingAnchor.constraint(equalTo: categoryScrollView.leadingAnchor),
            categoryStackView.trailingAnchor.constraint(equalTo: categoryScrollView.trailingAnchor),
            categoryStackView.bottomAnchor.constraint(equalTo: categoryScrollView.bottomAnchor),
            categoryStackView.heightAnchor.constraint(equalTo: categoryScrollView.heightAnchor),
            
            // Map container
            mapContainer.topAnchor.constraint(equalTo: categoryScrollView.bottomAnchor, constant: Constants.Spacing.small),
            mapContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            mapContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            mapContainer.heightAnchor.constraint(equalToConstant: 300),
            
            // Map view inside container
            mapView.topAnchor.constraint(equalTo: mapContainer.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: mapContainer.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor),
            
            // Manual entry button
            manualEntryButton.topAnchor.constraint(equalTo: mapContainer.bottomAnchor, constant: Constants.Spacing.small),
            manualEntryButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Form container
            formContainer.topAnchor.constraint(equalTo: manualEntryButton.bottomAnchor, constant: Constants.Spacing.medium),
            formContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Form fields
            nameLabel.topAnchor.constraint(equalTo: formContainer.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            nameTextField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            nameTextField.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            nameTextField.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            nameTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Photo UI (moved after name field)
            photoLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            photoLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            addPhotoButton.topAnchor.constraint(equalTo: photoLabel.bottomAnchor, constant: Constants.Spacing.small),
            addPhotoButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            addPhotoButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            addPhotoButton.heightAnchor.constraint(equalToConstant: 100),
            
            photoImageView.topAnchor.constraint(equalTo: photoLabel.bottomAnchor, constant: Constants.Spacing.small),
            photoImageView.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            photoImageView.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            photoImageView.heightAnchor.constraint(equalToConstant: 200),
            
            removePhotoButton.topAnchor.constraint(equalTo: photoImageView.topAnchor, constant: 8),
            removePhotoButton.trailingAnchor.constraint(equalTo: photoImageView.trailingAnchor, constant: -8),
            removePhotoButton.widthAnchor.constraint(equalToConstant: 30),
            removePhotoButton.heightAnchor.constraint(equalToConstant: 30),
            
            categoryLabel.topAnchor.constraint(equalTo: addPhotoButton.bottomAnchor, constant: Constants.Spacing.medium),
            categoryLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            categoryButton.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            categoryButton.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            categoryButton.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            categoryButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Note: categoryDropdownTableView constraints are set up separately after all other constraints
            
            descriptionLabel.topAnchor.constraint(equalTo: categoryButton.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            descriptionTextView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            descriptionTextView.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            descriptionTextView.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 80),
            
            addressLabel.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: Constants.Spacing.medium),
            addressLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            addressTextView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.small),
            addressTextView.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            addressTextView.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            addressTextView.heightAnchor.constraint(equalToConstant: 60),
            
            privacyLabel.topAnchor.constraint(equalTo: addressTextView.bottomAnchor, constant: Constants.Spacing.medium),
            privacyLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            privacySegmentedControl.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: Constants.Spacing.small),
            privacySegmentedControl.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            privacySegmentedControl.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            
            privacySegmentedControl.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor),
            
            // Add place button
            addPlaceButton.topAnchor.constraint(equalTo: formContainer.bottomAnchor, constant: Constants.Spacing.large),
            addPlaceButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            addPlaceButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            addPlaceButton.heightAnchor.constraint(equalToConstant: 50),
            addPlaceButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large),
            
            // Search results overlay
            searchResultsTableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 4),
            searchResultsTableView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            searchResultsTableView.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            searchResultsTableView.heightAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
        
        // Initially hide form until a place is selected
        formContainer.alpha = 0.3
        formContainer.isUserInteractionEnabled = false
        addPlaceButton.isEnabled = false
        addPlaceButton.alpha = 0.3
        
        // Ensure all form fields have default alpha
        nameTextField.alpha = 1.0
        descriptionTextView.alpha = 1.0
        addressTextView.alpha = 1.0
        categoryButton.alpha = 1.0
        
        // Setup category buttons
        setupCategoryButtons()
        
        // Add dropdown to main view last to ensure it's on top
        view.addSubview(categoryDropdownTableView)
        view.bringSubviewToFront(categoryDropdownTableView)
    }
    
    private func setupCategoryButtons() {
        let categories = [
            ("🍽", "Restaurants"),
            ("☕️", "Coffee"),
            ("🏨", "Hotels"),
            ("⛽️", "Gas"),
            ("🛒", "Groceries"),
            ("🏞", "Parks"),
            ("🍺", "Bars"),
            ("🛍", "Shopping"),
            ("💊", "Pharmacy"),
            ("🏦", "Banks")
        ]
        
        for (emoji, title) in categories {
            let button = UIButton(type: .system)
            button.setTitle("\(emoji) \(title)", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            button.backgroundColor = .white
            button.setTitleColor(UIColor.systemBlue, for: .normal)
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.1
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.layer.shadowRadius = 2
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            button.addTarget(self, action: #selector(searchCategoryButtonTapped(_:)), for: .touchUpInside)
            
            categoryStackView.addArrangedSubview(button)
        }
    }
    
    private func setupMap() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Map delegate - this will handle all map interactions
        mapView.delegate = self
        
        // Note: We're using GMSMapViewDelegate's didTapAt method instead of a gesture recognizer
        // to avoid conflicts with Google Maps' built-in gesture handling
    }
    
    private func setupSearchCompleter() {
        placesClient = GMSPlacesClient.shared()
        sessionToken = GMSAutocompleteSessionToken.init()
        
        // Table view setup
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        // Don't register cell - we'll create subtitle cells manually
        searchResultsTableView.rowHeight = UITableView.automaticDimension
        searchResultsTableView.estimatedRowHeight = 60
        
        // Search bar delegate
        searchBar.delegate = self
    }
    
    private func setupActions() {
        addPlaceButton.addTarget(self, action: #selector(addPlaceButtonTapped), for: .touchUpInside)
        manualEntryButton.addTarget(self, action: #selector(manualEntryButtonTapped), for: .touchUpInside)
        addPhotoButton.addTarget(self, action: #selector(addPhotoButtonTapped), for: .touchUpInside)
        removePhotoButton.addTarget(self, action: #selector(removePhotoButtonTapped), for: .touchUpInside)
        categoryButton.addTarget(self, action: #selector(categoryButtonTapped), for: .touchUpInside)
    }
    
    private func setupCategoryDropdownItems() {
        categoryDropdownItems = []
        
        // Show only parent categories in the dropdown
        // Most common categories first
        let priorityCategories: [PlaceCategory] = [
            .restaurant, .cafe, .bar, .retail, .service, 
            .fitness, .healthcare, .entertainment
        ]
        
        // Add priority categories first
        for category in priorityCategories {
            categoryDropdownItems.append((category: category, subcategory: nil))
        }
        
        // Add a special "More..." option - using .other as a placeholder
        categoryDropdownItems.append((category: .other, subcategory: "More..."))
    }
    
    
    // MARK: - Actions
    
    
    private func handleMapTapAtCoordinate(_ coordinate: CLLocationCoordinate2D) {
        
        // Remove any existing "Selected Location" markers
        for marker in markers {
            if marker.title == "Selected Location" {
                marker.map = nil
            }
        }
        markers.removeAll { $0.title == "Selected Location" }
        
        // Add new marker
        let marker = GMSMarker()
        marker.position = coordinate
        marker.title = "Selected Location"
        marker.snippet = "Tap here to add this place"
        
        // Customize the selected location marker
        marker.icon = GMSMarker.markerImage(with: .systemGreen)
        marker.appearAnimation = .pop
        
        marker.map = mapView
        markers.append(marker)
        
        // Reverse geocode to get address
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else { return }
            
            DispatchQueue.main.async {
                // Enable manual entry
                self.enableManualEntry()
                
                // Clear form for manual entry
                self.nameTextField.text = ""
                self.descriptionTextView.text = ""
                
                // Clear any Google Place details since this is manual
                self.selectedGooglePlaceDetails = nil
                
                // Fill in address
                let address = [
                    placemark.subThoroughfare,
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                
                self.addressTextView.text = address
                self.selectedLocation = coordinate
            }
        }
    }
    
    @objc private func manualEntryButtonTapped() {
        // Clear any selected Google Place when manually entering
        selectedGooglePlaceDetails = nil
        enableManualEntry()
        nameTextField.becomeFirstResponder()
    }
    
    @objc private func addPhotoButtonTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func removePhotoButtonTapped() {
        selectedImage = nil
        photoImageView.image = nil
        photoImageView.isHidden = true
        removePhotoButton.isHidden = true
        addPhotoButton.isHidden = false
        
        // Update constraint for form container bottom
        NSLayoutConstraint.activate([
            addPhotoButton.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor)
        ])
    }
    
    @objc private func categoryButtonTapped() {
        isCategoryDropdownVisible.toggle()
        
        if isCategoryDropdownVisible {
            // Position dropdown below button
            let buttonFrame = categoryButton.convert(categoryButton.bounds, to: view)
            
            // Calculate available space below button
            let availableHeight = view.frame.height - buttonFrame.maxY - 20
            let dropdownHeight = min(300, availableHeight)
            
            categoryDropdownTableView.frame = CGRect(
                x: Constants.Spacing.large,
                y: buttonFrame.maxY + 4,
                width: view.frame.width - (Constants.Spacing.large * 2),
                height: dropdownHeight
            )
            
            // Ensure it's on top
            view.bringSubviewToFront(categoryDropdownTableView)
            categoryDropdownTableView.reloadData()
            
            // Set proper layer properties for visibility
            categoryDropdownTableView.layer.zPosition = 999
        }
        
        UIView.animate(withDuration: 0.3) {
            self.categoryDropdownTableView.isHidden = !self.isCategoryDropdownVisible
            self.categoryDropdownTableView.alpha = self.isCategoryDropdownVisible ? 1.0 : 0.0
            
            // Rotate chevron
            if self.isCategoryDropdownVisible {
                self.categoryButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi)
            } else {
                self.categoryButton.imageView?.transform = .identity
            }
        }
    }
    
    @objc private func dismissCategoryDropdown() {
        if isCategoryDropdownVisible {
            isCategoryDropdownVisible = false
            UIView.animate(withDuration: 0.3) {
                self.categoryDropdownTableView.isHidden = true
                self.categoryDropdownTableView.alpha = 0.0
                self.categoryButton.imageView?.transform = .identity
            }
        }
    }
    
    @objc private func searchCategoryButtonTapped(_ sender: UIButton) {
        guard let buttonTitle = sender.title(for: .normal) else { return }
        
        // Extract the category name (remove emoji and trim)
        let category = buttonTitle.components(separatedBy: " ").dropFirst().joined(separator: " ")
        
        print("Category button tapped: \(category)")
        
        // Clear search bar
        searchBar.text = ""
        searchResultsTableView.isHidden = true
        
        // Search for this category
        searchForCategory(category)
    }
    
    @objc private func addPlaceButtonTapped() {
        guard let name = nameTextField.text, !name.isEmpty,
              let address = addressTextView.text, !address.isEmpty else {
            presentAlert(title: "Error", message: "Please provide a name and address")
            return
        }
        
        let category = selectedCategory
        
        // Get custom category if "Other" is selected
        let customCategory: String? = (category == .other && selectedSubcategory != nil) ? selectedSubcategory : nil
        let subcategory: String? = (category != .other) ? selectedSubcategory : nil
        
        let description = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get privacy setting from segmented control
        let privacy: PlacePrivacy = privacySegmentedControl.selectedSegmentIndex == 0 ? .followCirclePrivacy : .private
        
        // First check for duplicates
        let checkingAlert = UIAlertController(title: "Checking...", message: "Verifying place doesn't already exist", preferredStyle: .alert)
        present(checkingAlert, animated: true)
        
        // Check for duplicate places
        checkForDuplicatePlace(name: name, address: address, googlePlaceId: selectedGooglePlaceDetails?.placeID) { [weak self] duplicatePlace, duplicateCircle in
            DispatchQueue.main.async {
                checkingAlert.dismiss(animated: true) {
                    if let duplicate = duplicatePlace, let circle = duplicateCircle {
                        // Show alert about duplicate
                        let alert = UIAlertController(
                            title: "Place Already Exists",
                            message: "You already have \"\(duplicate.name)\" in your \"\(circle.name)\" circle. Would you like to view it?",
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "View Place", style: .default) { _ in
                            // Navigate to the place detail
                            self?.navigationController?.popViewController(animated: false)
                            NotificationCenter.default.post(
                                name: Notification.Name("ShowPlaceDetails"),
                                object: nil,
                                userInfo: ["place": duplicate]
                            )
                        })
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        
                        self?.present(alert, animated: true)
                    } else {
                        // No duplicate found, proceed with creation
                        self?.proceedWithPlaceCreation(
                            name: name,
                            address: address,
                            description: description,
                            category: category,
                            customCategory: customCategory,
                            subcategory: subcategory,
                            privacy: privacy
                        )
                    }
                }
            }
        }
    }
    
    private func checkForDuplicatePlace(name: String, address: String, googlePlaceId: String?, completion: @escaping (Place?, Circle?) -> Void) {
        // Get all circles for the user
        CircleService.shared.fetchUserCircles { result in
            switch result {
            case .success(let circles):
                let group = DispatchGroup()
                var duplicatePlace: Place?
                var duplicateCircle: Circle?
                
                // Check each circle for places
                for circle in circles {
                    group.enter()
                    PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { placeResult in
                        defer { group.leave() }
                        
                        if case .success(let places) = placeResult {
                            // Check for duplicate by googlePlaceId first (most accurate)
                            if let googleId = googlePlaceId, !googleId.isEmpty {
                                if let match = places.first(where: { $0.googlePlaceId == googleId }) {
                                    duplicatePlace = match
                                    duplicateCircle = circle
                                    return
                                }
                            }
                            
                            // Check by name and address similarity
                            for place in places {
                                // Exact name match
                                if place.name.lowercased() == name.lowercased() {
                                    // Check if addresses are similar
                                    let placeAddressLower = place.address.lowercased()
                                    let newAddressLower = address.lowercased()
                                    
                                    // Simple similarity check - if addresses share significant components
                                    let placeComponents = placeAddressLower.components(separatedBy: CharacterSet(charactersIn: ", "))
                                    let newComponents = newAddressLower.components(separatedBy: CharacterSet(charactersIn: ", "))
                                    
                                    let commonComponents = placeComponents.filter { component in
                                        newComponents.contains { $0.contains(component) || component.contains($0) }
                                    }
                                    
                                    // If at least 2 address components match, consider it a duplicate
                                    if commonComponents.count >= 2 {
                                        duplicatePlace = place
                                        duplicateCircle = circle
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    completion(duplicatePlace, duplicateCircle)
                }
                
            case .failure:
                // If we can't check for duplicates, allow creation
                completion(nil, nil)
            }
        }
    }
    
    private func proceedWithPlaceCreation(name: String, address: String, description: String, 
                                        category: PlaceCategory, customCategory: String?, 
                                        subcategory: String?, privacy: PlacePrivacy) {
        // Create place
        let loadingAlert = UIAlertController(title: "Creating Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Prepare photo data if available
        var photoData: [Data]? = nil
        if let image = selectedImage {
            // Very aggressive image resizing for reliability
            let maxSize: CGFloat = 500 // Much smaller max dimension
            var finalImage = image
            
            // Always resize to reduce memory usage
            let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0) // Never upscale
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            // Use lower scale for retina optimization (1.0 instead of screen scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0) // true = opaque for smaller size
            // Fill with white background for JPEG
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: newSize))
            image.draw(in: CGRect(origin: .zero, size: newSize))
            
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                finalImage = resizedImage
            }
            UIGraphicsEndImageContext()
            
            // Use low quality JPEG compression
            let compressionQuality: CGFloat = 0.4 // Low quality is fine for place photos
            
            if let imageData = finalImage.jpegData(compressionQuality: compressionQuality) {
                let sizeInKB = Double(imageData.count) / 1024.0
                print("📸 Image compressed to \(String(format: "%.0f", sizeInKB)) KB (quality: \(compressionQuality))")
                
                // Only proceed if under 500KB
                if sizeInKB < 500 {
                    photoData = [imageData]
                    print("✅ Photo ready for upload")
                } else {
                    // Try one more time with even lower quality
                    if let tinyImageData = finalImage.jpegData(compressionQuality: 0.2) {
                        let tinySizeInKB = Double(tinyImageData.count) / 1024.0
                        print("📸 Further compressed to \(String(format: "%.0f", tinySizeInKB)) KB")
                        photoData = [tinyImageData]
                    }
                }
            } else {
                print("⚠️ Failed to prepare photo for upload")
            }
        }
        
        // Check if we have Google Place details to use
        if let googleDetails = selectedGooglePlaceDetails {
            // Create place data from Google details
            var placeData: [String: Any] = [
                "name": name,
                "address": address,
                "circleId": circleId,
                "category": category.rawValue,
                "privacy": privacy.rawValue,
                "location": [
                    "type": "Point",
                    "coordinates": [googleDetails.coordinate.longitude, googleDetails.coordinate.latitude]
                ]
            ]
            
            // Add Google-specific data
            if !googleDetails.placeID.isEmpty {
                placeData["googlePlaceId"] = googleDetails.placeID
            }
            if let rating = googleDetails.rating, rating > 0 {
                placeData["rating"] = rating
            }
            if googleDetails.userRatingsTotal > 0 {
                placeData["userRatingsTotal"] = googleDetails.userRatingsTotal
            }
            if let website = googleDetails.website {
                placeData["website"] = website.absoluteString
            }
            if let phone = googleDetails.phoneNumber {
                placeData["phone"] = phone
            }
            if let priceLevel = googleDetails.priceLevel {
                placeData["priceLevel"] = priceLevel.rawValue
            }
            if !description.isEmpty {
                placeData["description"] = description
            }
            if let customCategory = customCategory {
                placeData["customCategory"] = customCategory
            }
            if let subcategory = subcategory {
                placeData["subcategory"] = subcategory
            }
            
            // Handle photos
            if let imageData = photoData?.first {
                PlaceService.shared.uploadMultipleImages([imageData]) { uploadResult in
                    DispatchQueue.main.async {
                        switch uploadResult {
                        case .success(let imageUrls):
                            placeData["photos"] = imageUrls
                            self.createPlaceWithData(placeData, loadingAlert: loadingAlert)
                        case .failure(let error):
                            print("❌ Failed to upload photo: \(error)")
                            // Show error but continue without photo
                            loadingAlert.dismiss(animated: true) {
                                let alert = UIAlertController(title: "Photo Upload Failed", 
                                                            message: "The place will be created without the photo. Error: \(error.localizedDescription)", 
                                                            preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                                    // Re-show loading and create without photo
                                    self.present(loadingAlert, animated: true)
                                    self.createPlaceWithData(placeData, loadingAlert: loadingAlert)
                                })
                                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                self.present(alert, animated: true)
                            }
                        }
                    }
                }
            } else {
                self.createPlaceWithData(placeData, loadingAlert: loadingAlert)
            }
        } else {
            // No Google details, create place normally
            PlaceService.shared.createPlace(
                name: name,
                description: description.isEmpty ? nil : description,
                address: address,
                category: category,
                customCategory: customCategory,
                subcategory: subcategory,
                circleId: circleId,
                privacy: privacy,
                website: nil,
                phone: nil,
                tags: nil,
                photos: photoData
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let place):
                            print("✅ Place created successfully with photos: \(place.photos ?? [])")
                            self?.presentAlert(title: "Success", message: "Place added successfully") { _ in
                                self?.navigationController?.popViewController(animated: true)
                            }
                        case .failure(let error):
                            print("❌ Failed to create place: \(error)")
                            self?.presentAlert(title: "Error", message: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
    
    private func createPlaceWithData(_ placeData: [String: Any], loadingAlert: UIAlertController) {
        PlaceService.shared.createPlaceFromGoogleData(placeData) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        print("✅ Place created successfully with rating: \(place.rating ?? 0)")
                        self?.presentAlert(title: "Success", message: "Place added successfully") { _ in
                            self?.navigationController?.popViewController(animated: true)
                        }
                    case .failure(let error):
                        print("❌ Failed to create place: \(error)")
                        self?.presentAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func enableManualEntry() {
        UIView.animate(withDuration: 0.3) {
            self.formContainer.alpha = 1.0
            self.formContainer.isUserInteractionEnabled = true
            self.addPlaceButton.isEnabled = true
            self.addPlaceButton.alpha = 1.0
            self.hintLabel.alpha = 0
        } completion: { _ in
            // Scroll to show the form
            let formRect = self.formContainer.convert(self.formContainer.bounds, to: self.scrollView)
            self.scrollView.scrollRectToVisible(formRect, animated: true)
        }
    }
    
    private func selectSearchResult(_ result: GMSAutocompletePrediction) {
        // Hide search results
        searchResultsTableView.isHidden = true
        searchBar.resignFirstResponder()
        searchBar.text = result.attributedPrimaryText.string
        
        // Load and fill the form with place details
        loadAndFillFormWithGooglePlace(placeId: result.placeID, markerTitle: result.attributedPrimaryText.string)
    }
    
    private func fillFormWithMapItem(_ mapItem: MKMapItem) {
        selectedMapItem = mapItem
        selectedGooglePlaceDetails = nil // Clear Google details
        
        // Enable form first
        enableManualEntry()
        
        // Add a small delay to ensure the form is visible before populating
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if this is likely a residential address (no business name)
            let isResidentialAddress = mapItem.name == nil || mapItem.name?.isEmpty == true || 
                                     mapItem.pointOfInterestCategory == nil
            
            if isResidentialAddress {
                // For addresses, clear the name field so user must enter their own
                self.nameTextField.text = ""
                self.nameTextField.placeholder = "Enter a name for this place (e.g., \"Dad's House\")"
            } else {
                // For businesses, pre-fill with the business name
                self.nameTextField.text = mapItem.name ?? ""
            }
            
            // Fill address
            let placemark = mapItem.placemark
            let address = [
                placemark.subThoroughfare,
                placemark.thoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.postalCode,
                placemark.country
            ].compactMap { $0 }.joined(separator: ", ")
            
            self.addressTextView.text = address
            
            // Generate enhanced description
            var description = ""
            if let poiCategory = mapItem.pointOfInterestCategory {
                description = self.getCategoryDescription(for: poiCategory)
            }
            
            // Add location context if available
            if let locality = placemark.locality {
                if !description.isEmpty {
                    description += " in \(locality)"
                } else {
                    description = "Located in \(locality)"
                }
            }
            
            // Add phone number to description if available
            if let phone = mapItem.phoneNumber {
                description += "\nPhone: \(phone)"
            }
            
            // Add website to description if available
            if let url = mapItem.url {
                description += "\nWebsite: \(url.absoluteString)"
            }
            
            self.descriptionTextView.text = description
            
            // Set category
            self.selectedSubcategory = nil
            
            if let poiCategory = mapItem.pointOfInterestCategory {
                switch poiCategory {
                case .restaurant: 
                    self.selectedCategory = .restaurant
                case .cafe: 
                    self.selectedCategory = .cafe
                    self.selectedSubcategory = "Coffee Shop"
                case .nightlife: 
                    self.selectedCategory = .bar
                    self.selectedSubcategory = "Nightclub"
                case .brewery: 
                    self.selectedCategory = .bar
                    self.selectedSubcategory = "Brewery"
                case .winery: 
                    self.selectedCategory = .bar
                    self.selectedSubcategory = "Wine Bar"
                case .hotel, .campground: 
                    self.selectedCategory = .hotel
                case .store: 
                    self.selectedCategory = .retail
                case .foodMarket: 
                    self.selectedCategory = .retail
                    self.selectedSubcategory = "Grocery Store"
                case .gasStation, .evCharger, .carRental, .laundry, .postOffice:
                    self.selectedCategory = .service
                case .bank, .atm:
                    self.selectedCategory = .finance
                case .pharmacy:
                    self.selectedCategory = .healthcare
                    self.selectedSubcategory = "Pharmacy"
                case .hospital:
                    self.selectedCategory = .healthcare
                    self.selectedSubcategory = "Hospital"
                case .parking:
                    self.selectedCategory = .transport
                    self.selectedSubcategory = "Parking"
                case .fireStation, .police:
                    self.selectedCategory = .service
                case .publicTransport:
                    self.selectedCategory = .transport
                case .school, .university, .library:
                    self.selectedCategory = .education
                case .movieTheater:
                    self.selectedCategory = .entertainment
                    self.selectedSubcategory = "Movie Theater"
                case .museum:
                    self.selectedCategory = .attraction
                    self.selectedSubcategory = "Museum"
                case .park, .beach, .nationalPark:
                    self.selectedCategory = .outdoor
                    if poiCategory == .park {
                        self.selectedSubcategory = "Park"
                    } else if poiCategory == .beach {
                        self.selectedSubcategory = "Beach"
                    }
                case .theater:
                    self.selectedCategory = .entertainment
                    self.selectedSubcategory = "Theater"
                case .zoo, .aquarium:
                    self.selectedCategory = .attraction
                    if poiCategory == .zoo {
                        self.selectedSubcategory = "Zoo"
                    } else {
                        self.selectedSubcategory = "Aquarium"
                    }
                case .amusementPark:
                    self.selectedCategory = .attraction
                    self.selectedSubcategory = "Theme Park"
                case .miniGolf:
                    self.selectedCategory = .entertainment
                case .stadium:
                    self.selectedCategory = .entertainment
                case .marina:
                    self.selectedCategory = .outdoor
                case .castle, .landmark:
                    self.selectedCategory = .attraction
                    self.selectedSubcategory = "Landmark"
                default:
                    self.selectedCategory = .other
                }
            } else {
                // Try to infer category from name
                let name = (mapItem.name ?? "").lowercased()
                if name.contains("restaurant") || name.contains("kitchen") || name.contains("grill") {
                    self.selectedCategory = .restaurant
                } else if name.contains("cafe") || name.contains("coffee") {
                    self.selectedCategory = .cafe
                } else if name.contains("bar") || name.contains("pub") || name.contains("brewery") {
                    self.selectedCategory = .bar
                } else if name.contains("hotel") || name.contains("inn") || name.contains("motel") {
                    self.selectedCategory = .hotel
                } else if name.contains("store") || name.contains("shop") || name.contains("market") {
                    self.selectedCategory = .retail
                } else {
                    self.selectedCategory = .other
                }
            }
            
            // Update category button text
            if let subcategory = self.selectedSubcategory {
                self.categoryButton.setTitle("\(self.selectedCategory.displayName) - \(subcategory)", for: .normal)
            } else {
                self.categoryButton.setTitle(self.selectedCategory.displayName, for: .normal)
            }
            
            // Update selected location
            if let location = placemark.location {
                self.selectedLocation = location.coordinate
            }
            
            // Force UI refresh
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
    
    private func fillFormWithGMSPlace(_ place: GMSPlace) {
        // Convert GMSPlace to GooglePlaceDetails
        let placeDetails = GooglePlaceDetails(from: place)
        fillFormWithGooglePlace(placeDetails)
        
        // Update map to show the selected place
        updateMapForLocation(place.coordinate)
        
        // Calculate and show distance from current location
        if let userLocation = locationManager.location {
            let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let distance = userLocation.distance(from: placeLocation)
            
            // Convert to miles or kilometers based on locale
            let formatter = MeasurementFormatter()
            formatter.numberFormatter.maximumFractionDigits = 1
            let measurement = Measurement(value: distance, unit: UnitLength.meters)
            let distanceString = formatter.string(from: measurement)
            
            // Update the address text to include distance
            if let currentAddress = addressTextView.text, !currentAddress.isEmpty {
                addressTextView.text = "\(currentAddress)\n📍 \(distanceString) from current location"
            }
        }
    }
    
    private func loadAndFillFormWithGooglePlace(placeId: String, markerTitle: String) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading Place Details", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Fetch full place details
        placesClient.fetchPlace(
            fromPlaceID: placeId,
            placeFields: [.name, .formattedAddress, .coordinate, .types, .phoneNumber, .website, .rating, .userRatingsTotal, .priceLevel, .photos, .openingHours, .businessStatus],
            sessionToken: nil
        ) { [weak self] (place, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    if let place = place {
                        // Fill the form with place details
                        self.fillFormWithGMSPlace(place)
                    } else {
                        print("Failed to fetch place details: \(error?.localizedDescription ?? "unknown error")")
                        self.presentAlert(title: "Error", message: "Failed to load place details")
                    }
                }
            }
        }
    }
    
    private func updateMapForLocation(_ coordinate: CLLocationCoordinate2D) {
        let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 17.0)
        mapView.animate(to: camera)
        
        // Add a marker for the selected location if not already present
        var hasMarker = false
        for marker in markers {
            if marker.position.latitude == coordinate.latitude && 
               marker.position.longitude == coordinate.longitude {
                hasMarker = true
                break
            }
        }
        
        if !hasMarker {
            let marker = GMSMarker()
            marker.position = coordinate
            marker.title = "Selected Location"
            marker.icon = GMSMarker.markerImage(with: .systemGreen)
            marker.map = mapView
            markers.append(marker)
        }
    }
    
    private func performReverseGeocoding(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else { return }
            
            DispatchQueue.main.async {
                // Fill in address
                let address = [
                    placemark.subThoroughfare,
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                
                self.addressTextView.text = address
                self.selectedLocation = coordinate
                self.enableManualEntry()
            }
        }
    }
    
    private func fillFormWithGooglePlace(_ placeDetails: GooglePlaceDetails) {
        // Store the Google Place details
        self.selectedGooglePlaceDetails = placeDetails
        
        // Enable form first
        enableManualEntry()
        
        // Add a small delay to ensure the form is visible before populating
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Fill name
            self.nameTextField.text = placeDetails.name
            
            // Fill address
            self.addressTextView.text = placeDetails.address ?? ""
            
            // Fill description with available details
            var description = ""
            
            // Add rating if available
            if let rating = placeDetails.rating, rating > 0 {
                description += "Rating: \(rating)/5"
                if placeDetails.userRatingsTotal > 0 {
                    description += " (\(placeDetails.userRatingsTotal) reviews)"
                }
            }
            
            // Add phone if available
            if let phone = placeDetails.phoneNumber, !phone.isEmpty {
                if !description.isEmpty { description += "\n" }
                description += "Phone: \(phone)"
            }
            
            // Add website if available
            if let website = placeDetails.website {
                if !description.isEmpty { description += "\n" }
                description += "Website: \(website.absoluteString)"
            }
            
            // Add opening hours if available
            if let openingHours = placeDetails.openingHours {
                if !description.isEmpty { description += "\n\n" }
                description += "Hours:\n"
                // Format opening hours from GMSOpeningHours
                if let weekdayText = openingHours.weekdayText {
                    for dayHours in weekdayText {
                        description += "\(dayHours)\n"
                    }
                }
            }
            
            self.descriptionTextView.text = description
            
            // Set category based on types
            if !placeDetails.types.isEmpty {
                self.setCategoryFromGoogleTypes(placeDetails.types)
            }
            
            // Update selected location
            self.selectedLocation = placeDetails.coordinate
            
            // Update map
            self.updateMapForLocation(self.selectedLocation!)
            
            // Load Google Place photo if available
            if !placeDetails.photos.isEmpty {
                print("📸 Loading photo from Google Places for form display...")
                GooglePlacesService.shared.loadPhoto(from: placeDetails.photos[0], maxSize: CGSize(width: 800, height: 800)) { [weak self] result in
                    switch result {
                    case .success(let image):
                        print("📸 Successfully loaded Google photo for form")
                        DispatchQueue.main.async {
                            self?.selectedImage = image
                            self?.photoImageView.image = image
                            self?.photoImageView.isHidden = false
                            self?.removePhotoButton.isHidden = false
                            self?.addPhotoButton.isHidden = true
                        }
                    case .failure(let error):
                        print("📸 Failed to load Google photo for form: \(error)")
                    }
                }
            }
            
            // Scroll to form
            let formRect = self.formContainer.convert(self.formContainer.bounds, to: self.scrollView)
            self.scrollView.scrollRectToVisible(formRect, animated: true)
            
            // Force UI refresh
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
    
    private func setCategoryFromGoogleTypes(_ types: [String]) {
        // Reset subcategory
        selectedSubcategory = nil
        
        // Check types and set appropriate category
        if types.contains("restaurant") || types.contains("food") {
            selectedCategory = .restaurant
            // Try to set subcategory based on more specific types
            if types.contains("meal_takeaway") || types.contains("meal_delivery") {
                selectedSubcategory = "Fast Food"
            } else if types.contains("bakery") {
                selectedSubcategory = "Bakery"
            }
        } else if types.contains("cafe") {
            selectedCategory = .cafe
            if types.contains("coffee_shop") {
                selectedSubcategory = "Coffee Shop"
            }
        } else if types.contains("bar") || types.contains("night_club") {
            selectedCategory = .bar
            if types.contains("night_club") {
                selectedSubcategory = "Nightclub"
            }
        } else if types.contains("lodging") || types.contains("hotel") {
            selectedCategory = .hotel
        } else if types.contains("store") || types.contains("shopping_mall") {
            selectedCategory = .retail
            if types.contains("grocery_or_supermarket") {
                selectedSubcategory = "Grocery Store"
            } else if types.contains("clothing_store") {
                selectedSubcategory = "Clothing Store"
            } else if types.contains("electronics_store") {
                selectedSubcategory = "Electronics"
            }
        } else if types.contains("beauty_salon") || types.contains("hair_care") || types.contains("spa") {
            selectedCategory = .service
            if types.contains("beauty_salon") {
                selectedSubcategory = "Beauty Salon"
            } else if types.contains("hair_care") {
                selectedSubcategory = "Hair Salon"
            } else if types.contains("spa") {
                selectedSubcategory = "Spa"
            }
        } else if types.contains("gym") || types.contains("health") {
            selectedCategory = .fitness
            if types.contains("gym") {
                selectedSubcategory = "Gym"
            }
        } else if types.contains("doctor") || types.contains("hospital") || types.contains("pharmacy") {
            selectedCategory = .healthcare
            if types.contains("doctor") {
                selectedSubcategory = "Doctor"
            } else if types.contains("hospital") {
                selectedSubcategory = "Hospital"
            } else if types.contains("pharmacy") {
                selectedSubcategory = "Pharmacy"
            }
        } else if types.contains("tourist_attraction") || types.contains("museum") || types.contains("park") {
            selectedCategory = .attraction
            if types.contains("museum") {
                selectedSubcategory = "Museum"
            } else if types.contains("park") {
                selectedSubcategory = "Park"
            }
        } else if types.contains("movie_theater") {
            selectedCategory = .entertainment
            selectedSubcategory = "Movie Theater"
        } else {
            selectedCategory = .other
        }
        
        // Update category button text
        if let subcategory = selectedSubcategory {
            categoryButton.setTitle("\(selectedCategory.displayName) - \(subcategory)", for: .normal)
        } else {
            categoryButton.setTitle(selectedCategory.displayName, for: .normal)
        }
    }
    
    private func presentAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alert, animated: true)
    }
    
    private func searchForNearbyPlaces(around coordinate: CLLocationCoordinate2D) {
        // Don't automatically search when location is first obtained
        // Let user choose a category instead
    }
    
    private func searchForCategory(_ category: String) {
        print("Searching for category: \(category)")
        
        // Use Google Places text search
        let filter = GMSAutocompleteFilter()
        filter.type = .establishment
        
        // Get current map bounds for location bias
        let visibleRegion = mapView.projection.visibleRegion()
        let bounds = GMSCoordinateBounds(region: visibleRegion)
        
        // Set location bias to current map view
        filter.locationBias = GMSPlaceRectangularLocationOption(
            bounds.northEast,
            bounds.southWest
        )
        
        // Create a search token
        let token = GMSAutocompleteSessionToken()
        
        // Perform text search
        placesClient.findAutocompletePredictions(
            fromQuery: category,
            filter: filter,
            sessionToken: token
        ) { [weak self] (predictions, error) in
            guard let self = self,
                  let predictions = predictions else {
                print("No predictions found or error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            print("Found \(predictions.count) predictions")
            
            DispatchQueue.main.async {
                // Remove existing markers
                for marker in self.markers {
                    marker.map = nil
                }
                self.markers.removeAll()
                self.markerToPlaceIdMap.removeAll()
                self.placeIdsByCoordinate.removeAll()
                
                // Process first 10 predictions to get place details
                let predictionsToProcess = Array(predictions.prefix(10))
                var processedCount = 0
                
                for prediction in predictionsToProcess {
                    let placeId = prediction.placeID  // Capture placeID
                    
                    // Fetch place details for each prediction
                    self.placesClient.fetchPlace(
                        fromPlaceID: placeId,
                        placeFields: [.name, .formattedAddress, .coordinate, .types, .phoneNumber, .website],
                        sessionToken: nil
                    ) { (place, error) in
                        guard let place = place else { 
                            print("Failed to fetch place details for \(placeId)")
                            return 
                        }
                        
                        DispatchQueue.main.async {
                            let marker = GMSMarker()
                            marker.position = place.coordinate
                            marker.title = place.name
                            marker.snippet = place.formattedAddress
                            
                            // Store place ID in marker's userData
                            marker.userData = placeId
                            
                            // Customize marker appearance
                            marker.icon = GMSMarker.markerImage(with: Constants.Colors.primary)
                            marker.appearAnimation = .pop
                            
                            marker.map = self.mapView
                            self.markers.append(marker)
                            
                            // Store the place ID for this marker
                            self.markerToPlaceIdMap[marker] = placeId
                            
                            // Also store by coordinate as backup
                            let coordKey = "\(place.coordinate.latitude),\(place.coordinate.longitude)"
                            self.placeIdsByCoordinate[coordKey] = placeId
                            
                            print("Added marker '\(place.name ?? "")' with placeId: \(placeId) and userData: \(marker.userData ?? "nil")")
                            
                            processedCount += 1
                            
                            // Show all markers when done
                            if processedCount == predictionsToProcess.count {
                                self.showAllAnnotations()
                                print("Total markers with place IDs: \(self.markerToPlaceIdMap.count)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func showAllAnnotations() {
        if markers.isEmpty { return }
        
        var bounds = GMSCoordinateBounds()
        for marker in markers {
            bounds = bounds.includingCoordinate(marker.position)
        }
        
        let update = GMSCameraUpdate.fit(bounds, withPadding: 50.0)
        mapView.animate(with: update)
    }
    
    private func addGooglePlace(placeId: String, markerTitle: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Fetch full place details with all available fields
        placesClient.fetchPlace(
            fromPlaceID: placeId,
            placeFields: [.name, .formattedAddress, .coordinate, .types, .phoneNumber, .website, .rating, .userRatingsTotal, .priceLevel, .photos, .openingHours, .businessStatus],
            sessionToken: nil
        ) { [weak self] (place, error) in
            guard let self = self, let place = place else {
                loadingAlert.dismiss(animated: true) {
                    self?.presentAlert(title: "Error", message: "Failed to get place details")
                }
                return
            }
            
            // Determine category based on place types
            let category = self.determinePlaceCategory(from: place.types ?? [])
            
            // Format opening hours if available
            var openingHoursArray: [[String: Any]] = []
            if let openingHours = place.openingHours {
                // Use the GooglePlaceDetails method to properly format opening hours
                let placeDetails = GooglePlaceDetails(from: place)
                if let formattedHours = placeDetails.toPlaceData(circleId: self.circleId)["openingHours"] as? [[String: Any]] {
                    openingHoursArray = formattedHours
                }
            }
            
            // Create comprehensive place data
            var placeData: [String: Any] = [
                "name": place.name ?? markerTitle,
                "address": place.formattedAddress ?? "",
                "googlePlaceId": placeId,
                "circleId": self.circleId,
                "category": category.rawValue,
                "rating": place.rating,
                "userRatingsTotal": place.userRatingsTotal,
                "website": place.website?.absoluteString ?? "",
                "phone": place.phoneNumber ?? "",
                "priceLevel": place.priceLevel.rawValue,
                "types": place.types ?? [],
                "location": [
                    "type": "Point",
                    "coordinates": [place.coordinate.longitude, place.coordinate.latitude]
                ]
            ]
            
            // Add opening hours if available
            if !openingHoursArray.isEmpty {
                placeData["openingHours"] = openingHoursArray
            }
            
            // Add business status
            switch place.businessStatus {
            case .operational:
                placeData["businessStatus"] = "operational"
            case .closedTemporarily:
                placeData["businessStatus"] = "closed_temporarily"
            case .closedPermanently:
                placeData["businessStatus"] = "closed_permanently"
            case .unknown:
                placeData["businessStatus"] = "unknown"
            @unknown default:
                placeData["businessStatus"] = "unknown"
            }
            
            // Add place description from types and business info
            var descriptionParts: [String] = []
            if place.rating > 0 {
                descriptionParts.append("Rating: \(String(format: "%.1f", place.rating))/5.0 (\(place.userRatingsTotal) reviews)")
            }
            if place.priceLevel.rawValue > 0 {
                let priceString = String(repeating: "$", count: Int(place.priceLevel.rawValue))
                descriptionParts.append("Price: \(priceString)")
            }
            if !descriptionParts.isEmpty {
                placeData["description"] = descriptionParts.joined(separator: " • ")
            }
            
            // Handle Google Place photos
            if let photos = place.photos, !photos.isEmpty {
                // Load the first photo
                print("📸 Loading photo from Google Places...")
                GooglePlacesService.shared.loadPhoto(from: photos[0], maxSize: CGSize(width: 800, height: 800)) { photoResult in
                    switch photoResult {
                    case .success(let image):
                        print("📸 Successfully loaded Google photo")
                        // Convert to data and upload
                        if let imageData = image.jpegData(compressionQuality: 0.8) {
                            print("📸 Uploading photo to backend... Size: \(imageData.count / 1024)KB")
                            PlaceService.shared.uploadMultipleImages([imageData]) { uploadResult in
                                switch uploadResult {
                                case .success(let imageUrls):
                                    print("📸 Photo uploaded successfully: \(imageUrls)")
                                    placeData["photos"] = imageUrls
                                    self.createPlaceWithGoogleData(placeData, loadingAlert: loadingAlert)
                                case .failure(let error):
                                    print("📸 Failed to upload photo: \(error)")
                                    self.createPlaceWithGoogleData(placeData, loadingAlert: loadingAlert)
                                }
                            }
                        } else {
                            print("📸 Failed to convert image to JPEG data")
                            self.createPlaceWithGoogleData(placeData, loadingAlert: loadingAlert)
                        }
                    case .failure(let error):
                        print("📸 Failed to load Google photo: \(error)")
                        self.createPlaceWithGoogleData(placeData, loadingAlert: loadingAlert)
                    }
                }
            } else {
                print("📸 No photos available from Google Places")
                self.createPlaceWithGoogleData(placeData, loadingAlert: loadingAlert)
            }
        }
    }
    
    private func createPlaceWithGoogleData(_ placeData: [String: Any], loadingAlert: UIAlertController) {
        // Debug: Log place data being sent
        print("📍 Creating place with data:")
        print("📍 Name: \(placeData["name"] ?? "No name")")
        print("📍 Category: \(placeData["category"] ?? "No category")")
        print("📍 Photos: \(placeData["photos"] ?? "No photos")")
        print("📍 Rating: \(placeData["rating"] ?? "No rating")")
        print("📍 Description: \(placeData["description"] ?? "No description")")
        
        PlaceService.shared.createPlaceFromGoogleData(placeData) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let newPlace):
                        // Debug: Log returned place data
                        print("✅ Place created successfully:")
                        print("✅ ID: \(newPlace.id)")
                        print("✅ Name: \(newPlace.name)")
                        print("✅ Photos: \(newPlace.photos ?? [])")
                        print("✅ Description: \(newPlace.description ?? "nil")")
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(newPlace.name) has been added to the circle",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                            // Go back to circle detail
                            self.navigationController?.popViewController(animated: true)
                        })
                        self.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        print("❌ Failed to create place: \(error)")
                        self.presentAlert(
                            title: "Error",
                            message: "Failed to add place: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
    }
    
    private func determinePlaceCategory(from types: [String]) -> PlaceCategory {
        // Check for specific types in order of priority
        if types.contains("restaurant") { return .restaurant }
        if types.contains("cafe") { return .cafe }
        if types.contains("bar") { return .bar }
        if types.contains("lodging") || types.contains("hotel") { return .hotel }
        if types.contains("store") || types.contains("shopping_mall") { return .retail }
        if types.contains("tourist_attraction") || types.contains("museum") { return .attraction }
        if types.contains("health") || types.contains("hospital") || types.contains("doctor") { return .healthcare }
        if types.contains("gym") || types.contains("spa") { return .fitness }
        if types.contains("movie_theater") || types.contains("night_club") { return .entertainment }
        
        // Default to service
        return .service
    }
    
    private func getCategoryForMapItem(_ mapItem: MKMapItem) -> String {
        if let category = mapItem.pointOfInterestCategory {
            switch category {
            case .restaurant: return "Restaurant"
            case .cafe: return "Café"
            case .nightlife, .brewery, .winery: return "Bar"
            case .store, .foodMarket: return "Shop"
            case .gasStation: return "Gas Station"
            case .hotel: return "Hotel"
            case .park: return "Park"
            case .pharmacy: return "Pharmacy"
            case .bank, .atm: return "Bank"
            default: return "Place"
            }
        }
        return "Place"
    }
    
    private func getCategoryDescription(for category: MKPointOfInterestCategory) -> String {
        switch category {
        case .restaurant: return "A dining establishment"
        case .cafe: return "A coffee shop or casual dining spot"
        case .nightlife, .brewery, .winery: return "A bar or nightlife venue"
        case .hotel, .campground: return "Accommodation services"
        case .store, .foodMarket: return "Retail shopping location"
        case .gasStation, .evCharger: return "Vehicle fueling or charging station"
        case .parking: return "Parking facility"
        case .carRental: return "Car rental services"
        case .laundry: return "Laundry services"
        case .postOffice: return "Postal services"
        case .bank, .atm: return "Banking and financial services"
        case .pharmacy: return "Pharmacy and medication services"
        case .hospital: return "Healthcare services"
        case .fireStation, .police: return "Emergency services"
        case .publicTransport: return "Public transportation"
        case .school, .university: return "Educational institution"
        case .library: return "Library and information services"
        case .movieTheater: return "Movie theater entertainment"
        case .museum: return "Museum and cultural exhibits"
        case .park, .beach, .nationalPark: return "Outdoor recreation area"
        case .theater: return "Theater and performing arts venue"
        case .zoo, .aquarium: return "Animal exhibits and attractions"
        case .amusementPark: return "Amusement park and rides"
        case .miniGolf: return "Mini golf recreation"
        case .stadium: return "Sports and event venue"
        case .marina: return "Marina and boating services"
        case .castle, .landmark: return "Historical landmark or attraction"
        default: return "Local business or point of interest"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension AddPlaceViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        
        // Center map on user location with wider zoom
        let camera = GMSCameraPosition.camera(withTarget: location.coordinate, zoom: 15.0)
        
        // Use dispatch to ensure map renders properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.mapView.animate(to: camera)
            
            // Add a small delay to ensure map tiles load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.mapView.setNeedsDisplay()
            }
        }
        
        // Stop updating
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            // Also try to get current location immediately
            if let location = manager.location {
                locationManager(manager, didUpdateLocations: [location])
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // This is the old delegate method, keeping for backward compatibility
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location error occurred - could show alert if needed
    }
}

// MARK: - GMSMapViewDelegate

extension AddPlaceViewController: GMSMapViewDelegate {
    func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        // Handle tap on map (not on a marker)
        handleMapTapAtCoordinate(coordinate)
    }
    
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        guard let name = marker.title else { return false }
        
        print("Marker tapped: \(name)")
        print("Marker userData: \(marker.userData ?? "nil")")
        print("markerToPlaceIdMap has \(markerToPlaceIdMap.count) entries")
        
        // For "Selected Location" markers, fill the form
        if name == "Selected Location" {
            mapView.selectedMarker = marker
            return true
        }
        
        // First check userData for place ID
        if let placeId = marker.userData as? String {
            print("Found place ID in userData: \(placeId)")
            // Show confirmation popup
            let alert = UIAlertController(
                title: "Add Place",
                message: "Do you want to add \"\(name)\" to this circle?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Add Place", style: .default) { [weak self] _ in
                self?.loadAndFillFormWithGooglePlace(placeId: placeId, markerTitle: name)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            present(alert, animated: true)
        }
        // Then check if this is a Google Places marker in our map
        else if let placeId = markerToPlaceIdMap[marker] {
            print("Found place ID in markerToPlaceIdMap: \(placeId)")
            // Show confirmation popup
            let alert = UIAlertController(
                title: "Add Place",
                message: "Do you want to add \"\(name)\" to this circle?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Add Place", style: .default) { [weak self] _ in
                self?.loadAndFillFormWithGooglePlace(placeId: placeId, markerTitle: name)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            present(alert, animated: true)
        } else {
            print("No place ID found for marker in markerToPlaceIdMap")
            
            // Try coordinate-based lookup
            let coordKey = "\(marker.position.latitude),\(marker.position.longitude)"
            if let placeId = placeIdsByCoordinate[coordKey] {
                print("Found place ID by coordinate lookup: \(placeId)")
                // Show confirmation popup
                let alert = UIAlertController(
                    title: "Add Place",
                    message: "Do you want to add \"\(name)\" to this circle?",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "Add Place", style: .default) { [weak self] _ in
                    self?.addGooglePlace(placeId: placeId, markerTitle: name)
                })
                
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                
                present(alert, animated: true)
            } else {
                print("No place ID found even with coordinate lookup")
                // As last resort, try to find by position in markerToPlaceIdMap
                for (storedMarker, storedPlaceId) in markerToPlaceIdMap {
                    if storedMarker.position.latitude == marker.position.latitude &&
                       storedMarker.position.longitude == marker.position.longitude {
                        print("Found place ID by position match in markerToPlaceIdMap: \(storedPlaceId)")
                        // Show confirmation popup
                        let alert = UIAlertController(
                            title: "Add Place",
                            message: "Do you want to add \"\(name)\" to this circle?",
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "Add Place", style: .default) { [weak self] _ in
                            self?.loadAndFillFormWithGooglePlace(placeId: storedPlaceId, markerTitle: name)
                        })
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        
                        present(alert, animated: true)
                        break
                    }
                }
            }
        }
        
        // Select the marker to show info window
        mapView.selectedMarker = marker
        
        return true // Consume the tap event
    }
    
    func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
        print("POI tapped: \(name) with placeID: \(placeID)")
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Fetch full place details
        GooglePlacesService.shared.fetchPlaceDetails(placeID: placeID) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let gmsPlace):
                        // Show confirmation alert
                        let alert = UIAlertController(
                            title: "Add Place", 
                            message: "Add '\(gmsPlace.name ?? name)' to this circle?",
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
                            self.fillFormWithGMSPlace(gmsPlace)
                        })
                        
                        self.present(alert, animated: true)
                        
                    case .failure(let error):
                        print("Failed to fetch place details: \(error)")
                        // Fallback to basic info
                        let alert = UIAlertController(
                            title: "Add Place",
                            message: "Add '\(name)' to this circle?", 
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
                            // Populate with basic info
                            self.nameTextField.text = name
                            self.selectedLocation = location
                            self.updateMapForLocation(location)
                            self.performReverseGeocoding(for: location)
                        })
                        
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    func mapView(_ mapView: GMSMapView, didTapInfoWindowOf marker: GMSMarker) {
        // When info window is tapped, ensure the form is visible and scroll to it
        if marker.title != "Selected Location" {
            // Scroll to form
            let formRect = self.formContainer.convert(self.formContainer.bounds, to: self.scrollView)
            self.scrollView.scrollRectToVisible(formRect, animated: true)
        }
    }
    
    func mapView(_ mapView: GMSMapView, markerInfoWindow marker: GMSMarker) -> UIView? {
        // Return nil to use default info window
        return nil
    }
    
}

// MARK: - UISearchBarDelegate

extension AddPlaceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Cancel previous timer
        searchTimer?.invalidate()
        
        // Hide results if search is empty
        if searchText.isEmpty {
            searchResults = []
            searchResultsTableView.reloadData()
            searchResultsTableView.isHidden = true
            return
        }
        
        // Show table view immediately for better UX
        searchResultsTableView.isHidden = false
        
        // Debounce search by 0.3 seconds
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performGooglePlacesSearch(searchText)
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        if !searchBar.text!.isEmpty {
            searchResultsTableView.isHidden = false
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Google Places Search

extension AddPlaceViewController {
    private func performGooglePlacesSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            searchResultsTableView.reloadData()
            return
        }
        
        let filter = GMSAutocompleteFilter()
        filter.type = .noFilter
        
        // Create location bounds for bias (25 mile radius)
        if let userLocation = locationManager.location {
            // Convert 25 miles to degrees (approximate)
            // 1 degree latitude = ~69 miles, so 25 miles = ~0.36 degrees
            let latDelta = 0.36
            let lonDelta = 0.36
            
            let northEast = CLLocationCoordinate2D(
                latitude: userLocation.coordinate.latitude + latDelta,
                longitude: userLocation.coordinate.longitude + lonDelta
            )
            let southWest = CLLocationCoordinate2D(
                latitude: userLocation.coordinate.latitude - latDelta,
                longitude: userLocation.coordinate.longitude - lonDelta
            )
            
            filter.locationBias = GMSPlaceRectangularLocationOption(northEast, southWest)
        }
        
        placesClient.findAutocompletePredictions(
            fromQuery: query,
            filter: filter,
            sessionToken: sessionToken
        ) { [weak self] (results, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("🔴 Google Places search error: \(error.localizedDescription)")
                print("🔴 Error details: \(error)")
                self.searchResults = []
                self.searchResultsTableView.reloadData()
                return
            }
            
            if let results = results {
                print("✅ Google Places found \(results.count) results for query: \(query)")
                self.searchResults = results
                self.searchResultsTableView.reloadData()
            } else {
                print("⚠️ Google Places returned nil results")
                self.searchResults = []
                self.searchResultsTableView.reloadData()
            }
        }
    }
}


// MARK: - UITableViewDataSource & Delegate

extension AddPlaceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == categoryDropdownTableView {
            return categoryDropdownItems.count
        } else {
            return searchResults.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == categoryDropdownTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell") ?? UITableViewCell(style: .default, reuseIdentifier: "CategoryCell")
            
            // Set cell background for dark mode support
            cell.backgroundColor = .secondarySystemBackground
            let item = categoryDropdownItems[indexPath.row]
            
            // Format display text
            if item.category == .other && item.subcategory == "More..." {
                // Special formatting for "More..." option
                cell.textLabel?.text = "More..."
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell.textLabel?.textColor = .systemBlue
            } else if let subcategory = item.subcategory {
                cell.textLabel?.text = "    \(subcategory)"  // Indent subcategories
                cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
                cell.textLabel?.textColor = .secondaryLabel  // Better for dark mode
            } else {
                cell.textLabel?.text = item.category.displayName
                cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell.textLabel?.textColor = .label  // Adapts to dark/light mode
            }
            
            // Add checkmark for selected item
            let isSelected = (item.subcategory == nil && item.category == selectedCategory && selectedSubcategory == nil) ||
                           (item.subcategory != nil && item.category == selectedCategory && item.subcategory == selectedSubcategory)
            
            if isSelected {
                cell.accessoryType = .checkmark
                cell.tintColor = .systemBlue
            } else {
                cell.accessoryType = .none
            }
            
            // Add icon only for main categories
            if item.category == .other && item.subcategory == "More..." {
                // Special icon for "More..." option
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell.imageView?.image = UIImage(systemName: "ellipsis.circle", withConfiguration: config)
                cell.imageView?.tintColor = .systemBlue
            } else if item.subcategory == nil {
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell.imageView?.image = UIImage(systemName: item.category.systemIconName, withConfiguration: config)
                cell.imageView?.tintColor = .systemBlue
            } else {
                cell.imageView?.image = nil
            }
            
            return cell
        } else {
            var cell = tableView.dequeueReusableCell(withIdentifier: "SearchCell")
            if cell == nil {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "SearchCell")
            }
            
            let result = searchResults[indexPath.row]
            
            // Configure cell for better display
            cell?.textLabel?.text = result.attributedPrimaryText.string
            cell?.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            cell?.textLabel?.numberOfLines = 2
            
            // Show full address with city, state, country
            cell?.detailTextLabel?.text = result.attributedSecondaryText?.string
            cell?.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
            cell?.detailTextLabel?.textColor = .systemGray
            cell?.detailTextLabel?.numberOfLines = 2
            
            return cell!
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == categoryDropdownTableView {
            let item = categoryDropdownItems[indexPath.row]
            
            // Check if "More..." was selected
            if item.category == .other && item.subcategory == "More..." {
                // Hide dropdown first
                categoryButtonTapped()
                
                // Present the category picker
                let categoryPicker = CategoryPickerViewController(
                    selectedCategory: selectedCategory,
                    selectedSubcategory: selectedSubcategory
                )
                categoryPicker.delegate = self
                let navController = UINavigationController(rootViewController: categoryPicker)
                present(navController, animated: true)
            } else {
                // Normal category selection
                selectedCategory = item.category
                selectedSubcategory = item.subcategory
                
                // Update button title
                if let subcategory = item.subcategory {
                    categoryButton.setTitle("\(item.category.displayName) - \(subcategory)", for: .normal)
                } else {
                    categoryButton.setTitle(item.category.displayName, for: .normal)
                }
                
                // Hide dropdown
                categoryButtonTapped()
                
                tableView.reloadData()
            }
        } else {
            selectSearchResult(searchResults[indexPath.row])
        }
    }
}

// MARK: - CategoryPickerDelegate

extension AddPlaceViewController {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?) {
        selectedCategory = category
        selectedSubcategory = subcategory
        
        // Update button title
        if let subcategory = subcategory {
            categoryButton.setTitle("\(category.displayName) - \(subcategory)", for: .normal)
        } else {
            categoryButton.setTitle(category.displayName, for: .normal)
        }
    }
}

// MARK: - PHPickerViewControllerDelegate

// MARK: - UIGestureRecognizerDelegate

extension AddPlaceViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't dismiss if tapping on the dropdown or button itself
        let location = touch.location(in: view)
        let dropdownFrame = categoryDropdownTableView.convert(categoryDropdownTableView.bounds, to: view)
        let buttonFrame = categoryButton.convert(categoryButton.bounds, to: view)
        
        if dropdownFrame.contains(location) || buttonFrame.contains(location) {
            return false
        }
        return isCategoryDropdownVisible
    }
}

// MARK: - PHPickerViewControllerDelegate

extension AddPlaceViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.selectedImage = image
                        self?.photoImageView.image = image
                        self?.photoImageView.isHidden = false
                        self?.removePhotoButton.isHidden = false
                        self?.addPhotoButton.isHidden = true
                        
                        // No need to update constraints as they're already set up
                    }
                }
            }
        }
    }
}


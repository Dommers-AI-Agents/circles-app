import UIKit
import MapKit
import CoreLocation
import GooglePlaces  // Keep only for photos
import PhotosUI

protocol PlaceSearchDelegate: AnyObject {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?)
}

// Custom annotation class for place search
class PlaceSearchAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    var title: String?
    var subtitle: String?
    var placeId: String?
    var mapItem: MKMapItem?
    var isTemporary: Bool = false
}

class AddPlaceViewController: UIViewController, CategoryPickerDelegate {
    
    // MARK: - Properties
    private let circleId: String
    private let locationManager = CLLocationManager()
    private var userLocation: CLLocation?
    private var selectedLocation: CLLocationCoordinate2D?
    private var currentPOIData: POIPlaceData?
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    private var showPlaceTypeSuggestion = false
    private var placeTypeSuggestionQuery = ""
    private var selectedMapItem: MKMapItem?
    private var annotations: [MKAnnotation] = []
    private var annotationToPlaceIdMap: [ObjectIdentifier: String] = [:]
    private var placesClient: GMSPlacesClient!  // Keep only for photos
    private var placeIdsByCoordinate: [String: String] = [:] // Additional storage by coordinate
    private var selectedGooglePlaceDetails: GooglePlaceDetails?
    private var selectedCategory: PlaceCategory = .restaurant
    private var selectedSubcategory: String?
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
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.pointOfInterestFilter = .includingAll
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
    
    private let privateNotesLabel: UILabel = {
        let label = UILabel()
        label.text = "Private Notes (only visible to you)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privateNotesTextView: UITextView = {
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
    
    private let publicNotesLabel: UILabel = {
        let label = UILabel()
        label.text = "Public Notes (visible to others)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let publicNotesTextView: UITextView = {
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
    private var downloadedGoogleImage: UIImage?
    private var downloadedLookAroundImage: UIImage?
    private var uploadedPhotoUrls: [String] = []
    
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
    
    private let zoomToMeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.systemBlue
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var isSearchingNearby = false
    private var mapRegionTimer: Timer?
    private var hasSearchedCategory = false
    private var hasPerformedInitialSearch = false
    
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
        
        // Don't set initial region - wait for user location
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
        
        // Don't automatically search - wait for user location to search for coffee shops
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemGray6
        title = "Add Place"
        
        // Add Cancel button to navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        
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
        mapContainer.addSubview(zoomToMeButton)
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
        formContainer.addSubview(privateNotesLabel)
        formContainer.addSubview(privateNotesTextView)
        formContainer.addSubview(publicNotesLabel)
        formContainer.addSubview(publicNotesTextView)
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
            
            // Zoom to me button
            zoomToMeButton.bottomAnchor.constraint(equalTo: mapContainer.bottomAnchor, constant: -12),
            zoomToMeButton.trailingAnchor.constraint(equalTo: mapContainer.trailingAnchor, constant: -12),
            zoomToMeButton.widthAnchor.constraint(equalToConstant: 44),
            zoomToMeButton.heightAnchor.constraint(equalToConstant: 44),
            
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
            
            privateNotesLabel.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: Constants.Spacing.medium),
            privateNotesLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            privateNotesTextView.topAnchor.constraint(equalTo: privateNotesLabel.bottomAnchor, constant: Constants.Spacing.small),
            privateNotesTextView.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            privateNotesTextView.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            privateNotesTextView.heightAnchor.constraint(equalToConstant: 60),
            
            publicNotesLabel.topAnchor.constraint(equalTo: privateNotesTextView.bottomAnchor, constant: Constants.Spacing.medium),
            publicNotesLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            publicNotesTextView.topAnchor.constraint(equalTo: publicNotesLabel.bottomAnchor, constant: Constants.Spacing.small),
            publicNotesTextView.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            publicNotesTextView.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            publicNotesTextView.heightAnchor.constraint(equalToConstant: 60),
            
            addressLabel.topAnchor.constraint(equalTo: publicNotesTextView.bottomAnchor, constant: Constants.Spacing.medium),
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
        privateNotesTextView.alpha = 1.0
        publicNotesTextView.alpha = 1.0
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
        
        // Enable POI selection for iOS 16+
        if #available(iOS 16.0, *) {
            mapView.selectableMapFeatures = [.pointsOfInterest]
        }
        
        // Add tap gesture for manual location selection
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        tapGesture.delegate = self
        mapView.addGestureRecognizer(tapGesture)
        
        // Set initial region
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            latitudinalMeters: 20000,
            longitudinalMeters: 20000
        )
        mapView.setRegion(region, animated: false)
    }
    
    private func setupSearchCompleter() {
        // Keep Google Places client only for photos
        placesClient = GMSPlacesClient.shared()
        
        // Setup MKLocalSearchCompleter
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        
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
        zoomToMeButton.addTarget(self, action: #selector(zoomToCurrentLocation), for: .touchUpInside)
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
    
    
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: mapView)
        let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
        handleMapTapAtCoordinate(coordinate)
    }
    
    private func handleMapTapAtCoordinate(_ coordinate: CLLocationCoordinate2D) {
        // Remove any existing "Selected Location" annotations
        let selectedAnnotations = mapView.annotations.filter { ($0 as? PlaceSearchAnnotation)?.title == "Selected Location" }
        mapView.removeAnnotations(selectedAnnotations)
        
        // Add new annotation
        let annotation = PlaceSearchAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Selected Location"
        annotation.subtitle = "Tap here to add this place"
        annotation.isTemporary = true
        
        mapView.addAnnotation(annotation)
        annotations.append(annotation)
        
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
                self.privateNotesTextView.text = ""
                self.publicNotesTextView.text = ""
                
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
                
                // Search for nearby places at this location
                self.searchNearbyPlaces(at: coordinate)
            }
        }
    }
    
    private func searchNearbyPlaces(at coordinate: CLLocationCoordinate2D) {
        print("🔍 Searching for nearby places at \(coordinate.latitude), \(coordinate.longitude)")
        
        // Use Google Places to search for nearby businesses
        GooglePlacesService.shared.searchPlacesByCategory(
            category: "",  // Empty query to get all nearby places
            center: coordinate,
            radiusInMeters: 50  // Search within 50 meters
        ) { [weak self] result in
            switch result {
            case .success(let predictions):
                if let nearestPlace = predictions.first {
                    print("✅ Found nearby place: \(nearestPlace.attributedPrimaryText.string)")
                    
                    // Fetch details for the nearest place
                    GooglePlacesService.shared.fetchPlaceDetails(placeID: nearestPlace.placeID) { detailsResult in
                        switch detailsResult {
                        case .success(let place):
                            DispatchQueue.main.async {
                                // If we found a place, update the form with its details
                                let googleDetails = GooglePlaceDetails(from: place)
                                self?.selectedGooglePlaceDetails = googleDetails
                                
                                // Update the name field with the found place
                                self?.nameTextField.text = place.name ?? ""
                                
                                // Preload photos
                                self?.preloadAndUploadPhotosForPlace(googleDetails)
                                
                                print("📍 Updated form with nearby place: \(place.name ?? "Unknown")")
                            }
                        case .failure(let error):
                            print("❌ Failed to fetch place details: \(error)")
                        }
                    }
                } else {
                    print("⚠️ No nearby places found at this location")
                }
            case .failure(let error):
                print("❌ Failed to search nearby places: \(error)")
            }
        }
    }
    
    @objc private func cancelButtonTapped() {
        // Show confirmation if user has entered data
        let hasEnteredData = !(nameTextField.text?.isEmpty ?? true) ||
                            !addressTextView.text.isEmpty ||
                            !descriptionTextView.text.isEmpty ||
                            !privateNotesTextView.text.isEmpty ||
                            !publicNotesTextView.text.isEmpty ||
                            selectedImage != nil ||
                            selectedLocation != nil
        
        if hasEnteredData {
            let alert = UIAlertController(
                title: "Cancel Adding Place?",
                message: "You have unsaved changes. Are you sure you want to cancel?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
            
            present(alert, animated: true)
        } else {
            // No data entered, go back immediately
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func manualEntryButtonTapped() {
        // Clear any selected Google Place when manually entering
        selectedGooglePlaceDetails = nil
        hasSearchedCategory = false  // Reset category search flag
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
        
        // Clear pre-uploaded photos when user removes photo
        uploadedPhotoUrls.removeAll()
        downloadedGoogleImage = nil
        downloadedLookAroundImage = nil
        print("📸 Cleared all photos and uploads")
        
        // Update layout to reflect changes
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Ensure scroll view updates its content size
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
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
        let privateNotes = privateNotesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicNotes = publicNotesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
                            privacy: privacy,
                            privateNotes: privateNotes.isEmpty ? nil : privateNotes,
                            publicNotes: publicNotes.isEmpty ? nil : publicNotes
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
                                        subcategory: String?, privacy: PlacePrivacy,
                                        privateNotes: String?, publicNotes: String?) {
        // Create place
        let loadingAlert = UIAlertController(title: "Creating Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Check if we have pre-uploaded photos
        print("📸 Checking pre-uploaded photos: \(uploadedPhotoUrls.count) available")
        
        // Only prepare photo data if no pre-uploaded photos exist
        var photoData: [Data]? = nil
        if uploadedPhotoUrls.isEmpty && selectedImage != nil {
            print("⚠️ No pre-uploaded photos but image exists - this shouldn't happen!")
            // This is a fallback - photos should have been pre-uploaded
            if let image = selectedImage {
                if let imageData = image.jpegData(compressionQuality: 0.6) {
                    photoData = [imageData]
                    print("📸 Using fallback photo data")
                }
            }
        }
        
        // Check if we have Google Place details to use
        if let googleDetails = selectedGooglePlaceDetails {
            print("🚀 AddPlaceViewController: Creating place with Google details")
            print("  Name: \(name)")
            print("  GooglePlaceId: \(googleDetails.placeID)")
            print("  Has photos: \(googleDetails.photos.count > 0)")
            
            // Use addPlaceFromPOI which collects both Apple Look Around and Google Places photos
            let location = GeoLocation(
                type: "Point", 
                coordinates: [googleDetails.coordinate.longitude, googleDetails.coordinate.latitude]
            )
            
            print("📸 Using pre-uploaded photos: \(self.uploadedPhotoUrls)")
            
            PlaceService.shared.addPlaceFromPOI(
                name: name,
                address: address,
                location: location,
                category: category,
                website: googleDetails.website?.absoluteString,
                phone: googleDetails.phoneNumber,
                description: description.isEmpty ? nil : description,
                circleId: circleId,
                notes: privateNotes,
                googlePlaceId: googleDetails.placeID.isEmpty ? nil : googleDetails.placeID,
                preUploadedPhotoUrls: self.uploadedPhotoUrls.isEmpty ? nil : self.uploadedPhotoUrls
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let place):
                            print("✅ Place created successfully")
                            print("  ID: \(place.id)")
                            print("  Photos count: \(place.photos?.count ?? 0)")
                            if let photos = place.photos {
                                for (index, photo) in photos.enumerated() {
                                    print("  Photo \(index + 1): \(photo)")
                                }
                            }
                            
                            // TODO: Update place with publicNotes if provided
                            // Currently addPlaceFromPOI only supports privateNotes through the 'notes' parameter
                            // A separate update call would be needed for publicNotes
                            if let publicNotes = publicNotes, !publicNotes.isEmpty {
                                print("⚠️ Public notes were provided but not saved: \(publicNotes)")
                                // PlaceService.shared.updatePlace(id: place.id, publicNotes: publicNotes) { _ in }
                            }
                            
                            // Post notification that a place was added
                            NotificationCenter.default.post(
                                name: Notification.Name("PlaceAddedToCircle"),
                                object: nil,
                                userInfo: ["circleId": self?.circleId ?? "", "place": place]
                            )
                            
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
        } else {
            // No Google details, create place normally
            print("📸 Creating non-Google place with pre-uploaded photos: \(self.uploadedPhotoUrls)")
            
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
                photos: photoData,
                photoUrls: self.uploadedPhotoUrls.isEmpty ? nil : self.uploadedPhotoUrls,
                location: self.selectedLocation,
                googlePlaceId: self.selectedGooglePlaceDetails?.placeID
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let place):
                            print("✅ Place created successfully with photos: \(place.photos ?? [])")
                            // Post notification that a place was added
                            NotificationCenter.default.post(
                                name: Notification.Name("PlaceAddedToCircle"),
                                object: nil,
                                userInfo: ["circleId": self?.circleId ?? "", "place": place]
                            )
                            
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
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        // Hide search results
        searchResultsTableView.isHidden = true
        searchBar.resignFirstResponder()
        searchBar.text = result.title
        
        // Create search request from completion
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                return
            }
            
            guard let response = response, let mapItem = response.mapItems.first else {
                print("No map items found")
                return
            }
            
            DispatchQueue.main.async {
                // Fill the form with map item details
                self.fillFormWithMapItem(mapItem)
                
                // Update map location to show both user location and selected place
                self.showBothUserAndPlace(placeCoordinate: mapItem.placemark.coordinate)
                
                // Add annotation
                let annotation = PlaceSearchAnnotation()
                annotation.coordinate = mapItem.placemark.coordinate
                annotation.title = mapItem.name ?? result.title
                annotation.subtitle = self.formatAddress(for: mapItem.placemark)
                annotation.mapItem = mapItem
                
                // Remove previous search annotations
                let nonUserAnnotations = self.mapView.annotations.filter { !($0 is MKUserLocation) && !(($0 as? PlaceSearchAnnotation)?.isTemporary ?? false) }
                self.mapView.removeAnnotations(nonUserAnnotations)
                
                self.mapView.addAnnotation(annotation)
                self.annotations = [annotation]
            }
        }
    }
    
    private func performPlaceTypeSearch(_ query: String) {
        // Hide search results
        searchResultsTableView.isHidden = true
        searchBar.resignFirstResponder()
        
        // Get user location to search nearby
        guard let userLocation = locationManager.location else {
            presentAlert(title: "Location Required", message: "Please enable location services to search nearby places")
            return
        }
        
        // Create search request for the place type
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 10000, // ~6 miles radius
            longitudinalMeters: 10000
        )
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Place type search error: \(error.localizedDescription)")
                return
            }
            
            guard let response = response else {
                print("No results found for place type: \(query)")
                return
            }
            
            DispatchQueue.main.async {
                // Sort results by distance from user
                let sortedItems = response.mapItems.sorted { item1, item2 in
                    let location1 = CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude)
                    let location2 = CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude)
                    
                    let distance1 = userLocation.distance(from: location1)
                    let distance2 = userLocation.distance(from: location2)
                    
                    return distance1 < distance2
                }
                
                // Clear existing annotations except user location
                let annotationsToRemove = self.mapView.annotations.filter { !($0 is MKUserLocation) }
                self.mapView.removeAnnotations(annotationsToRemove)
                
                // Add annotations for search results
                for (index, item) in sortedItems.prefix(20).enumerated() { // Show top 20 results
                    let annotation = PlaceSearchAnnotation()
                    annotation.coordinate = item.placemark.coordinate
                    annotation.title = item.name
                    annotation.subtitle = self.formatAddress(for: item.placemark)
                    annotation.mapItem = item
                    
                    self.mapView.addAnnotation(annotation)
                }
                
                // Zoom map to show all results and user location
                var coordinates: [CLLocationCoordinate2D] = sortedItems.prefix(10).map { $0.placemark.coordinate }
                coordinates.append(userLocation.coordinate)
                
                self.showAnnotations(coordinates: coordinates)
                
                // Update search bar text
                self.searchBar.text = ""
                
                // Show category search flag
                self.hasSearchedCategory = true
            }
        }
    }
    
    private func showBothUserAndPlace(placeCoordinate: CLLocationCoordinate2D) {
        guard let userLocation = locationManager.location else {
            // If no user location, just show the place
            let region = MKCoordinateRegion(
                center: placeCoordinate,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
            mapView.setRegion(region, animated: true)
            return
        }
        
        // Calculate region that includes both user location and place
        let userCoordinate = userLocation.coordinate
        
        // Find the center point between user and place
        let centerLat = (userCoordinate.latitude + placeCoordinate.latitude) / 2
        let centerLon = (userCoordinate.longitude + placeCoordinate.longitude) / 2
        let centerCoordinate = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        // Calculate distance between points
        let placeLocation = CLLocation(latitude: placeCoordinate.latitude, longitude: placeCoordinate.longitude)
        let distance = userLocation.distance(from: placeLocation)
        
        // Set span to include both points with some padding
        let span = distance * 2.5 // Add padding
        
        let region = MKCoordinateRegion(
            center: centerCoordinate,
            latitudinalMeters: max(span, 2000), // Minimum 2km
            longitudinalMeters: max(span, 2000)
        )
        
        mapView.setRegion(region, animated: true)
    }
    
    private func showAnnotations(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        
        let latDelta = (maxLat - minLat) * 1.3 // Add padding
        let lonDelta = (maxLon - minLon) * 1.3
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(latDelta, 0.01),
            longitudeDelta: max(lonDelta, 0.01)
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }
    
    private func captureStreetViewImage(for coordinate: CLLocationCoordinate2D) {
        // First check if street view is available at this location
        GoogleStreetViewService.shared.checkStreetViewAvailability(at: coordinate) { [weak self] available in
            guard available else {
                print("Street View not available at this location")
                return
            }
            
            // Download the street view image
            let parameters = GoogleStreetViewService.StreetViewParameters(
                location: coordinate,
                size: CGSize(width: 800, height: 600),
                pitch: 10,
                fov: 100
            )
            
            GoogleStreetViewService.shared.downloadStreetViewImage(parameters: parameters) { imageData in
                guard let data = imageData,
                      let image = UIImage(data: data) else {
                    print("Failed to download street view image")
                    return
                }
                
                DispatchQueue.main.async {
                    self?.selectedImage = image
                    self?.photoImageView.image = image
                    self?.photoImageView.isHidden = false
                    self?.removePhotoButton.isHidden = false
                    self?.addPhotoButton.isHidden = true
                    print("✅ Street view image captured successfully")
                }
            }
        }
    }
    
    private func fillFormWithMapItem(_ mapItem: MKMapItem) {
        print("📝 fillFormWithMapItem called with: \(mapItem.name ?? "Unknown")")
        print("📝 Category search active: \(hasSearchedCategory)")
        
        selectedMapItem = mapItem
        selectedGooglePlaceDetails = nil // Clear Google details
        
        // Enable form first
        enableManualEntry()
        
        // Capture street view image for the location
        captureStreetViewImage(for: mapItem.placemark.coordinate)
        
        // Add a small delay to ensure the form is visible before populating
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("📝 Form container state - alpha: \(self.formContainer.alpha), enabled: \(self.formContainer.isUserInteractionEnabled)")
            
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
            
            // Calculate and add distance from current location
            var finalAddress = address
            if let userLocation = self.locationManager.location {
                let placeLocation = CLLocation(latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude)
                let distance = userLocation.distance(from: placeLocation)
                
                // Convert to miles or kilometers based on locale
                let formatter = MeasurementFormatter()
                formatter.numberFormatter.maximumFractionDigits = 1
                let measurement = Measurement(value: distance, unit: UnitLength.meters)
                let distanceString = formatter.string(from: measurement)
                
                finalAddress += "\n📍 \(distanceString) from current location"
            }
            
            self.addressTextView.text = finalAddress
            
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
            
            // Clear notes fields for new place
            self.privateNotesTextView.text = ""
            self.publicNotesTextView.text = ""
            
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
                case .stadium:
                    self.selectedCategory = .entertainment
                case .marina:
                    self.selectedCategory = .outdoor
                default:
                    if #available(iOS 18.0, *) {
                        switch poiCategory {
                        case .miniGolf:
                            self.selectedCategory = .entertainment
                        case .castle, .landmark:
                            self.selectedCategory = .attraction
                            self.selectedSubcategory = "Landmark"
                        default:
                            self.selectedCategory = .other
                        }
                    } else {
                        self.selectedCategory = .other
                    }
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
            
            // Debug: Log what was filled
            print("📝 Form filled with:")
            print("  - Name: \(self.nameTextField.text ?? "empty")")
            print("  - Address: \(self.addressTextView.text ?? "empty")")
            print("  - Description: \(self.descriptionTextView.text ?? "empty")")
            print("  - Category: \(self.selectedCategory.displayName)")
            print("  - Form enabled: \(self.formContainer.isUserInteractionEnabled)")
            
            // Search for Google Place to get photos (only for businesses, not residential)
            if !isResidentialAddress, let placeName = mapItem.name, !placeName.isEmpty {
                print("🔍 Searching Google Places for: \(placeName)")
                GooglePlacesService.shared.searchPlaceByNameAndLocation(
                    name: placeName,
                    coordinate: mapItem.placemark.coordinate
                ) { [weak self] result in
                    switch result {
                    case .success(let prediction):
                        if let prediction = prediction {
                            print("✅ Found Google Place match: \(prediction.attributedPrimaryText.string)")
                            // Fetch place details to get photos
                            GooglePlacesService.shared.fetchPlaceDetails(placeID: prediction.placeID) { detailsResult in
                                switch detailsResult {
                                case .success(let place):
                                    let googleDetails = GooglePlaceDetails(from: place)
                                    DispatchQueue.main.async {
                                        // Store the Google Place details for later use
                                        self?.selectedGooglePlaceDetails = googleDetails
                                        // Preload and upload photos
                                        self?.preloadAndUploadPhotosForPlace(googleDetails)
                                    }
                                case .failure(let error):
                                    print("❌ Failed to fetch Google Place details: \(error)")
                                }
                            }
                        } else {
                            print("⚠️ No Google Place match found for: \(placeName)")
                        }
                    case .failure(let error):
                        print("❌ Failed to search Google Places: \(error)")
                    }
                }
            }
        }
    }
    
    private func fillFormWithGMSPlace(_ place: GMSPlace) {
        // Convert GMSPlace to GooglePlaceDetails
        let placeDetails = GooglePlaceDetails(from: place)
        fillFormWithGooglePlace(placeDetails)
        
        // Update map to show the selected place
        updateMapForLocation(place.coordinate)
        
        // Capture street view image for the location
        captureStreetViewImage(for: place.coordinate)
        
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
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: true)
        
        // Add an annotation for the selected location if not already present
        var hasAnnotation = false
        for annotation in mapView.annotations {
            if let searchAnnotation = annotation as? PlaceSearchAnnotation,
               searchAnnotation.coordinate.latitude == coordinate.latitude &&
               searchAnnotation.coordinate.longitude == coordinate.longitude {
                hasAnnotation = true
                break
            }
        }
        
        if !hasAnnotation {
            let annotation = PlaceSearchAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "Selected Location"
            annotation.isTemporary = true
            mapView.addAnnotation(annotation)
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
    
    private func preloadAndUploadPhotosForPlace(_ placeDetails: GooglePlaceDetails) {
        print("🚀 Pre-loading photos for place: \(placeDetails.name)")
        
        // Reset previous photos
        self.downloadedGoogleImage = nil
        self.downloadedLookAroundImage = nil
        self.uploadedPhotoUrls.removeAll()
        
        let photoGroup = DispatchGroup()
        
        // Load Google Place photo if available
        if !placeDetails.photos.isEmpty {
            photoGroup.enter()
            print("📸 Loading photo from Google Places...")
            GooglePlacesService.shared.loadPhoto(from: placeDetails.photos[0], maxSize: CGSize(width: 800, height: 800)) { [weak self] result in
                switch result {
                case .success(let image):
                    print("📸 Successfully loaded Google photo")
                    self?.downloadedGoogleImage = image
                    
                    // Show in UI immediately
                    DispatchQueue.main.async {
                        self?.selectedImage = image
                        self?.photoImageView.image = image
                        self?.photoImageView.isHidden = false
                        self?.removePhotoButton.isHidden = false
                        self?.addPhotoButton.isHidden = true
                    }
                    
                    // Upload the image
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        print("📸 Uploading Google photo (size: \(imageData.count / 1024) KB)...")
                        self?.uploadImageData(imageData) { uploadedUrl in
                            if let url = uploadedUrl {
                                self?.uploadedPhotoUrls.append(url)
                                print("✅ Google photo uploaded: \(url)")
                            }
                            photoGroup.leave()
                        }
                    } else {
                        photoGroup.leave()
                    }
                    
                case .failure(let error):
                    print("❌ Failed to load Google photo: \(error)")
                    photoGroup.leave()
                }
            }
        }
        
        // Try Apple Look Around
        if #available(iOS 16.0, *) {
            photoGroup.enter()
            Task {
                print("📸 Checking Apple Look Around...")
                let hasLookAround = await AppleLookAroundService.shared.checkLookAroundAvailability(at: placeDetails.coordinate)
                
                if hasLookAround {
                    print("✅ Look Around is available")
                    do {
                        let lookAroundImage = try await AppleLookAroundService.shared.getLookAroundSnapshot(at: placeDetails.coordinate)
                        self.downloadedLookAroundImage = lookAroundImage
                        
                        // If no Google photo, show Look Around in UI
                        if self.downloadedGoogleImage == nil {
                            DispatchQueue.main.async {
                                self.selectedImage = lookAroundImage
                                self.photoImageView.image = lookAroundImage
                                self.photoImageView.isHidden = false
                                self.removePhotoButton.isHidden = false
                                self.addPhotoButton.isHidden = true
                            }
                        }
                        
                        // Upload the image
                        if let imageData = lookAroundImage.jpegData(compressionQuality: 0.8) {
                            print("📸 Uploading Look Around photo (size: \(imageData.count / 1024) KB)...")
                            self.uploadImageData(imageData) { uploadedUrl in
                                if let url = uploadedUrl {
                                    self.uploadedPhotoUrls.append(url)
                                    print("✅ Look Around photo uploaded: \(url)")
                                }
                                photoGroup.leave()
                            }
                        } else {
                            photoGroup.leave()
                        }
                    } catch {
                        print("❌ Failed to get Look Around snapshot: \(error)")
                        photoGroup.leave()
                    }
                } else {
                    print("⚠️ Look Around not available")
                    photoGroup.leave()
                }
            }
        }
        
        // Log completion
        photoGroup.notify(queue: .main) {
            print("📸 Photo pre-loading complete. Uploaded \(self.uploadedPhotoUrls.count) photos")
            for (index, url) in self.uploadedPhotoUrls.enumerated() {
                print("  Photo \(index + 1): \(url)")
            }
        }
    }
    
    private func uploadImageData(_ imageData: Data, completion: @escaping (String?) -> Void) {
        PlaceService.shared.uploadMultipleImages([imageData]) { result in
            switch result {
            case .success(let urls):
                completion(urls.first)
            case .failure(let error):
                print("❌ Image upload failed: \(error)")
                completion(nil)
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
            
            // Clear notes fields for new place
            self.privateNotesTextView.text = ""
            self.publicNotesTextView.text = ""
            
            // Set category based on types
            if !placeDetails.types.isEmpty {
                self.setCategoryFromGoogleTypes(placeDetails.types)
            }
            
            // Update selected location
            self.selectedLocation = placeDetails.coordinate
            
            // Update map
            self.updateMapForLocation(self.selectedLocation!)
            
            // Pre-load and pre-upload photos when place is selected
            self.preloadAndUploadPhotosForPlace(placeDetails)
            
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
        
        // Mark that we've searched for a category
        hasSearchedCategory = true
        
        // Create search request using Apple Maps (cost-efficient)
        // NOTE: Always use MKLocalSearch for place discovery, not Google Places
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category
        request.region = mapView.region
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                return
            }
            
            guard let response = response else { return }
            
            print("Found \(response.mapItems.count) items")
            
            DispatchQueue.main.async {
                // Remove existing annotations (except user location)
                let nonUserAnnotations = self.mapView.annotations.filter { !($0 is MKUserLocation) }
                self.mapView.removeAnnotations(nonUserAnnotations)
                self.annotations.removeAll()
                self.annotationToPlaceIdMap.removeAll()
                self.placeIdsByCoordinate.removeAll()
                
                // Add annotations for each result
                for mapItem in response.mapItems {
                    let annotation = PlaceSearchAnnotation()
                    annotation.coordinate = mapItem.placemark.coordinate
                    annotation.title = mapItem.name ?? "Unknown Place"
                    annotation.subtitle = self.formatAddress(for: mapItem.placemark)
                    annotation.mapItem = mapItem
                    
                    self.mapView.addAnnotation(annotation)
                    self.annotations.append(annotation)
                    
                    print("📍 Added annotation: \(annotation.title ?? "Unknown") at \(annotation.coordinate)")
                    
                    // Store by coordinate for lookup
                    let coordKey = "\(mapItem.placemark.coordinate.latitude),\(mapItem.placemark.coordinate.longitude)"
                    // We'll need to get Google Place ID later if user selects this
                }
                
                // Show all annotations
                self.showAllAnnotations()
            }
        }
    }
    
    private func showAllAnnotations() {
        if annotations.isEmpty { return }
        
        var coordinates = annotations.map { $0.coordinate }
        
        // Include user location if available
        if let userLocation = mapView.userLocation.location {
            coordinates.append(userLocation.coordinate)
        }
        
        // Calculate region that fits all coordinates
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.2,
            longitudeDelta: (maxLon - minLon) * 1.2
        )
        
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
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
            // NOTE: This is the ONLY acceptable use of Google Places API - fetching photos
            // For all other operations, use Apple Maps API (see APIUsageGuidelines.md)
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
        
        var enrichedPlaceData = placeData
        
        // Try to get Apple Look Around image if location is available
        if let location = placeData["location"] as? [String: Any],
           let coordinates = location["coordinates"] as? [Double],
           coordinates.count >= 2 {
            
            let longitude = coordinates[0]
            let latitude = coordinates[1]
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            // Check and fetch Apple Look Around
            if #available(iOS 16.0, *) {
                Task {
                    let hasLookAround = await AppleLookAroundService.shared.checkLookAroundAvailability(at: coordinate)
                    
                    if hasLookAround {
                        do {
                            // Get the Look Around snapshot
                            let lookAroundImage = try await AppleLookAroundService.shared.getLookAroundSnapshot(at: coordinate)
                            
                            // Convert to JPEG data
                            if let imageData = lookAroundImage.jpegData(compressionQuality: 0.8) {
                                // Upload the image
                                PlaceService.shared.uploadMultipleImages([imageData]) { uploadResult in
                                    switch uploadResult {
                                    case .success(let imageUrls):
                                        // Add Apple Look Around URL to existing photos
                                        var photos = enrichedPlaceData["photos"] as? [String] ?? []
                                        photos.append(contentsOf: imageUrls)
                                        enrichedPlaceData["photos"] = photos
                                        print("✅ Apple Look Around image uploaded successfully")
                                        print("📸 Total photos: \(photos.count)")
                                        
                                        // Now create the place with both images
                                        self.finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
                                        
                                    case .failure(let error):
                                        print("Failed to upload Look Around image: \(error)")
                                        // Continue without Look Around image
                                        self.finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
                                    }
                                }
                            } else {
                                // Failed to convert image
                                self.finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
                            }
                        } catch {
                            print("Failed to get Look Around snapshot: \(error)")
                            // Continue without Look Around image
                            self.finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
                        }
                    } else {
                        // No Look Around available
                        self.finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
                    }
                }
            } else {
                // iOS version too old for Look Around
                finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
            }
        } else {
            // No location available
            finalizeCreatePlace(enrichedPlaceData, loadingAlert: loadingAlert)
        }
    }
    
    private func finalizeCreatePlace(_ placeData: [String: Any], loadingAlert: UIAlertController) {
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
    
    private func formatAddress(for placemark: MKPlacemark) -> String {
        let addressComponents = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ].compactMap { $0 }
        
        return addressComponents.joined(separator: ", ")
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
        case .stadium: return "Sports and event venue"
        case .marina: return "Marina and boating services"
        default:
            if #available(iOS 18.0, *) {
                switch category {
                case .miniGolf: return "Mini golf recreation"
                case .castle, .landmark: return "Historical landmark or attraction"
                default: return "Local business or point of interest"
                }
            } else {
                return "Local business or point of interest"
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension AddPlaceViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        
        // Center map on user location with wider zoom
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
        
        // Use dispatch to ensure map renders properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.mapView.setRegion(region, animated: true)
            
            // Search for coffee shops if this is the first location update
            if !self.hasPerformedInitialSearch {
                self.hasPerformedInitialSearch = true
                // Small delay to ensure map has finished animating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.searchNearbyPlaces(query: "coffee shop cafe")
                }
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

// MARK: - Map Helpers

extension AddPlaceViewController {
    @objc private func zoomToCurrentLocation() {
        guard let location = userLocation else {
            // Request location if not available
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            return
        }
        
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        mapView.setRegion(region, animated: true)
    }
    
    private func scrollToFormTop() {
        // Calculate the offset to show the form nicely
        let formY = formContainer.frame.origin.y - 20 // Add some padding
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        let targetOffset = min(formY, maxOffset)
        
        // Animate scroll to show form
        scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
    }
    
    private func searchNearbyPlaces(query: String? = nil) {
        // Only search if we're not already searching
        guard !isSearchingNearby else { return }
        
        isSearchingNearby = true
        let region = mapView.region
        
        // Create search request for points of interest
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query ?? "restaurant cafe bar shop attraction" // Use provided query or default
        request.region = region
        request.resultTypes = [.pointOfInterest]
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let response = response {
                // Clear existing annotations except user location
                let annotationsToRemove = self.mapView.annotations.filter { !($0 is MKUserLocation) }
                self.mapView.removeAnnotations(annotationsToRemove)
                
                // Add annotations for each result
                for item in response.mapItems {
                    let annotation = PlaceSearchAnnotation()
                    annotation.coordinate = item.placemark.coordinate
                    annotation.title = item.name
                    annotation.subtitle = item.placemark.title
                    annotation.mapItem = item
                    
                    self.mapView.addAnnotation(annotation)
                }
            }
            
            self.isSearchingNearby = false
        }
    }
}

// MARK: - MKMapViewDelegate

extension AddPlaceViewController: MKMapViewDelegate {
    @available(iOS 16.0, *)
    private func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let poiSubtitle = featureAnnotation.subtitle ?? ""
        let coordinate = featureAnnotation.coordinate
        
        print("🏪 POI selected: \(poiName)")
        print("📍 POI subtitle: \(poiSubtitle)")
        print("📍 POI coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Enable form first
        enableManualEntry()
        
        // Extract POI data without saving to backend
        AppleMapsService.shared.extractPOIData(
            from: featureAnnotation
        ) { [weak self] result in
            switch result {
            case .success(let poiData):
                DispatchQueue.main.async {
                    // Fill form with POI details (without saving to backend)
                    self?.nameTextField.text = poiData.name
                    self?.addressTextView.text = poiData.address
                    self?.selectedCategory = poiData.category
                    self?.updateCategoryButtonTitle()
                    
                    // Store additional data for later use when saving
                    self?.currentPOIData = poiData
                    
                    // Update location
                    self?.selectedLocation = coordinate
                    
                    // Add marker to map
                    self?.clearPreviousAnnotations()
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = coordinate
                    annotation.title = poiName
                    self?.mapView.addAnnotation(annotation)
                    
                    // Center map on selected location
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                    
                    // Deselect the POI annotation
                    self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
                    
                    // Scroll to show form
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.scrollToFormTop()
                    }
                    
                    // Search for Google Place to get photos
                    let placeName = poiData.name
                    if !placeName.isEmpty {
                        print("🔍 Searching Google Places for POI: \(placeName)")
                        GooglePlacesService.shared.searchPlaceByNameAndLocation(
                            name: placeName,
                            coordinate: coordinate
                        ) { [weak self] result in
                            switch result {
                            case .success(let prediction):
                                if let prediction = prediction {
                                    print("✅ Found Google Place match for POI: \(prediction.attributedPrimaryText.string)")
                                    // Fetch place details to get photos
                                    GooglePlacesService.shared.fetchPlaceDetails(placeID: prediction.placeID) { detailsResult in
                                        switch detailsResult {
                                        case .success(let place):
                                            let googleDetails = GooglePlaceDetails(from: place)
                                            DispatchQueue.main.async {
                                                // Store the Google Place details for later use
                                                self?.selectedGooglePlaceDetails = googleDetails
                                                // Preload and upload photos
                                                self?.preloadAndUploadPhotosForPlace(googleDetails)
                                            }
                                        case .failure(let error):
                                            print("❌ Failed to fetch Google Place details for POI: \(error)")
                                        }
                                    }
                                } else {
                                    print("⚠️ No Google Place match found for POI: \(placeName)")
                                }
                            case .failure(let error):
                                print("❌ Failed to search Google Places for POI: \(error)")
                            }
                        }
                    }
                }
            case .failure(let error):
                print("❌ Failed to convert POI to place: \(error)")
                // Fall back to basic info
                DispatchQueue.main.async {
                    self?.nameTextField.text = poiName
                    self?.addressTextView.text = poiSubtitle
                    self?.selectedLocation = coordinate
                    
                    // Add marker
                    self?.clearPreviousAnnotations()
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = coordinate
                    annotation.title = poiName
                    self?.mapView.addAnnotation(annotation)
                    
                    // Center map
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                    
                    self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
                    
                    // Scroll to form
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.scrollToFormTop()
                    }
                    
                    // Search for Google Place to get photos even in fallback case
                    if !poiName.isEmpty {
                        print("🔍 Searching Google Places for POI (fallback): \(poiName)")
                        GooglePlacesService.shared.searchPlaceByNameAndLocation(
                            name: poiName,
                            coordinate: coordinate
                        ) { [weak self] result in
                            switch result {
                            case .success(let prediction):
                                if let prediction = prediction {
                                    print("✅ Found Google Place match for POI (fallback): \(prediction.attributedPrimaryText.string)")
                                    // Fetch place details to get photos
                                    GooglePlacesService.shared.fetchPlaceDetails(placeID: prediction.placeID) { detailsResult in
                                        switch detailsResult {
                                        case .success(let place):
                                            let googleDetails = GooglePlaceDetails(from: place)
                                            DispatchQueue.main.async {
                                                // Store the Google Place details for later use
                                                self?.selectedGooglePlaceDetails = googleDetails
                                                // Preload and upload photos
                                                self?.preloadAndUploadPhotosForPlace(googleDetails)
                                            }
                                        case .failure(let error):
                                            print("❌ Failed to fetch Google Place details for POI (fallback): \(error)")
                                        }
                                    }
                                } else {
                                    print("⚠️ No Google Place match found for POI (fallback): \(poiName)")
                                }
                            case .failure(let error):
                                print("❌ Failed to search Google Places for POI (fallback): \(error)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Cancel previous timer
        mapRegionTimer?.invalidate()
        
        // Don't auto-search if user has searched for a category or is searching
        guard !hasSearchedCategory && searchResultsTableView.isHidden else { return }
        
        // Start new timer to search after user stops moving the map
        mapRegionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.searchNearbyPlaces()
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Handle POI selection for iOS 16+
        if #available(iOS 16.0, *) {
            if let featureAnnotation = view.annotation as? MKMapFeatureAnnotation {
                handlePOISelection(featureAnnotation)
                return
            }
        }
        
        guard let placeAnnotation = view.annotation as? PlaceSearchAnnotation else { return }
        
        // Skip user location and "Selected Location" markers
        if view.annotation is MKUserLocation || placeAnnotation.title == "Selected Location" {
            return
        }
        
        let name = placeAnnotation.title ?? "Unknown Place"
        print("🗺️ Map annotation selected: \(name)")
        print("🗺️ Annotation source: \(hasSearchedCategory ? "category search" : "regular search")")
        
        // Check if we have a mapItem (from Apple Maps search)
        if let mapItem = placeAnnotation.mapItem {
            print("✅ Found map item, filling form immediately")
            print("🗺️ Map item details: name=\(mapItem.name ?? ""), placemark=\(mapItem.placemark)")
            
            // Enable form first to ensure it's ready
            enableManualEntry()
            
            // Small delay to ensure form is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                // Immediately fill the form without confirmation popup
                self?.fillFormWithMapItem(mapItem)
                
                // Scroll to show the form after filling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.scrollToFormTop()
                }
            }
        }
        // Check if we have a Google Place ID
        else if let placeId = placeAnnotation.placeId {
            print("✅ Found Google place ID, loading details")
            
            // Enable form first
            enableManualEntry()
            
            // Small delay to ensure form is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                // Load and fill form without confirmation popup
                self?.loadAndFillFormWithGooglePlace(placeId: placeId, markerTitle: name)
                
                // Scroll to show the form
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.scrollToFormTop()
                }
            }
        } else {
            print("⚠️ No map item or place ID found for annotation")
        }
        
        // Keep the annotation selected to show the callout
        // The info button will still work for users who want to use it
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }
        
        guard let placeAnnotation = annotation as? PlaceSearchAnnotation else {
            return nil
        }
        
        let identifier = "PlaceSearchAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            annotationView?.isEnabled = true  // Ensure it's enabled for selection
            
            // Add detail button (optional - users can still use it if they prefer)
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
            annotationView?.isEnabled = true  // Ensure it's enabled
        }
        
        // Customize appearance
        if let markerView = annotationView {
            if placeAnnotation.isTemporary {
                markerView.markerTintColor = .systemGreen
            } else {
                markerView.markerTintColor = Constants.Colors.primary
            }
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceSearchAnnotation else { return }
        
        let name = placeAnnotation.title ?? "Unknown Place"
        print("ℹ️ Info button tapped: \(name)")
        
        // For "Selected Location" annotations, the form is already filled
        if name == "Selected Location" {
            return
        }
        
        // Since we now handle selection in didSelect, this is just a backup
        // or for users who prefer to use the info button
        print("ℹ️ Form should already be populated from didSelect")
        
        // Scroll to form if it's not visible
        scrollToFormTop()
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
            self?.performAppleMapsSearch(searchText)
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        // Reset category search flag when user starts typing
        hasSearchedCategory = false
        
        if !searchBar.text!.isEmpty {
            searchResultsTableView.isHidden = false
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Apple Maps Search

extension AddPlaceViewController {
    private func performAppleMapsSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            showPlaceTypeSuggestion = false
            searchResultsTableView.reloadData()
            return
        }
        
        // Check if query looks like a place type (simple words without numbers or specific addresses)
        let isLikelyPlaceType = !query.contains(where: { $0.isNumber }) && 
                               !query.lowercased().contains("street") && 
                               !query.lowercased().contains("ave") &&
                               !query.lowercased().contains("road") &&
                               !query.contains(",") &&
                               query.split(separator: " ").count <= 3
        
        showPlaceTypeSuggestion = isLikelyPlaceType
        placeTypeSuggestionQuery = query
        
        // Set search region based on current map view
        if let userLocation = locationManager.location {
            searchCompleter.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 40000, // ~25 miles
                longitudinalMeters: 40000
            )
        } else {
            searchCompleter.region = mapView.region
        }
        
        searchCompleter.queryFragment = query
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension AddPlaceViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        searchResultsTableView.reloadData()
        print("✅ Apple Maps found \(searchResults.count) results")
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("🔴 Apple Maps search error: \(error.localizedDescription)")
        searchResults = []
        searchResultsTableView.reloadData()
    }
}


// MARK: - UITableViewDataSource & Delegate

extension AddPlaceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == categoryDropdownTableView {
            return categoryDropdownItems.count
        } else {
            // Add 1 for place type suggestion if applicable
            return showPlaceTypeSuggestion ? searchResults.count + 1 : searchResults.count
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
            
            // Handle place type suggestion row
            if showPlaceTypeSuggestion && indexPath.row == 0 {
                // Configure as place type suggestion
                cell?.textLabel?.text = "\"\(placeTypeSuggestionQuery)\" nearby"
                cell?.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell?.textLabel?.textColor = .systemBlue
                cell?.textLabel?.numberOfLines = 1
                
                cell?.detailTextLabel?.text = "Search for this type of place"
                cell?.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
                cell?.detailTextLabel?.textColor = .systemGray
                
                // Add search icon
                let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                cell?.imageView?.image = UIImage(systemName: "magnifyingglass.circle.fill", withConfiguration: config)
                cell?.imageView?.tintColor = .systemBlue
            } else {
                // Regular search result
                let resultIndex = showPlaceTypeSuggestion ? indexPath.row - 1 : indexPath.row
                let result = searchResults[resultIndex]
                
                // Configure cell for better display
                cell?.textLabel?.text = result.title
                cell?.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                cell?.textLabel?.numberOfLines = 2
                cell?.textLabel?.textColor = .label
                
                // Show full address with city, state, country
                cell?.detailTextLabel?.text = result.subtitle
                cell?.detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
                cell?.detailTextLabel?.textColor = .systemGray
                cell?.detailTextLabel?.numberOfLines = 2
                
                // Add location icon for regular results
                let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                cell?.imageView?.image = UIImage(systemName: "mappin.circle", withConfiguration: config)
                cell?.imageView?.tintColor = .systemGray
            }
            
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
                if item.category == .other && item.subcategory == nil {
                    // User selected "Other" from dropdown - show category picker for custom input
                    categoryButtonTapped() // Hide dropdown first
                    
                    let categoryPicker = CategoryPickerViewController(
                        selectedCategory: .other,
                        selectedSubcategory: nil
                    )
                    categoryPicker.delegate = self
                    let navController = UINavigationController(rootViewController: categoryPicker)
                    present(navController, animated: true)
                } else {
                    // Regular category/subcategory selection
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
            }
        } else {
            // Handle place type suggestion
            if showPlaceTypeSuggestion && indexPath.row == 0 {
                // Perform a search for this place type nearby
                performPlaceTypeSearch(placeTypeSuggestionQuery)
            } else {
                // Regular search result selection
                let resultIndex = showPlaceTypeSuggestion ? indexPath.row - 1 : indexPath.row
                selectSearchResult(searchResults[resultIndex])
            }
        }
    }
}

// MARK: - CategoryPickerDelegate

extension AddPlaceViewController {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?, customCategory: String?) {
        selectedCategory = category
        
        // Handle custom category for "Other"
        if category == .other && customCategory != nil {
            selectedSubcategory = customCategory
        } else {
            selectedSubcategory = subcategory
        }
        
        // Update button title
        updateCategoryButtonTitle()
    }
    
    private func updateCategoryButtonTitle() {
        if let subcategory = selectedSubcategory {
            categoryButton.setTitle("\(selectedCategory.displayName) - \(subcategory)", for: .normal)
        } else {
            categoryButton.setTitle(selectedCategory.displayName, for: .normal)
        }
    }
    
    private func clearPreviousAnnotations() {
        // Remove any existing temporary annotations (like "Selected Location")
        let annotationsToRemove = mapView.annotations.filter { annotation in
            if let placeAnnotation = annotation as? PlaceSearchAnnotation {
                return placeAnnotation.isTemporary || placeAnnotation.title == "Selected Location"
            }
            return false
        }
        mapView.removeAnnotations(annotationsToRemove)
    }
}

// MARK: - PHPickerViewControllerDelegate

// MARK: - UIGestureRecognizerDelegate

extension AddPlaceViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Handle map tap gesture
        if gestureRecognizer is UITapGestureRecognizer && gestureRecognizer.view == mapView {
            let location = touch.location(in: mapView)
            
            // Check if tap is on a POI (iOS 16+)
            if #available(iOS 16.0, *) {
                // Check if any subview was hit (which could be a POI marker)
                if let hitView = mapView.hitTest(location, with: nil), hitView != mapView {
                    print("🚫 Tap on POI detected, allowing map to handle it")
                    return false // Let the map handle POI selection
                }
            }
            
            // Check if tap is on an annotation view
            for annotation in mapView.annotations {
                if let annotationView = mapView.view(for: annotation) {
                    let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
                    let annotationRect = CGRect(x: annotationPoint.x - 22, y: annotationPoint.y - 22, width: 44, height: 44)
                    
                    if annotationRect.contains(location) {
                        print("🚫 Tap on annotation detected, allowing map to handle it")
                        return false // Let the map handle annotation selection
                    }
                }
            }
            
            print("✅ Tap on empty map area, handling manual location selection")
            return true // Handle tap for manual location selection
        }
        
        // Handle category dropdown tap
        let location = touch.location(in: view)
        let dropdownFrame = categoryDropdownTableView.convert(categoryDropdownTableView.bounds, to: view)
        let buttonFrame = categoryButton.convert(categoryButton.bounds, to: view)
        
        if dropdownFrame.contains(location) || buttonFrame.contains(location) {
            return false
        }
        return isCategoryDropdownVisible
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow map's internal gesture recognizers to work alongside our tap gesture
        if gestureRecognizer.view == mapView || otherGestureRecognizer.view == mapView {
            print("🤝 Allowing simultaneous gesture recognition on map")
            return true
        }
        return false
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
                        
                        // Clear pre-uploaded photos since user selected a new one
                        self?.uploadedPhotoUrls.removeAll()
                        self?.downloadedGoogleImage = nil
                        self?.downloadedLookAroundImage = nil
                        
                        // Pre-upload the manually selected photo
                        print("📸 Pre-uploading manually selected photo...")
                        if let imageData = image.jpegData(compressionQuality: 0.8) {
                            self?.uploadImageData(imageData) { uploadedUrl in
                                if let url = uploadedUrl {
                                    self?.uploadedPhotoUrls.append(url)
                                    print("✅ Manual photo pre-uploaded: \(url)")
                                } else {
                                    print("❌ Failed to pre-upload manual photo")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Public Methods for Prefilling

extension AddPlaceViewController {
    /// Prefills the search bar with a place name and triggers search
    func prefillSearchWithPlace(name: String, coordinate: CLLocationCoordinate2D? = nil) {
        // Wait for view to load if needed
        guard isViewLoaded else {
            // Store for later use after view loads
            DispatchQueue.main.async { [weak self] in
                self?.prefillSearchWithPlace(name: name, coordinate: coordinate)
            }
            return
        }
        
        // Set search text
        searchBar.text = name
        
        // Store the coordinate for auto-selection
        self.selectedLocation = coordinate
        
        // If coordinate provided, center map on it
        if let coordinate = coordinate {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
            mapView.setRegion(region, animated: true)
            
            // Add a temporary annotation to show the location
            let tempAnnotation = PlaceSearchAnnotation()
            tempAnnotation.coordinate = coordinate
            tempAnnotation.title = name
            tempAnnotation.isTemporary = true
            mapView.addAnnotation(tempAnnotation)
        }
        
        // Trigger search after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Perform the search
            self.performAppleMapsSearch(name)
            
            // After search completes, directly trigger the search and fill form
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // If we have a coordinate, search for the place and fill form
                if let coordinate = coordinate, !name.isEmpty {
                    // Create a search request for the specific place
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = name
                    request.region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 200, // Small radius for precise search
                        longitudinalMeters: 200
                    )
                    
                    let search = MKLocalSearch(request: request)
                    search.start { [weak self] response, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("❌ POI search error: \(error.localizedDescription)")
                            // Still enable form for manual entry
                            self.enableManualEntry()
                            return
                        }
                        
                        // Find the closest match to our POI
                        if let mapItems = response?.mapItems {
                            let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            let closestItem = mapItems.min(by: { item1, item2 in
                                let dist1 = targetLocation.distance(from: CLLocation(
                                    latitude: item1.placemark.coordinate.latitude,
                                    longitude: item1.placemark.coordinate.longitude
                                ))
                                let dist2 = targetLocation.distance(from: CLLocation(
                                    latitude: item2.placemark.coordinate.latitude,
                                    longitude: item2.placemark.coordinate.longitude
                                ))
                                return dist1 < dist2
                            })
                            
                            if let mapItem = closestItem {
                                print("✅ Found POI match: \(mapItem.name ?? name)")
                                
                                DispatchQueue.main.async {
                                    // Enable form and fill it
                                    self.enableManualEntry()
                                    self.fillFormWithMapItem(mapItem)
                                    
                                    // Update map to show the place
                                    self.showBothUserAndPlace(placeCoordinate: mapItem.placemark.coordinate)
                                    
                                    // Add annotation for the selected place
                                    let annotation = PlaceSearchAnnotation()
                                    annotation.coordinate = mapItem.placemark.coordinate
                                    annotation.title = mapItem.name ?? name
                                    annotation.subtitle = self.formatAddress(for: mapItem.placemark)
                                    annotation.mapItem = mapItem
                                    
                                    // Remove previous annotations except user location and temporary
                                    let annotationsToRemove = self.mapView.annotations.filter { 
                                        !($0 is MKUserLocation) && 
                                        !(($0 as? PlaceSearchAnnotation)?.isTemporary ?? false) 
                                    }
                                    self.mapView.removeAnnotations(annotationsToRemove)
                                    
                                    self.mapView.addAnnotation(annotation)
                                    self.annotations = [annotation]
                                    
                                    // Select the annotation to show callout
                                    self.mapView.selectAnnotation(annotation, animated: true)
                                    
                                    // Scroll to form
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        self.scrollToFormTop()
                                    }
                                }
                            } else {
                                print("⚠️ No matching POI found nearby")
                                self.enableManualEntry()
                            }
                        }
                    }
                } else if !name.isEmpty {
                    // No coordinate, just select first search result
                    if self.searchResults.count > 0 {
                        self.selectSearchResult(self.searchResults[0])
                    }
                }
            }
        }
    }
}


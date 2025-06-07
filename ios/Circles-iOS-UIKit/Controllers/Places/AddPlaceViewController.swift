import UIKit
import MapKit
import CoreLocation

protocol PlaceSearchDelegate: AnyObject {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?)
}

class AddPlaceViewController: UIViewController {
    
    // MARK: - Properties
    private let circleId: String
    private let locationManager = CLLocationManager()
    private var userLocation: CLLocation?
    private var selectedLocation: CLLocationCoordinate2D?
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    private var selectedMapItem: MKMapItem?
    private var selectedAnnotation: MKAnnotation?
    private var mapItemsByCoordinate: [String: MKMapItem] = [:] // Store map items by coordinate key
    
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
        label.text = "Search for a place or select a category below"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemGray
        label.textAlignment = .center
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
        searchBar.placeholder = "🔍 Search for a place"
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
        mapView.mapType = .standard // Use standard map type
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsTraffic = false
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = false // Disable pitch to prevent 3D view issues
        mapView.isRotateEnabled = true
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
        textField.placeholder = "Enter place name"
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
    
    private let categorySegmentedControl: UISegmentedControl = {
        let categories = ["Restaurant", "Cafe", "Bar", "Hotel", "Retail", "Service", "Attraction", "Other"]
        let segmentedControl = UISegmentedControl(items: categories)
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
        setupUI()
        setupMap()
        setupSearchCompleter()
        setupActions()
        
        // Set initial map region to NYC to prevent black screen
        let initialLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) // New York City
        let initialRegion = MKCoordinateRegion(
            center: initialLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        mapView.setRegion(initialRegion, animated: false)
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
        formContainer.addSubview(categoryLabel)
        formContainer.addSubview(categorySegmentedControl)
        formContainer.addSubview(descriptionLabel)
        formContainer.addSubview(descriptionTextView)
        formContainer.addSubview(addressLabel)
        formContainer.addSubview(addressTextView)
        
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
            
            categoryLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            categoryLabel.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            
            categorySegmentedControl.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: Constants.Spacing.large),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -Constants.Spacing.large),
            
            descriptionLabel.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
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
            addressTextView.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor),
            
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
        categorySegmentedControl.alpha = 1.0
        
        // Setup category buttons
        setupCategoryButtons()
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
            button.addTarget(self, action: #selector(categoryButtonTapped(_:)), for: .touchUpInside)
            
            categoryStackView.addArrangedSubview(button)
        }
    }
    
    private func setupMap() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Map delegate
        mapView.delegate = self
        
        // Add tap gesture to map
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        tapGesture.delegate = self // Set gesture delegate to handle conflicts
        mapView.addGestureRecognizer(tapGesture)
    }
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .pointOfInterest
        
        // Table view setup
        searchResultsTableView.delegate = self
        searchResultsTableView.dataSource = self
        searchResultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchCell")
        
        // Search bar delegate
        searchBar.delegate = self
    }
    
    private func setupActions() {
        addPlaceButton.addTarget(self, action: #selector(addPlaceButtonTapped), for: .touchUpInside)
        manualEntryButton.addTarget(self, action: #selector(manualEntryButtonTapped), for: .touchUpInside)
    }
    
    
    // MARK: - Actions
    
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        // This will only be called for taps on empty map space due to gesture delegate
        let touchPoint = gesture.location(in: mapView)
        let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        
        // Clear existing annotations except user location and search results
        let searchAnnotations = mapView.annotations.filter { annotation in
            return !(annotation is MKUserLocation) && annotation.title != "Selected Location"
        }
        
        // Remove only previous "Selected Location" annotations
        let selectedLocationAnnotations = mapView.annotations.filter { annotation in
            return annotation.title == "Selected Location"
        }
        mapView.removeAnnotations(selectedLocationAnnotations)
        
        // Add new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Selected Location"
        mapView.addAnnotation(annotation)
        
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
        enableManualEntry()
        nameTextField.becomeFirstResponder()
    }
    
    @objc private func categoryButtonTapped(_ sender: UIButton) {
        guard let buttonTitle = sender.title(for: .normal) else { return }
        
        // Extract the category name (remove emoji and trim)
        let category = buttonTitle.components(separatedBy: " ").dropFirst().joined(separator: " ")
        
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
        
        let categoryIndex = categorySegmentedControl.selectedSegmentIndex
        let categories = [PlaceCategory.restaurant, .cafe, .bar, .hotel, .retail, .service, .attraction, .other]
        let category = categories[categoryIndex]
        
        let description = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Places always follow the circle's privacy setting
        let privacy = PlacePrivacy.followCirclePrivacy
        
        // Create place
        let loadingAlert = UIAlertController(title: "Creating Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.createPlace(
            name: name,
            description: description.isEmpty ? nil : description,
            address: address,
            category: category,
            circleId: circleId,
            privacy: privacy,
            website: nil,
            phone: nil,
            tags: nil,
            photos: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(_):
                        self?.presentAlert(title: "Success", message: "Place added successfully") { _ in
                            self?.navigationController?.popViewController(animated: true)
                        }
                    case .failure(let error):
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
    
    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        // Hide search results
        searchResultsTableView.isHidden = true
        searchBar.resignFirstResponder()
        
        // Perform full search to get details
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { [weak self] response, error in
            guard let self = self,
                  let response = response,
                  let mapItem = response.mapItems.first else { return }
            
            DispatchQueue.main.async {
                self.fillFormWithMapItem(mapItem)
            }
        }
    }
    
    private func fillFormWithMapItem(_ mapItem: MKMapItem) {
        selectedMapItem = mapItem
        
        // Enable form first
        enableManualEntry()
        
        // Add a small delay to ensure the form is visible before populating
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Fill name
            self.nameTextField.text = mapItem.name ?? "Unknown Place"
            
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
            if let poiCategory = mapItem.pointOfInterestCategory {
                switch poiCategory {
                case .restaurant: self.categorySegmentedControl.selectedSegmentIndex = 0
                case .cafe: self.categorySegmentedControl.selectedSegmentIndex = 1
                case .nightlife, .brewery, .winery: self.categorySegmentedControl.selectedSegmentIndex = 2
                case .hotel, .campground: self.categorySegmentedControl.selectedSegmentIndex = 3
                case .store, .foodMarket: self.categorySegmentedControl.selectedSegmentIndex = 4
                case .gasStation, .evCharger, .parking, .carRental,
                     .laundry, .postOffice, .bank, .atm, .pharmacy, .hospital,
                     .fireStation, .police, .publicTransport,
                     .school, .university, .library, .movieTheater:
                    self.categorySegmentedControl.selectedSegmentIndex = 5
                case .museum, .park, .beach, .theater, .zoo, .aquarium, .amusementPark,
                     .miniGolf, .stadium, .marina, .castle, .landmark, .nationalPark:
                    self.categorySegmentedControl.selectedSegmentIndex = 6
                default:
                    self.categorySegmentedControl.selectedSegmentIndex = 7
                }
            } else {
                // Try to infer category from name
                let name = (mapItem.name ?? "").lowercased()
                if name.contains("restaurant") || name.contains("kitchen") || name.contains("grill") {
                    self.categorySegmentedControl.selectedSegmentIndex = 0
                } else if name.contains("cafe") || name.contains("coffee") {
                    self.categorySegmentedControl.selectedSegmentIndex = 1
                } else if name.contains("bar") || name.contains("pub") || name.contains("brewery") {
                    self.categorySegmentedControl.selectedSegmentIndex = 2
                } else if name.contains("hotel") || name.contains("inn") || name.contains("motel") {
                    self.categorySegmentedControl.selectedSegmentIndex = 3
                } else if name.contains("store") || name.contains("shop") || name.contains("market") {
                    self.categorySegmentedControl.selectedSegmentIndex = 4
                } else {
                    self.categorySegmentedControl.selectedSegmentIndex = 7 // Other
                }
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
        guard let userLocation = userLocation else {
            return
        }
        
        // Save current map region before search
        let currentRegion = mapView.region
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self,
                  let response = response else { return }
            
            DispatchQueue.main.async {
                // Remove existing annotations (except user location)
                self.mapView.removeAnnotations(self.mapView.annotations.filter { !($0 is MKUserLocation) })
                
                // Clear previous map items
                self.mapItemsByCoordinate.removeAll()
                
                // Add annotations for places
                for item in response.mapItems {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = item.placemark.coordinate
                    annotation.title = item.name
                    annotation.subtitle = self.getCategoryForMapItem(item)
                    self.mapView.addAnnotation(annotation)
                    
                    // Store the map item by coordinate for later retrieval
                    let lat = String(format: "%.6f", item.placemark.coordinate.latitude)
                    let lon = String(format: "%.6f", item.placemark.coordinate.longitude)
                    let coordinateKey = "\(lat),\(lon)"
                    self.mapItemsByCoordinate[coordinateKey] = item
                }
                
                // Keep the same zoom level - don't call showAllAnnotations
                // The map will maintain its current region
            }
        }
    }
    
    private func showAllAnnotations() {
        let annotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        if annotations.isEmpty { return }
        
        mapView.showAnnotations(annotations, animated: true)
        
        // Add some padding
        let mapRect = mapView.visibleMapRect
        let edgePadding = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
        mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: true)
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
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        
        // Use dispatch to ensure map renders properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.mapView.setRegion(region, animated: true)
            
            // Force map to refresh
            self.mapView.setNeedsLayout()
            self.mapView.layoutIfNeeded()
            
            // Add a small delay to ensure map tiles load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.mapView.setNeedsDisplay()
            }
        }
        
        // Update search completer region
        searchCompleter.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        
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

// MARK: - MKMapViewDelegate

extension AddPlaceViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "PlacePin"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = false // Don't show callout, handle selection directly
            annotationView?.isEnabled = true
            annotationView?.isDraggable = false
        } else {
            annotationView?.annotation = annotation
        }
        
        // Check if this is the selected annotation
        if let selected = selectedAnnotation, selected.coordinate.latitude == annotation.coordinate.latitude && selected.coordinate.longitude == annotation.coordinate.longitude {
            // Highlight selected annotation
            annotationView?.markerTintColor = Constants.Colors.primary
            annotationView?.glyphImage = UIImage(systemName: "checkmark.circle.fill")
        } else {
            // Normal color based on category
            annotationView?.glyphImage = nil
            if let subtitle = annotation.subtitle {
                switch subtitle {
                case "Restaurant":
                    annotationView?.markerTintColor = UIColor.systemRed
                case "Café":
                    annotationView?.markerTintColor = UIColor.systemBrown
                case "Bar":
                    annotationView?.markerTintColor = UIColor.systemPurple
                case "Shop":
                    annotationView?.markerTintColor = UIColor.systemBlue
                default:
                    annotationView?.markerTintColor = UIColor.systemGreen
                }
            }
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation,
              !(annotation is MKUserLocation) else { return }
        
        guard let title = annotation.title,
              let name = title else { return }
        
        // Don't process "Selected Location" pins
        if name == "Selected Location" {
            return
        }
        
        // Update selected annotation
        selectedAnnotation = annotation
        
        // Look up the stored map item
        let lat = String(format: "%.6f", annotation.coordinate.latitude)
        let lon = String(format: "%.6f", annotation.coordinate.longitude)
        let coordinateKey = "\(lat),\(lon)"
        
        if let storedMapItem = mapItemsByCoordinate[coordinateKey] {
            // We have the full map item stored, use it directly
            DispatchQueue.main.async {
                self.fillFormWithMapItem(storedMapItem)
                self.searchBar.text = name
            }
        } else {
            // Fallback: search for this specific place to get full details
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            request.region = MKCoordinateRegion(
                center: annotation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
            )
            
            let search = MKLocalSearch(request: request)
            search.start { [weak self] response, error in
                guard let self = self,
                      let response = response,
                      let mapItem = response.mapItems.first else { return }
                
                DispatchQueue.main.async {
                    self.fillFormWithMapItem(mapItem)
                    self.searchBar.text = name
                }
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        // This is called when the detail disclosure button is tapped
        // We're now handling selection directly in didSelect, so this is optional
    }
}

// MARK: - UISearchBarDelegate

extension AddPlaceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchCompleter.queryFragment = searchText
        searchResultsTableView.isHidden = searchText.isEmpty
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

// MARK: - MKLocalSearchCompleterDelegate

extension AddPlaceViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        searchResultsTableView.reloadData()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AddPlaceViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle tap if we're tapping on an annotation
        if let view = touch.view {
            var superview = view.superview
            while superview != nil {
                if superview is MKAnnotationView {
                    return false // Let the map handle annotation taps
                }
                superview = superview?.superview
            }
        }
        return true
    }
}

// MARK: - UITableViewDataSource & Delegate

extension AddPlaceViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchCell", for: indexPath)
        let result = searchResults[indexPath.row]
        
        cell.textLabel?.text = result.title
        cell.detailTextLabel?.text = result.subtitle
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectSearchResult(searchResults[indexPath.row])
    }
}
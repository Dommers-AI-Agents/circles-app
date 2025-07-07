import UIKit
import MapKit
import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

class CircleDetailViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {
    
    // MARK: - Properties
    private var circle: Circle
    private var places: [Place] = []
    private var filteredPlaces: [Place] = []
    private var annotationPlaceMap: [ObjectIdentifier: Place] = [:]
    private let locationManager = CLLocationManager()
    private var userLocation: CLLocation?
    private var selectedCategory: PlaceCategory?
    
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
    
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let circleInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xxlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.tertiaryBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.white
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placesLabel: UILabel = {
        let label = UILabel()
        label.text = "Places"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("All Categories", for: .normal)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.semanticContentAttribute = .forceRightToLeft
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .medium)
        button.backgroundColor = Constants.Colors.tertiaryBackground
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 8)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        
        // Enable map controls
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.showsUserLocation = true
        
        return mapView
    }()
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.layer.cornerRadius = 12
        tableView.isScrollEnabled = false
        tableView.register(PlaceTableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dragInteractionEnabled = true
        tableView.estimatedRowHeight = 116
        tableView.rowHeight = UITableView.automaticDimension
        return tableView
    }()
    
    private let addPlaceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add Place", for: .normal)
        button.setTitleColor(Constants.Colors.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 25
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    
    // MARK: - Init
    
    init(circle: Circle) {
        self.circle = circle
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureUI()
        setupLocationManager()
        fetchPlaces()
        setupNotificationObservers()
        
        // Configure scroll view to avoid bottom overlap with Add Place button
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        scrollView.scrollIndicatorInsets = scrollView.contentInset
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh places when returning to this view
        fetchPlaces()
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
            // Denied or restricted - keep default NYC location
            break
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(headerView)
        headerView.addSubview(coverImageView)
        headerView.addSubview(circleInfoView)
        
        circleInfoView.addSubview(nameLabel)
        circleInfoView.addSubview(descriptionLabel)
        circleInfoView.addSubview(privacyView)
        circleInfoView.addSubview(categoryLabel)
        
        privacyView.addSubview(privacyImageView)
        privacyView.addSubview(privacyLabel)
        
        contentView.addSubview(placesLabel)
        contentView.addSubview(categoryFilterButton)
        contentView.addSubview(mapView)
        contentView.addSubview(tableView)
        
        view.addSubview(addPlaceButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Header view
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Cover image view
            coverImageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            coverImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            coverImageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Circle info view
            circleInfoView.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -20),
            circleInfoView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            circleInfoView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            circleInfoView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: circleInfoView.topAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.large),
            nameLabel.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.large),
            categoryLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.large),
            descriptionLabel.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Privacy view
            privacyView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.medium),
            privacyView.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.large),
            privacyView.heightAnchor.constraint(equalToConstant: 30),
            privacyView.bottomAnchor.constraint(equalTo: circleInfoView.bottomAnchor, constant: -Constants.Spacing.large),
            
            // Privacy image view
            privacyImageView.leadingAnchor.constraint(equalTo: privacyView.leadingAnchor, constant: Constants.Spacing.small),
            privacyImageView.centerYAnchor.constraint(equalTo: privacyView.centerYAnchor),
            privacyImageView.widthAnchor.constraint(equalToConstant: 16),
            privacyImageView.heightAnchor.constraint(equalToConstant: 16),
            
            // Privacy label
            privacyLabel.leadingAnchor.constraint(equalTo: privacyImageView.trailingAnchor, constant: Constants.Spacing.small),
            privacyLabel.trailingAnchor.constraint(equalTo: privacyView.trailingAnchor, constant: -Constants.Spacing.small),
            privacyLabel.centerYAnchor.constraint(equalTo: privacyView.centerYAnchor),
            
            // Places label
            placesLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: Constants.Spacing.large),
            placesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Category filter button
            categoryFilterButton.centerYAnchor.constraint(equalTo: placesLabel.centerYAnchor),
            categoryFilterButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            categoryFilterButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Map view
            mapView.topAnchor.constraint(equalTo: placesLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            mapView.heightAnchor.constraint(equalToConstant: 200),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.large),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -100), // Increased bottom padding for Add Place button
            
            // Add place button
            addPlaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            addPlaceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.medium),
            addPlaceButton.widthAnchor.constraint(equalToConstant: 120),
            addPlaceButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Set initial table view height
        tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        
        // Setup button actions
        addPlaceButton.addTarget(self, action: #selector(addPlaceButtonTapped), for: .touchUpInside)
        categoryFilterButton.addTarget(self, action: #selector(categoryFilterButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to map
        let mapTapGesture = UITapGestureRecognizer(target: self, action: #selector(mapViewTapped))
        mapView.addGestureRecognizer(mapTapGesture)
        
        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        
        // Setup map view delegate
        mapView.delegate = self
    }
    
    private func configureUI() {
        title = circle.name
        
        // Navigation bar buttons
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonTapped))
        let editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editButtonTapped))
        navigationItem.rightBarButtonItems = [shareButton, editButton]
        
        // Cover image
        if let coverImageUrl = circle.coverImage {
            // Load image from URL
            ImageService.shared.loadImage(from: coverImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.coverImageView.image = image
                }
            }
        } else {
            // Default image based on category
            switch circle.category {
            case .travel:
                coverImageView.image = UIImage(systemName: "airplane.departure")
            case .food:
                coverImageView.image = UIImage(systemName: "fork.knife")
            case .services:
                coverImageView.image = UIImage(systemName: "wrench.and.screwdriver")
            case .shopping:
                coverImageView.image = UIImage(systemName: "bag")
            case .healthcare:
                coverImageView.image = UIImage(systemName: "heart.text.square")
            case .entertainment:
                coverImageView.image = UIImage(systemName: "ticket")
            case .other:
                coverImageView.image = UIImage(systemName: "square.grid.2x2")
            }
            coverImageView.tintColor = Constants.Colors.primary
            coverImageView.contentMode = .scaleAspectFit
            coverImageView.backgroundColor = Constants.Colors.background
        }
        
        // Circle name and description
        nameLabel.text = circle.name
        descriptionLabel.text = circle.description ?? "No description provided"
        
        // Privacy settings
        switch circle.privacy {
        case .public:
            privacyImageView.image = UIImage(systemName: "globe")
            privacyLabel.text = "Public"
        case .myNetwork:
            privacyImageView.image = UIImage(systemName: "person.2")
            privacyLabel.text = "My Network"
        case .private:
            privacyImageView.image = UIImage(systemName: "lock")
            privacyLabel.text = "Private"
        }
        
        // Category
        categoryLabel.text = "  \(circle.category.rawValue.capitalized)  " // Add padding with spaces
        
        // Set category color
        switch circle.category {
        case .travel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .food:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
        case .services:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .shopping:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        mapView.delegate = self
    }
    
    // MARK: - Data Fetching
    private func fetchPlaces() {
        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let places):
                    // Debug logging
                    print("🔍 CircleDetailViewController - Fetched \(places.count) places")
                    for (index, place) in places.enumerated() {
                        print("  Place \(index + 1): \(place.name)")
                        print("    - ID: \(place.id)")
                        print("    - Has photos: \(place.hasPhotos)")
                        print("    - Photos: \(place.photos ?? [])")
                    }
                    
                    // Places are already ordered by the backend based on the circle's places array
                    self?.places = places
                    self?.applyFilter()
                case .failure(let error):
                    print("❌ Error fetching places: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                    // Don't use sample places - show empty state instead
                    self?.places = []
                    self?.filteredPlaces = []
                }
                
                self?.tableView.reloadData()
                
                // Force layout update to calculate correct content size
                DispatchQueue.main.async {
                    self?.tableView.layoutIfNeeded()
                    self?.updateTableViewHeight()
                }
                
                self?.addAnnotationsToMap()
            }
        }
    }
    
    // COMMENTED OUT: This method was creating test data but the Place struct no longer has a direct initializer
    // If sample data is needed in the future, it should be created using proper JSON decoding
    /*
    private func createSamplePlaces() -> [Place] {
        // Create sample places based on the circle's category
        
        let userId = AuthService.shared.getUserId() ?? "user123"
        let date = Date()
        
        var samplePlaces: [Place] = []
        
        switch circle.category {
        case .travel:
            // New York travel places
            let place1 = Place(
                id: "place1",
                name: "Central Park",
                description: "Urban park in Manhattan",
                address: "Central Park, New York, NY",
                location: GeoLocation(type: "Point", coordinates: [-73.9665, 40.7812]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .attraction,
                rating: 4.8,
                userRatingsTotal: 432,
                notes: "Beautiful park to walk around",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["park", "nature", "walking"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 5),
                updatedAt: date
            )
            
            let place2 = Place(
                id: "place2",
                name: "Empire State Building",
                description: "Historic 102-story skyscraper",
                address: "20 W 34th St, New York, NY 10001",
                location: GeoLocation(type: "Point", coordinates: [-73.9857, 40.7484]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .attraction,
                rating: 4.7,
                userRatingsTotal: 289,
                notes: "Great views from the observation deck",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["landmark", "skyscraper", "view"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 4),
                updatedAt: date
            )
            
            let place3 = Place(
                id: "place3",
                name: "The Metropolitan Museum of Art",
                description: "Art museum on the east side of Central Park",
                address: "1000 5th Ave, New York, NY 10028",
                location: GeoLocation(type: "Point", coordinates: [-73.9632, 40.7794]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .attraction,
                rating: 4.8,
                userRatingsTotal: 376,
                notes: "Amazing collection of art",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["museum", "art", "culture"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 3),
                updatedAt: date
            )
            
            samplePlaces = [place1, place2, place3]
            
        case .food:
            // Restaurant places
            let place1 = Place(
                id: "place4",
                name: "Le Bernardin",
                description: "Upscale French seafood restaurant",
                address: "155 W 51st St, New York, NY 10019",
                location: GeoLocation(type: "Point", coordinates: [-73.9819, 40.7614]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .restaurant,
                rating: 4.9,
                userRatingsTotal: 156,
                notes: "Amazing seafood, get the chef's tasting menu",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["seafood", "french", "fine dining"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 5),
                updatedAt: date
            )
            
            let place2 = Place(
                id: "place5",
                name: "Gramercy Tavern",
                description: "Upscale American restaurant",
                address: "42 E 20th St, New York, NY 10003",
                location: GeoLocation(type: "Point", coordinates: [-73.9880, 40.7387]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .restaurant,
                rating: 4.8,
                userRatingsTotal: 223,
                notes: "Seasonal American cuisine, great atmosphere",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["american", "seasonal", "tavern"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 4),
                updatedAt: date
            )
            
            samplePlaces = [place1, place2]
            
        case .shopping:
            // Shopping places
            let place1 = Place(
                id: "place6",
                name: "Fifth Avenue",
                description: "Famous shopping street",
                address: "5th Ave, New York, NY",
                location: GeoLocation(type: "Point", coordinates: [-73.9745, 40.7636]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .retail,
                rating: 4.7,
                userRatingsTotal: 498,
                notes: "Luxury shopping district",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["luxury", "fashion", "shopping district"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 5),
                updatedAt: date
            )
            
            let place2 = Place(
                id: "place7",
                name: "Bloomingdale's",
                description: "Upscale department store",
                address: "1000 3rd Ave, New York, NY 10022",
                location: GeoLocation(type: "Point", coordinates: [-73.9668, 40.7621]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .retail,
                rating: 4.5,
                userRatingsTotal: 187,
                notes: "Great selection of designer clothes",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["department store", "fashion", "luxury"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 4),
                updatedAt: date
            )
            
            let place3 = Place(
                id: "place8",
                name: "Chelsea Market",
                description: "Food hall and shopping center",
                address: "75 9th Ave, New York, NY 10011",
                location: GeoLocation(type: "Point", coordinates: [-74.0048, 40.7420]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .retail,
                rating: 4.7,
                userRatingsTotal: 334,
                notes: "Great mix of food vendors and shopping",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["market", "food hall", "shopping"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 3),
                updatedAt: date
            )
            
            let place4 = Place(
                id: "place9",
                name: "SoHo Shopping District",
                description: "Trendy shopping area",
                address: "SoHo, New York, NY",
                location: GeoLocation(type: "Point", coordinates: [-74.0023, 40.7248]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .retail,
                rating: 4.8,
                userRatingsTotal: 421,
                notes: "Trendy shops and boutiques",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["trendy", "boutiques", "shopping district"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400 * 2),
                updatedAt: date
            )
            
            samplePlaces = [place1, place2, place3, place4]
            
        default:
            // Create a generic place for other categories
            let place = Place(
                id: "place10",
                name: "Sample Place",
                description: "A sample place for this circle",
                address: "123 Main St, New York, NY 10001",
                location: GeoLocation(type: "Point", coordinates: [-73.9857, 40.7484]),
                website: nil,
                phone: nil,
                googlePlaceId: nil,
                photos: nil,
                category: .other,
                rating: 4.5,
                userRatingsTotal: 92,
                notes: "This is a sample place",
                privateNotes: nil,
                publicNotes: nil,
                tags: ["sample"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                addedByUser: nil,
                privacy: .followCirclePrivacy,
                createdAt: date.addingTimeInterval(-86400),
                updatedAt: date
            )
            
            samplePlaces = [place]
        }
        
        // Sort sample places by createdAt date, most recent first
        return samplePlaces.sorted { $0.createdAt > $1.createdAt }
    }
    */
    
    private func updateTableViewHeight() {
        // Force layout to calculate proper content size
        tableView.layoutIfNeeded()
        
        // Use the table's content size for height
        let height = tableView.contentSize.height
        
        // Update table view height constraint
        if let constraint = tableView.constraints.first(where: { $0.firstAttribute == .height }) {
            constraint.constant = height
        } else {
            tableView.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
    }
    
    private func addAnnotationsToMap() {
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)
        annotationPlaceMap.removeAll()
        
        var mapRect = MKMapRect.null
        
        for place in filteredPlaces {
            if let location = place.location?.clLocation {
                let annotation = PlaceAnnotation(place: place)
                mapView.addAnnotation(annotation)
                
                // Store the place reference
                annotationPlaceMap[ObjectIdentifier(annotation)] = place
                
                // Update map rect
                let point = MKMapPoint(location.coordinate)
                let rect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                mapRect = mapRect.union(rect)
            }
        }
        
        // Adjust map to show all annotations
        if !mapRect.isNull {
            // Calculate the current rect size
            let rectWidth = mapRect.width
            let rectHeight = mapRect.height
            
            // If the rect is very small (places are close together), expand it
            let minSize: Double = 10000 // Minimum 10km
            if rectWidth < minSize || rectHeight < minSize {
                // Expand the rect to have a minimum size
                let expandX = max(0, (minSize - rectWidth) / 2)
                let expandY = max(0, (minSize - rectHeight) / 2)
                mapRect = mapRect.insetBy(dx: -expandX, dy: -expandY)
            }
            
            // Reduce padding for a tighter view
            let padding = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            mapView.setVisibleMapRect(mapRect, edgePadding: padding, animated: true)
        } else if let userLocation = locationManager.location {
            // Center on user location if no places
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 2000,  // Reduced from 5000 to 2000 meters
                longitudinalMeters: 2000
            )
            mapView.setRegion(region, animated: true)
        }
    }
    
    private func createMarkerView(for category: PlaceCategory) -> UIView? {
        // Create a Google Maps style circle marker with category icon
        let markerSize: CGFloat = 36
        let view = UIView(frame: CGRect(x: 0, y: 0, width: markerSize, height: markerSize))
        
        // Background circle
        let circleView = UIView(frame: CGRect(x: 0, y: 0, width: markerSize, height: markerSize))
        circleView.backgroundColor = .white
        circleView.layer.cornerRadius = markerSize / 2
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        circleView.layer.shadowRadius = 4
        circleView.layer.shadowOpacity = 0.3
        
        // Inner colored circle
        let innerCircle = UIView(frame: CGRect(x: 3, y: 3, width: markerSize - 6, height: markerSize - 6))
        innerCircle.backgroundColor = categoryColor(for: category)
        innerCircle.layer.cornerRadius = (markerSize - 6) / 2
        
        // Category icon
        let iconView = UIImageView(frame: CGRect(x: 8, y: 8, width: 20, height: 20))
        iconView.image = UIImage(systemName: categoryIcon(for: category))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        
        view.addSubview(circleView)
        circleView.addSubview(innerCircle)
        circleView.addSubview(iconView)
        
        return view
    }
    
    private func categoryColor(for category: PlaceCategory) -> UIColor {
        switch category {
        case .restaurant:
            return UIColor(hex: "#E53E3E") // Red
        case .cafe:
            return UIColor(hex: "#DD6B20") // Orange
        case .bar:
            return UIColor(hex: "#7B341E") // Brown
        case .hotel:
            return UIColor(hex: "#3182CE") // Blue
        case .retail:
            return UIColor(hex: "#805AD5") // Purple
        case .service:
            return UIColor(hex: "#38A169") // Green
        case .attraction:
            return UIColor(hex: "#D69E2E") // Yellow
        case .entertainment:
            return UIColor(hex: "#9C4221") // Orange Brown
        case .healthcare:
            return UIColor(hex: "#319795") // Teal
        case .fitness:
            return UIColor(hex: "#2C7A7B") // Dark Teal
        case .education:
            return UIColor(hex: "#744210") // Dark Yellow
        case .outdoor:
            return UIColor(hex: "#2F855A") // Dark Green
        case .transport:
            return UIColor(hex: "#2B6CB0") // Dark Blue
        case .finance:
            return UIColor(hex: "#285E61") // Dark Teal
        case .home:
            return UIColor(hex: "#3182CE") // Blue
        case .work:
            return UIColor(hex: "#38A169") // Green
        case .other:
            return UIColor(hex: "#38A169") // Green
        }
    }
    
    private func categoryIcon(for category: PlaceCategory) -> String {
        switch category {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .hotel: return "bed.double"
        case .retail: return "bag"
        case .service: return "wrench.and.screwdriver"
        case .attraction: return "star"
        case .entertainment: return "ticket"
        case .healthcare: return "cross.case"
        case .fitness: return "figure.run"
        case .education: return "book"
        case .outdoor: return "tree"
        case .transport: return "car"
        case .finance: return "dollarsign.circle"
        case .home: return "house"
        case .work: return "building.2"
        case .other: return "mappin"
        }
    }
    
    // MARK: - Actions
    @objc private func shareButtonTapped() {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: nil, message: "Creating share link...", preferredStyle: .alert)
        let loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor, constant: 30)
        ])
        present(loadingAlert, animated: true)
        
        // Create share link via API
        CircleService.shared.createShareLink(
            circleId: circle.id,
            shareType: .link,
            accessLevel: .viewOnly,
            expiresIn: 30 // 30 days expiration
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let share):
                        self?.presentShareSheet(with: share)
                    case .failure(let error):
                        self?.showShareError(error)
                    }
                }
            }
        }
    }
    
    private func presentShareSheet(with share: CircleShare) {
        // Create formatted text to share
        var shareText = "🟦 \(circle.name)"
        if let description = circle.description {
            shareText += "\n\(description)"
        }
        
        let memberCount = (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        if memberCount > 0 {
            shareText += "\n👥 \(memberCount) member\(memberCount != 1 ? "s" : "")"
        }
        
        let placeCount = places.count
        shareText += "\n📍 \(placeCount) place\(placeCount != 1 ? "s" : "")"
        
        // Add privacy emoji
        switch circle.privacy {
        case .public:
            shareText += " 🌐"
        case .myNetwork:
            shareText += " 👥"
        case .private:
            shareText += " 🔒"
        }
        
        // Add deep link
        if let shareLink = share.shareLink {
            shareText += "\n\nOpen in Circles: \(shareLink)"
        }
        
        // Add app download link
        let appStoreLink = "https://apps.apple.com/app/circles/id123456789" // TODO: Replace with actual App Store link
        shareText += "\n\nDon't have Circles? Download here: \(appStoreLink)"
        
        var activityItems: [Any] = [shareText]
        
        // Add the direct deep link URL as a separate item for better sharing
        if let shareLink = share.shareLink, let url = URL(string: shareLink) {
            activityItems.append(url)
        }
        
        // Function to present the share sheet
        let presentShareSheet = { [weak self] in
            let activityViewController = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )
            
            // For iPad
            if let popover = activityViewController.popoverPresentationController {
                popover.barButtonItem = self?.navigationItem.rightBarButtonItems?.first { $0.action == #selector(self?.shareButtonTapped) }
            }
            
            self?.present(activityViewController, animated: true)
        }
        
        // Add cover image if available (load asynchronously)
        if let coverImageUrl = circle.coverImage,
           let url = URL(string: coverImageUrl) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    if let data = data, let image = UIImage(data: data) {
                        activityItems.append(image)
                    }
                    presentShareSheet()
                }
            }.resume()
        } else {
            presentShareSheet()
        }
    }
    
    private func showShareError(_ error: Error) {
        let alert = UIAlertController(
            title: "Share Failed",
            message: "Unable to create share link. Please try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func editButtonTapped() {
        let editCircleVC = EditCircleViewController(circle: circle)
        editCircleVC.delegate = self
        let navController = UINavigationController(rootViewController: editCircleVC)
        present(navController, animated: true)
    }
    
    @objc private func addPlaceButtonTapped() {
        // Directly open the AddPlaceViewController with map and search functionality
        let addPlaceVC = AddPlaceViewController(circleId: circle.id)
        navigationController?.pushViewController(addPlaceVC, animated: true)
    }
    
    @objc private func mapViewTapped() {
        presentFullScreenMap()
    }
    
    @objc private func categoryFilterButtonTapped() {
        showCategoryFilterMenu()
    }
    
    private func showCategoryFilterMenu() {
        let actionSheet = UIAlertController(title: "Filter by Category", message: nil, preferredStyle: .actionSheet)
        
        // All categories option
        actionSheet.addAction(UIAlertAction(title: "All Categories", style: .default) { [weak self] _ in
            self?.selectedCategory = nil
            self?.categoryFilterButton.setTitle("All Categories", for: .normal)
            self?.applyFilter()
        })
        
        // Get unique categories from places
        let categories = Set(places.map { $0.category })
        let sortedCategories = categories.sorted { $0.displayName < $1.displayName }
        
        // Add action for each category
        for category in sortedCategories {
            actionSheet.addAction(UIAlertAction(title: category.displayName, style: .default) { [weak self] _ in
                self?.selectedCategory = category
                self?.categoryFilterButton.setTitle(category.displayName, for: .normal)
                self?.applyFilter()
            })
        }
        
        // Cancel action
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = categoryFilterButton
            popover.sourceRect = categoryFilterButton.bounds
        }
        
        present(actionSheet, animated: true)
    }
    
    private func applyFilter() {
        if let category = selectedCategory {
            filteredPlaces = places.filter { $0.category == category }
        } else {
            filteredPlaces = places
        }
        
        tableView.reloadData()
        
        // Update table view height
        DispatchQueue.main.async { [weak self] in
            self?.tableView.layoutIfNeeded()
            self?.updateTableViewHeight()
        }
        
        // Update map annotations
        addAnnotationsToMap()
    }
    
    private func presentFullScreenMap() {
        let fullScreenMapVC = FullScreenMapViewController(places: filteredPlaces, initialRegion: mapView.region, selectedCategory: selectedCategory)
        fullScreenMapVC.delegate = self
        fullScreenMapVC.isPresentedModally = true
        present(fullScreenMapVC, animated: true)
    }
    
    private func setupNotificationObservers() {
        // Observe when user wants to view place details from full-screen map
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowPlaceDetails(_:)),
            name: Notification.Name("ShowPlaceDetails"),
            object: nil
        )
        
        // Observe when user wants to add a POI from full-screen map
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAddPOIToCircle(_:)),
            name: Notification.Name("AddPOIToCircle"),
            object: nil
        )
    }
    
    @objc private func handleShowPlaceDetails(_ notification: Notification) {
        guard let place = notification.userInfo?["place"] as? Place else { return }
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    @objc private func handleAddPOIToCircle(_ notification: Notification) {
        guard let placeID = notification.userInfo?["placeID"] as? String,
              let name = notification.userInfo?["name"] as? String,
              let location = notification.userInfo?["location"] as? CLLocationCoordinate2D else { return }
        
        // Fetch place details from Google
        fetchGooglePlaceDetails(placeID: placeID, name: name, location: location)
    }
    
    private func fetchGooglePlaceDetails(placeID: String, name: String, location: CLLocationCoordinate2D) {
        // Show loading indicator
        let alert = UIAlertController(title: "Loading", message: "Fetching place details...", preferredStyle: .alert)
        present(alert, animated: true)
        
        GooglePlacesService.shared.fetchPlaceDetails(placeID: placeID) { [weak self] result in
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    switch result {
                    case .success(let gmsPlace):
                        self?.addGooglePlace(gmsPlace: gmsPlace, placeID: placeID)
                    case .failure(let error):
                        print("Failed to fetch place details: \(error)")
                        // Fallback to basic place info
                        self?.addPlaceWithCoordinates(name: name, location: location, placeID: placeID)
                    }
                }
            }
        }
    }
    
    private func presentGooglePlacesSearch() {
        // Navigate to PlaceSearchViewController for Apple Maps search
        let placeSearchVC = PlaceSearchViewController()
        placeSearchVC.delegate = self
        let navController = UINavigationController(rootViewController: placeSearchVC)
        present(navController, animated: true)
    }
    
    private func sharePlace(_ place: Place) {
        // Create a formatted string with place name prominently displayed
        var shareText = "Check out \(place.name)!"
        
        if let description = place.description, !description.isEmpty {
            shareText += "\n\n\(description)"
        }
        
        // Category
        shareText += "\n\n🏷️ \(place.category.displayName)"
        
        // Address
        shareText += "\n📍 \(place.address)"
        
        // Rating if available
        if let rating = place.rating {
            let stars = String(repeating: "⭐", count: Int(rating.rounded()))
            shareText += "\n\(stars) \(rating)/5.0"
        }
        
        // Contact info if available
        if let phone = place.phone, !phone.isEmpty {
            shareText += "\n📞 \(phone)"
        }
        
        if let website = place.website, !website.isEmpty {
            shareText += "\n🌐 \(website)"
        }
        
        // Add to your places message
        shareText += "\n\n➕ Add this place to your Circles!"
        
        // Deep link to open/add the place in Circles
        let deepLink = "circles://place/\(place.id)"
        shareText += "\n📱 Open in Circles: \(deepLink)"
        
        // App Store link (use TestFlight for now)
        let appStoreLink = "https://testflight.apple.com/join/YourTestFlightLink" // Replace with actual App Store link
        shareText += "\n\nDon't have Circles? Download here: \(appStoreLink)"
        
        var activityItems: [Any] = [shareText]
        
        // Add location as Apple Maps link with place name
        if let location = place.location?.clLocation {
            // Create Apple Maps URL with place name
            let escapedName = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let appleMapsURL = "https://maps.apple.com/?q=\(escapedName)&ll=\(location.coordinate.latitude),\(location.coordinate.longitude)"
            if let url = URL(string: appleMapsURL) {
                activityItems.append(url)
            }
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(activityViewController, animated: true)
    }
    
    private func openPlaceInMaps(_ place: Place) {
        guard let location = place.location?.clLocation else { 
            // Show alert if no location available
            let alert = UIAlertController(
                title: "No Location Available",
                message: "This place doesn't have location information.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return 
        }
        
        // Create the Apple Maps item with destination
        let coordinate = location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = place.name
        
        // Open in Apple Maps with directions
        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]
        
        mapItem.openInMaps(launchOptions: launchOptions)
    }
    
    private func likePlace(_ place: Place) {
        // Disable interaction while processing
        view.isUserInteractionEnabled = false
        
        PlaceService.shared.likePlace(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.view.isUserInteractionEnabled = true
                
                switch result {
                case .success(let updatedPlace):
                    // Update the place in our filtered list
                    if let index = self?.filteredPlaces.firstIndex(where: { $0.id == place.id }) {
                        self?.filteredPlaces[index] = updatedPlace
                        self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    }
                case .failure(let error):
                    print("Failed to like place: \(error)")
                    // Show error alert
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to like place. Please try again.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }
    
    private func showComments(for place: Place) {
        let commentsVC = PlaceCommentsViewController(place: place)
        let navController = UINavigationController(rootViewController: commentsVC)
        present(navController, animated: true)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension CircleDetailViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath) as? PlaceTableViewCell else {
            return UITableViewCell()
        }
        
        let place = filteredPlaces[indexPath.row]
        cell.configure(with: place)
        
        // Set up share button action
        cell.onShareTapped = { [weak self] place in
            self?.sharePlace(place)
        }
        
        // Set up directions button action
        cell.onDirectionsTapped = { [weak self] place in
            self?.openPlaceInMaps(place)
        }
        
        // Set up like button action
        cell.onLikeTapped = { [weak self] place in
            self?.likePlace(place)
        }
        
        // Set up comment button action
        cell.onCommentTapped = { [weak self] place in
            self?.showComments(for: place)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let place = filteredPlaces[indexPath.row]
        
        // Debug logging
        print("🔍 CircleDetailViewController - Selected place:")
        print("  - Place name: \(place.name)")
        print("  - Place ID: \(place.id)")
        print("  - Has photos: \(place.hasPhotos)")
        print("  - Photos array: \(place.photos ?? [])")
        print("  - Photos count: \(place.photos?.count ?? 0)")
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    // MARK: - Swipe Actions
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only allow deletion for own circles
        guard circle.isOwner else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDeletePlace(at: indexPath, completion: completion)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        
        return configuration
    }
    
    private func confirmDeletePlace(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        let place = filteredPlaces[indexPath.row]
        
        let alert = UIAlertController(
            title: "Delete Place",
            message: "Are you sure you want to remove \"\(place.name)\" from this circle?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deletePlace(at: indexPath)
            completion(true)
        })
        
        present(alert, animated: true)
    }
    
    private func deletePlace(at indexPath: IndexPath) {
        let place = filteredPlaces[indexPath.row]
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Deleting", message: "Removing place...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.deletePlace(id: place.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Remove from local arrays
                        if let originalIndex = self?.places.firstIndex(where: { $0.id == place.id }) {
                            self?.places.remove(at: originalIndex)
                        }
                        if let filteredIndex = self?.filteredPlaces.firstIndex(where: { $0.id == place.id }) {
                            self?.filteredPlaces.remove(at: filteredIndex)
                        }
                        
                        // Update table view
                        self?.tableView.deleteRows(at: [indexPath], with: .fade)
                        
                        // Update map
                        self?.addAnnotationsToMap()
                        
                        // Update table view height after deletion
                        self?.updateTableViewHeight()
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to delete place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Drag Delegate
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Disable drag when filtering
        guard selectedCategory == nil else { return [] }
        
        let place = filteredPlaces[indexPath.row]
        let itemProvider = NSItemProvider(object: place.id as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = place
        return [dragItem]
    }
    
    // MARK: - Drop Delegate
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.text.identifier])
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if tableView.hasActiveDrag {
            if session.items.count > 1 {
                return UITableViewDropProposal(operation: .cancel)
            } else {
                return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
        } else {
            return UITableViewDropProposal(operation: .forbidden)
        }
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        for item in coordinator.items {
            guard let sourceIndexPath = item.sourceIndexPath else { continue }
            
            tableView.performBatchUpdates({
                let movedPlace = places.remove(at: sourceIndexPath.row)
                places.insert(movedPlace, at: destinationIndexPath.row)
                tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
            })
            
            coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            
            // Update the order in the backend
            updatePlaceOrder()
        }
    }
    
    // MARK: - Helper method to update place order
    private func updatePlaceOrder() {
        // Update the order of places in the backend
        Task {
            do {
                // Create an array of place IDs in the new order
                let orderedPlaceIds = places.map { $0.id }
                
                // Call the API to update the order
                try await PlaceService.shared.updatePlaceOrder(circleId: circle.id, placeIds: orderedPlaceIds)
                
                // Update map annotations to reflect new order if needed
                await MainActor.run {
                    self.addAnnotationsToMap()
                }
            } catch {
                print("Failed to update place order: \(error)")
                // Optionally, revert the changes if the API call fails
                await MainActor.run {
                    self.fetchPlaces()
                }
            }
        }
    }
}

// MARK: - PlaceTableViewCell
class PlaceTableViewCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let imageLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.primary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let imageGradientView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = false
        label.alpha = 1.0
        label.backgroundColor = .clear
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = Constants.Colors.white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private let ratingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.tertiaryBackground
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let ratingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "star.fill")
        imageView.tintColor = UIColor(hex: "#F6E05E") // Yellow
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let ratingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let directionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let likeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        return label
    }()
    
    private let commentButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "bubble.right"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentMode = .scaleAspectFit
        return button
    }()
    
    private let commentCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        return label
    }()
    
    // Closure for share action
    var onShareTapped: ((Place) -> Void)?
    var onDirectionsTapped: ((Place) -> Void)?
    var onLikeTapped: ((Place) -> Void)?
    var onCommentTapped: ((Place) -> Void)?
    private var place: Place?
    private var photoLoadingTask: URLSessionDataTask?
    
    // Image cache specifically for Google Places photos
    private static let googlePhotosCache = NSCache<NSString, UIImage>()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupCell() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        containerView.addSubview(placeImageView)
        containerView.addSubview(imageGradientView)
        containerView.addSubview(categoryIconView)
        containerView.addSubview(imageLoadingIndicator)
        containerView.addSubview(nameLabel)
        containerView.addSubview(categoryLabel)
        containerView.addSubview(addressLabel)
        containerView.addSubview(ratingView)
        containerView.addSubview(shareButton)
        containerView.addSubview(directionsButton)
        containerView.addSubview(likeButton)
        containerView.addSubview(likeCountLabel)
        containerView.addSubview(commentButton)
        containerView.addSubview(commentCountLabel)
        
        ratingView.addSubview(ratingImageView)
        ratingView.addSubview(ratingLabel)
        
        // Add target for share button
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        // Add target for directions button
        directionsButton.addTarget(self, action: #selector(directionsButtonTapped), for: .touchUpInside)
        // Add target for like button
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        // Add target for comment button
        commentButton.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.small),
            
            // Place image view
            placeImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            placeImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            placeImageView.widthAnchor.constraint(equalToConstant: 80),
            placeImageView.heightAnchor.constraint(equalToConstant: 80),
            placeImageView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small),
            
            // Image gradient view (same as image view)
            imageGradientView.topAnchor.constraint(equalTo: placeImageView.topAnchor),
            imageGradientView.leadingAnchor.constraint(equalTo: placeImageView.leadingAnchor),
            imageGradientView.trailingAnchor.constraint(equalTo: placeImageView.trailingAnchor),
            imageGradientView.bottomAnchor.constraint(equalTo: placeImageView.bottomAnchor),
            
            // Category icon view (centered on top of image view)
            categoryIconView.centerXAnchor.constraint(equalTo: placeImageView.centerXAnchor),
            categoryIconView.centerYAnchor.constraint(equalTo: placeImageView.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: 40),
            categoryIconView.heightAnchor.constraint(equalToConstant: 40),
            
            // Image loading indicator
            imageLoadingIndicator.centerXAnchor.constraint(equalTo: placeImageView.centerXAnchor),
            imageLoadingIndicator.centerYAnchor.constraint(equalTo: placeImageView.centerYAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            nameLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.trailingAnchor.constraint(equalTo: directionsButton.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Directions button
            directionsButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            directionsButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -Constants.Spacing.tiny),
            directionsButton.widthAnchor.constraint(equalToConstant: 30),
            directionsButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Share button
            shareButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            shareButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            shareButton.widthAnchor.constraint(equalToConstant: 30),
            shareButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            categoryLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20),
            
            // Address label
            addressLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            addressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Rating view
            ratingView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.small),
            ratingView.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            ratingView.widthAnchor.constraint(equalToConstant: 60),
            ratingView.heightAnchor.constraint(equalToConstant: 22),
            
            // Like button - reduced spacing and size
            likeButton.leadingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: Constants.Spacing.small),
            likeButton.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            likeButton.widthAnchor.constraint(equalToConstant: 20),
            likeButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Like count label - reduced spacing and width constraint
            likeCountLabel.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor, constant: 2),
            likeCountLabel.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            likeCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 24),
            
            // Comment button - reduced spacing and size
            commentButton.leadingAnchor.constraint(equalTo: likeCountLabel.trailingAnchor, constant: Constants.Spacing.xsmall),
            commentButton.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            commentButton.widthAnchor.constraint(equalToConstant: 20),
            commentButton.heightAnchor.constraint(equalToConstant: 20),
            
            // Comment count label - reduced spacing and width constraint
            commentCountLabel.leadingAnchor.constraint(equalTo: commentButton.trailingAnchor, constant: 2),
            commentCountLabel.centerYAnchor.constraint(equalTo: commentButton.centerYAnchor),
            commentCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 24),
            commentCountLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Rating image view
            ratingImageView.leadingAnchor.constraint(equalTo: ratingView.leadingAnchor, constant: Constants.Spacing.tiny),
            ratingImageView.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            ratingImageView.widthAnchor.constraint(equalToConstant: 14),
            ratingImageView.heightAnchor.constraint(equalToConstant: 14),
            
            // Rating label
            ratingLabel.leadingAnchor.constraint(equalTo: ratingImageView.trailingAnchor, constant: 2),
            ratingLabel.trailingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: -Constants.Spacing.tiny),
            ratingLabel.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor)
        ])
    }
    
    // MARK: - Configure
    func configure(with place: Place) {
        self.place = place
        nameLabel.text = place.name.isEmpty ? "Unnamed Place" : place.name
        
        // Highlight new places
        if place.isNew == true {
            containerView.layer.borderColor = Constants.Colors.primary.cgColor
            containerView.layer.borderWidth = 2
            containerView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.05)
            
            // Add new badge to name
            let attributedString = NSMutableAttributedString(string: nameLabel.text ?? "")
            let newBadge = NSAttributedString(
                string: " NEW",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: Constants.Colors.primary,
                    .backgroundColor: Constants.Colors.primary.withAlphaComponent(0.1)
                ]
            )
            attributedString.append(newBadge)
            nameLabel.attributedText = attributedString
        } else {
            containerView.layer.borderColor = Constants.Colors.separator.cgColor
            containerView.layer.borderWidth = 1
            containerView.backgroundColor = Constants.Colors.secondaryBackground
            nameLabel.attributedText = nil
            nameLabel.text = place.name.isEmpty ? "Unnamed Place" : place.name
        }
        
        // Category label
        categoryLabel.text = "  \(place.displayCategory)  " // Add padding with spaces
        
        // Set category color and icon
        setCategoryAppearance(for: place.category)
        
        // Initially show category icon while loading photo
        categoryIconView.isHidden = false
        placeImageView.image = nil
        imageGradientView.isHidden = true
        
        // Setup gradient layer
        setupGradientLayer()
        
        // Cancel any previous photo loading task
        photoLoadingTask?.cancel()
        
        // Load place photo
        loadPlacePhoto(for: place)
        
        // Address
        if !place.address.isEmpty {
            addressLabel.text = place.address
        } else {
            addressLabel.text = "No address available"
        }
        
        // Rating
        if let rating = place.rating {
            ratingLabel.text = String(format: "%.1f", rating)
        } else {
            ratingLabel.text = "N/A"
        }
        
        // Like button and count
        let isLiked = place.isLikedByCurrentUser
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : Constants.Colors.primary
        
        let likeCount = place.likesCount ?? 0
        likeCountLabel.text = likeCount > 0 ? "\(likeCount)" : ""
        
        // Comment count (will need to fetch separately)
        commentCountLabel.text = ""
        
        // Show/hide directions button based on location availability
        directionsButton.isHidden = (place.location == nil)
        
        // Force layout update
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    // MARK: - Photo Loading
    private func loadPlacePhoto(for place: Place) {
        // First check if we have stored photo URLs
        if let photos = place.photos, !photos.isEmpty, let firstPhotoUrl = photos.first {
            // Load from URL if available
            loadPhotoFromURL(firstPhotoUrl)
        } else {
            // No photo available, use category icon
            // Don't call Google Places API to save costs
            showCategoryIcon()
        }
    }
    
    // Removed loadGooglePlacePhoto to avoid unnecessary API calls
    // All photos should be stored when the place is created
    
    private func loadPhotoFromURL(_ urlString: String) {
        imageLoadingIndicator.startAnimating()
        
        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.placeImageView.image = image
                self.categoryIconView.isHidden = true
                self.imageGradientView.isHidden = false
            } else {
                self.showCategoryIcon()
            }
            self.imageLoadingIndicator.stopAnimating()
        }
    }
    
    private func showCategoryIcon() {
        categoryIconView.isHidden = false
        placeImageView.image = nil
        imageGradientView.isHidden = true
    }
    
    private func setupGradientLayer() {
        // Remove existing gradient layers
        imageGradientView.layer.sublayers?.forEach { if $0 is CAGradientLayer { $0.removeFromSuperlayer() } }
        
        // Create gradient layer
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.3).cgColor
        ]
        gradientLayer.locations = [0.5, 1.0]
        gradientLayer.cornerRadius = 8
        
        imageGradientView.layer.addSublayer(gradientLayer)
    }
    
    private func setCategoryAppearance(for category: PlaceCategory) {
        // Set category label color
        switch category {
        case .restaurant:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
            categoryIconView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
            categoryIconView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            categoryLabel.backgroundColor = UIColor(hex: "#7B341E") // Brown
            categoryIconView.image = UIImage(systemName: "wineglass")
        case .hotel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            categoryIconView.image = UIImage(systemName: "bed.double")
        case .retail:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
            categoryIconView.image = UIImage(systemName: "bag")
        case .service:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
            categoryIconView.image = UIImage(systemName: "star")
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#9C4221") // Orange Brown
            categoryIconView.image = UIImage(systemName: "ticket")
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#319795") // Teal
            categoryIconView.image = UIImage(systemName: "cross.case")
        case .fitness:
            categoryLabel.backgroundColor = UIColor(hex: "#2C7A7B") // Dark Teal
            categoryIconView.image = UIImage(systemName: "figure.run")
        case .education:
            categoryLabel.backgroundColor = UIColor(hex: "#744210") // Dark Yellow
            categoryIconView.image = UIImage(systemName: "book")
        case .outdoor:
            categoryLabel.backgroundColor = UIColor(hex: "#2F855A") // Dark Green
            categoryIconView.image = UIImage(systemName: "tree")
        case .transport:
            categoryLabel.backgroundColor = UIColor(hex: "#2B6CB0") // Dark Blue
            categoryIconView.image = UIImage(systemName: "car")
        case .finance:
            categoryLabel.backgroundColor = UIColor(hex: "#285E61") // Dark Teal
            categoryIconView.image = UIImage(systemName: "dollarsign.circle")
        case .home:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            categoryIconView.image = UIImage(systemName: "house")
        case .work:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "building.2")
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            categoryIconView.image = UIImage(systemName: "mappin")
        }
    }
    
    // MARK: - Actions
    @objc private func shareButtonTapped() {
        guard let place = place else { return }
        onShareTapped?(place)
    }
    
    @objc private func directionsButtonTapped() {
        guard let place = place else { return }
        onDirectionsTapped?(place)
    }
    
    @objc private func likeButtonTapped() {
        guard let place = place else { return }
        onLikeTapped?(place)
    }
    
    @objc private func commentButtonTapped() {
        guard let place = place else { return }
        onCommentTapped?(place)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        categoryLabel.text = nil
        addressLabel.text = nil
        ratingLabel.text = nil
        placeImageView.image = nil
        categoryIconView.isHidden = false
        imageGradientView.isHidden = true
        directionsButton.isHidden = false
        photoLoadingTask?.cancel()
        imageLoadingIndicator.stopAnimating()
    }
}

// MARK: - EditCircleDelegate
extension CircleDetailViewController: EditCircleDelegate {
    func didUpdateCircle(_ updatedCircle: Circle) {
        self.circle = updatedCircle
        configureUI()
    }
    
    func didDeleteCircle(_ circleId: String) {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - PlaceSearchDelegate
extension CircleDetailViewController: PlaceSearchDelegate {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?) {
        // Dismiss the search controller
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            
            // Show loading indicator
            let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
            self.present(loadingAlert, animated: true)
            
            // Determine category from string or default
            let placeCategory: PlaceCategory
            if let categoryString = category {
                placeCategory = PlaceCategory(rawValue: categoryString) ?? .other
            } else {
                placeCategory = .other
            }
            
            // Create location object
            let location = GeoLocation(type: "Point", coordinates: [coordinate.longitude, coordinate.latitude])
            
            // Add the place
            PlaceService.shared.createPlace(
                name: name,
                description: description,
                address: address,
                category: placeCategory,
                circleId: self.circle.id,
                privacy: PlacePrivacy.followCirclePrivacy,
                website: website,
                phone: phone,
                tags: nil,
                photos: nil
            ) { [weak self] (result: Result<Place, Error>) in
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let newPlace):
                        // Add the new place to our list
                        self.places.insert(newPlace, at: 0)
                        self.tableView.reloadData()
                        self.updateTableViewHeight()
                        self.addAnnotationsToMap()
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(name) has been added to \(self.circle.name)",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to add place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    private func determinePlaceCategory(from types: [String]) -> PlaceCategory {
        // Check for specific place types and map to our categories
        if types.contains("restaurant") { return .restaurant }
        if types.contains("cafe") { return .cafe }
        if types.contains("bar") || types.contains("night_club") { return .bar }
        if types.contains("lodging") || types.contains("hotel") { return .hotel }
        if types.contains("store") || types.contains("shopping_mall") { return .retail }
        if types.contains("hospital") || types.contains("doctor") || types.contains("pharmacy") { return .healthcare }
        if types.contains("gym") || types.contains("health") { return .fitness }
        if types.contains("school") || types.contains("university") { return .education }
        if types.contains("park") || types.contains("campground") { return .outdoor }
        if types.contains("movie_theater") || types.contains("museum") || types.contains("art_gallery") { return .entertainment }
        if types.contains("bus_station") || types.contains("subway_station") || types.contains("train_station") { return .transport }
        if types.contains("bank") || types.contains("atm") { return .finance }
        if types.contains("tourist_attraction") || types.contains("point_of_interest") { return .attraction }
        
        // Default to service or other
        if types.contains("establishment") { return .service }
        return .other
    }
}

// MARK: - Helper Methods
extension CircleDetailViewController {
    private func addGooglePlace(gmsPlace: Any, placeID: String) {
        // This method is kept for legacy compatibility but should be migrated to use Apple Maps
        // For now, we'll just show an error message
        let alert = UIAlertController(
            title: "Not Available",
            message: "Please use the search button to add places.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return
        
        /* Original implementation commented out for reference:
        // Show loading
        let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Determine category based on place types
        let category = determinePlaceCategory(from: gmsPlace.types ?? [])
        
        // Format opening hours if available
        var openingHoursArray: [[String: Any]] = []
        if let openingHours = gmsPlace.openingHours {
            // Use the GooglePlaceDetails method to properly format opening hours
            let placeDetails = GooglePlaceDetails(from: gmsPlace)
            if let formattedHours = placeDetails.toPlaceData(circleId: self.circle.id)["openingHours"] as? [[String: Any]] {
                openingHoursArray = formattedHours
            }
        }
        
        // Create comprehensive place data from Google Place
        var placeData: [String: Any] = [
            "name": gmsPlace.name ?? "",
            "address": gmsPlace.formattedAddress ?? "",
            "googlePlaceId": placeID,
            "circleId": circle.id,
            "category": category.rawValue,
            "rating": gmsPlace.rating,
            "userRatingsTotal": gmsPlace.userRatingsTotal,
            "website": gmsPlace.website?.absoluteString ?? "",
            "phone": gmsPlace.phoneNumber ?? "",
            "priceLevel": gmsPlace.priceLevel.rawValue,
            "types": gmsPlace.types ?? [],
            "location": [
                "type": "Point",
                "coordinates": [gmsPlace.coordinate.longitude, gmsPlace.coordinate.latitude]
            ]
        ]
        
        // Add opening hours if available
        if !openingHoursArray.isEmpty {
            placeData["openingHours"] = openingHoursArray
        }
        
        // Add business status
        switch gmsPlace.businessStatus {
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
        
        // Add place description from rating and price info
        var descriptionParts: [String] = []
        if gmsPlace.rating > 0 {
            descriptionParts.append("Rating: \(String(format: "%.1f", gmsPlace.rating))/5.0 (\(gmsPlace.userRatingsTotal) reviews)")
        }
        if gmsPlace.priceLevel.rawValue > 0 {
            let priceString = String(repeating: "$", count: Int(gmsPlace.priceLevel.rawValue))
            descriptionParts.append("Price: \(priceString)")
        }
        if !descriptionParts.isEmpty {
            placeData["description"] = descriptionParts.joined(separator: " • ")
        }
        
        // Handle Google Place photos
        if let photos = gmsPlace.photos, !photos.isEmpty {
            // Load the first photo and save it
            print("📸 Loading photo from Google Places...")
            GooglePlacesService.shared.loadPhoto(from: photos[0], maxSize: CGSize(width: 800, height: 800)) { [weak self] photoResult in
                switch photoResult {
                case .success(let image):
                    print("📸 Successfully loaded Google photo")
                    // Convert image to data and upload
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        print("📸 Uploading photo to backend... Size: \(imageData.count / 1024)KB")
                        self?.uploadImageAndCreatePlace(placeData: placeData, imageData: imageData, loadingAlert: loadingAlert)
                    } else {
                        print("📸 Failed to convert image to JPEG data")
                        // Create place without photo if conversion fails
                        self?.createPlaceWithData(placeData, loadingAlert: loadingAlert)
                    }
                case .failure(let error):
                    print("📸 Failed to load Google photo: \(error)")
                    // Create place without photo if loading fails
                    self?.createPlaceWithData(placeData, loadingAlert: loadingAlert)
                }
            }
        } else {
            // No photos available, create place without photo
            print("📸 No photos available from Google Places")
            createPlaceWithData(placeData, loadingAlert: loadingAlert)
        }
    }
    
    private func uploadImageAndCreatePlace(placeData: [String: Any], imageData: Data, loadingAlert: UIAlertController) {
        // Upload image to storage
        PlaceService.shared.uploadMultipleImages([imageData]) { [weak self] result in
            switch result {
            case .success(let imageUrls):
                print("📸 Photo uploaded successfully: \(imageUrls)")
                // Add photo URLs to place data
                var updatedPlaceData = placeData
                updatedPlaceData["photos"] = imageUrls
                self?.createPlaceWithData(updatedPlaceData, loadingAlert: loadingAlert)
                
            case .failure(let error):
                print("📸 Failed to upload photo: \(error)")
                // Create place without photo if upload fails
                self?.createPlaceWithData(placeData, loadingAlert: loadingAlert)
            }
        }
        */
    }
    
    private func createPlaceWithData(_ placeData: [String: Any], loadingAlert: UIAlertController) {
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
                    switch result {
                    case .success(let newPlace):
                        // Debug: Log created place
                        print("✅ Place created successfully:")
                        print("✅ ID: \(newPlace.id)")
                        print("✅ Name: \(newPlace.name)")
                        print("✅ Photos: \(newPlace.photos ?? [])")
                        print("✅ Description: \(newPlace.description ?? "nil")")
                        
                        self?.places.append(newPlace)
                        self?.tableView.reloadData()
                        self?.updateTableViewHeight()
                        self?.addAnnotationsToMap()
                        
                        // Show success message
                        let successAlert = UIAlertController(
                            title: "Success",
                            message: "\(newPlace.name) has been added to the circle",
                            preferredStyle: .alert
                        )
                        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(successAlert, animated: true)
                        
                    case .failure(let error):
                        print("❌ Failed to create place: \(error)")
                        let errorAlert = UIAlertController(
                            title: "Error",
                            message: "Failed to add place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(errorAlert, animated: true)
                    }
                }
            }
        }
    }
    
    private func addPlaceWithCoordinates(name: String, location: CLLocationCoordinate2D, placeID: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Reverse geocode to get address
        let geocoder = CLGeocoder()
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            let placemark = placemarks?.first
            let address = [
                placemark?.subThoroughfare,
                placemark?.thoroughfare,
                placemark?.locality,
                placemark?.administrativeArea,
                placemark?.postalCode,
                placemark?.country
            ].compactMap { $0 }.joined(separator: ", ")
            let finalAddress = address.isEmpty ? "Unknown Address" : address
            
            // Create place with geocoded address
            PlaceService.shared.createPlace(
                name: name,
                description: nil,
                address: finalAddress,
                category: .other,
                circleId: self.circle.id,
                privacy: .followCirclePrivacy,
                website: nil,
                phone: nil,
                tags: nil,
                photos: nil
            ) { result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let newPlace):
                            self.places.append(newPlace)
                            self.tableView.reloadData()
                            self.updateTableViewHeight()
                            self.addAnnotationsToMap()
                            
                            // Show success message
                            let successAlert = UIAlertController(
                                title: "Success",
                                message: "\(newPlace.name) has been added to the circle",
                                preferredStyle: .alert
                            )
                            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(successAlert, animated: true)
                            
                        case .failure(let error):
                            let errorAlert = UIAlertController(
                                title: "Error",
                                message: "Failed to add place: \(error.localizedDescription)",
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension CircleDetailViewController {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        
        // Don't automatically center on user location - let the map show all places
        // User can tap the my location button to zoom to their location
        
        // Stop updating to save battery
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
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location error occurred - map will stay at default NYC location
        print("Location error: \(error.localizedDescription)")
    }
}


// MARK: - MKMapViewDelegate
extension CircleDetailViewController {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }
        
        guard let placeAnnotation = annotation as? PlaceAnnotation else {
            return nil
        }
        
        let identifier = "PlaceAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            
            // Add detail button
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
        }
        
        // Customize marker appearance
        if let markerView = annotationView {
            markerView.markerTintColor = categoryColor(for: placeAnnotation.place.category)
            markerView.glyphImage = UIImage(systemName: categoryIcon(for: placeAnnotation.place.category))
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { return }
        showPlaceActionSheet(for: placeAnnotation.place)
    }
    
    // Handle map region changes for better performance
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Update user location if needed
        if let userLocation = locationManager.location {
            self.userLocation = userLocation
        }
    }
    
    private func showNearbyPlacesIndicator(count: Int) {
        let label = UILabel()
        label.text = count > 0 ? "📍 \(count) place\(count == 1 ? "" : "s") nearby" : "No places nearby"
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.bottomAnchor.constraint(equalTo: mapView.topAnchor, constant: -8),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.heightAnchor.constraint(equalToConstant: 32),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        // Add padding
        label.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        // Animate in
        label.alpha = 0
        UIView.animate(withDuration: 0.3) {
            label.alpha = 1
        }
        
        // Remove after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UIView.animate(withDuration: 0.3, animations: {
                label.alpha = 0
            }) { _ in
                label.removeFromSuperview()
            }
        }
    }
    
    // Show action sheet with place options
    private func showPlaceActionSheet(for place: Place) {
        let actionSheet = UIAlertController(title: place.name, message: place.address, preferredStyle: .actionSheet)
        
        // View Details action
        actionSheet.addAction(UIAlertAction(title: "View Details", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let placeDetailVC = PlaceDetailViewController(place: place, circle: self.circle)
            self.navigationController?.pushViewController(placeDetailVC, animated: true)
        })
        
        // Get Directions action
        if place.location != nil {
            actionSheet.addAction(UIAlertAction(title: "Get Directions", style: .default) { [weak self] _ in
                self?.openPlaceInMaps(place)
            })
        }
        
        // Share action
        actionSheet.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            self?.sharePlace(place)
        })
        
        // Cancel action
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(actionSheet, animated: true)
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension CircleDetailViewController: FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        // Navigate to place details
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}

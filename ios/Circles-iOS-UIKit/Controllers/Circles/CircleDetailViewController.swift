import UIKit
import MapKit

class CircleDetailViewController: UIViewController {
    
    // MARK: - Properties
    private let circle: Circle
    private var places: [Place] = []
    
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
        view.backgroundColor = Constants.Colors.white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let circleInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.white
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xxlarge, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacyView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let privacyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.gray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.darkGray
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
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.white
        tableView.separatorStyle = .none
        tableView.layer.cornerRadius = 12
        tableView.isScrollEnabled = false
        tableView.register(PlaceTableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
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
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureUI()
        fetchPlaces()
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
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
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
            
            // Map view
            mapView.topAnchor.constraint(equalTo: placesLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            mapView.heightAnchor.constraint(equalToConstant: 200),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.large),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.xxxlarge),
            
            // Add place button
            addPlaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            addPlaceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.medium),
            addPlaceButton.widthAnchor.constraint(equalToConstant: 120),
            addPlaceButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Setup button actions
        addPlaceButton.addTarget(self, action: #selector(addPlaceButtonTapped), for: .touchUpInside)
        
        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    private func configureUI() {
        title = circle.name
        
        // Navigation bar buttons
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonTapped))
        let editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editButtonTapped))
        navigationItem.rightBarButtonItems = [shareButton, editButton]
        
        // Cover image
        if circle.coverImage != nil {
            // In a real app, you would load the image from the URL
            coverImageView.image = UIImage(systemName: "photo")
        } else {
            // Default image based on category
            switch circle.category {
            case .travel:
                coverImageView.image = UIImage(systemName: "airplane")
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
        case .friends:
            privacyImageView.image = UIImage(systemName: "person.2")
            privacyLabel.text = "Friends Only"
        case .private:
            privacyImageView.image = UIImage(systemName: "lock")
            privacyLabel.text = "Private"
        }
        
        // Category
        categoryLabel.text = circle.category.rawValue.capitalized
        
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
    
    // MARK: - Data Fetching
    private func fetchPlaces() {
        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let places):
                    self?.places = places
                case .failure(let error):
                    print("Error fetching places: \(error.localizedDescription)")
                    // Show sample places as fallback for now
                    self?.places = self?.createSamplePlaces() ?? []
                }
                
                self?.tableView.reloadData()
                self?.updateTableViewHeight()
                self?.addAnnotationsToMap()
            }
        }
    }
    
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
                notes: "Beautiful park to walk around",
                tags: ["park", "nature", "walking"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Great views from the observation deck",
                tags: ["landmark", "skyscraper", "view"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Amazing collection of art",
                tags: ["museum", "art", "culture"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Amazing seafood, get the chef's tasting menu",
                tags: ["seafood", "french", "fine dining"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Seasonal American cuisine, great atmosphere",
                tags: ["american", "seasonal", "tavern"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Luxury shopping district",
                tags: ["luxury", "fashion", "shopping district"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Great selection of designer clothes",
                tags: ["department store", "fashion", "luxury"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Great mix of food vendors and shopping",
                tags: ["market", "food hall", "shopping"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "Trendy shops and boutiques",
                tags: ["trendy", "boutiques", "shopping district"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
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
                notes: "This is a sample place",
                tags: ["sample"],
                reviews: nil,
                openingHours: nil,
                priceLevel: nil,
                circleId: circle.id,
                addedBy: userId,
                createdAt: date.addingTimeInterval(-86400),
                updatedAt: date
            )
            
            samplePlaces = [place]
        }
        
        return samplePlaces
    }
    
    private func updateTableViewHeight() {
        let height = CGFloat(places.count * 100) // Assuming each cell is 100 points tall
        
        // Update table view height constraint
        if let constraint = tableView.constraints.first(where: { $0.firstAttribute == .height }) {
            constraint.constant = height
        } else {
            tableView.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
    }
    
    private func addAnnotationsToMap() {
        mapView.removeAnnotations(mapView.annotations)
        
        var annotations: [MKPointAnnotation] = []
        var coordinates: [CLLocationCoordinate2D] = []
        
        for place in places {
            if let location = place.location?.clLocation {
                let annotation = MKPointAnnotation()
                annotation.coordinate = location.coordinate
                annotation.title = place.name
                annotation.subtitle = place.category.rawValue.capitalized
                
                annotations.append(annotation)
                coordinates.append(location.coordinate)
            }
        }
        
        mapView.addAnnotations(annotations)
        
        if coordinates.count > 0 {
            let region = MKCoordinateRegion(
                center: coordinates.reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) { 
                    CLLocationCoordinate2D(
                        latitude: $0.latitude + $1.latitude,
                        longitude: $0.longitude + $1.longitude
                    )
                }.applying(multiplier: 1.0 / Double(coordinates.count)),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            mapView.setRegion(region, animated: true)
        }
    }
    
    // MARK: - Actions
    @objc private func shareButtonTapped() {
        // Share circle with others
        let activityViewController = UIActivityViewController(
            activityItems: ["Check out my circle \"\(circle.name)\" on Circles!"],
            applicationActivities: nil
        )
        
        present(activityViewController, animated: true)
    }
    
    @objc private func editButtonTapped() {
        let editCircleVC = EditCircleViewController(circle: circle)
        let navController = UINavigationController(rootViewController: editCircleVC)
        present(navController, animated: true)
    }
    
    @objc private func addPlaceButtonTapped() {
        let addPlaceVC = AddPlaceViewController(circleId: circle.id)
        navigationController?.pushViewController(addPlaceVC, animated: true)
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension CircleDetailViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return places.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath) as? PlaceTableViewCell else {
            return UITableViewCell()
        }
        
        let place = places[indexPath.row]
        cell.configure(with: place)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let place = places[indexPath.row]
        let detailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - PlaceTableViewCell
class PlaceTableViewCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.white
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.lightGray.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.layer.cornerRadius = 4
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xsmall)
        label.textColor = Constants.Colors.white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let ratingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
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
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .semibold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
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
        containerView.addSubview(nameLabel)
        containerView.addSubview(categoryLabel)
        containerView.addSubview(addressLabel)
        containerView.addSubview(ratingView)
        
        ratingView.addSubview(ratingImageView)
        ratingView.addSubview(ratingLabel)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.small),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.small),
            
            // Place image view
            placeImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            placeImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.Spacing.small),
            placeImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.Spacing.small),
            placeImageView.widthAnchor.constraint(equalToConstant: 80),
            placeImageView.heightAnchor.constraint(equalToConstant: 80),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Constants.Spacing.small),
            nameLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.trailingAnchor.constraint(equalTo: categoryLabel.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Category label
            categoryLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            categoryLabel.heightAnchor.constraint(equalToConstant: 20),
            
            // Address label
            addressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            addressLabel.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            addressLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.Spacing.small),
            
            // Rating view
            ratingView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.small),
            ratingView.leadingAnchor.constraint(equalTo: placeImageView.trailingAnchor, constant: Constants.Spacing.small),
            ratingView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Constants.Spacing.small),
            ratingView.widthAnchor.constraint(equalToConstant: 65),
            ratingView.heightAnchor.constraint(equalToConstant: 24),
            
            // Rating image view
            ratingImageView.leadingAnchor.constraint(equalTo: ratingView.leadingAnchor, constant: Constants.Spacing.tiny),
            ratingImageView.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            ratingImageView.widthAnchor.constraint(equalToConstant: 16),
            ratingImageView.heightAnchor.constraint(equalToConstant: 16),
            
            // Rating label
            ratingLabel.leadingAnchor.constraint(equalTo: ratingImageView.trailingAnchor, constant: Constants.Spacing.tiny),
            ratingLabel.trailingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: -Constants.Spacing.tiny),
            ratingLabel.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor)
        ])
    }
    
    // MARK: - Configure
    func configure(with place: Place) {
        nameLabel.text = place.name
        
        // Category label
        categoryLabel.text = place.category.rawValue.capitalized
        
        // Set category color
        switch place.category {
        case .restaurant:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
            placeImageView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
            placeImageView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            categoryLabel.backgroundColor = UIColor(hex: "#7B341E") // Brown
            placeImageView.image = UIImage(systemName: "wineglass")
        case .hotel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            placeImageView.image = UIImage(systemName: "bed.double")
        case .retail:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
            placeImageView.image = UIImage(systemName: "bag")
        case .service:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            placeImageView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
            placeImageView.image = UIImage(systemName: "star")
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#9C4221") // Orange Brown
            placeImageView.image = UIImage(systemName: "ticket")
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#319795") // Teal
            placeImageView.image = UIImage(systemName: "cross.case")
        case .fitness:
            categoryLabel.backgroundColor = UIColor(hex: "#2C7A7B") // Dark Teal
            placeImageView.image = UIImage(systemName: "figure.run")
        case .education:
            categoryLabel.backgroundColor = UIColor(hex: "#744210") // Dark Yellow
            placeImageView.image = UIImage(systemName: "book")
        case .outdoor:
            categoryLabel.backgroundColor = UIColor(hex: "#2F855A") // Dark Green
            placeImageView.image = UIImage(systemName: "tree")
        case .transport:
            categoryLabel.backgroundColor = UIColor(hex: "#2B6CB0") // Dark Blue
            placeImageView.image = UIImage(systemName: "car")
        case .finance:
            categoryLabel.backgroundColor = UIColor(hex: "#285E61") // Dark Teal
            placeImageView.image = UIImage(systemName: "dollarsign.circle")
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
            placeImageView.image = UIImage(systemName: "mappin")
        }
        
        placeImageView.tintColor = Constants.Colors.primary
        
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
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        categoryLabel.text = nil
        addressLabel.text = nil
        ratingLabel.text = nil
        placeImageView.image = nil
    }
}

extension CLLocationCoordinate2D {
    func applying(multiplier: Double) -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(
            latitude: self.latitude * multiplier,
            longitude: self.longitude * multiplier
        )
    }
}

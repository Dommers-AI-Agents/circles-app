import UIKit
import MapKit
import PhotosUI

class PlaceDetailViewController: UIViewController {
    
    // MARK: - Properties
    private let place: Place
    private var circle: Circle?
    
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
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.masksToBounds = true
        return imageView
    }()
    
    private var streetViewImage: UIImage?
    private var isStreetViewAvailable = false
    private var showingStreetView = false
    private var customImage: UIImage?
    private var isHomeOrWorkPlace: Bool {
        return place.circleId.isEmpty && (place.id == "home-place" || place.id == "work-place")
    }
    private var isLoadingPhoto = false
    private var placePhotos: [UIImage] = []
    private var currentPhotoIndex = 0
    
    private let streetViewToggleButton: UIButton = {
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
    }()
    
    private let editImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Change Photo", for: .normal)
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
    }()
    
    private let infoContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.xlarge, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.numberOfLines = 2
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
    
    private let ratingView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Creator info view
    private let creatorInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let creatorLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Add to Circle button
    private let addToCircleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add to My Circle", for: .normal)
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 22
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true // Hidden by default
        button.tintColor = .white
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        return button
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
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.darkGray
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
    
    private let addressTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Address"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let navigateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Navigate", for: .normal)
        button.setImage(UIImage(systemName: "location.fill"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 25
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Add shadow for better visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        return button
    }()
    
    private let notesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Notes"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesButtonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let notesEditButton: UIButton = {
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
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addNotesButton: UIButton = {
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
    }()
    
    private let tagsTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Constants.Spacing.small
        stackView.alignment = .leading
        stackView.distribution = .fillProportionally
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    
    private let websiteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Visit Website", for: .normal)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let phoneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Call", for: .normal)
        button.setImage(UIImage(systemName: "phone"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let circleInfoView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let circleNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("View Circle", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    
    init(place: Place, circle: Circle? = nil) {
        self.place = place
        self.circle = circle
        super.init(nibName: nil, bundle: nil)
        
        Logger.debug("PlaceDetailViewController init for place: \(place.name)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.debug("PlaceDetailViewController viewDidLoad")
        
        // Configure scroll view behavior
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        
        // If circle is not provided and circleId is not empty, fetch it
        if circle == nil && !place.circleId.isEmpty {
            fetchCircle()
        }
        
        setupUI()
        configureUI()
        setupMap()
        
        // Check street view availability and auto-load if no photos
        checkStreetViewAvailability()
        autoLoadStreetView()
        
        // Fetch rating if not available
        if place.rating == nil || place.rating == 0 {
            fetchPlaceRating()
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchPlaceRating() {
        // Use PlaceEnrichmentService to fetch rating from Google Places
        PlaceEnrichmentService.shared.enrichPlaceDetails(
            name: place.name,
            address: place.address,
            category: place.category,
            coordinate: (latitude: place.location?.coordinates[1] ?? 0, longitude: place.location?.coordinates[0] ?? 0)
        ) { [weak self] result in
            switch result {
            case .success(let enrichedData):
                if let rating = enrichedData.rating, rating > 0 {
                    DispatchQueue.main.async {
                        self?.updateRatingDisplay(rating: rating, userRatingsTotal: enrichedData.userRatingsTotal)
                    }
                }
            case .failure(let error):
                print("Failed to fetch rating: \(error)")
            }
        }
    }
    
    private func updateRatingDisplay(rating: Double, userRatingsTotal: Int?) {
        ratingLabel.text = String(format: "%.1f", rating)
        if let userRatingsTotal = userRatingsTotal, userRatingsTotal > 0 {
            ratingLabel.text = (ratingLabel.text ?? "") + " (\(userRatingsTotal) reviews)"
        }
        ratingView.isHidden = false
    }
    
    private func fetchCircle() {
        // In a real app, we would fetch circle details from the API using the circle ID
        CircleService.shared.fetchCircleById(id: place.circleId) { [weak self] result in
            switch result {
            case .success(let circle):
                self?.circle = circle
                DispatchQueue.main.async {
                    self?.updateCircleInfo()
                }
            case .failure(let error):
                print("Failed to fetch circle: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = place.name
        
        // Add share button to navigation bar
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonTapped))
        navigationItem.rightBarButtonItem = shareButton
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        // Add image view first
        contentView.addSubview(imageView)
        
        // Add photo control buttons on top of image view
        imageView.addSubview(streetViewToggleButton)
        imageView.addSubview(editImageButton)
        imageView.isUserInteractionEnabled = true
        
        // Add info container after image view
        contentView.addSubview(infoContainerView)
        
        infoContainerView.addSubview(nameLabel)
        infoContainerView.addSubview(categoryLabel)
        infoContainerView.addSubview(creatorInfoView)
        creatorInfoView.addSubview(creatorLabel)
        infoContainerView.addSubview(ratingView)
        infoContainerView.addSubview(descriptionLabel)
        infoContainerView.addSubview(addToCircleButton)
        infoContainerView.addSubview(addressTitleLabel)
        infoContainerView.addSubview(addressLabel)
        infoContainerView.addSubview(mapView)
        infoContainerView.addSubview(navigateButton)
        
        // Always add notes labels - visibility will be controlled in configureUI
        infoContainerView.addSubview(notesTitleLabel)
        infoContainerView.addSubview(notesButtonsStackView)
        notesButtonsStackView.addArrangedSubview(notesEditButton)
        notesButtonsStackView.addArrangedSubview(addNotesButton)
        infoContainerView.addSubview(notesLabel)
        
        if let tags = place.tags, !tags.isEmpty {
            infoContainerView.addSubview(tagsTitleLabel)
            infoContainerView.addSubview(tagsStackView)
        }
        
        // Add contact buttons directly to imageView if available  
        if place.website != nil {
            imageView.addSubview(websiteButton)
            websiteButton.addTarget(self, action: #selector(websiteButtonTapped), for: .touchUpInside)
        }
        
        if place.phone != nil {
            imageView.addSubview(phoneButton)
            phoneButton.addTarget(self, action: #selector(phoneButtonTapped), for: .touchUpInside)
        }
        
        // Add circle info
        infoContainerView.addSubview(circleInfoView)
        circleInfoView.addSubview(circleNameLabel)
        circleInfoView.addSubview(circleButton)
        circleButton.addTarget(self, action: #selector(circleButtonTapped), for: .touchUpInside)
        
        // Add target for street view toggle
        streetViewToggleButton.addTarget(self, action: #selector(streetViewToggleButtonTapped), for: .touchUpInside)
        
        // Add target for edit image button
        editImageButton.addTarget(self, action: #selector(editImageButtonTapped), for: .touchUpInside)
        
        // Add target for navigate button
        navigateButton.addTarget(self, action: #selector(directionsButtonTapped), for: .touchUpInside)
        
        // Add target for notes edit button
        notesEditButton.addTarget(self, action: #selector(notesEditButtonTapped), for: .touchUpInside)
        
        // Add target for add notes button
        addNotesButton.addTarget(self, action: #selector(addNotesButtonTapped), for: .touchUpInside)
        
        ratingView.addSubview(ratingImageView)
        ratingView.addSubview(ratingLabel)
        
        // Add navigation bar buttons
        let directionButton = UIBarButtonItem(image: UIImage(systemName: "map"), style: .plain, target: self, action: #selector(directionsButtonTapped))
        let editButton = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editButtonTapped))
        // shareButton already added to navigationItem.rightBarButtonItem above
        navigationItem.rightBarButtonItems = [editButton, navigationItem.rightBarButtonItem!, directionButton]
        
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
            
            // Image view
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 300),
            
            // Street View toggle button - positioned within imageView
            streetViewToggleButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 20),
            streetViewToggleButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -16),
            streetViewToggleButton.heightAnchor.constraint(equalToConstant: 32),
            streetViewToggleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            // Edit Image button - positioned within imageView
            editImageButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -16),
            editImageButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -16),
            editImageButton.heightAnchor.constraint(equalToConstant: 32),
            editImageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            // Info container view - positioned below the image with padding
            infoContainerView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: Constants.Spacing.medium),
            infoContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            infoContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: infoContainerView.topAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: categoryLabel.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            categoryLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Creator info view
            creatorInfoView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            creatorInfoView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            creatorInfoView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            creatorInfoView.heightAnchor.constraint(equalToConstant: 24),
            
            // Creator label
            creatorLabel.leadingAnchor.constraint(equalTo: creatorInfoView.leadingAnchor, constant: Constants.Spacing.small),
            creatorLabel.trailingAnchor.constraint(equalTo: creatorInfoView.trailingAnchor, constant: -Constants.Spacing.small),
            creatorLabel.centerYAnchor.constraint(equalTo: creatorInfoView.centerYAnchor),
            
            // Rating view - will be hidden if no rating
            ratingView.topAnchor.constraint(equalTo: creatorInfoView.bottomAnchor, constant: Constants.Spacing.small),
            ratingView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            ratingView.heightAnchor.constraint(equalToConstant: 26),
            
            // Rating image view
            ratingImageView.leadingAnchor.constraint(equalTo: ratingView.leadingAnchor, constant: Constants.Spacing.small),
            ratingImageView.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            ratingImageView.widthAnchor.constraint(equalToConstant: 18),
            ratingImageView.heightAnchor.constraint(equalToConstant: 18),
            
            // Rating label
            ratingLabel.leadingAnchor.constraint(equalTo: ratingImageView.trailingAnchor, constant: Constants.Spacing.small),
            ratingLabel.trailingAnchor.constraint(equalTo: ratingView.trailingAnchor, constant: -Constants.Spacing.small),
            ratingLabel.centerYAnchor.constraint(equalTo: ratingView.centerYAnchor),
            
            // Rating view trailing constraint - let it size based on content
            ratingView.trailingAnchor.constraint(equalTo: ratingLabel.trailingAnchor, constant: Constants.Spacing.small),
            
            // Description label - always anchor to rating view
            descriptionLabel.topAnchor.constraint(equalTo: ratingView.bottomAnchor, constant: Constants.Spacing.small),
            descriptionLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Add to Circle button - always in the layout flow, visibility controlled by isHidden
            addToCircleButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.medium),
            addToCircleButton.centerXAnchor.constraint(equalTo: infoContainerView.centerXAnchor),
            addToCircleButton.heightAnchor.constraint(equalToConstant: 44),
            addToCircleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            
            // Address title label
            addressTitleLabel.topAnchor.constraint(equalTo: addToCircleButton.bottomAnchor, constant: Constants.Spacing.large),
            addressTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            
            // Address label
            addressLabel.topAnchor.constraint(equalTo: addressTitleLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            addressLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            addressLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Map view
            mapView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            mapView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            mapView.heightAnchor.constraint(equalToConstant: 160),
            
            // Navigate button
            navigateButton.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.medium),
            navigateButton.centerXAnchor.constraint(equalTo: infoContainerView.centerXAnchor),
            navigateButton.heightAnchor.constraint(equalToConstant: 50),
            navigateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        
        // Dynamic constraints based on available data
        var lastAnchor: NSLayoutYAxisAnchor = navigateButton.bottomAnchor
        var additionalSpacing: CGFloat = Constants.Spacing.medium
        
        // Always set up notes constraints - visibility controlled in configureUI
        NSLayoutConstraint.activate([
            notesTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
            notesTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            
            notesButtonsStackView.centerYAnchor.constraint(equalTo: notesTitleLabel.centerYAnchor),
            notesButtonsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            notesLabel.topAnchor.constraint(equalTo: notesTitleLabel.bottomAnchor, constant: Constants.Spacing.tiny),
            notesLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
            notesLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        
        lastAnchor = notesLabel.bottomAnchor
        
        // Add tags if available
        if let tags = place.tags, !tags.isEmpty {
            NSLayoutConstraint.activate([
                tagsTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                tagsTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                
                tagsStackView.topAnchor.constraint(equalTo: tagsTitleLabel.bottomAnchor, constant: Constants.Spacing.tiny),
                tagsStackView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                tagsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium)
            ])
            
            lastAnchor = tagsStackView.bottomAnchor
        }
        
        // Add contact button constraints - positioned on the image
        if place.website != nil && place.phone != nil {
            // Both buttons - position side by side
            NSLayoutConstraint.activate([
                websiteButton.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 16),
                websiteButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -16),
                websiteButton.heightAnchor.constraint(equalToConstant: 36),
                
                phoneButton.leadingAnchor.constraint(equalTo: websiteButton.trailingAnchor, constant: 8),
                phoneButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -16),
                phoneButton.heightAnchor.constraint(equalToConstant: 36)
            ])
        } else if place.website != nil {
            // Only website button
            NSLayoutConstraint.activate([
                websiteButton.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 16),
                websiteButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -16),
                websiteButton.heightAnchor.constraint(equalToConstant: 36)
            ])
        } else if place.phone != nil {
            // Only phone button
            NSLayoutConstraint.activate([
                phoneButton.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 16),
                phoneButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -16),
                phoneButton.heightAnchor.constraint(equalToConstant: 36)
            ])
        }
        
        // Add circle info only if we have a circle or circleId
        if circle != nil || !place.circleId.isEmpty {
            NSLayoutConstraint.activate([
                circleInfoView.topAnchor.constraint(equalTo: lastAnchor, constant: Constants.Spacing.large),
                circleInfoView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.medium),
                circleInfoView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.medium),
                circleInfoView.heightAnchor.constraint(equalToConstant: 50),
                
                circleNameLabel.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.medium),
                circleNameLabel.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleButton.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.medium),
                circleButton.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleInfoView.bottomAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.medium)
            ])
        } else {
            // No circle info, just add bottom constraint
            lastAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.medium).isActive = true
        }
        
        // Ensure all buttons on imageView are interactive
        if place.website != nil {
            imageView.bringSubviewToFront(websiteButton)
        }
        if place.phone != nil {
            imageView.bringSubviewToFront(phoneButton)
        }
        imageView.bringSubviewToFront(streetViewToggleButton)
        imageView.bringSubviewToFront(editImageButton)
    }
    
    private func configureUI() {
        // Set place details
        nameLabel.text = place.name
        
        // Creator info
        configureCreatorInfo()
        
        // Add to Circle button
        configureAddToCircleButton()
        
        // Category
        categoryLabel.text = "  \(place.displayCategory)  " // Add padding with spaces
        
        // Set category color and icon
        switch place.category {
        case .restaurant:
            categoryLabel.backgroundColor = UIColor(hex: "#E53E3E") // Red
        case .cafe:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
        case .bar:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
        case .hotel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .retail:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
        case .service:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .attraction:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#319795") // Teal
        case .fitness:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .education:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .outdoor:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .transport:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
        case .finance:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
        case .home:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
        case .work:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
        }
        
        // Set default image - this will be called before street view loads
        configureDefaultImage()
        
        // Update edit button visibility based on whether user can edit this place
        let canEdit = place.isAddedByCurrentUser || isHomeOrWorkPlace
        editImageButton.isHidden = !canEdit
        
        // Description - only show if available
        if let description = place.description, !description.isEmpty {
            descriptionLabel.text = description
            descriptionLabel.isHidden = false
        } else {
            descriptionLabel.isHidden = true
        }
        
        // Rating - show even if no rating available
        if let rating = place.rating, rating > 0 {
            ratingLabel.text = String(format: "%.1f", rating)
            ratingView.isHidden = false
        } else {
            // Show "No rating" when rating is not available
            ratingLabel.text = "No rating"
            ratingView.isHidden = false
        }
        
        // Address
        addressLabel.text = place.address
        
        // Notes - combine all available notes
        var notesText = ""
        
        // Add public notes first
        if let publicNotes = place.publicNotes, !publicNotes.isEmpty {
            notesText = publicNotes
        } else if let notes = place.notes, !notes.isEmpty {
            // Fall back to legacy notes field
            notesText = notes
        }
        
        // Add private notes if the current user added this place
        if place.isAddedByCurrentUser, let privateNotes = place.privateNotes, !privateNotes.isEmpty {
            if !notesText.isEmpty {
                notesText += "\n\nPrivate Notes:\n"
            }
            notesText += privateNotes
        }
        
        if !notesText.isEmpty {
            notesLabel.text = notesText
            notesLabel.isHidden = false
            addNotesButton.isHidden = true
            notesEditButton.isHidden = false
        } else {
            notesLabel.isHidden = true
            addNotesButton.isHidden = false
            notesEditButton.isHidden = true
        }
        
        // Always show notes section
        notesTitleLabel.isHidden = false
        
        // Make notes tappable when they exist
        notesLabel.isUserInteractionEnabled = true
        let notesTapGesture = UITapGestureRecognizer(target: self, action: #selector(notesLabelTapped))
        notesLabel.addGestureRecognizer(notesTapGesture)
        
        // Tags
        if let tags = place.tags, !tags.isEmpty {
            setupTagsView(tags: tags)
        }
        
        // Website and phone
        if let website = place.website {
            websiteButton.setTitle("Visit Website", for: .normal)
        }
        
        if let phone = place.phone {
            phoneButton.setTitle("Call \(phone)", for: .normal)
        }
        
        // Price Level
        if let priceLevel = place.priceLevel {
            let priceString = String(repeating: "$", count: priceLevel.rawValue + 1)
            // Could add a price level label here if UI element exists
        }
        
        // User ratings total
        if let userRatingsTotal = place.userRatingsTotal, userRatingsTotal > 0, !ratingView.isHidden {
            let ratingsText = " (\(userRatingsTotal) reviews)"
            ratingLabel.text = (ratingLabel.text ?? "") + ratingsText
        }
        
        // Description constraint is already set in setupUI
        
        // Opening Hours
        if let openingHours = place.openingHours, !openingHours.isEmpty {
            // Could add opening hours display here if UI element exists
            print("Place has opening hours: \(openingHours.count) entries")
        }
        
        // Circle info
        updateCircleInfo()
        
        // Load place photos if available
        loadPlacePhotos()
        
        // After loading photos, check if we need to show street view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let hasPhotos = !self.placePhotos.isEmpty || self.customImage != nil || (self.place.photos != nil && !self.place.photos!.isEmpty)
            if !hasPhotos && self.streetViewImage != nil {
                // No photos loaded, but we have street view - show it
                self.showingStreetView = true
                self.updateImageView()
                self.streetViewToggleButton.isHidden = true
            }
        }
        
        // Hide navigate button if no location available
        navigateButton.isHidden = (place.location == nil)
    }
    
    private func updateCircleInfo() {
        if let circle = self.circle {
            circleNameLabel.text = "In: \(circle.name)"
        } else if !place.circleId.isEmpty {
            circleNameLabel.text = "Loading circle..."
        } else {
            // Hide circle info view for places without circles (e.g., Home/Work)
            circleInfoView.isHidden = true
        }
    }
    
    private func setupTagsView(tags: [String]) {
        // Clear stack view first
        tagsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add tags
        for tag in tags {
            let tagView = UIView()
            tagView.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.5)
            tagView.layer.cornerRadius = 8
            
            let tagLabel = UILabel()
            tagLabel.text = "#\(tag)"
            tagLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
            tagLabel.textColor = Constants.Colors.primary
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            
            tagView.addSubview(tagLabel)
            
            NSLayoutConstraint.activate([
                tagLabel.topAnchor.constraint(equalTo: tagView.topAnchor, constant: Constants.Spacing.tiny),
                tagLabel.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: Constants.Spacing.small),
                tagLabel.trailingAnchor.constraint(equalTo: tagView.trailingAnchor, constant: -Constants.Spacing.small),
                tagLabel.bottomAnchor.constraint(equalTo: tagView.bottomAnchor, constant: -Constants.Spacing.tiny)
            ])
            
            tagsStackView.addArrangedSubview(tagView)
        }
    }
    
    private func setupMap() {
        // Add annotation for the place location
        if let location = place.location?.clLocation {
            // Create annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = place.name
            annotation.subtitle = place.displayCategory
            mapView.addAnnotation(annotation)
            
            // Set map region
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
            
            // Select the annotation to show callout
            mapView.selectAnnotation(annotation, animated: false)
        }
    }
    
    // MARK: - Configuration Helpers
    
    private func configureCreatorInfo() {
        var creatorText = ""
        
        if let addedByUser = place.addedByUser {
            creatorText = "Added by \(addedByUser.displayName)"
        } else {
            // If addedByUser is not populated, check if it's the current user
            let currentUserId = AuthService.shared.getUserId() ?? ""
            if place.addedBy == currentUserId {
                creatorText = "Added by you"
            } else {
                // Try to find the user in the circle
                if let circle = circle {
                    if circle.owner == place.addedBy {
                        if let ownerDetails = circle.ownerDetails {
                            creatorText = "Added by \(ownerDetails.displayName)"
                        } else {
                            creatorText = "Added by circle owner"
                        }
                    } else {
                        creatorText = "Added by a member"
                    }
                } else {
                    creatorText = "Added by a connection"
                }
            }
        }
        
        creatorLabel.text = creatorText
    }
    
    private func configureAddToCircleButton() {
        // Check if the current user already has this place in any of their circles
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Hide button if:
        // 1. User created this place themselves
        // 2. Place is already in one of user's circles
        // 3. User doesn't have any circles to add to
        
        if place.addedBy == currentUserId {
            // User created this place
            addToCircleButton.isHidden = true
            return
        }
        
        // Check if user already has this place
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let userCircles):
                    // Check if any of user's circles contain this place
                    let hasPlace = userCircles.contains { circle in
                        circle.places?.contains(self.place.id) ?? false
                    }
                    
                    if hasPlace {
                        self.addToCircleButton.isHidden = true
                    } else if userCircles.isEmpty {
                        // User has no circles
                        self.addToCircleButton.isHidden = true
                    } else {
                        // Show the button
                        self.addToCircleButton.isHidden = false
                        self.addToCircleButton.addTarget(self, action: #selector(self.addToCircleButtonTapped), for: .touchUpInside)
                    }
                    
                case .failure:
                    self.addToCircleButton.isHidden = true
                }
            }
        }
    }
    
    private func updateAddressTitleConstraint() {
        // No need to update constraints dynamically anymore
        // The constraint is set in setupUI to always anchor to addToCircleButton
    }
    
    // MARK: - Actions
    
    @objc private func addToCircleButtonTapped() {
        // Fetch user's circles to show in picker
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    if circles.isEmpty {
                        // No circles available
                        let alert = UIAlertController(
                            title: "No Circles",
                            message: "You need to create a circle first before adding places to it.",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    } else {
                        // Show circle picker
                        let pickerVC = CirclePickerViewController(circles: circles)
                        pickerVC.onCircleSelected = { [weak self] selectedCircle in
                            self?.addPlaceToCircle(selectedCircle)
                        }
                        let navController = UINavigationController(rootViewController: pickerVC)
                        self.present(navController, animated: true)
                    }
                    
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to load circles: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    @objc private func shareButtonTapped() {
        // Create a formatted string with place details
        var shareText = "📍 \(place.name)\n"
        
        if let description = place.description, !description.isEmpty {
            shareText += "\(description)\n"
        }
        
        shareText += "\n📍 \(place.address)\n"
        
        if let phone = place.phone {
            shareText += "📞 \(phone)\n"
        }
        
        if let website = place.website {
            shareText += "🌐 \(website)\n"
        }
        
        if let rating = place.rating {
            let stars = String(repeating: "⭐", count: Int(rating.rounded()))
            shareText += "\(stars) \(rating)/5.0\n"
        }
        
        // Add Google Maps link
        if let location = place.location?.clLocation {
            let googleMapsURL = "https://maps.google.com/?q=\(location.coordinate.latitude),\(location.coordinate.longitude)"
            shareText += "\n🗺️ View on Google Maps: \(googleMapsURL)"
        }
        
        // Add deep link and web link
        shareText += "\n\n📱 Open in Circles: circles://place/\(place.id)"
        
        // Add TestFlight link
        shareText += "\n\n🔗 Get Circles App: https://testflight.apple.com/join/n1sBRMG3"
        
        var activityItems: [Any] = [shareText]
        
        // Add website URL if available
        if let websiteString = place.website, let url = URL(string: websiteString) {
            activityItems.append(url)
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func directionsButtonTapped() {
        // Open directions to the place in Maps app
        if let location = place.location?.clLocation {
            // Try Google Maps first
            let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&directionsmode=driving")
            
            if let url = googleMapsURL, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback to Apple Maps
                let appleMapsURL = URL(string: "maps://?daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)&dirflg=d")
                if let url = appleMapsURL {
                    UIApplication.shared.open(url)
                }
            }
        } else {
            let alert = UIAlertController(title: "No Location", message: "Location information is not available for this place.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    @objc private func websiteButtonTapped() {
        if let websiteString = place.website, let url = URL(string: websiteString) {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func phoneButtonTapped() {
        if let phoneString = place.phone, let url = URL(string: "tel://\(phoneString.replacingOccurrences(of: " ", with: ""))") {
            UIApplication.shared.open(url)
        }
    }
    
    @objc private func circleButtonTapped() {
        if let circle = self.circle {
            let circleDetailVC = CircleDetailViewController(circle: circle)
            navigationController?.pushViewController(circleDetailVC, animated: true)
        } else {
            let alert = UIAlertController(title: "Loading", message: "Circle information is still loading. Please try again in a moment.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    @objc private func editButtonTapped() {
        let editPlaceVC = EditPlaceViewController(place: place)
        editPlaceVC.delegate = self
        let navController = UINavigationController(rootViewController: editPlaceVC)
        present(navController, animated: true)
    }
    
    @objc private func streetViewToggleButtonTapped() {
        print("🔘 PlaceDetailViewController: Street view toggle button tapped")
        print("  - Current state - showingStreetView: \(showingStreetView)")
        print("  - placePhotos.count: \(placePhotos.count)")
        print("  - currentPhotoIndex: \(currentPhotoIndex)")
        
        // Cycle through available images
        if placePhotos.count > 1 {
            // Multiple photos - cycle through them and optionally street view
            if showingStreetView {
                // Currently showing street view, go back to first photo
                showingStreetView = false
                currentPhotoIndex = 0
                imageView.image = placePhotos[0]
                imageView.contentMode = .scaleAspectFill
                streetViewToggleButton.setTitle("Next Photo", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
            } else {
                // Currently showing a photo
                currentPhotoIndex = (currentPhotoIndex + 1) % placePhotos.count
                imageView.image = placePhotos[currentPhotoIndex]
                imageView.contentMode = .scaleAspectFill
                
                // Update button for next action
                if currentPhotoIndex < placePhotos.count - 1 {
                    streetViewToggleButton.setTitle("Next Photo", for: .normal)
                    streetViewToggleButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
                } else if isStreetViewAvailable {
                    // Last photo, next tap will show street view
                    streetViewToggleButton.setTitle("Look Around", for: .normal)
                    streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
                } else {
                    // Last photo, next tap will go back to first
                    streetViewToggleButton.setTitle("First Photo", for: .normal)
                    streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
                }
            }
        } else if placePhotos.count == 1 && isStreetViewAvailable {
            // Single photo and street view available - toggle between them
            if showingStreetView {
                // Show the photo
                showingStreetView = false
                imageView.image = placePhotos[0]
                imageView.contentMode = .scaleAspectFill
                streetViewToggleButton.setTitle("Look Around", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
            } else {
                // Show street view
                showingStreetView = true
                if streetViewImage == nil {
                    loadStreetViewImage()
                } else {
                    updateImageView()
                }
            }
        } else if placePhotos.isEmpty && isStreetViewAvailable {
            // No photos but street view is available - just toggle street view
            showingStreetView.toggle()
            updateImageView()
            
            if showingStreetView && streetViewImage == nil {
                loadStreetViewImage()
            }
        }
    }
    
    private func checkStreetViewAvailability() {
        guard let location = place.location?.clLocation else { 
            print("⚠️ PlaceDetailViewController: No location available for street view check")
            return 
        }
        
        if #available(iOS 16.0, *) {
            print("🔍 PlaceDetailViewController: Checking Look Around availability for \(place.name)")
            Task {
                let available = await AppleLookAroundService.shared.checkLookAroundAvailability(at: location.coordinate)
                await MainActor.run {
                    print("📍 PlaceDetailViewController: Look Around available: \(available)")
                    self.isStreetViewAvailable = available
                    self.updateToggleButtonVisibility()
                }
            }
        } else {
            // Look Around not available on iOS < 16
            print("⚠️ PlaceDetailViewController: iOS < 16.0, Look Around not available")
            isStreetViewAvailable = false
            updateToggleButtonVisibility()
        }
    }
    
    private func loadStreetViewImage() {
        guard let location = place.location?.clLocation else { return }
        
        if #available(iOS 16.0, *) {
            let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 200)
            
            Task {
                do {
                    let image = try await AppleLookAroundService.shared.getLookAroundSnapshot(
                        at: location.coordinate,
                        size: imageSize
                    )
                    await MainActor.run {
                        self.streetViewImage = image
                        if self.showingStreetView == true {
                            self.updateImageView()
                        }
                    }
                } catch {
                    print("Failed to load Look Around: \(error)")
                }
            }
        }
    }
    
    private func autoLoadStreetView() {
        guard let location = place.location?.clLocation else { return }
        
        if #available(iOS 16.0, *) {
            Task {
                // Check if Look Around is available first
                let available = await AppleLookAroundService.shared.checkLookAroundAvailability(at: location.coordinate)
                guard available else { return }
                
                let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 300)
                
                do {
                    let image = try await AppleLookAroundService.shared.getLookAroundSnapshot(
                        at: location.coordinate,
                        size: imageSize
                    )
                    await MainActor.run {
                        self.streetViewImage = image
                        
                        // Only show street view automatically if there are no photos
                        let hasPhotos = (self.place.photos != nil && !self.place.photos!.isEmpty) || self.customImage != nil
                        
                        if !hasPhotos {
                            // No photos available, show street view
                            self.showingStreetView = true
                            self.updateImageView()
                            self.streetViewToggleButton.isHidden = true // Hide toggle when street view is the only option
                            Logger.debug("PlaceDetailViewController: Auto-showing street view for place without photos")
                        } else {
                            // Has photos, just store street view for toggle option
                            self.updateToggleButtonVisibility()
                            Logger.debug("PlaceDetailViewController: Street view loaded but not shown (place has photos)")
                        }
                    }
                } catch {
                    Logger.error("Failed to auto-load Look Around: \(error)")
                }
            }
        }
    }
    
    private func updateImageView() {
        if showingStreetView, let streetViewImage = streetViewImage {
            imageView.image = streetViewImage
            imageView.contentMode = .scaleAspectFill
            
            // Update button based on whether we have photos to go back to
            if !placePhotos.isEmpty || customImage != nil {
                streetViewToggleButton.setTitle("Photos", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
            } else {
                // No photos, so button should show as "Hide Look Around" or similar
                streetViewToggleButton.setTitle("Close", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
            }
        } else {
            // Reset to original photo or icon
            if !placePhotos.isEmpty && currentPhotoIndex < placePhotos.count {
                imageView.image = placePhotos[currentPhotoIndex]
                imageView.contentMode = .scaleAspectFill
            } else if customImage != nil {
                imageView.image = customImage
                imageView.contentMode = .scaleAspectFill
            } else {
                // No photos available, show default icon
                configureDefaultImage()
            }
            
            if isStreetViewAvailable {
                streetViewToggleButton.setTitle("Look Around", for: .normal)
                streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
            }
        }
    }
    
    private func configureDefaultImage() {
        // Check if we have a custom image (for Home/Work places or user-uploaded)
        if customImage != nil {
            imageView.image = customImage
            imageView.contentMode = .scaleAspectFill
            return
        }
        
        // Check if we have stored photo URLs
        if let photos = place.photos, !photos.isEmpty, let firstPhotoUrl = photos.first {
            // Load from URL if available
            loadPhotoFromURL(firstPhotoUrl)
            return
        }
        
        // If we have street view available and no photos, show it
        if streetViewImage != nil {
            imageView.image = streetViewImage
            imageView.contentMode = .scaleAspectFill
            showingStreetView = true
            streetViewToggleButton.isHidden = true // Hide toggle when street view is the only option
            return
        }
        
        // If no photos or street view, use category icon
        switch place.category {
        case .restaurant:
            imageView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            imageView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            imageView.image = UIImage(systemName: "wineglass")
        case .hotel:
            imageView.image = UIImage(systemName: "bed.double")
        case .retail:
            imageView.image = UIImage(systemName: "bag")
        case .service:
            imageView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            imageView.image = UIImage(systemName: "star")
        case .entertainment:
            imageView.image = UIImage(systemName: "ticket")
        case .healthcare:
            imageView.image = UIImage(systemName: "cross.case")
        case .fitness:
            imageView.image = UIImage(systemName: "figure.run")
        case .education:
            imageView.image = UIImage(systemName: "book")
        case .outdoor:
            imageView.image = UIImage(systemName: "tree")
        case .transport:
            imageView.image = UIImage(systemName: "car")
        case .finance:
            imageView.image = UIImage(systemName: "dollarsign.circle")
        case .home:
            imageView.image = UIImage(systemName: "house")
        case .work:
            imageView.image = UIImage(systemName: "building.2")
        case .other:
            imageView.image = UIImage(systemName: "mappin")
        }
        
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = Constants.Colors.background
    }
    
    // MARK: - Notes Handling
    
    @objc private func notesLabelTapped() {
        showNotesEditor()
    }
    
    @objc private func notesEditButtonTapped() {
        showNotesEditor()
    }
    
    @objc private func addNotesButtonTapped() {
        showNotesEditor()
    }
    
    private func showNotesEditor() {
        let notesEditorVC = NotesEditorViewController(
            publicNotes: place.publicNotes ?? place.notes ?? "",
            privateNotes: place.privateNotes ?? "",
            isPrivateNotesEnabled: place.isAddedByCurrentUser
        )
        
        notesEditorVC.onSave = { [weak self] publicNotes, privateNotes in
            self?.updatePlaceNotes(publicNotes: publicNotes, privateNotes: privateNotes)
        }
        
        let navController = UINavigationController(rootViewController: notesEditorVC)
        present(navController, animated: true)
    }
    
    private func updatePlaceNotes(publicNotes: String, privateNotes: String) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Saving Notes", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Call PlaceService to update notes on Firebase
        PlaceService.shared.updatePlace(
            id: place.id,
            privateNotes: place.isAddedByCurrentUser ? privateNotes : nil,
            publicNotes: publicNotes
        ) { [weak self] result in
            guard let self = self else { return }
            
            loadingAlert.dismiss(animated: true) {
                switch result {
                case .success(_):
                    // Update the UI with the new notes
                    var notesText = ""
                    
                    if !publicNotes.isEmpty {
                        notesText = publicNotes
                    }
                    
                    if self.place.isAddedByCurrentUser && !privateNotes.isEmpty {
                        if !notesText.isEmpty {
                            notesText += "\n\nPrivate Notes:\n"
                        }
                        notesText += privateNotes
                    }
                    
                    if !notesText.isEmpty {
                        self.notesLabel.text = notesText
                        self.notesLabel.textColor = Constants.Colors.gray
                        self.notesLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
                        self.notesLabel.isHidden = false
                        self.addNotesButton.isHidden = true
                        self.notesEditButton.isHidden = false
                    } else {
                        self.notesLabel.isHidden = true
                        self.addNotesButton.isHidden = false
                        self.notesEditButton.isHidden = true
                    }
                    
                case .failure(let error):
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Failed to save notes: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        }
    }
    
    // MARK: - Photo Loading
    
    // Removed loadGooglePlacePhoto function to avoid unnecessary API calls
    // All place data including photos should be stored when the place is created
    
    private func loadPhotoFromURL(_ urlString: String) {
        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            guard let self = self else { return }
            
            if let image = image {
                self.imageView.image = image
                self.imageView.contentMode = .scaleAspectFill
            } else {
                self.setDefaultCategoryIcon()
            }
        }
    }
    
    private func setDefaultCategoryIcon() {
        switch place.category {
        case .restaurant:
            imageView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            imageView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            imageView.image = UIImage(systemName: "wineglass")
        case .hotel:
            imageView.image = UIImage(systemName: "bed.double")
        case .retail:
            imageView.image = UIImage(systemName: "bag")
        case .service:
            imageView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            imageView.image = UIImage(systemName: "star")
        case .entertainment:
            imageView.image = UIImage(systemName: "ticket")
        case .healthcare:
            imageView.image = UIImage(systemName: "cross.case")
        case .fitness:
            imageView.image = UIImage(systemName: "figure.run")
        case .education:
            imageView.image = UIImage(systemName: "book")
        case .outdoor:
            imageView.image = UIImage(systemName: "tree")
        case .transport:
            imageView.image = UIImage(systemName: "car")
        case .finance:
            imageView.image = UIImage(systemName: "dollarsign.circle")
        case .home:
            imageView.image = UIImage(systemName: "house")
        case .work:
            imageView.image = UIImage(systemName: "building.2")
        case .other:
            imageView.image = UIImage(systemName: "mappin")
        }
        
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = Constants.Colors.background
    }
    
    // MARK: - Image Handling for Home/Work
    
    @objc private func editImageButtonTapped() {
        let title = isHomeOrWorkPlace ? "Choose Photo" : "Upload Photo for \(place.name)"
        let message = isHomeOrWorkPlace ? nil : "The photo will be uploaded and visible to others who can see this place"
        let actionSheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
            self?.presentCamera()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        
        // Add street view option if available
        if isStreetViewAvailable && streetViewImage != nil {
            actionSheet.addAction(UIAlertAction(title: "Use Street View", style: .default) { [weak self] _ in
                self?.useStreetViewAsCustomImage()
            })
        }
        
        if customImage != nil || (place.photos != nil && !place.photos!.isEmpty) {
            actionSheet.addAction(UIAlertAction(title: "Remove Photo", style: .destructive) { [weak self] _ in
                self?.removeCustomImage()
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = editImageButton
            popover.sourceRect = editImageButton.bounds
        }
        
        present(actionSheet, animated: true)
    }
    
    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showAlert(title: "Camera Not Available", message: "Camera is not available on this device.")
            return
        }
        
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }
    
    private func presentPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func removeCustomImage() {
        customImage = nil
        saveImage(nil)
        configureDefaultImage()
        editImageButton.setTitle("Add Photo", for: .normal)
    }
    
    private func useStreetViewAsCustomImage() {
        guard let streetViewImage = streetViewImage else { return }
        customImage = streetViewImage
        showingStreetView = false
        editImageButton.setTitle("Change Photo", for: .normal)
        saveImage(streetViewImage)
        updateImageView()
        
        // Show success message
        showAlert(title: "Success", message: "Street view image set as the place photo.")
    }
    
    private func loadSavedImage() {
        let imageKey = "place_image_\(place.id)"
        if let imageData = UserDefaults.standard.data(forKey: imageKey),
           let image = UIImage(data: imageData) {
            customImage = image
            imageView.image = image
            imageView.contentMode = .scaleAspectFill
        }
    }
    
    private func loadPlacePhotos() {
        // First check if place has photos from the API
        if let photos = place.photos, !photos.isEmpty {
            print("🖼️ PlaceDetailViewController: Loading \(photos.count) photos for place: \(place.name)")
            for (index, photo) in photos.enumerated() {
                print("  Photo \(index + 1): \(photo)")
            }
            
            // Load all photos from the API
            placePhotos.removeAll()
            let loadGroup = DispatchGroup()
            
            for (index, photoUrl) in photos.enumerated() {
                guard let url = URL(string: photoUrl) else { 
                    print("❌ PlaceDetailViewController: Invalid photo URL at index \(index): \(photoUrl)")
                    continue 
                }
                
                loadGroup.enter()
                URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                    if let error = error {
                        print("❌ PlaceDetailViewController: Error loading photo \(index): \(error)")
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("📡 PlaceDetailViewController: Photo \(index) HTTP Status: \(httpResponse.statusCode)")
                    }
                    
                    if let data = data, let image = UIImage(data: data) {
                        print("✅ PlaceDetailViewController: Successfully loaded photo \(index)")
                        DispatchQueue.main.async {
                            self?.placePhotos.append(image)
                        }
                    } else {
                        print("❌ PlaceDetailViewController: Failed to create image from data for photo \(index)")
                    }
                    loadGroup.leave()
                }.resume()
            }
            
            loadGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                print("🏁 PlaceDetailViewController: Finished loading photos. Total loaded: \(self.placePhotos.count)")
                
                // Show first photo if available
                if let firstPhoto = self.placePhotos.first {
                    self.customImage = firstPhoto
                    self.imageView.image = firstPhoto
                    self.imageView.contentMode = .scaleAspectFill
                    self.editImageButton.setTitle("Change Photo", for: .normal)
                } else {
                    print("⚠️ PlaceDetailViewController: No photos were successfully loaded")
                }
                
                // Update street view toggle button visibility
                self.updateToggleButtonVisibility()
            }
        } else if isHomeOrWorkPlace {
            // For home/work places, check local storage
            loadSavedImage()
            // Update button title if image exists
            if customImage != nil {
                editImageButton.setTitle("Change Photo", for: .normal)
            }
            updateToggleButtonVisibility()
        } else {
            updateToggleButtonVisibility()
        }
    }
    
    private func updateToggleButtonVisibility() {
        // Show toggle button if:
        // 1. Apple Look Around is available, OR
        // 2. There are multiple photos, OR
        // 3. There's at least one photo AND Look Around is available
        let hasPhotos = !placePhotos.isEmpty || customImage != nil
        let hasMultiplePhotos = placePhotos.count > 1
        let shouldShowToggle = isStreetViewAvailable || hasMultiplePhotos || (hasPhotos && isStreetViewAvailable)
        
        print("🔘 PlaceDetailViewController: Toggle button visibility check:")
        print("  - hasPhotos: \(hasPhotos)")
        print("  - hasMultiplePhotos: \(hasMultiplePhotos)")
        print("  - isStreetViewAvailable: \(isStreetViewAvailable)")
        print("  - shouldShowToggle: \(shouldShowToggle)")
        
        streetViewToggleButton.isHidden = !shouldShowToggle
        
        // Update button title based on what's available
        if hasMultiplePhotos && currentPhotoIndex < placePhotos.count - 1 {
            streetViewToggleButton.setTitle("Next Photo", for: .normal)
            streetViewToggleButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        } else if isStreetViewAvailable {
            streetViewToggleButton.setTitle("Look Around", for: .normal)
            streetViewToggleButton.setImage(UIImage(systemName: "eye.circle"), for: .normal)
        }
    }
    
    private func saveImage(_ image: UIImage?) {
        // For home/work places, save locally
        if isHomeOrWorkPlace {
            let imageKey = "place_image_\(place.id)"
            
            if let image = image,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                UserDefaults.standard.set(imageData, forKey: imageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: imageKey)
            }
        } else {
            // For regular places, upload to API
            guard let image = image else {
                // If removing image, we could implement photo removal here
                return
            }
            
            guard !isLoadingPhoto else { return }
            isLoadingPhoto = true
            
            // Show loading indicator
            editImageButton.isEnabled = false
            
            // Compress image
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                isLoadingPhoto = false
                editImageButton.isEnabled = true
                showAlert(title: "Error", message: "Failed to process image")
                return
            }
            
            // Upload to API
            PlaceService.shared.updatePlace(
                id: place.id,
                addPhotos: [imageData]
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoadingPhoto = false
                    self?.editImageButton.isEnabled = true
                    
                    switch result {
                    case .success(let updatedPlace):
                        // Update the image view with the uploaded photo
                        if let photos = updatedPlace.photos, !photos.isEmpty, let firstPhotoUrl = photos.first, let url = URL(string: firstPhotoUrl) {
                            // Load the uploaded photo
                            URLSession.shared.dataTask(with: url) { data, response, error in
                                if let data = data, let image = UIImage(data: data) {
                                    DispatchQueue.main.async {
                                        self?.customImage = image
                                        self?.imageView.image = image
                                        self?.imageView.contentMode = .scaleAspectFill
                                        // Update button title
                                        self?.editImageButton.setTitle("Change Photo", for: .normal)
                                    }
                                }
                            }.resume()
                        }
                        self?.showAlert(title: "Success", message: "Photo uploaded successfully")
                    case .failure(let error):
                        self?.showAlert(title: "Error", message: "Failed to upload photo: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - EditPlaceDelegate
extension PlaceDetailViewController: EditPlaceDelegate {
    func didUpdatePlace(_ updatedPlace: Place) {
        // Update the current place with the updated one
        // Since place is a let constant, we need to navigate back and refresh
        navigationController?.popViewController(animated: true)
    }
    
    func didDeletePlace(_ placeId: String) {
        // Navigate back to the circle detail view after deletion
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension PlaceDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let editedImage = info[.editedImage] as? UIImage {
            customImage = editedImage
            imageView.image = editedImage
            imageView.contentMode = .scaleAspectFill
            editImageButton.setTitle("Change Photo", for: .normal)
            saveImage(editedImage)
        } else if let originalImage = info[.originalImage] as? UIImage {
            customImage = originalImage
            imageView.image = originalImage
            imageView.contentMode = .scaleAspectFill
            editImageButton.setTitle("Change Photo", for: .normal)
            saveImage(originalImage)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate
extension PlaceDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            if let image = object as? UIImage {
                DispatchQueue.main.async {
                    self?.customImage = image
                    self?.imageView.image = image
                    self?.imageView.contentMode = .scaleAspectFill
                    self?.editImageButton.setTitle("Change Photo", for: .normal)
                    self?.saveImage(image)
                }
            }
        }
    }
}

// MARK: - Add Place to Circle
extension PlaceDetailViewController {
    private func addPlaceToCircle(_ circle: Circle) {
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Adding Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Add the place to the selected circle
        PlaceService.shared.addExistingPlaceToCircle(placeId: place.id, circleId: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Hide the add button
                        self?.addToCircleButton.isHidden = true
                        self?.updateAddressTitleConstraint()
                        
                        // Show success message
                        let alert = UIAlertController(
                            title: "Success",
                            message: "Place added to \(circle.name)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(alert, animated: true)
                        
                        // Post notification to refresh circles if needed
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshCircles"), object: nil)
                        
                    case .failure(let error):
                        // Provide more specific error messages
                        var errorMessage = "Failed to add place"
                        
                        if let placeError = error as? PlaceError {
                            errorMessage = placeError.errorDescription ?? errorMessage
                        } else if (error as NSError).code == 401 {
                            errorMessage = "You don't have permission to add places to this circle"
                        } else if (error as NSError).code == 404 {
                            errorMessage = "The place or circle was not found"
                        } else if (error as NSError).code == 400 {
                            errorMessage = "This place is already in the selected circle"
                        } else {
                            errorMessage = "Failed to add place: \(error.localizedDescription)"
                        }
                        
                        let alert = UIAlertController(
                            title: "Error",
                            message: errorMessage,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self?.present(alert, animated: true)
                    }
                }
            }
        }
    }
}

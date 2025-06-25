import UIKit
import GoogleMaps
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
        return imageView
    }()
    
    private var streetViewImage: UIImage?
    private var isStreetViewAvailable = false
    private var showingStreetView = false
    private var customImage: UIImage?
    private var isHomeOrWorkPlace: Bool {
        return place.circleId.isEmpty && (place.id == "home-place" || place.id == "work-place")
    }
    
    private let streetViewToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Street View", for: .normal)
        button.setImage(UIImage(systemName: "person.and.arrow.left.and.arrow.right"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 20
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let editImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Edit Photo", for: .normal)
        button.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 20
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private let infoContainerView: UIView = {
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
    
    private let mapView: GMSMapView = {
        let mapView = GMSMapView()
        mapView.camera = GMSCameraPosition.camera(withLatitude: 40.7128, longitude: -74.0060, zoom: 15.0)
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
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
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
    
    private let notesEditButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Edit", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
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
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 20
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
    
    private let contactSectionView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let websiteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Visit Website", for: .normal)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let phoneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Call", for: .normal)
        button.setImage(UIImage(systemName: "phone"), for: .normal)
        button.tintColor = Constants.Colors.primary
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
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    
    init(place: Place, circle: Circle? = nil) {
        self.place = place
        self.circle = circle
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // If circle is not provided and circleId is not empty, fetch it
        if circle == nil && !place.circleId.isEmpty {
            fetchCircle()
        }
        
        setupUI()
        configureUI()
        setupMap()
        checkStreetViewAvailability()
        
        // Auto-load street view for Home/Work places
        if isHomeOrWorkPlace {
            autoLoadStreetViewForHomeWork()
        }
    }
    
    // MARK: - Data Fetching
    
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
        
        contentView.addSubview(imageView)
        contentView.addSubview(streetViewToggleButton)
        contentView.addSubview(editImageButton)
        contentView.addSubview(infoContainerView)
        
        infoContainerView.addSubview(nameLabel)
        infoContainerView.addSubview(categoryLabel)
        infoContainerView.addSubview(ratingView)
        infoContainerView.addSubview(descriptionLabel)
        infoContainerView.addSubview(addressTitleLabel)
        infoContainerView.addSubview(addressLabel)
        infoContainerView.addSubview(mapView)
        infoContainerView.addSubview(navigateButton)
        
        // Always add notes labels - visibility will be controlled in configureUI
        infoContainerView.addSubview(notesTitleLabel)
        infoContainerView.addSubview(notesEditButton)
        infoContainerView.addSubview(notesLabel)
        infoContainerView.addSubview(addNotesButton)
        
        if let tags = place.tags, !tags.isEmpty {
            infoContainerView.addSubview(tagsTitleLabel)
            infoContainerView.addSubview(tagsStackView)
        }
        
        // Add contact section if website or phone is available
        if place.website != nil || place.phone != nil {
            infoContainerView.addSubview(contactSectionView)
            
            if place.website != nil {
                contactSectionView.addSubview(websiteButton)
                websiteButton.addTarget(self, action: #selector(websiteButtonTapped), for: .touchUpInside)
            }
            
            if place.phone != nil {
                contactSectionView.addSubview(phoneButton)
                phoneButton.addTarget(self, action: #selector(phoneButtonTapped), for: .touchUpInside)
            }
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
            imageView.heightAnchor.constraint(equalToConstant: 250),
            
            // Street View toggle button
            streetViewToggleButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            streetViewToggleButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            streetViewToggleButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Edit Image button
            editImageButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -12),
            editImageButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            editImageButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Info container view
            infoContainerView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -20),
            infoContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            infoContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            infoContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: infoContainerView.topAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            nameLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            categoryLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            categoryLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Rating view
            ratingView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            ratingView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            ratingView.heightAnchor.constraint(equalToConstant: 30),
            
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
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: ratingView.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            descriptionLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Address title label
            addressTitleLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.large),
            addressTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Address label
            addressLabel.topAnchor.constraint(equalTo: addressTitleLabel.bottomAnchor, constant: Constants.Spacing.small),
            addressLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            addressLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Map view
            mapView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            mapView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            mapView.heightAnchor.constraint(equalToConstant: 180),
            
            // Navigate button
            navigateButton.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.medium),
            navigateButton.centerXAnchor.constraint(equalTo: infoContainerView.centerXAnchor),
            navigateButton.heightAnchor.constraint(equalToConstant: 50),
            navigateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
        
        // Dynamic constraints based on available data
        var lastAnchor: NSLayoutYAxisAnchor = navigateButton.bottomAnchor
        var additionalSpacing: CGFloat = Constants.Spacing.large
        
        // Always set up notes constraints - visibility controlled in configureUI
        NSLayoutConstraint.activate([
            notesTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
            notesTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            
            notesEditButton.centerYAnchor.constraint(equalTo: notesTitleLabel.centerYAnchor),
            notesEditButton.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            
            notesLabel.topAnchor.constraint(equalTo: notesTitleLabel.bottomAnchor, constant: Constants.Spacing.small),
            notesLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
            notesLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Add notes button (centered below title when there are no notes)
            addNotesButton.topAnchor.constraint(equalTo: notesTitleLabel.bottomAnchor, constant: Constants.Spacing.medium),
            addNotesButton.centerXAnchor.constraint(equalTo: infoContainerView.centerXAnchor),
            addNotesButton.widthAnchor.constraint(equalToConstant: 40),
            addNotesButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        lastAnchor = notesLabel.bottomAnchor
        
        // Add tags if available
        if let tags = place.tags, !tags.isEmpty {
            NSLayoutConstraint.activate([
                tagsTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                tagsTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                
                tagsStackView.topAnchor.constraint(equalTo: tagsTitleLabel.bottomAnchor, constant: Constants.Spacing.small),
                tagsStackView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                tagsStackView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large)
            ])
            
            lastAnchor = tagsStackView.bottomAnchor
        }
        
        // Add contact section if available
        if place.website != nil || place.phone != nil {
            NSLayoutConstraint.activate([
                contactSectionView.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                contactSectionView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                contactSectionView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
                contactSectionView.heightAnchor.constraint(equalToConstant: 50)
            ])
            
            if place.website != nil && place.phone != nil {
                // Both website and phone are available
                NSLayoutConstraint.activate([
                    websiteButton.leadingAnchor.constraint(equalTo: contactSectionView.leadingAnchor, constant: Constants.Spacing.medium),
                    websiteButton.centerYAnchor.constraint(equalTo: contactSectionView.centerYAnchor),
                    
                    phoneButton.trailingAnchor.constraint(equalTo: contactSectionView.trailingAnchor, constant: -Constants.Spacing.medium),
                    phoneButton.centerYAnchor.constraint(equalTo: contactSectionView.centerYAnchor)
                ])
            } else if place.website != nil {
                // Only website is available
                NSLayoutConstraint.activate([
                    websiteButton.centerXAnchor.constraint(equalTo: contactSectionView.centerXAnchor),
                    websiteButton.centerYAnchor.constraint(equalTo: contactSectionView.centerYAnchor)
                ])
            } else if place.phone != nil {
                // Only phone is available
                NSLayoutConstraint.activate([
                    phoneButton.centerXAnchor.constraint(equalTo: contactSectionView.centerXAnchor),
                    phoneButton.centerYAnchor.constraint(equalTo: contactSectionView.centerYAnchor)
                ])
            }
            
            lastAnchor = contactSectionView.bottomAnchor
        }
        
        // Add circle info only if we have a circle or circleId
        if circle != nil || !place.circleId.isEmpty {
            NSLayoutConstraint.activate([
                circleInfoView.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                circleInfoView.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                circleInfoView.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large),
                circleInfoView.heightAnchor.constraint(equalToConstant: 50),
                
                circleNameLabel.leadingAnchor.constraint(equalTo: circleInfoView.leadingAnchor, constant: Constants.Spacing.medium),
                circleNameLabel.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleButton.trailingAnchor.constraint(equalTo: circleInfoView.trailingAnchor, constant: -Constants.Spacing.medium),
                circleButton.centerYAnchor.constraint(equalTo: circleInfoView.centerYAnchor),
                
                circleInfoView.bottomAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.large)
            ])
        } else {
            // No circle info, just add bottom constraint
            lastAnchor.constraint(equalTo: infoContainerView.bottomAnchor, constant: -Constants.Spacing.large).isActive = true
        }
    }
    
    private func configureUI() {
        // Set place details
        nameLabel.text = place.name
        
        // Category
        categoryLabel.text = place.category.displayName
        
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
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
        }
        
        // Set default image
        configureDefaultImage()
        
        // Description
        descriptionLabel.text = place.description ?? "No description available"
        
        // Rating
        if let rating = place.rating {
            ratingLabel.text = String(format: "%.1f", rating)
        } else {
            ratingLabel.text = "N/A"
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
        if let userRatingsTotal = place.userRatingsTotal, userRatingsTotal > 0 {
            let ratingsText = " (\(userRatingsTotal) reviews)"
            ratingLabel.text = (ratingLabel.text ?? "") + ratingsText
        }
        
        // Opening Hours
        if let openingHours = place.openingHours, !openingHours.isEmpty {
            // Could add opening hours display here if UI element exists
            print("Place has opening hours: \(openingHours.count) entries")
        }
        
        // Circle info
        updateCircleInfo()
        
        // Show edit image button for Home/Work places
        if isHomeOrWorkPlace {
            editImageButton.isHidden = false
            // Load saved image if exists
            loadSavedImage()
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
        // Add marker for the place location
        if let location = place.location?.clLocation {
            let marker = GMSMarker()
            marker.position = location.coordinate
            marker.title = place.name
            marker.snippet = place.category.displayName
            marker.map = mapView
            
            // Custom marker color
            marker.icon = GMSMarker.markerImage(with: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
            
            // Center camera on the place
            let camera = GMSCameraPosition.camera(
                withLatitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                zoom: 16.0
            )
            mapView.animate(to: camera)
        }
    }
    
    // MARK: - Actions
    
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
        
        // Add deep link and web link
        shareText += "\n\n📱 Open in Circles: circles://place/\(place.id)"
        
        // Add a web link that could redirect to App Store or open the app
        // For now, use TestFlight link since app isn't on App Store yet
        shareText += "\n\n🔗 Get Circles App: https://testflight.apple.com/join/YourTestFlightCode"
        // TODO: Replace with App Store link when published: https://apps.apple.com/app/circles/idYOURAPPID
        
        shareText += "\n\nShared from Circles!"
        
        var activityItems: [Any] = [shareText]
        
        // Add location if available for sharing
        if let location = place.location?.clLocation {
            // Create a Google Maps URL for sharing
            let googleMapsURL = "https://maps.google.com/?q=\(location.coordinate.latitude),\(location.coordinate.longitude)"
            if let url = URL(string: googleMapsURL) {
                activityItems.append(url)
            }
        }
        
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
        showingStreetView.toggle()
        updateImageView()
        
        if showingStreetView && streetViewImage == nil {
            loadStreetViewImage()
        }
    }
    
    private func checkStreetViewAvailability() {
        guard let location = place.location?.clLocation else { return }
        
        GoogleStreetViewService.shared.checkStreetViewAvailability(at: location.coordinate) { [weak self] available in
            DispatchQueue.main.async {
                self?.isStreetViewAvailable = available
                self?.streetViewToggleButton.isHidden = !available
            }
        }
    }
    
    private func loadStreetViewImage() {
        guard let location = place.location?.clLocation else { return }
        
        let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 250)
        let parameters = GoogleStreetViewService.StreetViewParameters(
            location: location.coordinate,
            size: imageSize
        )
        
        GoogleStreetViewService.shared.downloadStreetViewImage(parameters: parameters) { [weak self] imageData in
            guard let data = imageData, let image = UIImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self?.streetViewImage = image
                if self?.showingStreetView == true {
                    self?.updateImageView()
                }
            }
        }
    }
    
    private func autoLoadStreetViewForHomeWork() {
        guard let location = place.location?.clLocation else { return }
        
        // Check if street view is available first
        GoogleStreetViewService.shared.checkStreetViewAvailability(at: location.coordinate) { [weak self] available in
            guard let self = self, available else { return }
            
            DispatchQueue.main.async {
                // Load street view image
                let imageSize = CGSize(width: UIScreen.main.bounds.width, height: 250)
                let parameters = GoogleStreetViewService.StreetViewParameters(
                    location: location.coordinate,
                    size: imageSize
                )
                
                GoogleStreetViewService.shared.downloadStreetViewImage(parameters: parameters) { [weak self] imageData in
                    guard let data = imageData, let image = UIImage(data: data) else { return }
                    
                    DispatchQueue.main.async {
                        self?.streetViewImage = image
                        self?.showingStreetView = true
                        self?.updateImageView()
                        // Update button state
                        self?.streetViewToggleButton.setTitle("Photos", for: .normal)
                        self?.streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
                    }
                }
            }
        }
    }
    
    private func updateImageView() {
        if showingStreetView, let streetViewImage = streetViewImage {
            imageView.image = streetViewImage
            imageView.contentMode = .scaleAspectFill
            streetViewToggleButton.setTitle("Photos", for: .normal)
            streetViewToggleButton.setImage(UIImage(systemName: "photo"), for: .normal)
        } else {
            // Reset to original photo or icon
            configureDefaultImage()
            streetViewToggleButton.setTitle("Street View", for: .normal)
            streetViewToggleButton.setImage(UIImage(systemName: "person.and.arrow.left.and.arrow.right"), for: .normal)
        }
    }
    
    private func configureDefaultImage() {
        // For Home/Work places, check if we already have street view loaded
        if isHomeOrWorkPlace && showingStreetView && streetViewImage != nil {
            imageView.image = streetViewImage
            imageView.contentMode = .scaleAspectFill
            return
        }
        
        // Check if we have a custom image for Home/Work places
        if isHomeOrWorkPlace && customImage != nil {
            imageView.image = customImage
            imageView.contentMode = .scaleAspectFill
            return
        }
        
        // First check if we have stored photo URLs
        if let photos = place.photos, !photos.isEmpty, let firstPhotoUrl = photos.first {
            // Load from URL if available
            loadPhotoFromURL(firstPhotoUrl)
            return
        }
        
        // If no stored photos, use category icon instead of calling Google Places API
        // This saves API costs since we already fetched all data when creating the place
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
        let actionSheet = UIAlertController(title: "Choose Photo", message: nil, preferredStyle: .actionSheet)
        
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
        
        if customImage != nil {
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
    }
    
    private func useStreetViewAsCustomImage() {
        guard let streetViewImage = streetViewImage else { return }
        customImage = streetViewImage
        showingStreetView = false
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
    
    private func saveImage(_ image: UIImage?) {
        let imageKey = "place_image_\(place.id)"
        
        if let image = image,
           let imageData = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(imageData, forKey: imageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: imageKey)
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
            saveImage(editedImage)
        } else if let originalImage = info[.originalImage] as? UIImage {
            customImage = originalImage
            imageView.image = originalImage
            imageView.contentMode = .scaleAspectFill
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
                    self?.saveImage(image)
                }
            }
        }
    }
}
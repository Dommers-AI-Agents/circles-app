import UIKit
import MapKit

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
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let notesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Notes"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        label.textColor = Constants.Colors.gray
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        
        // If circle is not provided, fetch it
        if circle == nil {
            fetchCircle()
        }
        
        setupUI()
        configureUI()
        setupMap()
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
        contentView.addSubview(infoContainerView)
        
        infoContainerView.addSubview(nameLabel)
        infoContainerView.addSubview(categoryLabel)
        infoContainerView.addSubview(ratingView)
        infoContainerView.addSubview(descriptionLabel)
        infoContainerView.addSubview(addressTitleLabel)
        infoContainerView.addSubview(addressLabel)
        infoContainerView.addSubview(mapView)
        
        if let notes = place.notes, !notes.isEmpty {
            infoContainerView.addSubview(notesTitleLabel)
            infoContainerView.addSubview(notesLabel)
        }
        
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
            ratingView.widthAnchor.constraint(equalToConstant: 70),
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
            mapView.heightAnchor.constraint(equalToConstant: 180)
        ])
        
        // Dynamic constraints based on available data
        var lastAnchor: NSLayoutYAxisAnchor = mapView.bottomAnchor
        var additionalSpacing: CGFloat = Constants.Spacing.large
        
        // Add notes if available
        if let notes = place.notes, !notes.isEmpty {
            NSLayoutConstraint.activate([
                notesTitleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: additionalSpacing),
                notesTitleLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                
                notesLabel.topAnchor.constraint(equalTo: notesTitleLabel.bottomAnchor, constant: Constants.Spacing.small),
                notesLabel.leadingAnchor.constraint(equalTo: infoContainerView.leadingAnchor, constant: Constants.Spacing.large),
                notesLabel.trailingAnchor.constraint(equalTo: infoContainerView.trailingAnchor, constant: -Constants.Spacing.large)
            ])
            
            lastAnchor = notesLabel.bottomAnchor
        }
        
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
        
        // Add circle info
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
            imageView.image = UIImage(systemName: "fork.knife")
        case .cafe:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
            imageView.image = UIImage(systemName: "cup.and.saucer")
        case .bar:
            categoryLabel.backgroundColor = UIColor(hex: "#DD6B20") // Orange
            imageView.image = UIImage(systemName: "wineglass")
        case .hotel:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            imageView.image = UIImage(systemName: "bed.double")
        case .retail:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
            imageView.image = UIImage(systemName: "bag")
        case .service:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            imageView.image = UIImage(systemName: "wrench.and.screwdriver")
        case .attraction:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
            imageView.image = UIImage(systemName: "star")
        case .entertainment:
            categoryLabel.backgroundColor = UIColor(hex: "#D69E2E") // Yellow
            imageView.image = UIImage(systemName: "ticket")
        case .healthcare:
            categoryLabel.backgroundColor = UIColor(hex: "#319795") // Teal
            imageView.image = UIImage(systemName: "cross.case")
        case .fitness:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            imageView.image = UIImage(systemName: "figure.run")
        case .education:
            categoryLabel.backgroundColor = UIColor(hex: "#3182CE") // Blue
            imageView.image = UIImage(systemName: "book")
        case .outdoor:
            categoryLabel.backgroundColor = UIColor(hex: "#38A169") // Green
            imageView.image = UIImage(systemName: "tree")
        case .transport:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
            imageView.image = UIImage(systemName: "car")
        case .finance:
            categoryLabel.backgroundColor = UIColor(hex: "#805AD5") // Purple
            imageView.image = UIImage(systemName: "dollarsign.circle")
        case .other:
            categoryLabel.backgroundColor = UIColor(hex: "#718096") // Gray
            imageView.image = UIImage(systemName: "mappin")
        }
        
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = Constants.Colors.background
        
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
        
        // Notes
        if let notes = place.notes {
            notesLabel.text = notes
        }
        
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
        
        // Circle info
        updateCircleInfo()
    }
    
    private func updateCircleInfo() {
        if let circle = self.circle {
            circleNameLabel.text = "In: \(circle.name)"
        } else {
            circleNameLabel.text = "Loading circle..."
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
            let annotation = MKPointAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = place.name
            annotation.subtitle = place.category.displayName
            
            mapView.addAnnotation(annotation)
            
            // Set map region centered on the place
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            mapView.setRegion(region, animated: true)
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
        
        // Add location if available for better sharing to Maps apps
        if let location = place.location?.clLocation {
            let placemark = MKPlacemark(coordinate: location.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = place.name
            activityItems.append(mapItem)
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
            let placemark = MKPlacemark(coordinate: location.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = place.name
            
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
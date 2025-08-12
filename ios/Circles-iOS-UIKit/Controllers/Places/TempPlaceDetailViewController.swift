import UIKit
import MapKit

class TempPlaceDetailViewController: BaseViewController {
    
    // MARK: - Properties
    private var placeId: String?
    private var placeName: String = ""
    private var placeAddress: String = ""
    private var latitude: Double?
    private var longitude: Double?
    private var photoURL: String?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = false
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false
        return mapView
    }()
    
    private let noticeLabel: UILabel = {
        let label = UILabel()
        label.text = "This place was shared via check-in"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var addToCircleButton = UIButton.primaryButton(title: "Add to My Circle")
    
    // MARK: - Configuration
    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateContent()
    }
    
    // MARK: - Configuration
    func configure(placeId: String, name: String, address: String, latitude: Double? = nil, longitude: Double? = nil, photo: String? = nil) {
        self.placeId = placeId
        self.placeName = name
        self.placeAddress = address
        self.latitude = latitude
        self.longitude = longitude
        self.photoURL = photo
        
        if isViewLoaded {
            updateContent()
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Place Details"
        view.backgroundColor = Constants.Colors.background
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(placeImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(addressLabel)
        contentView.addSubview(mapView)
        contentView.addSubview(noticeLabel)
        contentView.addSubview(addToCircleButton)
        
        addToCircleButton.addTarget(self, action: #selector(addToCircleTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            placeImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            placeImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            placeImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            placeImageView.heightAnchor.constraint(equalToConstant: 200),
            
            nameLabel.topAnchor.constraint(equalTo: placeImageView.bottomAnchor, constant: Constants.Spacing.medium),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            addressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            addressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            mapView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: Constants.Spacing.medium),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            mapView.heightAnchor.constraint(equalToConstant: 200),
            
            noticeLabel.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: Constants.Spacing.large),
            noticeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            noticeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            addToCircleButton.topAnchor.constraint(equalTo: noticeLabel.bottomAnchor, constant: Constants.Spacing.medium),
            addToCircleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            addToCircleButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            addToCircleButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
    }
    
    private func updateContent() {
        nameLabel.text = placeName
        addressLabel.text = placeAddress
        
        // Load place image if available
        if let photoURL = photoURL {
            ImageService.shared.loadImage(from: photoURL) { [weak self] image in
                DispatchQueue.main.async {
                    self?.placeImageView.image = image
                }
            }
        } else {
            placeImageView.image = UIImage(systemName: "photo")
            placeImageView.tintColor = Constants.Colors.secondaryLabel
        }
        
        // Setup map if coordinates are available
        if let latitude = latitude, let longitude = longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: false)
            
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = placeName
            mapView.addAnnotation(annotation)
        } else {
            mapView.isHidden = true
        }
    }
    
    // MARK: - Actions
    @objc private func addToCircleTapped() {
        guard placeId != nil else { return }
        
        // Create add to circle flow
        let addToCircleVC = AddPlaceToCircleViewController()
        addToCircleVC.configureForCheckInPlace(
            placeId: placeId!,
            name: placeName,
            address: placeAddress,
            latitude: latitude,
            longitude: longitude,
            photoURL: photoURL
        )
        let navController = UINavigationController(rootViewController: addToCircleVC)
        present(navController, animated: true)
    }
}
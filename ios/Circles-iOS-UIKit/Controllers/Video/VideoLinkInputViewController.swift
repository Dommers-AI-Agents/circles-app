import UIKit
import WebKit
import CoreLocation

protocol VideoLinkInputDelegate: AnyObject {
    func videoLinkInputDidFinish(with video: PlaceVideo)
    func videoLinkInputDidCancel()
}

class VideoLinkInputViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: VideoLinkInputDelegate?
    private var selectedPlace: Place?
    private var videoMetadata: VideoMetadata?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add Video from Social Media"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Paste a link from TikTok, Instagram Reels, YouTube Shorts, or Twitter/X"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let platformIconsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let urlTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Paste video link here..."
        textField.borderStyle = .roundedRect
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.keyboardType = .URL
        textField.clearButtonMode = .whileEditing
        textField.font = .systemFont(ofSize: 16)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let pasteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Paste from Clipboard", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let previewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let previewTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let previewAuthorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let previewPlatformBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .systemBlue
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeSelectionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📍 Select a Place", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemGray6
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let addButton: UIButton = {
        let button = UIButton.primaryButton(title: "Add Video")
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        setupPlatformIcons()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        urlTextField.becomeFirstResponder()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Add Video"
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(instructionLabel)
        contentView.addSubview(platformIconsStackView)
        contentView.addSubview(urlTextField)
        contentView.addSubview(pasteButton)
        contentView.addSubview(previewContainer)
        contentView.addSubview(placeSelectionButton)
        contentView.addSubview(addButton)
        contentView.addSubview(loadingIndicator)
        
        // Preview container subviews
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(previewTitleLabel)
        previewContainer.addSubview(previewAuthorLabel)
        previewContainer.addSubview(previewPlatformBadge)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            platformIconsStackView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            platformIconsStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            platformIconsStackView.heightAnchor.constraint(equalToConstant: 40),
            
            urlTextField.topAnchor.constraint(equalTo: platformIconsStackView.bottomAnchor, constant: 24),
            urlTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            pasteButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 8),
            pasteButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 20),
            
            previewContainer.topAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 24),
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            previewContainer.heightAnchor.constraint(equalToConstant: 280),
            
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.heightAnchor.constraint(equalToConstant: 200),
            
            previewTitleLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 12),
            previewTitleLabel.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            previewTitleLabel.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            
            previewAuthorLabel.topAnchor.constraint(equalTo: previewTitleLabel.bottomAnchor, constant: 4),
            previewAuthorLabel.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            previewAuthorLabel.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            
            previewPlatformBadge.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            previewPlatformBadge.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            previewPlatformBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            previewPlatformBadge.heightAnchor.constraint(equalToConstant: 24),
            
            placeSelectionButton.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 20),
            placeSelectionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            placeSelectionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            placeSelectionButton.heightAnchor.constraint(equalToConstant: 48),
            
            addButton.topAnchor.constraint(equalTo: placeSelectionButton.bottomAnchor, constant: 20),
            addButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.heightAnchor.constraint(equalToConstant: 50),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        
        // Add padding to platform badge
        previewPlatformBadge.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
    }
    
    private func setupActions() {
        urlTextField.addTarget(self, action: #selector(urlTextChanged), for: .editingChanged)
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        placeSelectionButton.addTarget(self, action: #selector(selectPlaceTapped), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addVideoTapped), for: .touchUpInside)
    }
    
    private func setupPlatformIcons() {
        let platforms = [
            ("TikTok", "music.note"),
            ("Instagram", "camera.fill"),
            ("YouTube", "play.rectangle.fill"),
            ("Twitter", "bubble.left.fill")
        ]
        
        for (name, icon) in platforms {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            
            let imageView = UIImageView()
            imageView.image = UIImage(systemName: icon)
            imageView.tintColor = platformColor(for: name)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 30),
                imageView.heightAnchor.constraint(equalToConstant: 30),
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                container.widthAnchor.constraint(equalToConstant: 40),
                container.heightAnchor.constraint(equalToConstant: 40)
            ])
            
            platformIconsStackView.addArrangedSubview(container)
        }
    }
    
    private func platformColor(for platform: String) -> UIColor {
        switch platform {
        case "TikTok": return .black
        case "Instagram": return .systemPink
        case "YouTube": return .systemRed
        case "Twitter": return .systemBlue
        default: return .systemGray
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        delegate?.videoLinkInputDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func urlTextChanged() {
        // Debounce the metadata fetch
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fetchMetadata), object: nil)
        perform(#selector(fetchMetadata), with: nil, afterDelay: 0.5)
    }
    
    @objc private func pasteTapped() {
        if let pasteboardString = UIPasteboard.general.string {
            urlTextField.text = pasteboardString
            urlTextChanged()
        }
    }
    
    @objc private func fetchMetadata() {
        guard let urlString = urlTextField.text,
              !urlString.isEmpty,
              urlString.hasPrefix("http") else {
            previewContainer.isHidden = true
            videoMetadata = nil
            updateAddButtonState()
            return
        }
        
        loadingIndicator.startAnimating()
        previewContainer.isHidden = true
        
        // Fetch metadata from backend
        let endpoint = "videos/metadata?url=\(urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideoMetadataResponse, APIError>) in
            DispatchQueue.main.async {
                self?.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let response):
                    if response.success, let metadata = response.data {
                        self?.displayMetadata(metadata)
                        self?.videoMetadata = metadata
                    } else {
                        self?.showErrorAlert("Unable to fetch video information")
                        self?.videoMetadata = nil
                    }
                    
                case .failure(let error):
                    self?.showErrorAlert("Invalid video URL. Please check and try again.")
                    self?.videoMetadata = nil
                }
                
                self?.updateAddButtonState()
            }
        }
    }
    
    private func displayMetadata(_ metadata: VideoMetadata) {
        previewContainer.isHidden = false
        
        previewTitleLabel.text = metadata.title
        previewAuthorLabel.text = "by @\(metadata.author ?? "unknown")"
        previewPlatformBadge.text = " \(metadata.platform.uppercased()) "
        previewPlatformBadge.backgroundColor = platformColor(for: metadata.platform.capitalized)
        
        // Load thumbnail
        if let thumbnailUrl = metadata.thumbnailUrl,
           let url = URL(string: thumbnailUrl) {
            ImageService.shared.loadImage(from: thumbnailUrl) { [weak self] image in
                self?.previewImageView.image = image
            }
        }
    }
    
    @objc private func selectPlaceTapped() {
        let placeSearchVC = PlaceSearchViewController()
        placeSearchVC.delegate = self
        let navController = UINavigationController(rootViewController: placeSearchVC)
        present(navController, animated: true)
    }
    
    @objc private func addVideoTapped() {
        guard let urlString = urlTextField.text,
              let place = selectedPlace,
              let metadata = videoMetadata else { return }
        
        let loadingAlert = AlertPresenter.showLoading(message: "Adding video...", from: self)
        
        // Create embedded video
        let body: [String: Any] = [
            "url": urlString,
            "placeId": place.id,
            "placeName": place.name,
            "title": metadata.title,
            "description": "",
            "visibility": "public",
            "tags": []
        ]
        
        APIService.shared.request(
            endpoint: "videos/embed",
            method: .post,
            body: body
        ) { [weak self] (result: Result<VideoCreateResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        if response.success, let video = response.data {
                            self?.delegate?.videoLinkInputDidFinish(with: video)
                            self?.dismiss(animated: true)
                        } else {
                            self?.showErrorAlert("Failed to add video")
                        }
                        
                    case .failure(let error):
                        self?.showErrorAlert("Failed to add video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func updateAddButtonState() {
        addButton.isEnabled = videoMetadata != nil && selectedPlace != nil
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PlaceSearchDelegate
extension VideoLinkInputViewController: PlaceSearchDelegate {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?) {
        // Create a minimal place object for video association
        let location = GeoLocation(
            type: "Point",
            coordinates: [coordinate.longitude, coordinate.latitude]
        )
        
        let placeCategory: PlaceCategory
        if let category = category {
            switch category.lowercased() {
            case "restaurant": placeCategory = .restaurant
            case "cafe": placeCategory = .cafe
            case "bar": placeCategory = .bar
            default: placeCategory = .other
            }
        } else {
            placeCategory = .other
        }
        
        selectedPlace = Place(
            id: UUID().uuidString,
            name: name,
            description: description,
            address: address,
            location: location,
            website: website,
            phone: phone,
            googlePlaceId: nil,
            photos: nil,
            videos: nil,
            category: placeCategory,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: "",
            addedBy: AuthService.shared.getUserId() ?? "",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date(),
            isNew: nil
        )
        
        placeSelectionButton.setTitle("📍 \(name)", for: .normal)
        updateAddButtonState()
    }
}

// MARK: - Response Models
struct VideoMetadata: Codable {
    let platform: String
    let title: String
    let author: String?
    let authorUrl: String?
    let thumbnailUrl: String?
    let embedHtml: String?
    let width: Int?
    let height: Int?
    let providerName: String?
    let providerUrl: String?
    let originalUrl: String
}

struct VideoMetadataResponse: Codable {
    let success: Bool
    let data: VideoMetadata?
}

struct VideoCreateResponse: Codable {
    let success: Bool
    let data: PlaceVideo?
}
import UIKit
import AVFoundation
import Photos
import CoreLocation

protocol ContentUploadDelegate: AnyObject {
    func contentUploadDidFinish(with moment: PlaceMoment)
    func contentUploadDidCancel()
}

class ContentUploadViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: ContentUploadDelegate?
    private var selectedPlace: Place?
    private var pendingContent: ContentType?
    
    // MARK: - UI Elements
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Share a Moment"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Choose how to share your place experience"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let optionsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let topRowStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        return stack
    }()
    
    private let bottomRowStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        return stack
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        createOptionButtons()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Add Content"
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(optionsStackView)
        
        optionsStackView.addArrangedSubview(topRowStack)
        optionsStackView.addArrangedSubview(bottomRowStack)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            optionsStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            optionsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            optionsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            optionsStackView.heightAnchor.constraint(equalToConstant: 320)
        ])
    }
    
    private func createOptionButtons() {
        // Record Video Option
        let recordVideoOption = createOptionButton(
            icon: "video.fill",
            title: "Record Video",
            subtitle: "15 sec max • Auto-compressed",
            color: .systemRed,
            action: #selector(recordVideoTapped)
        )
        
        // Link from Social Media Option (with recommended badge)
        let linkOption = createOptionButton(
            icon: "link.circle.fill",
            title: "Link from Social",
            subtitle: "TikTok • Instagram • YouTube",
            color: .systemPurple,
            action: #selector(linkFromSocialTapped),
            badge: "Recommended for Creators"
        )
        
        // Take Photo Option
        let takePhotoOption = createOptionButton(
            icon: "camera.fill",
            title: "Take Photo",
            subtitle: "Quick snapshot",
            color: .systemBlue,
            action: #selector(takePhotoTapped)
        )
        
        // Choose from Library Option
        let libraryOption = createOptionButton(
            icon: "photo.on.rectangle.angled",
            title: "Choose Photos",
            subtitle: "Up to 5 photos",
            color: .systemGreen,
            action: #selector(chooseFromLibraryTapped)
        )
        
        // Add to stacks
        topRowStack.addArrangedSubview(recordVideoOption)
        topRowStack.addArrangedSubview(linkOption)
        bottomRowStack.addArrangedSubview(takePhotoOption)
        bottomRowStack.addArrangedSubview(libraryOption)
    }
    
    private func createOptionButton(icon: String, title: String, subtitle: String, color: UIColor, action: Selector, badge: String? = nil) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor
        
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = color
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconImageView)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            iconImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])
        
        // Add badge if provided
        if let badge = badge {
            let badgeLabel = UILabel()
            badgeLabel.text = badge
            badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.backgroundColor = .systemOrange
            badgeLabel.textAlignment = .center
            badgeLabel.layer.cornerRadius = 10
            badgeLabel.clipsToBounds = true
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            
            container.addSubview(badgeLabel)
            NSLayoutConstraint.activate([
                badgeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                badgeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                badgeLabel.heightAnchor.constraint(equalToConstant: 20),
                badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
            ])
            
            // Add padding
            badgeLabel.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        }
        
        return container
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        delegate?.contentUploadDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func recordVideoTapped() {
        let videoRecordVC = VideoRecordingViewController()
        // TODO: Set max duration when VideoRecordingViewController supports it
        videoRecordVC.delegate = self
        let nav = UINavigationController(rootViewController: videoRecordVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func linkFromSocialTapped() {
        let linkInputVC = VideoLinkInputViewController()
        linkInputVC.delegate = self
        let nav = UINavigationController(rootViewController: linkInputVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func takePhotoTapped() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.delegate = self
            imagePicker.allowsEditing = false
            present(imagePicker, animated: true)
        } else {
            showErrorAlert("Camera not available")
        }
    }
    
    @objc private func chooseFromLibraryTapped() {
        checkPhotoLibraryPermission { [weak self] granted in
            if granted {
                self?.presentPhotoPicker()
            } else {
                self?.showErrorAlert("Photo library access denied")
            }
        }
    }
    
    private func presentPhotoPicker() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.image", "public.movie"]
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        present(imagePicker, animated: true)
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension ContentUploadViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let image = info[.originalImage] as? UIImage {
            // Compress and process image
            processImage(image)
        } else if let videoURL = info[.mediaURL] as? URL {
            // Process video (trim to 15 seconds and compress)
            processVideo(at: videoURL)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    private func processImage(_ image: UIImage) {
        // Show compression progress
        let loadingAlert = AlertPresenter.showLoading(message: "Optimizing image...", from: self)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Compress image aggressively
            let compressedImage = ImageCompressionService.compressImage(
                image,
                maxDimension: 1080,
                quality: 0.7
            )
            
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    // Show place selection
                    self?.showPlaceSelection(for: .photo(compressedImage))
                }
            }
        }
    }
    
    private func processVideo(at url: URL) {
        // Show compression progress
        let loadingAlert = AlertPresenter.showLoading(message: "Compressing video...", from: self)
        
        // Use aggressive compression for moments (15 sec, 720p, 500kbps)
        VideoCompressionService.shared.compressVideo(
            inputURL: url,
            quality: .preview, // Use preview quality for aggressive compression
            progress: { _ in }
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let compressed):
                        self?.showPlaceSelection(for: .video(compressed.url))
                    case .failure(let error):
                        self?.showErrorAlert("Failed to compress video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func showPlaceSelection(for content: ContentType) {
        let placeSearchVC = PlaceSearchViewController()
        placeSearchVC.delegate = self
        // Store content type for later use
        self.pendingContent = content
        let nav = UINavigationController(rootViewController: placeSearchVC)
        present(nav, animated: true)
    }
}

// MARK: - Content Type
enum ContentType {
    case video(URL)
    case photo(UIImage)
    case carousel([UIImage])
    case embedded(PlaceVideo)
}

// MARK: - VideoRecordingDelegate
extension ContentUploadViewController: VideoRecordingDelegate {
    func videoRecordingDidFinish(with url: URL, place: Place?) {
        processVideo(at: url)
    }
    
    func videoRecordingDidCancel() {
        // User cancelled recording
    }
}

// MARK: - VideoLinkInputDelegate
extension ContentUploadViewController: VideoLinkInputDelegate {
    func videoLinkInputDidFinish(with video: PlaceVideo) {
        // Convert to PlaceMoment and notify delegate
        let moment = PlaceMoment(from: video)
        delegate?.contentUploadDidFinish(with: moment)
        dismiss(animated: true)
    }
    
    func videoLinkInputDidCancel() {
        // User cancelled link input
    }
}

// MARK: - PlaceSearchDelegate
extension ContentUploadViewController: PlaceSearchDelegate {
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?) {
        guard let content = pendingContent else { return }
        
        // Create a place object
        let location = GeoLocation(
            type: "Point",
            coordinates: [coordinate.longitude, coordinate.latitude]
        )
        
        let place = Place(
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
            category: .other,
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
        
        // Upload content and create moment
        uploadContent(content, for: place)
    }
    
    private func uploadContent(_ content: ContentType, for place: Place) {
        // This will handle the actual upload and moment creation
        // For now, just dismiss
        dismiss(animated: true)
    }
}

// MARK: - Image Compression Service
struct ImageCompressionService {
    static func compressImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: min(maxDimension, size.width), height: min(maxDimension, size.width) / aspectRatio)
        } else {
            newSize = CGSize(width: min(maxDimension, size.height) * aspectRatio, height: min(maxDimension, size.height))
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Further compress to JPEG
        if let jpegData = resizedImage?.jpegData(compressionQuality: quality),
           let compressedImage = UIImage(data: jpegData) {
            return compressedImage
        }
        
        return resizedImage ?? image
    }
}
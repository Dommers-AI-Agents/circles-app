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
    private var selectedVisibility: VideoVisibility = .public // Default to public
    private var shouldNavigateToMomentsOnSuccess = false // Flag to control navigation behavior
    
    // Background image processing
    private var originalImage: UIImage?
    private var processedImage: UIImage?
    private var isImageProcessingComplete = false
    
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
        title = "Share a Moment"
        
        // Navigation items - Add cancel button for easy exit
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
        print("📸 User tapped cancel button - dismissing content upload")
        delegate?.contentUploadDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func recordVideoTapped() {
        showPrivacySelection { [weak self] in
            // Present video recording controller
            let videoRecordingVC = VideoRecordingViewController()
            videoRecordingVC.delegate = self
            videoRecordingVC.modalPresentationStyle = .fullScreen
            self?.present(videoRecordingVC, animated: true)
        }
    }
    
    @objc private func linkFromSocialTapped() {
        showPrivacySelection { [weak self] in
            let linkInputVC = VideoLinkInputViewController()
            linkInputVC.delegate = self
            let nav = UINavigationController(rootViewController: linkInputVC)
            nav.modalPresentationStyle = .fullScreen
            self?.present(nav, animated: true)
        }
    }
    
    @objc private func takePhotoTapped() {
        showPrivacySelection { [weak self] in
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                let imagePicker = UIImagePickerController()
                imagePicker.sourceType = .camera
                imagePicker.delegate = self
                imagePicker.allowsEditing = false
                self?.present(imagePicker, animated: true)
            } else {
                self?.showErrorAlert("Camera not available")
            }
        }
    }
    
    @objc private func chooseFromLibraryTapped() {
        showPrivacySelection { [weak self] in
            self?.checkPhotoLibraryPermission { granted in
                if granted {
                    self?.presentPhotoPicker()
                } else {
                    self?.showErrorAlert("Photo library access denied")
                }
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
        // Dismiss any presented view controller first
        if let presented = self.presentedViewController {
            print("⚠️ ContentUpload: Dismissing \(type(of: presented)) before showing error: \(message)")
            presented.dismiss(animated: false) { [weak self] in
                self?.presentErrorAlertAfterDismissal(message)
            }
        } else {
            presentErrorAlertAfterDismissal(message)
        }
    }
    
    private func presentErrorAlertAfterDismissal(_ message: String) {
        // Double-check we're still in the view hierarchy
        guard self.view.window != nil else {
            print("⚠️ ContentUpload: View not in window hierarchy, skipping alert: \(message)")
            return
        }
        
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showPrivacySelection(completion: @escaping () -> Void) {
        let alertController = UIAlertController(
            title: "Who can see this moment?",
            message: "Choose who can view your moment",
            preferredStyle: .actionSheet
        )
        
        // Public option (default) - with checkmark to show it's selected
        let publicTitle = selectedVisibility == .public ? "✓ Followers" : "Followers"
        let publicAction = UIAlertAction(title: publicTitle, style: .default) { [weak self] _ in
            self?.selectedVisibility = .public
            completion()
        }
        
        // Network only option
        let networkTitle = selectedVisibility == .network ? "✓ Only My Connections" : "Only My Connections"
        let networkAction = UIAlertAction(title: networkTitle, style: .default) { [weak self] _ in
            self?.selectedVisibility = .network
            completion()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(publicAction)
        alertController.addAction(networkAction)
        alertController.addAction(cancelAction)
        
        // iPad support
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    
    private func handleQuotaError() {
        let alert = UIAlertController(
            title: "Monthly Limit Reached",
            message: "You've reached your monthly video upload limit.\n\nFree users: 5 videos/month\nPremium users: 50 videos/month\n\nYour quota resets at the beginning of next month.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Upgrade to Premium", style: .default) { _ in
            // Navigate to subscription screen
            if let tabBarController = self.presentingViewController as? UITabBarController {
                self.dismiss(animated: true) {
                    // Switch to profile tab (index 3 - Profile is the 4th tab, but arrays are 0-indexed)
                    tabBarController.selectedIndex = 3
                    
                    // Navigate to subscription view
                    if let navController = tabBarController.viewControllers?[3] as? UINavigationController,
                       let profileVC = navController.viewControllers.first as? ProfileViewController {
                        // Use a small delay to ensure the tab switch animation completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            let subscriptionVC = SubscriptionViewController()
                            navController.pushViewController(subscriptionVC, animated: true)
                        }
                    }
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
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
        print("📸 Starting image processing in background...")
        
        // Store original image
        self.originalImage = image
        
        // Start place selection immediately with original image
        self.startUploadAndShowPlaceSelection(for: .photo(image))
        
        // Process image in background
        self.processImageInBackground(image)
    }
    
    private func processImageInBackground(_ image: UIImage) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let strongSelf = self else { return }
            
            // Resize and compress image
            let resizedImage = image.resized(to: CGSize(width: 1080, height: 1080))
            
            guard let compressedData = resizedImage.jpegData(compressionQuality: 0.7),
                  let compressedImage = UIImage(data: compressedData) else {
                print("⚠️ Background image processing failed, will use original")
                return
            }
            
            DispatchQueue.main.async {
                strongSelf.processedImage = compressedImage
                strongSelf.isImageProcessingComplete = true
                print("📸 Background image processing completed")
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
                    // Add small delay to avoid presentation conflict
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        switch result {
                        case .success(let compressed):
                            // Start upload immediately while user selects place
                            self?.startUploadAndShowPlaceSelection(for: .video(compressed.url))
                        case .failure(let error):
                            self?.showErrorAlert("Failed to compress video: \(error.localizedDescription)")
                        }
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
    
    private func startUploadAndShowPlaceSelection(for content: ContentType) {
        // Show place selection UI immediately
        let placeSearchVC = PlaceSearchViewController()
        placeSearchVC.delegate = self
        
        // Store content for upload completion
        self.pendingContent = content
        
        // Present place search
        let nav = UINavigationController(rootViewController: placeSearchVC)
        
        // Add loading indicator to show upload is happening
        let uploadIndicator = UIActivityIndicatorView(style: .medium)
        uploadIndicator.startAnimating()
        let uploadLabel = UILabel()
        uploadLabel.text = "Uploading in background..."
        uploadLabel.font = .systemFont(ofSize: 12)
        uploadLabel.textColor = .secondaryLabel
        
        let stackView = UIStackView(arrangedSubviews: [uploadIndicator, uploadLabel])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        
        placeSearchVC.navigationItem.titleView = stackView
        
        present(nav, animated: true)
        
        // Start upload in background (will complete when place is selected)
        // The actual upload will happen when place is selected in didSelectPlace delegate
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
        // Since we removed place selection from VideoRecordingViewController,
        // place will always be nil - process video and show place selection
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
    func didSelectExistingPlace(_ place: Place) {
        guard let content = pendingContent else { return }
        
        // Store the selected place
        self.selectedPlace = place
        
        // Dismiss place search first, then start upload
        if let presentedVC = presentedViewController {
            presentedVC.dismiss(animated: true) { [weak self] in
                // Now that place search is dismissed, show processing and upload
                self?.showProcessingAndUpload(content: content, place: place)
            }
        } else {
            // Fallback if somehow not presented
            showProcessingAndUpload(content: content, place: place)
        }
        
        // Clear pending content
        pendingContent = nil
    }
    
    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?, website: String?, category: String?, description: String?) {
        guard let content = pendingContent else { return }
        
        // Create a place object
        let location = GeoLocation(
            type: "Point",
            coordinates: [coordinate.longitude, coordinate.latitude]
        )
        
        // Map category string to PlaceCategory enum
        let placeCategory: PlaceCategory
        if let category = category {
            switch category.lowercased() {
            case "restaurant": placeCategory = .restaurant
            case "cafe": placeCategory = .cafe
            case "bar": placeCategory = .bar
            case "hotel": placeCategory = .hotel
            case "retail": placeCategory = .retail
            case "service": placeCategory = .service
            case "attraction": placeCategory = .attraction
            default: placeCategory = .other
            }
        } else {
            placeCategory = .other
        }
        
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
        
        // Store the selected place
        self.selectedPlace = place
        
        // Dismiss place search first, then start upload
        if let presentedVC = presentedViewController {
            presentedVC.dismiss(animated: true) { [weak self] in
                // Now that place search is dismissed, show processing and upload
                self?.showProcessingAndUpload(content: content, place: place)
            }
        } else {
            // Fallback if somehow not presented
            showProcessingAndUpload(content: content, place: place)
        }
        
        // Clear pending content
        pendingContent = nil
    }
    
    private func showProcessingAndUpload(content: ContentType, place: Place) {
        // Show a better processing view with place name
        let message = "Adding your moment to \(place.name)..."
        let loadingAlert = AlertPresenter.showLoading(message: message, from: self)
        
        // Set flag to navigate to moments on success
        shouldNavigateToMomentsOnSuccess = true
        
        // Start the actual upload
        uploadContent(content, for: place, withLoadingAlert: loadingAlert)
    }
    
    private func uploadContent(_ content: ContentType, for place: Place, withLoadingAlert loadingAlert: UIAlertController) {
        switch content {
        case .photo(let image):
            uploadPhoto(image, for: place, loadingAlert: loadingAlert)
        case .video(let url):
            uploadVideo(at: url, for: place, loadingAlert: loadingAlert)
        case .carousel(let images):
            uploadCarousel(images, for: place, loadingAlert: loadingAlert)
        case .embedded(let video):
            // Embedded video already created
            let moment = PlaceMoment(from: video)
            loadingAlert.dismiss(animated: true) {
                if self.shouldNavigateToMomentsOnSuccess {
                    self.navigateToMomentsTab(with: moment)
                } else {
                    self.delegate?.contentUploadDidFinish(with: moment)
                    self.dismiss(animated: true)
                }
            }
        }
    }
    
    private func uploadContent(_ content: ContentType, for place: Place) {
        // Use the same nice feedback as showProcessingAndUpload for consistency
        let message = "Adding your moment to \(place.name)..."
        let loadingAlert = AlertPresenter.showLoading(message: message, from: self)
        
        // Set navigation flag for consistency with home page flow
        shouldNavigateToMomentsOnSuccess = true
        
        switch content {
        case .photo(let image):
            uploadPhoto(image, for: place, loadingAlert: loadingAlert)
        case .video(let url):
            uploadVideo(at: url, for: place, loadingAlert: loadingAlert)
        case .carousel(let images):
            uploadCarousel(images, for: place, loadingAlert: loadingAlert)
        case .embedded(let video):
            // Embedded video already created
            let moment = PlaceMoment(from: video)
            loadingAlert.dismiss(animated: true) {
                self.delegate?.contentUploadDidFinish(with: moment)
                self.dismiss(animated: true)
            }
        }
    }
    
    private func navigateToMomentsTab(with moment: PlaceMoment) {
        // Notify delegate first
        self.delegate?.contentUploadDidFinish(with: moment)
        
        // Dismiss this controller and navigate to moments
        self.dismiss(animated: true) { [weak self] in
            // Find the tab bar controller
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController as? UITabBarController {
                
                // Switch to home tab (index 0)
                tabBarController.selectedIndex = 0
                
                // If the home view controller is a navigation controller with CirclesHomeViewController
                if let navController = tabBarController.viewControllers?[0] as? UINavigationController,
                   let homeVC = navController.viewControllers.first as? CirclesHomeViewController {
                    // Ensure we're showing the Moments tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // This will trigger the moments tab to be selected
                        homeVC.contentSegmentedControl.selectedSegmentIndex = 1 // Moments is at index 1 (Activity is 0, Moments is 1)
                        homeVC.contentSegmentChanged()
                    }
                }
            }
        }
    }
    
    private func uploadPhoto(_ image: UIImage, for place: Place, loadingAlert: UIAlertController) {
        // Use processed image if available, otherwise use original
        let imageToUpload = isImageProcessingComplete ? (processedImage ?? image) : image
        print("📸 Using \(isImageProcessingComplete ? "processed" : "original") image for upload")
        
        // Convert image to JPEG data
        guard let imageData = imageToUpload.jpegData(compressionQuality: 0.7) else {
            loadingAlert.dismiss(animated: true) {
                self.showErrorAlert("Failed to process image")
            }
            return
        }
        
        // Check if this is a new place (not from existing places)
        let isNewPlace = place.circleId?.isEmpty ?? true
        
        // Prepare request body
        var body: [String: Any] = [
            "placeId": place.id,
            "placeName": place.name,
            "title": place.name,
            "description": "",
            "visibility": selectedVisibility.rawValue,
            "tags": [],
            "contentType": "photo",
            "fileSize": imageData.count,
            "duration": 0,
            "isNewPlace": isNewPlace
        ]
        
        // Add place creation data if it's a new place
        if isNewPlace {
            body["placeAddress"] = place.address ?? ""
            body["placeCoordinates"] = place.location?.coordinates ?? []
            body["placeCategory"] = place.category.rawValue
            body["placeDescription"] = place.description ?? ""
            body["placePhone"] = place.phone ?? ""
            body["placeWebsite"] = place.website ?? ""
        }
        
        // Initiate upload
        APIService.shared.request(
            endpoint: "videos/upload/initiate",
            method: .post,
            body: body
        ) { [weak self] (result: Result<UploadInitiateResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success, let data = response.data {
                    // Upload image to signed URL
                    self?.uploadImageToStorage(
                        imageData: imageData,
                        uploadUrl: data.uploadUrls.thumbnail,
                        videoId: data.videoId,
                        storagePaths: data.storagePaths,
                        place: place,
                        loadingAlert: loadingAlert
                    )
                } else {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self?.showErrorAlert("Failed to initiate upload")
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        // Check if it's a quota error
                        if error.localizedDescription.lowercased().contains("quota") {
                            self?.handleQuotaError()
                        } else {
                            self?.showErrorAlert("Upload failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func uploadVideo(at url: URL, for place: Place, loadingAlert: UIAlertController) {
        // Get video file size and duration
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        // Get file size
        let fileSize: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attributes[.size] as? Int ?? 0
        } catch {
            fileSize = 0
        }
        
        // Read video data
        guard let videoData = try? Data(contentsOf: url) else {
            loadingAlert.dismiss(animated: true) {
                self.showErrorAlert("Failed to read video file")
            }
            return
        }
        
        // Generate thumbnail
        print("🎬 Generating thumbnail for video at URL: \(url.lastPathComponent)")
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTimeMake(value: 1, timescale: 2) // Get frame at 0.5 seconds
        
        var thumbnailData: Data?
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)
            let thumbnailSize = thumbnailData?.count ?? 0
            print("✅ Thumbnail generated successfully - Size: \(thumbnailSize) bytes")
            print("   - Image dimensions: \(thumbnail.size)")
            
            // Add unique identifier to verify uniqueness
            let uniqueId = UUID().uuidString.prefix(8)
            print("   - Thumbnail unique ID: \(uniqueId)")
        } catch {
            print("❌ Failed to generate thumbnail: \(error)")
        }
        
        // Check if this is a new place (not from existing places)
        let isNewPlace = place.circleId?.isEmpty ?? true
        
        // Prepare request body
        var body: [String: Any] = [
            "placeId": place.id,
            "placeName": place.name,
            "title": "Moment at \(place.name)",
            "description": "",
            "visibility": selectedVisibility.rawValue,
            "tags": [],
            "contentType": "video",
            "fileSize": fileSize,
            "duration": duration,
            "isNewPlace": isNewPlace
        ]
        
        // Add place creation data if it's a new place
        if isNewPlace {
            body["placeAddress"] = place.address ?? ""
            body["placeCoordinates"] = place.location?.coordinates ?? []
            body["placeCategory"] = place.category.rawValue
            body["placeDescription"] = place.description ?? ""
            body["placePhone"] = place.phone ?? ""
            body["placeWebsite"] = place.website ?? ""
        }
        
        // Initiate upload
        APIService.shared.request(
            endpoint: "videos/upload/initiate",
            method: .post,
            body: body
        ) { [weak self] (result: Result<UploadInitiateResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success, let data = response.data {
                    // Upload video files to storage
                    self?.uploadVideoFiles(
                        videoData: videoData,
                        thumbnailData: thumbnailData,
                        videoId: data.videoId,
                        uploadUrls: data.uploadUrls,
                        storagePaths: data.storagePaths,
                        originalSize: fileSize,
                        place: place,
                        loadingAlert: loadingAlert
                    )
                } else {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self?.showErrorAlert("Failed to initiate video upload")
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        // Check if it's a quota error
                        if error.localizedDescription.lowercased().contains("quota") {
                            self?.handleQuotaError()
                        } else {
                            self?.showErrorAlert("Failed to initiate upload: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func uploadVideoFiles(
        videoData: Data,
        thumbnailData: Data?,
        videoId: String,
        uploadUrls: UploadInitiateResponse.UploadUrls,
        storagePaths: UploadInitiateResponse.StoragePaths,
        originalSize: Int,
        place: Place,
        loadingAlert: UIAlertController
    ) {
        let group = DispatchGroup()
        var uploadErrors: [Error] = []
        
        // Upload video file
        if let videoUrl = uploadUrls.video {
            group.enter()
            uploadFile(data: videoData, to: videoUrl, contentType: "video/mp4") { error in
                if let error = error {
                    uploadErrors.append(error)
                }
                group.leave()
            }
        }
        
        // Upload thumbnail if available
        if let thumbnailData = thumbnailData {
            print("📤 Uploading thumbnail - Size: \(thumbnailData.count) bytes")
            print("   - Upload URL: \(uploadUrls.thumbnail.suffix(100))")
            group.enter()
            uploadFile(data: thumbnailData, to: uploadUrls.thumbnail, contentType: "image/jpeg") { error in
                if let error = error {
                    print("❌ Thumbnail upload failed: \(error)")
                    uploadErrors.append(error)
                } else {
                    print("✅ Thumbnail uploaded successfully")
                }
                group.leave()
            }
        } else {
            print("⚠️ No thumbnail data available for upload")
        }
        
        // Wait for all uploads to complete
        group.notify(queue: .main) { [weak self] in
            if !uploadErrors.isEmpty {
                loadingAlert.dismiss(animated: true) {
                    self?.showErrorAlert("Failed to upload video files")
                }
            } else {
                // Complete the upload
                self?.completeVideoUpload(
                    videoId: videoId,
                    storagePaths: storagePaths,
                    originalSize: originalSize,
                    place: place,
                    loadingAlert: loadingAlert
                )
            }
        }
    }
    
    private func uploadFile(data: Data, to urlString: String, contentType: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(NSError(domain: "ContentUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(error)
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let error = NSError(domain: "ContentUpload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(httpResponse.statusCode)"])
                completion(error)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    private func completeVideoUpload(
        videoId: String,
        storagePaths: UploadInitiateResponse.StoragePaths,
        originalSize: Int,
        place: Place,
        loadingAlert: UIAlertController
    ) {
        let body: [String: Any] = [
            "storagePaths": [
                "video": storagePaths.video ?? "",
                "preview": storagePaths.preview ?? "",
                "thumbnail": storagePaths.thumbnail ?? ""
            ],
            "originalSize": originalSize,
            "compressionRatio": 0.7 // Approximate compression ratio
        ]
        
        APIService.shared.request(
            endpoint: "videos/\(videoId)/upload/complete",
            method: .post,
            body: body
        ) { [weak self] (result: Result<UploadCompleteResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        print("📹 ContentUpload: Complete response received - success: \(response.success)")
                        if let video = response.data {
                            print("📹 ContentUpload: Video data - ID: \(video.id), Status: \(video.uploadStatus), URLs: video=\(video.videoUrl ?? "nil"), preview=\(video.previewUrl ?? "nil"), thumbnail=\(video.thumbnailUrl ?? "nil")")
                            
                            // Check if upload actually succeeded
                            if video.uploadStatus == .error || video.uploadStatus == .failed {
                                print("❌ ContentUpload: Upload failed with status: \(video.uploadStatus)")
                                // Delay to ensure loading alert is fully dismissed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    self?.showErrorAlert("Upload failed. Please try again.")
                                }
                            } else if response.success {
                                let moment = PlaceMoment(from: video)
                                if self?.shouldNavigateToMomentsOnSuccess == true {
                                    self?.navigateToMomentsTab(with: moment)
                                } else {
                                    self?.delegate?.contentUploadDidFinish(with: moment)
                                    self?.dismiss(animated: true)
                                }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    self?.showErrorAlert("Failed to complete upload")
                                }
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self?.showErrorAlert("Failed to complete upload")
                            }
                        }
                        
                    case .failure(let error):
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self?.showErrorAlert("Upload failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func uploadCarousel(_ images: [UIImage], for place: Place, loadingAlert: UIAlertController) {
        // Similar to photo but with multiple images
        // For now, show error as carousel needs more implementation
        loadingAlert.dismiss(animated: true) {
            self.showErrorAlert("Carousel upload coming soon")
        }
    }
    
    private func uploadImageToStorage(imageData: Data, uploadUrl: String, videoId: String, storagePaths: UploadInitiateResponse.StoragePaths, place: Place, loadingAlert: UIAlertController) {
        guard let url = URL(string: uploadUrl) else {
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    self.showErrorAlert("Invalid upload URL")
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        self?.showErrorAlert("Upload failed: \(error.localizedDescription)")
                    }
                }
                return
            }
            
            // Complete the upload
            self?.completeUpload(videoId: videoId, storagePaths: storagePaths, place: place, loadingAlert: loadingAlert)
        }.resume()
    }
    
    private func completeUpload(videoId: String, storagePaths: UploadInitiateResponse.StoragePaths, place: Place, loadingAlert: UIAlertController) {
        let body: [String: Any] = [
            "storagePaths": [
                "video": storagePaths.video ?? "",
                "preview": storagePaths.preview ?? "",
                "thumbnail": storagePaths.thumbnail
            ],
            "originalSize": 0,
            "compressionRatio": 0
        ]
        
        APIService.shared.request(
            endpoint: "videos/\(videoId)/upload/complete",
            method: .post,
            body: body
        ) { [weak self] (result: Result<UploadCompleteResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        print("📹 ContentUpload: Complete response received - success: \(response.success)")
                        if let video = response.data {
                            print("📹 ContentUpload: Video data - ID: \(video.id), Status: \(video.uploadStatus), URLs: video=\(video.videoUrl ?? "nil"), preview=\(video.previewUrl ?? "nil"), thumbnail=\(video.thumbnailUrl ?? "nil")")
                            
                            // Check if upload actually succeeded
                            if video.uploadStatus == .error || video.uploadStatus == .failed {
                                print("❌ ContentUpload: Upload failed with status: \(video.uploadStatus)")
                                // Delay to ensure loading alert is fully dismissed
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    self?.showErrorAlert("Upload failed. Please try again.")
                                }
                            } else if response.success {
                                let moment = PlaceMoment(from: video)
                                if self?.shouldNavigateToMomentsOnSuccess == true {
                                    self?.navigateToMomentsTab(with: moment)
                                } else {
                                    self?.delegate?.contentUploadDidFinish(with: moment)
                                    self?.dismiss(animated: true)
                                }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    self?.showErrorAlert("Failed to complete upload")
                                }
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self?.showErrorAlert("Failed to complete upload")
                            }
                        }
                        
                    case .failure(let error):
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self?.showErrorAlert("Upload failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Response Models
struct UploadInitiateResponse: Codable {
    let success: Bool
    let data: UploadData?
    
    struct UploadData: Codable {
        let videoId: String
        let uploadUrls: UploadUrls
        let storagePaths: StoragePaths
    }
    
    struct UploadUrls: Codable {
        let video: String?
        let preview: String?
        let thumbnail: String
    }
    
    struct StoragePaths: Codable {
        let video: String?
        let preview: String?
        let thumbnail: String
    }
}

struct UploadCompleteResponse: Codable {
    let success: Bool
    let data: PlaceVideo?
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
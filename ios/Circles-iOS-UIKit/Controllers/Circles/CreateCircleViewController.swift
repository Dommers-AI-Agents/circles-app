import UIKit
import Photos

class CreateCircleViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: CreateCircleDelegate?
    private var keyboardHeight: CGFloat = 0
    
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
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let addCoverPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Add Cover Photo", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.7)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "Circle Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter circle name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Description (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Category"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categorySegmentedControl: UISegmentedControl = {
        let categories = ["Travel", "Food", "Shopping", "Services", "Healthcare", "Entertainment", "Other"]
        let segmentedControl = UISegmentedControl(items: categories)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Privacy"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacySegmentedControl: UISegmentedControl = {
        let privacyLevels = ["Public", "My Network", "Private"]
        let segmentedControl = UISegmentedControl(items: privacyLevels)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.text = "Location (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let locationTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. New York, Paris, etc."
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let tagsLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags (optional, comma separated)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. vacation, foodie, nyc"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let inviteLabel: UILabel = {
        let label = UILabel()
        label.text = "Share with Connection(s) (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let connectionPickerView: ConnectionPickerView = {
        let picker = ConnectionPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()
    
    private let createButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Create Circle", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    private var selectedImage: UIImage? {
        didSet {
            if let image = selectedImage {
                coverImageView.image = image
                coverImageView.contentMode = .scaleAspectFill
                addCoverPhotoButton.setTitle("Change Photo", for: .normal)
            } else {
                coverImageView.image = Constants.Images.defaultCoverImage
                coverImageView.contentMode = .scaleAspectFit
                coverImageView.tintColor = Constants.Colors.primary
                addCoverPhotoButton.setTitle("Add Cover Photo", for: .normal)
            }
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        setupKeyboardObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardObservers()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Create Circle"
        
        // Default cover image
        coverImageView.image = Constants.Images.defaultCoverImage
        coverImageView.contentMode = .scaleAspectFit
        coverImageView.tintColor = Constants.Colors.primary
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(coverImageView)
        contentView.addSubview(addCoverPhotoButton)
        contentView.addSubview(nameLabel)
        contentView.addSubview(nameTextField)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(descriptionTextView)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(categorySegmentedControl)
        contentView.addSubview(privacyLabel)
        contentView.addSubview(privacySegmentedControl)
        contentView.addSubview(locationLabel)
        contentView.addSubview(locationTextField)
        contentView.addSubview(tagsLabel)
        contentView.addSubview(tagsTextField)
        contentView.addSubview(inviteLabel)
        contentView.addSubview(connectionPickerView)
        contentView.addSubview(createButton)
        
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
            
            // Cover image view
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            coverImageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Add cover photo button
            addCoverPhotoButton.centerXAnchor.constraint(equalTo: coverImageView.centerXAnchor),
            addCoverPhotoButton.centerYAnchor.constraint(equalTo: coverImageView.centerYAnchor),
            addCoverPhotoButton.widthAnchor.constraint(equalToConstant: 150),
            addCoverPhotoButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Create button - positioned right below the cover image
            createButton.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: Constants.Spacing.medium),
            createButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            createButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            createButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Name text field
            nameTextField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            nameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            nameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            nameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Description text view
            descriptionTextView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            descriptionTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            descriptionTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 100),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: Constants.Spacing.medium),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Category segmented control
            categorySegmentedControl.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Privacy label
            privacyLabel.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            privacyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Privacy segmented control
            privacySegmentedControl.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: Constants.Spacing.small),
            privacySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            privacySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Location label
            locationLabel.topAnchor.constraint(equalTo: privacySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            locationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Location text field
            locationTextField.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: Constants.Spacing.small),
            locationTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            locationTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            locationTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Tags label
            tagsLabel.topAnchor.constraint(equalTo: locationTextField.bottomAnchor, constant: Constants.Spacing.medium),
            tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Tags text field
            tagsTextField.topAnchor.constraint(equalTo: tagsLabel.bottomAnchor, constant: Constants.Spacing.small),
            tagsTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            tagsTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            tagsTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Invite label
            inviteLabel.topAnchor.constraint(equalTo: tagsTextField.bottomAnchor, constant: Constants.Spacing.medium),
            inviteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Connection picker view
            connectionPickerView.topAnchor.constraint(equalTo: inviteLabel.bottomAnchor, constant: Constants.Spacing.small),
            connectionPickerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            connectionPickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            connectionPickerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            connectionPickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
    }
    
    private func setupActions() {
        addCoverPhotoButton.addTarget(self, action: #selector(addCoverPhotoButtonTapped), for: .touchUpInside)
        createButton.addTarget(self, action: #selector(createButtonTapped), for: .touchUpInside)
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        // Set text field delegates for automatic scrolling
        nameTextField.delegate = self
        locationTextField.delegate = self
        tagsTextField.delegate = self
        descriptionTextView.delegate = self
        
        // Set connection picker delegate
        connectionPickerView.delegate = self
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Actions
    @objc private func addCoverPhotoButtonTapped() {
        // Check photo library permissions
        checkPhotoLibraryPermissions()
    }
    
    @objc private func createButtonTapped() {
        // Validate required fields
        guard let name = nameTextField.text, !name.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a name for your circle")
            return
        }
        
        // Note: Duplicate name check removed - backend will validate
        
        // Get selected category
        let categoryIndex = categorySegmentedControl.selectedSegmentIndex
        let categories = [CircleCategory.travel, .food, .shopping, .services, .healthcare, .entertainment, .other]
        let category = categories[categoryIndex]
        
        // Get selected privacy level
        let privacyIndex = privacySegmentedControl.selectedSegmentIndex
        let privacyLevels = [PrivacyLevel.public, .myNetwork, .private]
        let privacy = privacyLevels[privacyIndex]
        
        // Get optional fields
        let description = descriptionTextView.text?.isEmpty == false ? descriptionTextView.text : nil
        let location = locationTextField.text?.isEmpty == false ? locationTextField.text : nil
        
        // Get tags
        var tags: [String]?
        if let tagsText = tagsTextField.text, !tagsText.isEmpty {
            tags = tagsText.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        
        // Get selected connections and any email text
        let selectedConnections = connectionPickerView.getSelectedConnections()
        let emailText = connectionPickerView.getEmailText()
        
        // Get cover image data - optimize for upload
        var coverImageData: Data? = nil
        var defaultImageUrl: String? = nil
        
        if let image = selectedImage {
            // Use optimized upload function to create small thumbnail image (100KB max)
            coverImageData = image.optimizedForUpload(maxDimension: 300, targetSizeKB: 100)
            
            // Log the final size for debugging
            if let data = coverImageData {
                let sizeKB = data.count / 1024
                print("Optimized image size: \(sizeKB) KB")
                
                // Extra safety check - if still too large, make it even smaller
                if sizeKB > 100 {
                    print("Image still too large, applying extra compression")
                    coverImageData = image.optimizedForUpload(maxDimension: 200, targetSizeKB: 50)
                    if let newData = coverImageData {
                        print("Final compressed size: \(newData.count / 1024) KB")
                    }
                }
            }
        } else if let location = location?.lowercased() {
            // Set default image based on location
            defaultImageUrl = getDefaultImageUrl(for: location)
        }
        
        // Disable the create button and show loading
        createButton.isEnabled = false
        createButton.setTitle("Creating...", for: .normal)
        
        // If we have a default image URL and no custom image, pass it directly
        if defaultImageUrl != nil && coverImageData == nil {
            // Create circle with default image URL
            var body: [String: Any] = [
                "name": name,
                "privacy": privacy.rawValue,
                "category": category.rawValue
            ]
            
            if let description = description {
                body["description"] = description
            }
            if let location = location {
                body["location"] = location
            }
            if let tags = tags {
                body["tags"] = tags
            }
            if let coverImage = defaultImageUrl {
                body["coverImage"] = coverImage
            }
            
            APIService.shared.request(
                endpoint: "circles",
                method: .post,
                body: body,
                requiresAuth: true
            ) { [weak self] (result: Result<CircleResponse, APIError>) in
                DispatchQueue.main.async {
                    self?.createButton.isEnabled = true
                    self?.createButton.setTitle("Create Circle", for: .normal)
                    
                    switch result {
                    case .success(let response):
                        print("✅ Circle created successfully with default image: \(response.circle.name)")
                        print("📍 Navigation controller exists: \(self?.navigationController != nil)")
                        print("📍 Navigation stack count: \(self?.navigationController?.viewControllers.count ?? 0)")
                        
                        let circle = response.circle
                        
                        // Share circle with selected connections
                        self?.shareCircleWithConnections(circle, connections: selectedConnections, email: emailText)
                        
                        self?.delegate?.didCreateCircle(circle)
                    case .failure(let error):
                        self?.presentAlert(
                            title: "Error",
                            message: "Failed to create circle: \(error.localizedDescription)"
                        )
                    }
                }
            }
        } else {
            // Create the circle using CircleService with image upload
            CircleService.shared.createCircle(
                name: name,
                description: description,
                privacy: privacy,
                category: category,
                location: location,
                tags: tags,
                coverImage: coverImageData
            ) { [weak self] result in
                DispatchQueue.main.async {
                    self?.createButton.isEnabled = true
                    self?.createButton.setTitle("Create Circle", for: .normal)
                    
                    switch result {
                    case .success(let circle):
                        print("✅ Circle created successfully: \(circle.name)")
                        print("📍 Navigation controller exists: \(self?.navigationController != nil)")
                        print("📍 Navigation stack count: \(self?.navigationController?.viewControllers.count ?? 0)")
                        
                        // Share circle with selected connections
                        self?.shareCircleWithConnections(circle, connections: selectedConnections, email: emailText)
                        
                        self?.delegate?.didCreateCircle(circle)
                        
                    case .failure(let error):
                        self?.presentAlert(
                            title: "Error",
                            message: "Failed to create circle: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        keyboardHeight = keyboardFrame.height
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = self.keyboardHeight
            self.scrollView.scrollIndicatorInsets.bottom = self.keyboardHeight
        }
        
        // Scroll to active field if needed
        if let activeField = view.subviews.first(where: { $0.isFirstResponder }) {
            scrollToField(activeField)
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        keyboardHeight = 0
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.scrollIndicatorInsets.bottom = 0
        }
    }
    
    private func scrollToField(_ field: UIView) {
        // Convert field frame to scroll view coordinates
        let fieldFrame = field.convert(field.bounds, to: scrollView)
        let visibleHeight = scrollView.bounds.height - keyboardHeight
        
        // Check if field is below the visible area
        if fieldFrame.maxY > scrollView.contentOffset.y + visibleHeight {
            let targetOffset = fieldFrame.maxY - visibleHeight + 20 // Add some padding
            scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
        }
    }
    
    // MARK: - Helper Methods
    private func checkPhotoLibraryPermissions() {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            presentImagePicker()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        self?.presentImagePicker()
                    }
                }
            }
        case .denied, .restricted:
            presentPhotoLibraryPermissionAlert()
        @unknown default:
            break
        }
    }
    
    private func presentImagePicker() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        present(imagePicker, animated: true)
    }
    
    private func presentPhotoLibraryPermissionAlert() {
        let alert = UIAlertController(
            title: "Photo Library Access",
            message: "Please allow access to your photo library in Settings to add a cover photo.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func presentAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alertController, animated: true)
    }
    
    private func getDefaultImageUrl(for location: String) -> String? {
        // Map of locations to famous landmark image URLs
        let locationImages: [String: String] = [
            // US Cities
            "new york": "https://images.unsplash.com/photo-1485871981521-5b1fd3805eee?w=800&h=800&fit=crop", // Statue of Liberty
            "nyc": "https://images.unsplash.com/photo-1485871981521-5b1fd3805eee?w=800&h=800&fit=crop",
            "manhattan": "https://images.unsplash.com/photo-1485871981521-5b1fd3805eee?w=800&h=800&fit=crop",
            "san francisco": "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=800&h=800&fit=crop", // Golden Gate
            "sf": "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=800&h=800&fit=crop",
            "los angeles": "https://images.unsplash.com/photo-1534190760961-74e8c1c5c3da?w=800&h=800&fit=crop", // Hollywood Sign
            "la": "https://images.unsplash.com/photo-1534190760961-74e8c1c5c3da?w=800&h=800&fit=crop",
            "chicago": "https://images.unsplash.com/photo-1494522855154-9297ac14b55f?w=800&h=800&fit=crop", // Chicago Skyline
            "miami": "https://images.unsplash.com/photo-1514214246283-d427a95c5d2f?w=800&h=800&fit=crop", // Miami Beach
            "seattle": "https://images.unsplash.com/photo-1502175353174-a7a70e73b362?w=800&h=800&fit=crop", // Space Needle
            "boston": "https://images.unsplash.com/photo-1491168034976-6d24c7c0835f?w=800&h=800&fit=crop", // Boston Harbor
            "washington dc": "https://images.unsplash.com/photo-1463839346397-8e9946845e6d?w=800&h=800&fit=crop", // Capitol
            "dc": "https://images.unsplash.com/photo-1463839346397-8e9946845e6d?w=800&h=800&fit=crop",
            
            // International Cities
            "paris": "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800&h=800&fit=crop", // Eiffel Tower
            "london": "https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=800&h=800&fit=crop", // Tower Bridge
            "tokyo": "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=800&h=800&fit=crop", // Tokyo Tower
            "sydney": "https://images.unsplash.com/photo-1523059623039-a9ed027e7fad?w=800&h=800&fit=crop", // Opera House
            "rome": "https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=800&h=800&fit=crop", // Colosseum
            "barcelona": "https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=800&h=800&fit=crop", // Sagrada Familia
            "dubai": "https://images.unsplash.com/photo-1512453979798-5ea266f8880c?w=800&h=800&fit=crop", // Burj Khalifa
            "singapore": "https://images.unsplash.com/photo-1508964942454-1a56651d54ac?w=800&h=800&fit=crop", // Marina Bay
            
            // US States
            "california": "https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=800&h=800&fit=crop",
            "new jersey": "https://images.unsplash.com/photo-1579876570508-d2a5b5e6c5d3?w=800&h=800&fit=crop", // Atlantic City
            "nj": "https://images.unsplash.com/photo-1579876570508-d2a5b5e6c5d3?w=800&h=800&fit=crop",
            "florida": "https://images.unsplash.com/photo-1514214246283-d427a95c5d2f?w=800&h=800&fit=crop",
            "texas": "https://images.unsplash.com/photo-1531218150217-54595bc2b934?w=800&h=800&fit=crop", // Austin
            "hawaii": "https://images.unsplash.com/photo-1542259009477-d625272157b7?w=800&h=800&fit=crop", // Hawaii Beach
            
            // Generic/Default
            "beach": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=800&fit=crop",
            "mountain": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&h=800&fit=crop",
            "city": "https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=800&h=800&fit=crop",
            "travel": "https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800&h=800&fit=crop"
        ]
        
        // Check for exact match
        if let imageUrl = locationImages[location] {
            return imageUrl
        }
        
        // Check if location contains any of the keys
        for (key, imageUrl) in locationImages {
            if location.contains(key) {
                return imageUrl
            }
        }
        
        // Return a default travel image if no match found
        return "https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800&h=800&fit=crop"
    }
    
    private func shareCircleWithConnections(_ circle: Circle, connections: [User], email: String?) {
        // Share with each selected connection
        for user in connections {
            NetworkManager.shared.shareCircle(
                circle.id,
                with: user.id,
                accessLevel: .viewOnly
            ) { result in
                switch result {
                case .success:
                    print("✅ Shared circle with \(user.displayName)")
                case .failure(let error):
                    print("❌ Failed to share circle with \(user.displayName): \(error)")
                }
            }
        }
        
        // Share with email if provided
        if let email = email, !email.isEmpty {
            // Parse email addresses
            let emails = email.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            
            for emailAddress in emails {
                // Validate email format
                if isValidEmail(emailAddress) {
                    NetworkManager.shared.shareCircle(
                        circle.id,
                        with: nil,
                        email: emailAddress,
                        accessLevel: .viewOnly
                    ) { result in
                        switch result {
                        case .success:
                            print("✅ Sent circle invitation to \(emailAddress)")
                        case .failure(let error):
                            print("❌ Failed to send invitation to \(emailAddress): \(error)")
                        }
                    }
                }
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension CreateCircleViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
        }
        
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UITextFieldDelegate
extension CreateCircleViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollToField(textField)
        }
    }
}

// MARK: - UITextViewDelegate
extension CreateCircleViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollToField(textView)
        }
    }
}

// MARK: - ConnectionPickerDelegate
extension CreateCircleViewController: ConnectionPickerDelegate {
    func connectionPicker(_ picker: ConnectionPickerView, didSelectConnection connection: User) {
        // Connection selected - no additional action needed as the picker handles UI updates
        print("Selected connection: \(connection.displayName)")
    }
    
    func connectionPicker(_ picker: ConnectionPickerView, didDeselectConnection connection: User) {
        // Connection deselected - no additional action needed as the picker handles UI updates
        print("Deselected connection: \(connection.displayName)")
    }
}

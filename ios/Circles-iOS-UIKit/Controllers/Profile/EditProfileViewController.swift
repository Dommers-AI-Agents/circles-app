import UIKit
import Photos

class EditProfileViewController: UIViewController {
    
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
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.layer.cornerRadius = 50
        imageView.layer.borderWidth = 3
        imageView.layer.borderColor = Constants.Colors.white.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let changePhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Change Photo", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let displayNameLabel: UILabel = {
        let label = UILabel()
        label.text = "Display Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let displayNameTextField: UITextField = {
        let textField = UITextField()
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.text = "Email"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.isEnabled = false // Email cannot be changed
        textField.backgroundColor = Constants.Colors.lightGray.withAlphaComponent(0.3)
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.text = "Location"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let locationTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. New York, NY"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let bioLabel: UILabel = {
        let label = UILabel()
        label.text = "Bio"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bioTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Save Changes", for: .normal)
        button.setTitleColor(Constants.Colors.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    private var selectedImage: UIImage?
    private var currentUser: User?
    private var isLoading = false
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        loadUserProfile()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Edit Profile"
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(changePhotoButton)
        contentView.addSubview(displayNameLabel)
        contentView.addSubview(displayNameTextField)
        contentView.addSubview(emailLabel)
        contentView.addSubview(emailTextField)
        contentView.addSubview(locationLabel)
        contentView.addSubview(locationTextField)
        contentView.addSubview(bioLabel)
        contentView.addSubview(bioTextView)
        contentView.addSubview(saveButton)
        
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
            
            // Profile image view
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            profileImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 100),
            profileImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Change photo button
            changePhotoButton.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.small),
            changePhotoButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Display name label
            displayNameLabel.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: Constants.Spacing.large),
            displayNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Display name text field
            displayNameTextField.topAnchor.constraint(equalTo: displayNameLabel.bottomAnchor, constant: Constants.Spacing.small),
            displayNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            displayNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            displayNameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Email label
            emailLabel.topAnchor.constraint(equalTo: displayNameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            emailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Email text field
            emailTextField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: Constants.Spacing.small),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            emailTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Location label
            locationLabel.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: Constants.Spacing.medium),
            locationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Location text field
            locationTextField.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: Constants.Spacing.small),
            locationTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            locationTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            locationTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Bio label
            bioLabel.topAnchor.constraint(equalTo: locationTextField.bottomAnchor, constant: Constants.Spacing.medium),
            bioLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Bio text view
            bioTextView.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: Constants.Spacing.small),
            bioTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            bioTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            bioTextView.heightAnchor.constraint(equalToConstant: 120),
            
            // Save button
            saveButton.topAnchor.constraint(equalTo: bioTextView.bottomAnchor, constant: Constants.Spacing.large),
            saveButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
        
        // Add tap gesture to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupActions() {
        changePhotoButton.addTarget(self, action: #selector(changePhotoButtonTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Data Loading
    private func loadUserProfile() {
        // Load current user profile
        if let user = AuthService.shared.currentUser {
            currentUser = user
            displayUserProfile(user)
        } else {
            // Fetch current user if not cached
            AuthService.shared.fetchCurrentUser { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let user):
                        self?.currentUser = user
                        self?.displayUserProfile(user)
                    case .failure:
                        self?.navigationController?.popViewController(animated: true)
                    }
                }
            }
        }
    }
    
    private func displayUserProfile(_ user: User) {
        // Profile image
        if let profileImageUrl = user.profilePicture {
            ImageService.shared.loadImage(from: profileImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                    if image == nil {
                        self?.profileImageView.tintColor = Constants.Colors.primary
                    }
                }
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.tintColor = Constants.Colors.primary
        }
        
        // User info
        displayNameTextField.text = user.displayName
        emailTextField.text = user.email
        locationTextField.text = user.location ?? ""
        bioTextView.text = user.bio ?? ""
    }
    
    // MARK: - Actions
    @objc private func changePhotoButtonTapped() {
        checkPhotoLibraryPermissions()
    }
    
    @objc private func saveButtonTapped() {
        // Validate required fields
        guard let displayName = displayNameTextField.text, !displayName.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a display name")
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        saveButton.isEnabled = false
        saveButton.setTitle("Saving...", for: .normal)
        
        // Prepare update data
        var updates: [String: Any] = [
            "displayName": displayName
        ]
        
        if let location = locationTextField.text, !location.isEmpty {
            updates["location"] = location
        }
        
        if let bio = bioTextView.text, !bio.isEmpty {
            updates["bio"] = bio
        }
        
        // Upload profile image if changed
        if let image = selectedImage {
            uploadProfileImage(image) { [weak self] imageUrl in
                guard let self = self else { return }
                
                if let imageUrl = imageUrl {
                    updates["profilePicture"] = imageUrl
                }
                
                self.updateProfile(with: updates)
            }
        } else {
            updateProfile(with: updates)
        }
    }
    
    private func uploadProfileImage(_ image: UIImage, completion: @escaping (String?) -> Void) {
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(nil)
            return
        }
        
        // In a real app, you would upload to a storage service
        // For now, we'll simulate an upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Return a mock URL
            completion("https://api.circles.app/images/profile_\(UUID().uuidString).jpg")
        }
    }
    
    private func updateProfile(with updates: [String: Any]) {
        let displayName = updates["displayName"] as? String
        let location = updates["location"] as? String
        let bio = updates["bio"] as? String
        
        // Convert profile image URL to data if needed
        var profileImageData: Data?
        if let _ = updates["profilePicture"] as? String,
           let image = selectedImage {
            profileImageData = image.jpegData(compressionQuality: 0.8)
        }
        
        UserService.shared.updateUserProfile(
            displayName: displayName,
            bio: bio,
            location: location,
            profilePicture: profileImageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.saveButton.isEnabled = true
                self?.saveButton.setTitle("Save Changes", for: .normal)
                
                switch result {
                case .success(let updatedUser):
                    // Update the cached user
                    AuthService.shared.updateCurrentUser(updatedUser)
                    
                    self?.presentAlert(title: "Success", message: "Profile updated successfully") { _ in
                        self?.navigationController?.popViewController(animated: true)
                    }
                case .failure(let error):
                    self?.presentAlert(title: "Error", message: "Failed to update profile: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
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
            message: "Please allow access to your photo library in Settings to change your profile photo.",
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
}

// MARK: - UIImagePickerControllerDelegate
extension EditProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
            profileImageView.image = editedImage
            profileImageView.contentMode = .scaleAspectFill
        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
            profileImageView.image = originalImage
            profileImageView.contentMode = .scaleAspectFill
        }
        
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

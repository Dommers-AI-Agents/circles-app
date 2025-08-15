import UIKit
import Photos

class EditProfileViewController: BaseViewController {
    
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
    
    private let useAvatarButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Use Avatar", for: .normal)
        button.setTitleColor(Constants.Colors.secondary, for: .normal)
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
    
    private let firstNameLabel: UILabel = {
        let label = UILabel()
        label.text = "First Name (Optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let firstNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "First name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let lastNameLabel: UILabel = {
        let label = UILabel()
        label.text = "Last Name (Optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let lastNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Last name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let phoneNumberLabel: UILabel = {
        let label = UILabel()
        label.text = "Phone Number (Optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let phoneNumberTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Phone number"
        textField.keyboardType = .phonePad
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
    
    private lazy var saveButton = UIButton.primaryButton(title: "Save Changes")
    
    // MARK: - Properties
    private var selectedImage: UIImage?
    private var selectedAvatarName: String?
    private var currentUser: User?
    private var isLoading = false
    
    // MARK: - Lifecycle
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { false }
    override var enablesPullToRefresh: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        setupKeyboardHandling(scrollView: scrollView, dismissOnTap: true)
        loadUserProfile()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        setupNavigationBar(title: "Edit Profile")
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(changePhotoButton)
        contentView.addSubview(useAvatarButton)
        contentView.addSubview(displayNameLabel)
        contentView.addSubview(displayNameTextField)
        contentView.addSubview(firstNameLabel)
        contentView.addSubview(firstNameTextField)
        contentView.addSubview(lastNameLabel)
        contentView.addSubview(lastNameTextField)
        contentView.addSubview(phoneNumberLabel)
        contentView.addSubview(phoneNumberTextField)
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
            changePhotoButton.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -5),
            
            useAvatarButton.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: Constants.Spacing.small),
            useAvatarButton.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 5),
            
            // Display name label
            displayNameLabel.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: Constants.Spacing.large),
            displayNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Display name text field
            displayNameTextField.topAnchor.constraint(equalTo: displayNameLabel.bottomAnchor, constant: Constants.Spacing.small),
            displayNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            displayNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            displayNameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // First name label
            firstNameLabel.topAnchor.constraint(equalTo: displayNameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            firstNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // First name text field
            firstNameTextField.topAnchor.constraint(equalTo: firstNameLabel.bottomAnchor, constant: Constants.Spacing.small),
            firstNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            firstNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            firstNameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Last name label
            lastNameLabel.topAnchor.constraint(equalTo: firstNameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            lastNameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Last name text field
            lastNameTextField.topAnchor.constraint(equalTo: lastNameLabel.bottomAnchor, constant: Constants.Spacing.small),
            lastNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            lastNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            lastNameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Phone number label
            phoneNumberLabel.topAnchor.constraint(equalTo: lastNameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            phoneNumberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Phone number text field
            phoneNumberTextField.topAnchor.constraint(equalTo: phoneNumberLabel.bottomAnchor, constant: Constants.Spacing.small),
            phoneNumberTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            phoneNumberTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            phoneNumberTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Email label
            emailLabel.topAnchor.constraint(equalTo: phoneNumberTextField.bottomAnchor, constant: Constants.Spacing.medium),
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
    }
    
    private func setupActions() {
        changePhotoButton.addTarget(self, action: #selector(changePhotoButtonTapped), for: .touchUpInside)
        useAvatarButton.addTarget(self, action: #selector(useAvatarButtonTapped), for: .touchUpInside)
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
        currentUser = user
        
        // Profile image
        updateProfileImage()
        
        // User info
        displayNameTextField.text = user.displayName
        firstNameTextField.text = user.firstName ?? ""
        lastNameTextField.text = user.lastName ?? ""
        phoneNumberTextField.text = user.phoneNumber ?? ""
        emailTextField.text = user.email
        locationTextField.text = user.location ?? ""
        bioTextView.text = user.bio ?? ""
    }
    
    // MARK: - Actions
    @objc private func changePhotoButtonTapped() {
        checkPhotoLibraryPermissions()
    }
    
    @objc private func useAvatarButtonTapped() {
        showAvatarPicker()
    }
    
    @objc private func dismissAvatarPicker() {
        dismiss(animated: true)
    }
    
    @objc private func saveButtonTapped() {
        // Validate required fields
        guard let displayName = displayNameTextField.text, !displayName.isEmpty else {
            showError("Please enter a display name")
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        saveButton.setLoading(true)
        
        // Prepare update data
        var updates: [String: Any] = [
            "displayName": displayName
        ]
        
        // Always include these fields to ensure they're saved
        updates["firstName"] = firstNameTextField.text ?? ""
        updates["lastName"] = lastNameTextField.text ?? ""
        updates["phoneNumber"] = phoneNumberTextField.text ?? ""
        
        if let location = locationTextField.text, !location.isEmpty {
            updates["location"] = location
        }
        
        if let bio = bioTextView.text, !bio.isEmpty {
            updates["bio"] = bio
        }
        
        // Upload profile image if changed
        if let _ = selectedImage {
            // Profile image will be handled by UserService
            updateProfile(with: updates)
        } else {
            updateProfile(with: updates)
        }
    }
    
    
    private func updateProfile(with updates: [String: Any]) {
        let displayName = updates["displayName"] as? String
        let location = updates["location"] as? String
        let bio = updates["bio"] as? String
        
        // Debug logging
        print("🔍 EditProfileViewController - Sending updates:")
        print("   - Display Name: \(displayName ?? "nil")")
        print("   - First Name: \(updates["firstName"] ?? "nil")")
        print("   - Last Name: \(updates["lastName"] ?? "nil")")
        print("   - Phone Number: \(updates["phoneNumber"] ?? "nil")")
        print("   - Location: \(location ?? "nil")")
        print("   - Bio: \(bio ?? "nil")")
        
        // Convert selected image to data or handle avatar
        var profileImageData: Data?
        var profileImageUrl: String?
        
        if let image = selectedImage {
            profileImageData = image.jpegData(compressionQuality: 0.8)
        } else if let avatarName = selectedAvatarName {
            // Use special URL format for avatar
            profileImageUrl = "sf-symbol:\(avatarName)"
        }
        
        UserService.shared.updateUserProfile(
            displayName: displayName,
            firstName: updates["firstName"] as? String,
            lastName: updates["lastName"] as? String,
            phoneNumber: updates["phoneNumber"] as? String,
            bio: bio,
            location: location,
            profilePicture: profileImageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.saveButton.setLoading(false)
                self?.saveButton.setTitle("Save Changes", for: .normal)
                
                switch result {
                case .success(let updatedUser):
                    // Debug logging
                    print("✅ EditProfileViewController - Received updated user:")
                    print("   - Display Name: \(updatedUser.displayName)")
                    print("   - First Name: \(updatedUser.firstName ?? "nil")")
                    print("   - Last Name: \(updatedUser.lastName ?? "nil")")
                    print("   - Phone Number: \(updatedUser.phoneNumber ?? "nil")")
                    
                    // Update the cached user
                    AuthService.shared.updateCurrentUser(updatedUser)
                    
                    self?.presentAlert(title: "Success", message: "Profile updated successfully") {
                        self?.navigationController?.popViewController(animated: true)
                    }
                case .failure(let error):
                    self?.showError("Failed to update profile: \(error.localizedDescription)")
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
    
    private func showAvatarPicker() {
        let avatarView = DefaultImageSelectionView(type: .avatar)
        avatarView.onImageSelected = { [weak self] symbolName in
            self?.selectedAvatarName = symbolName
            self?.selectedImage = nil // Clear any selected photo
            self?.updateProfileImage()
            self?.dismiss(animated: true)
        }
        
        let containerVC = UIViewController()
        containerVC.view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        containerVC.modalPresentationStyle = .overFullScreen
        containerVC.modalTransitionStyle = .crossDissolve
        
        containerVC.view.addSubview(avatarView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            avatarView.centerXAnchor.constraint(equalTo: containerVC.view.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: containerVC.view.centerYAnchor),
            avatarView.widthAnchor.constraint(equalTo: containerVC.view.widthAnchor, constant: -40),
            avatarView.heightAnchor.constraint(lessThanOrEqualToConstant: 400)
        ])
        
        // Add tap gesture to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissAvatarPicker))
        tapGesture.delegate = self
        containerVC.view.addGestureRecognizer(tapGesture)
        
        present(containerVC, animated: true)
    }
    
    private func updateProfileImage() {
        if let image = selectedImage {
            profileImageView.image = image
            profileImageView.backgroundColor = Constants.Colors.lightGray
            profileImageView.tintColor = nil
        } else if let avatarName = selectedAvatarName {
            // Show the selected avatar
            if let avatarCase = DefaultImages.AvatarDefault.allCases.first(where: { $0.rawValue == avatarName }) {
                profileImageView.image = avatarCase.image(size: 80)
                profileImageView.backgroundColor = avatarCase.backgroundColor
                profileImageView.tintColor = .white
                profileImageView.contentMode = .scaleAspectFit
            }
        } else if let profilePicture = currentUser?.profilePicture {
            // Show existing profile picture
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image
                }
            }
        } else {
            // Default state
            profileImageView.image = UIImage(systemName: "person.circle.fill")
            profileImageView.backgroundColor = Constants.Colors.lightGray
            profileImageView.tintColor = Constants.Colors.primary
        }
    }
    
    private func presentPhotoLibraryPermissionAlert() {
        AlertPresenter.showActionSheet(
            title: "Photo Library Access",
            message: "Please allow access to your photo library in Settings to change your profile photo.",
            actions: [
                (title: "Settings", style: .default, handler: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
            ],
            from: self
        )
    }
    
    private func presentAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        if title == "Success" {
            AlertPresenter.showSuccess(title: title, message: message, from: self, completion: completion)
        } else {
            AlertPresenter.showError(title: title, message: message, from: self, completion: completion)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension EditProfileViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ensure touch.view is valid and is a UIView
        guard let view = touch.view as? UIView else {
            return false
        }
        
        // Only dismiss if tapping outside the avatar picker view
        if view.isDescendant(of: gestureRecognizer.view!) {
            return view == gestureRecognizer.view
        }
        return true
    }
}

// MARK: - UIImagePickerControllerDelegate
extension EditProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
            selectedAvatarName = nil // Clear avatar if photo is selected
        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
            selectedAvatarName = nil // Clear avatar if photo is selected
        }
        
        updateProfileImage()
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

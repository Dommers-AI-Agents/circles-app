import UIKit
import PhotosUI

class GroupConversationSettingsViewController: BaseViewController {
    
    // MARK: - Properties
    private var conversation: Conversation
    private var originalName: String?
    private var originalAvatar: String?
    private var selectedImageData: Data?
    
    // MARK: - UI Elements
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 50
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.isUserInteractionEnabled = true
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        imageView.addGestureRecognizer(tapGesture)
        
        return imageView
    }()
    
    private lazy var changeAvatarLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to change photo"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.primary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Group name"
        textField.borderStyle = .roundedRect
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.backgroundColor = UIColor.systemGray6
        textField.layer.cornerRadius = 8
        textField.delegate = self
        return textField
    }()
    
    private lazy var participantsLabel: UILabel = {
        let label = UILabel()
        label.text = "Participants"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var participantsTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ParticipantCell.self, forCellReuseIdentifier: "ParticipantCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AddParticipantCell")
        tableView.isScrollEnabled = false
        return tableView
    }()
    
    private lazy var deleteGroupButton: UIButton = {
        let button = UIButton.dangerButton(title: "Delete Group")
        button.addTarget(self, action: #selector(deleteGroupTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Initialization
    init(conversation: Conversation) {
        self.conversation = conversation
        self.originalName = conversation.name
        self.originalAvatar = conversation.avatar
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadConversationData()
    }
    
    override var showsLoadingIndicator: Bool { false }
    override var enablesPullToRefresh: Bool { false }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Group Settings"
        view.backgroundColor = .systemBackground
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(avatarImageView)
        contentView.addSubview(changeAvatarLabel)
        contentView.addSubview(nameTextField)
        contentView.addSubview(participantsLabel)
        contentView.addSubview(participantsTableView)
        contentView.addSubview(deleteGroupButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
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
            
            // Avatar image view
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            avatarImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 100),
            avatarImageView.heightAnchor.constraint(equalToConstant: 100),
            
            // Change avatar label
            changeAvatarLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            changeAvatarLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            // Name text field
            nameTextField.topAnchor.constraint(equalTo: changeAvatarLabel.bottomAnchor, constant: 32),
            nameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            nameTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Participants label
            participantsLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 32),
            participantsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            participantsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Participants table view
            participantsTableView.topAnchor.constraint(equalTo: participantsLabel.bottomAnchor, constant: 16),
            participantsTableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            participantsTableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Delete group button
            deleteGroupButton.topAnchor.constraint(equalTo: participantsTableView.bottomAnchor, constant: 32),
            deleteGroupButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            deleteGroupButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            deleteGroupButton.heightAnchor.constraint(equalToConstant: 50),
            deleteGroupButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        // Set table view height based on content
        let participantCount = conversation.participantDetails?.count ?? 0
        let tableHeight = CGFloat(participantCount * 60) // Estimated row height
        participantsTableView.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
    }
    
    private func loadConversationData() {
        // Set group name
        nameTextField.text = conversation.name
        
        // Load avatar
        if let avatar = conversation.avatar, !avatar.isEmpty {
            ImageService.shared.loadImage(from: avatar) { [weak self] image in
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                }
            }
        } else {
            // Set default group avatar
            avatarImageView.image = UIImage(systemName: "person.3.fill")
            avatarImageView.tintColor = Constants.Colors.lightGray
        }
        
        // Load participant details if not already loaded
        if conversation.participantDetails?.isEmpty != false {
            loadParticipantDetails()
        }
    }
    
    private func loadParticipantDetails() {
        print("🔍 GroupConversationSettings: Loading participant details for \(conversation.participants.count) participants")
        
        let participantIds = conversation.participants
        var participantDetails: [User] = []
        let group = DispatchGroup()
        
        for participantId in participantIds {
            group.enter()
            UserService.shared.fetchUserProfile(userId: participantId) { result in
                defer { group.leave() }
                
                switch result {
                case .success(let user):
                    participantDetails.append(user)
                case .failure(let error):
                    print("❌ Failed to load participant \(participantId): \(error)")
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            print("✅ Loaded \(participantDetails.count) participant details")
            // Update conversation with participant details
            if let currentConversation = self?.conversation {
                self?.conversation = Conversation(
                    id: currentConversation.id,
                    type: currentConversation.type,
                    participants: currentConversation.participants,
                    name: currentConversation.name,
                    avatar: currentConversation.avatar,
                    lastMessage: currentConversation.lastMessage,
                    lastMessageTime: currentConversation.lastMessageTime,
                    lastMessageSenderId: currentConversation.lastMessageSenderId,
                    unreadCounts: currentConversation.unreadCounts,
                    notificationSettings: currentConversation.notificationSettings,
                    createdAt: currentConversation.createdAt,
                    updatedAt: currentConversation.updatedAt,
                    createdBy: currentConversation.createdBy,
                    participantDetails: participantDetails
                )
            }
            
            // Update table view and constraints
            self?.participantsTableView.reloadData()
            self?.updateTableViewHeight()
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveTapped() {
        let newName = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNameChanged = newName != originalName
        var hasAvatarChanged = false
        
        // Check if avatar changed
        if selectedImageData != nil {
            hasAvatarChanged = true
        }
        
        // If nothing changed, just dismiss
        if !hasNameChanged && !hasAvatarChanged {
            dismiss(animated: true)
            return
        }
        
        // Show loading
        let loadingAlert = AlertPresenter.showLoading(message: "Updating group settings...", from: self)
        
        // Upload image if needed
        if let imageData = selectedImageData {
            uploadAvatarImage(imageData) { [weak self] avatarUrl in
                guard let self = self else { return }
                
                if avatarUrl == nil {
                    // Image upload failed, dismiss loading and show error
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self.showError("Failed to upload image. Please try again.")
                        }
                    }
                    return
                }
                
                self.updateConversation(name: newName, avatar: avatarUrl, loadingAlert: loadingAlert)
            }
        } else {
            updateConversation(name: newName, avatar: nil, loadingAlert: loadingAlert)
        }
    }
    
    @objc private func avatarTapped() {
        presentImagePicker()
    }
    
    @objc private func deleteGroupTapped() {
        let alert = UIAlertController(
            title: "Delete Group",
            message: "Are you sure you want to delete this group? This action cannot be undone and will remove the group for all participants.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteGroup()
        })
        
        present(alert, animated: true)
    }
    
    private func deleteGroup() {
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting group...", from: self)
        
        MessagingService.shared.deleteConversation(conversationId: conversation.id) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Post notification to update conversations list
                        NotificationCenter.default.post(
                            name: Notification.Name("ConversationDeleted"),
                            object: nil,
                            userInfo: ["conversationId": self?.conversation.id ?? ""]
                        )
                        
                        // Dismiss this view controller
                        self?.dismiss(animated: true) {
                            // Also dismiss the parent chat view if it exists
                            if let presentingVC = self?.presentingViewController as? UINavigationController {
                                presentingVC.popToRootViewController(animated: true)
                            }
                        }
                        
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
    
    // MARK: - Participant Management
    
    private func presentAddParticipantController() {
        // TODO: Implement participant selection controller
        // For now, show a simple alert
        showError("Add participant functionality coming soon!")
    }
    
    private func removeParticipant(_ participant: User) {
        let isCurrentUser = participant.id == AuthService.shared.getUserId()
        let title = isCurrentUser ? "Leave Group" : "Remove Participant"
        let message = isCurrentUser ? 
            "Are you sure you want to leave this group?" :
            "Are you sure you want to remove \(participant.displayName) from this group?"
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        let actionTitle = isCurrentUser ? "Leave" : "Remove"
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive) { [weak self] _ in
            self?.performRemoveParticipant(participant)
        })
        
        present(alert, animated: true)
    }
    
    private func performRemoveParticipant(_ participant: User) {
        let loadingAlert = AlertPresenter.showLoading(message: "Updating group...", from: self)
        
        MessagingService.shared.removeParticipant(
            conversationId: conversation.id,
            userId: participant.id
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Update local conversation data
                        var updatedParticipantDetails = self?.conversation.participantDetails ?? []
                        if let index = updatedParticipantDetails.firstIndex(where: { $0.id == participant.id }) {
                            updatedParticipantDetails.remove(at: index)
                        }
                        
                        // Update participants array as well  
                        var updatedParticipants = self?.conversation.participants ?? []
                        if let index = updatedParticipants.firstIndex(of: participant.id) {
                            updatedParticipants.remove(at: index)
                        }
                        
                        // Create updated conversation
                        if let currentConversation = self?.conversation {
                            self?.conversation = Conversation(
                                id: currentConversation.id,
                                type: currentConversation.type,
                                participants: updatedParticipants,
                                name: currentConversation.name,
                                avatar: currentConversation.avatar,
                                lastMessage: currentConversation.lastMessage,
                                lastMessageTime: currentConversation.lastMessageTime,
                                lastMessageSenderId: currentConversation.lastMessageSenderId,
                                unreadCounts: currentConversation.unreadCounts,
                                notificationSettings: currentConversation.notificationSettings,
                                createdAt: currentConversation.createdAt,
                                updatedAt: currentConversation.updatedAt,
                                createdBy: currentConversation.createdBy,
                                participantDetails: updatedParticipantDetails
                            )
                        }
                        
                        // Reload table view
                        self?.participantsTableView.reloadData()
                        
                        // Update constraints for new table height
                        self?.updateTableViewHeight()
                        
                        self?.showSuccess("Participant removed successfully")
                        
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
    
    private func updateTableViewHeight() {
        let participantCount = (conversation.participantDetails?.count ?? 0) + 1 // +1 for add button
        let tableHeight = CGFloat(participantCount * 60)
        
        // Remove existing height constraint and add new one
        participantsTableView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                constraint.isActive = false
            }
        }
        
        participantsTableView.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
    }
    
    // MARK: - Image Handling
    private func presentImagePicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func uploadAvatarImage(_ imageData: Data, completion: @escaping (String?) -> Void) {
        print("📤 Uploading avatar image, size: \(imageData.count / 1024)KB")
        
        // Convert image data to base64
        let base64String = imageData.base64EncodedString()
        
        let body: [String: Any] = [
            "image": base64String,
            "filename": "group-avatar.jpg"
        ]
        
        struct ImageUploadResponse: Decodable {
            let success: Bool
            let url: String
        }
        
        APIService.shared.request(
            endpoint: "upload/image",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<ImageUploadResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ Avatar image uploaded successfully: \(response.url)")
                    completion(response.url)
                case .failure(let error):
                    print("❌ Failed to upload avatar image: \(error)")
                    completion(nil)
                }
            }
        }
    }
    
    private func updateConversation(name: String?, avatar: String?, loadingAlert: UIAlertController) {
        MessagingManager.shared.updateConversation(
            conversationId: conversation.id,
            name: name,
            avatar: avatar
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let updatedConversation):
                        self?.conversation = updatedConversation
                        self?.showSuccess("Group settings updated")
                        
                        // Post notification to update other views
                        NotificationCenter.default.post(
                            name: Notification.Name("ConversationUpdated"),
                            object: nil,
                            userInfo: ["conversation": updatedConversation]
                        )
                        
                        // Dismiss after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self?.dismiss(animated: true)
                        }
                        
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
    
    // MARK: - Image Utilities
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        
        // If image is already small enough, return original
        if size.width <= maxSize && size.height <= maxSize {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let widthRatio = maxSize / size.width
        let heightRatio = maxSize / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
}

// MARK: - ParticipantCell
class ParticipantCell: UITableViewCell {
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .systemRed
        return button
    }()
    
    private var onRemove: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(removeButton)
        
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -12),
            
            emailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            emailLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -12),
            emailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with user: User, isCurrentUser: Bool, canRemove: Bool, onRemove: @escaping () -> Void) {
        nameLabel.text = user.displayName
        emailLabel.text = user.email
        self.onRemove = onRemove
        
        // Show "You" for current user
        if isCurrentUser {
            nameLabel.text = "\(user.displayName) (You)"
        }
        
        // Show/hide remove button based on permissions
        removeButton.isHidden = !canRemove
        
        // Load avatar image
        if let profilePictureUrl = user.profilePicture, !profilePictureUrl.isEmpty {
            ImageService.shared.loadImage(from: profilePictureUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                }
            }
        } else {
            // Default avatar
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .systemGray3
        }
    }
    
    @objc private func removeButtonTapped() {
        onRemove?()
    }
}

// MARK: - UITextField Delegate
extension GroupConversationSettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - UITableView DataSource & Delegate
extension GroupConversationSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Add 1 for the "Add Participant" cell
        return (conversation.participantDetails?.count ?? 0) + 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let participantCount = conversation.participantDetails?.count ?? 0
        
        if indexPath.row < participantCount {
            // Participant cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "ParticipantCell", for: indexPath) as! ParticipantCell
            
            if let participant = conversation.participantDetails?[indexPath.row] {
                let currentUserId = AuthService.shared.getUserId()
                let isCurrentUser = participant.id == currentUserId
                let canRemove = !isCurrentUser || participantCount > 2 // Can remove others or self if more than 2 people
                
                cell.configure(
                    with: participant,
                    isCurrentUser: isCurrentUser,
                    canRemove: canRemove,
                    onRemove: { [weak self] in
                        self?.removeParticipant(participant)
                    }
                )
            }
            
            return cell
        } else {
            // Add participant cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddParticipantCell", for: indexPath)
            cell.textLabel?.text = "Add Participant"
            cell.imageView?.image = UIImage(systemName: "plus.circle.fill")
            cell.imageView?.tintColor = Constants.Colors.primary
            cell.accessoryType = .none
            cell.selectionStyle = .default
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let participantCount = conversation.participantDetails?.count ?? 0
        
        if indexPath.row == participantCount {
            // Tapped "Add Participant" cell
            presentAddParticipantController()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - PHPickerViewController Delegate
extension GroupConversationSettingsViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            if let error = error {
                print("❌ Error loading image: \(error)")
                return
            }
            
            if let image = object as? UIImage {
                DispatchQueue.main.async {
                    // Resize image to reasonable size for group avatar
                    let maxSize: CGFloat = 400  // Reduced from 500
                    let resizedImage = self?.resizeImage(image, maxSize: maxSize) ?? image
                    
                    self?.avatarImageView.image = resizedImage
                    
                    // Convert to data for upload with lower quality for smaller file size
                    // Try different compression levels to stay under 750KB (which becomes ~1MB when base64 encoded)
                    var imageData: Data?
                    let maxSizeKB = 750  // 750KB max to stay under 1MB when base64 encoded
                    
                    for quality in [0.6, 0.4, 0.2, 0.1] {
                        if let data = resizedImage.jpegData(compressionQuality: quality) {
                            let sizeKB = data.count / 1024
                            if sizeKB <= maxSizeKB {
                                imageData = data
                                print("✅ Image compressed to \(sizeKB)KB with quality \(quality)")
                                break
                            }
                        }
                    }
                    
                    if let imageData = imageData {
                        self?.selectedImageData = imageData
                        print("✅ Image selected, size: \(imageData.count / 1024)KB")
                    } else {
                        print("❌ Failed to compress image to acceptable size")
                        self?.showError("Image is too large. Please choose a smaller image.")
                    }
                }
            }
        }
    }
}
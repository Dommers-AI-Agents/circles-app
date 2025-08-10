import UIKit

// MARK: - ActivityEngagementViewController
class ActivityEngagementViewController: BaseViewController {
    
    // MARK: - Properties
    private let activity: Activity
    private var reactions: [ReactionDetail] = []
    private var comments: [ActivityComment] = []
    private var selectedSegment = 0 // 0 = Reactions, 1 = Comments
    private var isPresentingAlert = false // Track alert presentation state
    private var isLoadingReactions = false // Prevent duplicate reaction loads
    private var isLoadingComments = false // Prevent duplicate comment loads
    
    // MARK: - UI Elements
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Reactions", "Comments"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .singleLine
        table.register(ReactionDetailCell.self, forCellReuseIdentifier: "ReactionDetailCell")
        table.register(CommentCell.self, forCellReuseIdentifier: "CommentCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No reactions yet"
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // Comment input for comments tab
    private let commentInputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.borderWidth = 0.5
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let commentTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "Write a comment..."
        field.font = UIFont.systemFont(ofSize: 14)
        field.borderStyle = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()
    
    private lazy var sendButton = UIButton.primaryButton(title: "Send")
    
    // MARK: - Initialization
    init(activity: Activity) {
        self.activity = activity
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Activity Engagement"
        
        // Add navigation buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        // Add subviews
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(commentInputContainer)
        
        commentInputContainer.addSubview(commentTextField)
        commentInputContainer.addSubview(sendButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Segmented control
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.medium),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Empty state
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Comment input container
            commentInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentInputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            commentInputContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Comment text field
            commentTextField.leadingAnchor.constraint(equalTo: commentInputContainer.leadingAnchor, constant: Constants.Spacing.medium),
            commentTextField.centerYAnchor.constraint(equalTo: commentInputContainer.centerYAnchor),
            commentTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -Constants.Spacing.small),
            
            // Send button
            sendButton.trailingAnchor.constraint(equalTo: commentInputContainer.trailingAnchor, constant: -Constants.Spacing.medium),
            sendButton.centerYAnchor.constraint(equalTo: commentInputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 60),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        // Adjust table view bottom constraint based on comment input visibility
        tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        
        // Add actions
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        sendButton.addTarget(self, action: #selector(sendCommentTapped), for: .touchUpInside)
    }
    
    // MARK: - BaseViewController Override
    override func loadData(completion: (() -> Void)? = nil) {
        if selectedSegment == 0 {
            loadReactions()
        } else {
            loadComments()
        }
        completion?()
    }
    
    // MARK: - Data Loading
    private func loadReactions() {
        // Prevent duplicate loads
        guard !isLoadingReactions else { return }
        
        isLoadingReactions = true
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/reactions/details",
            method: .get
        ) { [weak self] (result: Result<ReactionDetailsResponse, APIError>) in
            DispatchQueue.main.async {
                self?.isLoadingReactions = false
                switch result {
                case .success(let response):
                    self?.reactions = response.data
                    self?.updateUI()
                case .failure(let error):
                    self?.showErrorSafely("Failed to load reactions: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadComments() {
        // Prevent duplicate loads
        guard !isLoadingComments else { return }
        
        isLoadingComments = true
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/comments",
            method: .get
        ) { [weak self] (result: Result<ActivityCommentsResponse, APIError>) in
            DispatchQueue.main.async {
                self?.isLoadingComments = false
                switch result {
                case .success(let response):
                    self?.comments = response.data
                    self?.updateUI()
                case .failure(let error):
                    self?.showErrorSafely("Failed to load comments: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - UI Updates
    private func updateUI() {
        tableView.reloadData()
        
        let isEmpty = (selectedSegment == 0 && reactions.isEmpty) || 
                     (selectedSegment == 1 && comments.isEmpty)
        
        emptyStateLabel.isHidden = !isEmpty
        emptyStateLabel.text = selectedSegment == 0 ? "No reactions yet" : "No comments yet"
        
        // Show/hide comment input based on segment
        commentInputContainer.isHidden = selectedSegment == 0
        
        // Adjust table view bottom constraint
        if selectedSegment == 1 {
            tableView.contentInset.bottom = 60
        } else {
            tableView.contentInset.bottom = 0
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func segmentChanged() {
        selectedSegment = segmentedControl.selectedSegmentIndex
        loadData()
    }
    
    @objc private func sendCommentTapped() {
        guard let text = commentTextField.text, !text.isEmpty else { return }
        
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/comments",
            method: .post,
            body: ["text": text]
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.commentTextField.text = ""
                    self?.commentTextField.resignFirstResponder()
                    self?.loadComments()
                case .failure(let error):
                    self?.showErrorSafely("Failed to post comment: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Error Handling
    private func showErrorSafely(_ message: String) {
        // Prevent multiple alert presentations
        guard !isPresentingAlert else { return }
        
        isPresentingAlert = true
        showError(message)
        
        // Reset flag after a delay (typical alert presentation time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isPresentingAlert = false
        }
    }
}

// MARK: - UITableViewDataSource
extension ActivityEngagementViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return selectedSegment == 0 ? reactions.count : comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if selectedSegment == 0 {
            // Reaction cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "ReactionDetailCell", for: indexPath) as! ReactionDetailCell
            cell.configure(with: reactions[indexPath.row])
            return cell
        } else {
            // Comment cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "CommentCell", for: indexPath) as! CommentCell
            // Convert ActivityComment to format expected by CommentCell
            let comment = comments[indexPath.row]
            // Create a user object for the comment
            let commentUser = User(
                id: comment.userId,
                displayName: comment.userName,
                profilePicture: comment.userPhoto,
                bio: nil,
                location: nil,
                friends: nil,
                friendRequests: nil
            )
            let placeComment = PlaceComment(
                id: comment.id,
                placeId: "",
                userId: comment.userId,
                text: comment.text,
                likes: comment.isLikedByUser ? [AuthService.shared.getUserId() ?? ""] : [],
                likesCount: comment.likes.count,
                parentCommentId: comment.parentCommentId,
                replyCount: 0,
                createdAt: comment.createdAt,
                user: commentUser
            )
            cell.configure(with: placeComment)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension ActivityEngagementViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return selectedSegment == 0 ? 60 : UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if selectedSegment == 0 {
            // Navigate to user profile
            let reaction = reactions[indexPath.row]
            let profileVC = ProfileViewController()
            // Create a minimal User object for profile viewing
            let user = User(
                id: reaction.userId,
                displayName: reaction.displayName,
                profilePicture: reaction.profilePicture,
                bio: nil,
                location: nil,
                friends: nil,
                friendRequests: nil
            )
            profileVC.configureWith(user: user)
            navigationController?.pushViewController(profileVC, animated: true)
        }
    }
}

// MARK: - ReactionDetail Model
struct ReactionDetail: Codable {
    let userId: String
    let displayName: String
    let profilePicture: String?
    let emoji: String
    let timestamp: Date
}

// MARK: - ReactionDetailsResponse
struct ReactionDetailsResponse: Codable {
    let success: Bool
    let data: [ReactionDetail]
}

// MARK: - ReactionDetailCell
class ReactionDetailCell: UITableViewCell {
    
    // MARK: - UI Elements
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let reactionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(reactionLabel)
        contentView.addSubview(timestampLabel)
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 2),
            
            timestampLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            timestampLabel.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: -2),
            
            reactionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            reactionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    // MARK: - Configuration
    func configure(with reaction: ReactionDetail) {
        nameLabel.text = reaction.displayName
        reactionLabel.text = reaction.emoji
        
        // Format timestamp
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timestampLabel.text = formatter.localizedString(for: reaction.timestamp, relativeTo: Date())
        
        // Load avatar
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.primary
        
        if let profilePicture = reaction.profilePicture, !profilePicture.isEmpty {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                }
            }
        }
    }
}
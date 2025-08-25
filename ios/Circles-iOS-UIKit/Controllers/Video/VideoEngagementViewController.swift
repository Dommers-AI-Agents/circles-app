import UIKit

// MARK: - VideoEngagementViewController
class VideoEngagementViewController: BaseViewController {
    
    // MARK: - Properties
    private let video: PlaceVideo
    private var likes: [VideoLikeDetail] = []
    private var comments: [VideoEngagementComment] = []
    private var selectedSegment = 0 // 0 = Likes, 1 = Comments
    private var isPresentingAlert = false
    private var isLoadingLikes = false
    private var isLoadingComments = false
    
    // MARK: - UI Elements
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Likes", "Comments"])
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
        table.register(VideoLikeDetailCell.self, forCellReuseIdentifier: "VideoLikeDetailCell")
        table.register(VideoEngagementCommentCell.self, forCellReuseIdentifier: "VideoEngagementCommentCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No likes yet"
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
    init(video: PlaceVideo) {
        self.video = video
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
        setupSSE()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Clean up SSE connection if needed
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Moment Engagement"
        
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
    
    // MARK: - SSE Setup
    private func setupSSE() {
        // Listen for video engagement updates via SSE
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoEngagementUpdate(_:)),
            name: Notification.Name("VideoEngagementUpdate"),
            object: nil
        )
    }
    
    @objc private func handleVideoEngagementUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let videoId = userInfo["videoId"] as? String,
              videoId == video.id else { return }
        
        // Reload the appropriate data based on the update type
        if let updateType = userInfo["type"] as? String {
            DispatchQueue.main.async { [weak self] in
                switch updateType {
                case "like", "unlike":
                    if self?.selectedSegment == 0 {
                        self?.loadLikes()
                    }
                case "comment":
                    if self?.selectedSegment == 1 {
                        self?.loadComments()
                    }
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - BaseViewController Override
    override func loadData(completion: (() -> Void)? = nil) {
        if selectedSegment == 0 {
            loadLikes()
        } else {
            loadComments()
        }
        completion?()
    }
    
    // MARK: - Data Loading
    private func loadLikes() {
        guard !isLoadingLikes else { return }
        
        isLoadingLikes = true
        APIService.shared.request(
            endpoint: "videos/\(video.id)/likes",
            method: .get
        ) { [weak self] (result: Result<VideoLikesResponse, APIError>) in
            DispatchQueue.main.async {
                self?.isLoadingLikes = false
                switch result {
                case .success(let response):
                    self?.likes = response.data
                    self?.updateUI()
                case .failure(let error):
                    self?.showErrorSafely("Failed to load likes: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadComments() {
        guard !isLoadingComments else { return }
        
        isLoadingComments = true
        APIService.shared.request(
            endpoint: "videos/\(video.id)/comments",
            method: .get
        ) { [weak self] (result: Result<VideoEngagementCommentsResponse, APIError>) in
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
        
        let isEmpty = (selectedSegment == 0 && likes.isEmpty) || 
                     (selectedSegment == 1 && comments.isEmpty)
        
        emptyStateLabel.isHidden = !isEmpty
        emptyStateLabel.text = selectedSegment == 0 ? "No likes yet" : "No comments yet"
        
        // Show/hide comment input based on segment
        commentInputContainer.isHidden = selectedSegment == 0
        
        // Adjust table view bottom constraint
        if selectedSegment == 1 {
            tableView.contentInset.bottom = 60
        } else {
            tableView.contentInset.bottom = 0
        }
    }
    
    // MARK: - Public Methods
    func setSelectedSegment(_ index: Int) {
        selectedSegment = index
        segmentedControl.selectedSegmentIndex = index
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
            endpoint: "videos/\(video.id)/comments",
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
        guard !isPresentingAlert else { return }
        
        isPresentingAlert = true
        showError(message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isPresentingAlert = false
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDataSource
extension VideoEngagementViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return selectedSegment == 0 ? likes.count : comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if selectedSegment == 0 {
            // Like cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "VideoLikeDetailCell", for: indexPath) as! VideoLikeDetailCell
            cell.configure(with: likes[indexPath.row])
            return cell
        } else {
            // Comment cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "VideoEngagementCommentCell", for: indexPath) as! VideoEngagementCommentCell
            cell.configure(with: comments[indexPath.row])
            cell.delegate = self
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension VideoEngagementViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return selectedSegment == 0 ? 60 : UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if selectedSegment == 0 {
            // Navigate to user profile
            let like = likes[indexPath.row]
            let profileVC = ProfileViewController()
            let user = User(
                id: like.userId,
                displayName: like.displayName,
                profilePicture: like.profilePicture,
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

// MARK: - VideoEngagementCommentCellDelegate
extension VideoEngagementViewController: VideoEngagementCommentCellDelegate {
    func videoEngagementCommentCellDidTapLike(_ cell: VideoEngagementCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        // Toggle like state
        let endpoint = "videos/\(video.id)/comments/\(comment.id)/like"
        let method: RequestMethod = comment.isLikedByUser ? .delete : .post
        
        APIService.shared.request(
            endpoint: endpoint,
            method: method
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.loadComments()
                case .failure(let error):
                    self?.showErrorSafely("Failed to update like: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func videoEngagementCommentCellDidTapReply(_ cell: VideoEngagementCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        // Convert VideoEngagementComment to VideoComment
        let videoComment = VideoComment(
            id: comment.id,
            videoId: comment.videoId,
            userId: comment.userId,
            text: comment.text,
            parentCommentId: comment.parentCommentId,
            createdAt: comment.createdAt,
            updatedAt: comment.createdAt, // Use createdAt since we don't have updatedAt
            editedAt: nil,
            deletedAt: nil,
            replyCount: comment.replyCount,
            likes: comment.likes,
            likesCount: comment.likes.count,
            user: nil // User info not fully available in VideoEngagementComment
        )
        
        // Navigate to replies view controller
        let repliesVC = VideoCommentRepliesViewController(video: video, parentComment: videoComment)
        navigationController?.pushViewController(repliesVC, animated: true)
    }
    
    func videoEngagementCommentCellDidTapProfile(_ cell: VideoEngagementCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        let profileVC = ProfileViewController()
        let user = User(
            id: comment.userId,
            displayName: comment.userName,
            profilePicture: comment.userPhoto,
            bio: nil,
            location: nil,
            friends: nil,
            friendRequests: nil
        )
        profileVC.configureWith(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - Models
struct VideoLikeDetail: Codable {
    let userId: String
    let displayName: String
    let profilePicture: String?
    let timestamp: Date
}

struct VideoLikesResponse: Codable {
    let success: Bool
    let data: [VideoLikeDetail]
}

struct VideoEngagementComment: Codable {
    let id: String
    let videoId: String
    let userId: String
    let userName: String
    let userPhoto: String?
    let text: String
    let likes: [String]
    let isLikedByUser: Bool
    let parentCommentId: String?
    let replyCount: Int
    let createdAt: Date
}

struct VideoEngagementCommentsResponse: Codable {
    let success: Bool
    let data: [VideoEngagementComment]
}

// MARK: - VideoLikeDetailCell
class VideoLikeDetailCell: UITableViewCell {
    
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
    
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let heartIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "heart.fill")
        imageView.tintColor = .systemRed
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timestampLabel)
        contentView.addSubview(heartIcon)
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 2),
            
            timestampLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            timestampLabel.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: -2),
            
            heartIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            heartIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            heartIcon.widthAnchor.constraint(equalToConstant: 20),
            heartIcon.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with like: VideoLikeDetail) {
        nameLabel.text = like.displayName
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timestampLabel.text = formatter.localizedString(for: like.timestamp, relativeTo: Date())
        
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.primary
        
        if let profilePicture = like.profilePicture, !profilePicture.isEmpty {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                }
            }
        }
    }
}

// MARK: - VideoEngagementCommentCell
protocol VideoEngagementCommentCellDelegate: AnyObject {
    func videoEngagementCommentCellDidTapLike(_ cell: VideoEngagementCommentCell)
    func videoEngagementCommentCellDidTapReply(_ cell: VideoEngagementCommentCell)
    func videoEngagementCommentCellDidTapProfile(_ cell: VideoEngagementCommentCell)
}

class VideoEngagementCommentCell: UITableViewCell {
    
    weak var delegate: VideoEngagementCommentCellDelegate?
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 18
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let commentLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
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
    
    private lazy var likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var replyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Reply", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)
        return button
    }()
    
    private let likesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(commentLabel)
        contentView.addSubview(timestampLabel)
        contentView.addSubview(likeButton)
        contentView.addSubview(replyButton)
        contentView.addSubview(likesLabel)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        avatarImageView.addGestureRecognizer(tapGesture)
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.medium),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.medium),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Constants.Spacing.small),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.medium),
            
            commentLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            commentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            commentLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            timestampLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            timestampLabel.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: 8),
            
            likeButton.leadingAnchor.constraint(equalTo: timestampLabel.trailingAnchor, constant: Constants.Spacing.medium),
            likeButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            likeButton.widthAnchor.constraint(equalToConstant: 30),
            likeButton.heightAnchor.constraint(equalToConstant: 30),
            
            likesLabel.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor, constant: 4),
            likesLabel.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            
            replyButton.leadingAnchor.constraint(equalTo: likesLabel.trailingAnchor, constant: Constants.Spacing.medium),
            replyButton.centerYAnchor.constraint(equalTo: timestampLabel.centerYAnchor),
            replyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.medium)
        ])
    }
    
    func configure(with comment: VideoEngagementComment) {
        nameLabel.text = comment.userName
        commentLabel.text = comment.text
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timestampLabel.text = formatter.localizedString(for: comment.createdAt, relativeTo: Date())
        
        // Update like button
        let isLiked = comment.isLikedByUser
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : Constants.Colors.secondaryLabel
        
        // Update likes count
        if comment.likes.count > 0 {
            likesLabel.text = "\(comment.likes.count)"
            likesLabel.isHidden = false
        } else {
            likesLabel.isHidden = true
        }
        
        // Load avatar
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = Constants.Colors.primary
        
        if let profilePicture = comment.userPhoto, !profilePicture.isEmpty {
            ImageService.shared.loadImage(from: profilePicture) { [weak self] image in
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                }
            }
        }
    }
    
    @objc private func likeTapped() {
        delegate?.videoEngagementCommentCellDidTapLike(self)
    }
    
    @objc private func replyTapped() {
        delegate?.videoEngagementCommentCellDidTapReply(self)
    }
    
    @objc private func profileTapped() {
        delegate?.videoEngagementCommentCellDidTapProfile(self)
    }
}
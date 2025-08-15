import UIKit

// MARK: - VideoCommentsViewControllerDelegate
protocol VideoCommentsViewControllerDelegate: AnyObject {
    func videoCommentsDidUpdate(_ controller: VideoCommentsViewController, newCommentCount: Int)
}

// MARK: - Comment Model
struct VideoComment: Codable {
    let id: String
    let videoId: String
    let userId: String
    let text: String
    let parentCommentId: String?
    let createdAt: Date
    let updatedAt: Date
    let editedAt: Date?
    let deletedAt: Date?
    let replyCount: Int?
    let likes: [String]? // Array of user IDs who liked the comment
    let likesCount: Int? // Count for efficient display
    var user: User?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case videoId
        case userId
        case text
        case parentCommentId
        case createdAt
        case updatedAt
        case editedAt
        case deletedAt
        case replyCount
        case likes
        case likesCount
        case user
    }
    
    // Helper properties
    var isLikedByCurrentUser: Bool {
        guard let currentUserId = AuthService.shared.getUserId(),
              let likes = likes else { return false }
        return likes.contains(currentUserId)
    }
    
    var displayLikesCount: Int {
        return likesCount ?? likes?.count ?? 0
    }
    
    var displayReplyCount: Int {
        return replyCount ?? 0
    }
    
    var hasReplies: Bool {
        return displayReplyCount > 0
    }
}

// MARK: - Response Types
struct VideoCommentsResponse: Codable {
    let success: Bool
    let data: [VideoComment]
    let hasMore: Bool
}

struct VideoCommentResponse: Codable {
    let success: Bool
    let data: VideoComment
}

struct VideoLikeCommentResponse: Codable {
    let success: Bool
    let liked: Bool
    let likesCount: Int
}

// MARK: - VideoCommentsViewController
class VideoCommentsViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: VideoCommentsViewControllerDelegate?
    private let video: PlaceVideo
    private var comments: [VideoComment] = []
    private var isLoadingMore = false
    private var hasMoreComments = true
    
    // MARK: - UI Elements
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .grouped)
        tv.backgroundColor = Constants.Colors.background
        tv.separatorStyle = .none
        tv.keyboardDismissMode = .interactive
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    private let commentInputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let commentTextView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.textColor = Constants.Colors.label
        tv.backgroundColor = Constants.Colors.secondaryBackground
        tv.layer.cornerRadius = 20
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        tv.isScrollEnabled = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Add a comment..."
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(sendCommentTapped), for: .touchUpInside)
        return button
    }()
    
    private var commentInputBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Initialization
    init(video: PlaceVideo) {
        self.video = video
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "Be the first to comment!" }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupKeyboardObservers()
        loadData()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Comments"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(commentInputContainer)
        commentInputContainer.addSubview(commentTextView)
        commentInputContainer.addSubview(placeholderLabel)
        commentInputContainer.addSubview(sendButton)
        
        // Setup constraints
        let inputBottomConstraint = commentInputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        self.commentInputBottomConstraint = inputBottomConstraint
        
        NSLayoutConstraint.activate([
            // Table view
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: commentInputContainer.topAnchor),
            
            // Comment input container
            commentInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBottomConstraint,
            commentInputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            // Comment text view
            commentTextView.leadingAnchor.constraint(equalTo: commentInputContainer.leadingAnchor, constant: 16),
            commentTextView.topAnchor.constraint(equalTo: commentInputContainer.topAnchor, constant: 10),
            commentTextView.bottomAnchor.constraint(equalTo: commentInputContainer.bottomAnchor, constant: -10),
            commentTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            commentTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 100),
            
            // Placeholder
            placeholderLabel.leadingAnchor.constraint(equalTo: commentTextView.leadingAnchor, constant: 17),
            placeholderLabel.centerYAnchor.constraint(equalTo: commentTextView.centerYAnchor),
            
            // Send button
            sendButton.centerYAnchor.constraint(equalTo: commentTextView.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: commentInputContainer.trailingAnchor, constant: -16),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Add separator
        let separator = UIView()
        separator.backgroundColor = Constants.Colors.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        commentInputContainer.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: commentInputContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: commentInputContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: commentInputContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        
        // Setup text view delegate
        commentTextView.delegate = self
        commentTextView.addDoneButtonOnKeyboard()
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(VideoCommentCell.self, forCellReuseIdentifier: "VideoCommentCell")
        
        if enablesPullToRefresh {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
            tableView.refreshControl = refreshControl
        }
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        let endpoint = "videos/\(video.id)/comments"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideoCommentsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.comments = response.data
                    self.hasMoreComments = response.hasMore
                    self.tableView.reloadData()
                    self.updateEmptyState()
                    
                case .failure(let error):
                    self.showError(error)
                }
                
                self.tableView.refreshControl?.endRefreshing()
                completion?()
            }
        }
    }
    
    @objc override func refreshData() {
        comments.removeAll()
        hasMoreComments = true
        loadData()
    }
    
    private func loadMoreComments() {
        guard !isLoadingMore && hasMoreComments else { return }
        
        isLoadingMore = true
        let offset = comments.count
        let endpoint = "videos/\(video.id)/comments?offset=\(offset)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideoCommentsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                
                switch result {
                case .success(let response):
                    self.comments.append(contentsOf: response.data)
                    self.hasMoreComments = response.hasMore
                    self.tableView.reloadData()
                    
                case .failure(let error):
                    print("Failed to load more comments: \(error)")
                }
            }
        }
    }
    
    private func updateEmptyState() {
        if comments.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = emptyStateMessage
            emptyLabel.textColor = Constants.Colors.secondaryLabel
            emptyLabel.textAlignment = .center
            emptyLabel.font = UIFont.systemFont(ofSize: 16)
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func sendCommentTapped() {
        guard let text = commentTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        // Disable send button
        sendButton.isEnabled = false
        
        let endpoint = "videos/\(video.id)/comments"
        let body = ["text": text]
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body
        ) { [weak self] (result: Result<VideoCommentResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    // Add new comment to the top
                    self.comments.insert(response.data, at: 0)
                    self.tableView.reloadData()
                    self.updateEmptyState()
                    
                    // Clear input
                    self.commentTextView.text = ""
                    self.textViewDidChange(self.commentTextView)
                    self.commentTextView.resignFirstResponder()
                    
                    // Notify delegate of new comment count
                    self.delegate?.videoCommentsDidUpdate(self, newCommentCount: self.comments.count)
                    
                    // Show success
                    self.showSuccess("Comment posted!")
                    
                case .failure(let error):
                    self.showError(error)
                    self.sendButton.isEnabled = true
                }
            }
        }
    }
    
    private func deleteComment(_ comment: VideoComment, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Comment",
            message: "Are you sure you want to delete this comment?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDeleteComment(comment, at: indexPath)
        })
        
        present(alert, animated: true)
    }
    
    private func performDeleteComment(_ comment: VideoComment, at indexPath: IndexPath) {
        let endpoint = "videos/\(video.id)/comments/\(comment.id)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .delete
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success:
                    self.comments.remove(at: indexPath.row)
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                    self.updateEmptyState()
                    
                    // Notify delegate of new comment count
                    self.delegate?.videoCommentsDidUpdate(self, newCommentCount: self.comments.count)
                    
                    self.showSuccess("Comment deleted")
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Keyboard Handling
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height - view.safeAreaInsets.bottom
        commentInputBottomConstraint?.constant = -keyboardHeight
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        commentInputBottomConstraint?.constant = 0
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Like/Reply Helpers
    private func likeVideoComment(comment: VideoComment, at indexPath: IndexPath) {
        let endpoint = "videos/\(video.id)/comments/\(comment.id)/like"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post
        ) { [weak self] (result: Result<VideoLikeCommentResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    // Update the comment in our array with new like status
                    // Since we can't modify the struct directly, we'll reload the cell
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    
                case .failure(let error):
                    print("Failed to like comment: \(error)")
                    self.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
    
    private func presentReplyInterface(for comment: VideoComment) {
        let alert = UIAlertController(
            title: "Reply to \(comment.user?.displayName ?? "Unknown")",
            message: nil,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Write a reply..."
            textField.autocapitalizationType = .sentences
        }
        
        let sendAction = UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            guard let replyText = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !replyText.isEmpty else { return }
            
            self?.sendReply(text: replyText, to: comment)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(sendAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func sendReply(text: String, to comment: VideoComment) {
        let endpoint = "videos/\(video.id)/comments/\(comment.id)/replies"
        let body = ["text": text]
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body
        ) { [weak self] (result: Result<VideoCommentResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.showSuccess("Reply sent successfully")
                    // Show the replies view controller
                    self.showReplies(for: comment)
                    // Reload data to show updated reply count
                    self.loadData(completion: nil)
                    
                case .failure(let error):
                    print("Failed to send reply: \(error)")
                    self.showError("Failed to send reply. Please try again.")
                }
            }
        }
    }
    
    private func showReplies(for comment: VideoComment) {
        let repliesVC = VideoCommentRepliesViewController(video: video, parentComment: comment)
        let navController = UINavigationController(rootViewController: repliesVC)
        present(navController, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension VideoCommentsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoCommentCell", for: indexPath) as! VideoCommentCell
        let comment = comments[indexPath.row]
        cell.configure(with: comment)
        cell.delegate = self
        return cell
    }
}

// MARK: - UITableViewDelegate
extension VideoCommentsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let comment = comments[indexPath.row]
        
        // If comment has replies, show the replies
        if comment.hasReplies {
            showReplies(for: comment)
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height
        
        if offsetY > contentHeight - height * 2 {
            loadMoreComments()
        }
    }
}

// MARK: - UITextViewDelegate
extension VideoCommentsViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        placeholderLabel.isHidden = hasText
        sendButton.isEnabled = hasText
    }
}

// MARK: - VideoCommentCellDelegate
extension VideoCommentsViewController: VideoCommentCellDelegate {
    func videoCommentCellDidTapDelete(_ cell: VideoCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        // Only allow deleting own comments
        guard comment.userId == AuthService.shared.getUserId() else { return }
        
        deleteComment(comment, at: indexPath)
    }
    
    func videoCommentCellDidTapReply(_ cell: VideoCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        // Present reply interface
        presentReplyInterface(for: comment)
    }
    
    func videoCommentCellDidTapLike(_ cell: VideoCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let comment = comments[indexPath.row]
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Call API to toggle like
        likeVideoComment(comment: comment, at: indexPath)
    }
}

// MARK: - VideoCommentCell
protocol VideoCommentCellDelegate: AnyObject {
    func videoCommentCellDidTapDelete(_ cell: VideoCommentCell)
    func videoCommentCellDidTapReply(_ cell: VideoCommentCell)
    func videoCommentCellDidTapLike(_ cell: VideoCommentCell)
}

class VideoCommentCell: UITableViewCell {
    
    weak var delegate: VideoCommentCellDelegate?
    private var comment: VideoComment?
    
    // UI Elements
    private let profileImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 20
        iv.backgroundColor = Constants.Colors.secondaryBackground
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
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
    
    private lazy var moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Like button
    private lazy var likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Like count label
    private let likeCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Reply button
    private lazy var replyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Reply count label
    private let replyCountLabel: UILabel = {
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
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(commentLabel)
        contentView.addSubview(moreButton)
        contentView.addSubview(likeButton)
        contentView.addSubview(likeCountLabel)
        contentView.addSubview(replyButton)
        contentView.addSubview(replyCountLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            timeLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            moreButton.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),
            
            commentLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            commentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            commentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Like button and count at bottom left (after avatar)
            likeButton.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            likeButton.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: 8),
            likeButton.widthAnchor.constraint(equalToConstant: 20),
            likeButton.heightAnchor.constraint(equalToConstant: 20),
            likeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            
            likeCountLabel.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor, constant: 4),
            likeCountLabel.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            
            // Reply button and count to the right of like
            replyButton.leadingAnchor.constraint(equalTo: likeCountLabel.trailingAnchor, constant: 16),
            replyButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            replyButton.widthAnchor.constraint(equalToConstant: 20),
            replyButton.heightAnchor.constraint(equalToConstant: 20),
            
            replyCountLabel.leadingAnchor.constraint(equalTo: replyButton.trailingAnchor, constant: 4),
            replyCountLabel.centerYAnchor.constraint(equalTo: replyButton.centerYAnchor)
        ])
    }
    
    func configure(with comment: VideoComment) {
        self.comment = comment
        
        nameLabel.text = comment.user?.displayName ?? "Unknown"
        commentLabel.text = comment.text
        
        // Format time
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.text = formatter.localizedString(for: comment.createdAt, relativeTo: Date())
        
        // Load profile image
        if let urlString = comment.user?.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                self?.profileImageView.image = image
            }
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
        }
        
        // Show/hide more button based on ownership
        moreButton.isHidden = comment.userId != AuthService.shared.getUserId()
        
        // Configure like button
        let isLiked = comment.isLikedByCurrentUser
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : Constants.Colors.secondaryLabel
        
        // Configure like count
        let likesCount = comment.displayLikesCount
        likeCountLabel.text = likesCount > 0 ? "\(likesCount)" : ""
        
        // Configure reply count
        let replyCount = comment.displayReplyCount
        replyCountLabel.text = replyCount > 0 ? "\(replyCount)" : ""
    }
    
    @objc private func moreButtonTapped() {
        delegate?.videoCommentCellDidTapDelete(self)
    }
    
    @objc private func likeButtonTapped() {
        delegate?.videoCommentCellDidTapLike(self)
    }
    
    @objc private func replyButtonTapped() {
        delegate?.videoCommentCellDidTapReply(self)
    }
}
import UIKit

class PlaceCommentsViewController: BaseViewController {
    
    // MARK: - Properties
    private let place: Place
    private var comments: [PlaceComment] = []
    var onCommentsUpdated: ((Int) -> Void)?
    
    // MARK: - Configuration
    override var enablesPullToRefresh: Bool { true }
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        table.keyboardDismissMode = .interactive
        return table
    }()
    
    private let commentInputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let commentTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Add a comment..."
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        return button
    }()
    
    private var commentInputBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Init
    init(place: Place) {
        self.place = place
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupKeyboardObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Comments"
        
        // Navigation items
        addNavigationBarButton(image: "xmark", position: .left, action: #selector(closeTapped))
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(commentInputContainer)
        commentInputContainer.addSubview(commentTextField)
        commentInputContainer.addSubview(sendButton)
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CommentCell.self, forCellReuseIdentifier: "CommentCell")
        
        // Configure text field
        commentTextField.delegate = self
        commentTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        sendButton.addTarget(self, action: #selector(sendComment), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        commentInputBottomConstraint = commentInputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            // Table view
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: commentInputContainer.topAnchor),
            
            // Comment input container
            commentInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentInputContainer.heightAnchor.constraint(equalToConstant: 60),
            commentInputBottomConstraint!,
            
            // Comment text field
            commentTextField.leadingAnchor.constraint(equalTo: commentInputContainer.leadingAnchor, constant: 16),
            commentTextField.centerYAnchor.constraint(equalTo: commentInputContainer.centerYAnchor),
            commentTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            
            // Send button
            sendButton.trailingAnchor.constraint(equalTo: commentInputContainer.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: commentInputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30)
        ])
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
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }
    
    @objc private func textFieldDidChange() {
        sendButton.isEnabled = !(commentTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    @objc private func sendComment() {
        guard let text = commentTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        
        sendButton.isEnabled = false
        commentTextField.isEnabled = false
        
        PlaceService.shared.addPlaceComment(placeId: place.id, text: text) { [weak self] result in
            DispatchQueue.main.async {
                self?.sendButton.isEnabled = true
                self?.commentTextField.isEnabled = true
                
                switch result {
                case .success(let comment):
                    self?.commentTextField.text = ""
                    self?.sendButton.isEnabled = false
                    self?.comments.insert(comment, at: 0)
                    self?.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                    self?.onCommentsUpdated?(self?.comments.count ?? 0)
                case .failure(let error):
                    print("Failed to add comment: \(error)")
                    self?.showError("Failed to add comment. Please try again.")
                }
            }
        }
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        commentInputBottomConstraint?.constant = -keyboardFrame.height + view.safeAreaInsets.bottom
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        commentInputBottomConstraint?.constant = 0
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Data
    override func loadData(completion: (() -> Void)?) {
        PlaceService.shared.getPlaceComments(placeId: place.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let comments):
                    self?.comments = comments
                    self?.tableView.reloadData()
                    self?.onCommentsUpdated?(comments.count)
                case .failure(let error):
                    print("Failed to fetch comments: \(error)")
                }
                completion?()
            }
        }
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension PlaceCommentsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CommentCell", for: indexPath) as! CommentCell
        let comment = comments[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let canDelete = comment.userId == currentUserId || place.addedBy == currentUserId
        cell.configure(with: comment, canDelete: canDelete)
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let comment = comments[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // User can delete if they are the comment author or the place owner
        return comment.userId == currentUserId || place.addedBy == currentUserId
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let comment = comments[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only show delete if user can delete
        guard comment.userId == currentUserId || place.addedBy == currentUserId else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteComment(at: indexPath, completionHandler: completionHandler)
        }
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let comment = comments[indexPath.row]
        
        // If comment has replies, show the replies
        if comment.hasReplies {
            showReplies(for: comment)
        }
    }
    
    private func deleteComment(at indexPath: IndexPath, completionHandler: @escaping (Bool) -> Void) {
        let comment = comments[indexPath.row]
        
        PlaceService.shared.deletePlaceComment(placeId: place.id, commentId: comment.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove comment from array and table
                    self?.comments.remove(at: indexPath.row)
                    self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                    self?.onCommentsUpdated?(self?.comments.count ?? 0)
                    completionHandler(true)
                case .failure(let error):
                    print("Failed to delete comment: \(error)")
                    self?.showError("Failed to delete comment. Please try again.")
                    completionHandler(false)
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension PlaceCommentsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if sendButton.isEnabled {
            sendComment()
        }
        return true
    }
}

// MARK: - CommentCell
class CommentCell: UITableViewCell {
    
    // Delete button for comment owners
    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    // Like button
    private let likeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
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
    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
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
    
    weak var delegate: CommentCellDelegate?
    private var comment: PlaceComment?
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = Constants.Colors.secondaryLabel
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
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        backgroundColor = Constants.Colors.background
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(avatarImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(timeLabel)
        containerView.addSubview(commentLabel)
        containerView.addSubview(moreButton)
        containerView.addSubview(likeButton)
        containerView.addSubview(likeCountLabel)
        containerView.addSubview(replyButton)
        containerView.addSubview(replyCountLabel)
        
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
        likeButton.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            avatarImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            avatarImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            
            moreButton.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            moreButton.widthAnchor.constraint(equalToConstant: 24),
            moreButton.heightAnchor.constraint(equalToConstant: 24),
            
            commentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            commentLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            commentLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            // Like button and count at bottom right
            likeButton.topAnchor.constraint(equalTo: commentLabel.bottomAnchor, constant: 8),
            likeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            likeButton.widthAnchor.constraint(equalToConstant: 20),
            likeButton.heightAnchor.constraint(equalToConstant: 20),
            likeButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            
            likeCountLabel.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            likeCountLabel.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -4),
            
            // Reply button and count to the left of like button
            replyButton.centerYAnchor.constraint(equalTo: likeButton.centerYAnchor),
            replyButton.trailingAnchor.constraint(equalTo: likeCountLabel.leadingAnchor, constant: -16),
            replyButton.widthAnchor.constraint(equalToConstant: 20),
            replyButton.heightAnchor.constraint(equalToConstant: 20),
            
            replyCountLabel.centerYAnchor.constraint(equalTo: replyButton.centerYAnchor),
            replyCountLabel.trailingAnchor.constraint(equalTo: replyButton.leadingAnchor, constant: -4)
        ])
    }
    
    func configure(with comment: PlaceComment, canDelete: Bool = false) {
        self.comment = comment
        nameLabel.text = comment.user?.displayName ?? "Unknown User"
        commentLabel.text = comment.text
        
        // Format time
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        timeLabel.text = formatter.localizedString(for: comment.createdAt, relativeTo: Date())
        
        // Load avatar if available
        if let urlString = comment.user?.profilePicture, let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.avatarImageView.image = image
                    }
                }
            }.resume()
        }
        
        // Show more button if user can delete
        moreButton.isHidden = !canDelete
        
        // Configure like button
        let isLiked = comment.isLikedByCurrentUser
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart"), for: .normal)
        likeButton.tintColor = isLiked ? .systemRed : Constants.Colors.secondaryLabel
        
        // Configure like count
        let likesCount = comment.displayLikesCount
        likeCountLabel.text = likesCount > 0 ? "\(likesCount)" : ""
        
        // Hide reply button and count for comments that are already replies
        let isReply = comment.isReply
        replyButton.isHidden = isReply
        replyCountLabel.isHidden = isReply
        
        // Configure reply count (only for top-level comments)
        if !isReply {
            let replyCount = comment.displayReplyCount
            replyCountLabel.text = replyCount > 0 ? "\(replyCount)" : ""
        }
    }
    
    @objc private func moreButtonTapped() {
        guard let comment = comment else { return }
        delegate?.commentCell(self, didTapMoreButton: comment)
    }
    
    @objc private func likeButtonTapped() {
        guard let comment = comment else { return }
        delegate?.commentCell(self, didTapLikeButton: comment)
    }
    
    @objc private func replyButtonTapped() {
        guard let comment = comment else { return }
        delegate?.commentCell(self, didTapReplyButton: comment)
    }
}

// MARK: - CommentCellDelegate
protocol CommentCellDelegate: AnyObject {
    func commentCell(_ cell: CommentCell, didTapMoreButton comment: PlaceComment)
    func commentCell(_ cell: CommentCell, didTapLikeButton comment: PlaceComment)
    func commentCell(_ cell: CommentCell, didTapReplyButton comment: PlaceComment)
}

// MARK: - CommentCellDelegate
extension PlaceCommentsViewController: CommentCellDelegate {
    func commentCell(_ cell: CommentCell, didTapMoreButton comment: PlaceComment) {
        let deleteAction: (title: String, style: UIAlertAction.Style, handler: () -> Void) = (
            title: "Delete Comment",
            style: .destructive,
            handler: { [weak self] in
                guard let indexPath = self?.tableView.indexPath(for: cell) else { return }
                self?.deleteComment(at: indexPath) { _ in }
            }
        )
        
        AlertPresenter.showActionSheet(
            actions: [deleteAction],
            from: self,
            sourceView: cell,
            sourceRect: cell.bounds
        )
    }
    
    func commentCell(_ cell: CommentCell, didTapLikeButton comment: PlaceComment) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Call API to toggle like
        PlaceService.shared.likeComment(placeId: place.id, commentId: comment.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (liked, likesCount)):
                    // Find the comment in our array and update it
                    if let index = self?.comments.firstIndex(where: { $0.id == comment.id }) {
                        // Update the comment in our array (we need to create a new comment with updated values)
                        // Since PlaceComment is a struct, we can't modify it directly
                        // So we'll just refresh the table view cell
                        self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    }
                    
                case .failure(let error):
                    print("Failed to like comment: \(error)")
                    self?.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
    
    func commentCell(_ cell: CommentCell, didTapReplyButton comment: PlaceComment) {
        // Present reply interface
        presentReplyInterface(for: comment)
    }
    
    private func presentReplyInterface(for comment: PlaceComment) {
        let alert = UIAlertController(title: "Reply to \(comment.displayAuthorName)", message: nil, preferredStyle: .alert)
        
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
    
    private func sendReply(text: String, to comment: PlaceComment) {
        PlaceService.shared.addPlaceCommentReply(placeId: place.id, commentId: comment.id, text: text) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let reply):
                    self?.showSuccess("Reply sent successfully")
                    // Reload data to show updated reply count
                    self?.loadData(completion: nil)
                case .failure(let error):
                    print("Failed to send reply: \(error)")
                    self?.showError("Failed to send reply. Please try again.")
                }
            }
        }
    }
    
    private func showReplies(for comment: PlaceComment) {
        let repliesVC = PlaceCommentRepliesViewController(place: place, parentComment: comment)
        let navController = UINavigationController(rootViewController: repliesVC)
        present(navController, animated: true)
    }
    
    // Removed showAlert - using inherited showError from BaseViewController
}
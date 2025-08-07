import UIKit

class PlaceCommentRepliesViewController: BaseViewController {
    
    // MARK: - Properties
    private let place: Place
    private let parentComment: PlaceComment
    private var replies: [PlaceComment] = []
    
    // MARK: - Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No replies yet" }
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
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
        textField.placeholder = "Add a reply..."
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
    init(place: Place, parentComment: PlaceComment) {
        self.place = place
        self.parentComment = parentComment
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
        title = "Replies"
        
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
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 30
        
        // Configure text field
        commentTextField.delegate = self
        commentTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        sendButton.addTarget(self, action: #selector(sendReply), for: .touchUpInside)
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
    
    @objc private func sendReply() {
        guard let text = commentTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        
        sendButton.isEnabled = false
        commentTextField.isEnabled = false
        
        PlaceService.shared.addPlaceCommentReply(placeId: place.id, commentId: parentComment.id, text: text) { [weak self] result in
            DispatchQueue.main.async {
                self?.sendButton.isEnabled = true
                self?.commentTextField.isEnabled = true
                
                switch result {
                case .success(let reply):
                    self?.commentTextField.text = ""
                    self?.sendButton.isEnabled = false
                    self?.replies.insert(reply, at: 0)
                    self?.tableView.insertRows(at: [IndexPath(row: 0, section: 1)], with: .automatic)
                case .failure(let error):
                    print("Failed to add reply: \(error)")
                    self?.showError("Failed to add reply. Please try again.")
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
        PlaceService.shared.getPlaceCommentReplies(placeId: place.id, commentId: parentComment.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let replies):
                    print("📝 PlaceCommentRepliesViewController: Received \(replies.count) replies")
                    for (index, reply) in replies.enumerated() {
                        print("  Reply \(index): id=\(reply.id), text=\(reply.text), userId=\(reply.userId)")
                    }
                    self?.replies = replies
                    self?.tableView.reloadData()
                    
                    // Explicitly handle empty state
                    if replies.isEmpty {
                        self?.showEmptyState()
                    } else {
                        self?.hideEmptyState()
                    }
                case .failure(let error):
                    print("❌ PlaceCommentRepliesViewController: Failed to fetch replies: \(error)")
                    self?.showError("Failed to load replies")
                }
                completion?()
            }
        }
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension PlaceCommentRepliesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Section 0: Parent comment, Section 1: Replies
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1 // Parent comment
        } else {
            return replies.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Original Comment"
        } else if replies.count > 0 {
            return "Replies"
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CommentCell", for: indexPath) as! CommentCell
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        if indexPath.section == 0 {
            // Parent comment
            let canDelete = false // Don't allow deleting parent comment from reply view
            cell.configure(with: parentComment, canDelete: canDelete)
        } else {
            // Reply
            let reply = replies[indexPath.row]
            let canDelete = reply.userId == currentUserId || place.addedBy == currentUserId
            cell.configure(with: reply, canDelete: canDelete)
        }
        
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Only allow editing replies, not the parent comment
        guard indexPath.section == 1 else { return false }
        
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // User can delete if they are the reply author or the place owner
        return reply.userId == currentUserId || place.addedBy == currentUserId
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only allow swipe actions on replies, not the parent comment
        guard indexPath.section == 1 else { return nil }
        
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only show delete if user can delete
        guard reply.userId == currentUserId || place.addedBy == currentUserId else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteReply(at: indexPath, completionHandler: completionHandler)
        }
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    private func deleteReply(at indexPath: IndexPath, completionHandler: @escaping (Bool) -> Void) {
        let reply = replies[indexPath.row]
        
        PlaceService.shared.deletePlaceComment(placeId: place.id, commentId: reply.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove reply from array and table
                    self?.replies.remove(at: indexPath.row)
                    self?.tableView.deleteRows(at: [indexPath], with: .automatic)
                    completionHandler(true)
                case .failure(let error):
                    print("Failed to delete reply: \(error)")
                    self?.showError("Failed to delete reply. Please try again.")
                    completionHandler(false)
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension PlaceCommentRepliesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if sendButton.isEnabled {
            sendReply()
        }
        return true
    }
}

// MARK: - CommentCellDelegate
extension PlaceCommentRepliesViewController: CommentCellDelegate {
    func commentCell(_ cell: CommentCell, didTapMoreButton comment: PlaceComment) {
        guard let indexPath = tableView.indexPath(for: cell), indexPath.section == 1 else { return }
        
        let deleteAction: (title: String, style: UIAlertAction.Style, handler: () -> Void) = (
            title: "Delete Reply",
            style: .destructive,
            handler: { [weak self] in
                self?.deleteReply(at: indexPath) { _ in }
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
        
        // Call API to toggle like for reply
        PlaceService.shared.likeComment(placeId: place.id, commentId: comment.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (liked, likesCount)):
                    // Reload the cell to show updated like state
                    if let index = self?.replies.firstIndex(where: { $0.id == comment.id }) {
                        self?.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    }
                case .failure(let error):
                    print("Failed to like reply: \(error)")
                    self?.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
    
    func commentCell(_ cell: CommentCell, didTapReplyButton comment: PlaceComment) {
        // We don't allow replies to replies (single level nesting only)
        print("Reply to reply not supported")
    }
}
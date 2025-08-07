import UIKit

class CommentRepliesViewController: BaseViewController {
    
    // MARK: - Properties
    private let circle: Circle
    private let parentComment: CircleComment
    private var replies: [CircleComment] = []
    
    // MARK: - Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No replies yet" }
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        table.keyboardDismissMode = .interactive
        return table
    }()
    
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
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
    init(circle: Circle, parentComment: CircleComment) {
        self.circle = circle
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
        view.addSubview(headerView)
        view.addSubview(tableView)
        view.addSubview(commentInputContainer)
        commentInputContainer.addSubview(commentTextField)
        commentInputContainer.addSubview(sendButton)
        
        // Setup header with parent comment
        setupHeaderView()
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CircleCommentCell.self, forCellReuseIdentifier: "CircleCommentCell")
        
        // Configure text field
        commentTextField.delegate = self
        commentTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        sendButton.addTarget(self, action: #selector(sendReply), for: .touchUpInside)
    }
    
    private func setupHeaderView() {
        let parentCell = CircleCommentCell()
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let canDelete = parentComment.userId == currentUserId || circle.owner == currentUserId
        parentCell.configure(with: parentComment, canDelete: false) // Don't show delete in header
        parentCell.translatesAutoresizingMaskIntoConstraints = false
        
        // Add a label to indicate this is the original comment
        let headerLabel = UILabel()
        headerLabel.text = "Original Comment"
        headerLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        headerLabel.textColor = Constants.Colors.secondaryLabel
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(headerLabel)
        headerView.addSubview(parentCell)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            
            parentCell.topAnchor.constraint(equalTo: headerLabel.bottomAnchor),
            parentCell.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            parentCell.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            parentCell.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
        ])
    }
    
    private func setupConstraints() {
        commentInputBottomConstraint = commentInputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            // Header view
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
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
        
        CircleService.shared.addCommentReply(circleId: circle.id, commentId: parentComment.id, text: text) { [weak self] result in
            DispatchQueue.main.async {
                self?.sendButton.isEnabled = true
                self?.commentTextField.isEnabled = true
                
                switch result {
                case .success(let reply):
                    self?.commentTextField.text = ""
                    self?.sendButton.isEnabled = false
                    self?.replies.insert(reply, at: 0)
                    self?.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
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
        CircleService.shared.getCommentReplies(circleId: circle.id, commentId: parentComment.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let replies):
                    self?.replies = replies
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("Failed to fetch replies: \(error)")
                    self?.showError("Failed to load replies")
                }
                completion?()
            }
        }
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension CommentRepliesViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return replies.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCommentCell", for: indexPath) as! CircleCommentCell
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let canDelete = reply.userId == currentUserId || circle.owner == currentUserId
        cell.configure(with: reply, canDelete: canDelete)
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // User can delete if they are the reply author or the circle owner
        return reply.userId == currentUserId || circle.owner == currentUserId
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only show delete if user can delete
        guard reply.userId == currentUserId || circle.owner == currentUserId else {
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
        
        CircleService.shared.deleteCircleComment(circleId: circle.id, commentId: reply.id) { [weak self] result in
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
extension CommentRepliesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if sendButton.isEnabled {
            sendReply()
        }
        return true
    }
}

// MARK: - CircleCommentCellDelegate
extension CommentRepliesViewController: CircleCommentCellDelegate {
    func circleCommentCell(_ cell: CircleCommentCell, didTapMoreButton comment: CircleComment) {
        let deleteAction: (title: String, style: UIAlertAction.Style, handler: () -> Void) = (
            title: "Delete Reply",
            style: .destructive,
            handler: { [weak self] in
                guard let indexPath = self?.tableView.indexPath(for: cell) else { return }
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
    
    func circleCommentCell(_ cell: CircleCommentCell, didTapLikeButton comment: CircleComment) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // TODO: Implement reply liking when backend supports it
        print("Reply like tapped - not yet implemented")
    }
    
    func circleCommentCell(_ cell: CircleCommentCell, didTapReplyButton comment: CircleComment) {
        // We don't allow replies to replies (single level nesting only)
        print("Reply to reply not supported")
    }
}
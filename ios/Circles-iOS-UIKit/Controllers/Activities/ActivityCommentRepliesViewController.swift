import UIKit

class ActivityCommentRepliesViewController: BaseViewController {
    
    // MARK: - Properties
    private let activity: Activity
    private let parentComment: ActivityComment
    private var replies: [ActivityComment] = []
    
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
    
    private let parentCommentView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let parentAvatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = Constants.Colors.secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let parentNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let parentCommentLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let replyInputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let replyTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Write a reply..."
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
    
    private var replyInputBottomConstraint: NSLayoutConstraint?
    
    // MARK: - Init
    init(activity: Activity, parentComment: ActivityComment) {
        self.activity = activity
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
        configureParentComment()
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
        view.addSubview(parentCommentView)
        parentCommentView.addSubview(parentAvatarImageView)
        parentCommentView.addSubview(parentNameLabel)
        parentCommentView.addSubview(parentCommentLabel)
        
        view.addSubview(tableView)
        view.addSubview(replyInputContainer)
        replyInputContainer.addSubview(replyTextField)
        replyInputContainer.addSubview(sendButton)
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ActivityCommentCell.self, forCellReuseIdentifier: "ActivityCommentCell")
        
        // Configure text field
        replyTextField.delegate = self
        replyTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Configure send button
        sendButton.addTarget(self, action: #selector(sendReply), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        replyInputBottomConstraint = replyInputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            // Parent comment view
            parentCommentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            parentCommentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            parentCommentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Parent avatar
            parentAvatarImageView.topAnchor.constraint(equalTo: parentCommentView.topAnchor, constant: 12),
            parentAvatarImageView.leadingAnchor.constraint(equalTo: parentCommentView.leadingAnchor, constant: 16),
            parentAvatarImageView.widthAnchor.constraint(equalToConstant: 32),
            parentAvatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            // Parent name
            parentNameLabel.topAnchor.constraint(equalTo: parentAvatarImageView.topAnchor),
            parentNameLabel.leadingAnchor.constraint(equalTo: parentAvatarImageView.trailingAnchor, constant: 12),
            parentNameLabel.trailingAnchor.constraint(equalTo: parentCommentView.trailingAnchor, constant: -16),
            
            // Parent comment
            parentCommentLabel.topAnchor.constraint(equalTo: parentNameLabel.bottomAnchor, constant: 4),
            parentCommentLabel.leadingAnchor.constraint(equalTo: parentAvatarImageView.trailingAnchor, constant: 12),
            parentCommentLabel.trailingAnchor.constraint(equalTo: parentCommentView.trailingAnchor, constant: -16),
            parentCommentLabel.bottomAnchor.constraint(equalTo: parentCommentView.bottomAnchor, constant: -12),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: parentCommentView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: replyInputContainer.topAnchor),
            
            // Reply input container
            replyInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyInputContainer.heightAnchor.constraint(equalToConstant: 60),
            replyInputBottomConstraint!,
            
            // Reply text field
            replyTextField.leadingAnchor.constraint(equalTo: replyInputContainer.leadingAnchor, constant: 16),
            replyTextField.centerYAnchor.constraint(equalTo: replyInputContainer.centerYAnchor),
            replyTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            
            // Send button
            sendButton.trailingAnchor.constraint(equalTo: replyInputContainer.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: replyInputContainer.centerYAnchor),
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
    
    private func configureParentComment() {
        parentNameLabel.text = parentComment.userName
        parentCommentLabel.text = parentComment.text
        
        // Load avatar if available
        if let urlString = parentComment.userPhoto {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                DispatchQueue.main.async {
                    self?.parentAvatarImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    override func setupRefreshControl() {
        tableView.refreshControl = refreshControl
    }
    
    @objc private func textFieldDidChange() {
        sendButton.isEnabled = !(replyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    
    @objc private func sendReply() {
        guard let text = replyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        
        sendButton.isEnabled = false
        replyTextField.isEnabled = false
        
        // Call API to add reply
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/comments",
            method: .post,
            body: ["text": text, "parentCommentId": parentComment.id]
        ) { [weak self] (result: Result<ActivityCommentResponse, APIError>) in
            DispatchQueue.main.async {
                self?.sendButton.isEnabled = true
                self?.replyTextField.isEnabled = true
                
                switch result {
                case .success(let response):
                    if let reply = response.data {
                        self?.replyTextField.text = ""
                        self?.sendButton.isEnabled = false
                        self?.replies.insert(reply, at: 0)
                        self?.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                    }
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
        
        replyInputBottomConstraint?.constant = -keyboardFrame.height + view.safeAreaInsets.bottom
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        replyInputBottomConstraint?.constant = 0
        
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Data
    override func loadData(completion: (() -> Void)?) {
        // Load replies (comments with parentCommentId)
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/comments?parentCommentId=\(parentComment.id)",
            method: .get
        ) { [weak self] (result: Result<ActivityCommentsResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.replies = response.data
                    self?.tableView.reloadData()
                case .failure(let error):
                    print("Failed to fetch replies: \(error)")
                }
                completion?()
            }
        }
    }
    
    private func deleteReply(at indexPath: IndexPath, completionHandler: @escaping (Bool) -> Void) {
        let reply = replies[indexPath.row]
        
        APIService.shared.request(
            endpoint: "activities/\(activity.id)/comments/\(reply.id)",
            method: .delete
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
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

// MARK: - UITableViewDelegate & UITableViewDataSource
extension ActivityCommentRepliesViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return replies.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ActivityCommentCell", for: indexPath) as! ActivityCommentCell
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        let canDelete = reply.userId == currentUserId || activity.actorId == currentUserId
        cell.configure(with: reply, canDelete: canDelete)
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // User can delete if they are the reply author or the activity owner
        return reply.userId == currentUserId || activity.actorId == currentUserId
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let reply = replies[indexPath.row]
        let currentUserId = AuthService.shared.getUserId() ?? ""
        
        // Only show delete if user can delete
        guard reply.userId == currentUserId || activity.actorId == currentUserId else {
            return nil
        }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteReply(at: indexPath, completionHandler: completionHandler)
        }
        deleteAction.backgroundColor = .systemRed
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - UITextFieldDelegate
extension ActivityCommentRepliesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if sendButton.isEnabled {
            sendReply()
        }
        return true
    }
}

// MARK: - ActivityCommentCellDelegate
extension ActivityCommentRepliesViewController: ActivityCommentCellDelegate {
    func activityCommentCell(_ cell: ActivityCommentCell, didTapMoreButton comment: ActivityComment) {
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
    
    func activityCommentCell(_ cell: ActivityCommentCell, didTapLikeButton comment: ActivityComment) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Call API to toggle like
        APIService.shared.request(
            endpoint: "activities/comments/\(comment.id)/like",
            method: .post
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Reload data to update like state
                    self?.loadData(completion: nil)
                case .failure(let error):
                    print("Failed to like reply: \(error)")
                    self?.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
    
    func activityCommentCell(_ cell: ActivityCommentCell, didTapReplyButton comment: ActivityComment) {
        // Focus on the reply text field with @username
        replyTextField.text = "@\(comment.userName) "
        replyTextField.becomeFirstResponder()
    }
}
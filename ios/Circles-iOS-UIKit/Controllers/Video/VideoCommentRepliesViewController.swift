import UIKit

class VideoCommentRepliesViewController: BaseViewController {
    
    // MARK: - Properties
    private let video: PlaceVideo
    private let parentComment: VideoComment
    private var replies: [VideoComment] = []
    
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
    init(video: PlaceVideo, parentComment: VideoComment) {
        self.video = video
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
        tableView.register(VideoCommentCell.self, forCellReuseIdentifier: "VideoCommentCell")
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 30
        
        // Configure text field
        commentTextField.delegate = self
        commentTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        commentTextField.addDoneButtonOnKeyboard()
        
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
        
        let endpoint = "videos/\(video.id)/comments/\(parentComment.id)/replies"
        let body = ["text": text]
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body
        ) { [weak self] (result: Result<VideoCommentResponse, APIError>) in
            DispatchQueue.main.async {
                self?.sendButton.isEnabled = true
                self?.commentTextField.isEnabled = true
                
                switch result {
                case .success(let response):
                    self?.commentTextField.text = ""
                    self?.sendButton.isEnabled = false
                    self?.replies.insert(response.data, at: 0)
                    self?.tableView.insertRows(at: [IndexPath(row: 0, section: 1)], with: .automatic)
                    self?.updateEmptyState()
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
        let endpoint = "videos/\(video.id)/comments/\(parentComment.id)/replies"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get
        ) { [weak self] (result: Result<VideoCommentsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    self.replies = response.data
                    self.tableView.reloadData()
                    self.updateEmptyState()
                case .failure(let error):
                    print("Failed to fetch replies: \(error)")
                }
                completion?()
            }
        }
    }
    
    private func updateEmptyState() {
        tableView.backgroundView = replies.isEmpty ? createEmptyStateLabel() : nil
    }
    
    private func createEmptyStateLabel() -> UILabel {
        let label = UILabel()
        label.text = emptyStateMessage
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16)
        return label
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension VideoCommentRepliesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Parent comment + replies
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : replies.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoCommentCell", for: indexPath) as! VideoCommentCell
        
        if indexPath.section == 0 {
            // Parent comment
            cell.configure(with: parentComment)
        } else {
            // Reply
            let reply = replies[indexPath.row]
            cell.configure(with: reply)
        }
        
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Comment" : (replies.isEmpty ? nil : "Replies")
    }
}

// MARK: - UITextFieldDelegate
extension VideoCommentRepliesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if sendButton.isEnabled {
            sendReply()
        }
        return true
    }
}

// MARK: - VideoCommentCellDelegate
extension VideoCommentRepliesViewController: VideoCommentCellDelegate {
    func videoCommentCellDidTapDelete(_ cell: VideoCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell),
              indexPath.section == 1 else { return } // Only allow deleting replies, not parent
        
        let reply = replies[indexPath.row]
        
        // Only allow deleting own comments
        guard reply.userId == AuthService.shared.getUserId() else { return }
        
        showConfirmation(
            title: "Delete Reply",
            message: "Are you sure you want to delete this reply?"
        ) { [weak self] in
            self?.deleteReply(reply, at: indexPath)
        }
    }
    
    func videoCommentCellDidTapReply(_ cell: VideoCommentCell) {
        // Replies to replies not supported yet
    }
    
    func videoCommentCellDidTapLike(_ cell: VideoCommentCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        
        let comment = indexPath.section == 0 ? parentComment : replies[indexPath.row]
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        // Call API to toggle like
        let endpoint = "videos/\(video.id)/comments/\(comment.id)/like"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post
        ) { [weak self] (result: Result<VideoLikeCommentResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    // Reload the specific cell
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    
                case .failure(let error):
                    print("Failed to like comment: \(error)")
                    self.showError("Failed to update like. Please try again.")
                }
            }
        }
    }
    
    private func deleteReply(_ reply: VideoComment, at indexPath: IndexPath) {
        let endpoint = "videos/\(video.id)/comments/\(reply.id)"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .delete
        ) { [weak self] (result: Result<SimpleAPIResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success:
                    self.replies.remove(at: indexPath.row)
                    self.tableView.deleteRows(at: [indexPath], with: .automatic)
                    self.updateEmptyState()
                    self.showSuccess("Reply deleted")
                    
                case .failure(let error):
                    print("Failed to delete reply: \(error)")
                    self.showError("Failed to delete reply. Please try again.")
                }
            }
        }
    }
}
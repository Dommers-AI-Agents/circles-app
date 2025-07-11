import UIKit

class PlaceCommentsViewController: UIViewController {
    
    // MARK: - Properties
    private let place: Place
    private var comments: [PlaceComment] = []
    private let refreshControl = UIRefreshControl()
    var onCommentsUpdated: ((Int) -> Void)?
    
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
        fetchComments()
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        // Add subviews
        view.addSubview(tableView)
        view.addSubview(commentInputContainer)
        commentInputContainer.addSubview(commentTextField)
        commentInputContainer.addSubview(sendButton)
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CommentCell.self, forCellReuseIdentifier: "CommentCell")
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshComments), for: .valueChanged)
        
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
    
    @objc private func refreshComments() {
        fetchComments()
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
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to add comment. Please try again.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
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
    private func fetchComments() {
        PlaceService.shared.getPlaceComments(placeId: place.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.refreshControl.endRefreshing()
                
                switch result {
                case .success(let comments):
                    self?.comments = comments
                    self?.tableView.reloadData()
                    self?.onCommentsUpdated?(comments.count)
                case .failure(let error):
                    print("Failed to fetch comments: \(error)")
                }
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
                    let alert = UIAlertController(
                        title: "Error",
                        message: "Failed to delete comment. Please try again.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
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
        
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
        
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
            commentLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
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
    }
    
    @objc private func moreButtonTapped() {
        guard let comment = comment else { return }
        delegate?.commentCell(self, didTapMoreButton: comment)
    }
}

// MARK: - CommentCellDelegate
protocol CommentCellDelegate: AnyObject {
    func commentCell(_ cell: CommentCell, didTapMoreButton comment: PlaceComment)
}

// MARK: - CommentCellDelegate
extension PlaceCommentsViewController: CommentCellDelegate {
    func commentCell(_ cell: CommentCell, didTapMoreButton comment: PlaceComment) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        let deleteAction = UIAlertAction(title: "Delete Comment", style: .destructive) { [weak self] _ in
            guard let indexPath = self?.tableView.indexPath(for: cell) else { return }
            self?.deleteComment(at: indexPath) { _ in }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(cancelAction)
        
        // For iPad
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = cell
            popover.sourceRect = cell.bounds
        }
        
        present(actionSheet, animated: true)
    }
}
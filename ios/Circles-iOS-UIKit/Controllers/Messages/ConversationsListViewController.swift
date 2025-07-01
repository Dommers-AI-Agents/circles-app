import UIKit
import Combine

class ConversationsListViewController: UIViewController {
    
    // MARK: - UI Elements
    private let headerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let suggestionsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Suggestions", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        button.tintColor = .systemBlue
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let suggestionsBadge: UILabel = {
        let label = UILabel()
        label.backgroundColor = .systemRed
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let emptyImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "message.circle")
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No Messages Yet"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emptyDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Start a conversation with your connections"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let newMessageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 28
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 4
        return button
    }()
    
    // MARK: - Properties
    private let messagingManager = MessagingManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let cellIdentifier = "ConversationCell"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        setupEmptyState()
        setupNewMessageButton()
        setupSubscribers()
        loadConversations()
        checkForNewSuggestions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        messagingManager.loadConversations()
        messagingManager.updateUnreadCount()
        checkForNewSuggestions()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Messages"
        
        view.addSubview(headerContainer)
        headerContainer.addSubview(suggestionsButton)
        headerContainer.addSubview(suggestionsBadge)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(newMessageButton)
        
        // Add button target
        suggestionsButton.addTarget(self, action: #selector(suggestionsButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Suggestions button
            suggestionsButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            suggestionsButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            suggestionsButton.heightAnchor.constraint(equalToConstant: 36),
            
            // Suggestions badge
            suggestionsBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            suggestionsBadge.heightAnchor.constraint(equalToConstant: 20),
            suggestionsBadge.leadingAnchor.constraint(equalTo: suggestionsButton.trailingAnchor, constant: -12),
            suggestionsBadge.bottomAnchor.constraint(equalTo: suggestionsButton.topAnchor, constant: 8),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            
            newMessageButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            newMessageButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            newMessageButton.widthAnchor.constraint(equalToConstant: 56),
            newMessageButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ConversationCell.self, forCellReuseIdentifier: cellIdentifier)
        
        // Add refresh control
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshConversations), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupEmptyState() {
        emptyStateView.addSubview(emptyImageView)
        emptyStateView.addSubview(emptyTitleLabel)
        emptyStateView.addSubview(emptyDescriptionLabel)
        
        NSLayoutConstraint.activate([
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyImageView.widthAnchor.constraint(equalToConstant: 80),
            emptyImageView.heightAnchor.constraint(equalToConstant: 80),
            
            emptyTitleLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 24),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            emptyDescriptionLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptyDescriptionLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyDescriptionLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyDescriptionLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    private func setupNewMessageButton() {
        newMessageButton.addTarget(self, action: #selector(newMessageTapped), for: .touchUpInside)
    }
    
    private func setupSubscribers() {
        messagingManager.$conversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateEmptyState()
            }
            .store(in: &cancellables)
        
        messagingManager.$isLoadingConversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if !isLoading {
                    self?.tableView.refreshControl?.endRefreshing()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    private func loadConversations() {
        messagingManager.loadConversations()
    }
    
    @objc private func refreshConversations() {
        messagingManager.loadConversations()
    }
    
    // MARK: - Actions
    @objc private func newMessageTapped() {
        let selectConnectionVC = SelectConnectionViewController()
        selectConnectionVC.delegate = self
        let navController = UINavigationController(rootViewController: selectConnectionVC)
        present(navController, animated: true)
    }
    
    // MARK: - Empty State
    private func updateEmptyState() {
        let hasConversations = !messagingManager.conversations.isEmpty
        emptyStateView.isHidden = hasConversations
        tableView.isHidden = !hasConversations
    }
    
    // MARK: - Actions
    @objc private func suggestionsButtonTapped() {
        let suggestionsVC = SuggestionsViewController()
        navigationController?.pushViewController(suggestionsVC, animated: true)
    }
    
    private func checkForNewSuggestions() {
        SuggestionService.shared.getUnreadSuggestionsCount { [weak self] count in
            DispatchQueue.main.async {
                if count > 0 {
                    self?.suggestionsBadge.text = "\(count)"
                    self?.suggestionsBadge.isHidden = false
                } else {
                    self?.suggestionsBadge.isHidden = true
                }
            }
        }
    }
    
    // MARK: - Navigation
    private func showConversation(_ conversation: Conversation) {
        let chatVC = ChatViewController()
        chatVC.conversation = conversation
        navigationController?.pushViewController(chatVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension ConversationsListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messagingManager.conversations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! ConversationCell
        let conversation = messagingManager.conversations[indexPath.row]
        cell.configure(with: conversation)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ConversationsListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conversation = messagingManager.conversations[indexPath.row]
        showConversation(conversation)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            // TODO: Implement conversation deletion
            completion(false)
        }
        deleteAction.backgroundColor = .systemRed
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - SelectConnectionViewControllerDelegate
extension ConversationsListViewController: SelectConnectionViewControllerDelegate {
    func didSelectConnection(_ connection: Connection) {
        // Create or get conversation with selected connection
        messagingManager.createOrGetDirectConversation(with: connection.connectedUserId) { [weak self] result in
            switch result {
            case .success(let conversation):
                self?.showConversation(conversation)
            case .failure(let error):
                print("Error creating conversation: \(error)")
            }
        }
    }
}

// MARK: - ConversationCell
class ConversationCell: UITableViewCell {
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let unreadBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.backgroundColor = Constants.Colors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        avatarImageView.backgroundColor = .systemGray5
        nameLabel.text = nil
        messageLabel.text = nil
        timeLabel.text = nil
        unreadBadge.isHidden = true
        messageLabel.font = .systemFont(ofSize: 14)
    }
    
    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(unreadBadge)
        
        avatarImageView.layer.cornerRadius = 28
        
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 56),
            avatarImageView.heightAnchor.constraint(equalToConstant: 56),
            
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -8),
            
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            
            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            unreadBadge.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with conversation: Conversation) {
        nameLabel.text = conversation.displayName
        messageLabel.text = conversation.lastMessage ?? "No messages yet"
        timeLabel.text = conversation.formattedLastMessageTime ?? ""
        
        // Configure avatar
        if let avatarURL = conversation.displayAvatar {
            // Set placeholder while loading
            avatarImageView.image = UIImage(systemName: conversation.type == .direct ? "person.circle.fill" : "person.2.circle.fill")
            avatarImageView.tintColor = .systemGray3
            
            // Load image from URL
            ImageService.shared.loadImage(from: avatarURL) { [weak self] image in
                DispatchQueue.main.async {
                    if let image = image {
                        self?.avatarImageView.image = image
                        self?.avatarImageView.tintColor = nil
                    }
                }
            }
        } else {
            avatarImageView.image = UIImage(systemName: conversation.type == .direct ? "person.circle.fill" : "person.2.circle.fill")
            avatarImageView.tintColor = .systemGray3
        }
        
        // Configure unread badge
        if conversation.hasUnreadMessages {
            unreadBadge.isHidden = false
            unreadBadge.text = "\(conversation.unreadCount)"
            messageLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        } else {
            unreadBadge.isHidden = true
            messageLabel.font = .systemFont(ofSize: 14)
        }
    }
}
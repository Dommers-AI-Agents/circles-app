import UIKit
import MapKit
import CoreLocation

// MARK: - MessageCellDelegate
protocol MessageCellDelegate: AnyObject {
    func didTapProfileImage(for userId: String)
    /// A photo/postcard bubble was tapped.
    func didTapMessageImage(urlString: String)
    /// A drink a friend sent was tapped: open its recipe.
    func didTapDrink(id: String)
    /// A Coach Mane card a friend sent was tapped: open Motivation on it.
    func didTapMotivation(lineId: String)
    /// A shared place, circle or location was tapped.
    func didTapShareCard(_ card: MessageShareCard)
    /// A bubble was held: Copy / Edit / Delete.
    func didLongPressMessage(id: String, from sourceView: UIView)
}

class ChatViewController: BaseViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.backgroundColor = .systemBackground
        table.transform = CGAffineTransform(scaleX: 1, y: -1) // Invert for bottom-to-top layout
        table.keyboardDismissMode = .interactive
        return table
    }()
    
    private let messageInputContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor
        return view
    }()
    
    private let messageTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 18
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.isScrollEnabled = false
        // Fix RTI issues
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        return textView
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Type a message..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let sendButton: UIButton = {
        let button = UIButton.iconButton(systemName: "arrow.up.circle.fill")
        button.tintColor = Constants.Colors.primary
        button.isEnabled = false
        return button
    }()
    
    private let attachButton: UIButton = {
        let button = UIButton.iconButton(systemName: "plus.circle")
        button.tintColor = .systemGray
        return button
    }()
    
    private let loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Properties
    var conversation: Conversation?
    private let messagingManager = MessagingManager.shared
    private var messageUpdateTimer: Timer?
    private var messages: [Message] = []
    private var keyboardHeight: CGFloat = 0
    private var messageInputBottomConstraint: NSLayoutConstraint!
    private let cellIdentifier = "MessageCell"
    private var hasCompletedInitialLoad = false

    /// The new look (color wash, grouped bubbles, day dividers) or the
    /// classic one; read once, when the chat opens (`ChatLookPreference`)
    private let isPolished = ChatLookPreference.isPolished
    /// What the table shows, oldest first (the table is inverted)
    private var rows: [ChatTimeline.Row] = []
    private var messagesById: [String: Message] = [:]
    /// "Read" / "Sent" under your newest message (one-on-one, new look)
    private var receipt: (id: String, text: String)?
    /// Everything a bubble draws from, per message, as last shown: a redraw
    /// happens when this changes (an edit, a delete, a read), not only when
    /// the count does
    private var shownSignature: [String] = []
    private var markedReadIds = Set<String>()
    private let directTitleView = ChatTitleView()
    private let emptyStateView = ChatEmptyStateView()
    
    // MARK: - BaseViewController Configuration
    override var showsLoadingIndicator: Bool { true }
    override var loadsDataOnViewDidLoad: Bool { true }
    override var reloadsDataOnAppear: Bool { false }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Logger.debug("🔍 ChatViewController: viewDidLoad called")
        if let conv = conversation {
            Logger.debug("🔍 ChatViewController: Conversation loaded - ID: \(conv.id)")
            Logger.debug("🔍 ChatViewController: Conversation type: \(conv.type)")
            Logger.debug("🔍 ChatViewController: Conversation participants: \(conv.participants)")
        } else {
            Logger.debug("❌ ChatViewController: No conversation set!")
        }
        
        setupView()
        setupTableView()
        setupMessageInput()
        setupSubscribers()
        // Already loaded once (the list preloads, or a reopen): show it now
        // instead of a spinner until the fetch lands
        if let conversationId = conversation?.id, messagingManager.activeMessages[conversationId] != nil {
            refreshFromManager()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Both stop when the chat is covered (a profile, the info screen), so
        // both start here, not once in viewDidLoad: back from a profile the
        // chat used to stop refreshing and the keyboard covered the field
        setupKeyboardHandling(bottomConstraint: messageInputBottomConstraint, dismissOnTap: false)
        startRefreshTimer()
        if hasCompletedInitialLoad { refreshFromManager() }
        markMessagesAsRead()
        // Seeing the chat settles its notifications even when every message
        // was already read (another device, or a reopen)
        if let conversationId = conversation?.id {
            NotificationService.shared.originSeen(kind: "conversation", id: conversationId, userInfoKey: "conversationId")
        }
        
        // Refresh navigation bar in case group settings were updated
        if conversation?.type == .group {
            setupNavigationBarWithTappableTitle()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        markMessagesAsRead()
        removeKeyboardHandling()
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        messageUpdateTimer?.invalidate()
    }
    
    // MARK: - Setup
    private func setupView() {
        // Debug logging
        Logger.debug("🔍 ChatViewController.setupView: conversation type = \(conversation?.type.rawValue ?? "nil")")
        Logger.debug("🔍 ChatViewController.setupView: conversation name = \(conversation?.displayName ?? "nil")")
        Logger.debug("🔍 ChatViewController.setupView: is group = \(conversation?.type == .group)")
        
        // For group conversations, make title tappable for settings
        if conversation?.type == .group {
            Logger.debug("✅ ChatViewController: Setting up group conversation UI")
            setupNavigationBarWithTappableTitle()
            // Add settings gear icon for group conversations
            addNavigationBarButton(image: "gearshape.fill", position: .right, action: #selector(openGroupSettings))
        } else {
            Logger.debug("ℹ️ ChatViewController: Setting up direct conversation UI")
            setupDirectTitle()
            addNavigationBarButton(image: "info.circle", position: .right, action: #selector(showConversationInfo))
        }
        
        if isPolished {
            // Never a flat black page: the brand wash behind clear bubbles
            // (top to bottom: bubbles gather at the bottom, so the color
            // can't fade out halfway down like the first-run backdrop's)
            let backdrop = GradientView()
            backdrop.colors = [Constants.Colors.primary.withAlphaComponent(0.30),
                               Constants.Colors.accent.withAlphaComponent(0.14),
                               Constants.Colors.primary.withAlphaComponent(0.16)]
            backdrop.locations = [0, 0.5, 1]
            backdrop.isUserInteractionEnabled = false
            view.backgroundColor = Constants.Colors.background
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(backdrop, at: 0)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: view.topAnchor),
                backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            tableView.backgroundColor = .clear
            loadingView.backgroundColor = .clear
        }
        
        view.addSubview(tableView)
        view.addSubview(messageInputContainer)
        setupEmptyState()
        
        // Add loading view
        view.addSubview(loadingView)
        loadingView.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor)
        ])
        
        // Show loading initially
        showLoading()
    }
    
    /// The other person in a one-on-one chat
    private var otherParticipant: User? {
        let me = AuthService.shared.getUserId()
        let people = conversation?.participantDetails
        return people?.first(where: { $0.id != me }) ?? people?.first
    }

    /// One-on-one: the person's photo and name in the bar; a tap opens
    /// their profile (Wes, 2026-11-23)
    private func setupDirectTitle() {
        setupNavigationBar(title: conversation?.displayName ?? "Chat")
        guard let conversation, conversation.type == .direct, let other = otherParticipant else { return }
        directTitleView.configure(name: conversation.displayName, avatarURL: other.profilePicture, seed: other.id)
        directTitleView.addTarget(self, action: #selector(directTitleTapped), for: .touchUpInside)
        navigationItem.titleView = directTitleView
    }

    @objc private func directTitleTapped() {
        guard let userId = otherParticipant?.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        didTapProfileImage(for: userId)
    }

    /// A chat with nothing in it says who it is with and how to start
    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            emptyStateView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
        emptyStateView.onWave = { [weak self] in self?.send(text: "👋") }
        emptyStateView.onSharePlace = { [weak self] in self?.sharePlace() }
        configureEmptyState()
    }

    private func configureEmptyState() {
        guard let conversation else { return }
        let isGroup = conversation.type == .group
        emptyStateView.configure(name: conversation.displayName,
                                 firstName: isGroup ? nil : otherFirstName,
                                 avatarURL: conversation.displayAvatar,
                                 seed: isGroup ? conversation.id : (otherParticipant?.id ?? conversation.id),
                                 isGroup: isGroup)
    }

    private var otherFirstName: String? {
        guard conversation?.type == .direct, let other = otherParticipant else { return nil }
        if let first = other.firstName, !first.isEmpty { return first }
        return other.displayName.components(separatedBy: .whitespaces).first(where: { !$0.isEmpty })
    }

    private func updateEmptyState() {
        // (a system thread has nobody to wave at)
        let canStart = conversation?.type == .direct || conversation?.type == .group
        emptyStateView.isHidden = !(canStart && hasCompletedInitialLoad && messages.isEmpty)
    }

    private func setupNavigationBarWithTappableTitle() {
        setupNavigationBar(title: conversation?.displayName ?? "Group Chat")
        
        // Create a button for better touch handling
        let titleButton = UIButton(type: .system)
        titleButton.frame = CGRect(x: 0, y: 0, width: 250, height: 44)
        
        // Create group avatar image view
        // Rounded square, same silhouette as the group row in the messages list
        let avatarSide: CGFloat = 32
        let avatarImageView = UIImageView()
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = AvatarPlaceholder.groupCornerRadius(for: avatarSide)
        avatarImageView.layer.cornerCurve = .continuous
        avatarImageView.backgroundColor = Constants.Colors.tertiaryBackground
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.image = AvatarPlaceholder.groupImage(seed: conversation?.id ?? "", side: avatarSide)
        
        // Load group avatar over the placeholder
        if let groupAvatar = conversation?.avatar, !groupAvatar.isEmpty {
            ImageService.shared.loadImage(from: groupAvatar) { image in
                DispatchQueue.main.async {
                    if let image = image { avatarImageView.image = image }
                }
            }
        }
        
        // Create title label
        let titleLabel = UILabel()
        titleLabel.text = conversation?.displayName ?? "Group Chat"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        // Create chevron icon to indicate tappability
        let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.down.circle.fill"))
        chevronImageView.tintColor = .systemGray
        chevronImageView.contentMode = .scaleAspectFit
        
        // Stack view to arrange avatar, title and chevron
        let stackView = UIStackView(arrangedSubviews: [avatarImageView, titleLabel, chevronImageView])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        
        titleButton.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            // Avatar constraints
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            stackView.centerXAnchor.constraint(equalTo: titleButton.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: titleButton.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: titleButton.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: titleButton.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: titleButton.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: titleButton.bottomAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 20),
            chevronImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Add action to button
        titleButton.addTarget(self, action: #selector(titleTapped), for: .touchUpInside)
        
        // Add highlight effect
        titleButton.showsMenuAsPrimaryAction = false
        titleButton.adjustsImageWhenHighlighted = true
        
        navigationItem.titleView = titleButton
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: cellIdentifier)
        tableView.register(ChatDayCell.self, forCellReuseIdentifier: ChatDayCell.reuseIdentifier)
        // Removed ConnectionRequestMessageCell registration - no longer needed
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: messageInputContainer.topAnchor)
        ])
    }
    
    private func setupMessageInput() {
        messageInputContainer.addSubview(attachButton)
        messageInputContainer.addSubview(messageTextView)
        messageInputContainer.addSubview(placeholderLabel)
        messageInputContainer.addSubview(sendButton)
        
        messageTextView.delegate = self
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        attachButton.addTarget(self, action: #selector(showAttachmentOptions), for: .touchUpInside)
        
        messageInputBottomConstraint = messageInputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        if isPolished {
            // No boxed-in bar: a soft pill on the wash, brand-blue buttons
            messageInputContainer.backgroundColor = .clear
            messageInputContainer.layer.borderWidth = 0
            messageTextView.backgroundColor = MessageCell.receivedBubbleColor
            messageTextView.layer.cornerRadius = 20
            messageTextView.layer.cornerCurve = .continuous
            messageTextView.textContainerInset = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
            placeholderLabel.text = otherFirstName.map { "Message \($0)" } ?? "Message"
            attachButton.setImage(UIImage(systemName: "plus.circle.fill",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)), for: .normal)
            attachButton.tintColor = Constants.Colors.primary
            sendButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 30, weight: .medium), forImageIn: .normal)
            sendButton.tintColor = .systemGray3
        }
        attachButton.accessibilityLabel = "Share a circle, place or location"
        sendButton.accessibilityLabel = "Send"
        
        NSLayoutConstraint.activate([
            messageInputContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            messageInputContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            messageInputBottomConstraint,
            messageInputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            
            attachButton.leadingAnchor.constraint(equalTo: messageInputContainer.leadingAnchor, constant: 8),
            attachButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),
            
            messageTextView.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            messageTextView.topAnchor.constraint(equalTo: messageInputContainer.topAnchor, constant: 8),
            messageTextView.bottomAnchor.constraint(equalTo: messageInputContainer.bottomAnchor, constant: -8),
            messageTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            messageTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: messageTextView.leadingAnchor, constant: isPolished ? 19 : 16),
            placeholderLabel.centerYAnchor.constraint(equalTo: messageTextView.centerYAnchor),
            
            sendButton.trailingAnchor.constraint(equalTo: messageInputContainer.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: messageInputContainer.bottomAnchor, constant: isPolished ? -12 : -8),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    
    private func setupSubscribers() {
        Logger.debug("🔍 ChatViewController: setupSubscribers() called")
        
        guard let conversation = conversation else {
            Logger.debug("❌ ChatViewController: setupSubscribers() - conversation is nil!")
            return
        }
        
        let conversationId = conversation.id
        
        Logger.debug("✅ ChatViewController: setupSubscribers() - conversationId: \(conversationId)")
        
        // Listen for new messages notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessages(_:)),
            name: .newMessagesReceived,
            object: nil
        )
        Logger.debug("🔍 ChatViewController: Added observer for NewMessagesReceived")
        
        // Listen for conversation updates (e.g., avatar changes)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationUpdated(_:)),
            name: .conversationUpdated,
            object: nil
        )
        Logger.debug("🔍 ChatViewController: Added observer for ConversationUpdated")
        
        // Poll for message updates (as backup)
    }

    /// Looks for changes every 2 seconds while the chat is on screen
    private func startRefreshTimer() {
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshFromManager()
        }
    }

    /// Shows what the manager holds for this chat. Redraws when anything a
    /// bubble shows has changed: a new message, an edit, a delete, a read
    /// (it used to compare counts only, so those never appeared).
    private func refreshFromManager() {
        guard let conversationId = conversation?.id else { return }
        guard let loaded = messagingManager.activeMessages[conversationId] else {
            // Nothing fetched and nothing on the way: stop the spinner
            if !messagingManager.isLoadingMessages { finishInitialLoad() }
            return
        }
        // Connection requests live in My Network, not here
        let filtered = loaded.filter { $0.type != .connectionRequest }
        finishInitialLoad()
        guard filtered.map(Self.signature) != shownSignature else { return }
        let newestChanged = filtered.last?.id != messages.last?.id
        apply(filtered)
        if newestChanged { scrollToBottom(animated: true) }
    }

    private func finishInitialLoad() {
        guard !hasCompletedInitialLoad else { return }
        hasCompletedInitialLoad = true
        hideLoading()
        updateEmptyState()
    }

    private static func signature(_ message: Message) -> String {
        "\(message.id)|\(message.editedAt ?? "")|\(message.deletedAt ?? "")|\(message.readBy?.count ?? 0)"
    }

    /// Takes a new list of messages (oldest first) and redraws the chat
    private func apply(_ newMessages: [Message]) {
        messages = newMessages
        shownSignature = newMessages.map(Self.signature)
        messagesById = Dictionary(newMessages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let me = AuthService.shared.getUserId()
        let otherId = conversation?.type == .direct ? otherParticipant?.id : nil
        let entries = newMessages.map { message in
            ChatTimeline.Entry(id: message.id, senderId: message.senderId, date: message.createdDate,
                               isMine: message.senderId == me,
                               readByOther: otherId.map { (message.readBy ?? []).contains($0) } ?? false)
        }
        rows = ChatTimeline.rows(entries, grouped: isPolished)
        receipt = (isPolished && otherId != nil) ? ChatTimeline.receipt(entries) : nil

        tableView.reloadData()
        updateEmptyState()
        // Reading it here counts as read (it used to wait for the chat to close)
        if viewIfLoaded?.window != nil { markMessagesAsRead() }
    }

    /// The row at a table position (the table is inverted: row 0 is newest)
    private func row(at indexPath: IndexPath) -> ChatTimeline.Row? {
        let index = rows.count - 1 - indexPath.row
        return rows.indices.contains(index) ? rows[index] : nil
    }

    private func message(at indexPath: IndexPath) -> Message? {
        row(at: indexPath)?.messageId.flatMap { messagesById[$0] }
    }
    
    @objc private func handleConversationUpdated(_ notification: Notification) {
        Logger.debug("🔍 ChatViewController: handleConversationUpdated notification received")
        
        guard let userInfo = notification.userInfo,
              let updatedConversation = userInfo["conversation"] as? Conversation,
              updatedConversation.id == conversation?.id else {
            return
        }
        
        // Update our conversation reference
        self.conversation = updatedConversation
        
        // Refresh navigation bar to show updated avatar/name
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.conversation?.type == .group {
                self.setupNavigationBarWithTappableTitle()
            } else {
                self.setupDirectTitle()
            }
            self.configureEmptyState()
        }
    }
    
    @objc private func handleNewMessages(_ notification: Notification) {
        Logger.debug("🔍 ChatViewController: handleNewMessages notification received")
        
        guard let userInfo = notification.userInfo else {
            Logger.debug("⚠️ ChatViewController: handleNewMessages - no userInfo in notification")
            return
        }
        
        guard let notificationConversationId = userInfo["conversationId"] as? String else {
            Logger.debug("⚠️ ChatViewController: handleNewMessages - no conversationId in userInfo")
            return
        }
        
        Logger.debug("🔍 ChatViewController: handleNewMessages - notificationConversationId: \(notificationConversationId)")
        Logger.debug("🔍 ChatViewController: handleNewMessages - current conversation.id: \(conversation?.id ?? "nil")")
        
        guard notificationConversationId == conversation?.id else {
            Logger.debug("⚠️ ChatViewController: handleNewMessages - conversationId mismatch, ignoring notification")
            return
        }
        
        refreshFromManager()
    }
    
    // MARK: - BaseViewController Implementation
    override func loadData(completion: (() -> Void)?) {
        Logger.debug("🔍 ChatViewController: loadData() called")
        
        guard let conversation = conversation else {
            Logger.debug("❌ ChatViewController: loadData() - conversation is nil!")
            completion?()
            return
        }
        
        let conversationId = conversation.id
        
        Logger.debug("✅ ChatViewController: loadData() - conversationId: \(conversationId)")
        Logger.debug("🔍 ChatViewController: Conversation details:")
        Logger.debug("   - ID: \(conversationId)")
        Logger.debug("   - Type: \(conversation.type)")
        Logger.debug("   - Participants: \(conversation.participants)")
        Logger.debug("   - Display Name: \(conversation.displayName ?? "nil")")
        Logger.debug("   - Current messages count: \(messages.count)")
        
        Logger.debug("🔍 ChatViewController: Calling messagingManager.loadMessages(for: \(conversationId))")
        messagingManager.loadMessages(for: conversationId)
        
        // Complete after a short delay to allow messages to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            completion?()
        }
    }
    
    private func showLoading() {
        loadingView.isHidden = false
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        messageInputContainer.isHidden = true
    }
    
    private func hideLoading() {
        loadingView.isHidden = true
        loadingIndicator.stopAnimating()
        tableView.isHidden = false
        messageInputContainer.isHidden = false
    }
    
    private func markMessagesAsRead() {
        guard let conversationId = conversation?.id else { return }
        
        // Each message is reported once; the list refreshes every 2 seconds
        let unreadMessageIds = messages
            .filter { !$0.isCurrentUserMessage && !$0.isRead && !markedReadIds.contains($0.id) }
            .map { $0.id }
        
        if !unreadMessageIds.isEmpty {
            markedReadIds.formUnion(unreadMessageIds)
            messagingManager.markMessagesAsRead(conversationId: conversationId, messageIds: unreadMessageIds)
        }
    }
    
    // MARK: - Actions
    @objc private func sendMessage() {
        guard conversation?.id != nil else { return }
        
        // Get text directly from text view
        let text = messageTextView.text ?? ""
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else { return }
        
        // Clear the field (on the next turn: this can run inside the text
        // view's own change callback); a failed send puts the words back
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.messageTextView.text = ""
            self.textViewDidChange(self.messageTextView)
        }
        send(text: trimmedText) { [weak self] in
            guard let self, self.messageTextView.text.isEmpty else { return }
            self.messageTextView.text = trimmedText
            self.textViewDidChange(self.messageTextView)
        }
    }

    /// Sends a text message and shows it at once
    private func send(text: String, onFailure: (() -> Void)? = nil) {
        guard let conversationId = conversation?.id else { return }
        messagingManager.sendMessage(conversationId: conversationId, type: .text, content: text) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.refreshFromManager()
                case .failure(let error):
                    self?.showError(error)
                    onFailure?()
                }
            }
        }
    }
    
    @objc private func showAttachmentOptions() {
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = [
            (title: "Share Circle", style: .default, handler: { [weak self] in 
                _ = self?.shareCircle()
            }),
            (title: "Share Place", style: .default, handler: { [weak self] in 
                _ = self?.sharePlace()
            }),
            (title: "Share Location", style: .default, handler: { [weak self] in 
                _ = self?.shareLocation()
            })
        ]
        
        // Add group settings option for group conversations
        if conversation?.type == .group {
            actions.insert(
                (title: "Group Settings", style: .default, handler: { [weak self] in
                    self?.titleTapped()
                }),
                at: 0
            )
        }
        
        AlertPresenter.showActionSheet(
            actions: actions,
            from: self,
            sourceView: attachButton,
            sourceRect: attachButton.bounds
        )
    }
    
    @objc private func showConversationInfo() {
        guard let conversation else { return }
        // Newest first; the chat holds its messages newest first already
        let shared = messages.filter { !$0.isDeleted }.compactMap { MessageShareCard(type: $0.type, metadata: $0.metadata) }
        let info = ConversationInfoViewController(conversation: conversation, shared: shared)
        info.onOpenShare = { [weak self] card in self?.openShareTarget(card) }
        info.onOpenProfile = { [weak self] userId in self?.didTapProfileImage(for: userId) }
        info.onNotificationsChanged = { [weak self] enabled in self?.notificationsDidChange(enabled) }
        navigationController?.pushViewController(info, animated: true)
    }
    
    @objc private func openGroupSettings() {
        titleTapped()
    }
    
    @objc private func titleTapped() {
        Logger.debug("🔍 ChatViewController: Title tapped")
        Logger.debug("🔍 ChatViewController: Conversation type = \(conversation?.type.rawValue ?? "nil")")
        Logger.debug("🔍 ChatViewController: Is group = \(conversation?.type == .group)")
        Logger.debug("🔍 ChatViewController: Conversation ID = \(conversation?.id ?? "nil")")
        
        // Provide haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        guard let conversation = conversation else {
            Logger.debug("❌ ChatViewController: No conversation available")
            return
        }
        
        guard conversation.type == .group else {
            Logger.debug("❌ ChatViewController: Not a group conversation, type = \(conversation.type.rawValue)")
            return
        }
        
        Logger.debug("✅ ChatViewController: Opening group settings for conversation: \(conversation.displayName)")
        let settingsVC = GroupConversationSettingsViewController(conversation: conversation)
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }
    
    
    // MARK: - Helper Methods
    private func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
    
    // MARK: - Sharing (the "+" menu; 2026-10-30, these were empty stubs)

    /// Through the message manager, like a typed message, so the card shows
    /// in the chat at once (Wes, 2026-11-02: it sent but the chat didn't
    /// update until it reloaded; the service alone never told the chat)
    private func sendShare(_ share: MessageShareCard.Outgoing) {
        guard let conversationId = conversation?.id else { return }
        messagingManager.sendMessage(conversationId: conversationId, type: share.type,
                                     content: share.content, metadata: share.metadata) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.refreshFromManager()
                case .failure(let error): self?.showError(error)
                }
            }
        }
    }

    /// One of your circles, in profile order
    private func shareCircle() {
        let loading = AlertPresenter.showLoading(message: "Loading your circles...", from: self)
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    switch result {
                    case .success(let circles) where !circles.isEmpty:
                        let picker = CirclePickerViewController(circles: circles)
                        picker.pickerTitle = "Share a Circle"
                        picker.onCircleSelected = { [weak self, weak picker] circle in
                            picker?.dismiss(animated: true)
                            self?.sendShare(MessageShareCard.circle(id: circle.id, name: circle.name,
                                                                    placeCount: circle.placesCount ?? circle.places?.count,
                                                                    coverURL: circle.coverImage))
                        }
                        self.present(UINavigationController(rootViewController: picker), animated: true)
                    case .success:
                        self.showError("You don't have any circles to share yet.")
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }

    /// One of your saves, or any place from Apple Maps search
    private func sharePlace() {
        let search = PlaceSearchViewController()
        search.delegate = self
        present(UINavigationController(rootViewController: search), animated: true)
    }

    /// Where you are right now, with its street address when one is found
    private func shareLocation() {
        let loading = AlertPresenter.showLoading(message: "Finding your location...", from: self)
        LocationService.shared.getCurrentLocation(timeout: 10) { [weak self] location in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self else { return }
                    guard let location else {
                        self.showError("Couldn't find your location. Check that FavCircles can use it in Settings.")
                        return
                    }
                    CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            let mark = placemarks?.first
                            let address = [mark?.name, mark?.locality].compactMap { $0 }.joined(separator: ", ")
                            self.showConfirmation(title: "Share your location?",
                                                  message: address.isEmpty ? "Your current location goes into this chat." : address,
                                                  confirmTitle: "Share") { [weak self] in
                                self?.sendShare(MessageShareCard.location(location.coordinate, address: address))
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// The info screen's Notifications switch took: keep this chat's copy in step
    private func notificationsDidChange(_ enabled: Bool) {
        if let currentUserId = AuthService.shared.getUserId() {
            conversation?.notificationSettings?[currentUserId] = enabled
        }
    }

    @objc private func toggleNotifications() {
        guard let conversationId = conversation?.id else { return }
        
        let currentEnabled = conversation?.notificationsEnabled ?? true
        let newEnabled = !currentEnabled
        
        // Show loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: newEnabled ? "Enabling notifications..." : "Disabling notifications...", from: self)
        
        messagingManager.toggleNotifications(for: conversationId, enabled: newEnabled) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Update the conversation object
                        if let currentUserId = AuthService.shared.getUserId() {
                            self?.conversation?.notificationSettings?[currentUserId] = newEnabled
                        }
                        
                        // Update the navigation bar button
                        let bellImage = newEnabled ? "bell.fill" : "bell.slash.fill"
                        self?.navigationItem.rightBarButtonItem?.image = UIImage(systemName: bellImage)
                        
                        // Show confirmation
                        let message = newEnabled ? "Notifications enabled for this group" : "Notifications disabled for this group"
                        self?.showSuccess(message)
                        
                    case .failure(let error):
                        self?.showError(FriendlyError.message(for: error))
                    }
                }
            }
        }
    }
    
    
    private func deleteMessage(at indexPath: IndexPath) {
        guard let id = row(at: indexPath)?.messageId else { return }
        deleteMessage(id: id)
    }

    /// Gone from the chat at once, then from the server
    private func deleteMessage(id: String) {
        guard let conversationId = conversation?.id, messagesById[id] != nil else { return }
        apply(messages.filter { $0.id != id })
        messagingManager.deleteMessage(messageId: id, conversationId: conversationId)
    }

    private func editMessage(_ message: Message) {
        guard let conversationId = conversation?.id else { return }
        AlertPresenter.showTextInput(title: "Edit message", initialText: message.content, confirmTitle: "Save",
                                     from: self) { [weak self] newText in
            let trimmed = (newText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, !trimmed.isEmpty, trimmed != message.content else { return }
            self.messagingManager.editMessage(messageId: message.id, conversationId: conversationId,
                                              newContent: trimmed) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self?.refreshFromManager()
                    case .failure(let error): self?.showError(error)
                    }
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource
extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let flipped = CGAffineTransform(scaleX: 1, y: -1) // the table is inverted
        switch row(at: indexPath) {
        case .day(let title):
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatDayCell.reuseIdentifier, for: indexPath) as! ChatDayCell
            cell.configure(title: title)
            cell.transform = flipped
            return cell
        case .message(let bubble):
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! MessageCell
            cell.transform = flipped
            guard let message = messagesById[bubble.id] else { return cell }
            cell.delegate = self
            let layout = isPolished
                ? MessageCell.Layout(polished: true, startsRun: bubble.startsRun, endsRun: bubble.endsRun,
                                     receipt: receipt?.id == bubble.id ? receipt?.text : nil)
                : MessageCell.Layout.classic
            cell.configure(with: message, conversation: conversation, layout: layout)
            return cell
        case nil:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate
extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Allow deletion of user's own messages OR connection request messages
        guard let message = message(at: indexPath), message.isCurrentUserMessage || message.type == .connectionRequest else { return nil }
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completionHandler in
            self?.deleteMessage(at: indexPath)
            completionHandler(true)
        }
        
        deleteAction.image = UIImage(systemName: "trash")
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: - UITextViewDelegate
extension ChatViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        // No special handling needed
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // No special handling needed
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Only handle return key for sending messages
        if text == "\n" {
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendMessage()
                return false
            }
        }
        
        // Let UITextView handle all other text changes naturally
        return true
    }
    
    func textViewDidChange(_ textView: UITextView) {
        // Update placeholder visibility
        placeholderLabel.isHidden = !textView.text.isEmpty
        
        // Update send button state
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.tintColor = hasText ? Constants.Colors.primary : .systemGray3
        
        // Adjust text view height
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        textView.isScrollEnabled = size.height > 120
        
        // Force layout update to prevent RTI issues
        textView.layoutIfNeeded()
    }
}

// MARK: - ConnectionRequestMessageCellDelegate
extension ChatViewController: ConnectionRequestMessageCellDelegate {
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didAcceptConnectionId connectionId: String) {
        // Accept the connection request
        NetworkManager.shared.acceptConnection(connectionId) { [weak self] result in
            switch result {
            case .success:
                // Update the message to mark as handled
                DispatchQueue.main.async {
                    if let indexPath = self?.tableView.indexPath(for: cell) {
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                    self?.showSuccess("Connection request accepted")
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }
    
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didDeclineConnectionId connectionId: String) {
        // Decline the connection request
        NetworkManager.shared.declineConnection(connectionId) { [weak self] result in
            switch result {
            case .success:
                // Update the message to mark as handled
                DispatchQueue.main.async {
                    if let indexPath = self?.tableView.indexPath(for: cell) {
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                    self?.showSuccess("Connection request declined")
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }
    
    func connectionRequestCellDidTapDelete(_ cell: ConnectionRequestMessageCell) {
        // Find the index path for this cell
        if let indexPath = tableView.indexPath(for: cell) {
            // Delete the message
            deleteMessage(at: indexPath)
        }
    }
}

// MARK: - MessageCell
class MessageCell: UITableViewCell {
    
    // MARK: - Delegate
    weak var delegate: MessageCellDelegate?
    private var currentUserId: String?
    private var currentMessageId: String?

    /// How a bubble sits among its neighbours. `classic` is the chat as it
    /// was: every message its own bubble with its own time and avatar.
    struct Layout {
        var polished = false
        /// First of a run from one person (the name goes here in a group)
        var startsRun = true
        /// Last of a run (avatar, time and the bubble's tail go here)
        var endsRun = true
        /// "Read" / "Sent", on your newest message only
        var receipt: String?
        static let classic = Layout()
    }

    /// Deep enough that white words read on it in dark mode (the brand
    /// primary turns pale there)
    static let sentBubbleColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.44, blue: 0.80, alpha: 1)
            : UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1)
    }
    static let receivedBubbleColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(white: 0.93, alpha: 1)
    }
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        return label
    }()

    // Photo / postcard bubbles: the image sits between the caption and the
    // time. Zero height (and hidden) for text messages so nothing moves.
    private let mediaImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.isUserInteractionEnabled = true
        imageView.isHidden = true
        return imageView
    }()
    private var mediaHeightConstraint: NSLayoutConstraint!
    private var mediaWidthConstraint: NSLayoutConstraint!
    private var mediaTopConstraint: NSLayoutConstraint!
    private var currentImageURL: String?
    private var currentShareCard: MessageShareCard?
    private static let snapshotCache = NSCache<NSString, UIImage>()
    private var currentDrinkId: String?
    private var currentMotivationLineId: String?
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let senderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = Constants.Colors.tertiaryBackground
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var bubbleLeadingToAvatarConstraint: NSLayoutConstraint!
    private var bubbleLeadingToContentConstraint: NSLayoutConstraint!
    private var bubbleTrailingToAvatarConstraint: NSLayoutConstraint!
    private var avatarTrailingConstraint: NSLayoutConstraint!
    private var avatarLeadingConstraint: NSLayoutConstraint!
    private var bubbleTopConstraint: NSLayoutConstraint!
    private var bubbleBottomConstraint: NSLayoutConstraint!
    private var classicWidthConstraint: NSLayoutConstraint!
    private var polishedWidthConstraint: NSLayoutConstraint!
    private var messageTopToSenderConstraint: NSLayoutConstraint!
    private var messageTopToBubbleConstraint: NSLayoutConstraint!
    private var timeTopConstraint: NSLayoutConstraint!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(avatarImageView)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(senderLabel)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(mediaImageView)
        bubbleView.addSubview(timeLabel)
        
        // Add tap gesture to avatar
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(tapGesture)
        mediaImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaTapped)))
        bubbleView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(bubbleLongPressed(_:))))

        bubbleTopConstraint = bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)
        bubbleBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        classicWidthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        polishedWidthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78)
        messageTopToSenderConstraint = messageLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 2)
        messageTopToBubbleConstraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8)
        timeTopConstraint = timeLabel.topAnchor.constraint(equalTo: mediaImageView.bottomAnchor, constant: 4)

        mediaHeightConstraint = mediaImageView.heightAnchor.constraint(equalToConstant: 0)
        mediaWidthConstraint = mediaImageView.widthAnchor.constraint(equalToConstant: 240)
        mediaTopConstraint = mediaImageView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 0)
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        
        // Constraints for bubble with avatar on left (received messages)
        bubbleLeadingToAvatarConstraint = bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8)
        bubbleLeadingToContentConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        
        // Constraints for bubble with avatar on right (sent messages in direct conversations)
        bubbleTrailingToAvatarConstraint = bubbleView.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8)
        avatarTrailingConstraint = avatarImageView.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -8)
        avatarLeadingConstraint = avatarImageView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 8)
        
        NSLayoutConstraint.activate([
            // Avatar constraints (position will be controlled dynamically)
            avatarImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            
            bubbleTopConstraint,
            bubbleBottomConstraint,
            classicWidthConstraint,
            
            senderLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            senderLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            messageTopToSenderConstraint,
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            mediaTopConstraint,
            mediaHeightConstraint,
            mediaImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            mediaImageView.trailingAnchor.constraint(lessThanOrEqualTo: bubbleView.trailingAnchor, constant: -8),
            timeTopConstraint,
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with message: Message, conversation: Conversation?, layout: Layout = .classic) {
        currentMessageId = message.id
        messageLabel.text = message.displayContent
        timeLabel.text = message.formattedTime
        configureMedia(for: message)
        
        // Store user ID for tap handling (only for received messages)
        if !message.isCurrentUserMessage {
            self.currentUserId = message.senderId
        } else {
            self.currentUserId = nil
        }
        
        if message.isCurrentUserMessage {
            // Sent message
            bubbleView.backgroundColor = Constants.Colors.primary
            messageLabel.textColor = .white
            timeLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            senderLabel.isHidden = true
            avatarImageView.isHidden = true
            
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
            bubbleLeadingToAvatarConstraint.isActive = false
            bubbleLeadingToContentConstraint.isActive = false
            bubbleTrailingToAvatarConstraint.isActive = false
            avatarTrailingConstraint.isActive = false
            avatarLeadingConstraint.isActive = false
            
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner]
        } else {
            // Received message
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            timeLabel.textColor = .secondaryLabel
            
            // The sender's name, in group chats only (one-on-one there is
            // one other voice, and the bar already names them), once per run
            if conversation?.type == .group, layout.startsRun || !layout.polished,
               let senderName = message.senderDetails?.displayName {
                senderLabel.text = senderName
                senderLabel.isHidden = false
            } else {
                senderLabel.isHidden = true
            }
            
            // Show avatar for both group and direct conversations
            avatarImageView.isHidden = false
            
            if conversation?.type == .group {
                // Load sender avatar if available, otherwise use group avatar
                if let senderAvatar = message.senderDetails?.profilePicture, !senderAvatar.isEmpty {
                    ImageService.shared.loadImage(from: senderAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.circle.fill")
                        }
                    }
                } else if let groupAvatar = conversation?.avatar, !groupAvatar.isEmpty {
                    ImageService.shared.loadImage(from: groupAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.3.fill")
                        }
                    }
                } else {
                    // Show initials or default avatar
                    if let senderName = message.senderDetails?.displayName {
                        avatarImageView.image = AvatarPlaceholder.image(name: senderName, seed: message.senderId, diameter: 32)
                    } else {
                        avatarImageView.image = UIImage(systemName: "person.3.fill")
                    }
                }
            } else {
                // Direct conversation - load sender's avatar
                if let senderAvatar = message.senderDetails?.profilePicture, !senderAvatar.isEmpty {
                    ImageService.shared.loadImage(from: senderAvatar) { [weak avatarImageView] image in
                        DispatchQueue.main.async {
                            avatarImageView?.image = image ?? UIImage(systemName: "person.circle.fill")
                        }
                    }
                } else {
                    // Show initials or default avatar
                    if let senderName = message.senderDetails?.displayName {
                        avatarImageView.image = AvatarPlaceholder.image(name: senderName, seed: message.senderId, diameter: 32)
                    } else {
                        avatarImageView.image = UIImage(systemName: "person.circle.fill")
                    }
                }
            }
            
            // Use constraints with avatar on the left
            leadingConstraint.isActive = false
            bubbleLeadingToContentConstraint.isActive = false
            bubbleLeadingToAvatarConstraint.isActive = true
            bubbleTrailingToAvatarConstraint.isActive = false
            avatarTrailingConstraint.isActive = false
            avatarLeadingConstraint.isActive = true
            
            trailingConstraint.isActive = false
            bubbleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        // The words start under the name, or at the bubble's top without one.
        // A hidden name keeps no text, so it can't widen the bubble.
        if senderLabel.isHidden {
            senderLabel.text = nil
            messageTopToSenderConstraint.isActive = false
            messageTopToBubbleConstraint.isActive = true
        } else {
            messageTopToBubbleConstraint.isActive = false
            messageTopToSenderConstraint.isActive = true
        }
        applyLayout(layout, to: message)
    }

    /// The new look: runs of one person's messages sit close together, with
    /// the avatar, the time and the bubble's tail once, at the end
    private func applyLayout(_ layout: Layout, to message: Message) {
        guard layout.polished else {
            polishedWidthConstraint.isActive = false
            classicWidthConstraint.isActive = true
            return
        }
        classicWidthConstraint.isActive = false
        polishedWidthConstraint.isActive = true

        let isMine = message.isCurrentUserMessage
        bubbleView.layer.cornerRadius = 20
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.backgroundColor = isMine ? Self.sentBubbleColor : Self.receivedBubbleColor
        bubbleTopConstraint.constant = layout.startsRun ? 6 : 1
        bubbleBottomConstraint.constant = layout.endsRun ? -6 : -1
        if !layout.endsRun {
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                              .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        if !isMine { avatarImageView.isHidden = !layout.endsRun }

        if message.isDeleted { messageLabel.text = "Message deleted" }
        messageLabel.alpha = message.isDeleted ? 0.6 : 1

        if layout.endsRun {
            // The day divider says which day; the bubble says when
            let time = message.createdDate.map { Self.timeFormatter.string(from: $0) } ?? message.formattedTime
            timeLabel.text = [message.isEdited && !message.isDeleted ? "Edited" : nil, time, layout.receipt]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            timeTopConstraint.constant = 4
        } else {
            timeLabel.text = nil
            timeTopConstraint.constant = 0
        }
    }

    @objc private func bubbleLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let currentMessageId else { return }
        delegate?.didLongPressMessage(id: currentMessageId, from: bubbleView)
    }
    
    /// Shows the photo for image/postcard messages; collapses for text.
    private func configureMedia(for message: Message) {
        currentShareCard = nil
        if !message.isDeleted, let card = MessageShareCard(type: message.type, metadata: message.metadata) {
            configureShareCard(card)
            return
        }
        guard let urlString = message.displayImageURL else {
            mediaImageView.isHidden = true
            mediaImageView.image = nil
            currentImageURL = nil
            currentDrinkId = nil
            currentMotivationLineId = nil
            mediaHeightConstraint.constant = 0
            mediaWidthConstraint.isActive = false
            mediaTopConstraint.constant = 0
            return
        }
        mediaImageView.isHidden = false
        mediaHeightConstraint.constant = message.isPostcard ? 160 : 200
        mediaWidthConstraint.isActive = true
        mediaTopConstraint.constant = 6
        currentDrinkId = message.drinkId
        currentMotivationLineId = message.motivationLineId
        // Caption: the sender's note plus where the postcard is from.
        if message.isMotivation {
            messageLabel.text = [message.content ?? "", "📣 Tap to hear it from Coach Mane"]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        } else if message.isDrink {
            var lines = [message.content ?? ""]
            lines.append("🍸 \(message.drinkName ?? "A drink") · Tap to open the recipe")
            if let coins = message.drinkFavCoins {
                let noun = coins == "1" ? "FavCoin" : "FavCoins"
                lines.append(message.isCurrentUserMessage
                    ? "Came with \(coins) \(noun) 🌵 from FavCircles"
                    : "+\(coins) \(noun) 🌵 from FavCircles")
            }
            messageLabel.text = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        } else if message.isPostcard {
            var caption = message.content ?? ""
            if let place = message.postcardPlaceName, !place.isEmpty {
                caption = caption.isEmpty ? "📮 Postcard from \(place)" : "\(caption)\n📮 From \(place)"
            }
            messageLabel.text = caption.isEmpty ? "📮 Postcard" : caption
        } else {
            messageLabel.text = (message.content ?? "").isEmpty ? "📷 Photo" : message.content
        }
        currentImageURL = urlString
        mediaImageView.image = nil
        ImageService.shared.loadImage(from: urlString) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.currentImageURL == urlString else { return }
                self.mediaImageView.image = image
            }
        }
    }

    /// A shared place, circle or location: its photo (or a map), the name
    /// and address under it, tappable
    private func configureShareCard(_ card: MessageShareCard) {
        currentShareCard = card
        currentImageURL = nil
        currentDrinkId = nil
        currentMotivationLineId = nil
        messageLabel.text = card.caption
        mediaImageView.isHidden = false
        mediaHeightConstraint.constant = 150
        mediaWidthConstraint.isActive = true
        mediaTopConstraint.constant = 6
        mediaImageView.image = nil
        if let url = card.imageURL {
            ImageService.shared.loadImage(from: url) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.currentShareCard == card else { return }
                    self.mediaImageView.image = image
                }
            }
        } else if let coordinate = card.mapCoordinate {
            loadMapSnapshot(coordinate, for: card)
        } else {
            // A circle with no cover: a branded tile, so the card is still something to tap
            mediaImageView.image = Self.placeholderTile(symbol: "circle.circle.fill")
        }
    }

    private static func placeholderTile(symbol: String) -> UIImage {
        let size = CGSize(width: 240, height: 150)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            Constants.Colors.primary.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 54, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            icon?.draw(at: CGPoint(x: (size.width - (icon?.size.width ?? 0)) / 2, y: (size.height - (icon?.size.height ?? 0)) / 2))
        }
    }

    private func loadMapSnapshot(_ coordinate: CLLocationCoordinate2D, for card: MessageShareCard) {
        let key = "\(coordinate.latitude),\(coordinate.longitude)" as NSString
        if let cached = Self.snapshotCache.object(forKey: key) { mediaImageView.image = cached; return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        options.size = CGSize(width: 240, height: 150)
        options.traitCollection = traitCollection
        Task { @MainActor [weak self] in
            guard let snapshot = await MapSnapshotRenderer.shared.map(options) else { return }
            // The pin in the middle
            let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)
                let pin = UIImage(systemName: "mappin.circle.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                let point = snapshot.point(for: coordinate)
                pin?.draw(in: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28))
            }
            Self.snapshotCache.setObject(image, forKey: key)
            DispatchQueue.main.async {
                guard let self, self.currentShareCard == card else { return }
                self.mediaImageView.image = image
            }
        }
    }

    @objc private func mediaTapped() {
        if let currentShareCard {
            delegate?.didTapShareCard(currentShareCard)
            return
        }
        if let currentDrinkId {
            delegate?.didTapDrink(id: currentDrinkId)
            return
        }
        if let currentMotivationLineId {
            delegate?.didTapMotivation(lineId: currentMotivationLineId)
            return
        }
        guard let currentImageURL else { return }
        delegate?.didTapMessageImage(urlString: currentImageURL)
    }

    @objc private func avatarTapped() {
        guard let userId = currentUserId else { return }
        delegate?.didTapProfileImage(for: userId)
    }
    
}

// MARK: - MessageCellDelegate
extension ChatViewController: PlaceSearchDelegate {
    func didSelectExistingPlace(_ place: Place) {
        presentedViewController?.dismiss(animated: true)
        sendShare(MessageShareCard.place(id: place.globalPlaceId ?? place.id, name: place.name, address: place.address,
                                         photoURL: place.photos?.first, coordinate: place.location?.clLocation?.coordinate))
    }

    func didSelectPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String?,
                        website: String?, category: String?, description: String?) {
        presentedViewController?.dismiss(animated: true)
        sendShare(MessageShareCard.place(id: nil, name: name, address: address, photoURL: nil, coordinate: coordinate))
    }
}

extension ChatViewController: MessageCellDelegate {
    func didTapShareCard(_ card: MessageShareCard) {
        openShareTarget(card)
    }

    /// Opens what a share card points at; the info screen uses it too.
    func openShareTarget(_ card: MessageShareCard) {
        switch card.target {
        case .place(let id?, _):
            let loading = AlertPresenter.showLoading(message: "Opening...", from: self)
            PlaceService.shared.fetchPlaceById(id: id) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self else { return }
                        switch result {
                        case .success(let place):
                            self.navigationController?.pushViewController(PlaceDetailViewController(place: place), animated: true)
                        case .failure:
                            // Gone or not visible to you: Maps still knows where it is
                            if case .place(_, let coordinate?) = card.target { self.openInMaps(coordinate, name: card.title) }
                            else { self.showError("This place isn't available anymore.") }
                        }
                    }
                }
            }
        case .place(nil, let coordinate?):
            openInMaps(coordinate, name: card.title)
        case .place(nil, nil):
            break
        case .circle(let id):
            let loading = AlertPresenter.showLoading(message: "Opening...", from: self)
            CircleService.shared.fetchCircleById(id: id) { [weak self] result in
                DispatchQueue.main.async {
                    loading.dismiss(animated: true) {
                        guard let self else { return }
                        switch result {
                        case .success(let circle):
                            self.navigationController?.pushViewController(CircleDetailViewController(circle: circle), animated: true)
                        case .failure:
                            self.showError("You can't open this circle. It may be private or no longer shared.")
                        }
                    }
                }
            }
        case .location(let coordinate):
            openInMaps(coordinate, name: card.title)
        }
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)])
    }

    func didLongPressMessage(id: String, from sourceView: UIView) {
        guard let message = messagesById[id], !message.isDeleted else { return }
        var actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)] = []
        if let text = message.content, !text.isEmpty {
            actions.append((title: "Copy", style: .default, handler: { UIPasteboard.general.string = text }))
        }
        if message.isCurrentUserMessage {
            if message.type == .text {
                actions.append((title: "Edit", style: .default, handler: { [weak self] in self?.editMessage(message) }))
            }
            actions.append((title: "Delete", style: .destructive, handler: { [weak self] in self?.deleteMessage(id: id) }))
        }
        guard !actions.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AlertPresenter.showActionSheet(actions: actions, from: self, sourceView: sourceView, sourceRect: sourceView.bounds)
    }

    func didTapDrink(id: String) {
        // Home → Widgets → Make Me a Drink, opened on this recipe
        NotificationCenter.default.post(name: .navigateToHomeWidget, object: "drink", userInfo: ["drinkId": id])
    }

    func didTapMotivation(lineId: String) {
        // Home → Widgets → Motivation, showing that line (no send sheet)
        NotificationCenter.default.post(name: .navigateToHomeWidget, object: "motivation",
                                        userInfo: ["motivationLineId": lineId])
    }

    func didTapMessageImage(urlString: String) {
        let viewer = FullScreenImageViewController(imageURL: urlString)
        viewer.modalPresentationStyle = .fullScreen
        present(viewer, animated: true)
    }

    func didTapProfileImage(for userId: String) {
        Logger.debug("🔍 Profile image tapped for userId: \(userId)")
        
        // Check if the user is connected to navigate to their profile
        UserService.shared.fetchUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let user):
                    Logger.debug("✅ Found user: \(user.displayName)")
                    self.navigateToUserProfile(user: user)
                case .failure(let error):
                    Logger.debug("❌ Failed to fetch user profile: \(error)")
                    self.showError("Could not load user profile")
                }
            }
        }
    }
    
    private func navigateToUserProfile(user: User) {
        // Navigate to ProfileViewController just like in My Network tab
        let profileVC = ProfileViewController(user: user)
        navigationController?.pushViewController(profileVC, animated: true)
    }
}
import UIKit

class ChatViewController: UIViewController {
    
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
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        return button
    }()
    
    private let attachButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus.circle"), for: .normal)
        button.tintColor = .systemGray
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    var conversation: Conversation?
    private let messagingManager = MessagingManager.shared
    private var messageUpdateTimer: Timer?
    private var messages: [Message] = []
    private var keyboardHeight: CGFloat = 0
    private var messageInputBottomConstraint: NSLayoutConstraint!
    private let cellIdentifier = "MessageCell"
    private let connectionRequestCellIdentifier = "ConnectionRequestMessageCell"
    private var temporaryText: String = "" // Store text to prevent loss
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupTableView()
        setupMessageInput()
        setupKeyboardHandling(bottomConstraint: messageInputBottomConstraint, dismissOnTap: false)
        setupSubscribers()
        loadMessages()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        markMessagesAsRead()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        markMessagesAsRead()
        removeKeyboardHandling()
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = nil
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = conversation?.displayName ?? "Chat"
        
        // Add right bar button for conversation info
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showConversationInfo)
        )
        
        view.addSubview(tableView)
        view.addSubview(messageInputContainer)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: cellIdentifier)
        tableView.register(ConnectionRequestMessageCell.self, forCellReuseIdentifier: connectionRequestCellIdentifier)
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
        
        NSLayoutConstraint.activate([
            messageInputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageInputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
            
            placeholderLabel.leadingAnchor.constraint(equalTo: messageTextView.leadingAnchor, constant: 16),
            placeholderLabel.centerYAnchor.constraint(equalTo: messageTextView.centerYAnchor),
            
            sendButton.trailingAnchor.constraint(equalTo: messageInputContainer.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: messageInputContainer.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    
    private func setupSubscribers() {
        guard let conversationId = conversation?.id else { return }
        
        // Poll for message updates
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let messages = self.messagingManager.activeMessages[conversationId] {
                if messages.count != self.messages.count {
                    self.messages = messages
                    self.tableView.reloadData()
                    self.scrollToBottom(animated: true)
                }
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadMessages() {
        guard let conversationId = conversation?.id else { return }
        messagingManager.loadMessages(for: conversationId)
    }
    
    private func markMessagesAsRead() {
        guard let conversationId = conversation?.id else { return }
        
        let unreadMessageIds = messages
            .filter { !$0.isCurrentUserMessage && !$0.isRead }
            .map { $0.id }
        
        if !unreadMessageIds.isEmpty {
            messagingManager.markMessagesAsRead(conversationId: conversationId, messageIds: unreadMessageIds)
        }
    }
    
    // MARK: - Actions
    @objc private func sendMessage() {
        guard let conversationId = conversation?.id else { return }
        
        // Get text from temporary storage or text view
        let text = temporaryText.isEmpty ? (messageTextView.text ?? "") : temporaryText
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else { return }
        
        // Store the message text before clearing
        let messageToSend = trimmedText
        
        // Clear input and temporary storage
        DispatchQueue.main.async { [weak self] in
            self?.messageTextView.text = ""
            self?.temporaryText = ""
            self?.textViewDidChange(self?.messageTextView ?? UITextView())
            
            // Ensure the text view ends editing properly
            self?.messageTextView.resignFirstResponder()
            self?.messageTextView.becomeFirstResponder()
        }
        
        // Send message
        messagingManager.sendMessage(
            conversationId: conversationId,
            type: .text,
            content: messageToSend
        ) { [weak self] result in
            if case .failure(let error) = result {
                self?.showError(error.localizedDescription)
                // Restore text on failure
                DispatchQueue.main.async {
                    self?.messageTextView.text = messageToSend
                    self?.textViewDidChange(self?.messageTextView ?? UITextView())
                }
            }
        }
    }
    
    @objc private func showAttachmentOptions() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: "Share Circle", style: .default) { [weak self] _ in
            self?.shareCircle()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Share Place", style: .default) { [weak self] _ in
            self?.sharePlace()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Share Location", style: .default) { [weak self] _ in
            self?.shareLocation()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = attachButton
            popover.sourceRect = attachButton.bounds
        }
        
        present(actionSheet, animated: true)
    }
    
    @objc private func showConversationInfo() {
        // TODO: Show conversation info/settings
    }
    
    
    // MARK: - Helper Methods
    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
    
    private func shareCircle() {
        // TODO: Implement circle sharing
    }
    
    private func sharePlace() {
        // TODO: Implement place sharing
    }
    
    private func shareLocation() {
        // TODO: Implement location sharing
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func deleteMessage(at indexPath: IndexPath) {
        let messageIndex = messages.count - 1 - indexPath.row
        guard messageIndex >= 0 && messageIndex < messages.count else { return }
        
        let message = messages[messageIndex]
        guard let conversationId = conversation?.id else { return }
        
        // Store the message for potential restoration
        let deletedMessage = message
        
        // Remove from local array immediately for better UX
        messages.remove(at: messageIndex)
        
        // Animate the deletion
        tableView.performBatchUpdates({
            tableView.deleteRows(at: [indexPath], with: .fade)
        }) { [weak self] _ in
            // Call the messaging manager to delete from backend
            self?.messagingManager.deleteMessage(messageId: deletedMessage.id, conversationId: conversationId)
        }
    }
}

// MARK: - UITableViewDataSource
extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[messages.count - 1 - indexPath.row] // Reverse order due to inverted table
        
        if message.type == .connectionRequest {
            let cell = tableView.dequeueReusableCell(withIdentifier: connectionRequestCellIdentifier, for: indexPath) as! ConnectionRequestMessageCell
            cell.configure(with: message)
            cell.delegate = self
            cell.transform = CGAffineTransform(scaleX: 1, y: -1) // Invert cell
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! MessageCell
            cell.configure(with: message)
            cell.transform = CGAffineTransform(scaleX: 1, y: -1) // Invert cell
            return cell
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
        let message = messages[messages.count - 1 - indexPath.row]
        
        // Allow deletion of user's own messages OR connection request messages
        guard message.isCurrentUserMessage || message.type == .connectionRequest else { return nil }
        
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
        // Store current text when editing begins
        temporaryText = textView.text ?? ""
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // Ensure text is preserved when ending editing
        if textView.text.isEmpty && !temporaryText.isEmpty {
            textView.text = temporaryText
            textViewDidChange(textView)
        }
        temporaryText = ""
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle text changes properly
        guard let currentText = textView.text,
              let textRange = Range(range, in: currentText) else { return true }
        
        let updatedText = currentText.replacingCharacters(in: textRange, with: text)
        temporaryText = updatedText
        
        // Handle return key to send message
        if text == "\n" && !updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendMessage()
            return false
        }
        
        return true
    }
    
    func textViewDidChange(_ textView: UITextView) {
        // Store current text
        temporaryText = textView.text ?? ""
        
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
                if let indexPath = self?.tableView.indexPath(for: cell) {
                    let messageIndex = (self?.messages.count ?? 0) - 1 - indexPath.row
                    if messageIndex >= 0 && messageIndex < (self?.messages.count ?? 0) {
                        // Simply reload the cell - the button state will be updated based on the connection status
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                }
                
                // Show success message
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Success", message: "Connection request accepted", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError("Failed to accept connection: \(error.localizedDescription)")
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
                if let indexPath = self?.tableView.indexPath(for: cell) {
                    let messageIndex = (self?.messages.count ?? 0) - 1 - indexPath.row
                    if messageIndex >= 0 && messageIndex < (self?.messages.count ?? 0) {
                        // Simply reload the cell - the button state will be updated based on the connection status
                        self?.tableView.reloadRows(at: [indexPath], with: .fade)
                    }
                }
                
                // Show success message
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Success", message: "Connection request declined", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showError("Failed to decline connection: \(error.localizedDescription)")
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
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    
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
        
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(senderLabel)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(timeLabel)
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            
            senderLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            senderLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            messageLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 2),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            timeLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(with message: Message) {
        messageLabel.text = message.displayContent
        timeLabel.text = message.formattedTime
        
        if message.isCurrentUserMessage {
            // Sent message
            bubbleView.backgroundColor = Constants.Colors.primary
            messageLabel.textColor = .white
            timeLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            senderLabel.isHidden = true
            
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
            bubbleView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner]
        } else {
            // Received message
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            timeLabel.textColor = .secondaryLabel
            
            // Show sender name in group chats
            if let senderName = message.senderDetails?.displayName {
                senderLabel.text = senderName
                senderLabel.isHidden = false
            } else {
                senderLabel.isHidden = true
            }
            
            trailingConstraint.isActive = false
            leadingConstraint.isActive = true
            bubbleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        // Update constraints for sender label
        if senderLabel.isHidden {
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8).isActive = true
        }
    }
}
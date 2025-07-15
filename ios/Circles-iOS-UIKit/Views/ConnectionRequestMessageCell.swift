import UIKit

class ConnectionRequestMessageCell: UITableViewCell {
    static let identifier = "ConnectionRequestMessageCell"
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 25
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let acceptButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Accept", style: .primary)
        button.layer.cornerRadius = 8
        return button
    }()
    
    private let declineButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Decline", style: .secondary)
        button.backgroundColor = .systemGray5
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 8
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton.iconButton(systemName: "trash", pointSize: 16)
        button.tintColor = .systemRed
        return button
    }()
    
    private let buttonStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var connectionId: String?
    weak var delegate: ConnectionRequestMessageCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        setupConstraints()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.addSubview(containerView)
        containerView.addSubview(avatarImageView)
        containerView.addSubview(messageLabel)
        containerView.addSubview(timestampLabel)
        containerView.addSubview(deleteButton)
        
        buttonStackView.addArrangedSubview(declineButton)
        buttonStackView.addArrangedSubview(acceptButton)
        containerView.addSubview(buttonStackView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            avatarImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            avatarImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 50),
            avatarImageView.heightAnchor.constraint(equalToConstant: 50),
            
            messageLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            
            deleteButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 30),
            deleteButton.heightAnchor.constraint(equalToConstant: 30),
            
            timestampLabel.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            timestampLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            
            buttonStackView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            buttonStackView.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 12),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            buttonStackView.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    private func setupActions() {
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }
    
    @objc private func acceptTapped() {
        guard let connectionId = connectionId else { return }
        delegate?.connectionRequestCell(self, didAcceptConnectionId: connectionId)
    }
    
    @objc private func declineTapped() {
        guard let connectionId = connectionId else { return }
        delegate?.connectionRequestCell(self, didDeclineConnectionId: connectionId)
    }
    
    @objc private func deleteTapped() {
        delegate?.connectionRequestCellDidTapDelete(self)
    }
    
    func configure(with message: Message) {
        guard message.type == .connectionRequest,
              let metadata = message.metadata else { return }
        
        messageLabel.text = message.content
        timestampLabel.text = message.formattedTime
        
        // Extract metadata
        if let connectionIdValue = metadata["connectionId"] {
            self.connectionId = "\(connectionIdValue)"
        }
        
        if let senderName = metadata["senderName"] as? String {
            messageLabel.text = "\(senderName) wants to connect with you"
        }
        
        // Load avatar if available
        if let avatarUrl = metadata["senderAvatar"] as? String,
           let url = URL(string: avatarUrl) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.avatarImageView.image = image
                    }
                }
            }.resume()
        } else {
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
            avatarImageView.tintColor = .systemGray3
        }
        
        // Check if already handled by looking at connection status
        // The buttons should be disabled if the connection is no longer pending
        checkConnectionStatus()
    }
    
    private func checkConnectionStatus() {
        guard let connectionId = connectionId else {
            // No connection ID, disable buttons
            disableButtons(showMessage: "Connection request invalid")
            return
        }
        
        // Check the current connection status
        NetworkManager.shared.getConnectionStatus(connectionId: connectionId) { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case "accepted", "connected":
                    // Connection already accepted, disable buttons and show message
                    self?.disableButtons(showMessage: "Connection accepted")
                case "declined":
                    // Connection declined, disable buttons and show message
                    self?.disableButtons(showMessage: "Connection declined")
                case "pending":
                    // Still pending, keep buttons enabled
                    self?.enableButtons()
                default:
                    // Unknown status, disable buttons
                    self?.disableButtons(showMessage: "Connection request expired")
                }
            }
        }
    }
    
    private func enableButtons() {
        acceptButton.isEnabled = true
        declineButton.isEnabled = true
        acceptButton.alpha = 1.0
        declineButton.alpha = 1.0
        buttonStackView.isHidden = false
    }
    
    private func disableButtons(showMessage: String) {
        acceptButton.isEnabled = false
        declineButton.isEnabled = false
        acceptButton.alpha = 0.5
        declineButton.alpha = 0.5
        
        // Update the message to show status
        messageLabel.text = showMessage
        messageLabel.font = .systemFont(ofSize: 16, weight: .medium)
        messageLabel.textColor = .secondaryLabel
        
        // Hide the button stack
        buttonStackView.isHidden = true
    }
}

protocol ConnectionRequestMessageCellDelegate: AnyObject {
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didAcceptConnectionId connectionId: String)
    func connectionRequestCell(_ cell: ConnectionRequestMessageCell, didDeclineConnectionId connectionId: String)
    func connectionRequestCellDidTapDelete(_ cell: ConnectionRequestMessageCell)
}
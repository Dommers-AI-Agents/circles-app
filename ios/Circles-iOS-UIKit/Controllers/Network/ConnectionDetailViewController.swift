import UIKit

class ConnectionDetailViewController: UIViewController {
    
    // MARK: - Properties
    var connection: Connection?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 60
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let connectionDateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Message", for: .normal)
        button.setImage(UIImage(systemName: "message.fill"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.tintColor = .white
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 0)
        return button
    }()
    
    private let removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Remove Connection", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        configureView()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        title = "Connection"
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(connectionDateLabel)
        contentView.addSubview(messageButton)
        contentView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            profileImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 120),
            profileImageView.heightAnchor.constraint(equalToConstant: 120),
            
            nameLabel.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            emailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            connectionDateLabel.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 8),
            connectionDateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            connectionDateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            messageButton.topAnchor.constraint(equalTo: connectionDateLabel.bottomAnchor, constant: 24),
            messageButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            messageButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            messageButton.heightAnchor.constraint(equalToConstant: 48),
            
            removeButton.topAnchor.constraint(equalTo: messageButton.bottomAnchor, constant: 16),
            removeButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            removeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        messageButton.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeConnectionTapped), for: .touchUpInside)
    }
    
    private func configureView() {
        guard let connection = connection else { return }
        
        nameLabel.text = connection.connectedUser?.displayName ?? "Unknown User"
        emailLabel.text = connection.connectedUser?.email ?? ""
        
        if let acceptedAt = connection.acceptedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            connectionDateLabel.text = "Connected since \\(formatter.string(from: acceptedAt))"
        }
    }
    
    // MARK: - Actions
    @objc private func messageButtonTapped() {
        guard let userId = connection?.connectedUserId else { return }
        
        // Create or get conversation
        MessagingManager.shared.createOrGetDirectConversation(with: userId) { [weak self] result in
            switch result {
            case .success(let conversation):
                DispatchQueue.main.async {
                    let chatVC = ChatViewController()
                    chatVC.conversation = conversation
                    self?.navigationController?.pushViewController(chatVC, animated: true)
                }
            case .failure(let error):
                self?.showAlert(title: "Error", message: "Failed to start conversation: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func removeConnectionTapped() {
        let alert = UIAlertController(
            title: "Remove Connection",
            message: "Are you sure you want to remove this connection?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.removeConnection()
        })
        
        present(alert, animated: true)
    }
    
    private func removeConnection() {
        guard let connectionId = connection?.id else { return }
        
        NetworkManager.shared.removeConnection(connectionId: connectionId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showAlert(title: "Error", message: "Failed to remove connection: \\(error.localizedDescription)")
                } else {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
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
    
    private let circlesSectionLabel: UILabel = {
        let label = UILabel()
        label.text = "Circles"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let circlesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        layout.itemSize = CGSize(width: 140, height: 180)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let noCirclesLabel: UILabel = {
        let label = UILabel()
        label.text = "No circles to show"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // MARK: - Properties
    private var connectionCircles: [Circle] = []
    
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
        contentView.addSubview(circlesSectionLabel)
        contentView.addSubview(circlesCollectionView)
        contentView.addSubview(noCirclesLabel)
        
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
            
            circlesSectionLabel.topAnchor.constraint(equalTo: removeButton.bottomAnchor, constant: 32),
            circlesSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            circlesSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            circlesCollectionView.topAnchor.constraint(equalTo: circlesSectionLabel.bottomAnchor, constant: 12),
            circlesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            circlesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            circlesCollectionView.heightAnchor.constraint(equalToConstant: 200),
            
            noCirclesLabel.centerXAnchor.constraint(equalTo: circlesCollectionView.centerXAnchor),
            noCirclesLabel.centerYAnchor.constraint(equalTo: circlesCollectionView.centerYAnchor),
            noCirclesLabel.leadingAnchor.constraint(equalTo: circlesCollectionView.leadingAnchor),
            noCirclesLabel.trailingAnchor.constraint(equalTo: circlesCollectionView.trailingAnchor, constant: -20),
            
            circlesCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        messageButton.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeConnectionTapped), for: .touchUpInside)
        
        // Setup collection view
        circlesCollectionView.delegate = self
        circlesCollectionView.dataSource = self
        circlesCollectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
    }
    
    private func configureView() {
        guard let connection = connection else { return }
        
        // Display full name if available
        if let firstName = connection.connectedUser?.firstName, let lastName = connection.connectedUser?.lastName {
            nameLabel.text = "\(firstName) \(lastName)"
        } else if let firstName = connection.connectedUser?.firstName {
            nameLabel.text = firstName
        } else if let lastName = connection.connectedUser?.lastName {
            nameLabel.text = lastName
        } else {
            nameLabel.text = connection.connectedUser?.displayName ?? "Unknown User"
        }
        
        emailLabel.text = connection.connectedUser?.email ?? ""
        
        if let acceptedAt = connection.acceptedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            connectionDateLabel.text = "Connected since \\(formatter.string(from: acceptedAt))"
        }
        
        // Load connection's circles
        loadConnectionCircles()
    }
    
    private func loadConnectionCircles() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { 
            print("Error: No connection or current user ID found")
            return 
        }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
        print("Loading circles for user: \(userId)")
        
        // Use the network endpoint that properly checks connections
        struct UserCirclesResponse: Codable {
            let success: Bool
            let data: UserCirclesData
        }
        
        struct UserCirclesData: Codable {
            let user: User
            let circles: [Circle]
        }
        
        APIService.shared.request(
            endpoint: "network/user-circles/\(userId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.connectionCircles = response.data.circles
                    self?.circlesCollectionView.reloadData()
                    self?.noCirclesLabel.isHidden = !response.data.circles.isEmpty
                    self?.circlesCollectionView.isHidden = response.data.circles.isEmpty
                case .failure(let error):
                    print("Failed to load connection circles: \(error)")
                    self?.connectionCircles = []
                    self?.circlesCollectionView.reloadData()
                    self?.noCirclesLabel.isHidden = false
                    self?.circlesCollectionView.isHidden = true
                    
                    // Show specific error message
                    let errorMessage: String
                    if case .httpError(let statusCode, _) = error {
                        switch statusCode {
                        case 403:
                            errorMessage = "You are not connected to this user"
                        case 404:
                            errorMessage = "User not found"
                        default:
                            errorMessage = "Failed to load circles"
                        }
                    } else {
                        errorMessage = "Failed to load circles: \(error.localizedDescription)"
                    }
                    
                    self?.showAlert(title: "Error", message: errorMessage)
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func messageButtonTapped() {
        guard let connection = connection,
              let currentUserId = AuthService.shared.getUserId() else { return }
        let userId = connection.otherUserId(currentUserId: currentUserId)
        
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

// MARK: - UICollectionViewDataSource
extension ConnectionDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return connectionCircles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as! CircleCell
        let circle = connectionCircles[indexPath.item]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension ConnectionDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let circle = connectionCircles[indexPath.item]
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension ConnectionDetailViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
    }
}
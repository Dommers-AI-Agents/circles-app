import UIKit

protocol SuggestionTableViewCellDelegate: AnyObject {
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapPlace place: Place)
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapPlaceId placeId: String)
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapComments suggestion: Suggestion)
    func suggestionTableViewCell(_ cell: SuggestionTableViewCell, didTapLike suggestion: Suggestion)
}

class SuggestionTableViewCell: UITableViewCell {
    
    weak var delegate: SuggestionTableViewCellDelegate?
    private var suggestion: Suggestion?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = .tertiarySystemFill
        imageView.image = UIImage(systemName: "person.circle.fill")
        imageView.tintColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageLabel: TappableLabel = {
        let label = TappableLabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = Constants.Colors.primary.cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "mappin.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeAddressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeChevronImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let suggestionImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .tertiarySystemFill
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let likeButton: UIButton = {
        let button = UIButton.iconButton(systemName: "hand.thumbsup", pointSize: 16)
        button.tintColor = .secondaryLabel
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.setTitleColor(.secondaryLabel, for: .normal)
        return button
    }()
    
    private let commentsButton: UIButton = {
        let button = UIButton.iconButton(systemName: "bubble.left", pointSize: 16)
        button.tintColor = .secondaryLabel
        button.titleLabel?.font = .systemFont(ofSize: 14)
        button.setTitleColor(.secondaryLabel, for: .normal)
        return button
    }()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupView() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        
        containerView.addSubview(profileImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(timeLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(placeContainerView)
        containerView.addSubview(suggestionImageView)
        containerView.addSubview(likeButton)
        containerView.addSubview(commentsButton)
        
        placeContainerView.addSubview(placeIconImageView)
        placeContainerView.addSubview(placeNameLabel)
        placeContainerView.addSubview(placeAddressLabel)
        placeContainerView.addSubview(placeChevronImageView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            profileImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            profileImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            placeContainerView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            placeContainerView.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            placeContainerView.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
            placeContainerView.heightAnchor.constraint(equalToConstant: 56),
            
            placeIconImageView.leadingAnchor.constraint(equalTo: placeContainerView.leadingAnchor, constant: 8),
            placeIconImageView.centerYAnchor.constraint(equalTo: placeContainerView.centerYAnchor),
            placeIconImageView.widthAnchor.constraint(equalToConstant: 30),
            placeIconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            placeNameLabel.topAnchor.constraint(equalTo: placeContainerView.topAnchor, constant: 8),
            placeNameLabel.leadingAnchor.constraint(equalTo: placeIconImageView.trailingAnchor, constant: 8),
            placeNameLabel.trailingAnchor.constraint(equalTo: placeChevronImageView.leadingAnchor, constant: -8),
            
            placeAddressLabel.topAnchor.constraint(equalTo: placeNameLabel.bottomAnchor, constant: 2),
            placeAddressLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            placeAddressLabel.trailingAnchor.constraint(equalTo: placeNameLabel.trailingAnchor),
            
            placeChevronImageView.centerYAnchor.constraint(equalTo: placeContainerView.centerYAnchor),
            placeChevronImageView.trailingAnchor.constraint(equalTo: placeContainerView.trailingAnchor, constant: -8),
            placeChevronImageView.widthAnchor.constraint(equalToConstant: 16),
            placeChevronImageView.heightAnchor.constraint(equalToConstant: 16),
            
            suggestionImageView.topAnchor.constraint(equalTo: placeContainerView.bottomAnchor, constant: 8),
            suggestionImageView.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            suggestionImageView.trailingAnchor.constraint(equalTo: messageLabel.trailingAnchor),
            suggestionImageView.heightAnchor.constraint(equalToConstant: 200),
            
            likeButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            likeButton.heightAnchor.constraint(equalToConstant: 30),
            
            commentsButton.leadingAnchor.constraint(equalTo: likeButton.trailingAnchor, constant: 16),
            commentsButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Set up tap gesture for place container
        let placeTapGesture = UITapGestureRecognizer(target: self, action: #selector(placeTapped))
        placeContainerView.addGestureRecognizer(placeTapGesture)
        placeContainerView.isUserInteractionEnabled = true
        
        // Set up button actions
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        commentsButton.addTarget(self, action: #selector(commentsTapped), for: .touchUpInside)
        
        // Update bottom constraint based on content
        updateBottomConstraint()
    }
    
    private func updateBottomConstraint() {
        // Remove existing bottom constraint
        containerView.constraints.forEach { constraint in
            if constraint.firstAnchor == containerView.bottomAnchor {
                containerView.removeConstraint(constraint)
            }
        }
        
        // Position buttons based on content
        if !suggestionImageView.isHidden {
            likeButton.topAnchor.constraint(equalTo: suggestionImageView.bottomAnchor, constant: 8).isActive = true
            commentsButton.topAnchor.constraint(equalTo: suggestionImageView.bottomAnchor, constant: 8).isActive = true
        } else if !placeContainerView.isHidden {
            likeButton.topAnchor.constraint(equalTo: placeContainerView.bottomAnchor, constant: 8).isActive = true
            commentsButton.topAnchor.constraint(equalTo: placeContainerView.bottomAnchor, constant: 8).isActive = true
        } else {
            likeButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8).isActive = true
            commentsButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8).isActive = true
        }
        
        // Buttons are always at the bottom
        likeButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12).isActive = true
        commentsButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12).isActive = true
    }
    
    // MARK: - Configuration
    func configure(with suggestion: Suggestion) {
        self.suggestion = suggestion
        
        // User info
        nameLabel.text = suggestion.userDetails?.displayName ?? "Unknown User"
        timeLabel.text = suggestion.timeAgo
        
        // Load profile image
        if let urlString = suggestion.userDetails?.profilePicture {
            ImageService.shared.loadImage(from: urlString) { [weak self] image in
                DispatchQueue.main.async {
                    self?.profileImageView.image = image ?? UIImage(systemName: "person.circle.fill")
                }
            }
        }
        
        // Message with place mentions
        if let mentions = suggestion.mentionedPlaces, !mentions.isEmpty {
            messageLabel.configure(text: suggestion.message, placeMentions: mentions)
            messageLabel.delegate = self
        } else {
            messageLabel.text = suggestion.message
        }
        
        // Place info
        if let place = suggestion.placeDetails {
            placeContainerView.isHidden = false
            placeNameLabel.text = place.name
            placeAddressLabel.text = place.address
        } else {
            placeContainerView.isHidden = true
        }
        
        // Suggestion image
        if let imageUrl = suggestion.imageUrl {
            suggestionImageView.isHidden = false
            ImageService.shared.loadImage(from: imageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    self?.suggestionImageView.image = image
                }
            }
        } else {
            suggestionImageView.isHidden = true
        }
        
        // Likes count and state
        let likeCount = suggestion.likesCountDisplay
        if likeCount > 0 {
            likeButton.setTitle(" \(likeCount)", for: .normal)
        } else {
            likeButton.setTitle(" Like", for: .normal)
        }
        
        // Update like button appearance based on state
        if suggestion.isLikedByCurrentUser {
            likeButton.setImage(UIImage(systemName: "hand.thumbsup.fill"), for: .normal)
            likeButton.tintColor = Constants.Colors.primary
        } else {
            likeButton.setImage(UIImage(systemName: "hand.thumbsup"), for: .normal)
            likeButton.tintColor = .secondaryLabel
        }
        
        // Comments count
        let commentCount = suggestion.commentsCount ?? 0
        if commentCount > 0 {
            commentsButton.setTitle(" \(commentCount)", for: .normal)
        } else {
            commentsButton.setTitle(" Comment", for: .normal)
        }
        
        updateBottomConstraint()
    }
    
    // MARK: - Actions
    @objc private func placeTapped() {
        guard let place = suggestion?.placeDetails else { return }
        
        // Animate the tap
        UIView.animate(withDuration: 0.1, animations: {
            self.placeContainerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.placeContainerView.alpha = 0.8
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.placeContainerView.transform = .identity
                self.placeContainerView.alpha = 1.0
            }
        }
        
        delegate?.suggestionTableViewCell(self, didTapPlace: place)
    }
    
    @objc private func likeTapped() {
        guard let suggestion = suggestion else { return }
        delegate?.suggestionTableViewCell(self, didTapLike: suggestion)
    }
    
    @objc private func commentsTapped() {
        guard let suggestion = suggestion else { return }
        delegate?.suggestionTableViewCell(self, didTapComments: suggestion)
    }
    
    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        suggestionImageView.image = nil
        placeContainerView.isHidden = true
        suggestionImageView.isHidden = true
    }
}

// MARK: - TappableLabelDelegate
extension SuggestionTableViewCell: TappableLabelDelegate {
    func tappableLabel(_ label: TappableLabel, didTapPlaceWithId placeId: String) {
        delegate?.suggestionTableViewCell(self, didTapPlaceId: placeId)
    }
}
//
//  DailySummaryCardView.swift
//  Circles-iOS-UIKit
//
//  Created by Assistant on 8/22/2025.
//

import UIKit

protocol DailySummaryCardViewDelegate: AnyObject {
    func dailySummaryCardDidTapNewPlaces()
    func dailySummaryCardDidTapNewConnections()
    func dailySummaryCardDidTapUnreadMessages()
    func dailySummaryCardDidTapClose()
    func dailySummaryCardDidExpand()
    func dailySummaryCardDidCollapse()
}

class DailySummaryCardView: UIView {
    
    // MARK: - Properties
    weak var delegate: DailySummaryCardViewDelegate?
    private var isExpanded = false
    private var summaryData: [String: Any]?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let headerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "sparkles")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Your Daily Summary"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let expandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        button.tintColor = Constants.Colors.secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = Constants.Colors.tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let detailStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.isHidden = true
        stack.alpha = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        addSubview(containerView)
        
        // Header
        containerView.addSubview(headerStackView)
        headerStackView.addArrangedSubview(iconImageView)
        
        let titleStackView = UIStackView()
        titleStackView.axis = .vertical
        titleStackView.spacing = 2
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(dateLabel)
        headerStackView.addArrangedSubview(titleStackView)
        
        headerStackView.addArrangedSubview(UIView()) // Spacer
        headerStackView.addArrangedSubview(expandButton)
        headerStackView.addArrangedSubview(closeButton)
        
        // Summary
        containerView.addSubview(summaryLabel)
        
        // Details (hidden by default)
        containerView.addSubview(detailStackView)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),
            
            headerStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            headerStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            headerStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            expandButton.widthAnchor.constraint(equalToConstant: 24),
            expandButton.heightAnchor.constraint(equalToConstant: 24),
            
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            
            summaryLabel.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 8),
            summaryLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            detailStackView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            detailStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            detailStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            detailStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
        
        // Initial collapsed state
        summaryLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16).isActive = true
    }
    
    private func setupActions() {
        expandButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        containerView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Public Methods
    func configure(with data: [String: Any]) {
        self.summaryData = data
        
        // Set date
        if let date = data["date"] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            dateLabel.text = formatter.string(from: date)
        }
        
        // Build summary text
        var summaryParts: [String] = []
        
        if let newPlaces = data["newPlaces"] as? Int, newPlaces > 0 {
            summaryParts.append("📍 \(newPlaces) new place\(newPlaces > 1 ? "s" : "")")
        }
        
        if let newConnections = data["newConnections"] as? Int, newConnections > 0 {
            summaryParts.append("👥 \(newConnections) new connection\(newConnections > 1 ? "s" : "")")
        }
        
        if let unreadMessages = data["unreadMessages"] as? Int, unreadMessages > 0 {
            summaryParts.append("💬 \(unreadMessages) message\(unreadMessages > 1 ? "s" : "")")
        }
        
        if let placeComments = data["placeComments"] as? Int, 
           let placeLikes = data["placeLikes"] as? Int,
           placeComments > 0 || placeLikes > 0 {
            var activity: [String] = []
            if placeComments > 0 {
                activity.append("\(placeComments) comment\(placeComments > 1 ? "s" : "")")
            }
            if placeLikes > 0 {
                activity.append("\(placeLikes) like\(placeLikes > 1 ? "s" : "")")
            }
            summaryParts.append("❤️ \(activity.joined(separator: " & "))")
        }
        
        if summaryParts.isEmpty {
            summaryLabel.text = "No new activity today. Check back tomorrow!"
        } else {
            summaryLabel.text = summaryParts.joined(separator: " • ")
        }
        
        // Setup detail cards
        setupDetailCards(data)
    }
    
    private func setupDetailCards(_ data: [String: Any]) {
        // Clear existing cards
        detailStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // New places card
        if let newPlaces = data["newPlaces"] as? Int, newPlaces > 0 {
            let card = createDetailCard(
                emoji: "📍",
                title: "\(newPlaces) New Place\(newPlaces > 1 ? "s" : "")",
                subtitle: "From your network",
                color: Constants.Colors.primary
            ) { [weak self] in
                self?.delegate?.dailySummaryCardDidTapNewPlaces()
            }
            detailStackView.addArrangedSubview(card)
        }
        
        // New connections card
        if let newConnections = data["newConnections"] as? Int, newConnections > 0 {
            let card = createDetailCard(
                emoji: "👥",
                title: "\(newConnections) New Connection\(newConnections > 1 ? "s" : "")",
                subtitle: "Your network is growing",
                color: UIColor.systemBlue
            ) { [weak self] in
                self?.delegate?.dailySummaryCardDidTapNewConnections()
            }
            detailStackView.addArrangedSubview(card)
        }
        
        // Unread messages card
        if let unreadMessages = data["unreadMessages"] as? Int, unreadMessages > 0 {
            let card = createDetailCard(
                emoji: "💬",
                title: "\(unreadMessages) Unread Message\(unreadMessages > 1 ? "s" : "")",
                subtitle: "Check your messages",
                color: UIColor.systemOrange
            ) { [weak self] in
                self?.delegate?.dailySummaryCardDidTapUnreadMessages()
            }
            detailStackView.addArrangedSubview(card)
        }
        
        // Top contributors
        if let topContributors = data["topContributors"] as? [[String: Any]], !topContributors.isEmpty {
            let contributorsView = createContributorsView(topContributors)
            detailStackView.addArrangedSubview(contributorsView)
        }
    }
    
    private func createDetailCard(emoji: String, title: String, subtitle: String, color: UIColor, action: @escaping () -> Void) -> UIView {
        let card = UIView()
        card.backgroundColor = color.withAlphaComponent(0.1)
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let emojiLabel = UILabel()
        emojiLabel.text = emoji
        emojiLabel.font = UIFont.systemFont(ofSize: 24)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(emojiLabel)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = color
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = Constants.Colors.secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)
        
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Constants.Colors.tertiaryLabel
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chevron)
        
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 64),
            
            emojiLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            emojiLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: emojiLabel.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            chevron.widthAnchor.constraint(equalToConstant: 12)
        ])
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(detailCardTapped(_:)))
        card.addGestureRecognizer(tapGesture)
        card.isUserInteractionEnabled = true
        
        // Store the action in the card's tag (we'll use objc_setAssociatedObject for the closure)
        objc_setAssociatedObject(card, "action", action, .OBJC_ASSOCIATION_RETAIN)
        
        return card
    }
    
    private func createContributorsView(_ contributors: [[String: Any]]) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = "Top Contributors"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = Constants.Colors.secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        
        for contributor in contributors.prefix(3) {
            if let name = contributor["name"] as? String,
               let count = contributor["count"] as? Int {
                let label = UILabel()
                label.text = "\(name) added \(count) place\(count > 1 ? "s" : "")"
                label.font = UIFont.systemFont(ofSize: 13)
                label.textColor = Constants.Colors.label
                stackView.addArrangedSubview(label)
            }
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Actions
    @objc private func toggleExpanded() {
        isExpanded.toggle()
        
        UIView.animate(withDuration: 0.3) {
            self.expandButton.transform = self.isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
            self.summaryLabel.numberOfLines = self.isExpanded ? 0 : 2
            self.detailStackView.isHidden = !self.isExpanded
            self.detailStackView.alpha = self.isExpanded ? 1 : 0
            
            // Update constraints
            if self.isExpanded {
                self.summaryLabel.constraints.forEach { constraint in
                    if constraint.secondItem === self.containerView && constraint.secondAttribute == .bottom {
                        constraint.isActive = false
                    }
                }
            } else {
                self.summaryLabel.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor, constant: -16).isActive = true
            }
            
            self.layoutIfNeeded()
        }
        
        if isExpanded {
            delegate?.dailySummaryCardDidExpand()
        } else {
            delegate?.dailySummaryCardDidCollapse()
        }
    }
    
    @objc private func closeTapped() {
        delegate?.dailySummaryCardDidTapClose()
    }
    
    @objc private func cardTapped() {
        if !isExpanded {
            toggleExpanded()
        }
    }
    
    @objc private func detailCardTapped(_ gesture: UITapGestureRecognizer) {
        guard let card = gesture.view,
              let action = objc_getAssociatedObject(card, "action") as? () -> Void else { return }
        action()
    }
}
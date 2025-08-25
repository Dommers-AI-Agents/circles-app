import UIKit

class HelpTopicViewController: BaseViewController {
    
    // MARK: - Properties
    private let topic: HelpTopic
    
    // MARK: - UI Elements
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.backgroundColor = Constants.Colors.background
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()
    
    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var contentTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var videoButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Jump to Video Section")
        button.addTarget(self, action: #selector(jumpToVideoTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    
    private lazy var relatedTopicsLabel: UILabel = {
        let label = UILabel()
        label.text = "Related Topics"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var relatedTopicsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Init
    init(topic: HelpTopic) {
        self.topic = topic
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureContent()
    }
    
    // MARK: - Setup
    private func setupUI() {
        title = "Help"
        view.backgroundColor = Constants.Colors.background
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(categoryLabel)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(contentTextView)
        contentView.addSubview(videoButton)
        contentView.addSubview(relatedTopicsLabel)
        contentView.addSubview(relatedTopicsStackView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            categoryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Content
            contentTextView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            contentTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Video button
            videoButton.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 20),
            videoButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            videoButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            videoButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Related topics label
            relatedTopicsLabel.topAnchor.constraint(equalTo: videoButton.bottomAnchor, constant: 32),
            relatedTopicsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            relatedTopicsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Related topics stack
            relatedTopicsStackView.topAnchor.constraint(equalTo: relatedTopicsLabel.bottomAnchor, constant: 12),
            relatedTopicsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            relatedTopicsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            relatedTopicsStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }
    
    private func configureContent() {
        // Category
        categoryLabel.text = topic.category.rawValue.uppercased()
        categoryLabel.textColor = topic.category.color
        
        // Title
        titleLabel.text = topic.title
        
        // Subtitle
        subtitleLabel.text = topic.subtitle
        subtitleLabel.isHidden = topic.subtitle == nil
        
        // Content with markdown formatting
        let attributedContent = formatMarkdownContent(topic.content)
        contentTextView.attributedText = attributedContent
        
        // Video button
        if let timestamp = topic.videoTimestamp {
            videoButton.isHidden = false
            let minutes = Int(timestamp) / 60
            let seconds = Int(timestamp) % 60
            videoButton.setTitle("Jump to Video (\(String(format: "%d:%02d", minutes, seconds)))", for: .normal)
        }
        
        // Related topics
        setupRelatedTopics()
    }
    
    private func formatMarkdownContent(_ content: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 12
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: Constants.Colors.label,
            .paragraphStyle: paragraphStyle
        ]
        
        // Simple markdown parsing
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            var processedLine = line
            var attributes = baseAttributes
            
            // Headers
            if processedLine.hasPrefix("**") && processedLine.hasSuffix("**") {
                processedLine = processedLine.replacingOccurrences(of: "**", with: "")
                attributes[.font] = UIFont.systemFont(ofSize: 18, weight: .semibold)
            }
            
            // Bullet points
            if processedLine.hasPrefix("•") {
                let bulletParagraphStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                bulletParagraphStyle.firstLineHeadIndent = 0
                bulletParagraphStyle.headIndent = 20
                attributes[.paragraphStyle] = bulletParagraphStyle
            }
            
            // Numbered lists
            if processedLine.first?.isNumber == true && processedLine.contains(". ") {
                let listParagraphStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                listParagraphStyle.firstLineHeadIndent = 0
                listParagraphStyle.headIndent = 20
                attributes[.paragraphStyle] = listParagraphStyle
            }
            
            attributedString.append(NSAttributedString(string: processedLine + "\n", attributes: attributes))
        }
        
        return attributedString
    }
    
    private func setupRelatedTopics() {
        guard let relatedIds = topic.relatedTopics, !relatedIds.isEmpty else {
            relatedTopicsLabel.isHidden = true
            relatedTopicsStackView.isHidden = true
            return
        }
        
        for topicId in relatedIds {
            if let relatedTopic = HelpContentProvider.shared.topic(withId: topicId) {
                let button = createRelatedTopicButton(for: relatedTopic)
                relatedTopicsStackView.addArrangedSubview(button)
            }
        }
    }
    
    private func createRelatedTopicButton(for topic: HelpTopic) -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .left
        button.titleLabel?.numberOfLines = 0
        
        // Create container view for icon and text
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.backgroundColor = Constants.Colors.secondaryBackground
        container.layer.cornerRadius = 8
        
        let iconImageView = UIImageView(image: UIImage(systemName: topic.category.icon))
        iconImageView.tintColor = topic.category.color
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = topic.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = Constants.Colors.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconImageView)
        container.addSubview(titleLabel)
        button.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: button.topAnchor),
            container.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            
            iconImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        
        button.tag = topic.id.hashValue
        button.addTarget(self, action: #selector(relatedTopicTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    // MARK: - Actions
    @objc private func jumpToVideoTapped() {
        guard let timestamp = topic.videoTimestamp else { return }
        
        let tutorialVC = TutorialViewController()
        tutorialVC.startTime = timestamp
        let navController = UINavigationController(rootViewController: tutorialVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func relatedTopicTapped(_ sender: UIButton) {
        guard let relatedTopicId = topic.relatedTopics?.first(where: { 
            $0.hashValue == sender.tag 
        }),
        let relatedTopic = HelpContentProvider.shared.topic(withId: relatedTopicId) else { return }
        
        let detailVC = HelpTopicViewController(topic: relatedTopic)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
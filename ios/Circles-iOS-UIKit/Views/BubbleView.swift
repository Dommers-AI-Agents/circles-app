import UIKit

class BubbleView: UIView {
    
    // MARK: - Arrow Direction
    enum ArrowDirection {
        case top
        case bottom
        case left
        case right
    }
    
    // MARK: - Properties
    private var arrowDirection: ArrowDirection = .bottom
    private let arrowSize: CGSize = CGSize(width: 20, height: 10)
    private let bubbleCornerRadius: CGFloat = 12
    private let bubblePadding: CGFloat = 16
    private let maxWidth: CGFloat = 280
    
    // Callbacks
    var onNext: (() -> Void)?
    var onSkip: (() -> Void)?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .white.withAlphaComponent(0.9)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let buttonStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.setTitleColor(.white.withAlphaComponent(0.8), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = .white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Next", for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = .white
        button.layer.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let arrowView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        
        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 12
        
        // Setup container
        addSubview(containerView)
        containerView.layer.cornerRadius = bubbleCornerRadius
        containerView.clipsToBounds = true
        
        // Add arrow
        addSubview(arrowView)
        
        // Setup content
        containerView.addSubview(titleLabel)
        containerView.addSubview(descriptionLabel)
        containerView.addSubview(buttonStackView)
        
        buttonStackView.addArrangedSubview(skipButton)
        buttonStackView.addArrangedSubview(nextButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Container constraints
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: bubblePadding),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: bubblePadding),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -bubblePadding),
            
            // Description
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: bubblePadding),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -bubblePadding),
            
            // Buttons
            buttonStackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16),
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: bubblePadding),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -bubblePadding),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -bubblePadding),
            
            skipButton.heightAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        // Add button actions
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
    }
    
    // MARK: - Configuration
    func configure(title: String, description: String, arrowDirection: ArrowDirection) {
        titleLabel.text = title
        descriptionLabel.text = description
        self.arrowDirection = arrowDirection
        
        // Update arrow shape based on direction
        updateArrowShape()
        
        // Show arrow by default (will be hidden in centerInView if needed)
        arrowView.isHidden = false
    }
    
    // MARK: - Positioning
    func pointTo(_ targetView: UIView?, in parentView: UIView) {
        // If no target view, center the bubble
        guard let targetView = targetView else {
            centerInView(parentView)
            return
        }
        
        // Get target frame in parent coordinates
        let targetFrame = targetView.convert(targetView.bounds, to: parentView)
        
        // Calculate bubble position based on arrow direction
        var bubbleX: CGFloat = 0
        var bubbleY: CGFloat = 0
        var arrowX: CGFloat = 0
        var arrowY: CGFloat = 0
        
        // First, layout to get actual size
        layoutIfNeeded()
        let bubbleSize = containerView.bounds.size
        
        switch arrowDirection {
        case .top:
            // Bubble below target
            bubbleX = targetFrame.midX - bubbleSize.width / 2
            bubbleY = targetFrame.maxY + arrowSize.height + 8
            arrowX = targetFrame.midX - arrowSize.width / 2
            arrowY = targetFrame.maxY + 4
            
        case .bottom:
            // Bubble above target
            bubbleX = targetFrame.midX - bubbleSize.width / 2
            bubbleY = targetFrame.minY - bubbleSize.height - arrowSize.height - 8
            arrowX = targetFrame.midX - arrowSize.width / 2
            arrowY = targetFrame.minY - arrowSize.height - 4
            
        case .left:
            // Bubble to the right of target
            bubbleX = targetFrame.maxX + arrowSize.height + 8
            bubbleY = targetFrame.midY - bubbleSize.height / 2
            arrowX = targetFrame.maxX + 4
            arrowY = targetFrame.midY - arrowSize.width / 2
            
        case .right:
            // Bubble to the left of target
            bubbleX = targetFrame.minX - bubbleSize.width - arrowSize.height - 8
            bubbleY = targetFrame.midY - bubbleSize.height / 2
            arrowX = targetFrame.minX - arrowSize.height - 4
            arrowY = targetFrame.midY - arrowSize.width / 2
        }
        
        // Ensure bubble stays within parent bounds
        let parentBounds = parentView.bounds.inset(by: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16))
        bubbleX = max(parentBounds.minX, min(bubbleX, parentBounds.maxX - bubbleSize.width))
        bubbleY = max(parentBounds.minY, min(bubbleY, parentBounds.maxY - bubbleSize.height))
        
        // Position bubble
        frame = CGRect(origin: CGPoint(x: bubbleX, y: bubbleY), size: bubbleSize)
        
        // Position arrow relative to bubble
        let relativeArrowX = arrowX - bubbleX
        let relativeArrowY = arrowY - bubbleY
        
        // Update arrow constraints
        updateArrowPosition(x: relativeArrowX, y: relativeArrowY)
    }
    
    private func updateArrowShape() {
        // Remove existing sublayers
        arrowView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // Create arrow shape
        let arrowPath = UIBezierPath()
        let shapeLayer = CAShapeLayer()
        
        switch arrowDirection {
        case .top:
            arrowPath.move(to: CGPoint(x: 0, y: arrowSize.height))
            arrowPath.addLine(to: CGPoint(x: arrowSize.width / 2, y: 0))
            arrowPath.addLine(to: CGPoint(x: arrowSize.width, y: arrowSize.height))
            arrowView.frame.size = arrowSize
            
        case .bottom:
            arrowPath.move(to: CGPoint(x: 0, y: 0))
            arrowPath.addLine(to: CGPoint(x: arrowSize.width / 2, y: arrowSize.height))
            arrowPath.addLine(to: CGPoint(x: arrowSize.width, y: 0))
            arrowView.frame.size = arrowSize
            
        case .left:
            arrowPath.move(to: CGPoint(x: arrowSize.height, y: 0))
            arrowPath.addLine(to: CGPoint(x: 0, y: arrowSize.width / 2))
            arrowPath.addLine(to: CGPoint(x: arrowSize.height, y: arrowSize.width))
            arrowView.frame.size = CGSize(width: arrowSize.height, height: arrowSize.width)
            
        case .right:
            arrowPath.move(to: CGPoint(x: 0, y: 0))
            arrowPath.addLine(to: CGPoint(x: arrowSize.height, y: arrowSize.width / 2))
            arrowPath.addLine(to: CGPoint(x: 0, y: arrowSize.width))
            arrowView.frame.size = CGSize(width: arrowSize.height, height: arrowSize.width)
        }
        
        arrowPath.close()
        shapeLayer.path = arrowPath.cgPath
        shapeLayer.fillColor = Constants.Colors.primary.cgColor
        arrowView.layer.addSublayer(shapeLayer)
    }
    
    private func updateArrowPosition(x: CGFloat, y: CGFloat) {
        arrowView.frame.origin = CGPoint(x: x, y: y)
    }
    
    private func centerInView(_ parentView: UIView) {
        // Hide arrow when centered
        arrowView.isHidden = true
        
        // Layout to get size
        layoutIfNeeded()
        let bubbleSize = containerView.bounds.size
        
        // Center in parent view
        let centerX = (parentView.bounds.width - bubbleSize.width) / 2
        let centerY = (parentView.bounds.height - bubbleSize.height) / 2
        
        frame = CGRect(origin: CGPoint(x: centerX, y: centerY), size: bubbleSize)
    }
    
    // MARK: - Animations
    func show() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.alpha = 1
            self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.transform = .identity
            }
        }
    }
    
    func dismiss(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        } completion: { _ in
            completion?()
        }
    }
    
    // MARK: - Actions
    @objc private func skipTapped() {
        onSkip?()
    }
    
    @objc private func nextTapped() {
        onNext?()
    }
}
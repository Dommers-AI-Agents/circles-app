import UIKit

protocol AddFirstPlaceTutorialViewDelegate: AnyObject {
    func didTapGotIt()
    func didTapSkipTutorial()
}

class AddFirstPlaceTutorialView: UIView {
    
    // MARK: - Properties
    weak var delegate: AddFirstPlaceTutorialViewDelegate?
    private var spotlightLayer: CAShapeLayer?
    private var pulseAnimation: CABasicAnimation?
    private var arrowImageView: UIImageView?
    private var targetButton: UIView?
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.label.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: -4)
        view.layer.shadowOpacity = 0.15
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add Your First Favorite Place! 📍"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "This is the heart of Circles - saving and sharing your favorite spots"
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap the 'Add Place' button above to save restaurants, cafes, shops, and more to your circles"
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tipLabel: UILabel = {
        let label = UILabel()
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "lightbulb.fill")?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(x: 0, y: -2, width: 16, height: 16)
        
        let attributedString = NSMutableAttributedString(attachment: attachment)
        attributedString.append(NSAttributedString(string: " Tip: You can view all your saved places in your Profile tab", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]))
        
        label.attributedText = attributedString
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var gotItButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Got it! 👍", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = Constants.Colors.primary
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(gotItTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.0)
        
        addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(instructionLabel)
        containerView.addSubview(tipLabel)
        containerView.addSubview(gotItButton)
        containerView.addSubview(skipButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container - positioned at bottom like other overlays
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -30),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 30),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -30),
            
            // Instruction
            instructionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 30),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -30),
            
            // Tip
            tipLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16),
            tipLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 30),
            tipLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -30),
            
            // Got It Button
            gotItButton.topAnchor.constraint(equalTo: tipLabel.bottomAnchor, constant: 30),
            gotItButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            gotItButton.widthAnchor.constraint(equalToConstant: 200),
            gotItButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Skip Button
            skipButton.topAnchor.constraint(equalTo: gotItButton.bottomAnchor, constant: 12),
            skipButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            skipButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Public Methods
    func show(in parentView: UIView, targetButton: UIView) {
        self.targetButton = targetButton
        
        parentView.addSubview(self)
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parentView.topAnchor),
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
        ])
        
        // Initial state
        containerView.transform = CGAffineTransform(translationX: 0, y: 400)
        alpha = 0
        
        // Add spotlight effect
        addSpotlightEffect(for: targetButton, in: parentView)
        
        // Add animated arrow
        addAnimatedArrow(pointingTo: targetButton, in: parentView)
        
        // Add pulse animation to target button
        addPulseAnimation(to: targetButton)
        
        // Animate in
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            self.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                self.containerView.transform = .identity
            }
        }
    }
    
    func dismiss() {
        // Stop animations
        targetButton?.layer.removeAllAnimations()
        arrowImageView?.layer.removeAllAnimations()
        
        UIView.animate(withDuration: 0.3, animations: {
            self.containerView.transform = CGAffineTransform(translationX: 0, y: 400)
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                self.alpha = 0
            }) { _ in
                self.spotlightLayer?.removeFromSuperlayer()
                self.arrowImageView?.removeFromSuperview()
                self.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Animation Methods
    private func addSpotlightEffect(for targetView: UIView, in parentView: UIView) {
        // Create spotlight layer
        let spotlightLayer = CAShapeLayer()
        self.spotlightLayer = spotlightLayer
        
        // Create full screen path
        let fullPath = UIBezierPath(rect: parentView.bounds)
        
        // Get target frame in parent coordinates
        let targetFrame = parentView.convert(targetView.frame, from: targetView.superview)
        
        // Create expanded spotlight area (larger than button)
        let spotlightRect = targetFrame.insetBy(dx: -20, dy: -20)
        let spotlightPath = UIBezierPath(roundedRect: spotlightRect, cornerRadius: 25)
        
        // Cut out the spotlight area from full path
        fullPath.append(spotlightPath.reversing())
        
        spotlightLayer.path = fullPath.cgPath
        spotlightLayer.fillColor = UIColor.black.withAlphaComponent(0.3).cgColor
        spotlightLayer.fillRule = .evenOdd
        
        layer.insertSublayer(spotlightLayer, at: 0)
    }
    
    private func addAnimatedArrow(pointingTo targetView: UIView, in parentView: UIView) {
        // Create arrow image view
        let arrowImageView = UIImageView()
        self.arrowImageView = arrowImageView
        
        // Create arrow with configuration
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        arrowImageView.image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        arrowImageView.tintColor = Constants.Colors.primary
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(arrowImageView)
        
        // Position arrow below the target button
        let targetFrame = convert(targetView.frame, from: targetView.superview)
        NSLayoutConstraint.activate([
            arrowImageView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: targetFrame.midX),
            arrowImageView.topAnchor.constraint(equalTo: topAnchor, constant: targetFrame.maxY + 20)
        ])
        
        // Animate arrow bouncing
        let bounceAnimation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounceAnimation.values = [0, -10, 0, -5, 0]
        bounceAnimation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        bounceAnimation.duration = 1.5
        bounceAnimation.repeatCount = .infinity
        arrowImageView.layer.add(bounceAnimation, forKey: "bounce")
        
        // Add rotation animation
        let rotationAnimation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.values = [0, -0.05, 0, 0.05, 0]
        rotationAnimation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        rotationAnimation.duration = 2
        rotationAnimation.repeatCount = .infinity
        arrowImageView.layer.add(rotationAnimation, forKey: "rotation")
    }
    
    private func addPulseAnimation(to view: UIView) {
        // Scale animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 1.08
        scaleAnimation.duration = 0.8
        scaleAnimation.autoreverses = true
        scaleAnimation.repeatCount = .infinity
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        view.layer.add(scaleAnimation, forKey: "pulse")
        
        // Glow effect using shadow
        let glowAnimation = CABasicAnimation(keyPath: "shadowOpacity")
        glowAnimation.fromValue = 0.0
        glowAnimation.toValue = 0.8
        glowAnimation.duration = 0.8
        glowAnimation.autoreverses = true
        glowAnimation.repeatCount = .infinity
        glowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        view.layer.shadowColor = Constants.Colors.primary.cgColor
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 0)
        view.layer.add(glowAnimation, forKey: "glow")
    }
    
    // MARK: - Actions
    @objc private func gotItTapped() {
        delegate?.didTapGotIt()
        dismiss()
    }
    
    @objc private func skipTapped() {
        delegate?.didTapSkipTutorial()
        dismiss()
    }
}
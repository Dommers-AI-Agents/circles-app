import UIKit

// MARK: - ReactionPickerDelegate
protocol ReactionPickerDelegate: AnyObject {
    func reactionPicker(_ picker: ReactionPickerView, didSelectReaction reaction: ReactionStyle)
    func reactionPickerDidDismiss(_ picker: ReactionPickerView)
}

// MARK: - ReactionPickerView
class ReactionPickerView: UIView {
    
    // MARK: - Properties
    weak var delegate: ReactionPickerDelegate?
    private let reactions = ReactionStyle.allCases
    private var reactionButtons: [UIButton] = []
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 25
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.3)
        alpha = 0
        
        addSubview(containerView)
        containerView.addSubview(stackView)
        
        // Create reaction buttons
        for reaction in reactions {
            let button = createReactionButton(for: reaction)
            reactionButtons.append(button)
            stackView.addArrangedSubview(button)
        }
        
        NSLayoutConstraint.activate([
            // Container positioning
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -50),
            containerView.heightAnchor.constraint(equalToConstant: 60),
            containerView.widthAnchor.constraint(equalToConstant: CGFloat(reactions.count * 50 + 20)),
            
            // Stack view
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -15),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10)
        ])
    }
    
    private func createReactionButton(for reaction: ReactionStyle) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(reaction.rawValue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 28)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        button.addTarget(self, action: #selector(reactionButtonTapped(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(reactionButtonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(reactionButtonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        button.tag = reactions.firstIndex(of: reaction) ?? 0
        
        return button
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Actions
    @objc private func reactionButtonTapped(_ sender: UIButton) {
        guard sender.tag < reactions.count else { return }
        
        let reaction = reactions[sender.tag]
        selectionHapticGenerator.impactOccurred()
        
        // Animate selection
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = .identity
            }
        }
        
        // Notify delegate after animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.delegate?.reactionPicker(self, didSelectReaction: reaction)
            self.dismiss()
        }
    }
    
    @objc private func reactionButtonTouchDown(_ sender: UIButton) {
        hapticGenerator.prepare()
        hapticGenerator.impactOccurred()
        
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            sender.alpha = 0.8
        }
    }
    
    @objc private func reactionButtonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.alpha = 1.0
        }
    }
    
    @objc private func backgroundTapped() {
        dismiss()
        delegate?.reactionPickerDidDismiss(self)
    }
    
    // MARK: - Public Methods
    func show(from sourceView: UIView? = nil) {
        // Prepare haptic
        hapticGenerator.prepare()
        
        // Position near source view if provided
        if let sourceView = sourceView,
           let superview = sourceView.superview {
            let sourceFrame = superview.convert(sourceView.frame, to: self)
            containerView.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.minY - 40)
        }
        
        // Animate appearance with spring effect
        containerView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        
        UIView.animate(
            withDuration: ReactionAnimationSettings.pickerAppearDuration,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut,
            animations: {
                self.alpha = 1.0
                self.containerView.transform = .identity
            }
        )
        
        hapticGenerator.impactOccurred()
    }
    
    func dismiss() {
        UIView.animate(
            withDuration: ReactionAnimationSettings.pickerDismissDuration,
            animations: {
                self.alpha = 0
                self.containerView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            }
        ) { _ in
            self.removeFromSuperview()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ReactionPickerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only dismiss if tapping outside the container
        let location = touch.location(in: self)
        return !containerView.frame.contains(location)
    }
}

// MARK: - ReactionPillView
class ReactionPillView: UIView {
    
    // MARK: - Properties
    private let configuration: ReactionPillConfiguration
    
    // MARK: - UI Elements
    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    init(configuration: ReactionPillConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Configure appearance based on reaction style
        if let style = configuration.style {
            backgroundColor = style.backgroundColor.withAlphaComponent(0.15)
            layer.borderColor = style.backgroundColor.cgColor
            layer.borderWidth = configuration.isUserReaction ? 1.5 : 0
        } else {
            backgroundColor = Constants.Colors.secondaryBackground
        }
        
        layer.cornerRadius = 10
        
        // Set label
        label.text = configuration.displayText
        label.textColor = configuration.style?.backgroundColor ?? Constants.Colors.label
        
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}
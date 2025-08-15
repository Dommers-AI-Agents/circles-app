import UIKit

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
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            
            // Set minimum size constraints
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
    }
    
    // MARK: - Public Methods
    func updateConfiguration(_ newConfig: ReactionPillConfiguration) {
        label.text = newConfig.displayText
        
        if let style = newConfig.style {
            backgroundColor = style.backgroundColor.withAlphaComponent(0.15)
            layer.borderColor = style.backgroundColor.cgColor
            layer.borderWidth = newConfig.isUserReaction ? 1.5 : 0
            label.textColor = style.backgroundColor
        } else {
            backgroundColor = Constants.Colors.secondaryBackground
            layer.borderWidth = 0
            label.textColor = Constants.Colors.label
        }
    }
}
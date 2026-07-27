import UIKit

// MARK: - UIButton Factory Extension
// Eliminates redundant button configuration code throughout the app

extension UIButton {
    
    // MARK: - Primary Button Styles
    
    /// Creates a primary action button (filled background)
    static func primaryButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 6
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.enableTapFeedback()
        return button
    }
    
    /// Creates a secondary action button (outlined)
    static func secondaryButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Constants.Colors.primary, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = Constants.Colors.primary.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.enableTapFeedback()
        return button
    }
    
    /// Creates a danger/destructive button
    static func dangerButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.danger
        button.layer.cornerRadius = 6
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.enableTapFeedback()
        return button
    }
    
    // MARK: - Social Login Buttons
    
    /// Creates a social login button with icon
    static func socialButton(title: String, icon: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 25
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        // Add icon - try named asset first, fallback to system symbol
        if let image = UIImage(named: icon)?.withRenderingMode(.alwaysOriginal) {
            button.setImage(image, for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        } else if let systemImage = UIImage(systemName: icon) {
            button.setImage(systemImage, for: .normal)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        }
        
        button.enableTapFeedback()
        return button
    }
    
    /// Creates a Google Sign In button
    static func googleSignInButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Google", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray4.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        // Add Google icon
        if let systemImage = UIImage(systemName: "globe") {
            button.setImage(systemImage, for: .normal)
            button.tintColor = .black
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        }
        
        button.enableTapFeedback()
        return button
    }
    
    /// Creates a Facebook Sign In button  
    static func facebookSignInButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Facebook", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.231, green: 0.349, blue: 0.596, alpha: 1.0)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        // Add Facebook icon
        if let systemImage = UIImage(systemName: "person.2.circle") {
            button.setImage(systemImage, for: .normal)
            button.tintColor = .white
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        }
        
        button.enableTapFeedback()
        return button
    }
    
    /// Creates an Apple Sign In button
    static func appleSignInButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Sign in with Apple", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .black
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        // Add Apple icon
        if let systemImage = UIImage(systemName: "applelogo") {
            button.setImage(systemImage, for: .normal)
            button.tintColor = .white
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
        }
        
        button.enableTapFeedback()
        return button
    }
    
    // MARK: - Small Action Buttons
    
    /// Creates a small action button (e.g., for profile actions)
    static func smallActionButton(title: String, style: FactoryButtonStyle = .primary) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.layer.cornerRadius = 6
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        switch style {
        case .primary:
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = Constants.Colors.primary
        case .secondary:
            button.setTitleColor(Constants.Colors.primary, for: .normal)
            button.backgroundColor = .clear
            button.layer.borderWidth = 1
            button.layer.borderColor = Constants.Colors.primary.cgColor
        case .danger:
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = Constants.Colors.danger
        case .disabled:
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = .systemGray5
            button.isEnabled = false
        case .following:
            button.setTitleColor(.systemGray, for: .normal)
            button.backgroundColor = .systemGray5
            button.layer.borderWidth = 0
        }
        
        button.enableTapFeedback()
        return button
    }
    
    /// Creates an icon button
    static func iconButton(systemName: String, pointSize: CGFloat = 20) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = Constants.Colors.label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.enableTapFeedback()
        return button
    }
    
    // MARK: - Button Style Enum
    
    enum FactoryButtonStyle {
        case primary
        case secondary
        case danger
        case disabled
        case following
    }
    
    // MARK: - Convenience Methods
    
    private enum TapFeedbackKeys {
        static var savedTitle = "fc.button.savedTitle"
    }

    /// Updates button to loading state. Captures and restores its own title so
    /// callers don't have to (the previous version left the title cleared).
    func setLoading(_ isLoading: Bool) {
        self.isEnabled = !isLoading
        self.alpha = isLoading ? 0.6 : 1.0

        if isLoading {
            guard viewWithTag(999) == nil else { return } // already loading
            objc_setAssociatedObject(self, &TapFeedbackKeys.savedTitle, currentTitle, .OBJC_ASSOCIATION_RETAIN)

            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimating()
            spinner.color = self.titleColor(for: .normal)
            spinner.tag = 999 // Tag for removal

            self.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])

            self.setTitle("", for: .normal)
        } else {
            self.viewWithTag(999)?.removeFromSuperview()
            if let saved = objc_getAssociatedObject(self, &TapFeedbackKeys.savedTitle) as? String {
                self.setTitle(saved, for: .normal)
                objc_setAssociatedObject(self, &TapFeedbackKeys.savedTitle, nil, .OBJC_ASSOCIATION_RETAIN)
            }
        }
    }

    /// Adds instant tap feedback — a light haptic and a brief press dip — so a
    /// tap always registers visibly/physically even before a slow action (a
    /// network call, or the photo picker warming up) follows through. Called
    /// automatically by the factory methods; call it manually on non-factory
    /// buttons to opt in.
    func enableTapFeedback() {
        addTarget(self, action: #selector(_fcTapFeedbackDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(_fcTapFeedbackUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @objc private func _fcTapFeedbackDown() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.06, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    @objc private func _fcTapFeedbackUp() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = .identity
        }
    }
    
    /// Updates button style
    func setStyle(_ style: FactoryButtonStyle) {
        switch style {
        case .primary:
            self.setTitleColor(.white, for: .normal)
            self.backgroundColor = Constants.Colors.primary
            self.layer.borderWidth = 0
        case .secondary:
            self.setTitleColor(Constants.Colors.primary, for: .normal)
            self.backgroundColor = .clear
            self.layer.borderWidth = 1
            self.layer.borderColor = Constants.Colors.primary.cgColor
        case .danger:
            self.setTitleColor(.white, for: .normal)
            self.backgroundColor = Constants.Colors.danger
            self.layer.borderWidth = 0
        case .disabled:
            self.setTitleColor(.label, for: .normal)
            self.backgroundColor = .systemGray5
            self.layer.borderWidth = 0
            self.isEnabled = false
        case .following:
            self.setTitleColor(.systemGray, for: .normal)
            self.backgroundColor = .systemGray5
            self.layer.borderWidth = 0
        }
    }
}

// Example usage:
// Instead of:
// let button = UIButton(type: .system)
// button.setTitle("Sign In", for: .normal)
// button.setTitleColor(.white, for: .normal)
// button.backgroundColor = Constants.Colors.primary
// button.layer.cornerRadius = 6
// button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
// button.translatesAutoresizingMaskIntoConstraints = false
//
// Now you can write:
// let button = UIButton.primaryButton(title: "Sign In")
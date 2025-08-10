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
        }
        
        return button
    }
    
    /// Creates an icon button
    static func iconButton(systemName: String, pointSize: CGFloat = 20) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = Constants.Colors.label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    // MARK: - Button Style Enum
    
    enum FactoryButtonStyle {
        case primary
        case secondary
        case danger
        case disabled
    }
    
    // MARK: - Convenience Methods
    
    /// Updates button to loading state
    func setLoading(_ isLoading: Bool) {
        self.isEnabled = !isLoading
        self.alpha = isLoading ? 0.6 : 1.0
        
        if isLoading {
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
            // Title needs to be restored by caller
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
import UIKit
import ObjectiveC

// MARK: - Keyboard Handling Protocol
protocol KeyboardHandling: UIViewController {
    var keyboardHandlingScrollView: UIScrollView? { get }
    var keyboardHandlingBottomConstraint: NSLayoutConstraint? { get }
    func keyboardWillShow(keyboardHeight: CGFloat, animationDuration: Double)
    func keyboardWillHide(animationDuration: Double)
}

// MARK: - Default Implementation
extension KeyboardHandling {
    // Default implementation for scroll view - returns nil if not overridden
    var keyboardHandlingScrollView: UIScrollView? { nil }
    
    // Default implementation for bottom constraint - returns nil if not overridden
    var keyboardHandlingBottomConstraint: NSLayoutConstraint? { nil }
    
    // Default implementation for keyboard will show
    func keyboardWillShow(keyboardHeight: CGFloat, animationDuration: Double) {
        // Handle scroll view
        if let scrollView = keyboardHandlingScrollView {
            let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
            
            UIView.animate(withDuration: animationDuration) {
                scrollView.contentInset = contentInsets
                scrollView.scrollIndicatorInsets = contentInsets
                
                // Try to scroll to active field
                if let activeField = self.findFirstResponder(in: scrollView) {
                    var rect = activeField.frame
                    rect.size.height += 20 // Add padding
                    let convertedRect = scrollView.convert(rect, from: activeField.superview)
                    scrollView.scrollRectToVisible(convertedRect, animated: false)
                }
            }
        }
        
        // Handle bottom constraint
        if let bottomConstraint = keyboardHandlingBottomConstraint {
            UIView.animate(withDuration: animationDuration) {
                bottomConstraint.constant = -keyboardHeight
                self.view.layoutIfNeeded()
            }
        }
    }
    
    // Default implementation for keyboard will hide
    func keyboardWillHide(animationDuration: Double) {
        // Handle scroll view
        if let scrollView = keyboardHandlingScrollView {
            UIView.animate(withDuration: animationDuration) {
                scrollView.contentInset = .zero
                scrollView.scrollIndicatorInsets = .zero
            }
        }
        
        // Handle bottom constraint
        if let bottomConstraint = keyboardHandlingBottomConstraint {
            UIView.animate(withDuration: animationDuration) {
                bottomConstraint.constant = 0
                self.view.layoutIfNeeded()
            }
        }
    }
    
    // Helper method to find first responder
    private func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }
        
        for subview in view.subviews {
            if let firstResponder = findFirstResponder(in: subview) {
                return firstResponder
            }
        }
        
        return nil
    }
}

// MARK: - UIViewController Extension
private var keyboardObserversKey: UInt8 = 0
private var tapGestureKey: UInt8 = 0

extension UIViewController {
    
    // Storage for keyboard observers
    private var keyboardObservers: [Any]? {
        get {
            return objc_getAssociatedObject(self, &keyboardObserversKey) as? [Any]
        }
        set {
            objc_setAssociatedObject(self, &keyboardObserversKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // Storage for tap gesture
    private var keyboardDismissTapGesture: UITapGestureRecognizer? {
        get {
            return objc_getAssociatedObject(self, &tapGestureKey) as? UITapGestureRecognizer
        }
        set {
            objc_setAssociatedObject(self, &tapGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - Public Methods
    
    /// Sets up keyboard handling for the view controller
    /// - Parameters:
    ///   - scrollView: Optional scroll view to adjust when keyboard appears
    ///   - bottomConstraint: Optional bottom constraint to adjust when keyboard appears
    ///   - dismissOnTap: Whether to add tap gesture to dismiss keyboard (default: true)
    func setupKeyboardHandling(scrollView: UIScrollView? = nil,
                              bottomConstraint: NSLayoutConstraint? = nil,
                              dismissOnTap: Bool = true) {
        
        // Remove any existing observers
        removeKeyboardHandling()
        
        // Create notification observers
        let showObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardWillShow(notification: notification, scrollView: scrollView, bottomConstraint: bottomConstraint)
        }
        
        let hideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardWillHide(notification: notification, scrollView: scrollView, bottomConstraint: bottomConstraint)
        }
        
        // Store observers
        keyboardObservers = [showObserver, hideObserver]
        
        // Add tap gesture if requested
        if dismissOnTap {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
            tapGesture.cancelsTouchesInView = false
            
            if let scrollView = scrollView {
                scrollView.addGestureRecognizer(tapGesture)
            } else {
                view.addGestureRecognizer(tapGesture)
            }
            
            keyboardDismissTapGesture = tapGesture
        }
    }
    
    /// Removes keyboard handling observers and gestures
    func removeKeyboardHandling() {
        // Remove observers
        if let observers = keyboardObservers {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            keyboardObservers = nil
        }
        
        // Remove tap gesture
        if let tapGesture = keyboardDismissTapGesture {
            tapGesture.view?.removeGestureRecognizer(tapGesture)
            keyboardDismissTapGesture = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func handleKeyboardWillShow(notification: Notification,
                                       scrollView: UIScrollView?,
                                       bottomConstraint: NSLayoutConstraint?) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        
        // If conforming to KeyboardHandling protocol, use custom implementation
        if let keyboardHandling = self as? KeyboardHandling {
            keyboardHandling.keyboardWillShow(keyboardHeight: keyboardHeight, animationDuration: animationDuration)
        } else {
            // Use default implementation
            defaultKeyboardWillShow(keyboardHeight: keyboardHeight,
                                  animationDuration: animationDuration,
                                  scrollView: scrollView,
                                  bottomConstraint: bottomConstraint)
        }
    }
    
    private func handleKeyboardWillHide(notification: Notification,
                                       scrollView: UIScrollView?,
                                       bottomConstraint: NSLayoutConstraint?) {
        guard let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        // If conforming to KeyboardHandling protocol, use custom implementation
        if let keyboardHandling = self as? KeyboardHandling {
            keyboardHandling.keyboardWillHide(animationDuration: animationDuration)
        } else {
            // Use default implementation
            defaultKeyboardWillHide(animationDuration: animationDuration,
                                  scrollView: scrollView,
                                  bottomConstraint: bottomConstraint)
        }
    }
    
    private func defaultKeyboardWillShow(keyboardHeight: CGFloat,
                                       animationDuration: Double,
                                       scrollView: UIScrollView?,
                                       bottomConstraint: NSLayoutConstraint?) {
        // Handle scroll view
        if let scrollView = scrollView {
            let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
            
            UIView.animate(withDuration: animationDuration) {
                scrollView.contentInset = contentInsets
                scrollView.scrollIndicatorInsets = contentInsets
                
                // Try to scroll to active field
                if let activeField = self.view.firstResponder {
                    var rect = activeField.frame
                    rect.size.height += 20 // Add padding
                    let convertedRect = scrollView.convert(rect, from: activeField.superview)
                    scrollView.scrollRectToVisible(convertedRect, animated: false)
                }
            }
        }
        
        // Handle bottom constraint
        if let bottomConstraint = bottomConstraint {
            UIView.animate(withDuration: animationDuration) {
                bottomConstraint.constant = -keyboardHeight
                self.view.layoutIfNeeded()
            }
        }
    }
    
    private func defaultKeyboardWillHide(animationDuration: Double,
                                       scrollView: UIScrollView?,
                                       bottomConstraint: NSLayoutConstraint?) {
        // Handle scroll view
        if let scrollView = scrollView {
            UIView.animate(withDuration: animationDuration) {
                scrollView.contentInset = .zero
                scrollView.scrollIndicatorInsets = .zero
            }
        }
        
        // Handle bottom constraint
        if let bottomConstraint = bottomConstraint {
            UIView.animate(withDuration: animationDuration) {
                bottomConstraint.constant = 0
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc private func dismissKeyboardOnTap() {
        view.endEditing(true)
    }
}

// MARK: - UIView Extension for First Responder
extension UIView {
    var firstResponder: UIView? {
        if isFirstResponder {
            return self
        }
        
        for subview in subviews {
            if let firstResponder = subview.firstResponder {
                return firstResponder
            }
        }
        
        return nil
    }
}
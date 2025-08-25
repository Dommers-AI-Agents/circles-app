import UIKit

// MARK: - UIViewController Alert Extension
// This extension provides convenient methods for showing alerts
// Used throughout the app for consistent error and success messaging

extension UIViewController {
    
    /// Shows an error alert with a localized error message
    func showError(_ error: Error) {
        // Filter out duplicate request errors - these are intentional and don't need user notification
        let errorMessage = error.localizedDescription
        if errorMessage == "Duplicate request prevented" || 
           errorMessage == "Network error: Duplicate request prevented" ||
           errorMessage.contains("Duplicate request prevented") {
            return
        }
        AlertPresenter.showError(error, from: self)
    }
    
    /// Shows an error alert with a custom message
    func showError(_ message: String) {
        AlertPresenter.showError(message: message, from: self)
    }
    
    /// Shows a success alert with a custom message
    func showSuccess(_ message: String, completion: (() -> Void)? = nil) {
        AlertPresenter.showSuccess(message: message, from: self, completion: completion)
    }
    
    /// Shows a confirmation alert
    func showConfirmation(
        title: String,
        message: String,
        confirmTitle: String = "Yes",
        cancelTitle: String = "Cancel",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        AlertPresenter.showConfirmation(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            isDestructive: isDestructive,
            from: self,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }
    
    /// Shows an action sheet
    func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)],
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil
    ) {
        AlertPresenter.showActionSheet(
            title: title,
            message: message,
            actions: actions,
            from: self,
            sourceView: sourceView,
            sourceRect: sourceRect
        )
    }
    
    /// Shows a text input alert
    func showTextInput(
        title: String,
        message: String? = nil,
        placeholder: String? = nil,
        initialText: String? = nil,
        keyboardType: UIKeyboardType = .default,
        onSubmit: @escaping (String?) -> Void
    ) {
        AlertPresenter.showTextInput(
            title: title,
            message: message,
            placeholder: placeholder,
            initialText: initialText,
            keyboardType: keyboardType,
            from: self,
            onSubmit: onSubmit
        )
    }
    
    /// Shows a loading alert
    func showLoading(message: String = "Loading...") -> UIAlertController {
        return AlertPresenter.showLoading(message: message, from: self)
    }
    
    /// Finds the topmost presented view controller in the hierarchy
    func topMostViewController() -> UIViewController {
        var topController = self
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        return topController
    }
    
    /// Checks if any view controller in the hierarchy is presenting another view controller
    func isAnyViewControllerPresenting() -> Bool {
        // Check if this view controller is presenting something
        if self.presentedViewController != nil {
            return true
        }
        
        // Check parent view controllers
        var currentVC: UIViewController? = self
        while let parent = currentVC?.parent {
            if parent.presentedViewController != nil {
                return true
            }
            currentVC = parent
        }
        
        // Check navigation controller if we're in one
        if let navController = self.navigationController,
           navController.presentedViewController != nil {
            return true
        }
        
        // Check tab bar controller if we're in one
        if let tabController = self.tabBarController,
           tabController.presentedViewController != nil {
            return true
        }
        
        // Check the root view controller
        if let window = UIApplication.shared.windows.first,
           let rootVC = window.rootViewController,
           rootVC.presentedViewController != nil {
            return true
        }
        
        return false
    }
    
    /// Gets the root view controller for fallback presentation
    func getRootViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first,
              let rootVC = window.rootViewController else {
            return nil
        }
        
        // Don't use topMostViewController as it might return an alert
        // Instead, get the base root VC that can present new content
        
        // If root VC is presenting something, we need to be careful
        if let presented = rootVC.presentedViewController {
            // If it's presenting an alert, we can still use the root VC
            if presented is UIAlertController {
                return rootVC
            }
            
            // If it's presenting a navigation or tab controller, use that
            if presented is UINavigationController || presented is UITabBarController {
                return presented
            }
            
            // Otherwise, use the root VC
            return rootVC
        }
        
        // Root VC is not presenting anything, safe to use
        return rootVC
    }
}
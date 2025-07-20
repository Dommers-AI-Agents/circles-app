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
}
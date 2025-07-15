import UIKit

/// A utility class for presenting standardized alerts throughout the app
/// Eliminates redundant UIAlertController creation code
class AlertPresenter {
    
    // MARK: - Error Alerts
    
    /// Shows a standard error alert with OK button
    static func showError(_ error: Error, from viewController: UIViewController) {
        showError(title: "Error", message: error.localizedDescription, from: viewController)
    }
    
    /// Shows a standard error alert with custom message
    static func showError(
        title: String = "Error",
        message: String,
        from viewController: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        viewController.present(alert, animated: true)
    }
    
    // MARK: - Success Alerts
    
    /// Shows a success alert with OK button
    static func showSuccess(
        title: String = "Success",
        message: String,
        from viewController: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        viewController.present(alert, animated: true)
    }
    
    // MARK: - Confirmation Alerts
    
    /// Shows a confirmation alert with Yes/No or custom buttons
    static func showConfirmation(
        title: String,
        message: String,
        confirmTitle: String = "Yes",
        cancelTitle: String = "Cancel",
        isDestructive: Bool = false,
        from viewController: UIViewController,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let confirmStyle: UIAlertAction.Style = isDestructive ? .destructive : .default
        alert.addAction(UIAlertAction(title: confirmTitle, style: confirmStyle) { _ in
            onConfirm()
        })
        
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            onCancel?()
        })
        
        viewController.present(alert, animated: true)
    }
    
    // MARK: - Action Sheets
    
    /// Shows an action sheet with multiple options
    static func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        actions: [(title: String, style: UIAlertAction.Style, handler: () -> Void)],
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil
    ) {
        let actionSheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        
        for action in actions {
            actionSheet.addAction(UIAlertAction(title: action.title, style: action.style) { _ in
                action.handler()
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad requires popover presentation
        if let popover = actionSheet.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceRect ?? sourceView.bounds
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        viewController.present(actionSheet, animated: true)
    }
    
    // MARK: - Input Alerts
    
    /// Shows an alert with a text input field
    static func showTextInput(
        title: String,
        message: String? = nil,
        placeholder: String? = nil,
        initialText: String? = nil,
        keyboardType: UIKeyboardType = .default,
        from viewController: UIViewController,
        onSubmit: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.text = initialText
            textField.keyboardType = keyboardType
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            let text = alert.textFields?.first?.text
            onSubmit(text)
        })
        
        viewController.present(alert, animated: true)
    }
    
    // MARK: - Loading Alerts
    
    /// Shows a loading alert that can be dismissed programmatically
    static func showLoading(
        message: String = "Loading...",
        from viewController: UIViewController
    ) -> UIAlertController {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        
        alert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20)
        ])
        
        viewController.present(alert, animated: true)
        return alert
    }
}

// MARK: - UIViewController Extension for Convenience
// Note: These convenience methods are available directly on AlertPresenter class
// to avoid potential conflicts with existing UIViewController extensions

// Example usage:
// Instead of:
// let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
// alert.addAction(UIAlertAction(title: "OK", style: .default))
// self.present(alert, animated: true)
//
// Now you can write:
// self.showError(error)
// or
// AlertPresenter.showError(error, from: self)
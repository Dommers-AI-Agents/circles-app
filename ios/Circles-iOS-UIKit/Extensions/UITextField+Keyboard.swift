import UIKit

extension UITextField {
    /// Adds a Done button toolbar to the keyboard
    func addDoneButtonOnKeyboard() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(resignFirstResponder))
        
        toolbar.items = [flexSpace, doneButton]
        self.inputAccessoryView = toolbar
    }
}

extension UITextView {
    /// Adds a Done button toolbar to the keyboard
    func addDoneButtonOnKeyboard() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(resignFirstResponder))
        
        toolbar.items = [flexSpace, doneButton]
        self.inputAccessoryView = toolbar
    }
}

extension UISearchBar {
    /// Adds a Done button toolbar to the keyboard
    func addDoneButtonOnKeyboard() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(resignFirstResponder))
        
        toolbar.items = [flexSpace, doneButton]
        self.inputAccessoryView = toolbar
    }
}
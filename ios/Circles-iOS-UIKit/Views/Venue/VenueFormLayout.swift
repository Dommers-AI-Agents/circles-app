import UIKit

/// Shared scaffolding for the store-owner forms (offer, announcement): a
/// keyboard-aware scrolling column of labeled fields, and an inline problem
/// line that sits directly above the save button — never an alert, and never
/// hidden under the keyboard.
enum VenueFormLayout {

    /// Adds a scroll view pinned above the keyboard and returns its content stack
    static func install(in view: UIView) -> UIStackView {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        return stack
    }

    /// Bold title, the control, and an optional grey hint under it
    static func field(_ title: String, _ control: UIView, hint: UILabel? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)

        let box = UIStackView(arrangedSubviews: [label, control])
        box.axis = .vertical
        box.spacing = 6
        if let hint { box.addArrangedSubview(hint) }
        return box
    }

    static func textField(placeholder: String, text: String?, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.keyboardType = keyboard
        field.autocapitalizationType = keyboard == .numberPad ? .none : .sentences
        field.clearButtonMode = .whileEditing
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.returnKeyType = .done
        return field
    }

    /// A multi-line box that looks like the rounded text fields around it
    static func textView(text: String?) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 6
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.isScrollEnabled = false
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        return textView
    }

    static func hintLabel(_ text: String? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    /// Red line above the save button; hidden until there's a problem
    static func problemLabel() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }

    /// Title on the left, a switch on the right
    static func toggleRow(_ title: String, _ toggle: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        toggle.onTintColor = Constants.Colors.primary
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.alignment = .center
        return row
    }
}

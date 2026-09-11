import UIKit

/// Half-sheet description editor for a venue owner, with the text view
/// pinned to the keyboard layout guide — immune to the scroll/keyboard
/// geometry that made in-card editing type-blind.
final class OwnerDescriptionEditorViewController: BaseViewController {

    var initialText = ""
    var onSave: ((String) -> Void)?

    private let textView: UITextView = {
        let view = UITextView()
        view.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        view.textColor = Constants.Colors.label
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 10
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override var loadsDataOnViewDidLoad: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Description"
        view.backgroundColor = Constants.Colors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        textView.text = initialText
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.medium),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Constants.Spacing.small)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss(animated: true) { [onSave] in
            onSave?(text)
        }
    }
}

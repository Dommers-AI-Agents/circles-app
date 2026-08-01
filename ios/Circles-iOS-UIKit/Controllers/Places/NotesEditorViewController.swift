import UIKit

/// Edits the one note a save can carry: a private note, visible only to the
/// person who saved the place.
///
/// The public-notes field this screen used to offer is gone. A note meant for
/// other people is a comment on the venue — comments live on the canonical
/// place record, so everyone who opens that venue sees them, not just people
/// browsing the circle the note happened to sit in.
class NotesEditorViewController: BaseViewController {

    // MARK: - Properties
    private var privateNotesText: String
    private let isPrivateNotesEnabled: Bool

    var onSave: ((String) -> Void)?

    // MARK: - UI Elements
    private let privateLabel: UILabel = {
        let label = UILabel()
        label.text = "Private note"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.gray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let privateHintLabel: UILabel = {
        let label = UILabel()
        label.text = "Only you can see this. To share your thoughts about this place, leave a comment instead."
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = Constants.Colors.gray.withAlphaComponent(0.8)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let privateTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = .systemGray6
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private let privateNotesDisabledLabel: UILabel = {
        let label = UILabel()
        label.text = "Private notes are only available for places you add"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.gray.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init
    init(privateNotes: String, isPrivateNotesEnabled: Bool) {
        self.privateNotesText = privateNotes
        self.isPrivateNotesEnabled = isPrivateNotesEnabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration
    override var loadsDataOnViewDidLoad: Bool { false }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        privateTextView.text = privateNotesText
        setupKeyboardHandling(dismissOnTap: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isPrivateNotesEnabled {
            privateTextView.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "Private Note"
        addNavigationBarButton(title: "Cancel", position: .left, action: #selector(cancelTapped))
        addNavigationBarButton(title: "Save", position: .right, action: #selector(saveTapped))

        [privateLabel, privateHintLabel].forEach { view.addSubview($0) }
        view.addSubview(isPrivateNotesEnabled ? privateTextView : privateNotesDisabledLabel)

        NSLayoutConstraint.activate([
            privateLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            privateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            privateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            privateHintLabel.topAnchor.constraint(equalTo: privateLabel.bottomAnchor, constant: 4),
            privateHintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            privateHintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        let editor = isPrivateNotesEnabled ? privateTextView : privateNotesDisabledLabel
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: privateHintLabel.bottomAnchor, constant: 12),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            editor.heightAnchor.constraint(equalToConstant: isPrivateNotesEnabled ? 160 : 60)
        ])
    }

    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let privateNotes = isPrivateNotesEnabled
            ? (privateTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        onSave?(privateNotes)
        dismiss(animated: true)
    }
}

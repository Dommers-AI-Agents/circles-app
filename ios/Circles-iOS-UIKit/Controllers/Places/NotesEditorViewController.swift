import UIKit

class NotesEditorViewController: BaseViewController {
    
    // MARK: - Properties
    private var publicNotesText: String
    private var privateNotesText: String
    private let isPrivateNotesEnabled: Bool
    
    var onSave: ((String, String) -> Void)?
    
    // MARK: - UI Elements
    private let publicLabel: UILabel = {
        let label = UILabel()
        label.text = "Public Notes (visible to all)"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.gray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let publicTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = .systemGray6
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let privateLabel: UILabel = {
        let label = UILabel()
        label.text = "Private Notes (only visible to you)"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.gray
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
    init(publicNotes: String, privateNotes: String, isPrivateNotesEnabled: Bool) {
        self.publicNotesText = publicNotes
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
        configureTextViews()
        // Setup keyboard handling for text views
        setupKeyboardHandling(dismissOnTap: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publicTextView.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Edit Notes"
        setupNavigationBar()
        setupTextViews()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        addNavigationBarButton(title: "Cancel", position: .left, action: #selector(cancelTapped))
        addNavigationBarButton(title: "Save", position: .right, action: #selector(saveTapped))
    }
    
    private func setupTextViews() {
        [publicLabel, publicTextView, privateLabel].forEach { view.addSubview($0) }
        
        if isPrivateNotesEnabled {
            view.addSubview(privateTextView)
        } else {
            view.addSubview(privateNotesDisabledLabel)
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            publicLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            publicLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            publicLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            publicTextView.topAnchor.constraint(equalTo: publicLabel.bottomAnchor, constant: 8),
            publicTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            publicTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            publicTextView.heightAnchor.constraint(equalToConstant: 120),
            
            privateLabel.topAnchor.constraint(equalTo: publicTextView.bottomAnchor, constant: 20),
            privateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            privateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        let bottomView = isPrivateNotesEnabled ? privateTextView : privateNotesDisabledLabel
        NSLayoutConstraint.activate([
            bottomView.topAnchor.constraint(equalTo: privateLabel.bottomAnchor, constant: 8),
            bottomView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomView.heightAnchor.constraint(equalToConstant: isPrivateNotesEnabled ? 120 : 60)
        ])
    }
    
    private func configureTextViews() {
        publicTextView.text = publicNotesText
        
        if isPrivateNotesEnabled {
            privateTextView.text = privateNotesText
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveTapped() {
        let publicNotes = publicTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let privateNotes = isPrivateNotesEnabled ? (privateTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : ""
        
        onSave?(publicNotes, privateNotes)
        dismiss(animated: true)
    }
}
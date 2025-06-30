import UIKit

protocol CreateSuggestionViewControllerDelegate: AnyObject {
    func didCreateSuggestion(_ suggestion: Suggestion)
}

class CreateSuggestionViewController: UIViewController {
    
    weak var delegate: CreateSuggestionViewControllerDelegate?
    private var selectedPlace: Place?
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let messageTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Share your experience with your network..."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let characterCountLabel: UILabel = {
        let label = UILabel()
        label.text = "0/500"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addPlaceButton: UIButton = {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Select Place"
        config.image = UIImage(systemName: "magnifyingglass")
        config.imagePlacement = .leading
        config.imagePadding = 8
        config.baseBackgroundColor = .tertiarySystemGroupedBackground
        config.baseForegroundColor = Constants.Colors.primary
        config.cornerStyle = .medium
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Removed place display UI elements - places are now inserted as links directly in the message
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        setupKeyboardObservers()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        messageTextView.becomeFirstResponder()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemGroupedBackground
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(messageTextView)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(characterCountLabel)
        contentView.addSubview(addPlaceButton)
        // Remove selectedPlaceView since we're inserting links directly
        
        messageTextView.delegate = self
        addPlaceButton.addTarget(self, action: #selector(addPlaceTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            messageTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            messageTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            messageTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            placeholderLabel.topAnchor.constraint(equalTo: messageTextView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: messageTextView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(equalTo: messageTextView.trailingAnchor, constant: -16),
            
            characterCountLabel.topAnchor.constraint(equalTo: messageTextView.bottomAnchor, constant: 8),
            characterCountLabel.trailingAnchor.constraint(equalTo: messageTextView.trailingAnchor),
            
            addPlaceButton.topAnchor.constraint(equalTo: characterCountLabel.bottomAnchor, constant: 16),
            addPlaceButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addPlaceButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            addPlaceButton.heightAnchor.constraint(equalToConstant: 50),
            addPlaceButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    private func setupNavigationBar() {
        title = "Share Suggestion"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Share",
            style: .done,
            target: self,
            action: #selector(shareTapped)
        )
        
        updateShareButtonState()
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func shareTapped() {
        guard let message = messageTextView.text, !message.isEmpty else { return }
        
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        SuggestionService.shared.createSuggestion(
            message: message,
            placeId: selectedPlace?.id
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let suggestion):
                    self?.delegate?.didCreateSuggestion(suggestion)
                    self?.dismiss(animated: true)
                case .failure(let error):
                    self?.navigationItem.rightBarButtonItem?.isEnabled = true
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func addPlaceTapped() {
        let placePickerVC = PlacePickerViewController()
        placePickerVC.delegate = self
        let navVC = UINavigationController(rootViewController: placePickerVC)
        present(navVC, animated: true)
    }
    
    @objc private func removePlaceTapped() {
        // No longer needed since we insert places as links directly
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = keyboardFrame.height
        scrollView.scrollIndicatorInsets.bottom = keyboardFrame.height
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        scrollView.contentInset.bottom = 0
        scrollView.scrollIndicatorInsets.bottom = 0
    }
    
    // MARK: - Helpers
    private func updateShareButtonState() {
        let hasText = !(messageTextView.text?.isEmpty ?? true)
        navigationItem.rightBarButtonItem?.isEnabled = hasText
    }
    
    private func updateCharacterCount() {
        let count = messageTextView.text.count
        characterCountLabel.text = "\(count)/500"
        characterCountLabel.textColor = count > 500 ? .systemRed : .secondaryLabel
    }
    
    private func updatePlaceDisplay() {
        // No longer needed since we insert places as links directly
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextViewDelegate
extension CreateSuggestionViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateCharacterCount()
        updateShareButtonState()
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)
        return updatedText.count <= 500
    }
}

// MARK: - PlacePickerViewControllerDelegate
extension CreateSuggestionViewController: PlacePickerViewControllerDelegate {
    func placePickerViewController(_ controller: PlacePickerViewController, didSelectPlace place: Place) {
        // Insert place as hyperlink in the message
        let placeLinkText = " [\(place.name)]"
        
        // Get current text and cursor position
        if let selectedRange = messageTextView.selectedTextRange {
            let cursorPosition = messageTextView.offset(from: messageTextView.beginningOfDocument, to: selectedRange.start)
            let currentText = messageTextView.text ?? ""
            
            // Insert the place link at cursor position
            let index = currentText.index(currentText.startIndex, offsetBy: cursorPosition)
            var newText = currentText
            newText.insert(contentsOf: placeLinkText, at: index)
            
            // Update text view
            messageTextView.text = newText
            
            // Move cursor after the inserted link
            if let newPosition = messageTextView.position(from: messageTextView.beginningOfDocument, offset: cursorPosition + placeLinkText.count) {
                messageTextView.selectedTextRange = messageTextView.textRange(from: newPosition, to: newPosition)
            }
        } else {
            // If no selection, append to end
            messageTextView.text = (messageTextView.text ?? "") + placeLinkText
        }
        
        // Store the selected place for backend processing
        selectedPlace = place
        
        // Update UI
        placeholderLabel.isHidden = !messageTextView.text.isEmpty
        updateCharacterCount()
        updateShareButtonState()
        
        controller.dismiss(animated: true)
    }
}
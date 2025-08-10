import UIKit

protocol CreateSuggestionViewControllerDelegate: AnyObject {
    func didCreateSuggestion(_ suggestion: Suggestion)
}

class CreateSuggestionViewController: BaseViewController {
    
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
    
    // Place display is handled by the button state change
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        // Use standard keyboard handling with tap-to-dismiss
        setupKeyboardHandling(scrollView: scrollView, dismissOnTap: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        messageTextView.becomeFirstResponder()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardHandling()
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
        // If a place is already selected, show options
        if selectedPlace != nil {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            
            alert.addAction(UIAlertAction(title: "Change Place", style: .default) { [weak self] _ in
                self?.showPlacePicker()
            })
            
            alert.addAction(UIAlertAction(title: "Remove Place", style: .destructive) { [weak self] _ in
                self?.removeSelectedPlace()
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            // For iPad
            if let popover = alert.popoverPresentationController {
                popover.sourceView = addPlaceButton
                popover.sourceRect = addPlaceButton.bounds
            }
            
            present(alert, animated: true)
        } else {
            showPlacePicker()
        }
    }
    
    private func showPlacePicker() {
        let placePickerVC = PlacePickerViewController()
        placePickerVC.delegate = self
        let navVC = UINavigationController(rootViewController: placePickerVC)
        present(navVC, animated: true)
    }
    
    private func removeSelectedPlace() {
        selectedPlace = nil
        
        // Reset button to original state
        var config = addPlaceButton.configuration
        config?.title = "Select Place"
        config?.subtitle = nil
        config?.image = UIImage(systemName: "magnifyingglass")
        config?.baseBackgroundColor = .tertiarySystemGroupedBackground
        config?.baseForegroundColor = Constants.Colors.primary
        addPlaceButton.configuration = config
        
        updateShareButtonState()
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
        // Store the selected place for backend processing
        selectedPlace = place
        
        // Update the button to show the selected place
        var config = addPlaceButton.configuration
        config?.title = place.name
        config?.subtitle = "Tap to change"
        config?.image = UIImage(systemName: "checkmark.circle.fill")
        config?.baseBackgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        config?.baseForegroundColor = Constants.Colors.primary
        addPlaceButton.configuration = config
        
        // Update UI
        updateShareButtonState()
        
        controller.dismiss(animated: true)
    }
}
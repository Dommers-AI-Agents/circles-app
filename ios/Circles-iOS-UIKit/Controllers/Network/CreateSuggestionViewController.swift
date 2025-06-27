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
        config.title = "Add Place"
        config.image = UIImage(systemName: "mappin.circle")
        config.imagePlacement = .leading
        config.imagePadding = 8
        config.baseBackgroundColor = .tertiarySystemGroupedBackground
        config.baseForegroundColor = Constants.Colors.primary
        config.cornerStyle = .medium
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let selectedPlaceView: UIView = {
        let view = UIView()
        view.backgroundColor = .tertiarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeAddressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let removePlaceButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
        contentView.addSubview(selectedPlaceView)
        
        selectedPlaceView.addSubview(placeNameLabel)
        selectedPlaceView.addSubview(placeAddressLabel)
        selectedPlaceView.addSubview(removePlaceButton)
        
        messageTextView.delegate = self
        addPlaceButton.addTarget(self, action: #selector(addPlaceTapped), for: .touchUpInside)
        removePlaceButton.addTarget(self, action: #selector(removePlaceTapped), for: .touchUpInside)
        
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
            
            selectedPlaceView.topAnchor.constraint(equalTo: addPlaceButton.bottomAnchor, constant: 16),
            selectedPlaceView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            selectedPlaceView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            selectedPlaceView.heightAnchor.constraint(equalToConstant: 72),
            selectedPlaceView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            
            placeNameLabel.topAnchor.constraint(equalTo: selectedPlaceView.topAnchor, constant: 16),
            placeNameLabel.leadingAnchor.constraint(equalTo: selectedPlaceView.leadingAnchor, constant: 16),
            placeNameLabel.trailingAnchor.constraint(equalTo: removePlaceButton.leadingAnchor, constant: -8),
            
            placeAddressLabel.topAnchor.constraint(equalTo: placeNameLabel.bottomAnchor, constant: 4),
            placeAddressLabel.leadingAnchor.constraint(equalTo: placeNameLabel.leadingAnchor),
            placeAddressLabel.trailingAnchor.constraint(equalTo: placeNameLabel.trailingAnchor),
            
            removePlaceButton.centerYAnchor.constraint(equalTo: selectedPlaceView.centerYAnchor),
            removePlaceButton.trailingAnchor.constraint(equalTo: selectedPlaceView.trailingAnchor, constant: -16),
            removePlaceButton.widthAnchor.constraint(equalToConstant: 30),
            removePlaceButton.heightAnchor.constraint(equalToConstant: 30)
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
        selectedPlace = nil
        updatePlaceDisplay()
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
        if let place = selectedPlace {
            selectedPlaceView.isHidden = false
            addPlaceButton.isHidden = true
            placeNameLabel.text = place.name
            placeAddressLabel.text = place.address
        } else {
            selectedPlaceView.isHidden = true
            addPlaceButton.isHidden = false
        }
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
        selectedPlace = place
        updatePlaceDisplay()
        controller.dismiss(animated: true)
    }
}
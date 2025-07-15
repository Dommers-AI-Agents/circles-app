import UIKit

protocol CirclePickerSliderViewDelegate: AnyObject {
    func circlePickerDidSelectCircle(_ circle: Circle, notes: String?)
    func circlePickerDidSelectCreateNew(notes: String?)
    func circlePickerDidCancel()
}

class CirclePickerSliderView: UIView {
    
    // MARK: - Properties
    weak var delegate: CirclePickerSliderViewDelegate?
    private var circles: [Circle] = []
    private var selectedIndex: Int = 0
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.layer.cornerRadius = 20
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let handleView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGray3
        view.layer.cornerRadius = 2.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Add to Circle"
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let pickerView: UIPickerView = {
        let picker = UIPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()
    
    private let notesLabel: UILabel = {
        let label = UILabel()
        label.text = "Add Notes (optional)"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let notesTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.cornerRadius = 8
        textView.backgroundColor = .secondarySystemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = ""
        textView.returnKeyType = .done
        return textView
    }()
    
    private let addButton: UIButton = {
        let button = UIButton.primaryButton(title: "Add to Circle")
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.layer.cornerRadius = 12
        return button
    }()
    
    private let cancelButton: UIButton = {
        let button = UIButton.smallActionButton(title: "Cancel", style: .secondary)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.systemGray, for: .normal)
        button.backgroundColor = .clear
        return button
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        addSubview(containerView)
        containerView.addSubview(handleView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(pickerView)
        containerView.addSubview(notesLabel)
        containerView.addSubview(notesTextView)
        containerView.addSubview(addButton)
        containerView.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            // Container
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 500),
            
            // Handle
            handleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            handleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 40),
            handleView.heightAnchor.constraint(equalToConstant: 5),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Picker
            pickerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            pickerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            pickerView.heightAnchor.constraint(equalToConstant: 150),
            
            // Notes Label
            notesLabel.topAnchor.constraint(equalTo: pickerView.bottomAnchor, constant: 16),
            notesLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            notesLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Notes TextView
            notesTextView.topAnchor.constraint(equalTo: notesLabel.bottomAnchor, constant: 8),
            notesTextView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            notesTextView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            notesTextView.heightAnchor.constraint(equalToConstant: 80),
            
            // Add Button
            addButton.topAnchor.constraint(equalTo: notesTextView.bottomAnchor, constant: 16),
            addButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            addButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Cancel Button
            cancelButton.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 10),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        
        pickerView.delegate = self
        pickerView.dataSource = self
        
        addButton.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        
        // Add tap gesture to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        
        // Set text view delegate
        notesTextView.delegate = self
        
        // Add keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Public Methods
    func configure(with circles: [Circle]) {
        self.circles = circles
        pickerView.reloadAllComponents()
        
        // Select middle item for better UX
        if circles.count > 0 {
            let middleIndex = circles.count / 2
            pickerView.selectRow(middleIndex, inComponent: 0, animated: false)
            selectedIndex = middleIndex
        }
    }
    
    func show(in view: UIView) {
        frame = view.bounds
        view.addSubview(self)
        
        // Animate in
        containerView.transform = CGAffineTransform(translationX: 0, y: containerView.frame.height)
        alpha = 0
        
        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
            self.containerView.transform = .identity
        }
    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.containerView.frame.height)
        }) { _ in
            self.removeFromSuperview()
        }
    }
    
    // MARK: - Actions
    @objc private func addButtonTapped() {
        let notes = notesTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesText = notes?.isEmpty == true ? nil : notes
        
        if selectedIndex < circles.count {
            delegate?.circlePickerDidSelectCircle(circles[selectedIndex], notes: notesText)
            dismiss() // Dismiss after selection
        } else {
            delegate?.circlePickerDidSelectCreateNew(notes: notesText)
            dismiss() // Dismiss after selection
        }
    }
    
    @objc private func cancelButtonTapped() {
        delegate?.circlePickerDidCancel()
        dismiss()
    }
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if !containerView.frame.contains(location) {
            cancelButtonTapped()
        }
    }
    
    // MARK: - Keyboard Handling
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        UIView.animate(withDuration: 0.3) {
            self.containerView.transform = CGAffineTransform(translationX: 0, y: -keyboardFrame.height/3)
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.containerView.transform = .identity
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UIPickerViewDataSource
extension CirclePickerSliderView: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return circles.count + 1 // +1 for "Create New Circle"
    }
}

// MARK: - UIPickerViewDelegate
extension CirclePickerSliderView: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if row < circles.count {
            return circles[row].name
        } else {
            return "➕ Create New Circle"
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedIndex = row
        
        // Update button title
        if row < circles.count {
            addButton.setTitle("Add to \(circles[row].name)", for: .normal)
        } else {
            addButton.setTitle("Create New Circle", for: .normal)
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 44
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        
        if row < circles.count {
            label.text = circles[row].name
            label.textColor = .label
        } else {
            label.text = "➕ Create New Circle"
            label.textColor = Constants.Colors.primary
        }
        
        return label
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CirclePickerSliderView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == self
    }
}

// MARK: - UITextViewDelegate
extension CirclePickerSliderView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle return key to dismiss keyboard
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
}
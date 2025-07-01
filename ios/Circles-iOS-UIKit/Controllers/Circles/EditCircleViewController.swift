import UIKit
import Photos

protocol EditCircleDelegate: AnyObject {
    func didUpdateCircle(_ circle: Circle)
    func didDeleteCircle(_ circleId: String)
}

class EditCircleViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: EditCircleDelegate?
    private let circle: Circle
    
    // MARK: - UI Elements
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Constants.Colors.lightGray
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let addCoverPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Change Cover Photo", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.7)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "Circle Name"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Enter circle name"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Description (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Category"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let categorySegmentedControl: UISegmentedControl = {
        let categories = ["Travel", "Food", "Shopping", "Services", "Healthcare", "Entertainment", "Other"]
        let segmentedControl = UISegmentedControl(items: categories)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let privacyLabel: UILabel = {
        let label = UILabel()
        label.text = "Privacy"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let privacySegmentedControl: UISegmentedControl = {
        let privacyLevels = ["Public", "My Network", "Private"]
        let segmentedControl = UISegmentedControl(items: privacyLevels)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        return segmentedControl
    }()
    
    private let locationLabel: UILabel = {
        let label = UILabel()
        label.text = "Location (optional)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let locationTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. New York, Paris, etc."
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let tagsLabel: UILabel = {
        let label = UILabel()
        label.text = "Tags (optional, comma separated)"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .bold)
        label.textColor = Constants.Colors.darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tagsTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g. vacation, foodie, nyc"
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    // Editors section
    private let editorsLabel: UILabel = {
        let label = UILabel()
        label.text = "Circle Editors"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let editorsDescriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "Editors can add and remove places from this circle"
        label.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let editorsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let addEditorButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("+ Add Editor", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.medium, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Save Changes", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = Constants.Colors.primary
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Delete Circle", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.systemRed
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.large, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    private var editors: [User] = []
    private var selectedImage: UIImage? {
        didSet {
            if let image = selectedImage {
                coverImageView.image = image
                coverImageView.contentMode = .scaleAspectFill
                addCoverPhotoButton.setTitle("Change Photo", for: .normal)
            } else {
                loadCurrentCoverImage()
                addCoverPhotoButton.setTitle("Change Cover Photo", for: .normal)
            }
        }
    }
    
    private var hasUnsavedChanges: Bool {
        return nameTextField.text != circle.name ||
               descriptionTextView.text != (circle.description ?? "") ||
               getCurrentCategory() != circle.category ||
               getCurrentPrivacy() != circle.privacy ||
               locationTextField.text != (circle.location ?? "") ||
               getCurrentTags() != (circle.tags ?? []) ||
               selectedImage != nil
    }
    
    // MARK: - Lifecycle
    init(circle: Circle) {
        self.circle = circle
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        populateFields()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if hasUnsavedChanges && isMovingFromParent {
            // Show confirmation dialog for unsaved changes
            presentUnsavedChangesAlert()
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Edit Circle"
        
        // Add navigation bar buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(coverImageView)
        contentView.addSubview(addCoverPhotoButton)
        contentView.addSubview(nameLabel)
        contentView.addSubview(nameTextField)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(descriptionTextView)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(categorySegmentedControl)
        contentView.addSubview(privacyLabel)
        contentView.addSubview(privacySegmentedControl)
        contentView.addSubview(locationLabel)
        contentView.addSubview(locationTextField)
        contentView.addSubview(tagsLabel)
        contentView.addSubview(tagsTextField)
        contentView.addSubview(editorsLabel)
        contentView.addSubview(editorsDescriptionLabel)
        contentView.addSubview(editorsStackView)
        contentView.addSubview(addEditorButton)
        contentView.addSubview(saveButton)
        contentView.addSubview(deleteButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Cover image view
            coverImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.Spacing.large),
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            coverImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            coverImageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Add cover photo button
            addCoverPhotoButton.centerXAnchor.constraint(equalTo: coverImageView.centerXAnchor),
            addCoverPhotoButton.centerYAnchor.constraint(equalTo: coverImageView.centerYAnchor),
            addCoverPhotoButton.widthAnchor.constraint(equalToConstant: 180),
            addCoverPhotoButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: Constants.Spacing.large),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Name text field
            nameTextField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Constants.Spacing.small),
            nameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            nameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            nameTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Constants.Spacing.medium),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Description text view
            descriptionTextView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            descriptionTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            descriptionTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 100),
            
            // Category label
            categoryLabel.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: Constants.Spacing.medium),
            categoryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Category segmented control
            categorySegmentedControl.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: Constants.Spacing.small),
            categorySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            categorySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Privacy label
            privacyLabel.topAnchor.constraint(equalTo: categorySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            privacyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Privacy segmented control
            privacySegmentedControl.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: Constants.Spacing.small),
            privacySegmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            privacySegmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Location label
            locationLabel.topAnchor.constraint(equalTo: privacySegmentedControl.bottomAnchor, constant: Constants.Spacing.medium),
            locationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Location text field
            locationTextField.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: Constants.Spacing.small),
            locationTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            locationTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            locationTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Tags label
            tagsLabel.topAnchor.constraint(equalTo: locationTextField.bottomAnchor, constant: Constants.Spacing.medium),
            tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Tags text field
            tagsTextField.topAnchor.constraint(equalTo: tagsLabel.bottomAnchor, constant: Constants.Spacing.small),
            tagsTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            tagsTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            tagsTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Editors label
            editorsLabel.topAnchor.constraint(equalTo: tagsTextField.bottomAnchor, constant: Constants.Spacing.large),
            editorsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Editors description
            editorsDescriptionLabel.topAnchor.constraint(equalTo: editorsLabel.bottomAnchor, constant: Constants.Spacing.xsmall),
            editorsDescriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            editorsDescriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Editors stack view
            editorsStackView.topAnchor.constraint(equalTo: editorsDescriptionLabel.bottomAnchor, constant: Constants.Spacing.small),
            editorsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            editorsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            
            // Add editor button
            addEditorButton.topAnchor.constraint(equalTo: editorsStackView.bottomAnchor, constant: Constants.Spacing.small),
            addEditorButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            
            // Save button
            saveButton.topAnchor.constraint(equalTo: addEditorButton.bottomAnchor, constant: Constants.Spacing.large),
            saveButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Delete button
            deleteButton.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: Constants.Spacing.medium),
            deleteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.Spacing.large),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.Spacing.large),
            deleteButton.heightAnchor.constraint(equalToConstant: 50),
            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.Spacing.large)
        ])
    }
    
    private func setupActions() {
        addCoverPhotoButton.addTarget(self, action: #selector(addCoverPhotoButtonTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        addEditorButton.addTarget(self, action: #selector(addEditorTapped), for: .touchUpInside)
        
        // Add gesture recognizer to dismiss keyboard when tapping on the view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func populateFields() {
        // Populate form with current circle data
        nameTextField.text = circle.name
        descriptionTextView.text = circle.description
        locationTextField.text = circle.location
        
        // Set category
        let categories = [CircleCategory.travel, .food, .shopping, .services, .healthcare, .entertainment, .other]
        if let categoryIndex = categories.firstIndex(of: circle.category) {
            categorySegmentedControl.selectedSegmentIndex = categoryIndex
        }
        
        // Set privacy
        let privacyLevels = [PrivacyLevel.public, .myNetwork, .private]
        if let privacyIndex = privacyLevels.firstIndex(of: circle.privacy) {
            privacySegmentedControl.selectedSegmentIndex = privacyIndex
        }
        
        // Set tags
        if let tags = circle.tags {
            tagsTextField.text = tags.joined(separator: ", ")
        }
        
        // Load cover image
        loadCurrentCoverImage()
        
        // Load editors
        loadEditors()
    }
    
    private func loadCurrentCoverImage() {
        if let coverImageUrl = circle.coverImage {
            // Load image from URL
            ImageService.shared.loadImage(from: coverImageUrl) { [weak self] image in
                DispatchQueue.main.async {
                    if let image = image {
                        self?.coverImageView.image = image
                        self?.coverImageView.contentMode = .scaleAspectFill
                    } else {
                        // If image failed to load, show default
                        self?.setDefaultCategoryImage()
                    }
                }
            }
        } else {
            setDefaultCategoryImage()
        }
    }
    
    private func setDefaultCategoryImage() {
        switch circle.category {
        case .travel:
            coverImageView.image = UIImage(systemName: "airplane.departure")
        case .food:
            coverImageView.image = UIImage(systemName: "fork.knife.circle.fill")
        case .services:
            coverImageView.image = UIImage(systemName: "wrench.and.screwdriver.fill")
        case .shopping:
            coverImageView.image = UIImage(systemName: "bag.fill")
        case .healthcare:
            coverImageView.image = UIImage(systemName: "heart.text.square.fill")
        case .entertainment:
            coverImageView.image = UIImage(systemName: "music.note.tv.fill")
        case .other:
            coverImageView.image = UIImage(systemName: "square.stack.3d.up.fill")
        }
        coverImageView.tintColor = Constants.Colors.primary
        coverImageView.contentMode = .scaleAspectFit
    }
    
    // MARK: - Helper Methods
    private func getCurrentCategory() -> CircleCategory {
        let categories = [CircleCategory.travel, .food, .shopping, .services, .healthcare, .entertainment, .other]
        return categories[categorySegmentedControl.selectedSegmentIndex]
    }
    
    private func getCurrentPrivacy() -> PrivacyLevel {
        let privacyLevels = [PrivacyLevel.public, .myNetwork, .private]
        return privacyLevels[privacySegmentedControl.selectedSegmentIndex]
    }
    
    private func getCurrentTags() -> [String] {
        guard let tagsText = tagsTextField.text, !tagsText.isEmpty else { return [] }
        return tagsText.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        if hasUnsavedChanges {
            presentUnsavedChangesAlert()
        } else {
            // Check if we're in a navigation controller or presented modally
            if let navigationController = navigationController, navigationController.viewControllers.count > 1 {
                navigationController.popViewController(animated: true)
            } else {
                dismiss(animated: true, completion: nil)
            }
        }
    }
    
    @objc private func saveTapped() {
        // Validate required fields
        guard let name = nameTextField.text, !name.isEmpty else {
            presentAlert(title: "Error", message: "Please enter a name for your circle")
            return
        }
        
        // Get form data
        let description = descriptionTextView.text?.isEmpty == false ? descriptionTextView.text : nil
        let location = locationTextField.text?.isEmpty == false ? locationTextField.text : nil
        let tags = getCurrentTags().isEmpty ? nil : getCurrentTags()
        let category = getCurrentCategory()
        let privacy = getCurrentPrivacy()
        
        // Get cover image data - optimize for upload
        var coverImageData: Data? = nil
        if let image = selectedImage {
            // Use optimized upload function to create small thumbnail image (100KB max)
            coverImageData = image.optimizedForUpload(maxDimension: 300, targetSizeKB: 100)
            
            // Log the final size for debugging
            if let data = coverImageData {
                let sizeKB = data.count / 1024
                print("Optimized image size: \(sizeKB) KB")
                
                // Extra safety check - if still too large, make it even smaller
                if sizeKB > 100 {
                    print("Image still too large, applying extra compression")
                    coverImageData = image.optimizedForUpload(maxDimension: 200, targetSizeKB: 50)
                    if let newData = coverImageData {
                        print("Final compressed size: \(newData.count / 1024) KB")
                    }
                }
            }
        }
        
        // Disable the save button and show loading
        saveButton.isEnabled = false
        saveButton.setTitle("Saving...", for: .normal)
        
        // Update the circle using CircleService
        CircleService.shared.updateCircle(
            id: circle.id,
            name: name,
            description: description,
            privacy: privacy,
            category: category,
            location: location,
            tags: tags,
            coverImage: coverImageData
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.saveButton.isEnabled = true
                self?.saveButton.setTitle("Save Changes", for: .normal)
                
                switch result {
                case .success(let updatedCircle):
                    self?.delegate?.didUpdateCircle(updatedCircle)
                    self?.dismiss(animated: true, completion: nil)
                    
                case .failure(let error):
                    self?.presentAlert(
                        title: "Error",
                        message: "Failed to update circle: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    @objc private func deleteButtonTapped() {
        presentDeleteConfirmation()
    }
    
    @objc private func addCoverPhotoButtonTapped() {
        checkPhotoLibraryPermissions()
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Alert Methods
    private func presentUnsavedChangesAlert() {
        let alert = UIAlertController(
            title: "Unsaved Changes",
            message: "You have unsaved changes. Do you want to save them before leaving?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.saveTapped()
        })
        
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            if let navigationController = self?.navigationController, navigationController.viewControllers.count > 1 {
                navigationController.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true, completion: nil)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func presentDeleteConfirmation() {
        let alert = UIAlertController(
            title: "Delete Circle",
            message: "Are you sure you want to delete this circle? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func performDelete() {
        // Disable the delete button and show loading
        deleteButton.isEnabled = false
        deleteButton.setTitle("Deleting...", for: .normal)
        
        CircleService.shared.deleteCircle(id: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self?.delegate?.didDeleteCircle(self?.circle.id ?? "")
                    self?.dismiss(animated: true, completion: nil)
                    
                case .failure(let error):
                    self?.deleteButton.isEnabled = true
                    self?.deleteButton.setTitle("Delete Circle", for: .normal)
                    self?.presentAlert(
                        title: "Error",
                        message: "Failed to delete circle: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    // MARK: - Photo Methods
    private func checkPhotoLibraryPermissions() {
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            presentImagePicker()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        self?.presentImagePicker()
                    }
                }
            }
        case .denied, .restricted:
            presentPhotoLibraryPermissionAlert()
        @unknown default:
            break
        }
    }
    
    private func presentImagePicker() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .photoLibrary
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        present(imagePicker, animated: true)
    }
    
    private func presentPhotoLibraryPermissionAlert() {
        let alert = UIAlertController(
            title: "Photo Library Access",
            message: "Please allow access to your photo library in Settings to change the cover photo.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func presentAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alertController, animated: true)
    }
    
    // MARK: - Editor Management
    
    private func loadEditors() {
        CircleService.shared.getEditors(circleId: circle.id) { [weak self] result in
            switch result {
            case .success(let editors):
                self?.editors = editors
                self?.updateEditorsDisplay()
            case .failure(let error):
                print("Failed to load editors: \(error)")
            }
        }
    }
    
    private func updateEditorsDisplay() {
        // Clear existing editor views
        editorsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Add editor views
        for editor in editors {
            let editorView = createEditorView(for: editor)
            editorsStackView.addArrangedSubview(editorView)
        }
        
        // Show/hide stack view based on whether there are editors
        editorsStackView.isHidden = editors.isEmpty
    }
    
    private func createEditorView(for user: User) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = Constants.Colors.secondaryBackground
        containerView.layer.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let nameLabel = UILabel()
        nameLabel.text = user.displayName
        nameLabel.font = UIFont.systemFont(ofSize: Constants.FontSize.medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let removeButton = UIButton(type: .system)
        removeButton.setTitle("Remove", for: .normal)
        removeButton.setTitleColor(.systemRed, for: .normal)
        removeButton.titleLabel?.font = UIFont.systemFont(ofSize: Constants.FontSize.small)
        removeButton.tag = editors.firstIndex(where: { $0.id == user.id }) ?? 0
        removeButton.addTarget(self, action: #selector(removeEditorTapped(_:)), for: .touchUpInside)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(nameLabel)
        containerView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 44),
            
            nameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            removeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            removeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        return containerView
    }
    
    @objc private func addEditorTapped() {
        let searchVC = UserSearchViewController()
        searchVC.delegate = self
        searchVC.excludedUserIds = [circle.owner] + (editors.map { $0.id })
        searchVC.title = "Add Editor"
        let navController = UINavigationController(rootViewController: searchVC)
        present(navController, animated: true)
    }
    
    @objc private func removeEditorTapped(_ sender: UIButton) {
        guard sender.tag < editors.count else { return }
        let editor = editors[sender.tag]
        
        let alert = UIAlertController(
            title: "Remove Editor",
            message: "Remove \(editor.displayName) as an editor?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.removeEditor(userId: editor.id)
        })
        
        present(alert, animated: true)
    }
    
    private func removeEditor(userId: String) {
        CircleService.shared.removeEditor(circleId: circle.id, userId: userId) { [weak self] result in
            switch result {
            case .success:
                self?.editors.removeAll { $0.id == userId }
                self?.updateEditorsDisplay()
            case .failure(let error):
                self?.presentAlert(
                    title: "Error",
                    message: "Failed to remove editor: \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - UserSearchViewControllerDelegate
extension EditCircleViewController: UserSearchViewControllerDelegate {
    func userSearchViewController(_ controller: UserSearchViewController, didSelectUser user: User) {
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            
            CircleService.shared.addEditor(circleId: self.circle.id, userId: user.id) { result in
                switch result {
                case .success:
                    self.editors.append(user)
                    self.updateEditorsDisplay()
                case .failure(let error):
                    self.presentAlert(
                        title: "Error",
                        message: "Failed to add editor: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension EditCircleViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
        }
        
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
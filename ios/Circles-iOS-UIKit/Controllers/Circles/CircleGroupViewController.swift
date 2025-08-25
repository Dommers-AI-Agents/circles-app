import UIKit

class CircleGroupViewController: BaseViewController {
    
    // MARK: - Properties
    private var group: CircleGroup
    private var circles: [Circle] = []
    private var isEditingName = false
    
    // MARK: - UI Elements
    private let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let groupNameTextField: UITextField = {
        let textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        textField.textColor = Constants.Colors.label
        textField.textAlignment = .center
        textField.isEnabled = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let editNameButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pencil"), for: .normal)
        button.tintColor = Constants.Colors.primary
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let circleCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        let spacing: CGFloat = 16
        let width = (view.bounds.width - (spacing * 3)) / 2
        layout.itemSize = CGSize(width: width, height: width + 60)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Constants.Colors.background
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.register(CircleCell.self, forCellWithReuseIdentifier: "CircleCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let deleteGroupButton = UIButton.dangerButton(title: "Delete Group")
    
    // MARK: - Init
    init(group: CircleGroup) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCircles()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Circle Group"
        
        // Add navigation buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        // Add subviews
        view.addSubview(headerView)
        headerView.addSubview(groupNameTextField)
        headerView.addSubview(editNameButton)
        headerView.addSubview(circleCountLabel)
        view.addSubview(collectionView)
        view.addSubview(deleteGroupButton)
        
        // Configure text field
        groupNameTextField.text = group.name
        groupNameTextField.delegate = self
        
        // Configure labels
        updateCircleCount()
        
        // Add actions
        editNameButton.addTarget(self, action: #selector(editNameTapped), for: .touchUpInside)
        deleteGroupButton.addTarget(self, action: #selector(deleteGroupTapped), for: .touchUpInside)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Header view
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 120),
            
            // Group name text field
            groupNameTextField.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            groupNameTextField.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            groupNameTextField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 60),
            groupNameTextField.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -60),
            
            // Edit name button
            editNameButton.centerYAnchor.constraint(equalTo: groupNameTextField.centerYAnchor),
            editNameButton.leadingAnchor.constraint(equalTo: groupNameTextField.trailingAnchor, constant: 8),
            editNameButton.widthAnchor.constraint(equalToConstant: 30),
            editNameButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Circle count label
            circleCountLabel.topAnchor.constraint(equalTo: groupNameTextField.bottomAnchor, constant: 8),
            circleCountLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            
            // Collection view
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: deleteGroupButton.topAnchor, constant: -16),
            
            // Delete button
            deleteGroupButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            deleteGroupButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            deleteGroupButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            deleteGroupButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Data
    override func loadData(completion: (() -> Void)? = nil) {
        loadCircles()
        completion?()
    }
    
    private func loadCircles() {
        // If circles are already populated in the group, use them
        if let groupCircles = group.circles {
            self.circles = groupCircles
            collectionView.reloadData()
            return
        }
        
        // Otherwise, fetch circles by their IDs
        // For now, we'll use a placeholder implementation
        // In a real app, you'd fetch these from the API or local storage
        self.circles = []
        for circleId in group.circleIds {
            // Placeholder - in real implementation, fetch from API or cache
            let placeholderCircle = Circle(
                id: circleId,
                name: "Circle \(circleId.prefix(4))",
                description: nil,
                coverImage: nil,
                owner: group.owner,
                ownerDetails: nil,
                editors: nil,
                editorsDetails: nil,
                places: nil,
                placesCount: 0,
                placesWithDetails: nil,
                privacy: .private,
                allowNetworkEdit: false,
                category: .other,
                customCategoryId: nil,
                location: nil,
                tags: nil,
                sharedWith: nil,
                followers: nil,
                activeShares: nil,
                shareSettings: nil,
                isSharedWithMe: false,
                sharedBy: nil,
                myAccessLevel: nil,
                createdAt: Date(),
                updatedAt: Date(),
                groupId: group.id,
                orderInGroup: nil
            )
            circles.append(placeholderCircle)
        }
        collectionView.reloadData()
    }
    
    private func updateCircleCount() {
        circleCountLabel.text = "\(group.circleCount) circles in this group"
    }
    
    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        saveChanges()
        dismiss(animated: true)
    }
    
    @objc private func editNameTapped() {
        isEditingName.toggle()
        
        if isEditingName {
            groupNameTextField.isEnabled = true
            groupNameTextField.becomeFirstResponder()
            editNameButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        } else {
            groupNameTextField.isEnabled = false
            groupNameTextField.resignFirstResponder()
            editNameButton.setImage(UIImage(systemName: "pencil"), for: .normal)
            
            // Save the new name
            if let newName = groupNameTextField.text, !newName.isEmpty {
                group = CircleGroup(
                    id: group.id,
                    name: newName,
                    circleIds: group.circleIds,
                    coverImages: group.coverImages,
                    owner: group.owner,
                    ownerDetails: group.ownerDetails,
                    privacy: group.privacy,
                    createdAt: group.createdAt,
                    updatedAt: Date(),
                    circles: group.circles
                )
            }
        }
    }
    
    @objc private func deleteGroupTapped() {
        showConfirmation(
            title: "Delete Group",
            message: "This will ungroup all circles. The circles themselves won't be deleted."
        ) { [weak self] in
            self?.deleteGroup()
        }
    }
    
    private func deleteGroup() {
        showLoadingState()
        
        CircleGroupService.shared.deleteGroup(group.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success:
                    self?.showSuccess("Group deleted")
                    self?.dismiss(animated: true)
                case .failure(let error):
                    self?.showError("Failed to delete group: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveChanges() {
        guard let newName = groupNameTextField.text,
              newName != group.name else { return }
        
        CircleGroupService.shared.updateGroup(
            group.id,
            name: newName
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updatedGroup):
                    self?.group = updatedGroup
                    self?.showSuccess("Group updated")
                case .failure(let error):
                    self?.showError("Failed to update group: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func removeCircleFromGroup(_ circle: Circle) {
        // If this would leave only one circle, delete the group instead
        if circles.count <= 2 {
            showConfirmation(
                title: "Remove Circle",
                message: "Removing this circle will delete the group. Continue?"
            ) { [weak self] in
                self?.deleteGroup()
            }
            return
        }
        
        // Remove the circle from the group
        showLoadingState()
        
        CircleGroupService.shared.removeCircleFromGroup(circleId: circle.id) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideLoadingState()
                
                switch result {
                case .success:
                    self?.circles.removeAll { $0.id == circle.id }
                    
                    // Create updated group with circle removed
                    let updatedCircleIds = self?.group.circleIds.filter { $0 != circle.id } ?? []
                    self?.group = CircleGroup(
                        id: self?.group.id ?? "",
                        name: self?.group.name ?? "",
                        circleIds: updatedCircleIds,
                        coverImages: self?.group.coverImages ?? [],
                        owner: self?.group.owner ?? "",
                        ownerDetails: self?.group.ownerDetails,
                        privacy: self?.group.privacy ?? .private,
                        createdAt: self?.group.createdAt ?? Date(),
                        updatedAt: Date(),
                        circles: self?.circles
                    )
                    
                    self?.updateCircleCount()
                    self?.collectionView.reloadData()
                    self?.showSuccess("Circle removed from group")
                case .failure(let error):
                    self?.showError("Failed to remove circle: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - UICollectionViewDataSource
extension CircleGroupViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return circles.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CircleCell", for: indexPath) as! CircleCell
        let circle = circles[indexPath.item]
        cell.configure(with: circle)
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension CircleGroupViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let circle = circles[indexPath.item]
        
        // Show options for the circle
        let actionSheet = UIAlertController(title: circle.name, message: nil, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: "View Circle", style: .default) { [weak self] _ in
            let detailVC = CircleDetailViewController(circle: circle)
            self?.navigationController?.pushViewController(detailVC, animated: true)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Remove from Group", style: .destructive) { [weak self] _ in
            self?.removeCircleFromGroup(circle)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = actionSheet.popoverPresentationController {
            if let cell = collectionView.cellForItem(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }
        
        present(actionSheet, animated: true)
    }
}

// MARK: - UICollectionViewDragDelegate
extension CircleGroupViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let circle = circles[indexPath.item]
        let displayItem = CircleDisplayItem.circle(circle)
        return [displayItem.createDragItem()]
    }
    
    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        
        if let cell = collectionView.cellForItem(at: indexPath) as? CircleCell {
            cell.setDragState(true)
        }
        
        return parameters
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        // Reset visual states
        collectionView.visibleCells.forEach { cell in
            if let circleCell = cell as? CircleCell {
                circleCell.setDragState(false)
            }
        }
    }
}

// MARK: - UICollectionViewDropDelegate
extension CircleGroupViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSString.self)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if collectionView.hasActiveDrag {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        } else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        for item in coordinator.items {
            if let sourceIndexPath = item.sourceIndexPath {
                // Reorder within the group
                collectionView.performBatchUpdates({
                    let movedCircle = circles.remove(at: sourceIndexPath.item)
                    circles.insert(movedCircle, at: destinationIndexPath.item)
                    collectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
                })
                
                // Update order in backend
                let updatedCircleIds = circles.map { $0.id }
                CircleGroupService.shared.updateGroup(group.id, circleIds: updatedCircleIds) { _ in
                    // Handle result if needed
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension CircleGroupViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        editNameTapped()
        return true
    }
}
import UIKit

protocol ConnectionPickerDelegate: AnyObject {
    func connectionPicker(_ picker: ConnectionPickerView, didSelectConnection connection: User)
    func connectionPicker(_ picker: ConnectionPickerView, didDeselectConnection connection: User)
}

class ConnectionPickerView: UIView {
    
    // MARK: - Properties
    weak var delegate: ConnectionPickerDelegate?
    private var connections: [User] = []
    private var filteredConnections: [User] = []
    private var selectedConnections: [User] = []
    private var isShowingDropdown = false
    
    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.lightGray.cgColor
        view.layer.cornerRadius = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let searchTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Search connections by name"
        textField.borderStyle = .none
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let selectedConnectionsView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let dropdownTableView: UITableView = {
        let tableView = UITableView()
        tableView.layer.borderWidth = 0.5
        tableView.layer.borderColor = UIColor.lightGray.cgColor
        tableView.layer.cornerRadius = 5
        tableView.layer.shadowColor = UIColor.black.cgColor
        tableView.layer.shadowOpacity = 0.1
        tableView.layer.shadowOffset = CGSize(width: 0, height: 2)
        tableView.layer.shadowRadius = 4
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .singleLine
        tableView.isHidden = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private var dropdownHeightConstraint: NSLayoutConstraint?
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        loadConnections()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(scrollView)
        scrollView.addSubview(selectedConnectionsView)
        containerView.addSubview(searchTextField)
        addSubview(dropdownTableView)
        
        dropdownHeightConstraint = dropdownTableView.heightAnchor.constraint(equalToConstant: 0)
        
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 40),
            
            // Scroll view for selected connections
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            scrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            
            // Selected connections stack view
            selectedConnectionsView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            selectedConnectionsView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            selectedConnectionsView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            selectedConnectionsView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            selectedConnectionsView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            
            // Search text field
            searchTextField.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            searchTextField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Dropdown table view
            dropdownTableView.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 4),
            dropdownTableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dropdownTableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dropdownHeightConstraint!,
            
            // Bottom constraint
            bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Setup table view
        dropdownTableView.delegate = self
        dropdownTableView.dataSource = self
        dropdownTableView.register(ConnectionPickerCell.self, forCellReuseIdentifier: "ConnectionCell")
        
        // Setup text field
        searchTextField.delegate = self
        searchTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        // Add tap gesture to container
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        containerView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Data Loading
    private func loadConnections() {
        NetworkManager.shared.getConnections { [weak self] result in
            switch result {
            case .success(let users):
                self?.connections = users
                self?.filteredConnections = users
            case .failure(let error):
                print("Failed to load connections: \(error)")
            }
        }
    }
    
    // MARK: - Actions
    @objc private func containerTapped() {
        searchTextField.becomeFirstResponder()
        showDropdown()
    }
    
    @objc private func textFieldDidChange() {
        filterConnections()
    }
    
    private func filterConnections() {
        guard let searchText = searchTextField.text?.lowercased(), !searchText.isEmpty else {
            filteredConnections = connections
            dropdownTableView.reloadData()
            return
        }
        
        filteredConnections = connections.filter { user in
            let nameMatch = user.displayName.lowercased().contains(searchText)
            let emailMatch = user.email.lowercased().contains(searchText)
            return nameMatch || emailMatch
        }
        
        dropdownTableView.reloadData()
    }
    
    private func showDropdown() {
        guard !isShowingDropdown else { return }
        isShowingDropdown = true
        
        dropdownTableView.isHidden = false
        let height = min(CGFloat(filteredConnections.count) * 60, 200)
        dropdownHeightConstraint?.constant = height
        
        UIView.animate(withDuration: 0.3) {
            self.superview?.layoutIfNeeded()
        }
    }
    
    private func hideDropdown() {
        guard isShowingDropdown else { return }
        isShowingDropdown = false
        
        dropdownHeightConstraint?.constant = 0
        
        UIView.animate(withDuration: 0.3, animations: {
            self.superview?.layoutIfNeeded()
        }) { _ in
            self.dropdownTableView.isHidden = true
        }
    }
    
    private func addSelectedConnection(_ user: User) {
        guard !selectedConnections.contains(where: { $0.id == user.id }) else { return }
        
        selectedConnections.append(user)
        delegate?.connectionPicker(self, didSelectConnection: user)
        
        // Create chip view
        let chipView = ConnectionChipView(user: user)
        chipView.onRemove = { [weak self] in
            self?.removeSelectedConnection(user)
        }
        
        selectedConnectionsView.addArrangedSubview(chipView)
        
        // Clear search field
        searchTextField.text = ""
        filterConnections()
        
        // Update scroll view width constraint if needed
        scrollView.layoutIfNeeded()
        let contentWidth = selectedConnectionsView.frame.width
        if contentWidth > 200 {
            scrollView.constraints.forEach { constraint in
                if constraint.firstAttribute == .width {
                    constraint.constant = min(contentWidth + 16, frame.width - 100)
                }
            }
        }
    }
    
    private func removeSelectedConnection(_ user: User) {
        selectedConnections.removeAll { $0.id == user.id }
        delegate?.connectionPicker(self, didDeselectConnection: user)
        
        // Remove chip view
        for view in selectedConnectionsView.arrangedSubviews {
            if let chipView = view as? ConnectionChipView, chipView.user.id == user.id {
                selectedConnectionsView.removeArrangedSubview(chipView)
                chipView.removeFromSuperview()
                break
            }
        }
    }
    
    // MARK: - Public Methods
    func getSelectedConnections() -> [User] {
        return selectedConnections
    }
    
    func getEmailText() -> String? {
        return searchTextField.text?.isEmpty == false ? searchTextField.text : nil
    }
}

// MARK: - UITableViewDataSource
extension ConnectionPickerView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredConnections.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConnectionCell", for: indexPath) as! ConnectionPickerCell
        let user = filteredConnections[indexPath.row]
        cell.configure(with: user)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ConnectionPickerView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = filteredConnections[indexPath.row]
        addSelectedConnection(user)
        hideDropdown()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UITextFieldDelegate
extension ConnectionPickerView: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        showDropdown()
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Delay to allow table view selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.hideDropdown()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Connection Picker Cell
private class ConnectionPickerCell: UITableViewCell {
    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let userInfoLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 20
        profileImageView.backgroundColor = Constants.Colors.tertiaryBackground
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nameLabel.textColor = Constants.Colors.label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        userInfoLabel.font = UIFont.systemFont(ofSize: 14)
        userInfoLabel.textColor = Constants.Colors.secondaryLabel
        userInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(profileImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(userInfoLabel)
        
        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            profileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 40),
            profileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: profileImageView.topAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            userInfoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            userInfoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            userInfoLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor)
        ])
    }
    
    func configure(with user: User) {
        nameLabel.text = user.displayName
        // Display connection info instead of email for privacy
        userInfoLabel.text = "Connected"
        
        if let profilePicture = user.profilePicture, let url = URL(string: profilePicture) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.profileImageView.image = image
                    }
                }
            }.resume()
        } else {
            profileImageView.image = createInitialsImage(for: user.displayName)
        }
    }
    
    private func createInitialsImage(for name: String) -> UIImage {
        let initials = name.components(separatedBy: " ")
            .compactMap { $0.first?.uppercased() }
            .prefix(2)
            .joined()
        
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            Constants.Colors.tertiaryBackground.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: Constants.Colors.label
            ]
            
            let textSize = initials.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            initials.draw(in: textRect, withAttributes: attributes)
        }
    }
}

// MARK: - Connection Chip View
private class ConnectionChipView: UIView {
    let user: User
    var onRemove: (() -> Void)?
    
    private let label = UILabel()
    private let removeButton = UIButton.iconButton(systemName: "xmark.circle.fill", pointSize: 16)
    
    init(user: User) {
        self.user = user
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        layer.cornerRadius = 16
        
        label.text = user.firstName ?? user.displayName
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        
        removeButton.tintColor = Constants.Colors.primary
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        
        addSubview(label)
        addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            removeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
            
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    @objc private func removeTapped() {
        onRemove?()
    }
}
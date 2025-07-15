import UIKit

protocol ManageCategoriesDelegate: AnyObject {
    func categoriesDidUpdate()
}

class ManageCategoriesViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: ManageCategoriesDelegate?
    private let categoryType: CategoryType
    private var categories: [UserCategory] = []
    
    // MARK: - UI Components
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.register(CustomCategoryCell.self, forCellReuseIdentifier: "CustomCategoryCell")
        return tableView
    }()
    
    
    // MARK: - Initialization
    init(categoryType: CategoryType) {
        self.categoryType = categoryType
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - BaseViewController Overrides
    override var emptyStateMessage: String? { "No custom categories yet" }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Setup
    private func setupUI() {
        setupNavigationBar(title: "Manage Categories")
        addNavigationBarButton(image: "plus", position: .right, action: #selector(addButtonTapped))
        addNavigationBarButton(title: "Done", position: .left, action: #selector(doneButtonTapped))
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        CategoryService.shared.fetchUserCategories { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let categories):
                    // Filter by type
                    self?.categories = categories.filter { category in
                        category.type == .both || category.type == self?.categoryType
                    }
                    self?.updateUI()
                case .failure(let error):
                    self?.showError(error)
                }
                completion?()
            }
        }
    }
    
    private func updateUI() {
        if categories.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addButtonTapped() {
        AlertPresenter.showTextInput(
            title: "New Category",
            message: "Enter a name for your custom category",
            placeholder: "Category name",
            from: self
        ) { [weak self] text in
            guard let categoryName = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !categoryName.isEmpty else { return }
            self?.createCategory(name: categoryName)
        }
    }
    
    private func createCategory(name: String) {
        CategoryService.shared.createCategory(
            name: name,
            type: categoryType,
            icon: nil,
            color: nil,
            subcategories: []
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let category):
                    self?.categories.append(category)
                    self?.updateUI()
                    self?.delegate?.categoriesDidUpdate()
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    private func deleteCategory(at indexPath: IndexPath) {
        let category = categories[indexPath.row]
        
        AlertPresenter.showConfirmation(
            title: "Delete Category",
            message: "Are you sure you want to delete '\(category.name)'? This cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                CategoryService.shared.deleteCategory(categoryId: category.id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self?.categories.remove(at: indexPath.row)
                            self?.tableView.deleteRows(at: [indexPath], with: .fade)
                            self?.updateUI()
                            self?.delegate?.categoriesDidUpdate()
                        case .failure(let error):
                            self?.showError(error)
                        }
                    }
                }
            }
        )
    }
}

// MARK: - UITableViewDataSource
extension ManageCategoriesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return categories.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CustomCategoryCell", for: indexPath) as! CustomCategoryCell
        let category = categories[indexPath.row]
        cell.configure(with: category)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ManageCategoriesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            deleteCategory(at: indexPath)
        }
    }
}

// MARK: - CustomCategoryCell
private class CustomCategoryCell: UITableViewCell {
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        return label
    }()
    
    private let typeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(typeLabel)
        
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            typeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            typeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            typeLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor)
        ])
    }
    
    func configure(with category: UserCategory) {
        nameLabel.text = category.name
        typeLabel.text = "Available for: \(category.type.displayName)"
        
        // Set icon
        if let iconName = category.icon {
            iconImageView.image = UIImage(systemName: iconName)
        } else {
            iconImageView.image = UIImage(systemName: "folder.circle")
        }
    }
}
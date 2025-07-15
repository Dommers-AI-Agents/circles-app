import UIKit

protocol CategoryPickerDelegate: AnyObject {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: CategoryItem)
}

// Legacy delegate for backward compatibility with PlaceCategory
protocol LegacyCategoryPickerDelegate: AnyObject {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?, customCategory: String?)
}

class CategoryPickerViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: CategoryPickerDelegate?
    weak var legacyDelegate: LegacyCategoryPickerDelegate?
    private let categoryType: CategoryType
    private let useLegacyMode: Bool
    private var categories: [CategoryItem] = []
    private var filteredCategories: [CategoryItem] = []
    private var isSearching = false
    
    // MARK: - UI Components
    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search categories"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.register(CategoryPickerCell.self, forCellReuseIdentifier: "CategoryPickerCell")
        return tableView
    }()
    
    
    // MARK: - Initialization
    init(categoryType: CategoryType, useLegacyMode: Bool = false) {
        self.categoryType = categoryType
        self.useLegacyMode = useLegacyMode
        super.init(nibName: nil, bundle: nil)
    }
    
    // Legacy initializer for PlaceCategory compatibility
    convenience init(forPlaceCategory: Bool = true) {
        self.init(categoryType: .place, useLegacyMode: true)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - BaseViewController Overrides
    override var emptyStateMessage: String? { "No categories available" }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Setup
    private func setupUI() {
        setupNavigationBar(title: "Select Category")
        addNavigationBarButton(title: "Manage", position: .right, action: #selector(manageButtonTapped))
        addNavigationBarButton(title: "Cancel", position: .left, action: #selector(cancelButtonTapped))
        
        view.addSubview(searchBar)
        view.addSubview(tableView)
        
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        if useLegacyMode {
            CategoryService.shared.fetchPredefinedCategories { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let predefinedCategories):
                        let placeCategories = predefinedCategories.filter { $0.type == .place || $0.type == .both }
                        let categoryItems = placeCategories.map { CategoryItem.predefined($0) }
                        self?.categories = categoryItems
                        self?.filteredCategories = categoryItems
                        self?.updateUI()
                    case .failure(let error):
                        self?.showError(error)
                    }
                    completion?()
                }
            }
        } else {
            CategoryService.shared.getAllCategories(for: categoryType) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let categories):
                        self?.categories = categories
                        self?.filteredCategories = categories
                        self?.updateUI()
                    case .failure(let error):
                        self?.showError(error)
                    }
                    completion?()
                }
            }
        }
    }
    
    private func updateUI() {
        if filteredCategories.isEmpty {
            showEmptyState()
        } else {
            hideEmptyState()
        }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func manageButtonTapped() {
        let manageVC = ManageCategoriesViewController(categoryType: categoryType)
        manageVC.delegate = self
        let navController = UINavigationController(rootViewController: manageVC)
        present(navController, animated: true)
    }
    
    // MARK: - Search
    private func filterCategories(with searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredCategories = categories
        } else {
            isSearching = true
            filteredCategories = categories.filter { category in
                category.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        updateUI()
    }
}

// MARK: - UITableViewDataSource
extension CategoryPickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredCategories.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryPickerCell", for: indexPath) as! CategoryPickerCell
        let category = filteredCategories[indexPath.row]
        cell.configure(with: category)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension CategoryPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = filteredCategories[indexPath.row]
        
        if useLegacyMode, let legacyDelegate = legacyDelegate {
            // Convert CategoryItem back to PlaceCategory for legacy delegate
            if let placeCategory = PlaceCategory(rawValue: category.id) {
                legacyDelegate.categoryPicker(self, didSelectCategory: placeCategory, subcategory: nil, customCategory: nil)
            }
        } else {
            delegate?.categoryPicker(self, didSelectCategory: category)
        }
        
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UISearchBarDelegate
extension CategoryPickerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        filterCategories(with: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - ManageCategoriesDelegate
extension CategoryPickerViewController: ManageCategoriesDelegate {
    func categoriesDidUpdate() {
        loadData()
    }
}

// MARK: - CategoryPickerCell
private class CategoryPickerCell: UITableViewCell {
    
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
    
    func configure(with category: CategoryItem) {
        nameLabel.text = category.name
        
        // Show category type for custom categories
        if category.isCustom {
            typeLabel.text = "Custom • \(category.type.displayName)"
            typeLabel.isHidden = false
        } else {
            typeLabel.isHidden = true
        }
        
        // Set icon
        if let iconName = category.icon {
            iconImageView.image = UIImage(systemName: iconName)
        } else {
            // Default icon based on whether it's for circle or place
            iconImageView.image = UIImage(systemName: category.type == .circle ? "folder.circle" : "mappin.circle")
        }
    }
}
import UIKit

protocol CategoryPickerDelegate: AnyObject {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?, customCategory: String?)
}

class CategoryPickerViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: CategoryPickerDelegate?
    private var selectedCategory: PlaceCategory?
    private var selectedSubcategory: String?
    private var customCategoryText: String?
    
    // All categories with their subcategories
    private let subcategoriesData: [PlaceCategory: [String]] = [
        .restaurant: ["Breakfast", "Lunch", "Dinner", "Fast Food", "Fine Dining", "Buffet", "Food Truck", "Bakery", "Deli", "Pizza", "Sushi", "Mexican", "Italian", "Chinese", "Indian", "Thai", "Vietnamese", "Korean", "Japanese"],
        .cafe: ["Coffee Shop", "Tea House", "Juice Bar", "Internet Cafe", "Dessert Shop", "Smoothie Bar"],
        .bar: ["Sports Bar", "Wine Bar", "Cocktail Bar", "Pub", "Brewery", "Nightclub", "Lounge", "Dive Bar"],
        .retail: ["Grocery Store", "Pharmacy", "Clothing Store", "Electronics", "Department Store", "Convenience Store", "Mall", "Bookstore", "Hardware Store", "Pet Store", "Toy Store", "Sporting Goods", "Home Goods"],
        .service: ["Beauty Salon", "Hair Salon", "Nail Salon", "Spa", "Barber Shop", "Car Wash", "Dry Cleaner", "Repair Shop", "Pet Grooming", "Laundromat", "Tailor", "Locksmith"],
        .fitness: ["Gym", "Yoga Studio", "Pilates Studio", "CrossFit", "Personal Training", "Martial Arts", "Dance Studio", "Swimming Pool", "Sports Center", "Boxing Gym", "Climbing Gym"],
        .healthcare: ["Doctor", "Dentist", "Hospital", "Clinic", "Veterinarian", "Urgent Care", "Optometrist", "Physical Therapy", "Mental Health", "Chiropractor", "Dermatologist", "Pediatrician"],
        .entertainment: ["Movie Theater", "Concert Venue", "Comedy Club", "Arcade", "Bowling Alley", "Museum", "Art Gallery", "Theater", "Casino", "Amusement Park", "Escape Room"],
        .education: ["School", "University", "Library", "Tutoring Center", "Language School", "Music School", "Art School", "Daycare", "Preschool"],
        .outdoor: ["Park", "Beach", "Trail", "Campground", "Playground", "Garden", "Lake", "Golf Course", "Tennis Court", "Basketball Court"],
        .transport: ["Airport", "Train Station", "Bus Station", "Subway", "Taxi Stand", "Car Rental", "Parking", "Gas Station", "EV Charging"],
        .finance: ["Bank", "ATM", "Credit Union", "Insurance", "Investment Firm", "Tax Service", "Accounting"],
        .hotel: ["Hotel", "Motel", "Resort", "Bed & Breakfast", "Hostel", "Vacation Rental", "Inn"],
        .attraction: ["Tourist Attraction", "Monument", "Landmark", "Theme Park", "Zoo", "Aquarium", "Observatory"],
        .home: [],
        .work: [],
        .other: []
    ]
    
    // Filtered data for search
    private var filteredCategories: [(category: PlaceCategory, subcategories: [String])] = []
    private var isSearching = false
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search categories (e.g., Library, Gym)"
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Constants.Colors.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // Custom category input view
    private let customCategoryContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.background
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private let customCategoryLabel: UILabel = {
        let label = UILabel()
        label.text = "Enter custom category:"
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let customCategoryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "e.g., Bookstore, Pet Store, etc."
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .words
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private let confirmCustomCategoryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Confirm", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    init(selectedCategory: PlaceCategory? = nil, selectedSubcategory: String? = nil) {
        self.selectedCategory = selectedCategory
        self.selectedSubcategory = selectedSubcategory
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupSearchBar()
        setupCustomCategoryInput()
        loadAllCategories()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Select Category"
        
        // Navigation buttons
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        
        // Add subviews
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(customCategoryContainer)
        
        // Add custom category subviews
        customCategoryContainer.addSubview(customCategoryLabel)
        customCategoryContainer.addSubview(customCategoryTextField)
        customCategoryContainer.addSubview(confirmCustomCategoryButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            customCategoryContainer.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            customCategoryContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customCategoryContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customCategoryContainer.heightAnchor.constraint(equalToConstant: 180),
            
            customCategoryLabel.topAnchor.constraint(equalTo: customCategoryContainer.topAnchor, constant: 20),
            customCategoryLabel.leadingAnchor.constraint(equalTo: customCategoryContainer.leadingAnchor, constant: 20),
            customCategoryLabel.trailingAnchor.constraint(equalTo: customCategoryContainer.trailingAnchor, constant: -20),
            
            customCategoryTextField.topAnchor.constraint(equalTo: customCategoryLabel.bottomAnchor, constant: 12),
            customCategoryTextField.leadingAnchor.constraint(equalTo: customCategoryContainer.leadingAnchor, constant: 20),
            customCategoryTextField.trailingAnchor.constraint(equalTo: customCategoryContainer.trailingAnchor, constant: -20),
            customCategoryTextField.heightAnchor.constraint(equalToConstant: 44),
            
            confirmCustomCategoryButton.topAnchor.constraint(equalTo: customCategoryTextField.bottomAnchor, constant: 20),
            confirmCustomCategoryButton.leadingAnchor.constraint(equalTo: customCategoryContainer.leadingAnchor, constant: 20),
            confirmCustomCategoryButton.trailingAnchor.constraint(equalTo: customCategoryContainer.trailingAnchor, constant: -20),
            confirmCustomCategoryButton.heightAnchor.constraint(equalToConstant: 44),
            
            tableView.topAnchor.constraint(equalTo: customCategoryContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 44
    }
    
    private func setupSearchBar() {
        searchBar.delegate = self
    }
    
    private func setupCustomCategoryInput() {
        customCategoryTextField.delegate = self
        confirmCustomCategoryButton.addTarget(self, action: #selector(confirmCustomCategoryTapped), for: .touchUpInside)
    }
    
    private func loadAllCategories() {
        filteredCategories = PlaceCategory.allCases
            .filter { $0 != .home && $0 != .work } // Exclude home and work
            .sorted { $0.displayName < $1.displayName }
            .map { category in
                (category: category, subcategories: subcategoriesData[category] ?? [])
            }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func confirmCustomCategoryTapped() {
        guard let customText = customCategoryTextField.text, !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Show alert if text is empty
            let alert = UIAlertController(title: "Error", message: "Please enter a custom category name", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        // Pass the custom category to delegate
        customCategoryText = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        delegate?.categoryPicker(self, didSelectCategory: .other, subcategory: nil, customCategory: customCategoryText)
        dismiss(animated: true)
    }
    
    // MARK: - Custom Category Input
    private func showCustomCategoryInput() {
        // Hide search bar and show custom input
        UIView.animate(withDuration: 0.3) {
            self.customCategoryContainer.isHidden = false
            self.customCategoryContainer.alpha = 1.0
        }
        
        // Focus on text field
        customCategoryTextField.becomeFirstResponder()
        
        // Update title
        title = "Enter Custom Category"
    }
    
    private func hideCustomCategoryInput() {
        UIView.animate(withDuration: 0.3) {
            self.customCategoryContainer.isHidden = true
            self.customCategoryContainer.alpha = 0.0
        }
        
        customCategoryTextField.resignFirstResponder()
        customCategoryTextField.text = ""
        
        // Reset title
        title = "Select Category"
    }
    
    // MARK: - Search
    private func filterCategories(with searchText: String) {
        guard !searchText.isEmpty else {
            isSearching = false
            loadAllCategories()
            return
        }
        
        isSearching = true
        let lowercasedSearch = searchText.lowercased()
        
        filteredCategories = PlaceCategory.allCases
            .filter { $0 != .home && $0 != .work }
            .compactMap { category in
                // Check if category name matches
                let categoryMatches = category.displayName.lowercased().contains(lowercasedSearch)
                
                // Filter subcategories that match
                let matchingSubcategories = (subcategoriesData[category] ?? [])
                    .filter { $0.lowercased().contains(lowercasedSearch) }
                
                // Include if category matches or has matching subcategories
                if categoryMatches || !matchingSubcategories.isEmpty {
                    // If searching, show all subcategories for matching categories
                    // or only matching subcategories
                    let subcategoriesToShow = categoryMatches ? 
                        (subcategoriesData[category] ?? []) : matchingSubcategories
                    return (category: category, subcategories: subcategoriesToShow)
                }
                return nil
            }
            .sorted { $0.category.displayName < $1.category.displayName }
        
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource
extension CategoryPickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return filteredCategories.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let categoryData = filteredCategories[section]
        // Parent category + subcategories
        return 1 + categoryData.subcategories.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        let categoryData = filteredCategories[indexPath.section]
        
        if indexPath.row == 0 {
            // Parent category
            cell.textLabel?.text = categoryData.category.displayName
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            cell.indentationLevel = 0
            
            // Add checkmark if selected
            if categoryData.category == selectedCategory && selectedSubcategory == nil {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
        } else {
            // Subcategory
            let subcategory = categoryData.subcategories[indexPath.row - 1]
            cell.textLabel?.text = subcategory
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.indentationLevel = 2
            cell.indentationWidth = 15
            
            // Add checkmark if selected
            if categoryData.category == selectedCategory && subcategory == selectedSubcategory {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // Only show section headers when not searching
        return isSearching ? nil : filteredCategories[section].category.displayName
    }
}

// MARK: - UITableViewDelegate
extension CategoryPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let categoryData = filteredCategories[indexPath.section]
        
        if indexPath.row == 0 {
            // Selected parent category
            if categoryData.category == .other {
                // Show custom category input
                showCustomCategoryInput()
            } else {
                delegate?.categoryPicker(self, didSelectCategory: categoryData.category, subcategory: nil, customCategory: nil)
                dismiss(animated: true)
            }
        } else {
            // Selected subcategory
            let subcategory = categoryData.subcategories[indexPath.row - 1]
            delegate?.categoryPicker(self, didSelectCategory: categoryData.category, subcategory: subcategory, customCategory: nil)
            dismiss(animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide section headers when searching
        return isSearching ? 0.1 : UITableView.automaticDimension
    }
}

// MARK: - UITextFieldDelegate
extension CategoryPickerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == customCategoryTextField {
            confirmCustomCategoryTapped()
        }
        return true
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
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        loadAllCategories()
    }
}
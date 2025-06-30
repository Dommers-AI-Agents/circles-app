import UIKit

protocol CategoryPickerDelegate: AnyObject {
    func categoryPicker(_ picker: CategoryPickerViewController, didSelectCategory category: PlaceCategory, subcategory: String?)
}

class CategoryPickerViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: CategoryPickerDelegate?
    private var selectedCategory: PlaceCategory?
    private var selectedSubcategory: String?
    
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
        
        // Constraints
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
            delegate?.categoryPicker(self, didSelectCategory: categoryData.category, subcategory: nil)
        } else {
            // Selected subcategory
            let subcategory = categoryData.subcategories[indexPath.row - 1]
            delegate?.categoryPicker(self, didSelectCategory: categoryData.category, subcategory: subcategory)
        }
        
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide section headers when searching
        return isSearching ? 0.1 : UITableView.automaticDimension
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
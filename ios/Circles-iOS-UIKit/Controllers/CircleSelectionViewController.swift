import UIKit

protocol CircleSelectionDelegate: AnyObject {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle)
    func circleSelectionViewControllerDidCancel(_ controller: CircleSelectionViewController)
}

// Extended protocol for place moving functionality
protocol CircleSelectionWithPlaceDelegate: CircleSelectionDelegate {
    func circleSelectionViewController(_ controller: CircleSelectionViewController, didSelectCircle circle: Circle, forPlace place: Place)
}

class CircleSelectionViewController: UIViewController {
    // MARK: - Properties
    
    weak var delegate: CircleSelectionDelegate?
    var placeToMove: Place?
    
    private var circles: [Circle] = []
    private var filteredCircles: [Circle] = []
    private var excludedCircleId: String?
    private var isCreatingNewCircle = false
    private var customTitle: String?
    private var isSearchActive = false
    
    // MARK: - UI Components
    
    private lazy var navigationBar: UINavigationBar = {
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        let navItem = UINavigationItem(title: customTitle ?? "Select Circle")
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navItem.leftBarButtonItem = cancelButton
        
        navBar.setItems([navItem], animated: false)
        return navBar
    }()
    
    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search circles..."
        searchController.searchBar.delegate = self
        return searchController
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CircleCell")
        table.backgroundColor = .systemGroupedBackground
        return table
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No circles available"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.isHidden = true
        return label
    }()
    
    // MARK: - Initialization
    
    init(excludedCircleId: String? = nil, customTitle: String? = nil) {
        self.excludedCircleId = excludedCircleId
        self.customTitle = customTitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        loadCircles()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(navigationBar)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(emptyStateLabel)
        
        // Setup search controller
        if let navItem = navigationBar.items?.first {
            navItem.searchController = searchController
            navItem.hidesSearchBarWhenScrolling = false
        }
        
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadCircles() {
        loadingIndicator.startAnimating()
        tableView.isHidden = true
        emptyStateLabel.isHidden = true
        
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let allCircles):
                    // Filter out the excluded circle if provided
                    var circlesAfterExclusion = allCircles
                    if let excludedId = self.excludedCircleId {
                        circlesAfterExclusion = allCircles.filter { $0.id != excludedId }
                    }
                    
                    // Sort circles alphabetically by name
                    let sortedCircles = circlesAfterExclusion.sorted { (circle1, circle2) in
                        return circle1.name.localizedCaseInsensitiveCompare(circle2.name) == .orderedAscending
                    }
                    
                    self.circles = sortedCircles
                    self.filteredCircles = sortedCircles
                    
                    if self.circles.isEmpty {
                        self.tableView.isHidden = true
                        self.emptyStateLabel.isHidden = false
                        self.emptyStateLabel.text = "No other circles available"
                    } else {
                        self.tableView.isHidden = false
                        self.emptyStateLabel.isHidden = true
                        self.tableView.reloadData()
                    }
                    
                case .failure(let error):
                    self.tableView.isHidden = true
                    self.emptyStateLabel.isHidden = false
                    self.emptyStateLabel.text = "Failed to load circles"
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        delegate?.circleSelectionViewControllerDidCancel(self)
        dismiss(animated: true)
    }
    
    
    private func createNewCircle() {
        let alert = UIAlertController(title: "New Circle", message: "Enter a name for the new circle", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Circle name"
            textField.autocapitalizationType = .words
        }
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            
            // Check if circle with this name already exists
            let existingCircle = self.circles.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            
            if let existing = existingCircle {
                self.showDuplicateCircleAlert(existingName: name, existingCircle: existing)
                return
            }
            
            self.createCircleWithName(name)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(createAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showDuplicateCircleAlert(existingName: String, existingCircle: Circle) {
        let alert = UIAlertController(
            title: "Circle Already Exists",
            message: "A circle named '\(existingName)' already exists. Would you like to add anyway or select the existing circle?",
            preferredStyle: .alert
        )
        
        let addAnywayAction = UIAlertAction(title: "Add Anyway", style: .default) { [weak self] _ in
            self?.createCircleWithName(existingName)
        }
        
        let useExistingAction = UIAlertAction(title: "Use Existing", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            if let placeDelegate = self.delegate as? CircleSelectionWithPlaceDelegate,
               let place = self.placeToMove {
                placeDelegate.circleSelectionViewController(self, didSelectCircle: existingCircle, forPlace: place)
            } else {
                self.delegate?.circleSelectionViewController(self, didSelectCircle: existingCircle)
            }
            self.dismiss(animated: true)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(addAnywayAction)
        alert.addAction(useExistingAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func createCircleWithName(_ name: String) {
        self.isCreatingNewCircle = true
        self.loadingIndicator.startAnimating()
        
        CircleService.shared.createCircle(name: name, description: nil, privacy: .myNetwork, category: .other) { result in
            DispatchQueue.main.async {
                self.isCreatingNewCircle = false
                self.loadingIndicator.stopAnimating()
                
                switch result {
                case .success(let circle):
                    if let placeDelegate = self.delegate as? CircleSelectionWithPlaceDelegate,
                       let place = self.placeToMove {
                        placeDelegate.circleSelectionViewController(self, didSelectCircle: circle, forPlace: place)
                    } else {
                        self.delegate?.circleSelectionViewController(self, didSelectCircle: circle)
                    }
                    self.dismiss(animated: true)
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension CircleSelectionViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // 1 for existing circles, 1 for create new
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return filteredCircles.count
        } else {
            return 1 // Create new circle option
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath)
        
        if indexPath.section == 0 {
            let circle = filteredCircles[indexPath.row]
            
            // Configure cell with content configuration for better layout
            var content = cell.defaultContentConfiguration()
            content.text = circle.name
            content.secondaryText = "\(circle.placesCount ?? circle.places?.count ?? 0) places"
            
            // Set the image
            if let coverImageUrl = circle.coverImage {
                // Load circle cover image
                content.image = UIImage(systemName: "circle.fill") // Placeholder
                content.imageProperties.tintColor = .systemGray
                content.imageProperties.maximumSize = CGSize(width: 60, height: 60)
                content.imageProperties.cornerRadius = 30 // Make it circular
                
                // Load actual image asynchronously
                ImageService.shared.loadImage(from: coverImageUrl) { [weak tableView] image in
                    DispatchQueue.main.async {
                        // Check if cell is still visible for this index path
                        if let visibleIndexPaths = tableView?.indexPathsForVisibleRows,
                           visibleIndexPaths.contains(indexPath),
                           let cell = tableView?.cellForRow(at: indexPath) {
                            var updatedContent = cell.defaultContentConfiguration()
                            updatedContent.text = circle.name
                            updatedContent.secondaryText = "\(circle.placesCount ?? circle.places?.count ?? 0) places"
                            updatedContent.image = image
                            updatedContent.imageProperties.maximumSize = CGSize(width: 60, height: 60)
                            updatedContent.imageProperties.cornerRadius = 30
                            cell.contentConfiguration = updatedContent
                        }
                    }
                }
            } else {
                // Use category icon
                let iconName: String
                switch circle.category {
                case .travel: iconName = "airplane.circle.fill"
                case .food: iconName = "fork.knife.circle.fill"
                case .services: iconName = "wrench.and.screwdriver.circle.fill"
                case .shopping: iconName = "bag.circle.fill"
                case .healthcare: iconName = "heart.circle.fill"
                case .entertainment: iconName = "tv.circle.fill"
                case .other: iconName = "circle.grid.3x3.circle.fill"
                }
                content.image = UIImage(systemName: iconName)
                content.imageProperties.tintColor = Constants.Colors.primary
                content.imageProperties.maximumSize = CGSize(width: 60, height: 60)
            }
            
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        } else {
            // Create New Circle row
            var content = cell.defaultContentConfiguration()
            content.text = "Create New Circle"
            content.textProperties.color = .systemBlue
            content.image = UIImage(systemName: "plus.circle.fill")
            content.imageProperties.tintColor = .systemBlue
            content.imageProperties.maximumSize = CGSize(width: 60, height: 60)
            cell.contentConfiguration = content
            cell.accessoryType = .none
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CircleSelectionViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            let selectedCircle = filteredCircles[indexPath.row]
            if let placeDelegate = delegate as? CircleSelectionWithPlaceDelegate,
               let place = placeToMove {
                placeDelegate.circleSelectionViewController(self, didSelectCircle: selectedCircle, forPlace: place)
            } else {
                delegate?.circleSelectionViewController(self, didSelectCircle: selectedCircle)
            }
            dismiss(animated: true)
        } else {
            createNewCircle()
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 && !filteredCircles.isEmpty {
            return "Your Circles"
        }
        return nil
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80 // Fixed height for consistent circle image display
    }
}

// MARK: - UISearchResultsUpdating

extension CircleSelectionViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        filterCircles(with: searchText)
    }
    
    private func filterCircles(with searchText: String) {
        if searchText.isEmpty {
            filteredCircles = circles
            isSearchActive = false
        } else {
            filteredCircles = circles.filter { circle in
                circle.name.localizedCaseInsensitiveContains(searchText)
            }
            isSearchActive = true
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
}

// MARK: - UISearchBarDelegate

extension CircleSelectionViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        filteredCircles = circles
        isSearchActive = false
        tableView.reloadData()
    }
}
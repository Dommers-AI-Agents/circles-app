import UIKit

protocol PlacePickerViewControllerDelegate: AnyObject {
    func placePickerViewController(_ controller: PlacePickerViewController, didSelectPlace place: Place)
}

class PlacePickerViewController: UIViewController {
    
    weak var delegate: PlacePickerViewControllerDelegate?
    private var places: [Place] = []
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = "Search places"
        controller.obscuresBackgroundDuringPresentation = false
        return controller
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        loadPlaces()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupNavigationBar() {
        title = "Select Place"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    // MARK: - Data Loading
    private func loadPlaces() {
        // Load places from user's circles
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circles):
                    // Extract all unique places from circles
                    var allPlaces: [Place] = []
                    for circle in circles {
                        if let placesWithDetails = circle.placesWithDetails {
                            allPlaces.append(contentsOf: placesWithDetails)
                        }
                    }
                    
                    // Remove duplicates based on place ID
                    let uniquePlaces = Array(Set(allPlaces))
                    self?.places = uniquePlaces.sorted { $0.name < $1.name }
                    self?.tableView.reloadData()
                    
                case .failure(let error):
                    print("Error loading places: \(error)")
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Filtering
    private var filteredPlaces: [Place] {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            return places
        }
        
        return places.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.address.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - UITableViewDataSource
extension PlacePickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath)
        let place = filteredPlaces[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = place.name
        content.secondaryText = place.address
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PlacePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let place = filteredPlaces[indexPath.row]
        delegate?.placePickerViewController(self, didSelectPlace: place)
    }
}

// MARK: - UISearchResultsUpdating
extension PlacePickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
    }
}

// Make Place conform to Hashable for Set operations
extension Place: Hashable {
    static func == (lhs: Place, rhs: Place) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
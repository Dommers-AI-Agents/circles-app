import UIKit

// MARK: - Delegate Protocol
protocol QuickAccessPlacesDelegate: AnyObject {
    func didUpdateQuickAccessPlaces(_ places: [Place])
}

class QuickAccessPlacesViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: QuickAccessPlacesDelegate?
    private var _allPlaces: [Place] = []
    var allPlaces: [Place] {
        get { return _allPlaces }
        set {
            _allPlaces = newValue
            
            // Ensure we have valid data before sorting
            guard !_allPlaces.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.tableView.reloadData()
                }
                return
            }
            
            // Log for debugging
            print("📍 QuickAccessPlaces: Received \(_allPlaces.count) places")
            
            // Sort places with selected ones first, then alphabetically within each group
            DispatchQueue.main.async { [weak self] in
                self?.sortAndReload()
            }
        }
    }
    private var filteredPlaces: [Place] = []
    private var isSearching = false
    private var selectedPlaceIds: Set<String> = []
    private let maxPlaces = 10
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = Constants.Colors.background
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let saveButton = UIButton.primaryButton(title: "Save")
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Select up to 10 places for quick access"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search places..."
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = Constants.Colors.background
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSelectedPlaces()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        
        // Navigation
        title = "Quick Access Places"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        
        // Add subviews
        view.addSubview(instructionLabel)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(saveButton)
        
        // Configure search bar
        searchBar.delegate = self
        searchBar.showsCancelButton = true
        
        // Configure table
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(QuickAccessPlaceCell.self, forCellReuseIdentifier: "PlaceCell")
        
        // Configure save button
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        updateSaveButton()
        
        // Layout
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            searchBar.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),
            
            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            saveButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func loadSelectedPlaces() {
        // Load currently saved quick access places
        let savedPlaces = UserDefaults.standard.array(forKey: "userQuickAccessPlaces") as? [[String: Any]] ?? []
        selectedPlaceIds = Set(savedPlaces.compactMap { $0["id"] as? String })
        sortAndReload()
        updateSaveButton()
    }
    
    private func sortAndReload() {
        // Guard against empty array
        guard !_allPlaces.isEmpty else { 
            tableView.reloadData()
            return 
        }
        
        // Sort places with selected ones first
        _allPlaces.sort { (place1, place2) -> Bool in
            let isSelected1 = selectedPlaceIds.contains(place1.id)
            let isSelected2 = selectedPlaceIds.contains(place2.id)
            
            // Selected places come first
            if isSelected1 != isSelected2 {
                return isSelected1
            }
            
            // Within same group, sort alphabetically
            // Using a simple comparison to avoid crashes
            return place1.name < place2.name
        }
        
        tableView.reloadData()
    }
    
    private func updateSaveButton() {
        let count = selectedPlaceIds.count
        let title: String
        if count == 0 {
            title = "Save"
        } else if count == 1 {
            title = "Save (1)"
        } else {
            title = "Save (\(count))"
        }
        
        // Update bottom save button
        saveButton.setTitle(title, for: .normal)
        
        // Update navigation bar save button
        navigationItem.rightBarButtonItem?.title = title
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveTapped() {
        // Get selected places
        let selectedPlaces = _allPlaces.filter { selectedPlaceIds.contains($0.id) }
        
        // Notify delegate
        delegate?.didUpdateQuickAccessPlaces(selectedPlaces)
        
        // Dismiss
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource
extension QuickAccessPlacesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isSearching ? filteredPlaces.count : _allPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath) as! QuickAccessPlaceCell
        let place = isSearching ? filteredPlaces[indexPath.row] : _allPlaces[indexPath.row]
        let isSelected = selectedPlaceIds.contains(place.id)
        cell.configure(with: place, isSelected: isSelected)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension QuickAccessPlacesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let place = isSearching ? filteredPlaces[indexPath.row] : allPlaces[indexPath.row]
        
        if selectedPlaceIds.contains(place.id) {
            // Deselect
            selectedPlaceIds.remove(place.id)
        } else {
            // Check max limit
            if selectedPlaceIds.count >= maxPlaces {
                showError("You can only select up to \(maxPlaces) places")
                return
            }
            
            // Select
            selectedPlaceIds.insert(place.id)
        }
        
        // Re-sort and reload entire table to move selected items to top
        sortAndReload()
        updateSaveButton()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - Custom Cell
class QuickAccessPlaceCell: UITableViewCell {
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Constants.Colors.primary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = Constants.Colors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    // Optional right-aligned distance text (e.g. "2.3 mi"), hidden when not provided
    private let distanceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
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
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(addressLabel)
        containerView.addSubview(checkmarkImageView)
        containerView.addSubview(distanceLabel)

        NSLayoutConstraint.activate([
            distanceLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -4),
            distanceLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: distanceLabel.leadingAnchor, constant: -8),
            
            addressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            addressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            addressLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            checkmarkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with place: Place, isSelected: Bool, distanceText: String? = nil) {
        nameLabel.text = place.name
        addressLabel.text = place.address
        checkmarkImageView.isHidden = !isSelected
        distanceLabel.text = distanceText
        distanceLabel.isHidden = (distanceText == nil)

        // Set icon based on category
        let iconName = place.category.systemIconName
        iconImageView.image = UIImage(systemName: iconName)
    }
}

// MARK: - UISearchBarDelegate
extension QuickAccessPlacesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredPlaces = []
        } else {
            isSearching = true
            // Filter places by name or address
            filteredPlaces = _allPlaces.filter { place in
                place.name.localizedCaseInsensitiveContains(searchText) ||
                place.address.localizedCaseInsensitiveContains(searchText)
            }
            
            // Sort filtered results with selected ones first
            filteredPlaces.sort { (place1, place2) -> Bool in
                let isSelected1 = selectedPlaceIds.contains(place1.id)
                let isSelected2 = selectedPlaceIds.contains(place2.id)
                
                if isSelected1 != isSelected2 {
                    return isSelected1
                }
                
                // Simple alphabetical comparison
                return place1.name < place2.name
            }
        }
        tableView.reloadData()
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        searchBar.setShowsCancelButton(false, animated: true)
        isSearching = false
        filteredPlaces = []
        tableView.reloadData()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
import UIKit
import CoreLocation

class AddPlaceToCircleViewController: BaseViewController {
    
    // MARK: - Properties
    private var placeId: String?
    private var placeName: String = ""
    private var placeAddress: String = ""
    private var latitude: Double?
    private var longitude: Double?
    private var photoURL: String?
    private var circles: [Circle] = []
    private var selectedCircleId: String?
    
    // MARK: - UI Elements
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "Select a circle to add this place"
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Constants.Colors.background
        return table
    }()
    
    private lazy var createCircleButton = UIButton.secondaryButton(title: "Create New Circle")
    private lazy var saveButton = UIButton.primaryButton(title: "Add to Circle")
    
    // MARK: - Configuration
    override var showsLoadingIndicator: Bool { true }
    override var emptyStateMessage: String? { "No circles found. Create a circle first." }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }
    
    // MARK: - Configuration
    func configureForCheckInPlace(placeId: String, name: String, address: String, latitude: Double? = nil, longitude: Double? = nil, photoURL: String? = nil) {
        self.placeId = placeId
        self.placeName = name
        self.placeAddress = address
        self.latitude = latitude
        self.longitude = longitude
        self.photoURL = photoURL
        
        if isViewLoaded {
            placeNameLabel.text = name
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Add to Circle"
        view.backgroundColor = Constants.Colors.background
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        view.addSubview(headerLabel)
        view.addSubview(placeNameLabel)
        view.addSubview(tableView)
        view.addSubview(createCircleButton)
        view.addSubview(saveButton)
        
        placeNameLabel.text = placeName
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CircleCell")
        
        createCircleButton.addTarget(self, action: #selector(createCircleTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.isEnabled = false
        saveButton.alpha = 0.6
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.medium),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            
            placeNameLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: Constants.Spacing.small),
            placeNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            placeNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            
            tableView.topAnchor.constraint(equalTo: placeNameLabel.bottomAnchor, constant: Constants.Spacing.medium),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: createCircleButton.topAnchor, constant: -Constants.Spacing.medium),
            
            createCircleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            createCircleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            createCircleButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -Constants.Spacing.small),
            
            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.Spacing.medium)
        ])
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                
                switch result {
                case .success(let circles):
                    self?.circles = circles
                    self?.tableView.reloadData()
                    
                    if circles.isEmpty {
                        self?.showEmptyState()
                    }
                    
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func createCircleTapped() {
        let createVC = CreateCircleViewController()
        navigationController?.pushViewController(createVC, animated: true)
    }
    
    @objc private func saveTapped() {
        guard let placeId = placeId,
              let circleId = selectedCircleId else { return }
        
        saveButton.setLoading(true)
        
        // If we have coordinates, create the place in the circle
        if let latitude = latitude, let longitude = longitude {
            let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            PlaceService.shared.createPlace(
                name: placeName,
                description: nil,
                address: placeAddress,
                category: .other,
                circleId: circleId,
                photos: nil,
                photoUrls: photoURL != nil ? [photoURL!] : nil,
                location: location,
                googlePlaceId: placeId,
                completion: { [weak self] result in
                    DispatchQueue.main.async {
                        self?.saveButton.setLoading(false)
                        
                        switch result {
                        case .success:
                            self?.showSuccess("Place added to circle!")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                self?.dismiss(animated: true)
                            }
                            
                        case .failure(let error):
                            self?.showError(error)
                        }
                    }
                }
            )
        } else {
            // Try to add existing place to circle if it exists
            PlaceService.shared.addExistingPlaceToCircle(
                placeId: placeId,
                circleId: circleId,
                completion: { [weak self] result in
                    DispatchQueue.main.async {
                        self?.saveButton.setLoading(false)
                        
                        switch result {
                        case .success:
                            self?.showSuccess("Place added to circle!")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                self?.dismiss(animated: true)
                            }
                            
                        case .failure(let error):
                            // If adding existing place fails, create a new one
                            self?.saveButton.setLoading(true)
                            PlaceService.shared.createPlace(
                                name: self?.placeName ?? "",
                                description: nil,
                                address: self?.placeAddress ?? "",
                                category: .other,
                                circleId: circleId,
                                photos: nil,
                                photoUrls: self?.photoURL != nil ? [self!.photoURL!] : nil,
                                location: nil,
                                googlePlaceId: placeId,
                                completion: { result in
                                    DispatchQueue.main.async {
                                        self?.saveButton.setLoading(false)
                                        
                                        switch result {
                                        case .success:
                                            self?.showSuccess("Place added to circle!")
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                                self?.dismiss(animated: true)
                                            }
                                            
                                        case .failure(let error):
                                            self?.showError(error)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            )
        }
    }
    
    private func updateSaveButton() {
        let isEnabled = selectedCircleId != nil
        saveButton.isEnabled = isEnabled
        saveButton.alpha = isEnabled ? 1.0 : 0.6
    }
}

// MARK: - UITableViewDataSource
extension AddPlaceToCircleViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return circles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CircleCell", for: indexPath)
        let circle = circles[indexPath.row]
        
        cell.textLabel?.text = circle.name
        cell.detailTextLabel?.text = "\(circle.placesCount ?? 0) places"
        
        if circle.id == selectedCircleId {
            cell.accessoryType = .checkmark
            cell.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
        } else {
            cell.accessoryType = .none
            cell.backgroundColor = .clear
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension AddPlaceToCircleViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let previousSelection = selectedCircleId
        selectedCircleId = circles[indexPath.row].id
        
        // Update UI
        var indexPathsToReload = [indexPath]
        if let previousId = previousSelection,
           let previousIndex = circles.firstIndex(where: { $0.id == previousId }) {
            indexPathsToReload.append(IndexPath(row: previousIndex, section: 0))
        }
        
        tableView.reloadRows(at: indexPathsToReload, with: .automatic)
        updateSaveButton()
    }
}
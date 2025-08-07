import UIKit
import MapKit
import CoreLocation

class HomeWorkExclusionViewController: UITableViewController {
    
    // MARK: - Properties
    private var homeAddress: String?
    private var workAddress: String?
    private var excludeHome = false
    private var excludeWork = false
    private let locationManager = CLLocationManager()
    private var pendingLocationType: String?
    
    // MARK: - Cells
    private enum Section: Int, CaseIterable {
        case home
        case work
        case settings
        
        var title: String {
            switch self {
            case .home: return "Home Location"
            case .work: return "Work Location"
            case .settings: return "Exclusion Settings"
            }
        }
    }
    
    private enum HomeRow: Int, CaseIterable {
        case address
        case exclude
    }
    
    private enum WorkRow: Int, CaseIterable {
        case address
        case exclude
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadSettings()
    }
    
    // MARK: - Setup
    private func setupView() {
        title = "Home & Work Exclusion"
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(SwitchCell.self, forCellReuseIdentifier: "SwitchCell")
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveSettings)
        )
    }
    
    private func loadSettings() {
        // Load addresses from UserDefaults (these are set from Quick Access)
        homeAddress = UserDefaults.standard.string(forKey: "userHomeAddress")
        workAddress = UserDefaults.standard.string(forKey: "userWorkAddress")
        
        // Load exclusion settings
        excludeHome = UserDefaults.standard.bool(forKey: "excludeHomeFromVisits")
        excludeWork = UserDefaults.standard.bool(forKey: "excludeWorkFromVisits")
    }
    
    // MARK: - Actions
    @objc private func saveSettings() {
        // Save exclusion preferences
        UserDefaults.standard.set(excludeHome, forKey: "excludeHomeFromVisits")
        UserDefaults.standard.set(excludeWork, forKey: "excludeWorkFromVisits")
        
        // Update server preferences
        updateExclusionPreferences()
        
        navigationController?.popViewController(animated: true)
    }
    
    private func updateExclusionPreferences() {
        let preferences: [String: Any] = [
            "excludeHome": excludeHome,
            "excludeWork": excludeWork,
            "homeAddress": homeAddress ?? "",
            "workAddress": workAddress ?? ""
        ]
        
        APIService.shared.request(
            endpoint: "visits/settings/exclusions",
            method: .put,
            body: preferences,
            requiresAuth: true
        ) { (result: Result<SuccessResponse, APIError>) in
            if case .failure(let error) = result {
                Logger.error("Failed to update exclusion preferences: \(error)")
            }
        }
    }
    
    @objc private func homeExclusionChanged(_ sender: UISwitch) {
        excludeHome = sender.isOn
    }
    
    @objc private func workExclusionChanged(_ sender: UISwitch) {
        excludeWork = sender.isOn
    }
    
    private func showAddressPicker(for type: String) {
        let alert = UIAlertController(
            title: "Set \(type) Address",
            message: "Enter your \(type.lowercased()) address",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "123 Main St, City, State"
            textField.text = type == "Home" ? self.homeAddress : self.workAddress
        }
        
        alert.addAction(UIAlertAction(title: "Use Current Location", style: .default) { [weak self] _ in
            self?.useCurrentLocation(for: type)
        })
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let address = alert.textFields?.first?.text, !address.isEmpty else { return }
            self?.saveAddress(address, for: type)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func useCurrentLocation(for type: String) {
        pendingLocationType = type
        locationManager.delegate = self
        
        // Request location if needed
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            AlertPresenter.showLoading(message: "Getting location...", from: self)
            locationManager.requestLocation()
        } else {
            showAlert(title: "Location Access Denied", message: "Please enable location access in Settings to use current location.")
        }
    }
    
    private func formatAddress(from placemark: CLPlacemark) -> String {
        let components = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ].compactMap { $0 }
        
        return components.joined(separator: ", ")
    }
    
    private func saveAddress(_ address: String, for type: String) {
        if type == "Home" {
            homeAddress = address
            UserDefaults.standard.set(address, forKey: "userHomeAddress")
        } else {
            workAddress = address
            UserDefaults.standard.set(address, forKey: "userWorkAddress")
        }
        
        // Geocode the address to store coordinates
        geocodeAndStoreCoordinates(address: address, type: type.lowercased())
        
        tableView.reloadData()
    }
    
    private func geocodeAndStoreCoordinates(address: String, type: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let location = placemarks?.first?.location {
                UserDefaults.standard.set(location.coordinate.latitude, forKey: "\(type)Latitude")
                UserDefaults.standard.set(location.coordinate.longitude, forKey: "\(type)Longitude")
                Logger.info("📍 Stored \(type) coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else if let error = error {
                Logger.error("📍 Failed to geocode \(type) address: \(error)")
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension HomeWorkExclusionViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .home:
            return HomeRow.allCases.count
        case .work:
            return WorkRow.allCases.count
        case .settings:
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch sectionType {
        case .home:
            switch HomeRow(rawValue: indexPath.row) {
            case .address:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                cell.textLabel?.text = "Home Address"
                cell.detailTextLabel?.text = homeAddress ?? "Not set"
                cell.detailTextLabel?.textColor = homeAddress == nil ? .systemRed : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
                
            case .exclude:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
                cell.textLabel?.text = "Exclude Home Visits"
                cell.detailTextLabel?.text = "Don't track visits to your home"
                cell.switchControl.isOn = excludeHome
                cell.switchControl.isEnabled = homeAddress != nil
                cell.switchControl.addTarget(self, action: #selector(homeExclusionChanged), for: .valueChanged)
                return cell
                
            default:
                return UITableViewCell()
            }
            
        case .work:
            switch WorkRow(rawValue: indexPath.row) {
            case .address:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                cell.textLabel?.text = "Work Address"
                cell.detailTextLabel?.text = workAddress ?? "Not set"
                cell.detailTextLabel?.textColor = workAddress == nil ? .systemRed : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
                
            case .exclude:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
                cell.textLabel?.text = "Exclude Work Visits"
                cell.detailTextLabel?.text = "Don't track visits to your workplace"
                cell.switchControl.isOn = excludeWork
                cell.switchControl.isEnabled = workAddress != nil
                cell.switchControl.addTarget(self, action: #selector(workExclusionChanged), for: .valueChanged)
                return cell
                
            default:
                return UITableViewCell()
            }
            
        case .settings:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.text = "About Exclusions"
            cell.textLabel?.textColor = .secondaryLabel
            cell.textLabel?.font = .systemFont(ofSize: 14)
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.text = "When enabled, visits to your home or work locations will not be automatically tracked. You can still manually add these places to your circles."
            cell.selectionStyle = .none
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        
        switch sectionType {
        case .home:
            return "Set your home address to enable exclusion"
        case .work:
            return "Set your work address to enable exclusion"
        default:
            return nil
        }
    }
}

// MARK: - UITableViewDelegate
extension HomeWorkExclusionViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .home:
            if indexPath.row == HomeRow.address.rawValue {
                showAddressPicker(for: "Home")
            }
            
        case .work:
            if indexPath.row == WorkRow.address.rawValue {
                showAddressPicker(for: "Work")
            }
            
        default:
            break
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == Section.settings.rawValue {
            return UITableView.automaticDimension
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
}

// MARK: - CLLocationManagerDelegate
extension HomeWorkExclusionViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              let type = pendingLocationType else { return }
        
        // Stop updates
        manager.stopUpdatingLocation()
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            // Dismiss loading
            if let presentedVC = self?.presentedViewController {
                presentedVC.dismiss(animated: true) {
                    self?.handleGeocodeResult(placemarks: placemarks, error: error, location: location, type: type)
                }
            } else {
                self?.handleGeocodeResult(placemarks: placemarks, error: error, location: location, type: type)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Dismiss loading
        if let presentedVC = presentedViewController {
            presentedVC.dismiss(animated: true) {
                self.showAlert(title: "Error", message: "Failed to get location: \(error.localizedDescription)")
            }
        }
        pendingLocationType = nil
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways,
           pendingLocationType != nil {
            AlertPresenter.showLoading(message: "Getting location...", from: self)
            locationManager.requestLocation()
        }
    }
    
    private func handleGeocodeResult(placemarks: [CLPlacemark]?, error: Error?, location: CLLocation, type: String) {
        if let error = error {
            showAlert(title: "Error", message: "Failed to get address: \(error.localizedDescription)")
            return
        }
        
        guard let placemark = placemarks?.first else { return }
        
        let address = formatAddress(from: placemark)
        
        // Store coordinates directly since we already have them
        let typeKey = type.lowercased()
        UserDefaults.standard.set(location.coordinate.latitude, forKey: "\(typeKey)Latitude")
        UserDefaults.standard.set(location.coordinate.longitude, forKey: "\(typeKey)Longitude")
        
        saveAddress(address, for: type)
        pendingLocationType = nil
    }
}
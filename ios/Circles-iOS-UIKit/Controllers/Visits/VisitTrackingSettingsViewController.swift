import UIKit

class VisitTrackingSettingsViewController: UITableViewController {
    
    // MARK: - Properties
    private var isTrackingEnabled = false
    private var minVisitDuration = 5
    
    // MARK: - Cells
    private enum Section: Int, CaseIterable {
        case tracking
        case preferences
        case privacy
        
        var title: String? {
            switch self {
            case .tracking: return nil
            case .preferences: return "Preferences"
            case .privacy: return "Privacy"
            }
        }
    }
    
    private enum TrackingRow: Int, CaseIterable {
        case enableTracking
    }
    
    private enum PreferencesRow: Int, CaseIterable {
        case minDuration
        case excludeHomeWork
    }
    
    private enum PrivacyRow: Int, CaseIterable {
        case clearHistory
        case exportData
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadSettings()
    }
    
    // MARK: - Setup
    private func setupView() {
        title = "Visit Tracking Settings"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(SwitchCell.self, forCellReuseIdentifier: "SwitchCell")
    }
    
    private func loadSettings() {
        isTrackingEnabled = UserDefaults.standard.bool(forKey: "visitTrackingEnabled")
        minVisitDuration = UserDefaults.standard.integer(forKey: "minVisitDuration")
        if minVisitDuration == 0 {
            minVisitDuration = 5 // default
        }
    }
    
    // MARK: - Actions
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
    
    @objc private func trackingSwitchChanged(_ sender: UISwitch) {
        isTrackingEnabled = sender.isOn
        VisitDetectionService.shared.setTrackingEnabled(isTrackingEnabled)
        
        // Update preferences on server
        updateTrackingPreferences()
        
        // Reload table to show/hide preference rows
        tableView.reloadData()
    }
    
    private func updateTrackingPreferences() {
        let preferences: [String: Any] = [
            "enabled": isTrackingEnabled,
            "minVisitDuration": minVisitDuration,
            "excludeHome": UserDefaults.standard.bool(forKey: "excludeHomeFromVisits"),
            "excludeWork": UserDefaults.standard.bool(forKey: "excludeWorkFromVisits"),
            "autoSuggestCircles": true
        ]
        
        APIService.shared.request(
            endpoint: "visits/settings/preferences",
            method: .put,
            body: preferences,
            requiresAuth: true
        ) { (result: Result<SuccessResponse, APIError>) in
            if case .failure(let error) = result {
                Logger.error("Failed to update tracking preferences: \(error)")
            }
        }
    }
    
    private func showDurationPicker() {
        let alert = UIAlertController(
            title: "Minimum Visit Duration",
            message: "How long should you stay at a place for it to count as a visit?",
            preferredStyle: .actionSheet
        )
        
        let durations = [1, 2, 3, 5, 10, 15, 20, 30] // minutes
        
        for duration in durations {
            let action = UIAlertAction(
                title: "\(duration) minute\(duration == 1 ? "" : "s")",
                style: .default
            ) { [weak self] _ in
                self?.updateMinimumDuration(duration)
            }
            
            if duration == minVisitDuration {
                action.setValue(true, forKey: "checked")
            }
            
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad popover support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            if let cell = tableView.cellForRow(at: IndexPath(row: PreferencesRow.minDuration.rawValue, section: Section.preferences.rawValue)) {
                popover.sourceRect = cell.frame
            }
        }
        
        present(alert, animated: true)
    }
    
    private func updateMinimumDuration(_ duration: Int) {
        minVisitDuration = duration
        UserDefaults.standard.set(duration, forKey: "minVisitDuration")
        
        // Update the service with new duration
        VisitDetectionService.shared.updateMinimumDuration(TimeInterval(duration * 60))
        
        // Update server preferences
        updateTrackingPreferences()
        
        // Reload the table to show new value
        tableView.reloadRows(
            at: [IndexPath(row: PreferencesRow.minDuration.rawValue, section: Section.preferences.rawValue)],
            with: .none
        )
    }
    
    private func showHomeWorkSettings() {
        let homeWorkVC = HomeWorkExclusionViewController()
        navigationController?.pushViewController(homeWorkVC, animated: true)
    }
    
    private func clearVisitHistory() {
        let alert = UIAlertController(
            title: "Clear Visit History?",
            message: "This will permanently delete all your visit history. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Clear History", style: .destructive) { [weak self] _ in
            self?.performClearHistory()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func performClearHistory() {
        let loadingAlert = AlertPresenter.showLoading(message: "Clearing visit history...", from: self)
        
        APIService.shared.request(
            endpoint: "visits/clear-all",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<SuccessResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Clear local storage too
                        UserDefaults.standard.removeObject(forKey: "localPlaceVisits")
                        self?.showAlert(title: "Success", message: "Your visit history has been cleared.")
                        
                        // Post notification to refresh visits list
                        NotificationCenter.default.post(name: NSNotification.Name("VisitHistoryCleared"), object: nil)
                        
                    case .failure(let error):
                        self?.showAlert(title: "Error", message: "Failed to clear history: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func exportVisitData() {
        let loadingAlert = AlertPresenter.showLoading(message: "Preparing export...", from: self)
        
        // Fetch all visits
        APIService.shared.request(
            endpoint: "visits",
            method: .get,
            queryParams: ["limit": "1000"],
            requiresAuth: true
        ) { [weak self] (result: Result<VisitsResponse, APIError>) in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        self?.exportVisits(response.data)
                    case .failure(let error):
                        self?.showAlert(title: "Error", message: "Failed to fetch visits: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func exportVisits(_ visits: [VisitData]) {
        // Create CSV content
        var csvContent = "Place Name,Address,Date,Duration (minutes),Category,Notes\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for visit in visits {
            let date = ISO8601DateFormatter().date(from: visit.visitedAt) ?? Date()
            let dateString = dateFormatter.string(from: date)
            let notes = visit.notes ?? ""
            let category = visit.category ?? ""
            
            // Escape quotes and commas in strings
            let escapedName = visit.placeName.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedAddress = visit.placeAddress.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedNotes = notes.replacingOccurrences(of: "\"", with: "\"\"")
            
            csvContent += "\"\(escapedName)\",\"\(escapedAddress)\",\"\(dateString)\",\(visit.duration),\"\(category)\",\"\(escapedNotes)\"\n"
        }
        
        // Create temporary file
        let fileName = "circles_visits_\(Date().timeIntervalSince1970).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            
            // Share the file
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            // iPad popover support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = tableView
                if let cell = tableView.cellForRow(at: IndexPath(row: PrivacyRow.exportData.rawValue, section: Section.privacy.rawValue)) {
                    popover.sourceRect = cell.frame
                }
            }
            
            present(activityVC, animated: true)
            
        } catch {
            showAlert(title: "Error", message: "Failed to create export file: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension VisitTrackingSettingsViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .tracking:
            return TrackingRow.allCases.count
        case .preferences:
            return isTrackingEnabled ? PreferencesRow.allCases.count : 0
        case .privacy:
            return PrivacyRow.allCases.count
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
        case .tracking:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
            cell.textLabel?.text = "Enable Visit Tracking"
            cell.detailTextLabel?.text = "Automatically track places you visit"
            cell.switchControl.isOn = isTrackingEnabled
            cell.switchControl.addTarget(self, action: #selector(trackingSwitchChanged), for: .valueChanged)
            return cell
            
        case .preferences:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            
            switch PreferencesRow(rawValue: indexPath.row) {
            case .minDuration:
                cell.textLabel?.text = "Minimum Visit Duration"
                cell.detailTextLabel?.text = "\(minVisitDuration) minutes"
                cell.accessoryType = .disclosureIndicator
                
            case .excludeHomeWork:
                cell.textLabel?.text = "Exclude Home & Work"
                cell.detailTextLabel?.text = "Don't track visits to these locations"
                cell.accessoryType = .disclosureIndicator
                
            default:
                break
            }
            
            return cell
            
        case .privacy:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            
            switch PrivacyRow(rawValue: indexPath.row) {
            case .clearHistory:
                cell.textLabel?.text = "Clear Visit History"
                cell.textLabel?.textColor = .systemRed
                
            case .exportData:
                cell.textLabel?.text = "Export Visit Data"
                cell.accessoryType = .disclosureIndicator
                
            default:
                break
            }
            
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension VisitTrackingSettingsViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .preferences:
            switch PreferencesRow(rawValue: indexPath.row) {
            case .minDuration:
                showDurationPicker()
            case .excludeHomeWork:
                showHomeWorkSettings()
            default:
                break
            }
            
        case .privacy:
            switch PrivacyRow(rawValue: indexPath.row) {
            case .clearHistory:
                clearVisitHistory()
            case .exportData:
                exportVisitData()
            default:
                break
            }
            
        default:
            break
        }
    }
}

// MARK: - SwitchCell
class SwitchCell: UITableViewCell {
    let switchControl = UISwitch()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        accessoryView = switchControl
        selectionStyle = .none
        detailTextLabel?.textColor = .secondaryLabel
        detailTextLabel?.font = .systemFont(ofSize: 12)
    }
}

// MARK: - Response Model
struct SuccessResponse: Codable {
    let success: Bool
    let message: String?
}
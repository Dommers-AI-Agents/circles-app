import UIKit

class NotificationPreferencesViewController: BaseTableViewController {
    
    // MARK: - Properties
    private var preferences: NotificationPreferences = NotificationPreferences()
    private var hasChanges = false
    private var isLoading = false
    
    // Time picker for daily summary
    private let timePicker = UIDatePicker()
    private var showingTimePicker = false
    
    private enum Section: Int, CaseIterable {
        case dailySummary
        case activityNotifications
        case socialNotifications
        case quietHours
        
        var title: String {
            switch self {
            case .dailySummary: return "Daily Summary"
            case .activityNotifications: return "Activity Notifications"
            case .socialNotifications: return "Social Notifications"
            case .quietHours: return "Quiet Hours"
            }
        }
        
        var footer: String? {
            switch self {
            case .dailySummary: return "Get a daily summary of activity in your network"
            case .activityNotifications: return "Notifications about places and circles"
            case .socialNotifications: return "Notifications about connections and messages"
            case .quietHours: return "Pause notifications during specific hours"
            }
        }
    }
    
    private enum DailySummaryRow: Int, CaseIterable {
        case enabled
        case time
    }
    
    private enum ActivityRow: Int, CaseIterable {
        case newPlaces
        case circleInvites
        case discoveryPrompts
        case weekendRecommendations
    }
    
    private enum SocialRow: Int, CaseIterable {
        case newMessages
        case connectionRequests
        case newFollowers
        case newSuggestions
    }
    
    private enum QuietHoursRow: Int, CaseIterable {
        case enabled
        case startTime
        case endTime
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPreferences()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if hasChanges {
            savePreferences()
        }
    }
    
    // MARK: - BaseViewController Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Notification Preferences"
        navigationItem.largeTitleDisplayMode = .never
        
        // Add save button if needed
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveButtonTapped)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: "SwitchCell")
        
        // Setup time picker
        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .wheels
        timePicker.addTarget(self, action: #selector(timePickerChanged), for: .valueChanged)
    }
    
    // MARK: - Data Loading
    private func loadPreferences() {
        // Show a loading indicator
        let loadingAlert = AlertPresenter.showLoading(message: "Loading preferences...", from: self)
        
        UserService.shared.fetchUserProfile { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let user):
                        self.preferences = user.notificationPreferences ?? NotificationPreferences()
                        self.updateTimePickerDate()
                        self.tableView.reloadData()
                    case .failure(let error):
                        AlertPresenter.showError(error, from: self)
                    }
                }
            }
        }
    }
    
    private func updateTimePickerDate() {
        // Parse summary time (e.g., "12:00" or "14:30")
        let timeComponents = preferences.summaryTime.split(separator: ":")
        if timeComponents.count == 2,
           let hour = Int(timeComponents[0]),
           let minute = Int(timeComponents[1]) {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                timePicker.date = date
            }
        }
    }
    
    // MARK: - Actions
    @objc private func saveButtonTapped() {
        savePreferences()
    }
    
    @objc private func timePickerChanged() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        preferences.summaryTime = formatter.string(from: timePicker.date)
        
        // Update the time display cell
        if let cell = tableView.cellForRow(at: IndexPath(row: DailySummaryRow.time.rawValue, section: Section.dailySummary.rawValue)) {
            cell.detailTextLabel?.text = formatTime(preferences.summaryTime)
        }
        
        markAsChanged()
    }
    
    private func savePreferences() {
        guard hasChanges else { return }
        
        isLoading = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        UserService.shared.updateNotificationPreferences(preferences) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success:
                    self?.hasChanges = false
                    self?.navigationItem.rightBarButtonItem?.isEnabled = false
                    AlertPresenter.showSuccess("Preferences saved", from: self!)
                case .failure(let error):
                    self?.navigationItem.rightBarButtonItem?.isEnabled = true
                    AlertPresenter.showError(error, from: self!)
                }
            }
        }
    }
    
    private func markAsChanged() {
        hasChanges = true
        navigationItem.rightBarButtonItem?.isEnabled = !isLoading
    }
    
    private func formatTime(_ time: String) -> String {
        // Convert 24-hour time to 12-hour format with AM/PM
        let components = time.split(separator: ":")
        if components.count == 2,
           let hour = Int(components[0]),
           let minute = Int(components[1]) {
            let isPM = hour >= 12
            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
            return String(format: "%d:%02d %@", displayHour, minute, isPM ? "PM" : "AM")
        }
        return time
    }
}

// MARK: - UITableViewDataSource
extension NotificationPreferencesViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .dailySummary:
            return showingTimePicker ? 3 : DailySummaryRow.allCases.count
        case .activityNotifications:
            return ActivityRow.allCases.count
        case .socialNotifications:
            return SocialRow.allCases.count
        case .quietHours:
            return QuietHoursRow.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return Section(rawValue: section)?.footer
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .dailySummary:
            if showingTimePicker && indexPath.row == 2 {
                let cell = UITableViewCell()
                cell.contentView.addSubview(timePicker)
                timePicker.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    timePicker.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    timePicker.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    timePicker.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    timePicker.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
                ])
                return cell
            }
            
            let row = DailySummaryRow(rawValue: indexPath.row)!
            switch row {
            case .enabled:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
                cell.configure(
                    title: "Daily Summary",
                    isOn: preferences.dailySummary,
                    onToggle: { [weak self] isOn in
                        self?.preferences.dailySummary = isOn
                        self?.markAsChanged()
                    }
                )
                return cell
                
            case .time:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                config.text = "Summary Time"
                config.secondaryText = formatTime(preferences.summaryTime)
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .activityNotifications:
            let row = ActivityRow(rawValue: indexPath.row)!
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            
            switch row {
            case .newPlaces:
                cell.configure(
                    title: "New Places",
                    isOn: preferences.newPlaces,
                    onToggle: { [weak self] isOn in
                        self?.preferences.newPlaces = isOn
                        self?.markAsChanged()
                    }
                )
            case .circleInvites:
                cell.configure(
                    title: "Circle Invites",
                    isOn: preferences.circleInvites,
                    onToggle: { [weak self] isOn in
                        self?.preferences.circleInvites = isOn
                        self?.markAsChanged()
                    }
                )
            case .discoveryPrompts:
                cell.configure(
                    title: "Discovery Prompts",
                    isOn: preferences.discoveryPrompts,
                    onToggle: { [weak self] isOn in
                        self?.preferences.discoveryPrompts = isOn
                        self?.markAsChanged()
                    }
                )
            case .weekendRecommendations:
                cell.configure(
                    title: "Weekend Recommendations",
                    isOn: preferences.weekendRecommendations,
                    onToggle: { [weak self] isOn in
                        self?.preferences.weekendRecommendations = isOn
                        self?.markAsChanged()
                    }
                )
            }
            return cell
            
        case .socialNotifications:
            let row = SocialRow(rawValue: indexPath.row)!
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
            
            switch row {
            case .newMessages:
                cell.configure(
                    title: "New Messages",
                    isOn: preferences.newMessages,
                    onToggle: { [weak self] isOn in
                        self?.preferences.newMessages = isOn
                        self?.markAsChanged()
                    }
                )
            case .connectionRequests:
                cell.configure(
                    title: "Connection Requests",
                    isOn: preferences.connectionRequests,
                    onToggle: { [weak self] isOn in
                        self?.preferences.connectionRequests = isOn
                        self?.markAsChanged()
                    }
                )
            case .newFollowers:
                cell.configure(
                    title: "New Followers",
                    isOn: preferences.newFollowers,
                    onToggle: { [weak self] isOn in
                        self?.preferences.newFollowers = isOn
                        self?.markAsChanged()
                    }
                )
            case .newSuggestions:
                cell.configure(
                    title: "Place Suggestions",
                    isOn: preferences.newSuggestions,
                    onToggle: { [weak self] isOn in
                        self?.preferences.newSuggestions = isOn
                        self?.markAsChanged()
                    }
                )
            }
            return cell
            
        case .quietHours:
            let row = QuietHoursRow(rawValue: indexPath.row)!
            
            switch row {
            case .enabled:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchTableViewCell
                cell.configure(
                    title: "Quiet Hours",
                    isOn: preferences.quietHoursEnabled,
                    onToggle: { [weak self] isOn in
                        self?.preferences.quietHoursEnabled = isOn
                        self?.markAsChanged()
                        
                        // Reload quiet hours section to show/hide time rows
                        self?.tableView.reloadSections(IndexSet(integer: Section.quietHours.rawValue), with: .automatic)
                    }
                )
                return cell
                
            case .startTime, .endTime:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                config.text = row == .startTime ? "Start Time" : "End Time"
                let time = row == .startTime ? preferences.quietHoursStart : preferences.quietHoursEnd
                config.secondaryText = formatTime(time)
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                
                // Disable if quiet hours are off
                cell.isUserInteractionEnabled = preferences.quietHoursEnabled
                cell.textLabel?.isEnabled = preferences.quietHoursEnabled
                cell.detailTextLabel?.isEnabled = preferences.quietHoursEnabled
                
                return cell
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == Section.dailySummary.rawValue && showingTimePicker && indexPath.row == 2 {
            return 216 // Standard height for date picker
        }
        return UITableView.automaticDimension
    }
}

// MARK: - UITableViewDelegate
extension NotificationPreferencesViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .dailySummary:
            if indexPath.row == DailySummaryRow.time.rawValue && preferences.dailySummary {
                showingTimePicker.toggle()
                tableView.reloadSections(IndexSet(integer: Section.dailySummary.rawValue), with: .automatic)
            }
            
        case .quietHours:
            if indexPath.row == QuietHoursRow.startTime.rawValue || indexPath.row == QuietHoursRow.endTime.rawValue {
                // TODO: Show time picker for quiet hours
                AlertPresenter.showSuccess("Time picker for quiet hours coming soon", from: self)
            }
            
        default:
            break
        }
    }
}

// MARK: - Custom Switch Cell
class SwitchTableViewCell: UITableViewCell {
    private let switchControl = UISwitch()
    private var onToggle: ((Bool) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        accessoryView = switchControl
        switchControl.addTarget(self, action: #selector(switchToggled), for: .valueChanged)
    }
    
    func configure(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        textLabel?.text = title
        switchControl.isOn = isOn
        self.onToggle = onToggle
    }
    
    @objc private func switchToggled() {
        onToggle?(switchControl.isOn)
    }
}
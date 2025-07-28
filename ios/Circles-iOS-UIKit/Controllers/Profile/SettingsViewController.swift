import UIKit
import UserNotifications

class SettingsViewController: BaseTableViewController {
    
    // MARK: - Properties
    private var notificationPermissionStatus: String = "Checking..."
    
    private enum Section: Int, CaseIterable {
        case account
        case privacy
        case notifications
        case about
        case tutorial
        case danger
        
        var title: String {
            switch self {
            case .account: return "Account"
            case .privacy: return "Privacy"
            case .notifications: return "Notifications"
            case .about: return "About"
            case .tutorial: return "Tutorial"
            case .danger: return "Danger Zone"
            }
        }
    }
    
    private enum AccountRow: Int, CaseIterable {
        case email
        case changePassword
        case manageAccounts
        
        var title: String {
            switch self {
            case .email: return "Email"
            case .changePassword: return "Change Password"
            case .manageAccounts: return "Manage Accounts"
            }
        }
    }
    
    private enum PrivacyRow: Int, CaseIterable {
        case profileVisibility
        case circleSharing
        
        var title: String {
            switch self {
            case .profileVisibility: return "Profile Visibility"
            case .circleSharing: return "Circle Sharing"
            }
        }
    }
    
    private enum NotificationRow: Int, CaseIterable {
        case pushNotifications
        
        var title: String {
            switch self {
            case .pushNotifications: return "Push Notifications"
            }
        }
    }
    
    private enum AboutRow: Int, CaseIterable {
        case version
        case termsOfService
        case privacyPolicy
        
        var title: String {
            switch self {
            case .version: return "Version"
            case .termsOfService: return "Terms of Service"
            case .privacyPolicy: return "Privacy Policy"
            }
        }
    }
    
    private enum TutorialRow: Int, CaseIterable {
        case resetTutorial
        
        var title: String {
            switch self {
            case .resetTutorial: return "Reset Tutorial"
            }
        }
    }
    
    private enum DangerRow: Int, CaseIterable {
        case deleteAccount
        
        var title: String {
            switch self {
            case .deleteAccount: return "Delete Account"
            }
        }
    }
    
    // MARK: - Lifecycle
    // MARK: - BaseViewController Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkNotificationPermissions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-check permissions when returning from settings
        checkNotificationPermissions()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .never
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    private func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    self?.notificationPermissionStatus = "Enabled"
                case .denied:
                    self?.notificationPermissionStatus = "Disabled"
                case .notDetermined:
                    self?.notificationPermissionStatus = "Not Set"
                case .provisional:
                    self?.notificationPermissionStatus = "Provisional"
                case .ephemeral:
                    self?.notificationPermissionStatus = "Ephemeral"
                @unknown default:
                    self?.notificationPermissionStatus = "Unknown"
                }
                
                // Reload notification section
                if let notificationSection = Section.allCases.firstIndex(of: .notifications) {
                    self?.tableView.reloadSections(IndexSet(integer: notificationSection), with: .none)
                }
            }
        }
    }
    
    // MARK: - Actions
    private func showChangePassword() {
        let changePasswordVC = ChangePasswordViewController()
        navigationController?.pushViewController(changePasswordVC, animated: true)
    }
    
    private func showAccountMerge() {
        let accountMergeVC = AccountMergeViewController()
        let navController = UINavigationController(rootViewController: accountMergeVC)
        present(navController, animated: true)
    }
    
    private func showProfileVisibility() {
        AlertPresenter.showActionSheet(
            title: "Profile Visibility",
            message: "Choose who can see your profile",
            actions: [
                (title: "Everyone", style: .default, handler: { /* Handle selection */ }),
                (title: "Connections Only", style: .default, handler: { /* Handle selection */ }),
                (title: "No One", style: .default, handler: { /* Handle selection */ })
            ],
            from: self,
            sourceView: view
        )
    }
    
    private func showCircleSharing() {
        AlertPresenter.showActionSheet(
            title: "Circle Sharing",
            message: "Default sharing settings for new circles",
            actions: [
                (title: "Public", style: .default, handler: { /* Handle selection */ }),
                (title: "Private", style: .default, handler: { /* Handle selection */ })
            ],
            from: self,
            sourceView: view
        )
    }
    
    private func openNotificationSettings() {
        // Check current permission status
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    // Never asked - show our custom prompt
                    self?.showNotificationEnablePrompt()
                case .denied:
                    // Previously denied - guide to settings
                    self?.showNotificationDeniedAlert()
                case .authorized, .provisional, .ephemeral:
                    // Already enabled - show detailed preferences
                    let preferencesVC = NotificationPreferencesViewController()
                    self?.navigationController?.pushViewController(preferencesVC, animated: true)
                @unknown default:
                    // Unknown state - try settings
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
    
    private func showNotificationEnablePrompt() {
        AlertPresenter.showConfirmation(
            title: "Enable Notifications?",
            message: "Stay updated when you receive messages, connection requests, or when interesting places are added to your network.",
            confirmTitle: "Enable",
            cancelTitle: "Not Now",
            from: self,
            onConfirm: { [weak self] in
                NotificationService.shared.requestNotificationPermissions { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self?.showSuccess("Notifications enabled! You'll stay connected with your network.")
                        } else {
                            self?.showError("Notifications were not enabled. You can enable them later in Settings.")
                        }
                        self?.checkNotificationPermissions()
                    }
                }
            }
        )
    }
    
    private func showNotificationDeniedAlert() {
        AlertPresenter.showConfirmation(
            title: "Notifications Disabled",
            message: "To enable notifications, you'll need to go to your device's Settings app and turn on notifications for Circles.",
            confirmTitle: "Open Settings",
            cancelTitle: "Cancel",
            from: self,
            onConfirm: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }
    
    private func showTermsOfService() {
        let termsVC = TermsOfServiceViewController()
        navigationController?.pushViewController(termsVC, animated: true)
    }
    
    private func showPrivacyPolicy() {
        if let url = URL(string: "https://favcircles.com/privacy.html") {
            UIApplication.shared.open(url)
        }
    }
    
    private func showResetTutorialConfirmation() {
        AlertPresenter.showConfirmation(
            title: "Reset Tutorial",
            message: "Do you want to reset the onboarding tutorial? The tutorial will show again when you navigate through the app.",
            confirmTitle: "Reset",
            isDestructive: false,
            from: self,
            onConfirm: { [weak self] in
                OnboardingManager.shared.resetTutorial()
                self?.showSuccess("Tutorial has been reset. You'll see helpful tips as you navigate the app.")
            }
        )
    }
    
    private func showDeleteAccountConfirmation() {
        AlertPresenter.showConfirmation(
            title: "Delete Account",
            message: "Are you sure you want to delete your account? This action cannot be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            from: self,
            onConfirm: { [weak self] in
                self?.deleteAccount()
            }
        )
    }
    
    private func deleteAccount() {
        let loadingAlert = AlertPresenter.showLoading(message: "Deleting Account...", from: self)
        
        UserService.shared.deleteAccount { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        AuthService.shared.logout()
                    case .failure(let error):
                        self?.showError("Failed to delete account: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Removed - using AlertPresenter.showError instead
}

// MARK: - UITableViewDataSource
extension SettingsViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .account: return AccountRow.allCases.count
        case .privacy: return PrivacyRow.allCases.count
        case .notifications: return NotificationRow.allCases.count
        case .about: return AboutRow.allCases.count
        case .tutorial: return TutorialRow.allCases.count
        case .danger: return DangerRow.allCases.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        guard let section = Section(rawValue: indexPath.section) else { return cell }
        
        switch section {
        case .account:
            if let row = AccountRow(rawValue: indexPath.row) {
                switch row {
                case .email:
                    cell.textLabel?.text = row.title
                    cell.detailTextLabel?.text = AuthService.shared.currentUser?.email
                    cell.selectionStyle = .none
                case .changePassword:
                    cell.textLabel?.text = row.title
                    cell.accessoryType = .disclosureIndicator
                case .manageAccounts:
                    cell.textLabel?.text = row.title
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .privacy:
            if let row = PrivacyRow(rawValue: indexPath.row) {
                cell.textLabel?.text = row.title
                cell.accessoryType = .disclosureIndicator
            }
            
        case .notifications:
            if let row = NotificationRow(rawValue: indexPath.row) {
                switch row {
                case .pushNotifications:
                    var config = cell.defaultContentConfiguration()
                    config.text = row.title
                    
                    // Show different text based on permission status
                    switch notificationPermissionStatus {
                    case "Enabled":
                        config.secondaryText = "Manage preferences"
                        config.secondaryTextProperties.color = .secondaryLabel
                    case "Disabled":
                        config.secondaryText = "Tap to enable"
                        config.secondaryTextProperties.color = .systemRed
                    case "Not Set":
                        config.secondaryText = "Tap to set up"
                        config.secondaryTextProperties.color = .systemOrange
                    default:
                        config.secondaryText = notificationPermissionStatus
                        config.secondaryTextProperties.color = .secondaryLabel
                    }
                    
                    cell.contentConfiguration = config
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .about:
            if let row = AboutRow(rawValue: indexPath.row) {
                switch row {
                case .version:
                    cell.textLabel?.text = row.title
                    cell.detailTextLabel?.text = "1.0.0"
                    cell.selectionStyle = .none
                case .termsOfService, .privacyPolicy:
                    cell.textLabel?.text = row.title
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .tutorial:
            if let row = TutorialRow(rawValue: indexPath.row) {
                cell.textLabel?.text = row.title
                cell.textLabel?.textColor = Constants.Colors.primary
                cell.accessoryType = .disclosureIndicator
            }
            
        case .danger:
            if let row = DangerRow(rawValue: indexPath.row) {
                cell.textLabel?.text = row.title
                cell.textLabel?.textColor = Constants.Colors.danger
                cell.accessoryType = .disclosureIndicator
            }
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension SettingsViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .account:
            if let row = AccountRow(rawValue: indexPath.row) {
                switch row {
                case .email:
                    break // Do nothing for email
                case .changePassword:
                    showChangePassword()
                case .manageAccounts:
                    showAccountMerge()
                }
            }
            
        case .privacy:
            if let row = PrivacyRow(rawValue: indexPath.row) {
                switch row {
                case .profileVisibility:
                    showProfileVisibility()
                case .circleSharing:
                    showCircleSharing()
                }
            }
            
        case .notifications:
            if let row = NotificationRow(rawValue: indexPath.row) {
                switch row {
                case .pushNotifications:
                    openNotificationSettings()
                }
            }
            
        case .about:
            if let row = AboutRow(rawValue: indexPath.row) {
                switch row {
                case .version:
                    break // Do nothing for version
                case .termsOfService:
                    showTermsOfService()
                case .privacyPolicy:
                    showPrivacyPolicy()
                }
            }
            
        case .tutorial:
            if let row = TutorialRow(rawValue: indexPath.row) {
                switch row {
                case .resetTutorial:
                    showResetTutorialConfirmation()
                }
            }
            
        case .danger:
            if let row = DangerRow(rawValue: indexPath.row) {
                switch row {
                case .deleteAccount:
                    showDeleteAccountConfirmation()
                }
            }
        }
    }
}
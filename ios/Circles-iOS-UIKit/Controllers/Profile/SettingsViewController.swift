import UIKit
import UserNotifications

class SettingsViewController: BaseTableViewController {
    
    // MARK: - Properties
    private var notificationPermissionStatus: String = "Checking..."
    
    private enum Section: Int, CaseIterable {
        case subscription
        case data
        case account
        case privacy
        case notifications
        case about
        case tutorial
        case danger
        
        var title: String {
            switch self {
            case .subscription: return "Subscription"
            case .data: return "Data"
            case .account: return "Account"
            case .privacy: return "Privacy"
            case .notifications: return "Notifications"
            case .about: return "About"
            case .tutorial: return "Tutorial"
            case .danger: return "Danger Zone"
            }
        }
    }
    
    private enum SubscriptionRow: Int, CaseIterable {
        case status
        case manage
        
        var title: String {
            switch self {
            case .status: return "Premium Status"
            case .manage: return "Manage Subscription"
            }
        }
    }
    
    private enum DataRow: Int, CaseIterable {
        case exportData
        
        var title: String {
            switch self {
            case .exportData: return "Export My Data"
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
        case troubleshoot
        
        var title: String {
            switch self {
            case .pushNotifications: return "Push Notifications"
            case .troubleshoot: return "Troubleshoot Notifications"
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
        case helpCenter
        case watchTutorial
        case resetTutorial
        
        var title: String {
            switch self {
            case .helpCenter: return "Help Center"
            case .watchTutorial: return "Watch Tutorial Video"
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
    
    private func showEmailDetails() {
        guard let email = AuthService.shared.currentUser?.email else {
            showError("Email not available")
            return
        }
        
        let alert = UIAlertController(
            title: "Account Email",
            message: email,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Copy Email", style: .default) { _ in
            UIPasteboard.general.string = email
            self.showSuccess("Email copied to clipboard")
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        
        present(alert, animated: true)
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
    
    private func showNotificationTroubleshooting() {
        let alert = UIAlertController(
            title: "Notification Troubleshooting",
            message: "If you're not receiving notifications, try these steps:",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Check iOS Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Re-register for Notifications", style: .default) { [weak self] _ in
            NotificationService.shared.updatePushToken()
            self?.showSuccess("Re-registering for push notifications...")
            
            // Check status after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.checkNotificationPermissions()
            }
        })
        
        alert.addAction(UIAlertAction(title: "Test Notification", style: .default) { [weak self] _ in
            NotificationService.shared.scheduleTestNotification()
            self?.showSuccess("Test notification scheduled. You should see it in 5 seconds.")
        })
        
        alert.addAction(UIAlertAction(title: "View Help Guide", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let helpMessage = """
            Common notification issues:
            
            1. Check Settings → Circles → Notifications is ON
            2. Check Do Not Disturb is OFF
            3. Check Focus modes aren't blocking Circles
            4. Ensure Background App Refresh is ON
            5. Check you have a stable internet connection
            
            If issues persist, try:
            - Log out and log back in
            - Delete and reinstall the app
            """
            
            AlertPresenter.showSuccess(
                title: "Notification Help",
                message: helpMessage,
                from: self
            )
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
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
    
    private func showHelpCenter() {
        let helpVC = HelpViewController()
        let navController = UINavigationController(rootViewController: helpVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    private func showTutorialVideo() {
        let tutorialVC = TutorialViewController()
        let navController = UINavigationController(rootViewController: tutorialVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
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
    
    private func showDataExport() {
        // Check if user is subscribed
        if !SubscriptionManager.shared.isSubscribed {
            // Show paywall
            SubscriptionManager.shared.showPaywall(from: self, reason: .exportFeature)
            // Note: PaywallViewController will auto-dismiss on successful purchase
            // User can retry the export action after subscribing
        } else {
            // User is subscribed, show export directly
            presentDataExportViewController()
        }
    }
    
    private func presentDataExportViewController() {
        let exportVC = DataExportViewController()
        let navController = UINavigationController(rootViewController: exportVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
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
        case .subscription: return SubscriptionRow.allCases.count
        case .data: return DataRow.allCases.count
        case .account: return AccountRow.allCases.count
        case .privacy: return PrivacyRow.allCases.count
        case .notifications: return NotificationRow.allCases.count
        case .about: return AboutRow.allCases.count
        case .tutorial: return TutorialRow.allCases.count
        case .danger: return DangerRow.allCases.count
        }
    }
    
    // Removed titleForHeaderInSection to avoid conflicts with viewForHeaderInSection
    // The custom header view in viewForHeaderInSection provides the section titles
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        
        let headerView = UIView()
        headerView.backgroundColor = Constants.Colors.background
        
        let label = UILabel()
        label.text = sectionType.title.uppercased()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = Constants.Colors.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -6)
        ])
        
        return headerView
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 38
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        // Reset cell to default state to prevent reuse issues
        cell.textLabel?.text = ""
        cell.textLabel?.textColor = Constants.Colors.label
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none
        cell.accessoryView = nil
        
        guard let section = Section(rawValue: indexPath.section) else { return cell }
        
        switch section {
        case .subscription:
            if let row = SubscriptionRow(rawValue: indexPath.row) {
                switch row {
                case .status:
                    cell.textLabel?.text = row.title
                    let status = SubscriptionManager.shared.subscriptionStatus
                    cell.detailTextLabel?.text = status.displayName
                    cell.detailTextLabel?.textColor = status.badgeColor
                    cell.accessoryType = .disclosureIndicator
                    
                    // Make it more prominent for free users
                    if status == .none {
                        cell.textLabel?.text = "🎯 " + row.title
                        cell.detailTextLabel?.text = "Upgrade to Premium"
                        cell.detailTextLabel?.textColor = Constants.Colors.primary
                        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
                    }
                case .manage:
                    cell.textLabel?.text = row.title
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .data:
            if let row = DataRow(rawValue: indexPath.row) {
                switch row {
                case .exportData:
                    cell.textLabel?.text = row.title
                    cell.accessoryType = .disclosureIndicator
                    
                    // Add icon
                    let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                    let icon = UIImage(systemName: "square.and.arrow.down", withConfiguration: config)
                    let iconView = UIImageView(image: icon)
                    iconView.tintColor = Constants.Colors.primary
                    iconView.translatesAutoresizingMaskIntoConstraints = false
                    
                    // Add premium badge if not subscribed
                    if !SubscriptionManager.shared.isSubscribed {
                        let stackView = UIStackView()
                        stackView.axis = .horizontal
                        stackView.spacing = 8
                        stackView.alignment = .center
                        
                        let premiumBadge = UILabel()
                        premiumBadge.text = "Premium"
                        premiumBadge.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
                        premiumBadge.textColor = .white
                        premiumBadge.backgroundColor = Constants.Colors.primary
                        premiumBadge.layer.cornerRadius = 4
                        premiumBadge.clipsToBounds = true
                        premiumBadge.textAlignment = .center
                        
                        // Add padding to the badge
                        let paddedBadge = UIView()
                        paddedBadge.addSubview(premiumBadge)
                        premiumBadge.translatesAutoresizingMaskIntoConstraints = false
                        NSLayoutConstraint.activate([
                            premiumBadge.topAnchor.constraint(equalTo: paddedBadge.topAnchor, constant: 2),
                            premiumBadge.bottomAnchor.constraint(equalTo: paddedBadge.bottomAnchor, constant: -2),
                            premiumBadge.leadingAnchor.constraint(equalTo: paddedBadge.leadingAnchor, constant: 6),
                            premiumBadge.trailingAnchor.constraint(equalTo: paddedBadge.trailingAnchor, constant: -6)
                        ])
                        
                        stackView.addArrangedSubview(iconView)
                        stackView.addArrangedSubview(paddedBadge)
                        cell.accessoryView = stackView
                    } else {
                        cell.accessoryView = iconView
                    }
                }
            }
            
        case .account:
            if let row = AccountRow(rawValue: indexPath.row) {
                switch row {
                case .email:
                    var config = cell.defaultContentConfiguration()
                    config.text = row.title
                    if let email = AuthService.shared.currentUser?.email {
                        config.secondaryText = email
                        config.secondaryTextProperties.color = .secondaryLabel
                    }
                    cell.contentConfiguration = config
                    cell.accessoryType = .disclosureIndicator
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
                    
                case .troubleshoot:
                    var config = cell.defaultContentConfiguration()
                    config.text = row.title
                    config.secondaryText = "Fix notification issues"
                    config.secondaryTextProperties.color = .secondaryLabel
                    cell.contentConfiguration = config
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .about:
            if let row = AboutRow(rawValue: indexPath.row) {
                var config = cell.defaultContentConfiguration()
                config.text = row.title
                
                switch row {
                case .version:
                    config.secondaryText = "1.0.0"
                    config.secondaryTextProperties.color = .secondaryLabel
                    cell.contentConfiguration = config
                    cell.selectionStyle = .none
                    cell.accessoryType = .none
                case .termsOfService, .privacyPolicy:
                    cell.contentConfiguration = config
                    cell.selectionStyle = .default
                    cell.accessoryType = .disclosureIndicator
                }
            }
            
        case .tutorial:
            if let row = TutorialRow(rawValue: indexPath.row) {
                var config = cell.defaultContentConfiguration()
                config.text = row.title
                
                if row == .resetTutorial {
                    config.textProperties.color = Constants.Colors.primary
                } else {
                    config.textProperties.color = Constants.Colors.label
                }
                
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
            }
            
        case .danger:
            if let row = DangerRow(rawValue: indexPath.row) {
                // Use content configuration to properly reset cell state
                var config = cell.defaultContentConfiguration()
                config.text = row.title
                config.textProperties.color = Constants.Colors.danger
                cell.contentConfiguration = config
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
        case .subscription:
            if let row = SubscriptionRow(rawValue: indexPath.row) {
                switch row {
                case .status:
                    showSubscriptionDetails()
                case .manage:
                    openAppStoreSubscriptionManagement()
                }
            }
            
        case .data:
            if let row = DataRow(rawValue: indexPath.row) {
                switch row {
                case .exportData:
                    showDataExport()
                }
            }
            
        case .account:
            if let row = AccountRow(rawValue: indexPath.row) {
                switch row {
                case .email:
                    showEmailDetails()
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
                case .troubleshoot:
                    showNotificationTroubleshooting()
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
                case .helpCenter:
                    showHelpCenter()
                case .watchTutorial:
                    showTutorialVideo()
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
    
    // MARK: - Subscription Methods
    
    private func showSubscriptionDetails() {
        let subscriptionVC = SubscriptionViewController()
        navigationController?.pushViewController(subscriptionVC, animated: true)
    }
    
    private func openAppStoreSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}
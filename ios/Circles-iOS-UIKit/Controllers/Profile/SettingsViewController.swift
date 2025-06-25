import UIKit

class SettingsViewController: UIViewController {
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // MARK: - Properties
    private enum Section: Int, CaseIterable {
        case account
        case privacy
        case notifications
        case about
        case danger
        
        var title: String {
            switch self {
            case .account: return "Account"
            case .privacy: return "Privacy"
            case .notifications: return "Notifications"
            case .about: return "About"
            case .danger: return "Danger Zone"
            }
        }
    }
    
    private enum AccountRow: Int, CaseIterable {
        case email
        case changePassword
        
        var title: String {
            switch self {
            case .email: return "Email"
            case .changePassword: return "Change Password"
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
    
    private enum DangerRow: Int, CaseIterable {
        case deleteAccount
        
        var title: String {
            switch self {
            case .deleteAccount: return "Delete Account"
            }
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Settings"
        
        navigationItem.largeTitleDisplayMode = .never
        
        // Add table view
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    private func showChangePassword() {
        let changePasswordVC = ChangePasswordViewController()
        navigationController?.pushViewController(changePasswordVC, animated: true)
    }
    
    private func showProfileVisibility() {
        let alert = UIAlertController(title: "Profile Visibility", message: "Choose who can see your profile", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Everyone", style: .default))
        alert.addAction(UIAlertAction(title: "Connections Only", style: .default))
        alert.addAction(UIAlertAction(title: "No One", style: .default))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        
        present(alert, animated: true)
    }
    
    private func showCircleSharing() {
        let alert = UIAlertController(title: "Circle Sharing", message: "Default sharing settings for new circles", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Public", style: .default))
        alert.addAction(UIAlertAction(title: "Private", style: .default))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        
        present(alert, animated: true)
    }
    
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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
    
    private func showDeleteAccountConfirmation() {
        let alert = UIAlertController(
            title: "Delete Account",
            message: "Are you sure you want to delete your account? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteAccount()
        })
        
        present(alert, animated: true)
    }
    
    private func deleteAccount() {
        let loadingAlert = UIAlertController(title: "Deleting Account", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        UserService.shared.deleteAccount { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success:
                        AuthService.shared.logout()
                    case .failure(let error):
                        self?.presentAlert(title: "Error", message: "Failed to delete account: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .account: return AccountRow.allCases.count
        case .privacy: return PrivacyRow.allCases.count
        case .notifications: return NotificationRow.allCases.count
        case .about: return AboutRow.allCases.count
        case .danger: return DangerRow.allCases.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
                }
            }
            
        case .privacy:
            if let row = PrivacyRow(rawValue: indexPath.row) {
                cell.textLabel?.text = row.title
                cell.accessoryType = .disclosureIndicator
            }
            
        case .notifications:
            if let row = NotificationRow(rawValue: indexPath.row) {
                cell.textLabel?.text = row.title
                cell.accessoryType = .disclosureIndicator
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
extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
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
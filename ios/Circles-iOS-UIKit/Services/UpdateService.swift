import Foundation
import UIKit

class UpdateService {
    static let shared = UpdateService()
    
    private let userDefaults = UserDefaults.standard
    private let lastVersionKey = "lastCheckedAppVersion"
    private let lastCheckDateKey = "lastUpdateCheckDate"
    private let skipVersionKey = "skippedAppVersion"
    private let checkInterval: TimeInterval = 3600 * 24 // Check once per day
    
    private init() {}
    
    // MARK: - Version Check
    
    func checkForUpdates(completion: @escaping (Bool, String?, Bool) -> Void) {
        // Get current app version
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            print("🔄 UpdateService: Failed to get current version info")
            completion(false, nil, false)
            return
        }
        
        print("🔄 UpdateService: Current version: \(currentVersion) build: \(currentBuild)")
        
        // Check if we should perform the check (rate limiting)
        if !shouldCheckForUpdate() {
            print("🔄 UpdateService: Skipping check due to rate limiting")
            completion(false, nil, false)
            return
        }
        
        // Update last check date
        userDefaults.set(Date(), forKey: lastCheckDateKey)
        
        // Check if running in TestFlight or App Store
        let isTestFlight = isRunningInTestFlight()
        print("🔄 UpdateService: Running in TestFlight: \(isTestFlight)")
        
        if isTestFlight {
            // Skip update checks for TestFlight builds
            completion(false, nil, false)
        } else {
            // For App Store, check iTunes API
            checkAppStoreVersion(currentVersion: currentVersion, completion: completion)
        }
    }
    
    // MARK: - TestFlight Check
    
    private func checkTestFlightVersion(currentVersion: String, currentBuild: String, completion: @escaping (Bool, String?, Bool) -> Void) {
        // Check against your backend for TestFlight builds
        let baseURL = APIEnvironment.production.baseURL // Use production for version checks
        guard let url = URL(string: "\(baseURL)/app/version") else {
            completion(false, nil, false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token if available
        // Skip auth for version check endpoint as it should be public
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(false, nil, false)
                }
                return
            }
            
            let latestVersion = json["version"] as? String ?? currentVersion
            let latestBuild = json["buildNumber"] as? String ?? currentBuild
            let releaseNotes = json["releaseNotes"] as? String
            let isRequired = json["isRequired"] as? Bool ?? false
            
            // Check if skipped
            if let skippedVersion = self.userDefaults.string(forKey: self.skipVersionKey),
               skippedVersion == "\(latestVersion).\(latestBuild)",
               !isRequired {
                DispatchQueue.main.async {
                    completion(false, nil, false)
                }
                return
            }
            
            let isUpdateAvailable = self.compareVersions(
                currentVersion: currentVersion,
                currentBuild: currentBuild,
                latestVersion: latestVersion,
                latestBuild: latestBuild
            )
            
            DispatchQueue.main.async {
                completion(isUpdateAvailable, releaseNotes, isRequired)
            }
        }
        
        task.resume()
    }
    
    // MARK: - App Store Check
    
    private func checkAppStoreVersion(currentVersion: String, completion: @escaping (Bool, String?, Bool) -> Void) {
        // Get your app's bundle ID
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdentifier)") else {
            completion(false, nil, false)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let appInfo = results.first else {
                DispatchQueue.main.async {
                    completion(false, nil, false)
                }
                return
            }
            
            let appStoreVersion = appInfo["version"] as? String ?? currentVersion
            let releaseNotes = appInfo["releaseNotes"] as? String
            
            // Check if skipped
            if let skippedVersion = self.userDefaults.string(forKey: self.skipVersionKey),
               skippedVersion == appStoreVersion {
                DispatchQueue.main.async {
                    completion(false, nil, false)
                }
                return
            }
            
            let isUpdateAvailable = self.isNewerVersion(latest: appStoreVersion, current: currentVersion)
            
            DispatchQueue.main.async {
                completion(isUpdateAvailable, releaseNotes, false) // App Store updates are never forced
            }
        }
        
        task.resume()
    }
    
    // MARK: - Helper Methods
    
    private func shouldCheckForUpdate() -> Bool {
        if let lastCheckDate = userDefaults.object(forKey: lastCheckDateKey) as? Date {
            return Date().timeIntervalSince(lastCheckDate) > checkInterval
        }
        return true
    }
    
    private func compareVersions(currentVersion: String, currentBuild: String, latestVersion: String, latestBuild: String) -> Bool {
        // First compare version numbers
        if isNewerVersion(latest: latestVersion, current: currentVersion) {
            return true
        }
        
        // If versions are same, compare build numbers
        if currentVersion == latestVersion {
            if let currentBuildInt = Int(currentBuild),
               let latestBuildInt = Int(latestBuild) {
                return latestBuildInt > currentBuildInt
            }
        }
        
        return false
    }
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(latestComponents.count, currentComponents.count)
        
        for i in 0..<maxLength {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }
        
        return false
    }
    
    private func isRunningInTestFlight() -> Bool {
        // Check if receipt exists in sandbox location
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL {
            return appStoreReceiptURL.lastPathComponent == "sandboxReceipt"
        }
        return false
    }
    
    // MARK: - Update Prompts
    
    func showUpdatePrompt(in viewController: UIViewController, releaseNotes: String?, isRequired: Bool) {
        let title = isRequired ? "Required Update" : "Update Available"
        let message = """
        A new version of Circles is available!
        
        \(releaseNotes ?? "This update includes bug fixes and performance improvements.")
        """
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Update Now", style: .default) { [weak self] _ in
            self?.openAppStore()
        })
        
        if !isRequired {
            alert.addAction(UIAlertAction(title: "Skip This Version", style: .default) { [weak self] _ in
                self?.skipCurrentVersion()
            })
            
            alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        }
        
        viewController.present(alert, animated: true)
    }
    
    func showUpdateBanner(in viewController: UIViewController, isRequired: Bool) {
        let banner = UpdateBannerView(isRequired: isRequired)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.alpha = 0
        
        viewController.view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Animate in
        UIView.animate(withDuration: 0.3) {
            banner.alpha = 1
        }
        
        // Auto-dismiss after 10 seconds if not required
        if !isRequired {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                UIView.animate(withDuration: 0.3, animations: {
                    banner.alpha = 0
                }) { _ in
                    banner.removeFromSuperview()
                }
            }
        }
    }
    
    private func skipCurrentVersion() {
        // Store the version being skipped
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            userDefaults.set("\(version).\(build)", forKey: skipVersionKey)
        }
    }
    
    func openAppStore() {
        if isRunningInTestFlight() {
            // Open TestFlight
            if let url = URL(string: "itms-beta://") {
                UIApplication.shared.open(url)
            }
        } else {
            // Open App Store
            if let bundleId = Bundle.main.bundleIdentifier,
               let url = URL(string: "https://apps.apple.com/app/id<YOUR_APP_ID>") { // Replace with your actual App ID
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Update Banner View

class UpdateBannerView: UIView {
    
    private let isRequired: Bool
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let updateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Update", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 14
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    init(isRequired: Bool = false) {
        self.isRequired = isRequired
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = isRequired ? UIColor.systemRed : UIColor.systemBlue
        messageLabel.text = isRequired ? "⚠️ Required update available!" : "🎉 New update available!"
        
        addSubview(messageLabel)
        addSubview(updateButton)
        
        if !isRequired {
            addSubview(closeButton)
        }
        
        // Add padding to button width
        let buttonWidthConstraint = updateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        
        var constraints = [
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            updateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            updateButton.heightAnchor.constraint(equalToConstant: 28),
            buttonWidthConstraint
        ]
        
        if isRequired {
            constraints.append(updateButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16))
        } else {
            constraints.append(updateButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8))
            constraints.append(contentsOf: [
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                closeButton.widthAnchor.constraint(equalToConstant: 24),
                closeButton.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        
        updateButton.addTarget(self, action: #selector(updateTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }
    
    @objc private func updateTapped() {
        UpdateService.shared.openAppStore()
    }
    
    @objc private func closeTapped() {
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }
}
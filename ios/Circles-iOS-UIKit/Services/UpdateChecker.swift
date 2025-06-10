import SwiftUI
import Combine

class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var updateMessage = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    func checkForUpdates() {
        // Only check for App Store updates, not TestFlight
        checkAppStoreVersion()
    }
    
    private func checkAppStoreVersion() {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)") else {
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: AppStoreResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    self?.handleAppStoreResponse(response)
                }
            )
            .store(in: &cancellables)
    }
    
    private func handleAppStoreResponse(_ response: AppStoreResponse) {
        guard let result = response.results.first,
              let latestVersion = result.version else {
            return
        }
        
        if isVersion(latestVersion, greaterThan: currentVersion) {
            updateAvailable = true
            updateMessage = "Version \(latestVersion) is available on the App Store"
        }
    }
    
    private func isVersion(_ version1: String, greaterThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Value = i < v1Components.count ? v1Components[i] : 0
            let v2Value = i < v2Components.count ? v2Components[i] : 0
            
            if v1Value > v2Value {
                return true
            } else if v1Value < v2Value {
                return false
            }
        }
        
        return false
    }
}

// MARK: - App Store Response Models
private struct AppStoreResponse: Codable {
    let results: [AppStoreResult]
}

private struct AppStoreResult: Codable {
    let version: String?
}
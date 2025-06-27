import SwiftUI
import Combine

class CircleManager: ObservableObject {
    static let shared = CircleManager()
    
    @Published var circles: [Circle] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedCircle: Circle?
    @Published var shouldNavigateToCircle = false
    
    private let circleService = CircleService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func fetchCircles() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let fetchedCircles = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Circle], Error>) in
                circleService.fetchUserCircles { result in
                    switch result {
                    case .success(let circles):
                        continuation.resume(returning: circles)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                self.circles = fetchedCircles
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func createCircle(name: String, description: String?, category: String, privacy: String, coverImage: UIImage?) async throws -> Circle {
        try await withCheckedThrowingContinuation { continuation in
            let imageData = coverImage?.jpegData(compressionQuality: 0.8)
            let categoryEnum = CircleCategory(rawValue: category) ?? .other
            let privacyEnum = PrivacyLevel(rawValue: privacy) ?? .private
            
            circleService.createCircle(
                name: name,
                description: description,
                privacy: privacyEnum,
                category: categoryEnum,
                coverImage: imageData
            ) { [weak self] result in
                switch result {
                case .success(let circle):
                    DispatchQueue.main.async {
                        self?.circles.append(circle)
                    }
                    continuation.resume(returning: circle)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateCircle(_ circle: Circle, name: String, description: String?, category: String, privacy: String, coverImage: UIImage?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let imageData = coverImage?.jpegData(compressionQuality: 0.8)
            let categoryEnum = CircleCategory(rawValue: category) ?? .other
            let privacyEnum = PrivacyLevel(rawValue: privacy) ?? .private
            
            circleService.updateCircle(
                id: circle.id,
                name: name,
                description: description,
                privacy: privacyEnum,
                category: categoryEnum,
                coverImage: imageData
            ) { [weak self] result in
                switch result {
                case .success(let updatedCircle):
                    DispatchQueue.main.async {
                        if let index = self?.circles.firstIndex(where: { $0.id == circle.id }) {
                            self?.circles[index] = updatedCircle
                        }
                        if self?.selectedCircle?.id == circle.id {
                            self?.selectedCircle = updatedCircle
                        }
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deleteCircle(_ circle: Circle) async throws {
        try await withCheckedThrowingContinuation { continuation in
            circleService.deleteCircle(id: circle.id) { [weak self] result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self?.circles.removeAll { $0.id == circle.id }
                        if self?.selectedCircle?.id == circle.id {
                            self?.selectedCircle = nil
                        }
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func navigateToCircle(id: String) {
        // First try to find the circle in our current list
        if let circle = circles.first(where: { $0.id == id }) {
            selectedCircle = circle
            shouldNavigateToCircle = true
        } else {
            // If not found, fetch it from the server
            Task {
                do {
                    let circle = try await fetchCircle(by: id)
                    await MainActor.run {
                        self.selectedCircle = circle
                        self.shouldNavigateToCircle = true
                    }
                } catch {
                    print("Failed to fetch circle: \(error)")
                }
            }
        }
    }
    
    private func fetchCircle(by id: String) async throws -> Circle {
        try await withCheckedThrowingContinuation { continuation in
            circleService.fetchCircleById(id: id) { result in
                switch result {
                case .success(let circle):
                    continuation.resume(returning: circle)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func shareCircle(_ circle: Circle) -> [Any] {
        // Create formatted text to share
        var shareText = "🟦 \(circle.name)"
        if let description = circle.description {
            shareText += "\n\(description)"
        }
        
        let memberCount = (circle.sharedWith?.count ?? 0) + (circle.followers?.count ?? 0)
        if memberCount > 0 {
            shareText += "\n👥 \(memberCount) member\(memberCount != 1 ? "s" : "")"
        }
        
        let placeCount = circle.places?.count ?? 0
        shareText += "\n📍 \(placeCount) place\(placeCount != 1 ? "s" : "")"
        
        // Add privacy emoji
        switch circle.privacy {
        case .public:
            shareText += " 🌐"
        case .myNetwork:
            shareText += " 👥"
        case .private:
            shareText += " 🔒"
        }
        
        // Add deep link
        let deepLink = "circles://circle/\(circle.id)"
        shareText += "\n\nOpen in Circles: \(deepLink)"
        
        // Add app download link
        let appStoreLink = "https://testflight.apple.com/join/YourTestFlightLink" // Replace with actual link
        shareText += "\n\nDon't have Circles? Download here: \(appStoreLink)"
        
        var items: [Any] = [shareText]
        
        // Note: Image will be loaded asynchronously in the view
        // Don't load it here to avoid blocking the UI
        
        return items
    }
}
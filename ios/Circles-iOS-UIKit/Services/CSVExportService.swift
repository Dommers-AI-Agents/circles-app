import Foundation

class CSVExportService {
    static let shared = CSVExportService()
    
    private init() {}
    
    // MARK: - Export Types
    enum ExportType {
        case all
        case circlesOnly
        case placesOnly
    }
    
    // MARK: - Public Methods
    func exportData(type: ExportType, completion: @escaping (Result<URL, Error>) -> Void) {
        Task {
            do {
                let fileURL = try await generateCSVFile(for: type)
                DispatchQueue.main.async {
                    completion(.success(fileURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    private func generateCSVFile(for type: ExportType) async throws -> URL {
        let userId = AuthService.shared.currentUser?.id ?? ""
        
        switch type {
        case .all:
            return try await generateCompleteExport(userId: userId)
        case .circlesOnly:
            return try await generateCirclesExport(userId: userId)
        case .placesOnly:
            return try await generatePlacesExport(userId: userId)
        }
    }
    
    private func generateCompleteExport(userId: String) async throws -> URL {
        // Fetch all user's circles and places
        let circles = try await fetchUserCircles(userId: userId)
        let places = try await fetchAllPlaces(from: circles)
        
        // Generate CSV content
        var csvContent = ""
        
        // Add circles section
        csvContent += "=== CIRCLES ===\n"
        csvContent += generateCirclesCSV(circles)
        csvContent += "\n\n"
        
        // Add places section
        csvContent += "=== PLACES ===\n"
        csvContent += generatePlacesCSV(places, circles: circles)
        
        // Save to file
        return try saveToFile(content: csvContent, filename: "circles_export_\(Date().timeIntervalSince1970).csv")
    }
    
    private func generateCirclesExport(userId: String) async throws -> URL {
        let circles = try await fetchUserCircles(userId: userId)
        let csvContent = generateCirclesCSV(circles)
        return try saveToFile(content: csvContent, filename: "circles_\(Date().timeIntervalSince1970).csv")
    }
    
    private func generatePlacesExport(userId: String) async throws -> URL {
        let circles = try await fetchUserCircles(userId: userId)
        let places = try await fetchAllPlaces(from: circles)
        let csvContent = generatePlacesCSV(places, circles: circles)
        return try saveToFile(content: csvContent, filename: "places_\(Date().timeIntervalSince1970).csv")
    }
    
    private func fetchUserCircles(userId: String) async throws -> [Circle] {
        return try await withCheckedThrowingContinuation { continuation in
            CircleService.shared.fetchUserCircles(userId: userId) { result in
                switch result {
                case .success(let circles):
                    continuation.resume(returning: circles)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchAllPlaces(from circles: [Circle]) async throws -> [Place] {
        var allPlaces: [Place] = []
        
        for circle in circles {
            let places = try await fetchPlacesForCircle(circleId: circle.id)
            allPlaces.append(contentsOf: places)
        }
        
        return allPlaces
    }
    
    private func fetchPlacesForCircle(circleId: String) async throws -> [Place] {
        return try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.fetchPlacesByCircleId(circleId: circleId) { result in
                switch result {
                case .success(let places):
                    continuation.resume(returning: places)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func generateCirclesCSV(_ circles: [Circle]) -> String {
        var csv = "Circle Name,Description,Privacy,Category,Number of Places,Created Date\n"
        
        for circle in circles {
            let name = escapeCSVField(circle.name)
            let description = escapeCSVField(circle.description ?? "")
            let privacy = circle.privacy.rawValue
            let category = circle.category.rawValue
            let placeCount = circle.placesCount ?? circle.places?.count ?? 0
            let createdDate = formatDate(circle.createdAt)
            
            csv += "\(name),\(description),\(privacy),\(category),\(placeCount),\(createdDate)\n"
        }
        
        return csv
    }
    
    private func generatePlacesCSV(_ places: [Place], circles: [Circle]) -> String {
        var csv = "Place Name,Address,Circle Name,Category,Public Notes,Private Notes,Rating,Tags,Website,Phone,Date Added\n"
        
        for place in places {
            let name = escapeCSVField(place.name)
            let address = escapeCSVField(place.address)
            let circleName = circles.first(where: { $0.id == place.circleId })?.name ?? ""
            let category = place.category.rawValue
            let publicNotes = escapeCSVField(place.publicNotes ?? place.notes ?? "")
            let privateNotes = escapeCSVField(place.privateNotes ?? "")
            let rating = place.rating?.description ?? ""
            let tags = place.tags?.joined(separator: "; ") ?? ""
            let website = escapeCSVField(place.website ?? "")
            let phone = escapeCSVField(place.phone ?? "")
            let dateAdded = formatDate(place.createdAt)
            
            csv += "\(name),\(address),\(escapeCSVField(circleName)),\(category),\(publicNotes),\(privateNotes),\(rating),\(escapeCSVField(tags)),\(website),\(phone),\(dateAdded)\n"
        }
        
        return csv
    }
    
    private func escapeCSVField(_ field: String) -> String {
        // If field contains comma, newline, or quote, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func saveToFile(content: String, filename: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
}
import Foundation

// MARK: - Simple Response for void operations
struct SimpleResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - CircleGroupService
/// Service for managing circle groups
class CircleGroupService {
    
    static let shared = CircleGroupService()
    private init() {}
    
    // MARK: - Helper Methods
    
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { result in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - API Methods
    
    /// Fetch all circle groups for the current user
    func fetchGroups(completion: @escaping (Result<[CircleGroup], APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/groups",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CircleGroupsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create a new circle group
    func createGroup(name: String, circleIds: [String], completion: @escaping (Result<CircleGroup, APIError>) -> Void) {
        let body: [String: Any] = [
            "name": name,
            "circleIds": circleIds
        ]
        
        APIService.shared.request(
            endpoint: "circles/groups",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<CircleGroupResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Update an existing circle group
    func updateGroup(_ groupId: String, name: String? = nil, circleIds: [String]? = nil, completion: @escaping (Result<CircleGroup, APIError>) -> Void) {
        var body: [String: Any] = [:]
        if let name = name {
            body["name"] = name
        }
        if let circleIds = circleIds {
            body["circleIds"] = circleIds
        }
        
        APIService.shared.request(
            endpoint: "circles/groups/\(groupId)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<CircleGroupResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Delete a circle group (ungroups the circles)
    func deleteGroup(_ groupId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/groups/\(groupId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Add a circle to an existing group
    func addCircleToGroup(circleId: String, groupId: String, completion: @escaping (Result<CircleGroup, APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/group",
            method: .put,
            body: ["groupId": groupId],
            requiresAuth: true
        ) { (result: Result<CircleGroupResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Remove a circle from its group
    func removeCircleFromGroup(circleId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/group",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Local Operations (for immediate UI updates)
    
    /// Create a group locally from dragged circles (optimistic update)
    func createGroupLocally(from sourceCircle: Circle, and targetCircle: Circle) -> CircleGroup {
        let groupName = "New Group" // Default name, user can rename later
        let circles = [sourceCircle, targetCircle]
        let owner = AuthService.shared.getUserId() ?? ""
        
        return CircleGroup.createFrom(circles: circles, name: groupName, owner: owner)
    }
    
    /// Generate a default group name based on circles
    func generateGroupName(for circles: [Circle]) -> String {
        if circles.count == 2 {
            let names = circles.prefix(2).map { $0.name }
            return "\(names[0]) & \(names[1])"
        } else {
            return "\(circles[0].name) & \(circles.count - 1) more"
        }
    }
}
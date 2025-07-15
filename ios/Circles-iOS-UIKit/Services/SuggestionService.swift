import Foundation

class SuggestionService {
    static let shared = SuggestionService()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - Create Suggestion
    func createSuggestion(
        message: String,
        placeId: String? = nil,
        imageUrl: String? = nil,
        completion: @escaping (Result<Suggestion, Error>) -> Void
    ) {
        var body: [String: Any] = ["message": message]
        
        if let placeId = placeId {
            body["placeId"] = placeId
        }
        
        if let imageUrl = imageUrl {
            body["imageUrl"] = imageUrl
        }
        
        apiService.request(
            endpoint: "suggestions",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { (result: Result<SuggestionResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    // MARK: - Get Network Suggestions
    func fetchNetworkSuggestions(completion: @escaping (Result<[Suggestion], Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/network",
            method: .get,
            requiresAuth: true,
            completion: { (result: Result<SuggestionsResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    // MARK: - Delete Suggestion
    func deleteSuggestion(_ suggestionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/\(suggestionId)",
            method: .delete,
            requiresAuth: true,
            completion: { (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    // MARK: - Notification Management
    private let lastViewedSuggestionsKey = "lastViewedSuggestionsTimestamp"
    
    func markSuggestionsAsViewed() {
        UserDefaults.standard.set(Date(), forKey: lastViewedSuggestionsKey)
    }
    
    func getLastViewedTimestamp() -> Date {
        return UserDefaults.standard.object(forKey: lastViewedSuggestionsKey) as? Date ?? Date.distantPast
    }
    
    func checkForNewSuggestions(completion: @escaping (Int) -> Void) {
        fetchNetworkSuggestions { [weak self] result in
            switch result {
            case .success(let suggestions):
                let lastViewed = self?.getLastViewedTimestamp() ?? Date.distantPast
                let newCount = suggestions.filter { $0.createdAt > lastViewed && !$0.isCurrentUserSuggestion }.count
                completion(newCount)
            case .failure:
                completion(0)
            }
        }
    }
    
    func getUnreadSuggestionsCount(completion: @escaping (Int) -> Void) {
        checkForNewSuggestions(completion: completion)
    }
    
    // MARK: - Comments
    func addComment(to suggestionId: String, message: String, completion: @escaping (Result<Comment, Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/\(suggestionId)/comments",
            method: .post,
            body: ["message": message],
            requiresAuth: true,
            completion: { (result: Result<CommentResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    func fetchComments(for suggestionId: String, completion: @escaping (Result<[Comment], Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/\(suggestionId)/comments",
            method: .get,
            requiresAuth: true,
            completion: { (result: Result<CommentsResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    // MARK: - Likes
    func likeSuggestion(_ suggestionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/\(suggestionId)/like",
            method: .post,
            requiresAuth: true,
            completion: { (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
    
    func unlikeSuggestion(_ suggestionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "suggestions/\(suggestionId)/like",
            method: .delete,
            requiresAuth: true,
            completion: { (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            })
    }
}

// MARK: - Response Types
// These types are already defined in the respective model files (Suggestion.swift, Comment.swift)
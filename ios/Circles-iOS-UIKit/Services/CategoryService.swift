import Foundation

// MARK: - Models
struct UserCategory: Codable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let type: CategoryType
    let icon: String?
    let color: String?
    let subcategories: [String]
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, name, type, icon, color, subcategories, createdAt, updatedAt
    }
}

struct PredefinedCategory: Codable, Identifiable {
    let id: String
    let name: String
    let type: CategoryType
    let icon: String
    let color: String
}

enum CategoryType: String, Codable, CaseIterable {
    case place = "place"
    case circle = "circle"
    case both = "both"
    
    var displayName: String {
        switch self {
        case .place: return "Places Only"
        case .circle: return "Circles Only"
        case .both: return "Both"
        }
    }
}

// MARK: - API Response Models
struct CategoriesResponse: Codable {
    let success: Bool
    let data: [UserCategory]
}

struct CategoryResponse: Codable {
    let success: Bool
    let data: UserCategory
}

struct PredefinedCategoriesResponse: Codable {
    let success: Bool
    let data: [PredefinedCategory]
}

// MARK: - Category Service
class CategoryService {
    static let shared = CategoryService()
    
    private var cachedUserCategories: [UserCategory] = []
    private var cachedPredefinedCategories: [PredefinedCategory] = []
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Helper Methods
    
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Get all categories (predefined + user's custom) for a specific type
    func getAllCategories(for type: CategoryType, completion: @escaping (Result<[CategoryItem], Error>) -> Void) {
        // Check cache first
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !cachedUserCategories.isEmpty || !cachedPredefinedCategories.isEmpty {
            
            let filteredCategories = self.filterAndCombineCategories(for: type)
            completion(.success(filteredCategories))
            return
        }
        
        // Fetch fresh data
        let group = DispatchGroup()
        var predefinedError: Error?
        var userError: Error?
        
        // Fetch predefined categories
        group.enter()
        fetchPredefinedCategories { result in
            defer { group.leave() }
            switch result {
            case .success(let categories):
                self.cachedPredefinedCategories = categories
            case .failure(let error):
                predefinedError = error
            }
        }
        
        // Fetch user categories
        group.enter()
        fetchUserCategories { result in
            defer { group.leave() }
            switch result {
            case .success(let categories):
                self.cachedUserCategories = categories
            case .failure(let error):
                userError = error
            }
        }
        
        group.notify(queue: .main) {
            // If we got at least one type successfully, proceed
            if predefinedError == nil || userError == nil {
                self.lastFetchTime = Date()
                let filteredCategories = self.filterAndCombineCategories(for: type)
                completion(.success(filteredCategories))
            } else {
                // Both failed, return the user error (more likely to be actionable)
                completion(.failure(userError ?? predefinedError!))
            }
        }
    }
    
    /// Get user's custom categories
    func fetchUserCategories(completion: @escaping (Result<[UserCategory], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/categories",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CategoriesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get predefined categories
    func fetchPredefinedCategories(completion: @escaping (Result<[PredefinedCategory], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/categories/predefined",
            method: .get,
            requiresAuth: true
        ) { (result: Result<PredefinedCategoriesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create a new custom category
    func createCategory(name: String, type: CategoryType, icon: String? = nil, color: String? = nil, subcategories: [String] = [], completion: @escaping (Result<UserCategory, Error>) -> Void) {
        
        var body: [String: Any] = [
            "name": name,
            "type": type.rawValue
        ]
        
        if let icon = icon { body["icon"] = icon }
        if let color = color { body["color"] = color }
        if !subcategories.isEmpty { body["subcategories"] = subcategories }
        
        APIService.shared.request(
            endpoint: "users/categories",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCategoryResponse, APIError>) in
            switch result {
            case .success(let response):
                // Update cache
                self?.cachedUserCategories.append(response.data)
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Update an existing custom category
    func updateCategory(categoryId: String, name: String? = nil, type: CategoryType? = nil, icon: String? = nil, color: String? = nil, subcategories: [String]? = nil, completion: @escaping (Result<UserCategory, Error>) -> Void) {
        
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let type = type { body["type"] = type.rawValue }
        if let icon = icon { body["icon"] = icon }
        if let color = color { body["color"] = color }
        if let subcategories = subcategories { body["subcategories"] = subcategories }
        
        APIService.shared.request(
            endpoint: "users/categories/\(categoryId)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<UserCategoryResponse, APIError>) in
            switch result {
            case .success(let response):
                // Update cache
                if let index = self?.cachedUserCategories.firstIndex(where: { $0.id == categoryId }) {
                    self?.cachedUserCategories[index] = response.data
                }
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Delete a custom category
    func deleteCategory(categoryId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/categories/\(categoryId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                // Remove from cache
                self?.cachedUserCategories.removeAll { $0.id == categoryId }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Clear cache (useful when user logs out)
    func clearCache() {
        cachedUserCategories = []
        cachedPredefinedCategories = []
        lastFetchTime = nil
    }
    
    // MARK: - Private Methods
    
    private func filterAndCombineCategories(for type: CategoryType) -> [CategoryItem] {
        var items: [CategoryItem] = []
        
        // Add predefined categories
        let filteredPredefined = cachedPredefinedCategories.filter { category in
            category.type == .both || category.type == type
        }
        
        items.append(contentsOf: filteredPredefined.map { CategoryItem.predefined($0) })
        
        // Add user categories
        let filteredUser = cachedUserCategories.filter { category in
            category.type == .both || category.type == type
        }
        
        items.append(contentsOf: filteredUser.map { CategoryItem.custom($0) })
        
        return items
    }
}

// MARK: - Category Item (Unified model for UI)
enum CategoryItem: Identifiable {
    case predefined(PredefinedCategory)
    case custom(UserCategory)
    
    var id: String {
        switch self {
        case .predefined(let category): return category.id
        case .custom(let category): return category.id
        }
    }
    
    var name: String {
        switch self {
        case .predefined(let category): return category.name
        case .custom(let category): return category.name
        }
    }
    
    var icon: String? {
        switch self {
        case .predefined(let category): return category.icon
        case .custom(let category): return category.icon
        }
    }
    
    var color: String? {
        switch self {
        case .predefined(let category): return category.color
        case .custom(let category): return category.color
        }
    }
    
    var type: CategoryType {
        switch self {
        case .predefined(let category): return category.type
        case .custom(let category): return category.type
        }
    }
    
    var isCustom: Bool {
        switch self {
        case .predefined: return false
        case .custom: return true
        }
    }
    
    var customCategoryId: String? {
        switch self {
        case .predefined: return nil
        case .custom(let category): return category.id
        }
    }
}

// MARK: - Response Types
struct UserCategoryResponse: Codable {
    let success: Bool
    let data: UserCategory
}


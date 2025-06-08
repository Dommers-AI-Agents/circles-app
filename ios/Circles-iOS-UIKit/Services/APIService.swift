import Foundation

// MARK: - API Errors
enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case httpError(Int, Data?)
    case decodingFailed(Error)
    case noInternet
    case unauthorized
    case serverError
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, _):
            return "HTTP Error: \(statusCode)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noInternet:
            return "No internet connection"
        case .unauthorized:
            return "You are not authorized to perform this action"
        case .serverError:
            return "Server error occurred"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// MARK: - API Environment
enum APIEnvironment {
    case development
    case staging
    case production
    
    var baseURL: String {
        switch self {
        case .development:
            return "http://192.168.0.120:3001/api"
        case .staging:
            return "https://api-staging.circles-app.com/api"
        case .production:
            return "https://circles-backend-778088177220.us-central1.run.app/api"
        }
    }
}

// MARK: - Request Method
enum RequestMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Service
class APIService {
    static let shared = APIService()
    
    // Current environment
    #if DEBUG
    // Use production environment even in DEBUG to connect to Firebase backend
    private var environment: APIEnvironment = .production
    #else
    private var environment: APIEnvironment = .production
    #endif
    
    // Session and configuration
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    // Authentication
    private var authToken: String?
    private var refreshToken: String?
    
    // Logging
    private var isLoggingEnabled = true
    
    // Rate limiting
    private var rateLimitRemaining: Int = 100
    private var rateLimitReset: Date?
    
    // Network status
    private var networkMonitorId = "APIService"
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
        
        // Setup date decoding strategy for ISO8601 with fractional seconds
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try with fractional seconds first
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            // Fallback to without fractional seconds
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected date string to be ISO8601-formatted with or without fractional seconds")
        }
        
        // Load saved tokens if available
        authToken = UserDefaults.standard.string(forKey: "authToken")
        refreshToken = UserDefaults.standard.string(forKey: "refreshToken")
        
        // Monitor network status
        NetworkMonitor.shared.addObserver(id: networkMonitorId) { isConnected in
            // If connection restored, we could potentially retry failed requests
            if isConnected {
                print("🌐 Network connection restored")
            } else {
                print("⚠️ Network connection lost")
            }
        }
    }
    
    deinit {
        NetworkMonitor.shared.removeObserver(id: networkMonitorId)
    }
    
    // MARK: - Configuration Methods
    
    func configure(environment: APIEnvironment, loggingEnabled: Bool = true) {
        self.environment = environment
        self.isLoggingEnabled = loggingEnabled
    }
    
    func setAuthToken(_ token: String) {
        self.authToken = token
        UserDefaults.standard.set(token, forKey: "authToken")
    }
    
    func setRefreshToken(_ token: String) {
        self.refreshToken = token
        UserDefaults.standard.set(token, forKey: "refreshToken")
    }
    
    func clearTokens() {
        self.authToken = nil
        self.refreshToken = nil
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
    }
    
    // MARK: - Request Methods
    
    func request<T: Decodable>(
        endpoint: String,
        method: RequestMethod = .get,
        queryParams: [String: String]? = nil,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = true,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        // Check internet connection
        guard NetworkMonitor.shared.isConnected else {
            completion(.failure(.noInternet))
            return
        }
        
        // Check rate limiting
        if let resetDate = rateLimitReset, rateLimitRemaining <= 5 {
            let currentDate = Date()
            if currentDate < resetDate {
                // Wait until rate limit resets
                let delay = resetDate.timeIntervalSince(currentDate)
                if isLoggingEnabled {
                    print("⚠️ Rate limit almost exceeded. Delaying request for \(Int(delay)) seconds.")
                }
                
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.performRequest(
                        endpoint: endpoint,
                        method: method,
                        queryParams: queryParams,
                        body: body,
                        headers: headers,
                        requiresAuth: requiresAuth,
                        completion: completion
                    )
                }
                return
            }
        }
        
        performRequest(
            endpoint: endpoint,
            method: method,
            queryParams: queryParams,
            body: body,
            headers: headers,
            requiresAuth: requiresAuth,
            completion: completion
        )
    }
    
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: RequestMethod,
        queryParams: [String: String]?,
        body: [String: Any]?,
        headers: [String: String]?,
        requiresAuth: Bool,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: "\(environment.baseURL)/\(endpoint)") else {
            completion(.failure(.invalidURL))
            return
        }
        
        // Add query parameters if provided
        if let queryParams = queryParams {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = urlComponents.url else {
            completion(.failure(.invalidURL))
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add auth token if required and available
        if requiresAuth, let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add default headers
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add custom headers if provided
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add body data if provided
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                completion(.failure(.requestFailed(error)))
                return
            }
        }
        
        // Log request details if logging is enabled
        if isLoggingEnabled {
            logRequest(request)
        }
        
        // Execute the request
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Handle network errors
            if let error = error {
                let apiError: APIError
                
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        apiError = .noInternet
                    default:
                        apiError = .requestFailed(error)
                    }
                } else {
                    apiError = .requestFailed(error)
                }
                
                self.logError(apiError)
                completion(.failure(apiError))
                return
            }
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logError(APIError.invalidResponse)
                completion(.failure(.invalidResponse))
                return
            }
            
            // Update rate limiting information if available
            if let remainingString = httpResponse.allHeaderFields["X-RateLimit-Remaining"] as? String,
               let remaining = Int(remainingString),
               let resetString = httpResponse.allHeaderFields["X-RateLimit-Reset"] as? String,
               let resetTimestamp = Double(resetString) {
                
                self.rateLimitRemaining = remaining
                self.rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
                
                if self.isLoggingEnabled && remaining < 20 {
                    print("⚠️ Rate limit warning: \(remaining) requests remaining")
                }
            }
            
            // Log response details if logging is enabled
            if self.isLoggingEnabled {
                self.logResponse(httpResponse, data: data)
            }
            
            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200..<300:
                // Success - continue to parsing
                break
                
            case 401:
                // Unauthorized - try to refresh token if available
                if requiresAuth && self.refreshToken != nil {
                    self.refreshAuthToken { result in
                        switch result {
                        case .success(let newToken):
                            self.setAuthToken(newToken)
                            // Retry the original request with the new token
                            self.request(
                                endpoint: endpoint,
                                method: method,
                                queryParams: queryParams,
                                body: body,
                                headers: headers,
                                requiresAuth: requiresAuth,
                                completion: completion
                            )
                        case .failure:
                            completion(.failure(.unauthorized))
                        }
                    }
                    return
                } else {
                    completion(.failure(.unauthorized))
                    return
                }
                
            case 400, 403, 404:
                completion(.failure(.httpError(httpResponse.statusCode, data)))
                return
                
            case 429:
                // Rate limit exceeded
                if let resetString = httpResponse.allHeaderFields["X-RateLimit-Reset"] as? String,
                   let resetTimestamp = Double(resetString) {
                    
                    let resetDate = Date(timeIntervalSince1970: resetTimestamp)
                    let delay = resetDate.timeIntervalSince(Date())
                    
                    if self.isLoggingEnabled {
                        print("⚠️ Rate limit exceeded. Retrying in \(Int(delay)) seconds.")
                    }
                    
                    // Retry after the rate limit resets
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.request(
                            endpoint: endpoint,
                            method: method,
                            queryParams: queryParams,
                            body: body,
                            headers: headers,
                            requiresAuth: requiresAuth,
                            completion: completion
                        )
                    }
                    return
                }
                
                completion(.failure(.httpError(httpResponse.statusCode, data)))
                return
                
            case 500..<600:
                completion(.failure(.serverError))
                return
                
            default:
                completion(.failure(.httpError(httpResponse.statusCode, data)))
                return
            }
            
            // Ensure we have data
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            // Parse the data
            do {
                let result = try self.decoder.decode(T.self, from: data)
                completion(.success(result))
            } catch {
                print("🔍 =================== DECODING ERROR ===================")
                print("🔍 ERROR: \(error)")
                print("🔍 ERROR DESCRIPTION: \(error.localizedDescription)")
                
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("🔍 Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("🔍 Context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("🔍 Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("🔍 Context: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("🔍 Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("🔍 Context: \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        print("🔍 Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("🔍 Context: \(context.debugDescription)")
                    @unknown default:
                        print("🔍 Unknown decoding error")
                    }
                }
                
                // Always print the raw JSON data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("🔍 RAW JSON RESPONSE:")
                    print(jsonString)
                } else {
                    print("🔍 Could not convert data to string")
                }
                print("🔍 ===================================================")
                
                self.logError(APIError.decodingFailed(error))
                
                completion(.failure(.decodingFailed(error)))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Token Refresh
    
    private func refreshAuthToken(completion: @escaping (Result<String, APIError>) -> Void) {
        guard let refreshToken = refreshToken else {
            completion(.failure(.unauthorized))
            return
        }
        
        let endpoint = "auth/refresh-token"
        let body = ["refreshToken": refreshToken]
        
        request(
            endpoint: endpoint,
            method: .post,
            body: body,
            requiresAuth: false
        ) { (result: Result<RefreshTokenResponse, APIError>) in
            switch result {
            case .success(let response):
                if let newToken = response.token {
                    completion(.success(newToken))
                } else {
                    completion(.failure(.unauthorized))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Logging Utilities
    
    private func logRequest(_ request: URLRequest) {
        print("📤 REQUEST: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "no_url")")
        
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("📋 HEADERS:")
            headers.forEach { print("  \($0.key): \($0.value)") }
        }
        
        if let body = request.httpBody, !body.isEmpty {
            printJSON(from: body, prefix: "📦 BODY: ")
        }
    }
    
    private func logResponse(_ response: HTTPURLResponse, data: Data?) {
        print("📥 RESPONSE: \(response.statusCode) - \(response.url?.absoluteString ?? "no_url")")
        
        if let headers = response.allHeaderFields as? [String: Any], !headers.isEmpty {
            print("📋 HEADERS:")
            headers.forEach { print("  \($0.key): \($0.value)") }
        }
        
        if let data = data, !data.isEmpty {
            printJSON(from: data, prefix: "📦 BODY: ")
        }
    }
    
    private func logError(_ error: APIError) {
        print("❌ API ERROR: \(error.localizedDescription)")
    }
    
    private func printJSON(from data: Data, prefix: String = "") {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                print("\(prefix)\(prettyString)")
            }
        } catch {
            if let string = String(data: data, encoding: .utf8) {
                print("\(prefix)\(string)")
            }
        }
    }
}

// MARK: - Response Types

struct RefreshTokenResponse: Decodable {
    let success: Bool
    let token: String?
}
import Foundation

// MARK: - API Errors
/**
 Enhanced API error handling that parses server error responses to provide user-friendly messages.
 
 Features:
 - Parses server error responses to extract meaningful error messages
 - Falls back to user-friendly status code messages when server response unavailable
 - Polishes error message formatting (capitalization, punctuation)
 - Provides context-appropriate error messages for different HTTP statuses
 */
enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case httpError(Int, Data?)
    case decodingFailed(Error)
    case noInternet
    case unauthorized
    case serverError
    case duplicateRequest
    case processingFailed
    case processingTimeout
    case rateLimited(retryAfter: TimeInterval?)
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, let data):
            return parseServerErrorMessage(statusCode: statusCode, data: data)
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noInternet:
            return "No internet connection"
        case .unauthorized:
            return "You are not authorized to perform this action"
        case .serverError:
            return "Server error occurred"
        case .duplicateRequest:
            return "Duplicate request prevented"
        case .processingFailed:
            return "Video processing failed"
        case .processingTimeout:
            return "Video processing took too long"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Too many requests. Please try again in \(Int(retryAfter)) seconds"
            }
            return "Too many requests. Please try again in a moment"
        case .unknown:
            return "Unknown error occurred"
        }
    }
    
    // MARK: - Server Error Message Parsing  
    private func parseServerErrorMessage(statusCode: Int, data: Data?) -> String {
        // Debug logging for error parsing
        if let data = data, let rawResponse = String(data: data, encoding: .utf8) {
            Logger.debug("APIError: Parsing error response - Status: \(statusCode), Response: \(rawResponse)")
        }
        
        // Try to parse server error response
        if let data = data,
           let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            // Use server's error message if available
            if !errorResponse.message.isEmpty {
                Logger.debug("APIError: Using server message: \(errorResponse.message)")
                // Make the message more user-friendly
                return polishErrorMessage(errorResponse.message)
            }
            
            // If there are specific field errors, use the helper to get them
            let allErrors = errorResponse.allErrorMessages
            if allErrors != errorResponse.message {
                return polishErrorMessage(allErrors)
            }
        }
        
        // If we can't parse the response, try to extract a simple message
        if let data = data,
           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let simpleMessage = jsonObject["message"] as? String {
            return polishErrorMessage(simpleMessage)
        }
        
        // Fallback to user-friendly status code messages
        return userFriendlyStatusMessage(for: statusCode)
    }
    
    private func polishErrorMessage(_ message: String) -> String {
        // Capitalize first letter and ensure proper punctuation
        var polished = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !polished.isEmpty {
            polished = polished.prefix(1).uppercased() + polished.dropFirst()
            if !polished.hasSuffix(".") && !polished.hasSuffix("!") && !polished.hasSuffix("?") {
                polished += "."
            }
        }
        return polished.isEmpty ? "An error occurred." : polished
    }
    
    private func userFriendlyStatusMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "Invalid request. Please check your input and try again."
        case 401:
            return "You are not logged in. Please log in and try again."
        case 403:
            return "You don't have permission to perform this action."
        case 404:
            return "The requested resource could not be found."
        case 409:
            return "This action conflicts with existing data. Please try again."
        case 422:
            return "The provided data is invalid. Please check your input."
        case 429:
            return "Too many requests. Please wait a moment and try again."
        case 500...599:
            return "Server error occurred. Please try again later."
        default:
            return "An error occurred (Error \(statusCode)). Please try again."
        }
    }
}

// MARK: - API Environment
enum APIEnvironment {
    case development
    case staging
    case production
    
    // Static current environment based on build configuration
    static var current: APIEnvironment {
        #if DEBUG
        // Use production environment even in DEBUG to connect to Firebase backend
        return .production
        #else
        return .production
        #endif
    }
    
    var baseURL: String {
        switch self {
        case .development:
            return "http://192.168.0.120:3001/api"
        case .staging:
            return "https://api-staging.circles-app.com/api"
        case .production:
            return "https://circles-backend-196924649787.us-central1.run.app/api"
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
    
    // Current environment - defaults to static property but can be overridden
    private var environment: APIEnvironment = APIEnvironment.current
    
    // Session and configuration
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    // Authentication
    private var authToken: String?
    private var refreshToken: String?
    private let keychainService = KeychainService.shared
    
    // Logging
    public enum APILogLevel: Int, Comparable {
        case none = 0
        case errors = 1
        case minimal = 2
        case verbose = 3
        
        public static func < (lhs: APILogLevel, rhs: APILogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    private var logLevel: APILogLevel = .errors  // Only log errors by default
    
    // Rate limiting
    private var rateLimitRemaining: Int = 100
    private var rateLimitReset: Date?
    private var retryQueue = [() -> Void]()
    private var rateLimitBackoffMultiplier: TimeInterval = 1.0
    private let maxBackoffMultiplier: TimeInterval = 32.0
    
    // Network status
    private var networkMonitorId = "APIService"
    
    // Request deduplication (simple approach)
    private var pendingGETRequests = Set<String>()
    private var pendingRequestTimers = [String: Timer]()
    private var lastRequestTimes = [String: Date]()
    private let minRequestInterval: TimeInterval = 0.5 // Minimum 500ms between identical requests to reduce load
    
    // Logger flags
    private var hasLoggedNoInternetOnce = false
    
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
        
        // Load saved tokens from Keychain if available
        authToken = keychainService.getAuthToken()
        refreshToken = keychainService.getRefreshToken()
        Logger.debug("APIService: Initialized with auth token: \(authToken != nil)")
        
        // Monitor network status
        NetworkMonitor.shared.addObserver(id: networkMonitorId) { isConnected in
            // If connection restored, we could potentially retry failed requests
            if isConnected {
                // Network connection restored
            } else {
                Logger.warning("Network connection lost")
            }
        }
    }
    
    deinit {
        NetworkMonitor.shared.removeObserver(id: networkMonitorId)
    }
    
    // MARK: - Configuration Methods
    
    func configure(environment: APIEnvironment, loggingEnabled: Bool = true) {
        self.environment = environment
        self.logLevel = loggingEnabled ? .minimal : .errors
    }
    
    func setAuthToken(_ token: String) {
        Logger.debug("APIService: Setting auth token")
        self.authToken = token
        keychainService.saveAuthToken(token)
    }
    
    func setRefreshToken(_ token: String) {
        self.refreshToken = token
        keychainService.saveRefreshToken(token)
    }
    
    func clearTokens() {
        self.authToken = nil
        self.refreshToken = nil
        keychainService.clearAllTokens()
    }
    
    func clearPendingRequests() {
        // Clear all pending GET request tracking
        pendingGETRequests.removeAll()
        
        // Invalidate and clear all pending timers
        for timer in pendingRequestTimers.values {
            timer.invalidate()
        }
        pendingRequestTimers.removeAll()
        
        Logger.debug("APIService: Cleared all pending requests and timers")
    }
    
    func clearPendingRequestsForEndpoint(_ endpoint: String) {
        // Clear pending requests that match the endpoint pattern
        let keysToRemove = pendingGETRequests.filter { $0.contains(endpoint) }
        for key in keysToRemove {
            pendingGETRequests.remove(key)
            pendingRequestTimers[key]?.invalidate()
            pendingRequestTimers.removeValue(forKey: key)
        }
        Logger.debug("APIService: Cleared \(keysToRemove.count) pending requests for endpoint: \(endpoint)")
    }
    
    // MARK: - Logging Configuration
    func setLogLevel(_ level: APILogLevel) {
        self.logLevel = level
    }
    
    // MARK: - Request Deduplication
    
    private func createRequestKey(endpoint: String, method: RequestMethod, body: [String: Any]?) -> String {
        let bodyData = body?.compactMapValues { $0 } ?? [:]
        let bodyString = bodyData.keys.sorted().map { "\($0)=\(bodyData[$0] ?? "")" }.joined(separator: "&")
        return "\(method.rawValue):\(endpoint):\(bodyString)"
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
        // Improved duplicate request prevention for GET requests
        // Only prevent duplicates for identical requests within a short time window
        if method == .get {
            let requestKey = createRequestKey(endpoint: endpoint, method: method, body: body)
            
            // Only prevent duplicates for specific endpoints that are problematic
            let shouldPreventDuplicates = endpoint.contains("/users/") || 
                                         endpoint.contains("/circles/") ||
                                         endpoint.contains("/places/")
            
            if shouldPreventDuplicates && pendingGETRequests.contains(requestKey) {
                Logger.debug("Preventing duplicate GET request: \(requestKey)")
                completion(.failure(.duplicateRequest))
                return
            }
            
            if shouldPreventDuplicates {
                pendingGETRequests.insert(requestKey)
                
                // Clean up pending request after 0.5 seconds (reduced from 1.0)
                let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.pendingGETRequests.remove(requestKey)
                    self?.pendingRequestTimers.removeValue(forKey: requestKey)
                    Logger.debug("Cleaned up stale pending request: \(requestKey)")
                }
                pendingRequestTimers[requestKey] = timer
            }
        }
        
        // Check internet connection silently
        guard NetworkMonitor.shared.isConnected else {
            // Only log once per session using instance variable
            if !hasLoggedNoInternetOnce {
                Logger.error("APIService: No internet connection")
                hasLoggedNoInternetOnce = true
            }
            completion(.failure(.noInternet))
            return
        }
        
        // Check rate limiting
        if let resetDate = rateLimitReset, rateLimitRemaining <= 5 {
            let currentDate = Date()
            if currentDate < resetDate {
                // Wait until rate limit resets
                let delay = resetDate.timeIntervalSince(currentDate)
                if logLevel >= .minimal {
                    Logger.warning("Rate limit almost exceeded. Delaying request for \(Int(delay)) seconds.")
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
            retryCount: 0,
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
        retryCount: Int = 0,
        completion: @escaping (Result<T, APIError>) -> Void
    ) {
        if logLevel == .verbose {
            print("📡 API APIService: Starting request")
            print("📡 API APIService: Endpoint: \(endpoint)")
            print("📡 API APIService: Method: \(method.rawValue)")
            print("📡 API APIService: Requires Auth: \(requiresAuth)")
        }
        
        // Rate limiting check - prevent duplicate requests too close together
        let requestKey = "\(method.rawValue):\(endpoint)"
        if let lastRequestTime = lastRequestTimes[requestKey] {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
            if timeSinceLastRequest < minRequestInterval {
                if logLevel >= .minimal {
                    print("⏰ APIService: Throttling request to \(endpoint) (last request \(Int(timeSinceLastRequest * 1000))ms ago)")
                }
                // Delay the request
                DispatchQueue.main.asyncAfter(deadline: .now() + (minRequestInterval - timeSinceLastRequest)) {
                    self.performRequest(
                        endpoint: endpoint,
                        method: method,
                        queryParams: queryParams,
                        body: body,
                        headers: headers,
                        requiresAuth: requiresAuth,
                        retryCount: retryCount,
                        completion: completion
                    )
                }
                return
            }
        }
        
        // Update last request time
        lastRequestTimes[requestKey] = Date()
        
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: "\(environment.baseURL)/\(endpoint)") else {
            if logLevel >= .errors {
                print("❌ ERROR APIService: Invalid URL for endpoint: \(endpoint)")
            }
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
        
        // Disable caching for GET requests to ensure fresh data
        if method == .get {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        
        // Add auth token if required and available
        if requiresAuth {
            if logLevel == .verbose {
                print("🔐 AUTH APIService: Checking auth token for \(endpoint)")
            }
            
            // Try to get token from keychain if not in memory
            if authToken == nil {
                if logLevel == .verbose {
                    print("🔐 AUTH APIService: No token in memory, checking keychain")
                }
                if let token = keychainService.getAuthToken() {
                    authToken = token
                    if logLevel == .verbose {
                        print("🔐 AUTH APIService: Retrieved token from keychain")
                    }
                } else {
                    if logLevel >= .errors {
                        print("❌ ERROR APIService: Failed to get token from keychain")
                    }
                }
            }
            
            if let token = authToken {
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if logLevel == .verbose {
                    print("✅ SUCCESS APIService: Auth token added to request headers")
                    print("🔐 AUTH APIService: Token length: \(token.count)")
                }
            } else {
                if logLevel >= .errors {
                    print("❌ ERROR APIService: No auth token available for protected endpoint \(endpoint)")
                }
                Logger.warning("APIService: No auth token available for protected endpoint \(endpoint)")
                completion(.failure(.unauthorized))
                return
            }
        }
        
        // Add default headers
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add cache control headers to prevent 304 responses
        if method == .get {
            request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.addValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        
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
        if logLevel == .verbose {
            logRequest(request)
        }
        
        // Execute the request
        if logLevel == .verbose {
            print("📡 API APIService: Executing HTTP request to: \(url.absoluteString)")
        }
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { 
                // Can't access instance properties when self is nil
                print("❌ ERROR APIService: Self deallocated during request")
                return 
            }
            
            if self.logLevel == .verbose {
                print("📡 API APIService: Response received for \(endpoint)")
            }
            
            // Handle network errors
            if let error = error {
                if self.logLevel >= .errors {
                    print("❌ ERROR APIService: Network error for \(endpoint): \(error.localizedDescription)")
                    if self.logLevel == .verbose {
                        print("❌ ERROR APIService: Error type: \(type(of: error))")
                        print("❌ ERROR APIService: Error domain: \((error as NSError).domain)")
                        print("❌ ERROR APIService: Error code: \((error as NSError).code)")
                    }
                }
                
                let apiError: APIError
                
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        apiError = .noInternet
                        if self.logLevel >= .errors {
                            print("❌ ERROR APIService: No internet connection")
                        }
                    default:
                        apiError = .requestFailed(error)
                        if self.logLevel >= .errors {
                            print("❌ ERROR APIService: URL error: \(urlError.code)")
                        }
                    }
                } else {
                    apiError = .requestFailed(error)
                }
                
                self.logError(apiError)
                
                // Clean up pending request tracking for GET requests
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
                completion(.failure(apiError))
                return
            }
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                if self.logLevel >= .errors {
                    print("❌ ERROR APIService: Invalid response type for \(endpoint)")
                    if self.logLevel == .verbose {
                        print("❌ ERROR APIService: Response type: \(type(of: response))")
                    }
                }
                self.logError(APIError.invalidResponse)
                
                // Clean up pending request tracking for GET requests
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
                completion(.failure(.invalidResponse))
                return
            }
            
            if self.logLevel == .verbose {
                print("📡 API APIService: HTTP Status Code: \(httpResponse.statusCode) for \(endpoint)")
                print("📡 API APIService: Response headers: \(httpResponse.allHeaderFields)")
            } else if self.logLevel == .minimal {
                print("📡 API APIService: \(endpoint) - Status: \(httpResponse.statusCode)")
            }
            
            // Update rate limiting information if available
            if let remainingString = httpResponse.allHeaderFields["X-RateLimit-Remaining"] as? String,
               let remaining = Int(remainingString),
               let resetString = httpResponse.allHeaderFields["X-RateLimit-Reset"] as? String,
               let resetTimestamp = Double(resetString) {
                
                self.rateLimitRemaining = remaining
                self.rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
                
                if self.logLevel >= .minimal && remaining < 20 {
                    Logger.warning("Rate limit warning: \(remaining) requests remaining")
                }
            }
            
            // Log response details if logging is enabled
            if self.logLevel == .verbose {
                self.logResponse(httpResponse, data: data)
            }
            
            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200..<300:
                // Success - continue to parsing
                break
                
            case 401:
                if self.logLevel >= .errors {
                    print("❌ ERROR APIService: 401 Unauthorized for \(endpoint)")
                }
                if self.logLevel == .verbose {
                    print("🔐 AUTH APIService: requiresAuth: \(requiresAuth), hasRefreshToken: \(self.refreshToken != nil), retryCount: \(retryCount)")
                }
                
                if self.logLevel >= .errors, let data = data, let errorString = String(data: data, encoding: .utf8) {
                    print("❌ ERROR APIService: 401 Response body: \(errorString)")
                }
                
                // Handle unauthorized based on request type
                if requiresAuth && self.refreshToken != nil && retryCount < 1 {
                    if self.logLevel >= .minimal {
                        print("🔐 AUTH APIService: Attempting to refresh token...")
                    }
                    // Authenticated request with refresh token - try to refresh
                    self.refreshAuthToken { result in
                        switch result {
                        case .success(let newToken):
                            if self.logLevel >= .minimal {
                                print("✅ SUCCESS APIService: Token refreshed successfully")
                            }
                            self.setAuthToken(newToken)
                            // Retry the original request with the new token
                            self.performRequest(
                                endpoint: endpoint,
                                method: method,
                                queryParams: queryParams,
                                body: body,
                                headers: headers,
                                requiresAuth: requiresAuth,
                                retryCount: retryCount + 1,
                                completion: completion
                            )
                        case .failure(let error):
                            if self.logLevel >= .errors {
                                print("❌ ERROR APIService: Token refresh failed: \(error)")
                            }
                            // Clear tokens on refresh failure
                            self.clearTokens()
                            // Notify AuthService that tokens expired
                            AuthService.shared.handleTokenExpired()
                            completion(.failure(.unauthorized))
                        }
                    }
                    return
                } else if requiresAuth {
                    if self.logLevel >= .errors {
                        print("❌ ERROR APIService: No refresh token available, clearing tokens")
                    }
                    // Authenticated request without refresh capability
                    self.clearTokens()
                    // Notify AuthService that tokens expired
                    AuthService.shared.handleTokenExpired()
                    completion(.failure(.unauthorized))
                    return
                } else {
                    if self.logLevel >= .errors {
                        print("❌ ERROR APIService: 401 on non-authenticated request (e.g., login)")
                    }
                    // Non-authenticated request (like login) - preserve error message
                    // Clean up any pending GET request tracking
                    if method == .get {
                        let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                        self.pendingGETRequests.remove(requestKey)
                        self.pendingRequestTimers[requestKey]?.invalidate()
                        self.pendingRequestTimers.removeValue(forKey: requestKey)
                    }
                    completion(.failure(.httpError(401, data)))
                    return
                }
                
            case 400, 403, 404:
                // Log the error response for debugging
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    Logger.error("HTTP \(httpResponse.statusCode) Error Response: \(errorString)")
                }
                
                // Clean up pending request tracking for GET requests
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
                completion(.failure(.httpError(httpResponse.statusCode, data)))
                return
                
            case 429:
                // Rate limit exceeded - implement exponential backoff
                if self.logLevel >= .minimal {
                    Logger.warning("Rate limit exceeded (429) for \(endpoint). Implementing exponential backoff.")
                }
                
                // Check for retry-after header or use a modest default delay
                var delay: TimeInterval = 2.0 // Default 2 second delay
                
                if let retryAfterString = httpResponse.allHeaderFields["Retry-After"] as? String,
                   let retryAfterSeconds = Double(retryAfterString) {
                    delay = retryAfterSeconds
                } else if let resetString = httpResponse.allHeaderFields["X-RateLimit-Reset"] as? String,
                          let resetTimestamp = Double(resetString) {
                    let resetDate = Date(timeIntervalSince1970: resetTimestamp)
                    let calculatedDelay = resetDate.timeIntervalSince(Date())
                    if calculatedDelay > 0 && calculatedDelay < 30.0 { // Only use if reasonable
                        delay = calculatedDelay
                    }
                }
                
                // Cap the delay at a maximum of 30 seconds
                delay = min(delay, 30.0)
                
                // Reduce retry attempts from 3 to 1 to prevent retry storms
                if retryCount < 1 && delay <= 10.0 { // Only retry once and only if delay is reasonable
                    if self.logLevel >= .minimal {
                        Logger.warning("Retrying rate-limited request in \(Int(delay)) seconds (attempt \(retryCount + 1)/1)")
                    }
                    
                    // Clean up pending request tracking for GET requests
                    if method == .get {
                        let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                        self.pendingGETRequests.remove(requestKey)
                        self.pendingRequestTimers[requestKey]?.invalidate()
                        self.pendingRequestTimers.removeValue(forKey: requestKey)
                    }
                    
                    // Retry after delay using performRequest
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.performRequest(
                            endpoint: endpoint,
                            method: method,
                            queryParams: queryParams,
                            body: body,
                            headers: headers,
                            requiresAuth: requiresAuth,
                            retryCount: retryCount + 1,
                            completion: completion
                        )
                    }
                    return
                } else {
                    // No retries for rate limiting or delay too long - fail immediately
                    if self.logLevel >= .minimal {
                        Logger.warning("Rate limited request not retried (retryCount: \(retryCount), delay: \(delay)s) for \(endpoint)")
                    }
                    
                    // Clean up pending request tracking for GET requests
                    if method == .get {
                        let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                        self.pendingGETRequests.remove(requestKey)
                        self.pendingRequestTimers[requestKey]?.invalidate()
                        self.pendingRequestTimers.removeValue(forKey: requestKey)
                    }
                    
                    completion(.failure(.rateLimited(retryAfter: delay)))
                    return
                }
                
            case 500..<600:
                // Log server errors with detailed information
                var errorMessage = "HTTP \(httpResponse.statusCode) Server Error"
                var isFirestoreIndexError = false
                
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    Logger.error("\(errorMessage): \(errorString)")
                    
                    // Check if this is a Firestore index error (should not be retried automatically)
                    if errorString.contains("FAILED_PRECONDITION") || 
                       errorString.contains("requires an index") ||
                       errorString.contains("composite index") {
                        isFirestoreIndexError = true
                        if self.logLevel >= .errors {
                            Logger.error("Detected Firestore index error - will not retry automatically")
                        }
                    }
                } else {
                    Logger.error(errorMessage)
                }
                
                // Clean up pending request tracking for GET requests
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
                // Don't retry Firestore index errors or after multiple attempts
                if !isFirestoreIndexError && retryCount < 1 && httpResponse.statusCode >= 500 && httpResponse.statusCode < 503 {
                    // Retry once for 500-502 errors (server temporarily unavailable)
                    if self.logLevel >= .minimal {
                        Logger.warning("Retrying server error \(httpResponse.statusCode) for \(endpoint) in 2 seconds")
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.performRequest(
                            endpoint: endpoint,
                            method: method,
                            queryParams: queryParams,
                            body: body,
                            headers: headers,
                            requiresAuth: requiresAuth,
                            retryCount: retryCount + 1,
                            completion: completion
                        )
                    }
                    return
                }
                
                completion(.failure(.serverError))
                return
                
            default:
                // Log any other HTTP errors
                if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    Logger.error("HTTP \(httpResponse.statusCode) Unexpected Error: \(errorString)")
                }
                
                // Clean up pending request tracking for GET requests
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
                completion(.failure(.httpError(httpResponse.statusCode, data)))
                return
            }
            
            // Ensure we have data
            guard let data = data else {
                if self.logLevel >= .errors {
                    print("❌ ERROR APIService: No data in response for \(endpoint)")
                }
                completion(.failure(.invalidResponse))
                return
            }
            
            if self.logLevel == .verbose {
                print("📡 API APIService: Response data size: \(data.count) bytes for \(endpoint)")
                
                // Log raw response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📡 API APIService: Raw response preview (first 500 chars): \(String(jsonString.prefix(500)))")
                }
            }
            
            // Parse the data
            do {
                if self.logLevel == .verbose {
                    print("📡 API APIService: Attempting to decode response as \(T.self)")
                }
                
                // Special logging for connections endpoint (only in verbose mode)
                if endpoint == "connections" && self.logLevel == .verbose {
                    print("🔍 APIService: Decoding connections response...")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📡 APIService: Full connections response: \(jsonString)")
                    }
                }
                
                let result = try self.decoder.decode(T.self, from: data)
                if self.logLevel >= .minimal {
                    print("✅ SUCCESS APIService: Successfully decoded response for \(endpoint)")
                }
                
                // Remove from pending requests if it was a GET request
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    // Cancel and remove the timer
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                completion(.success(result))
            } catch {
                Logger.error("Decoding error: \(error.localizedDescription)")
                
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        Logger.debug("Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        Logger.debug("Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        Logger.debug("Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        Logger.debug("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    @unknown default:
                        Logger.debug("Unknown decoding error")
                    }
                }
                
                // Always log the raw JSON data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    Logger.debug("RAW JSON RESPONSE: \(jsonString)")
                } else {
                    Logger.debug("Could not convert data to string")
                }
                
                self.logError(APIError.decodingFailed(error))
                
                // Remove from pending requests if it was a GET request
                if method == .get {
                    let requestKey = self.createRequestKey(endpoint: endpoint, method: method, body: body)
                    self.pendingGETRequests.remove(requestKey)
                    // Cancel and remove the timer
                    self.pendingRequestTimers[requestKey]?.invalidate()
                    self.pendingRequestTimers.removeValue(forKey: requestKey)
                }
                
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
        Logger.debug("REQUEST: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "no_url")")
        
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            Logger.debug("HEADERS: \(headers)")
        }
        
        if let body = request.httpBody, !body.isEmpty {
            logJSON(from: body, prefix: "BODY: ")
        }
    }
    
    private func logResponse(_ response: HTTPURLResponse, data: Data?) {
        let level: LogLevel = response.statusCode >= 400 ? .warning : .debug
        Logger.log(level: level, message: "RESPONSE: \(response.statusCode) - \(response.url?.absoluteString ?? "no_url")")
        
        if response.statusCode >= 400, let data = data, !data.isEmpty {
            logJSON(from: data, prefix: "ERROR BODY: ")
        }
    }
    
    private func logError(_ error: APIError) {
        Logger.error("API ERROR: \(error.localizedDescription)")
    }
    
    private func logJSON(from data: Data, prefix: String = "") {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                Logger.debug("\(prefix)\(prettyString)")
            }
        } catch {
            if let string = String(data: data, encoding: .utf8) {
                Logger.debug("\(prefix)\(string)")
            }
        }
    }
    
    // MARK: - Check-In API
    
    func createCheckIn(_ checkInData: [String: Any], completion: @escaping (Result<CheckIn, APIError>) -> Void) {
        request(
            endpoint: "check-ins",
            method: .post,
            body: checkInData,
            requiresAuth: true
        ) { (result: Result<APIResponse<CheckIn>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getActiveCheckIns(completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        request(
            endpoint: "check-ins/active",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getMyActiveCheckIns(completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        request(
            endpoint: "check-ins/my-active",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func respondToCheckIn(checkInId: String, status: String, completion: @escaping (Result<CheckIn, APIError>) -> Void) {
        request(
            endpoint: "check-ins/\(checkInId)/respond",
            method: .put,
            body: ["status": status],
            requiresAuth: true
        ) { (result: Result<APIResponse<CheckIn>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func endCheckIn(checkInId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "check-ins/\(checkInId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getCheckInsAtPlace(placeId: String, completion: @escaping (Result<[CheckIn], APIError>) -> Void) {
        request(
            endpoint: "check-ins/at-place/\(placeId)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<APIResponse<[CheckIn]>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Videos
    
    func getUserVideos(userId: String, limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        request(
            endpoint: "videos/user/\(userId)\(queryParams)",
            method: .get,
            requiresAuth: false
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func getUserReels(userId: String, limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        request(
            endpoint: "videos/reels/user/\(userId)\(queryParams)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func getReelsFeed(limit: Int = 20, offset: Int = 0, completion: @escaping (Result<VideosResponse, APIError>) -> Void) {
        let queryParams = "?limit=\(limit)&offset=\(offset)"
        request(
            endpoint: "videos/reels/feed\(queryParams)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VideosResponse, APIError>) in
            completion(result)
        }
    }
    
    func deleteVideo(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "videos/\(videoId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func likeReel(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "videos/reels/\(videoId)/like",
            method: .post,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func unlikeReel(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "videos/reels/\(videoId)/like",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func trackReelView(videoId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        request(
            endpoint: "videos/reels/\(videoId)/view",
            method: .post,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Daily Summary
    func fetchDailySummary(completion: @escaping (Result<DailySummaryData, APIError>) -> Void) {
        request(
            endpoint: "users/me/daily-summary",
            method: .get,
            requiresAuth: true
        ) { (result: Result<DailySummaryResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Response Types

struct RefreshTokenResponse: Decodable {
    let success: Bool
    let token: String?
}

// MARK: - Daily Summary Response Types
struct DailySummaryResponse: Decodable {
    let success: Bool
    let data: DailySummaryData
}

struct DailySummaryData: Decodable {
    let date: String
    let newPlaces: Int
    let newPlacesByCategory: [String: Int]
    let newConnections: Int
    let unreadMessages: Int
    let placeComments: Int
    let placeLikes: Int
    let topContributors: [DailySummaryContributor]
    let connectionCount: Int
    let userPlaceCount: Int
}

struct DailySummaryContributor: Decodable {
    let name: String
    let count: Int
}

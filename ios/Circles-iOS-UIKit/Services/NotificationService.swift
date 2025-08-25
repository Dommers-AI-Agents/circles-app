import Foundation
import UserNotifications
import UIKit

class NotificationService {
    static let shared = NotificationService()
    
    private var deviceToken: String?
    
    private init() {}
    
    // MARK: - Device Token Management
    
    func registerDeviceToken(_ token: String) {
        print("🔔 ===== REGISTER DEVICE TOKEN =====")
        print("🔔 Token length: \(token.count)")
        print("🔔 Token preview: \(token.prefix(30))...")
        print("🔔 User logged in: \(AuthService.shared.isLoggedIn)")
        
        self.deviceToken = token
        
        // Save to UserDefaults for persistence
        UserDefaults.standard.set(token, forKey: "FCMToken")
        UserDefaults.standard.synchronize()
        print("🔔 Saved FCM token to UserDefaults")
        
        // Only send to backend if user is logged in
        guard AuthService.shared.isLoggedIn else {
            print("🔔 User not logged in, storing device token for later registration")
            print("🔔 Token will be sent when user logs in")
            return
        }
        
        print("🔔 User is logged in, sending token to backend NOW")
        sendDeviceTokenToBackend(token)
    }
    
    private func sendDeviceTokenToBackend(_ token: String) {
        print("🔔 Sending device token to backend...")
        let body: [String: Any] = [
            "deviceToken": token,
            "platform": "ios",
            "replaceExisting": true  // Tell backend to replace all existing tokens
        ]
        
        APIService.shared.request(
            endpoint: "users/device-token",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                print("🔔 ✅ Device token registered successfully with backend")
                print("🔔 Old tokens have been automatically cleaned up")
            case .failure(let error):
                print("🔔 ❌ Failed to register device token: \(error)")
                print("🔔 Error details: \(error.localizedDescription)")
                
                // Retry once after a delay if it fails
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    print("🔔 Retrying device token registration...")
                    self.sendDeviceTokenToBackend(token)
                }
            }
        }
    }
    
    func unregisterDeviceToken() {
        guard let token = deviceToken else { return }
        
        let body: [String: Any] = [
            "deviceToken": token
        ]
        
        APIService.shared.request(
            endpoint: "users/device-token",
            method: .delete,
            body: body,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                print("🔔 Device token unregistered successfully")
            case .failure(let error):
                print("🔔 Failed to unregister device token: \(error)")
            }
        }
    }
    
    // MARK: - Badge Management
    
    func updateApplicationBadge(count: Int) {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
    
    func clearBadge() {
        updateApplicationBadge(count: 0)
    }
    
    // MARK: - Notification Permissions
    
    func checkNotificationPermissions(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    completion(granted)
                }
            }
        )
    }
    
    // MARK: - Local Notifications (for testing)
    
    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from Circles"
        content.badge = 1
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 Error scheduling test notification: \(error)")
            } else {
                print("🔔 Test notification scheduled")
            }
        }
    }
    
    // MARK: - Handle User Login/Logout
    
    func handleUserLogin() {
        // Send stored device token to backend if available
        if let token = deviceToken {
            sendDeviceTokenToBackend(token)
        } else if let fcmToken = UserDefaults.standard.string(forKey: "FCMToken") {
            // If no device token but FCM token exists, use that
            registerDeviceToken(fcmToken)
        }
    }
    
    func updatePushToken() {
        // Called when FCM token is refreshed
        if let fcmToken = UserDefaults.standard.string(forKey: "FCMToken") {
            registerDeviceToken(fcmToken)
        }
    }
    
    func handleUserLogout() {
        // Unregister device token from backend
        unregisterDeviceToken()
        
        // Clear badge
        clearBadge()
    }
}

// MARK: - Notification Preferences

extension NotificationService {
    struct NotificationPreferences: Codable {
        var newMessages: Bool = true
        var newSuggestions: Bool = true
        var newPlaces: Bool = true
        var connectionRequests: Bool = true
        var circleInvites: Bool = true
        var dailyDigest: Bool = false
        var quietHoursEnabled: Bool = false
        var quietHoursStart: String = "22:00" // 10 PM
        var quietHoursEnd: String = "08:00"   // 8 AM
    }
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences, completion: @escaping (Result<Void, Error>) -> Void) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(preferences),
              let prefsDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completion(.failure(APIError.invalidResponse))
            return
        }
        
        let body: [String: Any] = [
            "notificationPreferences": prefsDict
        ]
        
        APIService.shared.request(
            endpoint: "users/notification-preferences",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - In-App Notifications
    
    func getNotifications(limit: Int = 50, offset: Int = 0, archived: Bool = false, completion: @escaping (Result<NotificationsResponse, Error>) -> Void) {
        print("🚀 NotificationService: getNotifications called")
        print("🚀 NotificationService: limit: \(limit), offset: \(offset), archived: \(archived)")
        
        let queryParams: [String: String] = [
            "limit": "\(limit)",
            "offset": "\(offset)",
            "archived": archived ? "true" : "false"
        ]
        
        print("🚀 NotificationService: Making API request to 'notifications' endpoint")
        
        APIService.shared.request(
            endpoint: "notifications",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { (result: Result<NotificationsResponse, APIError>) in
            print("📡 NotificationService: API callback received")
            
            switch result {
            case .success(let response):
                print("✅ NotificationService: Successfully fetched notifications")
                print("✅ NotificationService: Notification count: \(response.notifications.count)")
                completion(.success(response))
            case .failure(let error):
                print("❌ NotificationService: Failed to fetch notifications: \(error)")
                print("❌ NotificationService: Error type: \(type(of: error))")
                completion(.failure(error))
            }
        }
    }
    
    func markNotificationAsRead(notificationId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/\(notificationId)/read",
            method: .put,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getUnreadNotificationCount(completion: @escaping (Result<Int, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/unread-count",
            method: .get,
            requiresAuth: true
        ) { (result: Result<NotificationUnreadCountResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.unreadCount))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func markAllNotificationsAsRead(completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/read-all",
            method: .put,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func archiveAllNotifications(completion: @escaping (Result<String, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/archive-all",
            method: .put,
            requiresAuth: true
        ) { (result: Result<NotificationActionResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.message))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteNotification(notificationId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/\(notificationId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func clearArchivedNotifications(completion: @escaping (Result<String, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "notifications/archived",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<NotificationActionResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.message))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Response Models

private struct NotificationUnreadCountResponse: Codable {
    let success: Bool
    let unreadCount: Int
}

private struct NotificationActionResponse: Codable {
    let success: Bool
    let message: String
}
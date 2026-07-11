import Foundation
import LocalAuthentication

/// Service for handling biometric authentication (Face ID / Touch ID)
class BiometricAuthService {
    static let shared = BiometricAuthService()

    private init() {}

    // MARK: - Biometric Availability

    enum BiometricType {
        case none
        case touchID
        case faceID

        var displayName: String {
            switch self {
            case .none: return "Biometric"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            }
        }
    }

    /// Check if biometric authentication is available on this device
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        if #available(iOS 11.0, *) {
            switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            case .none:
                return .none
            @unknown default:
                return .none
            }
        } else {
            // iOS 10 and below only had Touch ID
            return .touchID
        }
    }

    /// Check if biometric authentication is available
    var isBiometricAvailable: Bool {
        return biometricType() != .none
    }

    // MARK: - Biometric Authentication

    /// Authenticate user with biometrics
    /// - Parameters:
    ///   - reason: The reason to show to the user
    ///   - completion: Called with success/failure
    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }

        // Perform biometric authentication
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    /// Authenticate with biometrics or device passcode fallback
    func authenticateWithBiometricsOrPasscode(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        // Check if device authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false, error)
            return
        }

        // Perform authentication with fallback to passcode
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    // MARK: - User Preferences

    private let biometricLoginEnabledKey = "biometricLoginEnabled"

    /// Check if user has enabled biometric login
    var isBiometricLoginEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: biometricLoginEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: biometricLoginEnabledKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// Enable biometric login for the user
    func enableBiometricLogin() {
        isBiometricLoginEnabled = true
        print("🔐 BiometricAuthService: Biometric login enabled")
    }

    /// Disable biometric login for the user
    func disableBiometricLogin() {
        isBiometricLoginEnabled = false
        // Also clear saved credentials when disabling
        KeychainService.shared.clearSavedCredentials()
        print("🔐 BiometricAuthService: Biometric login disabled and credentials cleared")
    }

    // MARK: - Helper Methods

    /// Get a user-friendly prompt for biometric authentication
    func getBiometricPrompt(action: String = "sign in") -> String {
        let type = biometricType()
        return "Use \(type.displayName) to \(action)"
    }
}

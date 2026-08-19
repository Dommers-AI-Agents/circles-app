import Foundation
import UIKit
import AuthenticationServices

/// Passkey (WebAuthn) registration and sign-in.
///
/// Modeled on SocialAuthService's retention pattern (ASAuthorizationController
/// parked on AppDelegate so it survives the async ceremony) but deliberately a
/// SEPARATE service — SocialAuthService's shared completionHandler/nonce state
/// would collide if an Apple sign-in and a passkey ceremony interleaved.
///
/// The relying party is favcircles.com — permanent once users hold
/// credentials, and it must match the backend's WEBAUTHN_RP_ID and the
/// webcredentials entitlement.
final class PasskeyAuthService: NSObject {

    static let shared = PasskeyAuthService()
    static let relyingPartyIdentifier = "favcircles.com"

    enum PasskeyError: LocalizedError {
        case canceled          // user dismissed the sheet — callers fall back silently
        case noCredential
        case badServerData

        var errorDescription: String? {
            switch self {
            case .canceled: return "Sign in was canceled"
            case .noCredential: return "No passkey available on this device"
            case .badServerData: return "Could not start the passkey ceremony"
            }
        }
    }

    private enum Pending {
        case registration(email: String)
        case assertion
        case addPasskey // enroll a passkey on an already-signed-in account
    }

    private var pending: Pending?
    private var completionHandler: ((Result<User, Error>) -> Void)?
    private var addCompletion: ((Result<Void, Error>) -> Void)?
    private weak var presentationAnchor: ASPresentationAnchor?
    private var authorizationController: ASAuthorizationController?

    // MARK: - Public API

    /// Creates a passkey for a NEW account (email must not exist server-side —
    /// the backend 409s otherwise, which AuthService maps to .accountExists).
    func registerPasskey(email: String, presentationAnchor: ASPresentationAnchor?, completion: @escaping (Result<User, Error>) -> Void) {
        self.presentationAnchor = presentationAnchor
        self.completionHandler = completion

        APIService.shared.request(
            endpoint: "auth/passkey/register-options",
            method: .post,
            body: ["email": email],
            requiresAuth: false
        ) { [weak self] (result: Result<PasskeyOptionsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    guard let challenge = Data(base64URLEncoded: response.options.challenge),
                          let userIDString = response.options.user?.id,
                          let userID = Data(base64URLEncoded: userIDString) else {
                        self.finish(.failure(PasskeyError.badServerData))
                        return
                    }
                    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                        relyingPartyIdentifier: Self.relyingPartyIdentifier)
                    let request = provider.createCredentialRegistrationRequest(
                        challenge: challenge, name: email, userID: userID)
                    self.pending = .registration(email: email)
                    self.perform(requests: [request])
                case .failure(let error):
                    self.finish(.failure(AuthService.shared.mapPasskeyAPIError(error)))
                }
            }
        }
    }

    /// Signs in with an existing passkey (discoverable credential). With
    /// preferImmediate, a device holding no credential fails fast with
    /// .canceled instead of showing a qr/other-device sheet — used by the
    /// automatic paths so password fallback appears without friction.
    func signInWithPasskey(presentationAnchor: ASPresentationAnchor?, preferImmediate: Bool = false, completion: @escaping (Result<User, Error>) -> Void) {
        self.presentationAnchor = presentationAnchor
        self.completionHandler = completion

        APIService.shared.request(
            endpoint: "auth/passkey/login-options",
            method: .post,
            body: [:],
            requiresAuth: false
        ) { [weak self] (result: Result<PasskeyOptionsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    guard let challenge = Data(base64URLEncoded: response.options.challenge) else {
                        self.finish(.failure(PasskeyError.badServerData))
                        return
                    }
                    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                        relyingPartyIdentifier: Self.relyingPartyIdentifier)
                    let request = provider.createCredentialAssertionRequest(challenge: challenge)
                    self.pending = .assertion
                    self.perform(requests: [request], preferImmediate: preferImmediate)
                case .failure(let error):
                    self.finish(.failure(AuthService.shared.mapPasskeyAPIError(error)))
                }
            }
        }
    }

    /// Enrolls a passkey on the CURRENT signed-in account (Settings flow). Unlike
    /// registerPasskey this hits the authenticated add-options/add-verify
    /// endpoints — no new account, no session minted. `accountName` is just the
    /// label the system shows while saving the passkey (their email/name).
    func addPasskeyForCurrentUser(accountName: String, presentationAnchor: ASPresentationAnchor?, completion: @escaping (Result<Void, Error>) -> Void) {
        self.presentationAnchor = presentationAnchor
        self.addCompletion = completion

        APIService.shared.request(
            endpoint: "auth/passkey/add-options",
            method: .post,
            body: [:],
            requiresAuth: true
        ) { [weak self] (result: Result<PasskeyOptionsResponse, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    guard let challenge = Data(base64URLEncoded: response.options.challenge),
                          let userIDString = response.options.user?.id,
                          let userID = Data(base64URLEncoded: userIDString) else {
                        self.finishAdd(.failure(PasskeyError.badServerData))
                        return
                    }
                    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
                        relyingPartyIdentifier: Self.relyingPartyIdentifier)
                    let request = provider.createCredentialRegistrationRequest(
                        challenge: challenge, name: accountName, userID: userID)
                    self.pending = .addPasskey
                    self.perform(requests: [request])
                case .failure(let error):
                    self.finishAdd(.failure(AuthService.shared.mapPasskeyAPIError(error)))
                }
            }
        }
    }

    private func finishAdd(_ result: Result<Void, Error>) {
        let handler = addCompletion
        addCompletion = nil
        pending = nil
        authorizationController = nil
        (UIApplication.shared.delegate as? AppDelegate)?.authorizationController = nil
        handler?(result)
    }

    // MARK: - Ceremony plumbing

    private func perform(requests: [ASAuthorizationRequest], preferImmediate: Bool = false) {
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        // Same deallocation dodge SocialAuthService uses
        (UIApplication.shared.delegate as? AppDelegate)?.authorizationController = controller
        if preferImmediate {
            controller.performRequests(options: .preferImmediatelyAvailableCredentials)
        } else {
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<User, Error>) {
        let handler = completionHandler
        completionHandler = nil
        pending = nil
        authorizationController = nil
        (UIApplication.shared.delegate as? AppDelegate)?.authorizationController = nil
        handler?(result)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension PasskeyAuthService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {

        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            // Enrolling a passkey on an already-authenticated account
            if case .addPasskey = pending {
                guard let attestation = registration.rawAttestationObject else {
                    finishAdd(.failure(PasskeyError.noCredential))
                    return
                }
                let body: [String: Any] = [
                    "deviceName": UIDevice.current.model,
                    "credential": [
                        "id": registration.credentialID.base64URLEncodedString(),
                        "rawId": registration.credentialID.base64URLEncodedString(),
                        "type": "public-key",
                        "response": [
                            "clientDataJSON": registration.rawClientDataJSON.base64URLEncodedString(),
                            "attestationObject": attestation.base64URLEncodedString()
                        ],
                        "clientExtensionResults": [String: String]()
                    ]
                ]
                let handler = addCompletion
                addCompletion = nil
                pending = nil
                APIService.shared.request(
                    endpoint: "auth/passkey/add-verify",
                    method: .post,
                    body: body,
                    requiresAuth: true
                ) { (result: Result<PasskeySimpleResponse, APIError>) in
                    switch result {
                    case .success: handler?(.success(()))
                    case .failure(let error): handler?(.failure(error))
                    }
                }
                return
            }

            guard case let .registration(email) = pending,
                  let attestation = registration.rawAttestationObject else {
                finish(.failure(PasskeyError.noCredential))
                return
            }
            let body: [String: Any] = [
                "email": email,
                "deviceName": UIDevice.current.model,
                "credential": [
                    "id": registration.credentialID.base64URLEncodedString(),
                    "rawId": registration.credentialID.base64URLEncodedString(),
                    "type": "public-key",
                    "response": [
                        "clientDataJSON": registration.rawClientDataJSON.base64URLEncodedString(),
                        "attestationObject": attestation.base64URLEncodedString()
                    ],
                    "clientExtensionResults": [String: String]()
                ]
            ]
            let handler = completionHandler
            completionHandler = nil
            pending = nil
            AuthService.shared.completePasskeyRegistration(email: email, body: body) { result in
                handler?(result)
            }

        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            let body: [String: Any] = [
                "credential": [
                    "id": assertion.credentialID.base64URLEncodedString(),
                    "rawId": assertion.credentialID.base64URLEncodedString(),
                    "type": "public-key",
                    "response": [
                        "clientDataJSON": assertion.rawClientDataJSON.base64URLEncodedString(),
                        "authenticatorData": assertion.rawAuthenticatorData.base64URLEncodedString(),
                        "signature": assertion.signature.base64URLEncodedString(),
                        "userHandle": assertion.userID.base64URLEncodedString()
                    ],
                    "clientExtensionResults": [String: String]()
                ]
            ]
            let handler = completionHandler
            completionHandler = nil
            pending = nil
            AuthService.shared.completePasskeyLogin(body: body) { result in
                handler?(result)
            }

        default:
            finish(.failure(PasskeyError.noCredential))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let isCancel = (error as? ASAuthorizationError)?.code == .canceled
        let resolved: Error = isCancel ? PasskeyError.canceled : error
        if !isCancel {
            // ASAuthorizationError.failed (1004) at this point usually means
            // the webcredentials AASA wasn't reachable for the RP
            Logger.debug("🔑 Passkey ceremony failed: \(error)")
        }
        // Route to whichever flow is in flight (enrollment vs sign-in/registration)
        if addCompletion != nil {
            finishAdd(.failure(resolved))
        } else {
            finish(.failure(resolved))
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension PasskeyAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let anchor = presentationAnchor { return anchor }
        // Fall back to the key window (same approach as SocialAuthService)
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}

// MARK: - Response models

struct PasskeyOptionsResponse: Decodable {
    struct Options: Decodable {
        struct PasskeyUser: Decodable {
            let id: String
        }
        let challenge: String
        let user: PasskeyUser? // present on registration options only
    }
    let success: Bool
    let options: Options
}

struct PasskeySimpleResponse: Decodable {
    let success: Bool
    let message: String?
}
